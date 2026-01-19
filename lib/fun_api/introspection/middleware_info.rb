# frozen_string_literal: true

module FunApi
  module Introspection
    class MiddlewareInfo
      attr_reader :middleware_spec, :position, :app

      def initialize(middleware_spec, position, app)
        @middleware_spec = middleware_spec
        @position = position
        @app = app
      end

      def middleware_class
        @middleware_spec[0]
      end

      def args
        @middleware_spec[1] || []
      end

      def block
        @middleware_spec[2]
      end

      def class_name
        middleware_class.name
      end

      def options
        return {} if args.empty?

        if args.length == 1 && args.first.is_a?(Hash) && args.first.keys.all? { |k| k.is_a?(Symbol) }
          args.first
        else
          {args: args}
        end
      end

      def builtin?
        class_name&.start_with?("FunApi::Middleware::")
      end

      def before?(other)
        position < other.position
      end

      def after?(other)
        position > other.position
      end

      def to_h
        {
          class: class_name,
          position: position,
          options: options,
          builtin: builtin?
        }
      end

      def to_json(*_args)
        to_h.to_json
      end

      def ==(other)
        other.is_a?(MiddlewareInfo) &&
          middleware_class == other.middleware_class &&
          position == other.position
      end
    end
  end
end
