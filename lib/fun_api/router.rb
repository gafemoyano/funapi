# frozen_string_literal: true

module FunApi
  class Router
    Route = Struct.new(:verb, :pattern, :keys, :handler, :metadata)

    def initialize
      @routes = []
    end

    attr_reader :routes

    def add(verb, path, metadata: {}, &handler)
      keys = []
      regex = path.split('/').map do |seg|
        if seg.start_with?(':')
          keys << seg.delete_prefix(':')
          '([^/]+)'
        else
          Regexp.escape(seg)
        end
      end.join('/')

      route_metadata = metadata.merge(path_template: path)
      @routes << Route.new(verb.upcase, /\A#{regex}\z/, keys, handler, route_metadata)
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
