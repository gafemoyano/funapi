---
title: Async Operations
---

# Async Operations

FunApi is async-first. Handlers run inside an `Async::Task` on Falcon's fiber
reactor, so I/O-bound work can run concurrently without threads.

## Concurrency Helpers

Handlers take two arguments — `|input, req|`. You no longer receive (or need) a
task object. Spawn concurrent work with the module functions:

```ruby
api.get "/dashboard" do |input, req|
  user  = FunApi.async { fetch_user(input[:path][:id]) }
  posts = FunApi.async { fetch_posts(input[:path][:id]) }

  [{user: user.wait, posts: posts.wait}, 200]
end
```

- `FunApi.async { ... }` starts a concurrent child task and returns it; call
  `#wait` to get its result.
- `FunApi.sleep(seconds)` suspends the current fiber without blocking the reactor.

Both resolve the current task via `Fiber[:async_task]` / `Async::Task.current`,
so handler code never touches an event-loop handle.

> The old three-argument form `|input, req, task|` still works during the
> deprecation window, but new code should use `FunApi.async`.

## Concurrent Fetches

Run multiple operations in parallel:

```ruby
api.get "/dashboard/:id" do |input, req|
  id = input[:path][:id]

  # These run concurrently
  user_task  = FunApi.async { fetch_user(id) }
  posts_task = FunApi.async { fetch_posts(id) }
  stats_task = FunApi.async { fetch_stats(id) }

  # Wait for all to complete
  [{
    user: user_task.wait,
    posts: posts_task.wait,
    stats: stats_task.wait
  }, 200]
end
```

Without async, this would take `time(user) + time(posts) + time(stats)`.
With async, it takes `max(time(user), time(posts), time(stats))`.

## Bounded Concurrency with Semaphore

When processing collections, limit concurrent operations to avoid overwhelming
external services. `Async::Semaphore` is not loaded by `require "async"` alone,
so require it explicitly:

```ruby
require "async/semaphore"

api.post "/batch-process" do |input, req|
  items = input[:body][:items]

  # Limit to 5 concurrent operations
  semaphore = Async::Semaphore.new(5)

  results = items.map do |item|
    semaphore.async { process_item(item) }
  end.map(&:wait)

  [{results: results}, 200]
end
```

`Async::Semaphore`, `Async::Barrier`, and `Async::Queue` are standalone objects —
they spawn their own child tasks, so you construct them directly without a
handler task.

## Task Groups with Barrier

Use `Async::Barrier` to manage groups of related tasks:

```ruby
require "async/barrier"

api.get "/reports/:id" do |input, req|
  barrier = Async::Barrier.new
  results = {}

  barrier.async { results[:sales] = fetch_sales_report }
  barrier.async { results[:inventory] = fetch_inventory_report }
  barrier.async { results[:customers] = fetch_customer_report }

  barrier.wait  # Wait for all to complete

  [results, 200]
end
```

### Combining Barrier with Semaphore

For bounded concurrent processing of many items:

```ruby
api.post "/bulk-import" do |input, req|
  records = input[:body][:records]

  barrier = Async::Barrier.new
  semaphore = Async::Semaphore.new(10, parent: barrier)

  records.each do |record|
    semaphore.async { import_record(record) }
  end

  barrier.wait

  [{imported: records.size}, 200]
end
```

## Error Handling

Handle errors from async operations:

```ruby
api.get "/data" do |input, req|
  primary  = FunApi.async { fetch_from_primary }
  fallback = FunApi.async { fetch_from_fallback }

  begin
    [{data: primary.wait}, 200]
  rescue
    # Primary failed, use fallback
    [{data: fallback.wait, source: "fallback"}, 200]
  end
end
```

### Error Handling with Barrier

```ruby
api.get "/resilient" do |input, req|
  barrier = Async::Barrier.new
  results = {errors: []}

  %i[api_a api_b api_c].each do |source|
    barrier.async do
      results[source] = fetch_from(source)
    rescue => e
      results[:errors] << {source: source, error: e.message}
    end
  end

  barrier.wait

  [results, 200]
end
```

## Timeouts

Every handler runs inside `Async::Task.current`, which exposes `with_timeout`:

```ruby
api.get "/external" do |input, req|
  result = Async::Task.current.with_timeout(5) do
    fetch_from_slow_api
  end

  [{data: result}, 200]
rescue Async::TimeoutError
  raise FunApi::HTTPException.new(status_code: 504, detail: "External API timeout")
end
```

## Sleep

Use `FunApi.sleep` — it suspends the fiber without blocking the reactor:

```ruby
api.get "/delayed" do |input, req|
  FunApi.sleep(1)
  [{message: "Done"}, 200]
end
```

## Queues for Producer/Consumer

Use `Async::Queue` for coordinating work between tasks:

```ruby
require "async/queue"

api.post "/stream-process" do |input, req|
  queue = Async::Queue.new
  results = []

  producer = FunApi.async do
    input[:body][:items].each { |item| queue.push(item) }
    queue.close
  end

  consumer = FunApi.async do
    while (item = queue.pop)
      results << process(item)
    end
  end

  producer.wait
  consumer.wait

  [{results: results}, 200]
end
```

## Real-World Example

```ruby
api.get "/user/:id/feed" do |input, req|
  user_id = input[:path][:id]

  # Fetch user and check permissions first
  user = fetch_user(user_id)
  raise FunApi::HTTPException.new(status_code: 404) unless user

  # Then fetch feed data concurrently
  posts         = FunApi.async { Post.where(user_id: user_id).limit(20) }
  notifications = FunApi.async { Notification.unread(user_id) }
  suggestions   = FunApi.async { RecommendationService.for(user_id) }

  [{
    user: user,
    posts: posts.wait,
    notifications: notifications.wait,
    suggestions: suggestions.wait
  }, 200]
end
```

## When to Use Async

**Good candidates:**
- Multiple independent database queries
- External API calls
- File I/O operations
- Any I/O-bound work

**Not needed for:**
- CPU-bound calculations
- Single database query
- Simple transformations

## Technical Details

FunApi uses Ruby's [Async](https://github.com/socketry/async) library and
[Falcon](https://github.com/socketry/falcon) server. `FunApi.async` delegates to
the current `Async::Task`, giving you the full Async API when you need it.

```ruby
# These are equivalent
FunApi.async { work }
Async::Task.current.async { work }
```

### Key Classes

| Class | Purpose |
|-------|---------|
| `Async::Task` | Unit of concurrent execution |
| `Async::Barrier` | Wait for multiple tasks to complete |
| `Async::Semaphore` | Limit concurrent task count |
| `Async::Queue` | Thread-safe queue for task coordination |
| `Async::Notification` | Signal between tasks |

See the [Streaming](/patterns/streaming) guide for SSE and WebSockets, and the
[Best Practices](/patterns/best-practices) guide for more patterns.
</content>
