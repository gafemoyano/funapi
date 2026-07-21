---
title: "Tutorial 3: Dependency Injection"
---

# Tutorial 3: Dependency Injection

So far our posts live in an array. Real apps need shared resources — a
database, a cache, the current user. FunApi injects these into handlers the
same way FastAPI does: you declare what a route `depends` on, and FunApi
resolves it per request (with cleanup).

## Register a dependency

Register a resource by name. The block runs once per request that needs it:

```ruby
require "funapi"

Application = FunApi::App.new(title: "Blog") do |api|
  # A tiny in-memory "database" for the tutorial.
  store = PostStore.new

  api.register(:db) { store }

  api.get "/posts", depends: [:db] do |_input, _req, db:|
    [db.all, 200]
  end

  api.post "/posts", depends: [:db] do |input, _req, db:|
    [db.create(input[:body]), 201]
  end
end
```

Dependencies arrive as **keyword arguments** after `|input, req|`. The route
declares `depends: [:db]`; the handler receives `db:`.

## Cleanup with blocks

For resources that must be released (connections, files), use the block form —
`ensure` guarantees cleanup after the response is sent:

```ruby
api.register(:db) do |provide|
  conn = Database.connect
  provide.call(conn)
ensure
  conn.close
end
```

This mirrors Ruby's own `File.open`/`Mutex#synchronize` shape. Dependencies can
also depend on other dependencies via `FunApi.Depends(...)` — see
[Dependencies](/docs/patterns/dependencies).

## Concurrency

Because FunApi is async-first, a handler can fan out concurrent work with
`FunApi.async` and wait without blocking the reactor:

```ruby
api.get "/dashboard", depends: [:db] do |_input, _req, db:|
  posts = FunApi.async { db.recent_posts }
  stats = FunApi.async { db.stats }
  [{posts: posts.wait, stats: stats.wait}, 200]
end
```

Use `FunApi.sleep(n)` for non-blocking sleeps. Handlers never touch a task
object directly.

## Override dependencies in tests

Testing shouldn't touch a real database. Swap any dependency with
`override_dependency`, and restore with `reset_overrides!`:

```ruby
require_relative "test_helper"

class FakeDb
  def all = [{id: 1, title: "fake"}]
end

class DashboardTest < Minitest::Test
  def test_lists_posts_from_fake_db
    Application.override_dependency(:db, FakeDb.new)
    client = FunApi::TestClient.new(Application)

    res = client.get("/posts")
    assert_equal "fake", res.json.first[:title]
  ensure
    Application.reset_overrides!
  end
end
```

`override_dependency` accepts a plain object (a fake) or a callable (called per
request). This is FunApi's take on FastAPI's `dependency_overrides`.

## Next

[Tutorial 4: Streaming with SSE →](/docs/tutorial/streaming)
