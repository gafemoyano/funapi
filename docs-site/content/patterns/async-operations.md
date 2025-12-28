---
title: Async Operations
---

# Async Operations

FunApi is async-first. Every handler receives an `Async::Task` for concurrent operations.

## The Task Parameter

The third handler parameter is an `Async::Task`:

```ruby
api.get '/dashboard' do |input, req, task|
  # task is Async::Task.current
end
```

This task is your gateway to concurrent execution within the request lifecycle.

## Concurrent Fetches

Run multiple operations in parallel:

```ruby
api.get '/dashboard/:id' do |input, req, task|
  id = input[:path]['id']

  # These run concurrently
  user_task = task.async { fetch_user(id) }
  posts_task = task.async { fetch_posts(id) }
  stats_task = task.async { fetch_stats(id) }

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

When processing collections, limit concurrent operations to avoid overwhelming external services:

```ruby
api.post '/batch-process' do |input, req, task|
  items = input[:body][:items]
  
  # Limit to 5 concurrent operations
  semaphore = Async::Semaphore.new(5)
  
  results = items.map do |item|
    semaphore.async do
      process_item(item)
    end
  end.map(&:wait)

  [{ results: results }, 200]
end
```

## Task Groups with Barrier

Use `Async::Barrier` to manage groups of related tasks:

```ruby
api.get '/reports/:id' do |input, req, task|
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
api.post '/bulk-import' do |input, req, task|
  records = input[:body][:records]
  
  barrier = Async::Barrier.new
  semaphore = Async::Semaphore.new(10, parent: barrier)
  
  records.each do |record|
    semaphore.async do
      import_record(record)
    end
  end

  barrier.wait
  
  [{ imported: records.size }, 200]
end
```

## Error Handling

Handle errors from async operations:

```ruby
api.get '/data' do |input, req, task|
  primary = task.async { fetch_from_primary }
  fallback = task.async { fetch_from_fallback }

  begin
    [{ data: primary.wait }, 200]
  rescue => e
    # Primary failed, use fallback
    [{ data: fallback.wait, source: 'fallback' }, 200]
  end
end
```

### Error Handling with Barrier

```ruby
api.get '/resilient' do |input, req, task|
  barrier = Async::Barrier.new
  results = { errors: [] }

  sources = [:api_a, :api_b, :api_c]
  
  sources.each do |source|
    barrier.async do
      results[source] = fetch_from(source)
    rescue => e
      results[:errors] << { source: source, error: e.message }
    end
  end

  barrier.wait
  
  [results, 200]
end
```

## Timeouts

Add timeouts to operations:

```ruby
api.get '/external' do |input, req, task|
  result = task.with_timeout(5) do
    fetch_from_slow_api
  end
  
  [{ data: result }, 200]
rescue Async::TimeoutError
  raise FunApi::HTTPException.new(
    status_code: 504,
    detail: "External API timeout"
  )
end
```

### Nested Timeouts

```ruby
api.get '/multi-source' do |input, req, task|
  task.with_timeout(10) do  # Overall timeout
    primary = task.async do
      task.with_timeout(3) { fetch_primary }
    rescue Async::TimeoutError
      nil
    end

    secondary = task.async do
      task.with_timeout(3) { fetch_secondary }
    rescue Async::TimeoutError
      nil
    end

    [{ 
      primary: primary.wait,
      secondary: secondary.wait 
    }, 200]
  end
rescue Async::TimeoutError
  raise FunApi::HTTPException.new(
    status_code: 504,
    detail: "Request timeout"
  )
end
```

## Sleep

Use `Kernel#sleep` - it's non-blocking in async context:

```ruby
api.get '/delayed' do |input, req, task|
  sleep(1)  # Non-blocking in async context
  [{ message: 'Done' }, 200]
end
```

## Queues for Producer/Consumer

Use `Async::Queue` for coordinating work between tasks:

```ruby
api.post '/stream-process' do |input, req, task|
  queue = Async::Queue.new
  results = []

  # Producer
  producer = task.async do
    input[:body][:items].each do |item|
      queue.push(item)
    end
    queue.close
  end

  # Consumer
  consumer = task.async do
    while item = queue.pop
      results << process(item)
    end
  end

  producer.wait
  consumer.wait

  [{ results: results }, 200]
end
```

## Real-World Example

```ruby
api.get '/user/:id/feed' do |input, req, task|
  user_id = input[:path]['id']

  # Fetch user and check permissions first
  user = fetch_user(user_id)
  raise FunApi::HTTPException.new(status_code: 404) unless user

  # Then fetch feed data concurrently
  posts = task.async { Post.where(user_id: user_id).limit(20) }
  notifications = task.async { Notification.unread(user_id) }
  suggestions = task.async { RecommendationService.for(user_id) }

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

FunApi uses Ruby's [Async](https://github.com/socketry/async) library and [Falcon](https://github.com/socketry/falcon) server. The task parameter is the current `Async::Task`, giving you access to the full Async API.

```ruby
# These are equivalent
task.async { work }
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

See the [Best Practices](/patterns/best-practices) guide for more patterns.
