# frozen_string_literal: true

require "digest"
require_relative "collection"
require_relative "route_info"
require_relative "dependency_info"
require_relative "schema_info"
require_relative "middleware_info"

module FunApi
  module Introspection
    class Inspector
      attr_reader :app

      def initialize(app)
        @app = app
        @cache = {}
      end

      def routes
        @cache[:routes] ||= RouteCollection.new(
          @app.router.routes
            .reject { |r| r.metadata[:internal] }
            .map { |r| RouteInfo.new(r, @app) }
        )
      end

      def all_routes
        @cache[:all_routes] ||= RouteCollection.new(
          @app.router.routes.map { |r| RouteInfo.new(r, @app) }
        )
      end

      def route(verb, path)
        routes.find_by(verb: verb.to_s.upcase, path: path)
      end

      def dependencies
        @cache[:dependencies] ||= DependencyCollection.new(
          @app.container.keys.map { |key| DependencyInfo.new(key, @app) }
        )
      end

      def dependency(name)
        DependencyInfo.new(name.to_sym, @app)
      end

      def schemas
        @cache[:schemas] ||= begin
          discovered = discover_schemas
          SchemaCollection.new(
            discovered.map { |schema, name| SchemaInfo.new(schema, @app, name: name) }
          )
        end
      end

      def schema(schema_obj)
        schemas.find { |s| s.schema == schema_obj }
      end

      def middleware
        @cache[:middleware] ||= MiddlewareCollection.new(
          @app.middleware_stack.map.with_index { |m, i| MiddlewareInfo.new(m, i, @app) }
        )
      end

      def stats
        {
          routes: routes.count,
          dependencies: dependencies.count,
          schemas: schemas.count,
          middleware: middleware.count,
          verbs: routes.verbs,
          path_params: routes.map(&:path_params).flatten.uniq,
          most_common_dependency: most_common_dependency,
          schema_coverage: schema_coverage
        }
      end

      def validate
        issues = []
        warnings = []

        unused_deps = dependencies.unused
        issues.concat(unused_deps.map { |d| {type: :unused_dependency, name: d.name} })

        routes_without_response = routes.where { |r| !r.has_response_schema? && !r.internal? }
        warnings.concat(routes_without_response.map do |r|
          {type: :missing_response_schema, path: r.path, verb: r.verb}
        end)

        post_without_body = routes.where(verb: "POST").where { |r| !r.has_body_schema? }
        warnings.concat(post_without_body.map do |r|
          {type: :post_without_body_schema, path: r.path}
        end)

        {
          issues: issues,
          warnings: warnings,
          score: calculate_health_score(issues, warnings)
        }
      end

      def relationships
        dependencies.all.each_with_object({}) do |dep, rels|
          rels[dep.name] = {
            routes: dep.used_by_count,
            route_paths: dep.used_by.map(&:path)
          }
        end
      end

      def fingerprint
        Digest::SHA256.hexdigest(to_json)
      end

      def changed_since?(old_fingerprint)
        fingerprint != old_fingerprint
      end

      def clear_cache
        @cache.clear
      end

      def to_h
        {
          stats: stats,
          routes: routes.to_h,
          dependencies: dependencies.to_h,
          schemas: schemas.to_h,
          middleware: middleware.to_h
        }
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      private

      def discover_schemas
        schemas = []
        seen = Set.new

        @app.router.routes.each do |route|
          [route.metadata[:body_schema], route.metadata[:query_schema],
            route.metadata[:response_schema]].each do |schema|
            next unless schema
            next if seen.include?(schema.object_id)

            seen.add(schema.object_id)
            name = OpenAPI::SchemaConverter.extract_schema_name(schema)
            schemas << [schema, name]
          end
        end

        schemas
      end

      def most_common_dependency
        return nil if routes.empty?

        dep_counts = routes.map(&:dependencies).flatten.each_with_object(Hash.new(0)) do |dep, counts|
          counts[dep] += 1
        end

        return nil if dep_counts.empty?

        dep_counts.max_by { |_dep, count| count }&.first
      end

      def schema_coverage
        return 1.0 if routes.empty?

        routes_with_schemas = routes.count do |r|
          r.has_body_schema? || r.has_query_schema? || r.has_response_schema?
        end

        routes_with_schemas.to_f / routes.count
      end

      def calculate_health_score(issues, warnings)
        total_routes = routes.count
        return 1.0 if total_routes.zero?

        deductions = issues.length * 0.1 + warnings.length * 0.05
        score = 1.0 - (deductions / total_routes)
        [score, 0.0].max
      end
    end
  end
end
