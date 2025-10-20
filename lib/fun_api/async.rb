# # frozen_string_literal: true

# module FunApi
#   # Async utilities for concurrent execution within route handlers
#   module AsyncHelpers
#     class NoAsyncContextError < StandardError; end

#     # Execute multiple async operations concurrently
#     # Returns a hash with the same keys, values resolved from the callables
#     def concurrent(**tasks)
#       # For now, execute sequentially - we can optimize this later
#       results = {}
#       tasks.each do |key, callable|
#         results[key] = callable.call
#       end
#       results
#     end

#     # Execute multiple async operations concurrently with block syntax
#     def concurrent_block
#       # For now, just execute the block
#       yield(MockTask.new)
#     end

#     # Set a timeout for an async operation
#     def timeout(_duration, &block)
#       # For now, just execute without timeout
#       block.call
#     end

#     # Access the current async task (for advanced usage)
#     def current_task
#       Fiber[:async_task] || MockTask.new
#     end

#     # Mock task for development
#     class MockTask
#       def async(&block)
#         MockFiber.new(&block)
#       end

#       def sleep(duration)
#         Kernel.sleep(duration)
#       end
#     end

#     class MockFiber
#       def initialize(&block)
#         @result = block.call
#       end

#       def wait
#         @result
#       end
#     end
#   end
# end
