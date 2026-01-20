# frozen_string_literal: true

module FunApi
  module Introspection
    module EndpointHelpers
      VERSION = "1.0"

      def self.wrap_response(data)
        {
          ok: true,
          data: data,
          meta: {
            generated_at: Time.now.iso8601,
            funapi_version: defined?(FunApi::VERSION) ? FunApi::VERSION : "0.1.0",
            introspection_version: VERSION
          }
        }
      end

      def self.error_response(message, hint: nil)
        response = {
          ok: false,
          error: message
        }
        response[:hint] = hint if hint
        response
      end

      def self.not_found_response(type, identifier)
        error_response(
          "#{type} '#{identifier}' not found",
          hint: "Use /introspect/#{type.downcase}s to list all available #{type.downcase}s"
        )
      end

      def self.route_to_hash(route_info)
        {
          verb: route_info.verb,
          path: route_info.path,
          path_params: route_info.path_params,
          dependencies: route_info.dependencies,
          body_schema: schema_name(route_info.body_schema),
          query_schema: schema_name(route_info.query_schema),
          response_schema: schema_name(route_info.response_schema),
          has_body_schema: route_info.has_body_schema?,
          has_query_schema: route_info.has_query_schema?,
          has_response_schema: route_info.has_response_schema?
        }
      end

      def self.route_to_detailed_hash(route_info, inspector)
        base = route_to_hash(route_info)
        base[:schemas] = {}

        if route_info.body_schema
          schema_info = inspector.schemas.find { |s| s.schema == route_info.body_schema }
          base[:schemas][:body] = schema_info_to_hash(schema_info) if schema_info
        end

        if route_info.query_schema
          schema_info = inspector.schemas.find { |s| s.schema == route_info.query_schema }
          base[:schemas][:query] = schema_info_to_hash(schema_info) if schema_info
        end

        if route_info.response_schema
          schema_info = inspector.schemas.find { |s| s.schema == route_info.response_schema }
          base[:schemas][:response] = schema_info_to_hash(schema_info) if schema_info
        end

        base[:example_request] = generate_example_request(base[:schemas][:body]) if base[:schemas][:body]

        similar = route_info.similar_routes.first(5).map do |r|
          {verb: r[:route].verb, path: r[:route].path, similarity: r[:score].round(2)}
        end
        base[:similar_routes] = similar

        base
      end

      def self.dependency_to_hash(dep_info)
        {
          name: dep_info.name,
          type: dep_info.type,
          has_cleanup: dep_info.cleanup_defined?,
          used_by_count: dep_info.used_by_count,
          used_by_routes: dep_info.used_by.map(&:path)
        }
      end

      def self.schema_info_to_hash(schema_info)
        {
          name: schema_info.name,
          required_fields: schema_info.required_fields,
          optional_fields: schema_info.optional_fields,
          field_types: schema_info.field_types
        }
      end

      def self.schema_to_hash(schema_info)
        base = schema_info_to_hash(schema_info)
        base[:used_as] = schema_info.used_as
        base[:used_by_routes] = schema_info.used_by_routes.map(&:path)
        base
      end

      def self.middleware_to_hash(mw_info)
        {
          name: mw_info.class_name,
          position: mw_info.position,
          builtin: mw_info.builtin?,
          options: mw_info.options
        }
      end

      def self.schema_name(schema)
        return nil if schema.nil?
        return "[#{schema_name(schema.first)}]" if schema.is_a?(Array)

        if schema.respond_to?(:name) && schema.name
          schema.name.split("::").last
        else
          "AnonymousSchema"
        end
      end

      def self.generate_example_request(schema_hash)
        return nil unless schema_hash

        example = {}
        all_fields = (schema_hash[:required_fields] || []) + (schema_hash[:optional_fields] || [])
        field_types = schema_hash[:field_types] || {}

        all_fields.each do |field|
          example[field] = example_value_for_type(field_types[field])
        end

        example
      end

      def self.example_value_for_type(type)
        case type.to_s
        when "string" then "string"
        when "integer", "int" then 0
        when "float", "decimal" then 0.0
        when "boolean", "bool" then true
        when "array" then []
        when "hash", "object" then {}
        else "value"
        end
      end

      def self.filter_routes(routes, params)
        result = routes.to_a

        if params["verb"]
          verb = params["verb"].upcase
          result = result.select { |r| r.verb == verb }
        end

        if params["has_body"] == "true"
          result = result.select(&:has_body_schema?)
        elsif params["has_body"] == "false"
          result = result.reject(&:has_body_schema?)
        end

        if params["has_response"] == "true"
          result = result.select(&:has_response_schema?)
        elsif params["has_response"] == "false"
          result = result.reject(&:has_response_schema?)
        end

        if params["uses_dep"]
          dep = params["uses_dep"].to_sym
          result = result.select { |r| r.dependencies.include?(dep) }
        end

        if params["search"]
          term = params["search"].downcase
          result = result.select { |r| r.path.downcase.include?(term) }
        end

        result
      end

      def self.filter_dependencies(dependencies, params)
        result = dependencies.to_a

        result = result.select { |d| d.used_by_count == 0 } if params["unused"] == "true"

        if params["has_cleanup"] == "true"
          result = result.select(&:cleanup_defined?)
        elsif params["has_cleanup"] == "false"
          result = result.reject(&:cleanup_defined?)
        end

        result
      end

      def self.filter_schemas(schemas, params)
        result = schemas.to_a

        if params["has_field"]
          field = params["has_field"].to_sym
          result = result.select { |s| s.fields.include?(field) }
        end

        if params["used_as"]
          usage = params["used_as"].to_sym
          result = result.select { |s| s.used_as.include?(usage) }
        end

        result
      end

      def self.decode_path(encoded_path)
        URI.decode_www_form_component(encoded_path)
      rescue ArgumentError
        encoded_path
      end
    end
  end
end
