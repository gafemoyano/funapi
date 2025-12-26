require_relative "schema_converter"

module FunApi
  module OpenAPI
    class SpecGenerator
      def initialize(routes, info:)
        @routes = routes
        @info = info
        @schemas = {}
        @schema_counter = 0
      end

      def generate
        {
          openapi: "3.0.3",
          info: build_info,
          paths: build_paths,
          components: build_components
        }
      end

      private

      def build_info
        {
          title: @info[:title],
          version: @info[:version],
          description: @info[:description]
        }
      end

      def build_paths
        paths = {}

        @routes.each do |route|
          next if route.metadata[:internal]

          path_template = convert_path_template(route.metadata[:path_template])
          paths[path_template] ||= {}

          operation = build_operation(route)
          paths[path_template][route.verb.downcase] = operation
        end

        paths
      end

      def build_operation(route)
        operation = {}

        parameters = []
        parameters.concat(build_path_parameters(route))
        parameters.concat(build_query_parameters(route))

        operation[:parameters] = parameters unless parameters.empty?
        operation[:requestBody] = build_request_body(route) if route.metadata[:body_schema]
        operation[:responses] = build_responses(route)

        operation
      end

      def build_path_parameters(route)
        route.keys.map do |key|
          {
            name: key,
            in: "path",
            required: true,
            schema: {type: "string"}
          }
        end
      end

      def build_query_parameters(route)
        query_schema = route.metadata[:query_schema]
        return [] unless query_schema

        schema = unwrap_array_schema(query_schema)
        json_schema = SchemaConverter.to_json_schema(schema)
        return [] unless json_schema && json_schema[:properties]

        required_fields = json_schema[:required] || []

        json_schema[:properties].map do |name, prop_schema|
          {
            name: name.to_s,
            in: "query",
            required: required_fields.include?(name.to_s),
            schema: prop_schema
          }
        end
      end

      def build_request_body(route)
        body_schema = route.metadata[:body_schema]
        return nil unless body_schema

        schema_ref = register_schema(body_schema, route.verb, route.metadata[:path_template])

        {
          required: true,
          content: {
            "application/json": {
              schema: schema_ref
            }
          }
        }
      end

      def build_responses(route)
        response_schema = route.metadata[:response_schema]

        if response_schema
          schema_ref = register_schema(response_schema, "#{route.verb}Response", route.metadata[:path_template])

          {
            "200": {
              description: "Successful response",
              content: {
                "application/json": {
                  schema: schema_ref
                }
              }
            }
          }
        else
          {
            "200": {
              description: "Successful response"
            }
          }
        end
      end

      def register_schema(schema, verb, path)
        schema_obj = unwrap_array_schema(schema)
        is_array = schema.is_a?(Array)

        schema_name = SchemaConverter.extract_schema_name(schema_obj)

        unless schema_name
          @schema_counter += 1
          method_name = path.split("/").reject(&:empty?).map do |s|
            s.start_with?(":") ? s[1..-1].capitalize : s.capitalize
          end.join
          schema_name = "#{method_name}#{verb.capitalize}Schema#{@schema_counter}"
        end

        @schemas[schema_name] = SchemaConverter.to_json_schema(schema_obj)

        if is_array
          {
            type: "array",
            items: {"$ref": "#/components/schemas/#{schema_name}"}
          }
        else
          {"$ref": "#/components/schemas/#{schema_name}"}
        end
      end

      def build_components
        {
          schemas: @schemas
        }
      end

      def convert_path_template(path)
        path.gsub(/:(\w+)/, '{\1}')
      end

      def unwrap_array_schema(schema)
        if schema.is_a?(Array) && schema.length == 1
          schema.first
        else
          schema
        end
      end
    end
  end
end
