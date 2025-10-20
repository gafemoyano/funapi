# frozen_string_literal: true

require 'async'
require 'async/http/server'
require 'async/http/endpoint'
require 'protocol/rack'
require 'fun_api/router'
require 'fun_api/async'
require 'fun_api/exceptions'
require 'fun_api/schema'

module FunApi
  class App
    include FunApi::AsyncHelpers

    def initialize
      @router = Router.new
      @middleware_stack = []

      yield self if block_given?
    end

    def get(path, query: nil, &blk)
      add_route('GET', path, query: query, &blk)
    end

    def post(path, body: nil, query: nil, &blk)
      add_route('POST', path, body: body, query: query, &blk)
    end

    def put(path, body: nil, query: nil, &blk)
      add_route('PUT', path, body: body, query: query, &blk)
    end

    def patch(path, body: nil, query: nil, &blk)
      add_route('PATCH', path, body: body, query: query, &blk)
    end

    def delete(path, query: nil, &blk)
      add_route('DELETE', path, query: query, &blk)
    end

    # Rack interface
    def call(env)
      # app = build_middleware_chain
      @router.call(env)
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

    def add_route(verb, path, body: nil, query: nil, &blk)
      @router.add(verb, path) { |req, path_params| handle_async_route(req, path_params, body, query, &blk) }
    end

    def handle_async_route(req, path_params, body_schema, query_schema, &blk)
      current_task = Async::Task.current
      Fiber[:async_task] = current_task

      begin
        input = {
          path: path_params,
          query: req.params,
          body: parse_body(req)
        }

        input[:query] = Schema.validate(query_schema, input[:query], location: 'query') if query_schema

        input[:body] = Schema.validate(body_schema, input[:body], location: 'body') if body_schema

        payload, status = blk.call(input, req, current_task)

        [
          status || 200,
          { 'content-type' => 'application/json' },
          [JSON.dump(payload)]
        ]
      rescue ValidationError => e
        e.to_response
      rescue HTTPException => e
        e.to_response
      ensure
        Fiber[:async_task] = nil
      end
    end

    # def build_middleware_chain
    #   app = ->(env) { handle_request(env) }
    #
    #   @middleware_stack.reverse_each do |middleware, args|
    #     app = middleware.new(app, *args)
    #   end
    #
    #   app
    # end

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
  end
end
