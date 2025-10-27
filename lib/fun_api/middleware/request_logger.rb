require 'logger'

module FunApi
  module Middleware
    class RequestLogger
      def initialize(app, **options)
        @app = app
        @logger = options[:logger] || Logger.new($stdout)
        @level = options[:level] || :info
      end

      def call(env)
        start = Time.now
        status, headers, body = @app.call(env)
        duration = Time.now - start

        log_request(env, status, duration)

        [status, headers, body]
      end

      private

      def log_request(env, status, duration)
        request = Rack::Request.new(env)
        @logger.send(@level,
                     "#{request.request_method} #{request.path} " \
                     "#{status} #{(duration * 1000).round(2)}ms")
      end
    end
  end
end
