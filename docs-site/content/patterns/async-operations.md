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

## Sleep

Use `Kernel#sleep` (not `task.sleep`):

```ruby
api.get '/delayed' do |input, req, task|
  sleep(1)  # Non-blocking in async context
  [{ message: 'Done' }, 200]
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
