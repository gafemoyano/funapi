# frozen_string_literal: true

module FunApi
  module Introspection
    class DependencyInfo
      attr_reader :name, :app

      def initialize(name, app)
        @name = name.to_sym
        @app = app
      end

      def type
        wrapper = resolve_wrapper
        case wrapper
        when SimpleDependency
          :simple
        when ManagedDependency
          :managed
        when BlockDependency
          :block
        else
          :unknown
        end
      end

      def used_by
        @app.router.routes
          .map { |r| RouteInfo.new(r, @app) }
          .select { |r| r.uses_dependency?(@name) }
      end

      def used_by_count
        used_by.length
      end

      def cleanup_defined?
        wrapper = resolve_wrapper
        case wrapper
        when ManagedDependency
          !wrapper.cleanup_proc.nil?
        when BlockDependency
          true
        else
          false
        end
      end

      def callable?
        resolve_wrapper.respond_to?(:call)
      end

      def has_sub_dependencies?
        details = dependency_details
        return false unless details

        details.values.any? { |v| v[:type] == :depends }
      end

      def sub_dependencies
        details = dependency_details
        return {} unless details

        details.select { |_k, v| v[:type] == :depends }
          .transform_values { |v| v[:callable] }
      end

      def sub_dependency_tree(depth: 3, current_depth: 0)
        return {} if current_depth >= depth
        return {} unless has_sub_dependencies?

        sub_dependencies.each_with_object({}) do |(key, callable), tree|
          tree[key] = {
            type: :depends,
            callable: callable.class.name
          }

          if callable.is_a?(Depends) && callable.sub_dependencies.any?
            tree[key][:nested] = analyze_depends_tree(callable, depth, current_depth + 1)
          end
        end
      end

      def dependency_chain
        [name]
      end

      def to_h
        {
          name: name,
          type: type,
          used_by_count: used_by_count,
          used_by_routes: used_by.map(&:path),
          has_cleanup: cleanup_defined?,
          has_sub_dependencies: has_sub_dependencies?
        }
      end

      def to_json(*_args)
        to_h.to_json
      end

      def ==(other)
        other.is_a?(DependencyInfo) && name == other.name
      end

      private

      def resolve_wrapper
        @app.container.resolve(@name)
      rescue
        nil
      end

      def dependency_details
        @app.router.routes.each do |route|
          deps = route.metadata[:dependencies]
          next unless deps

          dep_info = deps[@name]
          return deps if dep_info
        end
        nil
      end

      def analyze_depends_tree(depends_obj, depth, current_depth)
        return {} if current_depth >= depth

        depends_obj.sub_dependencies.each_with_object({}) do |(key, value), tree|
          tree[key] = if value.is_a?(Depends)
            {
              type: :depends,
              nested: analyze_depends_tree(value, depth, current_depth + 1)
            }
          elsif value.is_a?(Symbol)
            {type: :container, key: value}
          else
            {type: :other}
          end
        end
      end
    end
  end
end
