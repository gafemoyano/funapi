# frozen_string_literal: true

require "sequel"

::Sequel.extension :fiber_concurrency

module FunApi
  module Sequel
    module ConnectionSetup
      private

      def server_opts(server)
        options = super
        return options unless (callback = options[:after_connect])

        options.merge(after_connect: proc do |connection, name|
          completed = false
          result = (callback.arity == 2) ? callback.call(connection, name) : callback.call(connection)
          completed = true
          result
        ensure
          unless completed
            error = $!
            begin
              disconnect_connection(connection)
            ensure
              raise error if error
            end
          end
        end)
      end
    end

    def self.connect(url, pool_class: :timed_queue, **opts)
      before_preconnect = opts.fetch(:before_preconnect) do
        url[:before_preconnect] if url.is_a?(Hash)
      end
      opts[:before_preconnect] = proc do |db|
        db.extend(ConnectionSetup)
        before_preconnect&.call(db)
      end
      ::Sequel.connect(url, pool_class: pool_class, **opts)
    end
  end
end
