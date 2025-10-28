# Background Tasks Analysis for FunAPI

## Executive Summary

After extensive testing of Ruby's Async gem, **we can implement background tasks with ZERO abstraction** - users can simply use `Async(task) do ... end` to spawn fire-and-forget tasks. However, there's a critical **dependency cleanup issue** that makes a lightweight `BackgroundTasks` abstraction valuable.

## Key Findings

### Python vs Ruby: Task Lifecycle

**Python (asyncio):**
- `asyncio.create_task()` returns immediately without waiting
- Tasks can be "orphaned" if not explicitly awaited
- This is WHY FastAPI needs `BackgroundTasks` - to ensure tasks complete before process exits

**Ruby (Async gem):**
- `task.async { }` creates a child task that IS tracked by parent
- Parent waits for children when block ends (via `Async do ... end.wait`)
- `Async(parent) { }` creates a DETACHED task (truly fire-and-forget)

### The Critical Problem: Dependency Cleanup

```ruby
Async do |task|
  begin
    db = Database.connect
    
    # User spawns background task
    Async(task) do
      sleep 0.1
      send_email(db)  # DB is captured in closure
    end
    
    [response, 200]
    
  ensure
    db.close  # RUNS BEFORE background task!
  end
end
```

**Timeline:**
1. Request handler starts
2. Response returned
3. **ensure block runs → DB closed**
4. Background task tries to use DB (might work due to closure, but semantically wrong)

### Solution Options

#### Option 1: No Abstraction (Pure Async)

```ruby
api.post '/notify' do |input, req, task|
  email = input[:body][:email]
  
  # Detached background task
  Async(task) do
    send_welcome_email(email)
  end
  
  [{ message: "Sent" }, 200]
end
```

**Pros:**
- Zero magic, pure Ruby Async
- No new API to learn
- Explicit and clear

**Cons:**
- ❌ Runs AFTER dependency cleanup
- ❌ Dependencies might be closed when task runs
- ❌ No FastAPI parity
- ❌ No task collection/management

#### Option 2: BackgroundTasks Object (Recommended)

```ruby
api.post '/notify' do |input, req, task, background:|
  email = input[:body][:email]
  
  background.add_task(:send_welcome_email, email)
  
  [{ message: "Sent" }, 200]
end
```

**Implementation ensures correct execution order:**
1. Handler returns response tuple
2. **Background tasks execute** (with dependencies still available)
3. Dependency cleanup in ensure block
4. Response sent to client

**Pros:**
- ✅ Tasks run BEFORE dependency cleanup
- ✅ FastAPI API parity
- ✅ Dependencies guaranteed available
- ✅ Can inject dependencies into background tasks
- ✅ Error handling for task failures
- ✅ Testing/introspection support

**Cons:**
- Small abstraction needed (~50 lines)

## Recommended Implementation

### BackgroundTasks Class

```ruby
module FunApi
  class BackgroundTasks
    def initialize(task, context)
      @task = task
      @context = context
      @tasks = []
    end
    
    def add_task(callable, *args, **kwargs)
      @tasks << { callable: callable, args: args, kwargs: kwargs }
    end
    
    def execute
      @tasks.each do |task_def|
        callable = task_def[:callable]
        args = task_def[:args]
        kwargs = task_def[:kwargs]
        
        # Spawn as child task (not detached)
        @task.async do
          if callable.respond_to?(:call)
            callable.call(*args, **kwargs)
          elsif callable.is_a?(Symbol) && @context.respond_to?(callable)
            @context.public_send(callable, *args, **kwargs)
          end
        rescue => e
          warn "Background task failed: #{e.message}"
        end
      end
      
      # Wait for all background tasks to complete
      @task.children.each(&:wait)
    end
  end
end
```

### Modified Request Flow

```ruby
def handle_async_route(req, path_params, body_schema, query_schema, response_schema, dependencies, &blk)
  current_task = Async::Task.current
  cleanup_objects = []
  background_tasks = BackgroundTasks.new(current_task, self)

  begin
    # ... input validation ...
    # ... dependency resolution ...
    
    resolved_deps[:background] = background_tasks
    
    payload, status = blk.call(input, req, current_task, **resolved_deps)
    
    # Execute background tasks BEFORE ensure
    background_tasks.execute
    
    # ... response building ...
    
  ensure
    cleanup_objects.each(&:cleanup)
  end
end
```

### Execution Order

```
1. Request arrives
2. Dependencies resolved (DB connect, etc.)
3. Route handler executes
4. Handler returns [payload, status]
5. ⭐ Background tasks execute (deps still available)
6. Background tasks complete
7. Dependencies cleaned up (DB close, etc.)
8. Response tuple returned
9. HTTP layer sends response to client
```

## Use Cases

### Perfect For:
- Email notifications after signup
- Logging/analytics after request
- Cache warming
- Simple webhook calls
- Audit trail recording

### NOT For:
- Long-running jobs (> 30 seconds)
- Jobs requiring persistence/retries
- Jobs that must survive server restart
- Distributed job processing
→ Use Sidekiq, GoodJob, or Que instead

## API Design

### As Dependency (Recommended)

```ruby
api.post '/signup', body: UserSchema do |input, req, task, background:|
  user = create_user(input[:body])
  
  background.add_task(:send_welcome_email, user[:email])
  background.add_task(:notify_admin, user)
  
  [user, 201]
end
```

### With Callable Objects

```ruby
background.add_task(method(:send_email), to: user[:email])
background.add_task(lambda { |id| log_event(id) }, user[:id])
```

### With Dependencies

```ruby
api.register(:mailer) { Mailer.new }

api.post '/signup', depends: [:mailer] do |input, req, task, mailer:, background:|
  user = create_user(input[:body])
  
  # Background task can use mailer (captured in closure)
  background.add_task(lambda { mailer.send_welcome(user[:email]) })
  
  [user, 201]
end
```

## Comparison to FastAPI

### FastAPI
```python
from fastapi import BackgroundTasks

@app.post("/send-notification/{email}")
async def notify(email: str, background_tasks: BackgroundTasks):
    background_tasks.add_task(send_email, email, message="Hi")
    return {"message": "Sent"}
```

### FunAPI
```ruby
api.post '/send-notification/:email' do |input, req, task, background:|
  email = input[:path]['email']
  background.add_task(:send_email, email, message: "Hi")
  [{ message: "Sent" }, 200]
end
```

**Nearly identical!** ✨

## Testing Strategy

```ruby
class TestBackgroundTasks < Minitest::Test
  def test_background_tasks_execute_after_response
    execution_order = []
    
    app = FunApi::App.new do |api|
      api.post '/test' do |input, req, task, background:|
        execution_order << :handler
        
        background.add_task(lambda { execution_order << :background })
        
        [{ ok: true }, 200]
      end
    end
    
    res = async_request(app, :post, '/test')
    
    assert_equal [:handler, :background], execution_order
    assert_equal 200, res.status
  end
  
  def test_background_tasks_can_access_dependencies
    # Test that DB is still available in background task
  end
  
  def test_background_task_errors_are_handled
    # Test that task errors don't crash app
  end
end
```

## Recommendation: Implement BackgroundTasks

**Why:**
1. ✅ Correct execution order (before dependency cleanup)
2. ✅ FastAPI API parity
3. ✅ Safe dependency access
4. ✅ Better error handling
5. ✅ Testable and introspectable
6. ✅ Small implementation (~50-80 lines)

**Why not "no API":**
1. ❌ `Async(task) { }` runs AFTER cleanup
2. ❌ Dependencies might be closed
3. ❌ No error handling
4. ❌ Harder to test
5. ❌ Less discoverable

## Next Steps

1. Implement `BackgroundTasks` class
2. Modify `handle_async_route` to inject and execute
3. Write comprehensive tests
4. Create examples (email, logging, webhooks)
5. Update docs (README, AGENTS.md)
6. Consider dependency injection into background tasks

**Estimated effort:** 2-3 hours
**Impact:** High - production-critical feature
**Complexity:** Low - leverages existing Async infrastructure
