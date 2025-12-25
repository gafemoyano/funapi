---
title: Database
---

# Database

FunApi works with any database library. Here's how to integrate common options.

## With db-postgres

[db-postgres](https://github.com/socketry/db-postgres) is async-native and works great with FunApi:

```ruby
require 'fun_api'
require 'db/postgres'
require 'fun_api/server/falcon'

app = FunApi::App.new do |api|
  api.on_startup do
    $db = DB::Postgres::Connection.new(
      host: 'localhost',
      database: 'myapp',
      user: 'postgres'
    )
  end

  api.on_shutdown do
    $db&.close
  end

  api.get '/users' do |input, req, task|
    result = $db.query("SELECT id, name, email FROM users")
    [{ users: result.to_a }, 200]
  end
end
```

## With Sequel

[Sequel](https://sequel.jeremyevans.net/) is a powerful database toolkit:

```ruby
require 'fun_api'
require 'sequel'
require 'fun_api/server/falcon'

DB = Sequel.connect(ENV['DATABASE_URL'])

app = FunApi::App.new do |api|
  api.get '/users' do |input, req, task|
    users = DB[:users].all
    [{ users: users }, 200]
  end

  api.get '/users/:id' do |input, req, task|
    user = DB[:users].where(id: input[:path]['id']).first
    raise FunApi::HTTPException.new(status_code: 404) unless user
    [{ user: user }, 200]
  end

  api.post '/users', body: UserSchema do |input, req, task|
    id = DB[:users].insert(input[:body])
    user = DB[:users].where(id: id).first
    [{ user: user }, 201]
  end
end
```

## With ActiveRecord

You can use ActiveRecord standalone (without Rails):

```ruby
require 'fun_api'
require 'active_record'
require 'fun_api/server/falcon'

ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])

class User < ActiveRecord::Base
end

app = FunApi::App.new do |api|
  api.get '/users' do |input, req, task|
    users = User.all.map(&:attributes)
    [{ users: users }, 200]
  end

  api.post '/users', body: UserSchema do |input, req, task|
    user = User.create!(input[:body])
    [{ user: user.attributes }, 201]
  end
end
```

## Connection Pooling with Dependencies

Use dependency injection for connection management:

```ruby
require 'connection_pool'

app = FunApi::App.new do |api|
  pool = ConnectionPool.new(size: 10) do
    PG.connect(ENV['DATABASE_URL'])
  end

  api.register(:db) do
    conn = pool.checkout
    [conn, -> { pool.checkin(conn) }]
  end

  api.get '/users', depends: [:db] do |input, req, task, db:|
    result = db.exec("SELECT * FROM users")
    [{ users: result.to_a }, 200]
  end
end
```

## Transactions

### With Block Dependencies

```ruby
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

api.post '/transfer', depends: [:transaction] do |input, req, task, transaction:|
  transaction.exec("UPDATE accounts SET balance = balance - $1 WHERE id = $2", 
    [input[:body][:amount], input[:body][:from_id]])
  transaction.exec("UPDATE accounts SET balance = balance + $1 WHERE id = $2", 
    [input[:body][:amount], input[:body][:to_id]])
  
  [{ success: true }, 200]
end
```

## Async Queries

With async-compatible drivers, run queries concurrently:

```ruby
api.get '/dashboard/:id' do |input, req, task|
  id = input[:path]['id']

  user = task.async { DB[:users].where(id: id).first }
  posts = task.async { DB[:posts].where(user_id: id).limit(10).all }
  stats = task.async { DB[:stats].where(user_id: id).first }

  [{
    user: user.wait,
    posts: posts.wait,
    stats: stats.wait
  }, 200]
end
```

## Migrations

FunApi doesn't include migrations. Use your database library's migration tool:

- Sequel: `sequel -m migrations/ postgres://...`
- ActiveRecord: `rake db:migrate`
- Raw SQL files with a migration runner
