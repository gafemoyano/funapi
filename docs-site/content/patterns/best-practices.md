---
title: Best Practices
---

# Async Best Practices

FunApi runs on Falcon, an async HTTP server using Ruby's fiber-based concurrency. This guide covers patterns to write safe, performant async code.

## Understanding Fibers

FunApi uses **cooperative multitasking** via fibers. Key points:

- Fibers yield control at I/O points (network, file, sleep)
- Multiple fibers run on the same thread
- No preemption - a fiber runs until it yields
- Context switches are explicit and predictable

```ruby
api.get '/example' do |input, req, task|
  # This fiber runs until...
  data = fetch_from_api  # ...it hits I/O (yields to other fibers)
  process(data)          # continues after I/O completes
  [{ result: data }, 200]
end
```

## Bound Your Concurrency

### The Problem: Unbounded Tasks

```ruby
# DANGEROUS: Could spawn thousands of tasks
api.post '/process-all' do |input, req, task|
  items = input[:body][:items]  # Could be 10,000 items!
  
  items.each do |item|
    task.async { process(item) }  # Unbounded!
  end
  
  [{ok: true}, 200]
end
```

This can overwhelm:
- Database connection pools
- External API rate limits
- Memory (each task has overhead)
- The scheduler itself

### Solution: Use Semaphore

```ruby
api.post '/process-all' do |input, req, task|
  items = input[:body][:items]
  semaphore = Async::Semaphore.new(10)  # Max 10 concurrent
  
  results = items.map do |item|
    semaphore.async { process(item) }
  end.map(&:wait)
  
  [{ results: results }, 200]
end
```

### Rule of Thumb

| Scenario | Concurrency Limit |
|----------|-------------------|
| Database queries | Pool size (typically 5-10) |
| External HTTP APIs | Check rate limits (often 10-50) |
| File operations | 10-20 |
| CPU-bound work | CPU cores |

## Use Timeouts

Every external call should have a timeout:

```ruby
api.get '/external' do |input, req, task|
  # Overall request timeout
  task.with_timeout(30) do
    # Individual operation timeout
    data = task.with_timeout(5) do
      fetch_from_slow_service
    end
    
    [{ data: data }, 200]
  end
rescue Async::TimeoutError
  raise FunApi::HTTPException.new(
    status_code: 504,
    detail: "Request timeout"
  )
end
```

### Timeout Hierarchy

```ruby
task.with_timeout(30) do  # Overall: 30s
  a = task.async do
    task.with_timeout(10) { fetch_a }  # Individual: 10s
  end
  
  b = task.async do
    task.with_timeout(10) { fetch_b }  # Individual: 10s
  end
  
  [a.wait, b.wait]
end
```

## Avoid Blocking Operations

### Fiber-Safe vs Blocking

| Fiber-Safe | Blocking (Avoid) |
|-----------|------------------|
| `sleep(n)` in async context | C extensions without GVL release |
| `Async::HTTP` | `Net::HTTP` without async wrapper |
| `db-postgres`, `async-mysql` | Blocking database drivers |
| `Async::IO` file operations | Heavy CPU computation |

### Detecting Blocking Code

If a request "freezes" other requests, you likely have blocking code:

```ruby
# This blocks ALL requests on the worker
api.get '/block' do |input, req, task|
  # CPU-intensive - no yield points
  (1..1_000_000).reduce(:+)
  
  [{result: 'done'}, 200]
end
```

### Solutions for Blocking Code

1. **Offload to background job** (Sidekiq, etc.)
2. **Use thread pool** for CPU work
3. **Break into chunks** with explicit yields

```ruby
# Option 3: Chunked with yields
api.get '/compute' do |input, req, task|
  result = 0
  (1..1_000_000).each_slice(10_000) do |chunk|
    result += chunk.reduce(:+)
    task.yield  # Let other fibers run
  end
  
  [{ result: result }, 200]
end
```

## Fiber-Local Storage

Use `Fiber[:key]` for request-scoped data:

```ruby
# CORRECT: Fiber-local (per-request)
Fiber[:current_user] = user
Fiber[:request_id] = SecureRandom.uuid

# WRONG: Thread-local (shared across requests!)
Thread.current[:user] = user  # Multiple fibers share threads!
```

### Why Thread.current is Dangerous

```
Thread 1
├── Fiber A (Request 1): Thread.current[:user] = "alice"
├── Fiber B (Request 2): Thread.current[:user] = "bob"    # Overwrites!
└── Fiber A continues:   Thread.current[:user] == "bob"   # Wrong user!
```

## Connection Pools

### Database Connections

Always use connection pools sized for your concurrency:

```ruby
# Sequel with connection pool
DB = Sequel.connect(
  'postgres://...',
  max_connections: 10  # Match your semaphore limits
)

api.post '/batch' do |input, req, task|
  semaphore = Async::Semaphore.new(10)  # Same as pool size
  
  items.map do |item|
    semaphore.async { DB[:items].insert(item) }
  end.map(&:wait)
end
```

### HTTP Client Pools

```ruby
# Create client once, reuse
HTTP_CLIENT = Async::HTTP::Client.new(
  Async::HTTP::Endpoint.parse('https://api.example.com')
)

api.get '/fetch' do |input, req, task|
  response = HTTP_CLIENT.get('/data')
  [{ data: response.read }, 200]
end
```

## Error Handling Patterns

### Fail-Fast with Barrier

```ruby
barrier = Async::Barrier.new

begin
  barrier.async { might_fail_1 }
  barrier.async { might_fail_2 }
  barrier.wait
rescue => e
  barrier.stop  # Cancel remaining tasks
  raise
end
```

### Collect All Errors

```ruby
errors = []
results = []

items.each do |item|
  semaphore.async do
    results << process(item)
  rescue => e
    errors << { item: item, error: e.message }
  end
end

semaphore.wait

if errors.any?
  [{ partial_results: results, errors: errors }, 207]
else
  [{ results: results }, 200]
end
```

### Graceful Degradation

```ruby
api.get '/dashboard' do |input, req, task|
  core_data = fetch_core_data  # Required
  
  # Optional enrichment - don't fail if these timeout
  extras = {}
  
  task.async do
    task.with_timeout(2) do
      extras[:recommendations] = fetch_recommendations
    end
  rescue Async::TimeoutError
    extras[:recommendations] = []
  end.wait

  [{ data: core_data, **extras }, 200]
end
```

## Anti-Patterns

### Never Use `Timeout.timeout`

```ruby
# DANGEROUS: Can corrupt state
Timeout.timeout(5) do  
  database_operation  # Might be interrupted mid-transaction!
end

# SAFE: Use async timeouts
task.with_timeout(5) do
  database_operation  # Yields cleanly at I/O points
end
```

### Don't Share Mutable State

```ruby
# WRONG: Shared mutable state
@cache = {}

api.get '/cached/:key' do |input, req, task|
  key = input[:path]['key']
  @cache[key] ||= expensive_fetch(key)  # Race condition!
end

# BETTER: Use Concurrent::Map or per-request state
require 'concurrent'
@cache = Concurrent::Map.new

api.get '/cached/:key' do |input, req, task|
  key = input[:path]['key']
  @cache.compute_if_absent(key) { expensive_fetch(key) }
end
```

### Don't Create Tasks You Don't Wait For

```ruby
# WRONG: Fire-and-forget orphan tasks
api.post '/fire' do |input, req, task|
  task.async { send_email }  # Never waited!
  [{ok: true}, 200]
end

# CORRECT: Use background tasks
api.post '/fire' do |input, req, task, background:|
  background.add_task(-> { send_email })
  [{ok: true}, 200]
end
```

## Performance Tips

### Batch Database Queries

```ruby
# SLOW: N+1 queries
users.map do |user|
  task.async { User.find(user.id) }
end

# FAST: Single query
User.where(id: users.map(&:id))
```

### Reuse Connections

```ruby
# SLOW: New connection per request
api.get '/data' do |input, req, task|
  client = Async::HTTP::Client.new(endpoint)
  client.get('/path')
  client.close
end

# FAST: Shared client
CLIENT = Async::HTTP::Client.new(endpoint)

api.get '/data' do |input, req, task|
  CLIENT.get('/path')
end
```

### Profile Before Optimizing

Use `Async::Task#annotate` for debugging:

```ruby
api.get '/slow' do |input, req, task|
  task.annotate "Fetching user data"
  user = fetch_user
  
  task.annotate "Processing results"
  result = process(user)
  
  [result, 200]
end
```

## Summary

| Do | Don't |
|----|-------|
| Use `Async::Semaphore` for bounded concurrency | Spawn unlimited tasks |
| Use `task.with_timeout` | Use `Timeout.timeout` |
| Use `Fiber[:key]` for request state | Use `Thread.current[:key]` |
| Use connection pools | Create connections per request |
| Wait for all spawned tasks | Fire-and-forget tasks |
| Use fiber-aware libraries | Use blocking C extensions |

## Further Reading

- [Async Gem Documentation](https://socketry.github.io/async/)
- [Falcon Server](https://socketry.github.io/falcon/)
- [Async Best Practices](https://socketry.github.io/async/guides/best-practices/)
