# frozen_string_literal: true

require "dry-schema"
require_relative "exceptions"

module FunApi
  class Model
    PRIMITIVE_TYPES = %i[string integer float decimal bool date time hash].freeze
    VALID_OPTIONS = %i[optional default nullable description format enum min max pattern].freeze

    class << self
      def field(name, type, **options)
        name = name.to_sym

        unknown = options.keys - VALID_OPTIONS
        unless unknown.empty?
          raise ArgumentError,
            "unknown option(s) for field #{name}: #{unknown.join(", ")}. " \
            "Valid options are: #{VALID_OPTIONS.join(", ")}"
        end

        validate_type!(name, type)

        has_default = options.key?(:default)
        optional = options.fetch(:optional, false)

        meta = {
          name: name,
          type: type,
          required: !optional && !has_default,
          optional: optional,
          nullable: options.fetch(:nullable, false),
          has_default: has_default,
          default: options[:default],
          description: options[:description],
          format: options[:format],
          enum: options[:enum],
          min: options[:min],
          max: options[:max],
          pattern: options[:pattern]
        }.freeze

        own_fields[name] = meta
        reset_engine!
        name
      end

      def fields
        base = superclass.respond_to?(:fields) ? superclass.fields : {}
        base.merge(own_fields).freeze
      end

      def validate(data)
        prepared = apply_defaults(data || {})
        result = engine_schema.call(prepared)
        raise ValidationError.new(errors: result.errors) unless result.success?

        result.to_h
      end

      def dump(source)
        return nil if source.nil?

        fields.each_with_object({}) do |(name, meta), out|
          present, value = fetch(source, name)
          next unless present
          next if value.nil? && !meta[:nullable]

          out[name] = dump_value(value, meta)
        end
      end

      def json_schema
        properties = {}
        required = []

        fields.each do |name, meta|
          properties[name.to_s] = field_json_schema(meta)
          required << name.to_s if meta[:required]
        end

        schema = {type: "object", properties: properties}
        schema[:required] = required unless required.empty?
        schema
      end

      def engine_schema
        @engine_schema ||= build_engine_schema
      end

      def apply_defaults(data)
        return data unless data.is_a?(Hash)

        result = data.each_with_object({}) { |(key, value), acc| acc[key.to_sym] = value }

        fields.each do |name, meta|
          if meta[:has_default] && !result.key?(name)
            result[name] = default_value(meta[:default])
          end

          value = result[name]
          next if value.nil?

          type = meta[:type]
          if model_type?(type)
            result[name] = type.apply_defaults(value) if value.is_a?(Hash)
          elsif type.is_a?(Array) && model_type?(type.first) && value.is_a?(Array)
            result[name] = value.map { |item| item.is_a?(Hash) ? type.first.apply_defaults(item) : item }
          end
        end

        result
      end

      def apply_field(node, meta)
        type = meta[:type]

        if type.is_a?(Array)
          apply_array(node, type.first, meta)
        elsif model_type?(type)
          node.hash(type.engine_schema)
        else
          apply_primitive(node, type, meta)
        end
      end

      private

      def own_fields
        @own_fields ||= {}
      end

      def reset_engine!
        @engine_schema = nil
      end

      def model_type?(type)
        type.is_a?(Class) && type < FunApi::Model
      end

      def validate_type!(name, type)
        if type.is_a?(Array)
          unless type.length == 1
            raise ArgumentError,
              "array type for field #{name} must wrap exactly one element type, e.g. [:string] or [Tag]; got #{type.inspect}"
          end

          validate_type!(name, type.first)
          return
        end

        return if PRIMITIVE_TYPES.include?(type)
        return if model_type?(type)

        raise ArgumentError,
          "unknown type #{type.inspect} for field #{name}. " \
          "Use a primitive (#{PRIMITIVE_TYPES.join(", ")}), a FunApi::Model subclass, " \
          "or a single-element array like [:string] for collections"
      end

      def default_value(value)
        case value
        when Array, Hash then value.dup
        else value
        end
      end

      def build_engine_schema
        field_defs = fields
        Dry::Schema.Params do
          field_defs.each do |name, meta|
            node = meta[:required] ? required(name) : optional(name)
            FunApi::Model.apply_field(node, meta)
          end
        end
      end

      def apply_primitive(node, type, meta)
        predicates = field_predicates(meta)

        if meta[:nullable]
          predicates.empty? ? node.maybe(type) : node.maybe(type, **predicates)
        else
          predicates.empty? ? node.filled(type) : node.filled(type, **predicates)
        end
      end

      def apply_array(node, inner, meta)
        size = {}
        size[:min_size?] = meta[:min] if meta[:min]
        size[:max_size?] = meta[:max] if meta[:max]

        member = model_type?(inner) ? inner.engine_schema : inner

        if size.empty?
          node.array(member)
        else
          node.value(:array, **size).each(member)
        end
      end

      def field_predicates(meta)
        predicates = {}
        predicates[:included_in?] = meta[:enum] if meta[:enum]
        predicates[:format?] = meta[:pattern] if meta[:pattern]

        if numeric_type?(meta[:type])
          predicates[:gteq?] = meta[:min] if meta[:min]
          predicates[:lteq?] = meta[:max] if meta[:max]
        else
          predicates[:min_size?] = meta[:min] if meta[:min]
          predicates[:max_size?] = meta[:max] if meta[:max]
        end

        predicates
      end

      def numeric_type?(type)
        %i[integer float decimal].include?(type)
      end

      def fetch(source, name)
        if source.is_a?(Hash)
          if source.key?(name)
            [true, source[name]]
          elsif source.key?(name.to_s)
            [true, source[name.to_s]]
          else
            [false, nil]
          end
        elsif source.respond_to?(name)
          [true, source.public_send(name)]
        else
          [false, nil]
        end
      end

      def dump_value(value, meta)
        return nil if value.nil?

        type = meta[:type]
        if model_type?(type)
          type.dump(value)
        elsif type.is_a?(Array) && model_type?(type.first)
          Array(value).map { |item| type.first.dump(item) }
        else
          value
        end
      end

      def field_json_schema(meta)
        type = meta[:type]

        schema = if type.is_a?(Array)
          {type: "array", items: item_json_schema(type.first)}
        elsif model_type?(type)
          type.json_schema
        else
          primitive_json_schema(type)
        end

        decorate_json_schema(schema, meta)
      end

      def item_json_schema(inner)
        if model_type?(inner)
          inner.json_schema
        else
          primitive_json_schema(inner)
        end
      end

      def primitive_json_schema(type)
        case type
        when :string then {type: "string"}
        when :integer then {type: "integer"}
        when :float, :decimal then {type: "number"}
        when :bool then {type: "boolean"}
        when :date then {type: "string", format: "date"}
        when :time then {type: "string", format: "date-time"}
        when :hash then {type: "object"}
        else {type: "string"}
        end
      end

      def decorate_json_schema(schema, meta)
        schema = schema.dup
        schema[:description] = meta[:description] if meta[:description]
        schema[:format] = meta[:format] if meta[:format]
        schema[:enum] = meta[:enum] if meta[:enum]
        apply_bounds(schema, meta)
        schema[:pattern] = meta[:pattern].is_a?(Regexp) ? meta[:pattern].source : meta[:pattern] if meta[:pattern]
        schema[:nullable] = true if meta[:nullable]
        schema
      end

      def apply_bounds(schema, meta)
        return unless meta[:min] || meta[:max]

        type = meta[:type]
        min_key, max_key = if numeric_type?(type)
          %i[minimum maximum]
        elsif type.is_a?(Array)
          %i[minItems maxItems]
        else
          %i[minLength maxLength]
        end

        schema[min_key] = meta[:min] if meta[:min]
        schema[max_key] = meta[:max] if meta[:max]
      end
    end
  end
end
