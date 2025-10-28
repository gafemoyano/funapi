# frozen_string_literal: true

module FunApi
  class Depends
    attr_reader :callable, :sub_dependencies

    def initialize(callable, **sub_dependencies)
      @callable = callable
      @sub_dependencies = sub_dependencies

      validate_callable!
    end

    def call(context, cache = {})
      cache_key = object_id

      return cache[cache_key] if cache.key?(cache_key)

      resolved_deps, sub_cleanups = resolve_sub_dependencies(context, cache)
      available_context = context.merge(resolved_deps)

      result, cleanup = execute_callable(available_context)

      combined_cleanup = if sub_cleanups.any? || cleanup
                           lambda {
                             sub_cleanups.each(&:call)
                             cleanup&.call
                           }
                         end

      final_result = [result, combined_cleanup]
      cache[cache_key] = final_result
      final_result
    end

    private

    def validate_callable!
      return if @callable.respond_to?(:call)

      raise ArgumentError, 'Dependency must be callable (respond to :call)'
    end

    def resolve_sub_dependencies(context, cache)
      cleanups = []

      resolved = @sub_dependencies.transform_values do |dep|
        result = if dep.is_a?(Depends)
                   dep.call(context, cache)
                 elsif dep.is_a?(Symbol)
                   container = context[:container]
                   unless container && container.respond_to?(:resolve)
                     raise ArgumentError, "Cannot resolve symbol dependency :#{dep} without container in context"
                   end

                   wrapper = container.resolve(dep)
                   resource = wrapper.call
                   [resource, nil]

                 elsif dep.respond_to?(:call)
                   Depends.new(dep).call(context, cache)
                 else
                   [dep, nil]
                 end

        resource, cleanup = if result.is_a?(Array) && result.length == 2
                              result
                            else
                              [result, nil]
                            end

        cleanups << cleanup if cleanup
        resource
      end

      [resolved, cleanups]
    end

    def extract_resource_and_cleanup_from_result(result)
      if result.is_a?(Array) && result.length == 2 && result[1].respond_to?(:call)
        result
      else
        [result, nil]
      end
    end

    def execute_callable(context)
      params = extract_params(context)

      result = if params.any?
                 @callable.call(**params)
               else
                 @callable.call
               end

      handle_result(result)
    end

    def extract_params(context)
      parameters = callable_parameters
      return {} unless parameters

      params = {}

      parameters.each do |type, name|
        next unless %i[keyreq key].include?(type)

        if context.key?(name)
          params[name] = context[name]
        elsif type == :keyreq
          raise ArgumentError, "missing keyword: :#{name}"
        end
      end

      params
    end

    def callable_parameters
      if @callable.respond_to?(:parameters)
        @callable.parameters
      elsif @callable.respond_to?(:method)
        @callable.method(:call).parameters
      end
    end

    def handle_result(result)
      if result.is_a?(Array) && result.length == 2 && result[1].respond_to?(:call)
        result
      else
        [result, nil]
      end
    end
  end

  def self.Depends(callable, **sub_dependencies)
    Depends.new(callable, **sub_dependencies)
  end
end
