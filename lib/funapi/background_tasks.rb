# frozen_string_literal: true

module FunApi
  class BackgroundTasks
    def initialize(task = nil)
      @task = task
      @tasks = []
    end

    def add_task(callable, *args, **kwargs)
      @tasks << {callable: callable, args: args, kwargs: kwargs}
      nil
    end

    def execute
      @tasks.each do |task_def|
        invoke(task_def)
      rescue => e
        warn "Background task failed: #{e.class} - #{e.message}"
        warn e.backtrace.first(3).join("\n") if e.backtrace
      end
    end

    def empty?
      @tasks.empty?
    end

    def size
      @tasks.size
    end

    private

    def invoke(task_def)
      callable = task_def[:callable]
      args = task_def[:args]
      kwargs = task_def[:kwargs]

      unless callable.respond_to?(:call)
        raise ArgumentError, "Task must be callable, got #{callable.class}"
      end

      if kwargs.empty?
        callable.call(*args)
      else
        callable.call(*args, **kwargs)
      end
    end
  end
end
