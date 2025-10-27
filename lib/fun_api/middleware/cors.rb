module FunApi
  module Middleware
    class Cors
      def self.new(app, allow_origins: ['*'], allow_methods: ['*'],
                   allow_headers: ['*'], expose_headers: [],
                   max_age: 600, allow_credentials: false)
        require 'rack/cors'

        Rack::Cors.new(app) do |config|
          config.allow do |allow|
            allow.origins(*allow_origins)
            allow.resource '*',
                           methods: allow_methods,
                           headers: allow_headers,
                           expose: expose_headers,
                           max_age: max_age,
                           credentials: allow_credentials
          end
        end
      end
    end
  end
end
