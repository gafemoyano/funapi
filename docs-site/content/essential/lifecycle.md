---
title: Lifecycle
---

# Lifecycle

Lifecycle hooks let you run code when your application starts up or shuts down.

## Startup Hooks

Run code before the server accepts requests:

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
end
```

### Use Cases

- Database connection pool initialization
- Cache warming
- Loading configuration
- Starting background workers
- Metrics/logging initialization

## Shutdown Hooks

Run code when the server stops:

```ruby
app = FunApi::App.new do |api|
  api.on_shutdown do
    puts "Closing database connections..."
    DB.disconnect
  end

  api.on_shutdown do
    puts "Flushing metrics..."
    Metrics.flush
  end
end
```

### Use Cases

- Graceful database disconnection
- Flushing buffers/queues
- Stopping background workers
- Cleanup of temporary files

## Multiple Hooks

You can register multiple hooks of each type. They run in registration order:

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    puts "1. First startup hook"
  end

  api.on_startup do
    puts "2. Second startup hook"
  end

  api.on_shutdown do
    puts "1. First shutdown hook"
  end

  api.on_shutdown do
    puts "2. Second shutdown hook"
  end
end
```

## Error Handling

### Startup Errors

If a startup hook raises an error, the server won't start:

```ruby
api.on_startup do
  raise "Database unavailable"
  # Server fails to start
end
```

### Shutdown Errors

Shutdown hook errors are logged but don't stop other hooks:

```ruby
api.on_shutdown do
  raise "Cleanup failed"
  # Error logged, but next hook still runs
end

api.on_shutdown do
  puts "This still runs"
end
```

## Complete Example

```ruby
require 'funapi'
require 'funapi/server/falcon'

app = FunApi::App.new(title: "My API") do |api|
  api.on_startup do
    puts "Starting up..."
    $db = Database.connect(ENV['DATABASE_URL'])
    $cache = Cache.new
    $cache.warm
    puts "Ready!"
  end

  api.on_shutdown do
    puts "Shutting down..."
    $cache.flush
    $db.disconnect
    puts "Goodbye!"
  end

  api.get '/health' do |input, req, task|
    [{ status: 'ok', db: $db.connected? }, 200]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

## With Dependencies

Combine lifecycle hooks with dependency injection:

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    db_pool = ConnectionPool.new(size: 10) { Database.connect }
    api.register(:db) { db_pool.checkout }
  end

  api.on_shutdown do
    api.resolve(:db).close_all
  end

  api.get '/users', depends: [:db] do |input, req, task, db:|
    [{ users: db.query("SELECT * FROM users") }, 200]
  end
end
```
