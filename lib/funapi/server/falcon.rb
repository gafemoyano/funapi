# frozen_string_literal: true

require "falcon"
require "protocol/rack"

module FunApi
  module Server
    # Falcon server adapter - uses protocol-rack for proper Rack integration
    class Falcon
      def self.start(app, host: "0.0.0.0", port: 3000)
        Async do |task|
          falcon_app = Protocol::Rack::Adapter.new(app)
          endpoint = ::Async::HTTP::Endpoint.parse("http://#{host}:#{port}").with(protocols: Async::HTTP::Protocol::HTTP2)

          server = ::Falcon::Server.new(falcon_app, endpoint)

          app.run_startup_hooks if app.respond_to?(:run_startup_hooks)

          puts "Falcon listening on #{host}:#{port}"
          puts "Try: curl http://#{host}:#{port}/hello"
          puts "Press Ctrl+C to stop"

          shutdown = -> {
            puts "\nShutting down..."
            app.run_shutdown_hooks if app.respond_to?(:run_shutdown_hooks)
            task.stop
            exit
          }

          trap(:INT) { shutdown.call }
          trap(:TERM) { shutdown.call }

          server.run
        end
      end
    end
  end
end
