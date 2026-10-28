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
api.get '/users', depends: [:db] do |input, req, db:|
  users = db.query("SELECT * FROM users")
  [{ users: users }, 200]
end

api.post '/contact', depends: [:mailer, :logger] do |input, req, mailer:, logger:|
  logger.info("Sending contact email")
  mailer.send(input[:body])
  [{ sent: true }, 200]
end
```

## Dependency Cleanup (Preferred: Block Form)

For resources that need cleanup (database connections, file handles), use the
block form. Call `provide` with the resource and put teardown in `ensure` — the
same idiom as `File.open` or Python's `with`:

```ruby
api.register(:db) do |provide|
  conn = Database.connect
  provide.call(conn)
ensure
  conn.close
end
```

The `ensure` block runs after the response has been sent, and `ensure`
guarantees cleanup even when the handler raises. This is the recommended way to
manage resource lifecycles.

For transaction-style semantics you can run code after `provide.call` returns:

```ruby
api.register(:transaction) do |provide|
  db = Database.connect
  db.begin_transaction

  provide.call(db)  # Yield the resource to the handler

  db.commit
rescue
  db.rollback
  raise
ensure
  db.close
end
```

### Tuple Form (Legacy)

> **Deprecated**: The `[resource, cleanup]` tuple form is still supported for
> backward compatibility, but the block form above is preferred.

```ruby
api.register(:db) do
  conn = Database.connect
  cleanup = -> { conn.close }
  [conn, cleanup]
end
```

The cleanup proc runs after the request completes.

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
} do |input, req, db:, user:|
  [{ user: user }, 200]
end
```

## Complete Example

```ruby
require 'funapi'
require 'funapi/server/falcon'

app = FunApi::App.new(title: "My API") do |api|
  # Simple dependency
  api.register(:logger) { Logger.new(STDOUT) }
  
  # Dependency with cleanup (block form)
  api.register(:db) do |provide|
    conn = PG.connect(ENV['DATABASE_URL'])
    provide.call(conn)
  ensure
    conn.close
  end

  # Transaction-style dependency
  api.register(:transaction) do |provide|
    conn = PG.connect(ENV['DATABASE_URL'])
    conn.exec("BEGIN")
    provide.call(conn)
    conn.exec("COMMIT")
  rescue
    conn.exec("ROLLBACK")
    raise
  ensure
    conn.close
  end

  api.get '/users', depends: [:db, :logger] do |input, req, db:, logger:|
    logger.info("Fetching users")
    result = db.exec("SELECT * FROM users")
    [{ users: result.to_a }, 200]
  end

  api.post '/users', depends: [:transaction] do |input, req, transaction:|
    transaction.exec("INSERT INTO users (name) VALUES ($1)", [input[:body][:name]])
    [{ created: true }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```
