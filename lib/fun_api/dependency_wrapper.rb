# frozen_string_literal: true

module FunApi
  class SimpleDependency
    attr_reader :resource

    def initialize(resource)
      @resource = resource
    end

    def call
      @resource
    end

    def cleanup; end
  end

  class ManagedDependency
    attr_reader :resource, :cleanup_proc

    def initialize(resource, cleanup_proc)
      @resource = resource
      @cleanup_proc = cleanup_proc
    end

    def call
      @resource
    end

    def cleanup
      @cleanup_proc&.call
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
      return unless @fiber

      @fiber.resume if @fiber.alive?
    rescue FiberError
    end
  end
end
