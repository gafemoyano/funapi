# Lifecycle Hooks Implementation Plan

## Date: 2024-12-24

## Overview

Implement startup and shutdown lifecycle hooks for FunApi. These hooks allow users to run code before the server accepts requests and after it stops, useful for initializing/cleaning up resources like database connections, HTTP clients, and background task supervisors.

## Design Decision

**Approach**: Separate callbacks (`on_startup`/`on_shutdown`)

**Why callbacks over block/yield pattern**:
- Simpler implementation (~10 lines vs ~20 lines with Fibers)
- Multiple hooks are natural (common use case: init DB, cache, metrics separately)
- Familiar to Ruby developers (Rails, Sinatra patterns)
- Block pattern can be added later if demand exists

**Why NOT shared state between lifecycle and routes**:
- Async gems (Sequel, HTTP clients) manage their own connection pools
- Long-lived resources are typically singletons/constants
- Routes already have dependency injection for per-request resources
- Keeps implementation simple

## API Design

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    puts "Connecting to database..."
    DB.connect
  end
  
  api.on_startup do
    puts "Warming cache..."
    Cache.warm
  end
  
  api.on_shutdown do
    puts "Closing database..."
    DB.disconnect
  end
  
  api.get '/users' do |input, req, task|
    [DB[:users].all, 200]
  end
end
```

**Key behaviors**:
- Multiple hooks allowed (executed in registration order)
- Startup hooks run inside Async context, before server accepts requests
- Shutdown hooks run inside Async context, after server stops accepting requests
- Hooks can be async (have access to current Async::Task if needed)
- Errors in startup hooks should prevent server from starting
- Errors in shutdown hooks should be logged but not prevent other hooks from running

## Implementation

### 1. Application Changes (`lib/fun_api/application.rb`)

Add to `App` class:

```ruby
def initialize(...)
  # ... existing code ...
  @startup_hooks = []
  @shutdown_hooks = []
  
  yield self if block_given?
  # ... rest of existing code ...
end

def on_startup(&block)
  raise ArgumentError, "on_startup requires a block" unless block_given?
  @startup_hooks << block
  self
end

def on_shutdown(&block)
  raise ArgumentError, "on_shutdown requires a block" unless block_given?
  @shutdown_hooks << block
  self
end

def run_startup_hooks
  @startup_hooks.each(&:call)
end

def run_shutdown_hooks
  @shutdown_hooks.each do |hook|
    hook.call
  rescue => e
    warn "Shutdown hook failed: #{e.message}"
  end
end
```

### 2. Falcon Server Changes (`lib/fun_api/server/falcon.rb`)

```ruby
def self.start(app, host: "0.0.0.0", port: 3000)
  Async do |task|
    falcon_app = Protocol::Rack::Adapter.new(app)
    endpoint = ::Async::HTTP::Endpoint.parse("http://#{host}:#{port}")
    server = ::Falcon::Server.new(falcon_app, endpoint)

    # Run startup hooks
    app.run_startup_hooks if app.respond_to?(:run_startup_hooks)

    puts "Falcon listening on #{host}:#{port}"

    shutdown = -> {
      puts "\nShutting down..."
      app.run_shutdown_hooks if app.respond_to?(:run_shutdown_hooks)
      task.stop
    }

    trap(:INT) { shutdown.call }
    trap(:TERM) { shutdown.call }

    server.run
  end
end
```

### 3. Accessor for Hooks (for testing)

```ruby
# In Application class
attr_reader :startup_hooks, :shutdown_hooks
```

## Test Cases

Create `test/test_lifecycle.rb`:

```ruby
class TestLifecycle < Minitest::Test
  def test_on_startup_registers_hook
    app = FunApi::App.new do |api|
      api.on_startup { :startup }
    end
    
    assert_equal 1, app.startup_hooks.size
  end

  def test_on_shutdown_registers_hook
    app = FunApi::App.new do |api|
      api.on_shutdown { :shutdown }
    end
    
    assert_equal 1, app.shutdown_hooks.size
  end

  def test_multiple_startup_hooks
    app = FunApi::App.new do |api|
      api.on_startup { :first }
      api.on_startup { :second }
    end
    
    assert_equal 2, app.startup_hooks.size
  end

  def test_multiple_shutdown_hooks
    app = FunApi::App.new do |api|
      api.on_shutdown { :first }
      api.on_shutdown { :second }
    end
    
    assert_equal 2, app.shutdown_hooks.size
  end

  def test_run_startup_hooks_executes_in_order
    order = []
    app = FunApi::App.new do |api|
      api.on_startup { order << 1 }
      api.on_startup { order << 2 }
      api.on_startup { order << 3 }
    end
    
    app.run_startup_hooks
    
    assert_equal [1, 2, 3], order
  end

  def test_run_shutdown_hooks_executes_in_order
    order = []
    app = FunApi::App.new do |api|
      api.on_shutdown { order << 1 }
      api.on_shutdown { order << 2 }
    end
    
    app.run_shutdown_hooks
    
    assert_equal [1, 2], order
  end

  def test_shutdown_hook_error_does_not_stop_other_hooks
    order = []
    app = FunApi::App.new do |api|
      api.on_shutdown { order << 1 }
      api.on_shutdown { raise "error" }
      api.on_shutdown { order << 3 }
    end
    
    app.run_shutdown_hooks
    
    assert_equal [1, 3], order
  end

  def test_startup_hook_error_propagates
    app = FunApi::App.new do |api|
      api.on_startup { raise "startup failed" }
    end
    
    assert_raises(RuntimeError) { app.run_startup_hooks }
  end

  def test_on_startup_requires_block
    app = FunApi::App.new
    
    assert_raises(ArgumentError) { app.on_startup }
  end

  def test_on_shutdown_requires_block
    app = FunApi::App.new
    
    assert_raises(ArgumentError) { app.on_shutdown }
  end

  def test_on_startup_returns_self_for_chaining
    app = FunApi::App.new
    
    result = app.on_startup { :hook }
    
    assert_same app, result
  end

  def test_hooks_work_with_async_context
    order = []
    app = FunApi::App.new do |api|
      api.on_startup do
        Async do |task|
          task.sleep(0.001)
          order << :async_startup
        end.wait
      end
    end
    
    Async { app.run_startup_hooks }.wait
    
    assert_equal [:async_startup], order
  end
end
```

## Example Usage

Create `examples/lifecycle_demo.rb`:

```ruby
require_relative "../lib/fun_api"
require_relative "../lib/fun_api/server/falcon"

DB = { connected: false, users: [] }
CACHE = { warmed: false }

app = FunApi::App.new(
  title: "Lifecycle Demo",
  version: "1.0.0"
) do |api|
  api.on_startup do
    puts "Connecting to database..."
    sleep 0.1  # Simulate connection time
    DB[:connected] = true
    DB[:users] = [{id: 1, name: "Alice"}, {id: 2, name: "Bob"}]
    puts "Database connected!"
  end

  api.on_startup do
    puts "Warming cache..."
    sleep 0.05
    CACHE[:warmed] = true
    puts "Cache warmed!"
  end

  api.on_shutdown do
    puts "Closing database connection..."
    DB[:connected] = false
    puts "Database disconnected!"
  end

  api.on_shutdown do
    puts "Clearing cache..."
    CACHE[:warmed] = false
    puts "Cache cleared!"
  end

  api.get "/status" do |_input, _req, _task|
    [{
      db_connected: DB[:connected],
      cache_warmed: CACHE[:warmed]
    }, 200]
  end

  api.get "/users" do |_input, _req, _task|
    [DB[:users], 200]
  end
end

puts "Starting Lifecycle Demo..."
puts "Try: curl http://localhost:3000/status"
puts "Try: curl http://localhost:3000/users"
puts ""

FunApi::Server::Falcon.start(app, port: 3000)
```

## Files to Modify

1. `lib/fun_api/application.rb` - Add hook registration and execution methods
2. `lib/fun_api/server/falcon.rb` - Call hooks at appropriate times

## Files to Create

1. `test/test_lifecycle.rb` - Lifecycle hook tests
2. `examples/lifecycle_demo.rb` - Demo application

## Files to Update

1. `AGENTS.md` - Add lifecycle hooks documentation
2. `README.md` - Add lifecycle hooks section
3. `.claude/PROJECT_PLAN.md` - Mark lifecycle hooks as complete

## Documentation Updates

### AGENTS.md Addition

```markdown
### Lifecycle Hooks

Run code at startup/shutdown:
```ruby
api.on_startup do
  DB.connect
  Cache.warm
end

api.on_shutdown do
  DB.disconnect
end
```

- Multiple hooks allowed (run in registration order)
- Startup hooks run before server accepts requests
- Shutdown hooks run after server stops
- Shutdown errors logged but don't stop other hooks
```

### README.md Addition

```markdown
### 10. Lifecycle Hooks

Execute code when the application starts up or shuts down:

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    puts "Connecting to database..."
    DB.connect
  end
  
  api.on_startup do
    puts "Warming cache..."
    Cache.warm
  end
  
  api.on_shutdown do
    puts "Disconnecting..."
    DB.disconnect
  end
end
```

**Key behaviors:**
- Multiple hooks supported (executed in registration order)
- Startup hooks run before server accepts requests
- Shutdown hooks run after server stops accepting requests
- Startup errors prevent server from starting
- Shutdown errors are logged but don't prevent other hooks from running

**Use cases:**
- Database connection pool initialization
- Cache warming
- Background task supervisor setup
- Metrics/logging initialization
- Graceful resource cleanup
```

## Success Criteria

1. `on_startup` registers hooks that run before server accepts requests
2. `on_shutdown` registers hooks that run after server stops
3. Multiple hooks execute in registration order
4. Shutdown hook errors don't prevent other hooks from running
5. All tests pass
6. Linter passes
7. Demo example works correctly

## Estimated Effort

~1-2 hours

## Notes

- Keep implementation minimal - this is a simple feature
- Don't over-engineer (no priority system, no async hook detection, etc.)
- The Falcon server integration is the key piece - hooks must run inside Async context
- Consider: should hooks have access to the app instance? (Probably not needed for v1)
