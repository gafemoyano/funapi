# frozen_string_literal: true

require 'fun_api/router'

module FunApi
  class Application
    def initialize
      @router = Router.new
      @middleware_stack = []

      yield self if block_given?
    end

    # Route registration
    # %i[get post put patch delete].each do |method|
    #   define_method(method) do |path, contract: nil, &handler|
    #     add_route(method.to_s.upcase, path, contract, handler)
    #   end
    # end
    #
    # GET
    def get(path, contract: nil, &blk)
      add_route('GET', path, contract: contract, &blk)
    end

    # POST
    def post(path, contract: nil, &blk)
      add_route('POST', path, contract: contract, &blk)
    end

    # PUT (or PATCH – same idea)
    def put(path, contract: nil, &blk)
      add_route('PUT', path, contract: contract, &blk)
    end

    # DELETE
    def delete(path, contract: nil, &blk)
      add_route('DELETE', path, contract: contract, &blk)
    end

    # Rack interface
    def call(env)
      # app = build_middleware_chain
      @router.call(env)
    end

    private

    def add_route(verb, path, contract:, &blk)
      @router.add(verb, path) do |req, path_params|
        # Build the unified input object
        input = {
          path: path_params,
          query: req.params,
          body: parse_body(req) # you might only parse JSON for POST/PUT
        }

        # Run validation if a contract is provided
        if contract
          result = contract.call(input)
          unless result.success?
            return [
              422,
              { 'content-type' => 'application/json' },
              [JSON.dump(errors: result.errors.to_h)]
            ]
          end
          input = result.to_h
        end

        # Call user handler
        payload, status = blk.call(input, req)

        # Return JSON response
        [
          status || 200,
          { 'content-type' => 'application/json' },
          [JSON.dump(payload)]
        ]
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
