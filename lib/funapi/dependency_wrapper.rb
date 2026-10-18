# frozen_string_literal: true

require "async"

module FunApi
  class CleanupRegistry
    def initialize
      @wrappers = []
    end

    def empty?
      @wrappers.empty?
    end

    def <<(wrapper)
      @wrappers << wrapper
    end

    def resolve_container(container, key, cache)
      cache_key = "container:#{key}"
      return cache[cache_key] if cache.key?(cache_key)

      wrapper = container.resolve(key)
      resource = wrapper.call
      self << wrapper
      cache[cache_key] = resource
    end

    def cleanup
      if (task = Async::Task.current?)
        task.defer_stop { drain }
      else
        drain
      end
    end

    private

    def drain
      result = nil
      while (wrapper = @wrappers.pop)
        begin
          result = wrapper.cleanup
        rescue StandardError, Async::Stop => error
          warn "Dependency cleanup failed: #{error.message}"
        end
      end
      result
    end
  end

  class ManagedDependency
    attr_reader :resource

    def initialize(resource, cleanup_proc = nil)
      @resource = resource
      @cleanup_proc = cleanup_proc
    end

    def call
      @resource
    end

    def cleanup
      cleanup_proc = @cleanup_proc
      @cleanup_proc = nil
      cleanup_proc&.call
    end
  end

  class BlockDependency
    def initialize(block)
      @block = block
      @fiber = nil
      @resource = nil
    end

    def call
      return @resource if @fiber

      @fiber = Fiber.new do
        result = nil
        @block.call(proc { |resource|
          result = resource
          Fiber.yield resource
        })
        result
      end

      @resource = @fiber.resume
      @resource
    end

    def cleanup
      return if !@fiber || @cleaned

      @cleaned = true
      @fiber.resume if @fiber.alive?
    rescue FiberError
    end
  end
end
