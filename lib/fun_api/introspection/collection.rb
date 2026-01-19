# frozen_string_literal: true

module FunApi
  module Introspection
    class Collection
      include Enumerable

      attr_reader :items

      def initialize(items = [])
        @items = items
      end

      def each(&block)
        @items.each(&block)
      end

      def where(conditions = {}, &block)
        filtered = if block_given?
          @items.select(&block)
        else
          @items.select { |item| matches_conditions?(item, conditions) }
        end

        self.class.new(filtered)
      end

      def find_by(conditions)
        @items.find { |item| matches_conditions?(item, conditions) }
      end

      def all
        @items
      end

      def first
        @items.first
      end

      def last
        @items.last
      end

      def count
        @items.length
      end

      alias_method :length, :count
      alias_method :size, :count

      def empty?
        @items.empty?
      end

      def map(&block)
        @items.map(&block)
      end

      def select(&block)
        self.class.new(@items.select(&block))
      end

      def reject(&block)
        self.class.new(@items.reject(&block))
      end

      def group_by(&block)
        @items.group_by(&block)
      end

      def sort_by(&block)
        self.class.new(@items.sort_by(&block))
      end

      def to_a
        @items
      end

      def to_json(*args)
        @items.map(&:to_h).to_json(*args)
      end

      def to_h
        @items.map(&:to_h)
      end

      private

      def matches_conditions?(item, conditions)
        conditions.all? do |key, value|
          item_value = item.respond_to?(key) ? item.public_send(key) : nil

          case value
          when Proc
            value.call(item_value)
          when Regexp
            item_value.to_s =~ value
          when Array
            value.include?(item_value)
          else
            item_value == value
          end
        end
      end
    end

    class RouteCollection < Collection
      def where_verb(verb)
        where(verb: verb.to_s.upcase)
      end

      def where_uses_dependency(dep_name)
        where { |r| r.uses_dependency?(dep_name) }
      end

      def where_has_body_schema
        where { |r| r.has_body_schema? }
      end

      def where_has_query_schema
        where { |r| r.has_query_schema? }
      end

      def where_has_response_schema
        where { |r| r.has_response_schema? }
      end

      def where_path_param(param_name)
        where { |r| r.path_params.include?(param_name.to_s) }
      end

      def internal
        where(internal?: true)
      end

      def external
        where { |r| !r.internal? }
      end

      def search(query)
        query_lower = query.to_s.downcase
        where { |r| r.path.downcase.include?(query_lower) }
      end

      def verbs
        map(&:verb).uniq
      end

      def paths
        map(&:path)
      end

      def count_by_verb
        group_by(&:verb).transform_values(&:length)
      end

      def unused_dependencies(all_dependencies)
        used_deps = map(&:dependencies).flatten.uniq
        all_dependencies - used_deps
      end
    end

    class DependencyCollection < Collection
      def where_type(type)
        where(type: type)
      end

      def unused
        where { |d| d.used_by_count.zero? }
      end

      def most_used(limit = 10)
        sorted = sort_by { |d| -d.used_by_count }
        self.class.new(sorted.to_a.take(limit))
      end

      def names
        map(&:name)
      end

      def with_cleanup
        where { |d| d.cleanup_defined? }
      end

      def without_cleanup
        where { |d| !d.cleanup_defined? }
      end
    end

    class SchemaCollection < Collection
      def where_has_field(field_name)
        where { |s| s.has_field?(field_name) }
      end

      def where_required_field(field_name)
        where { |s| s.required_fields.include?(field_name.to_sym) }
      end

      def unused
        where { |s| s.used_by_routes.empty? }
      end

      def search(query)
        query_lower = query.to_s.downcase
        where { |s| s.name.downcase.include?(query_lower) }
      end

      def field_usage
        all_fields = map(&:fields).flatten
        all_fields.each_with_object(Hash.new(0)) { |field, counts| counts[field] += 1 }
      end

      def names
        map(&:name)
      end
    end

    class MiddlewareCollection < Collection
      def builtin
        where { |m| m.builtin? }
      end

      def custom
        where { |m| !m.builtin? }
      end

      def find_by_class_name(class_name)
        find_by(class_name: class_name)
      end

      def chain_order
        sort_by(&:position)
      end

      def class_names
        map(&:class_name)
      end
    end
  end
end
