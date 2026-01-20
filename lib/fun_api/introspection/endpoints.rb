# frozen_string_literal: true

require_relative "endpoint_helpers"

module FunApi
  module Introspection
    class Endpoints
      def self.register(app)
        new(app).register_all
      end

      def initialize(app)
        @app = app
      end

      def register_all
        register_overview
        register_routes
        register_single_route
        register_dependencies
        register_single_dependency
        register_schemas
        register_middleware
        register_health
        register_relationships
      end

      private

      attr_reader :app

      def add_internal_route(path, &handler)
        app.router.add("GET", path, metadata: {internal: true}) do |req, path_params|
          Async do
            result, status = handler.call(path_params, req.params)
            [
              status,
              {"content-type" => "application/json"},
              [JSON.dump(result)]
            ]
          end.wait
        end
      end

      def register_overview
        app_ref = app
        add_internal_route("/introspect") do |_path_params, _query_params|
          inspector = app_ref.introspect
          stats = inspector.stats
          validation = inspector.validate

          data = {
            stats: {
              routes: stats[:routes],
              dependencies: stats[:dependencies],
              schemas: stats[:schemas],
              middleware: stats[:middleware]
            },
            health: {
              score: validation[:score],
              issues_count: validation[:issues].size,
              warnings_count: validation[:warnings].size
            },
            verbs: inspector.routes.map(&:verb).uniq.sort,
            endpoints: {
              routes: "/introspect/routes",
              dependencies: "/introspect/dependencies",
              schemas: "/introspect/schemas",
              middleware: "/introspect/middleware",
              health: "/introspect/health",
              relationships: "/introspect/relationships"
            }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_routes
        app_ref = app
        add_internal_route("/introspect/routes") do |_path_params, query_params|
          inspector = app_ref.introspect
          routes = EndpointHelpers.filter_routes(inspector.routes, query_params || {})

          data = {
            count: routes.size,
            routes: routes.map { |r| EndpointHelpers.route_to_hash(r) }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_single_route
        app_ref = app
        add_internal_route("/introspect/routes/:verb/:path") do |path_params, _query_params|
          inspector = app_ref.introspect
          verb = path_params["verb"].upcase
          path = EndpointHelpers.decode_path(path_params["path"])
          path = "/#{path}" unless path.start_with?("/")

          route = inspector.route(verb, path)

          if route
            data = EndpointHelpers.route_to_detailed_hash(route, inspector)
            [EndpointHelpers.wrap_response(data), 200]
          else
            [EndpointHelpers.not_found_response("Route", "#{verb} #{path}"), 404]
          end
        end
      end

      def register_dependencies
        app_ref = app
        add_internal_route("/introspect/dependencies") do |_path_params, query_params|
          inspector = app_ref.introspect
          deps = EndpointHelpers.filter_dependencies(inspector.dependencies, query_params || {})

          data = {
            count: deps.size,
            dependencies: deps.map { |d| EndpointHelpers.dependency_to_hash(d) }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_single_dependency
        app_ref = app
        add_internal_route("/introspect/dependencies/:name") do |path_params, _query_params|
          inspector = app_ref.introspect
          name = path_params["name"].to_sym

          dep = inspector.dependency(name)

          if dep && app_ref.container.key?(name)
            data = EndpointHelpers.dependency_to_hash(dep)
            [EndpointHelpers.wrap_response(data), 200]
          else
            [EndpointHelpers.not_found_response("Dependency", name.to_s), 404]
          end
        end
      end

      def register_schemas
        app_ref = app
        add_internal_route("/introspect/schemas") do |_path_params, query_params|
          inspector = app_ref.introspect
          schemas = EndpointHelpers.filter_schemas(inspector.schemas, query_params || {})

          data = {
            count: schemas.size,
            schemas: schemas.map { |s| EndpointHelpers.schema_to_hash(s) }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_middleware
        app_ref = app
        add_internal_route("/introspect/middleware") do |_path_params, _query_params|
          inspector = app_ref.introspect

          data = {
            count: inspector.middleware.count,
            middleware: inspector.middleware.chain_order.map { |m| EndpointHelpers.middleware_to_hash(m) }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_health
        app_ref = app
        add_internal_route("/introspect/health") do |_path_params, _query_params|
          inspector = app_ref.introspect
          validation = inspector.validate
          stats = inspector.stats

          status = if validation[:score] >= 0.9
            "healthy"
          elsif validation[:score] >= 0.7
            "degraded"
          else
            "unhealthy"
          end

          issues = validation[:issues].map do |issue|
            {
              type: issue[:type],
              severity: "warning",
              name: issue[:name],
              message: issue_message(issue)
            }
          end

          warnings = validation[:warnings].map do |warning|
            {
              type: warning[:type],
              severity: "info",
              path: warning[:path],
              verb: warning[:verb],
              message: warning_message(warning)
            }
          end

          routes_with_body = inspector.routes.count(&:has_body_schema?)
          routes_with_response = inspector.routes.count(&:has_response_schema?)
          deps_used = inspector.dependencies.count { |d| d.used_by_count > 0 }
          deps_unused = inspector.dependencies.count { |d| d.used_by_count == 0 }

          data = {
            score: validation[:score],
            status: status,
            issues: issues,
            warnings: warnings,
            summary: {
              routes_with_body_schema: routes_with_body,
              routes_without_body_schema: stats[:routes] - routes_with_body,
              routes_with_response_schema: routes_with_response,
              routes_without_response_schema: stats[:routes] - routes_with_response,
              dependencies_used: deps_used,
              dependencies_unused: deps_unused
            }
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def register_relationships
        app_ref = app
        add_internal_route("/introspect/relationships") do |_path_params, _query_params|
          inspector = app_ref.introspect
          rels = inspector.relationships

          data = {
            dependencies: rels.transform_values do |info|
              {
                route_count: info[:routes],
                route_paths: info[:route_paths]
              }
            end
          }

          [EndpointHelpers.wrap_response(data), 200]
        end
      end

      def issue_message(issue)
        case issue[:type]
        when :unused_dependency
          "Dependency :#{issue[:name]} is registered but not used by any route"
        else
          "Issue: #{issue[:type]}"
        end
      end

      def warning_message(warning)
        case warning[:type]
        when :missing_response_schema
          "Route #{warning[:verb]} #{warning[:path]} has no response schema defined"
        else
          "Warning: #{warning[:type]}"
        end
      end
    end
  end
end
