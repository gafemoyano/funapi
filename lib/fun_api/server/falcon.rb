# frozen_string_literal: true

require 'falcon'
require 'protocol/rack'

module FunApi
  module Server
    # Falcon server adapter - uses protocol-rack for proper Rack integration
    class Falcon
      def self.start(app, host: '0.0.0.0', port: 3000)
        Async do |task|
          endpoint = Async::HTTP::Endpoint.parse("http://#{host}:#{port}")

          # Use protocol-rack to properly bridge Rack and Falcon
          falcon_app = Protocol::Rack::Adapter.new(app)
          server = ::Falcon::Server.new(falcon_app, endpoint)

          # Graceful shutdown on Ctrl-C / SIGINT
          task.async do
            task.sleep(0.1) # Small delay to let server start
            puts "🚀 Falcon listening on #{host}:#{port}"
            puts "Try: curl http://#{host}:#{port}/hello"
            puts 'Press Ctrl+C to stop'
          end

          trap(:INT) do
            puts "\nShutting down..."
            task.stop
          end

          server.run
        end
      end
    end
  end
end
