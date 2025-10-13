# frozen_string_literal: true

module FunApi
  # Map routes to handlers
  class Router
    Route = Struct.new(:verb, :pattern, :keys, :handler)

    def initialize
      @routes = []
    end

    def add(verb, path, &handler)
      # Convert /users/:id -> regex + keys
      keys = []
      regex = path.split('/').map do |seg|
        if seg.start_with?(':')
          keys << seg.delete_prefix(':')
          '([^/]+)'
        else
          Regexp.escape(seg)
        end
      end.join('/')
      @routes << Route.new(verb.upcase, /\A#{regex}\z/, keys, handler)
    end

    def call(env)
      req = Rack::Request.new(env)
      route = @routes.find { |r| r.verb == req.request_method && r.pattern =~ req.path_info }
      return [404, { 'content-type' => 'application/json' }, [JSON.dump(error: 'Not found')]] unless route

      match = route.pattern.match(req.path_info)
      params = route.keys.zip(match.captures).to_h
      route.handler.call(req, params)
    end
  end
end
