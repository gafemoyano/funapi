module FunApi
  module Middleware
    class TrustedHost
      def initialize(app, **options)
        @app = app
        @allowed_hosts = Array(options[:allowed_hosts] || [])
      end

      def call(env)
        host = env["HTTP_HOST"]&.split(":")&.first

        unless host_allowed?(host)
          return [
            400,
            {"content-type" => "application/json"},
            [JSON.dump(detail: "Invalid host header")]
          ]
        end

        @app.call(env)
      end

      private

      def host_allowed?(host)
        return true if @allowed_hosts.empty?

        @allowed_hosts.any? do |pattern|
          pattern.is_a?(Regexp) ? pattern.match?(host) : pattern == host
        end
      end
    end
  end
end
