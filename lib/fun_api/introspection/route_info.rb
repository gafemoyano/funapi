# frozen_string_literal: true

module FunApi
  module Introspection
    class RouteInfo
      attr_reader :route, :app

      def initialize(route, app)
        @route = route
        @app = app
      end

      def verb
        @route.verb
      end

      def path
        @route.metadata[:path_template] || pattern_to_path
      end

      alias_method :path_template, :path

      def path_params
        @route.keys
      end

      def query_schema
        @route.metadata[:query_schema]
      end

      def body_schema
        @route.metadata[:body_schema]
      end

      def response_schema
        @route.metadata[:response_schema]
      end

      def dependencies
        @route.metadata[:dependencies]&.keys || []
      end

      def dependency_details
        @route.metadata[:dependencies] || {}
      end

      def uses_dependency?(dep_name)
        dependencies.include?(dep_name.to_sym)
      end

      def has_body_schema?
        !body_schema.nil?
      end

      def has_query_schema?
        !query_schema.nil?
      end

      def has_response_schema?
        !response_schema.nil?
      end

      def handler_signature
        return [] unless @route.handler.respond_to?(:parameters)

        @route.handler.parameters
      end

      def internal?
        @route.metadata[:internal] == true
      end

      def metadata
        @route.metadata
      end

      def pattern
        @route.pattern
      end

      def similar_routes
        @app.router.routes
          .map { |r| RouteInfo.new(r, @app) }
          .reject { |r| r == self }
          .select { |r| similarity_score(r) > 0.5 }
          .sort_by { |r| -similarity_score(r) }
      end

      def dependency_tree(depth: 3, current_depth: 0)
        return {} if current_depth >= depth
        return {} if dependencies.empty?

        dependencies.each_with_object({}) do |dep_name, tree|
          dep_info = @app.introspect.dependency(dep_name)
          tree[dep_name] = {
            type: dep_info.type,
            has_cleanup: dep_info.cleanup_defined?
          }

          next unless dep_info.has_sub_dependencies?

          tree[dep_name][:sub_dependencies] = dep_info.sub_dependency_tree(
            depth: depth,
            current_depth: current_depth + 1
          )
        end
      end

      def to_h
        {
          verb: verb,
          path: path,
          path_params: path_params,
          query_schema: schema_name(query_schema),
          body_schema: schema_name(body_schema),
          response_schema: schema_name(response_schema),
          dependencies: dependencies,
          internal: internal?
        }
      end

      def to_json(*_args)
        to_h.to_json
      end

      def ==(other)
        other.is_a?(RouteInfo) &&
          verb == other.verb &&
          path == other.path
      end

      private

      def pattern_to_path
        @route.pattern.source
          .gsub(/\A\^/, "")
          .gsub(/\$\z/, "")
          .gsub("([^/]+)", ":param")
      end

      def schema_name(schema)
        return nil unless schema

        if schema.is_a?(Array)
          item_schema = schema.first
          name = OpenAPI::SchemaConverter.extract_schema_name(item_schema)
          return "[#{name}]" if name

          return "[Schema]"
        end

        OpenAPI::SchemaConverter.extract_schema_name(schema) || "Schema"
      end

      def similarity_score(other)
        score = 0.0
        total = 0.0

        score += 0.3 if body_schema && other.body_schema && same_schema?(body_schema, other.body_schema)
        total += 0.3

        score += 0.3 if response_schema && other.response_schema && same_schema?(response_schema, other.response_schema)
        total += 0.3

        common_deps = (dependencies & other.dependencies).length
        total_deps = (dependencies | other.dependencies).length
        score += 0.4 * (common_deps.to_f / total_deps) if total_deps > 0
        total += 0.4

        (total > 0) ? score / total : 0.0
      end

      def same_schema?(schema1, schema2)
        schema1 == schema2
      end
    end
  end
end
