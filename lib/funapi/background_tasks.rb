# frozen_string_literal: true

module FunApi
  class BackgroundTasks
    def initialize(task)
      @task = task
      @tasks = []
    end

    def add_task(callable, *args, **kwargs)
      @tasks << {callable: callable, args: args, kwargs: kwargs}
      nil
    end

    def execute
      return if @tasks.empty?

      @tasks.each do |task_def|
        callable = task_def[:callable]
        args = task_def[:args]
        kwargs = task_def[:kwargs]

        @task.async do
          if callable.respond_to?(:call)
            if kwargs.empty?
              callable.call(*args)
            else
              callable.call(*args, **kwargs)
            end
          elsif callable.is_a?(Symbol)
            raise ArgumentError, "Cannot call Symbol #{callable} without a context object"
          else
            raise ArgumentError, "Task must be callable or Symbol, got #{callable.class}"
          end
        rescue => e
          warn "Background task failed: #{e.class} - #{e.message}"
          warn e.backtrace.first(3).join("\n") if e.backtrace
        end
      end

      @task.children.each(&:wait)
    end

    def empty?
      @tasks.empty?
    end

    def size
      @tasks.size
    end
  end
end
