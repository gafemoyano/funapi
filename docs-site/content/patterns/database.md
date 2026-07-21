---
title: Database
---

# Database

FunApi ships one blessed data path: **[Sequel](https://sequel.jeremyevans.net/)
with a fibered connection pool**, exposed through `funapi/sequel`. Sequel is a
mature, actively maintained toolkit, and `pg` (>= 1.3) is fiber-scheduler-aware,
so queries are non-blocking under Falcon.

FunApi does not ship an ORM — it documents and tests one path so the ecosystem
tells one story. You still add `sequel` (and a driver such as `pg`) to your own
Gemfile:

```ruby
# Gemfile
gem "funapi"
gem "sequel"
gem "pg"
```

## FunApi::Sequel.connect

`require "funapi/sequel"` and connect. The returned `Sequel::Database` uses the
`FiberedConnectionPool`, which checks connections in and out cooperatively so
concurrent requests share the pool without blocking the reactor:

```ruby
require "funapi"
require "funapi/sequel"
require "funapi/server/falcon"

DB = FunApi::Sequel.connect(ENV["DATABASE_URL"], max_connections: 10)

app = FunApi::App.new do |api|
  api.get "/users" do |input, req|
    [{users: DB[:users].all}, 200]
  end

  api.get "/users/:id" do |input, req|
    user = DB[:users].where(id: input[:path][:id]).first
    raise FunApi::HTTPException.new(status_code: 404) unless user
    [{user: user}, 200]
  end

  api.post "/users", body: UserSchema do |input, req|
    id = DB[:users].insert(input[:body])
    [{user: DB[:users].where(id: id).first}, 201]
  end
end
```

`max_connections` caps the pool. Size it to match your bounded concurrency (see
[Best Practices](/patterns/best-practices)).

## Concurrent Queries

Because the fibered pool is cooperative, independent queries run concurrently
with `FunApi.async` — each child task checks out its own connection:

```ruby
api.get "/dashboard/:id" do |input, req|
  id = input[:path][:id]

  user  = FunApi.async { DB[:users].where(id: id).first }
  posts = FunApi.async { DB[:posts].where(user_id: id).limit(10).all }
  stats = FunApi.async { DB[:stats].where(user_id: id).first }

  [{user: user.wait, posts: posts.wait, stats: stats.wait}, 200]
end
```

## Serializing Sequel::Model through FunApi::Model

`FunApi::Model` reads any object that responds to the field names, so a
`Sequel::Model` instance serializes through a `response_schema` with no manual
mapping — sensitive columns you omit from the model are filtered out:

```ruby
class User < Sequel::Model(DB[:users])
end

class UserOut < FunApi::Model
  field :id, :integer
  field :name, :string
  field :email, :string
  # no :password field -> never serialized
end

app = FunApi::App.new do |api|
  api.get "/users/:id", response_schema: UserOut do |input, req|
    [User.where(id: input[:path][:id].to_i).first, 200]
  end

  # Arrays work too:
  api.get "/users", response_schema: [UserOut] do |input, req|
    [User.order(:id).all, 200]
  end
end
```

FunApi does **not** derive model fields from a dataset schema — you declare the
response shape explicitly. That keeps the wire contract decoupled from the table
and prevents accidental leaks when a column is added.

## Injecting the DB as a Dependency

Prefer a shared constant for a process-wide pool, but you can also inject the
database (or a per-request transaction) via dependencies:

```ruby
app = FunApi::App.new do |api|
  api.register(:db) { DB }

  api.get "/users", depends: [:db] do |input, req, db:|
    [{users: db[:users].all}, 200]
  end
end
```

### Transactions with Block Dependencies

Block dependencies run cleanup in `ensure`, which maps cleanly onto a
transaction's commit/rollback:

```ruby
api.register(:tx) do |provide|
  DB.transaction do
    provide.call(DB)
  end
end

api.post "/transfer", depends: [:tx] do |input, req, tx:|
  amount = input[:body][:amount]
  tx[:accounts].where(id: input[:body][:from_id]).update(balance: Sequel[:balance] - amount)
  tx[:accounts].where(id: input[:body][:to_id]).update(balance: Sequel[:balance] + amount)
  [{success: true}, 200]
end
```

## Lifecycle

Open the pool at boot and disconnect on shutdown:

```ruby
app = FunApi::App.new do |api|
  api.on_shutdown { DB.disconnect }
end
```

## Migrations

FunApi doesn't include migrations — use Sequel's:

```bash
sequel -m db/migrations postgres://...
```

## Other Libraries

FunApi works with any Ruby database library (ROM, ActiveRecord standalone, raw
`pg`). Only Sequel + the fibered pool is tested and documented as the blessed
path; anything blocking will stall the reactor, so prefer fiber-aware drivers.
</content>
