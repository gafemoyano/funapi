# frozen_string_literal: true

require "json"

module FunApi
  class RouteSet
    Route = Struct.new(:verb, :pattern, :keys, :handler, :metadata)
    Mount = Struct.new(:prefix, :app)

    NOT_FOUND = [404, {"content-type" => "application/json"}, [JSON.dump(detail: "Not Found")]].freeze

    def initialize
      @routes = []
      @routes_by_verb = Hash.new { |hash, verb| hash[verb] = [] }
      @mounts = []
    end

    attr_reader :routes

    def add(verb, path, metadata: {}, &handler)
      keys = []

      regex = if path == "/"
        "/"
      else
        path.split("/").map do |seg|
          if seg.start_with?(":")
            keys << seg.delete_prefix(":")
            "([^/]+)"
          else
            Regexp.escape(seg)
          end
        end.join("/")
      end

      route_metadata = metadata.merge(path_template: path)
      route = Route.new(verb.upcase, /\A#{regex}\z/, keys, handler, route_metadata)
      @routes << route
      @routes_by_verb[route.verb] << route
      route
    end

    def mount(prefix, app)
      @mounts << Mount.new(normalize_mount_prefix(prefix), app)
      @mounts.sort_by! { |m| -m.prefix.length }
      self
    end

    def call(env)
      mounted = match_mount(env["PATH_INFO"])
      return dispatch_mount(mounted, env) if mounted

      req = Rack::Request.new(env)
      route = @routes_by_verb[req.request_method].find { |r| r.pattern =~ req.path_info }
      return NOT_FOUND unless route

      match = route.pattern.match(req.path_info)
      params = route.keys.zip(match.captures).to_h
      route.handler.call(req, params)
    end

    private

    def normalize_mount_prefix(prefix)
      cleaned = prefix.to_s.chomp("/")
      return cleaned if cleaned.empty? || cleaned.start_with?("/")

      "/#{cleaned}"
    end

    def match_mount(path_info)
      @mounts.find do |mount|
        prefix = mount.prefix
        prefix.empty? || path_info == prefix || path_info.start_with?("#{prefix}/")
      end
    end

    def dispatch_mount(mount, env)
      prefix = mount.prefix
      mounted_env = env.dup
      mounted_env["SCRIPT_NAME"] = "#{env["SCRIPT_NAME"]}#{prefix}"
      remaining = env["PATH_INFO"][prefix.length..]
      mounted_env["PATH_INFO"] = remaining.empty? ? "" : remaining
      mount.app.call(mounted_env)
    end
  end
end
