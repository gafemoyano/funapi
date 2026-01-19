# frozen_string_literal: true

module FunApi
  module Introspection
    class SchemaInfo
      attr_reader :schema, :app

      def initialize(schema, app, name: nil)
        @schema = schema
        @app = app
        @cached_name = name
      end

      def name
        @cached_name ||= discover_name
      end

      def constant_name
        name
      end

      def is_array_schema?
        @schema.is_a?(Array)
      end

      def item_schema
        return nil unless is_array_schema?

        @schema.first
      end

      def fields
        return [] unless schema_object.respond_to?(:rules)

        schema_object.rules.keys.map(&:to_sym)
      end

      def required_fields
        fields.select { |field| field_required?(field) }
      end

      def optional_fields
        fields - required_fields
      end

      def field_types
        return {} unless schema_object.respond_to?(:rules)

        schema_object.rules.each_with_object({}) do |(key, rule), types|
          types[key.to_sym] = extract_type_from_rule(rule)
        end
      end

      def field(field_name)
        FieldInfo.new(field_name, self)
      end

      def has_field?(field_name)
        fields.include?(field_name.to_sym)
      end

      def used_by_routes
        @app.router.routes
          .map { |r| RouteInfo.new(r, @app) }
          .select do |r|
          r.body_schema == @schema ||
            r.query_schema == @schema ||
            r.response_schema == @schema
        end
      end

      def used_as
        roles = []
        @app.router.routes.each do |r|
          roles << :body if r.metadata[:body_schema] == @schema
          roles << :query if r.metadata[:query_schema] == @schema
          roles << :response if r.metadata[:response_schema] == @schema
        end
        roles.uniq
      end

      def similar_schemas
        @app.introspect.schemas.all
          .reject { |s| s == self }
          .select { |s| similarity_score(s) > 0.5 }
          .sort_by { |s| -similarity_score(s) }
      end

      def to_json_schema
        OpenAPI::SchemaConverter.to_json_schema(@schema, name)
      end

      def example_data
        return [] if is_array_schema?

        fields.each_with_object({}) do |field, data|
          type = field_types[field]
          data[field] = generate_example_value(type, field)
        end
      end

      def validate(data)
        result = schema_object.call(data)
        result.success? ? nil : result.errors.to_h
      end

      def to_h
        {
          name: name,
          is_array: is_array_schema?,
          fields: fields,
          required_fields: required_fields,
          optional_fields: optional_fields,
          field_types: field_types,
          used_by_routes: used_by_routes.map(&:path),
          used_as: used_as
        }
      end

      def to_json(*_args)
        to_h.to_json
      end

      def ==(other)
        other.is_a?(SchemaInfo) && @schema == other.schema
      end

      private

      def schema_object
        is_array_schema? ? item_schema : @schema
      end

      def discover_name
        OpenAPI::SchemaConverter.extract_schema_name(@schema) || "AnonymousSchema"
      end

      def field_required?(field)
        return false unless schema_object.respond_to?(:rules)

        rule = schema_object.rules[field]
        return false unless rule

        rule.class.name.include?("And")
      end

      def extract_type_from_rule(rule)
        rule_str = rule.to_s

        return :array if rule_str.include?("array?")
        return :hash if rule_str.include?("hash?")
        return :string if rule_str.include?("str?")
        return :integer if rule_str.include?("int?")
        return :number if rule_str.include?("float?") || rule_str.include?("decimal?")
        return :boolean if rule_str.include?("bool?")

        :unknown
      end

      def similarity_score(other)
        return 0.0 if fields.empty? || other.fields.empty?

        common_fields = (fields & other.fields).length
        total_fields = (fields | other.fields).length

        common_fields.to_f / total_fields
      end

      def generate_example_value(type, field_name)
        case type
        when :string
          generate_string_example(field_name)
        when :integer
          1
        when :number
          1.0
        when :boolean
          true
        when :array
          []
        when :hash
          {}
        end
      end

      def generate_string_example(field_name)
        field_str = field_name.to_s.downcase
        return "user@example.com" if field_str.include?("email")
        return "John Doe" if field_str.include?("name")
        return "https://example.com" if field_str.include?("url")

        "example_#{field_name}"
      end

      class FieldInfo
        attr_reader :name, :schema_info

        def initialize(name, schema_info)
          @name = name.to_sym
          @schema_info = schema_info
        end

        def type
          schema_info.field_types[@name]
        end

        def required?
          schema_info.required_fields.include?(@name)
        end

        def optional?
          !required?
        end

        def example
          schema_info.example_data[@name]
        end

        def to_h
          {
            name: @name,
            type: type,
            required: required?,
            example: example
          }
        end
      end
    end
  end
end
