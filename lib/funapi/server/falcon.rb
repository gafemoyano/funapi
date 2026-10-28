# frozen_string_literal: true

require "falcon"
require "protocol/rack"

module FunApi
  module Server
    # Falcon server adapter - uses protocol-rack for proper Rack integration
    class Falcon
      def self.start(app, host: "0.0.0.0", port: 3000)
        Async do |task|
          stopping = false
          previous_handlers = {}
          server_task = nil

          begin
            %i[INT TERM].each do |signal|
              previous_handlers[signal] = trap(signal) { stopping = true }
            end

            falcon_app = Protocol::Rack::Adapter.new(app)
            endpoint = ::Async::HTTP::Endpoint.parse("http://#{host}:#{port}").with(protocols: Async::HTTP::Protocol::HTTP2)
            server = ::Falcon::Server.new(falcon_app, endpoint)

            app.run_startup_hooks if app.respond_to?(:run_startup_hooks)

            unless stopping
              server_task = server.run

              puts "Falcon listening on #{host}:#{port}"
              puts "Try: curl http://#{host}:#{port}/hello"
              puts "Press Ctrl+C to stop"

              task.sleep(0.05) until stopping || !server_task.running?
              server_task.wait unless stopping
            end
          ensure
            begin
              if server_task
                server_task.stop
                begin
                  task.with_timeout(1) do
                    task.sleep(0.01) until server_task.finished?
                  end
                rescue Async::TimeoutError
                  server_task.stop
                end
                task.sleep(0.01) until server_task.finished?
              end

              app.run_shutdown_hooks if app.respond_to?(:run_shutdown_hooks)
            ensure
              previous_handlers.each { |signal, handler| trap(signal, handler) }
            end
          end
        end
      end
    end
  end
end
