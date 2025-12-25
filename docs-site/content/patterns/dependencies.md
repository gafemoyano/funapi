---
title: Dependencies
---

# Dependencies

Dependency injection lets you provide services to your handlers without global state.

## Registering Dependencies

Register dependencies in the app container:

```ruby
app = FunApi::App.new do |api|
  api.register(:db) { Database.connect }
  api.register(:logger) { Logger.new(STDOUT) }
  api.register(:mailer) { Mailer.new }
end
```

## Using Dependencies

Request dependencies with the `depends:` parameter:

```ruby
api.get '/users', depends: [:db] do |input, req, task, db:|
  users = db.query("SELECT * FROM users")
  [{ users: users }, 200]
end

api.post '/contact', depends: [:mailer, :logger] do |input, req, task, mailer:, logger:|
  logger.info("Sending contact email")
  mailer.send(input[:body])
  [{ sent: true }, 200]
end
```

## Dependency Cleanup

For resources that need cleanup (database connections, file handles), return a tuple:

```ruby
api.register(:db) do
  conn = Database.connect
  cleanup = -> { conn.close }
  [conn, cleanup]
end
```

The cleanup proc runs after the request completes.

## Block-Style Dependencies

For context-manager style cleanup (like Python's `with`):

```ruby
api.register(:transaction) do |yielder|
  db = Database.connect
  db.begin_transaction
  
  yielder.call(db)  # Yield the resource
  
  db.commit
rescue
  db.rollback
  raise
ensure
  db.close
end
```

## Per-Request Dependencies

Dependencies can access request context:

```ruby
api.register(:current_user) do
  # This runs fresh for each request
  User.find_by_token(request.headers['Authorization'])
end
```

## Depends Class

For complex dependency graphs, use `FunApi::Depends`:

```ruby
get_db = -> { Database.connect }
get_user = ->(db:) { db.find_user(current_token) }

api.get '/profile', depends: { 
  db: get_db, 
  user: FunApi.Depends(get_user, db: :db) 
} do |input, req, task, db:, user:|
  [{ user: user }, 200]
end
```

## Complete Example

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

app = FunApi::App.new(title: "My API") do |api|
  # Simple dependency
  api.register(:logger) { Logger.new(STDOUT) }
  
  # Dependency with cleanup
  api.register(:db) do
    conn = PG.connect(ENV['DATABASE_URL'])
    [conn, -> { conn.close }]
  end
  
  # Block-style dependency
  api.register(:transaction) do |yielder|
    conn = PG.connect(ENV['DATABASE_URL'])
    conn.exec("BEGIN")
    yielder.call(conn)
    conn.exec("COMMIT")
  rescue
    conn.exec("ROLLBACK")
    raise
  ensure
    conn.close
  end

  api.get '/users', depends: [:db, :logger] do |input, req, task, db:, logger:|
    logger.info("Fetching users")
    result = db.exec("SELECT * FROM users")
    [{ users: result.to_a }, 200]
  end

  api.post '/users', depends: [:transaction] do |input, req, task, transaction:|
    transaction.exec("INSERT INTO users (name) VALUES ($1)", [input[:body][:name]])
    [{ created: true }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```
