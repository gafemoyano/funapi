# frozen_string_literal: true

require 'async'
require 'async/http/server'
require 'async/http/endpoint'
require 'protocol/rack'
require 'dry-container'
require_relative 'router'
require_relative 'async'
require_relative 'exceptions'
require_relative 'schema'
require_relative 'depends'
require_relative 'dependency_wrapper'
require_relative 'background_tasks'
require_relative 'template_response'
require_relative 'openapi/spec_generator'

module FunApi
  class App
    attr_reader :openapi_config, :container

    def initialize(title: 'FunApi Application', version: '1.0.0', description: '')
      @router = Router.new
      @middleware_stack = []
      @container = Dry::Container.new
      @openapi_config = {
        title: title,
        version: version,
        description: description
      }

      yield self if block_given?

      register_openapi_routes
    end

    def register(key, &block)
      @container.register(key) do
        if block.arity == 0
          result = block.call
          if result.is_a?(Array) && result.length == 2 && result[1].respond_to?(:call)
            ManagedDependency.new(result[0], result[1])
          else
            SimpleDependency.new(result)
          end
        else
          BlockDependency.new(block)
        end
      end
    end

    def resolve(key)
      @container.resolve(key)
    end

    def get(path, query: nil, response_schema: nil, depends: nil, &blk)
      add_route('GET', path, query: query, response_schema: response_schema, depends: depends, &blk)
    end

    def post(path, body: nil, query: nil, response_schema: nil, depends: nil, &blk)
      add_route('POST', path, body: body, query: query, response_schema: response_schema, depends: depends, &blk)
    end

    def put(path, body: nil, query: nil, response_schema: nil, depends: nil, &blk)
      add_route('PUT', path, body: body, query: query, response_schema: response_schema, depends: depends, &blk)
    end

    def patch(path, body: nil, query: nil, response_schema: nil, depends: nil, &blk)
      add_route('PATCH', path, body: body, query: query, response_schema: response_schema, depends: depends, &blk)
    end

    def delete(path, query: nil, response_schema: nil, depends: nil, &blk)
      add_route('DELETE', path, query: query, response_schema: response_schema, depends: depends, &blk)
    end

    def use(middleware, *args, &block)
      @middleware_stack << [middleware, args, block]
      self
    end

    def add_cors(allow_origins: ['*'], allow_methods: ['*'], allow_headers: ['*'],
                 expose_headers: [], max_age: 600, allow_credentials: false)
      require_relative 'middleware/cors'
      use FunApi::Middleware::Cors,
          allow_origins: allow_origins,
          allow_methods: allow_methods,
          allow_headers: allow_headers,
          expose_headers: expose_headers,
          max_age: max_age,
          allow_credentials: allow_credentials
    end

    def add_trusted_host(allowed_hosts:)
      require_relative 'middleware/trusted_host'
      use FunApi::Middleware::TrustedHost, allowed_hosts: allowed_hosts
    end

    def add_request_logger(logger: nil, level: :info)
      require_relative 'middleware/request_logger'
      use FunApi::Middleware::RequestLogger, logger: logger, level: level
    end

    def add_gzip
      use Rack::Deflater, if: lambda { |_env, _status, headers, _body|
        headers['content-type']&.start_with?('application/json')
      }
    end

    def call(env)
      app = build_middleware_chain
      app.call(env)
    end

    # Run the app with Falcon
    # def run!(host: 'localhost', port: 9292, **options)
    #   puts "🚀 FunAPI server starting on http://#{host}:#{port}"
    #   puts "📚 Environment: #{options[:environment] || 'development'}"
    #   puts '⚡ Press Ctrl+C to stop'
    #   puts

    #   rack_app = self

    #   Async do |task|
    #     # Create endpoint
    #     endpoint = Async::HTTP::Endpoint.parse(
    #       "http://#{host}:#{port}",
    #       reuse_address: true
    #     )

    #     # Wrap Rack app for async-http
    #     app = Protocol::Rack::Adapter.new(rack_app)

    #     # Create server
    #     server = Async::HTTP::Server.new(app, endpoint)

    #     # Handle graceful shutdown
    #     Signal.trap('INT') do
    #       puts "\n👋 Shutting down gracefully..."
    #       task.stop
    #     end

    #     Signal.trap('TERM') do
    #       puts "\n👋 Shutting down gracefully..."
    #       task.stop
    #     end

    #     # Run the server
    #     server.run
    #   end
    # end

    private

    def add_route(verb, path, body: nil, query: nil, response_schema: nil, depends: nil, &blk)
      metadata = {
        body_schema: body,
        query_schema: query,
        response_schema: response_schema,
        dependencies: normalize_dependencies(depends)
      }

      @router.add(verb, path, metadata: metadata) do |req, path_params|
        handle_async_route(req, path_params, body, query, response_schema, metadata[:dependencies], &blk)
      end
    end

    def handle_async_route(req, path_params, body_schema, query_schema, response_schema, dependencies, &blk)
      current_task = Async::Task.current
      Fiber[:async_task] = current_task
      cleanup_objects = []
      background_tasks = BackgroundTasks.new(current_task)

      begin
        input = {
          path: path_params,
          query: req.params,
          body: parse_body(req)
        }

        input[:query] = Schema.validate(query_schema, input[:query], location: 'query') if query_schema

        input[:body] = Schema.validate(body_schema, input[:body], location: 'body') if body_schema

        resolved_deps, cleanup_objects = resolve_dependencies(dependencies, input, req, current_task)

        handler_params = blk.parameters.select { |type, _name| %i[keyreq key].include?(type) }.map(&:last)
        resolved_deps[:background] = background_tasks if handler_params.include?(:background)

        payload, status = blk.call(input, req, current_task, **resolved_deps)

        if payload.is_a?(TemplateResponse)
          background_tasks.execute
          return payload.to_response
        end

        payload = normalize_payload(payload)

        payload = Schema.validate_response(response_schema, payload) if response_schema

        background_tasks.execute

        [
          status || 200,
          {"content-type" => "application/json"},
          [JSON.dump(payload)]
        ]
      rescue ValidationError => e
        e.to_response
      rescue HTTPException => e
        e.to_response
      ensure
        cleanup_objects.each do |wrapper|
          wrapper.cleanup
        rescue StandardError => e
          warn "Dependency cleanup failed: #{e.message}"
        end
        Fiber[:async_task] = nil
      end
    end

    def build_middleware_chain
      app = @router

      @middleware_stack.reverse_each do |middleware, args, block|
        app = if args.length == 1 && args.first.is_a?(Hash) && args.first.keys.all? { |k| k.is_a?(Symbol) }
                middleware.new(app, **args.first, &block)
              else
                middleware.new(app, *args, &block)
              end
      end

      app
    end

    # def handle_request(env)
    #   request = Rack::Request.new(env)
    #   route = @router.match(request.request_method, request.path_info)
    #
    #   return [404, {}, ['Not Found']] unless route
    #
    #   # Build input from request
    #   input = build_input(request, route.path_params)
    #
    #   # Validate with contract if present
    #   if route.contract
    #     result = route.contract.call(input)
    #
    #     if result.failure?
    #       return [422,
    #               { 'content-type' => 'application/json' },
    #               [JSON.generate(errors: result.errors.to_h)]]
    #     end
    #
    #     input = result.to_h
    #   end
    #
    #   # Call handler - returns [body, status] or [body, status, headers]
    #   response = route.handler.call(input, request)
    #   normalize_response(response)
    # end
    #
    # def build_input(request, path_params)
    #   {
    #     path: path_params,
    #     query: request.GET, # Query params only
    #     body: parse_body(request),
    #     headers: extract_headers(request.env)
    #   }
    # end
    # Optional body parsing helper

    def parse_body(request)
      return nil unless request.body

      content_type = request.content_type
      body = request.body.read
      request.body.rewind

      case content_type
      when %r{application/json}
        begin
          JSON.parse(body, symbolize_names: true)
        rescue StandardError
          {}
        end
      when %r{application/x-www-form-urlencoded}
        request.POST
      else
        body
      end
    end

    def extract_headers(env)
      env.select { |k, _v| k.start_with?('HTTP_') }
         .transform_keys { |k| k.sub('HTTP_', '').downcase }
    end

    def normalize_response(response)
      case response
      in [body, status, headers]
        [status, headers, [serialize_body(body)]]
      in [body, status]
        [status, default_headers(body), [serialize_body(body)]]
      in [body]
        [200, default_headers(body), [serialize_body(body)]]
      else
        [200, default_headers(response), [serialize_body(response)]]
      end
    end

    def serialize_body(body)
      case body
      when String then body
      when Hash, Array then JSON.generate(body)
      else body.to_s
      end
    end

    def default_headers(body)
      case body
      when Hash, Array
        { 'content-type' => 'application/json' }
      else
        { 'content-type' => 'text/plain' }
      end
    end

    def normalize_payload(payload)
      return payload unless payload

      if payload.is_a?(Array)
        payload.map { |item| normalize_single_payload(item) }
      else
        normalize_single_payload(payload)
      end
    end

    def normalize_single_payload(item)
      if item.respond_to?(:to_h) && item.class.name&.include?('Dry::Schema::Result')
        item.to_h
      else
        item
      end
    end

    def normalize_dependencies(depends)
      return {} if depends.nil?

      normalized = {}

      case depends
      when Array
        depends.each do |dep_name|
          sym = dep_name.to_sym
          normalized[sym] = { type: :container, key: sym }
        end
      when Hash
        depends.each do |key, value|
          normalized[key.to_sym] = case value
                                   when Depends
                                     { type: :depends, callable: value }
                                   when Symbol
                                     { type: :container, key: value }
                                   when Proc, Method
                                     { type: :depends, callable: Depends.new(value) }
                                   when nil
                                     { type: :container, key: key.to_sym }
                                   else
                                     unless value.respond_to?(:call)
                                       raise ArgumentError, "Dependency must be callable, Depends, Symbol, or nil for #{key}"
                                     end

                                     { type: :depends, callable: Depends.new(value) }

                                   end
        end
      else
        raise ArgumentError, 'depends must be an Array or Hash'
      end

      normalized
    end

    def resolve_dependencies(dependencies, input, req, task)
      return [{}, []] if dependencies.nil? || dependencies.empty?

      cache = {}
      cleanup_objects = []

      context = {
        input: input,
        req: req,
        task: task,
        container: @container
      }

      resolved = dependencies.transform_values do |dep_info|
        case dep_info[:type]
        when :container
          cache_key = "container:#{dep_info[:key]}"
          if cache.key?(cache_key)
            cache[cache_key][:resource]
          else
            dependency_wrapper = @container.resolve(dep_info[:key])
            resource = dependency_wrapper.call
            cache[cache_key] = { resource: resource, wrapper: dependency_wrapper }
            cleanup_objects << dependency_wrapper
            resource
          end
        when :depends
          result, cleanup = dep_info[:callable].call(context, cache)
          cleanup_objects << ManagedDependency.new(result, cleanup) if cleanup
          result
        end
      end

      [resolved, cleanup_objects]
    rescue StandardError => e
      raise HTTPException.new(
        status_code: 500,
        detail: "Dependency resolution failed: #{e.message}"
      )
    end

    def register_openapi_routes
      @router.add('GET', '/openapi.json', metadata: { internal: true }) do |_req, _path_params|
        spec = generate_openapi_spec
        [
          200,
          { 'content-type' => 'application/json' },
          [JSON.dump(spec)]
        ]
      end

      @router.add('GET', '/docs', metadata: { internal: true }) do |_req, _path_params|
        html = swagger_ui_html
        [
          200,
          { 'content-type' => 'text/html' },
          [html]
        ]
      end
    end

    def generate_openapi_spec
      generator = OpenAPI::SpecGenerator.new(@router.routes, info: @openapi_config)
      generator.generate
    end

    def swagger_ui_html
      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <base href="/" />
          <title>#{@openapi_config[:title]} - Swagger UI</title>
          <link rel="stylesheet" type="text/css" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css" />
          <style>
            html { box-sizing: border-box; overflow: -moz-scrollbars-vertical; overflow-y: scroll; }
            *, *:before, *:after { box-sizing: inherit; }
            body { margin:0; padding:0; }
          </style>
        </head>
        <body>
          <div id="swagger-ui"></div>
          <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
          <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-standalone-preset.js"></script>
          <script>
            window.onload = function() {
              window.ui = SwaggerUIBundle({
                url: "/openapi.json",
                dom_id: '#swagger-ui',
                deepLinking: true,
                presets: [
                  SwaggerUIBundle.presets.apis,
                  SwaggerUIStandalonePreset
                ],
                plugins: [
                  SwaggerUIBundle.plugins.DownloadUrl
                ],
                layout: "StandaloneLayout"
              });
            };
          </script>
        </body>
        </html>
      HTML
    end
  end
end
