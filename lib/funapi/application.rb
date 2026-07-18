# frozen_string_literal: true

require "async"
require "async/http/server"
require "async/http/endpoint"
require "protocol/rack"
require "dry-container"
require_relative "router"
require_relative "route_set"
require_relative "exceptions"
require_relative "schema"
require_relative "model"
require_relative "depends"
require_relative "dependency_wrapper"
require_relative "background_tasks"
require_relative "template_response"
require_relative "streaming_response"
require_relative "openapi/spec_generator"

module FunApi
  class App
    attr_reader :openapi_config, :container, :startup_hooks, :shutdown_hooks

    def initialize(title: "FunApi Application", version: "1.0.0", description: "")
      @route_set = RouteSet.new
      @middleware_stack = []
      @container = Dry::Container.new
      @startup_hooks = []
      @shutdown_hooks = []
      @exception_handlers = {}
      @dependency_overrides = {}
      @openapi_config = {
        title: title,
        version: version,
        description: description
      }

      yield self if block_given?

      register_openapi_routes
    end

    def on_startup(&block)
      raise ArgumentError, "on_startup requires a block" unless block_given?

      @startup_hooks << block
      self
    end

    def on_shutdown(&block)
      raise ArgumentError, "on_shutdown requires a block" unless block_given?

      @shutdown_hooks << block
      self
    end

    def run_startup_hooks
      @startup_hooks.each(&:call)
    end

    def run_shutdown_hooks
      @shutdown_hooks.each do |hook|
        hook.call
      rescue => e
        warn "Shutdown hook failed: #{e.message}"
      end
    end

    def exception_handler(exception_class, &block)
      raise ArgumentError, "exception_handler requires a block" unless block_given?

      @exception_handlers[exception_class] = block
      self
    end

    def register(key, &block)
      provider = block_provider(block)
      @container.register(key) do
        BlockDependency.new(provider)
      end
    end

    def resolve(key)
      @container.resolve(key)
    end

    def override_dependency(key, replacement)
      @dependency_overrides[key.to_sym] = replacement
      self
    end

    def reset_overrides!
      @dependency_overrides.clear
      self
    end

    def get(route_path, path: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      add_route("GET", route_path, path: path, query: query, response_schema: response_schema, depends: depends, tags: tags, &blk)
    end

    def post(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      add_route("POST", route_path, path: path, body: body, query: query, response_schema: response_schema, depends: depends, tags: tags, &blk)
    end

    def put(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      add_route("PUT", route_path, path: path, body: body, query: query, response_schema: response_schema, depends: depends, tags: tags, &blk)
    end

    def patch(route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      add_route("PATCH", route_path, path: path, body: body, query: query, response_schema: response_schema, depends: depends, tags: tags, &blk)
    end

    def delete(route_path, path: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      add_route("DELETE", route_path, path: path, query: query, response_schema: response_schema, depends: depends, tags: tags, &blk)
    end

    def websocket(route_path, path: nil, query: nil, &blk)
      require_relative "websocket"

      metadata = {
        path_schema: path,
        query_schema: query,
        tags: [],
        dependencies: {},
        websocket: true
      }

      @route_set.add("GET", route_path, metadata: metadata) do |req, path_params|
        handle_websocket_route(req, path_params, path, query, &blk)
      end
    end

    def include_router(router, prefix: "", depends: {}, tags: [])
      router.each_route(
        inherited_prefix: normalize_router_prefix(prefix),
        inherited_depends: Router.coerce_depends(depends),
        inherited_tags: Array(tags)
      ) do |verb:, path:, path_schema:, body_schema:, query_schema:, response_schema:, depends:, tags:, block:|
        add_route(verb, path, path: path_schema, body: body_schema, query: query_schema, response_schema: response_schema, depends: depends, tags: tags, &block)
      end
      self
    end

    def mount(prefix, rack_app)
      @route_set.mount(prefix, rack_app)
      self
    end

    def use(middleware, *args, &block)
      if @middleware_chain
        raise "Cannot add middleware after the application has started handling requests"
      end

      @middleware_stack << [middleware, args, block]
      self
    end

    def add_cors(allow_origins: ["*"], allow_methods: ["*"], allow_headers: ["*"],
      expose_headers: [], max_age: 600, allow_credentials: false)
      require_relative "middleware/cors"
      use FunApi::Middleware::Cors,
        allow_origins: allow_origins,
        allow_methods: allow_methods,
        allow_headers: allow_headers,
        expose_headers: expose_headers,
        max_age: max_age,
        allow_credentials: allow_credentials
    end

    def add_trusted_host(allowed_hosts:)
      require_relative "middleware/trusted_host"
      use FunApi::Middleware::TrustedHost, allowed_hosts: allowed_hosts
    end

    def add_request_logger(logger: nil, level: :info)
      require_relative "middleware/request_logger"
      use FunApi::Middleware::RequestLogger, logger: logger, level: level
    end

    def add_gzip
      use Rack::Deflater, if: lambda { |_env, _status, headers, _body|
        headers["content-type"]&.start_with?("application/json")
      }
    end

    def call(env)
      @middleware_chain ||= build_middleware_chain
      @middleware_chain.call(env)
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

    def block_provider(block)
      return block if block.arity != 0

      proc do |provide|
        result = block.call
        if result.is_a?(Array) && result.length == 2 && result[1].respond_to?(:call)
          resource, cleanup = result
          begin
            provide.call(resource)
          ensure
            cleanup.call
          end
        else
          provide.call(result)
        end
      end
    end

    def normalize_router_prefix(prefix)
      value = prefix.to_s
      return "" if value.empty? || value == "/"

      value = "/#{value}" unless value.start_with?("/")
      value.chomp("/")
    end

    def add_route(verb, route_path, path: nil, body: nil, query: nil, response_schema: nil, depends: nil, tags: nil, &blk)
      metadata = {
        path_schema: path,
        body_schema: body,
        query_schema: query,
        response_schema: response_schema,
        tags: Array(tags),
        dependencies: normalize_dependencies(depends)
      }

      @route_set.add(verb, route_path, metadata: metadata) do |req, path_params|
        handle_async_route(req, path_params, path, body, query, response_schema, metadata[:dependencies], &blk)
      end
    end

    def handle_async_route(req, path_params, path_schema, body_schema, query_schema, response_schema, dependencies, &blk)
      current_task = Async::Task.current
      Fiber[:async_task] = current_task
      cleanup_objects = []
      background_tasks = BackgroundTasks.new(current_task)
      deferred = false

      begin
        input = {
          path: path_params.transform_keys(&:to_sym),
          query: req.params,
          body: parse_body(req),
          headers: extract_headers(req.env)
        }

        input[:path] = Schema.validate(path_schema, input[:path], location: "path") if path_schema

        input[:query] = Schema.validate(query_schema, input[:query], location: "query") if query_schema

        input[:body] = Schema.validate(body_schema, input[:body], location: "body") if body_schema

        resolved_deps, cleanup_objects = resolve_dependencies(dependencies, input, req, current_task)

        # standard:disable Style/HashSlice
        handler_params = blk.parameters.select { |type, _| %i[keyreq key].include?(type) }.map(&:last)
        # standard:enable Style/HashSlice
        resolved_deps[:background] = background_tasks if handler_params.include?(:background)

        payload, status = blk.call(input, req, current_task, **resolved_deps)

        response = if payload.is_a?(StreamingResponse)
          payload.to_response
        elsif payload.is_a?(TemplateResponse)
          payload.to_response
        else
          payload = normalize_payload(payload)
          payload = Schema.validate_response(response_schema, payload) if response_schema

          [
            status || 200,
            {"content-type" => "application/json"},
            [JSON.dump(payload)]
          ]
        end

        unless background_tasks.empty? && cleanup_objects.empty?
          schedule_post_response(current_task, background_tasks, cleanup_objects)
          deferred = true
        end

        response
      rescue => e
        handle_exception(e, req)
      ensure
        run_cleanup(cleanup_objects) unless deferred
        Fiber[:async_task] = nil
      end
    end

    def handle_websocket_route(req, path_params, path_schema, query_schema, &blk)
      Fiber[:async_task] = Async::Task.current

      input = {
        path: path_params.transform_keys(&:to_sym),
        query: req.GET,
        headers: extract_headers(req.env)
      }

      input[:path] = Schema.validate(path_schema, input[:path], location: "path") if path_schema
      input[:query] = Schema.validate(query_schema, input[:query], location: "query") if query_schema

      response = FunApi::WebSocket.open(req.env) do |connection|
        blk.call(connection, input)
      end

      response || FunApi::WebSocket.upgrade_required
    rescue => e
      handle_exception(e, req)
    ensure
      Fiber[:async_task] = nil
    end

    def schedule_post_response(task, background_tasks, cleanup_objects)
      task.async do |post_task|
        sleep(0)
        background_tasks.execute
      ensure
        run_cleanup(cleanup_objects)
      end
    end

    def run_cleanup(cleanup_objects)
      cleanup_objects.each do |wrapper|
        wrapper.cleanup
      rescue => e
        warn "Dependency cleanup failed: #{e.message}"
      end
    end

    def handle_exception(error, req)
      handler = find_exception_handler(error.class)

      if handler
        payload, status = handler.call(error, req)
        return [
          status || 500,
          {"content-type" => "application/json"},
          [JSON.dump(normalize_payload(payload))]
        ]
      end

      return error.to_response if error.is_a?(HTTPException)

      internal_server_error_response(error, req)
    end

    def find_exception_handler(error_class)
      error_class.ancestors.each do |ancestor|
        handler = @exception_handlers[ancestor]
        return handler if handler
      end
      nil
    end

    def internal_server_error_response(error, req = nil)
      unless development_env?
        return [
          500,
          {"content-type" => "application/json"},
          [JSON.dump(detail: "Internal Server Error")]
        ]
      end

      if req && prefers_html?(req)
        return [
          500,
          {"content-type" => "text/html; charset=utf-8"},
          [dev_error_html(error)]
        ]
      end

      detail = {
        error: error.class.name,
        message: error.message,
        backtrace: error.backtrace&.first(10)
      }

      [
        500,
        {"content-type" => "application/json"},
        [JSON.dump(detail: detail)]
      ]
    end

    def development_env?
      env = ENV["FUNAPI_ENV"] || ENV["RACK_ENV"]
      env == "development"
    end

    def prefers_html?(req)
      accept = req.get_header("HTTP_ACCEPT").to_s
      return false if accept.empty?

      html_index = accept.index("text/html")
      json_index = accept.index("application/json")

      return false unless html_index

      json_index.nil? || html_index < json_index
    end

    def dev_error_html(error)
      backtrace = (error.backtrace || []).map { |line| escape_html(line) }.join("\n")

      <<~HTML
        <!DOCTYPE html>
        <html lang="en">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>#{escape_html(error.class.name)}: #{escape_html(error.message)}</title>
          <style>
            body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; margin: 0; background: #1e1e2e; color: #cdd6f4; }
            header { background: #f38ba8; color: #11111b; padding: 1.5rem 2rem; }
            header h1 { margin: 0 0 0.25rem; font-size: 1.25rem; }
            header p { margin: 0; font-family: monospace; font-size: 1rem; }
            main { padding: 1.5rem 2rem; }
            h2 { font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.05em; color: #a6adc8; }
            pre { background: #181825; border: 1px solid #313244; border-radius: 6px; padding: 1rem; overflow-x: auto; font-size: 0.85rem; line-height: 1.5; }
          </style>
        </head>
        <body>
          <header>
            <h1>#{escape_html(error.class.name)}</h1>
            <p>#{escape_html(error.message)}</p>
          </header>
          <main>
            <h2>Backtrace</h2>
            <pre>#{backtrace}</pre>
          </main>
        </body>
        </html>
      HTML
    end

    def escape_html(text)
      Rack::Utils.escape_html(text.to_s)
    end

    def build_middleware_chain
      app = @route_set

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
        return {} if body.nil? || body.strip.empty?

        begin
          JSON.parse(body, symbolize_names: true)
        rescue JSON::ParserError => e
          raise HTTPException.new(
            status_code: 400,
            detail: [{loc: ["body"], msg: "Invalid JSON: #{e.message}", type: "json_invalid"}]
          )
        end
      when %r{application/x-www-form-urlencoded}
        request.POST
      else
        body
      end
    end

    def extract_headers(env)
      headers = env.select { |k, _v| k.start_with?("HTTP_") }
        .transform_keys { |k| k.delete_prefix("HTTP_").downcase.tr("_", "-") }
      headers["content-type"] = env["CONTENT_TYPE"] if env["CONTENT_TYPE"]
      headers["content-length"] = env["CONTENT_LENGTH"] if env["CONTENT_LENGTH"]
      headers
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
        {"content-type" => "application/json"}
      else
        {"content-type" => "text/plain"}
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
      if item.respond_to?(:to_h) && item.class.name&.include?("Dry::Schema::Result")
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
          normalized[sym] = {type: :container, key: sym}
        end
      when Hash
        depends.each do |key, value|
          normalized[key.to_sym] = case value
          when Depends
            {type: :depends, callable: value}
          when Symbol
            {type: :container, key: value}
          when Proc, Method
            {type: :depends, callable: Depends.new(value)}
          when nil
            {type: :container, key: key.to_sym}
          else
            unless value.respond_to?(:call)
              raise ArgumentError, "Dependency must be callable, Depends, Symbol, or nil for #{key}"
            end

            {type: :depends, callable: Depends.new(value)}

          end
        end
      else
        raise ArgumentError, "depends must be an Array or Hash"
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

      resolved = dependencies.each_with_object({}) do |(dep_name, dep_info), acc|
        override = dependency_override(dep_name, dep_info)

        acc[dep_name] = if override
          resolve_override(override.first)
        else
          case dep_info[:type]
          when :container
            cache_key = "container:#{dep_info[:key]}"
            if cache.key?(cache_key)
              cache[cache_key][:resource]
            else
              dependency_wrapper = @container.resolve(dep_info[:key])
              resource = dependency_wrapper.call
              cache[cache_key] = {resource: resource, wrapper: dependency_wrapper}
              cleanup_objects << dependency_wrapper
              resource
            end
          when :depends
            result, cleanup = dep_info[:callable].call(context, cache)
            cleanup_objects << ManagedDependency.new(result, cleanup) if cleanup
            result
          end
        end
      end

      [resolved, cleanup_objects]
    rescue HTTPException
      raise
    rescue => e
      raise HTTPException.new(
        status_code: 500,
        detail: "Dependency resolution failed: #{e.message}"
      )
    end

    def dependency_override(dep_name, dep_info)
      return [@dependency_overrides[dep_name]] if @dependency_overrides.key?(dep_name)

      key = dep_info[:key]
      return [@dependency_overrides[key]] if key && @dependency_overrides.key?(key)

      nil
    end

    def resolve_override(replacement)
      if replacement.is_a?(Proc) || replacement.is_a?(Method)
        replacement.call
      else
        replacement
      end
    end

    def register_openapi_routes
      @route_set.add("GET", "/openapi.json", metadata: {internal: true}) do |_req, _path_params|
        spec = generate_openapi_spec
        [
          200,
          {"content-type" => "application/json"},
          [JSON.dump(spec)]
        ]
      end

      @route_set.add("GET", "/docs", metadata: {internal: true}) do |_req, _path_params|
        html = swagger_ui_html
        [
          200,
          {"content-type" => "text/html"},
          [html]
        ]
      end
    end

    def generate_openapi_spec
      generator = OpenAPI::SpecGenerator.new(@route_set.routes, info: @openapi_config)
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
