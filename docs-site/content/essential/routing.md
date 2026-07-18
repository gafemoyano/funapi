---
title: Routing
---

# Routing

Routes map HTTP requests to handler functions based on the path and method.

## Defining Routes

FunApi provides methods for each HTTP verb:

```ruby
api.get '/users' do |input, req, task|
  [{ users: [] }, 200]
end

api.post '/users' do |input, req, task|
  [{ created: input[:body] }, 201]
end

api.put '/users/:id' do |input, req, task|
  [{ updated: true }, 200]
end

api.patch '/users/:id' do |input, req, task|
  [{ patched: true }, 200]
end

api.delete '/users/:id' do |input, req, task|
  [{}, 204]
end
```

## Path Parameters

Capture dynamic segments with `:param` syntax:

```ruby
api.get '/users/:id' do |input, req, task|
  user_id = input[:path][:id]  # Symbol keys; string value by default
  [{ id: user_id }, 200]
end

api.get '/posts/:post_id/comments/:comment_id' do |input, req, task|
  post_id = input[:path][:post_id]
  comment_id = input[:path][:comment_id]
  [{ post_id: post_id, comment_id: comment_id }, 200]
end
```

> **Note**: Path parameter keys are symbols. Values are strings by default, so
> convert them manually if needed:
> ```ruby
> id = input[:path][:id].to_i
> ```
> Or declare a `path:` schema to coerce them automatically (see
> [Validation](/essential/validation)).

## Query Parameters

Query parameters come from the URL query string:

```ruby
# GET /search?q=ruby&limit=10
api.get '/search' do |input, req, task|
  query = input[:query][:q]
  limit = input[:query][:limit]&.to_i || 20
  [{ query: query, limit: limit }, 200]
end
```

With validation:

```ruby
SearchSchema = FunApi::Schema.define do
  required(:q).filled(:string)
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

api.get '/search', query: SearchSchema do |input, req, task|
  # input[:query] is validated and coerced
  [{ results: search(input[:query]) }, 200]
end
```

## Request Body

POST, PUT, and PATCH routes typically receive a JSON body:

```ruby
UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

api.post '/users', body: UserSchema do |input, req, task|
  user = input[:body]  # Validated hash
  [{ created: user }, 201]
end
```

## Route Priority

Routes are matched in the order they're defined. More specific routes should come first:

```ruby
api.get '/users/me' do |input, req, task|
  # Matches /users/me
end

api.get '/users/:id' do |input, req, task|
  # Matches /users/123, /users/anything
end
```

## The Root Route

The root path `/` works like any other route:

```ruby
api.get '/' do |input, req, task|
  [{ status: 'ok' }, 200]
end
```

## Router Composition

As an app grows you'll want to split routes across files. `FunApi::Router` is a
standalone, composable unit — FunApi's answer to FastAPI's `APIRouter`. Define a
router in its own file, then include it into the app (or into another router).

```ruby
# routers/users.rb
UsersRouter = FunApi::Router.new(prefix: '/users', tags: ['users']) do |r|
  r.get '/' do |input, req, task|
    [{ users: [] }, 200]
  end

  r.get '/:id', path: IdSchema do |input, req, task|
    [{ id: input[:path][:id] }, 200]
  end
end
```

```ruby
# app.rb
require_relative 'routers/users'

app = FunApi::App.new do |api|
  api.include_router(UsersRouter)
end
```

A router accepts three composition options:

- `prefix:` — prepended to every route path. Prefixes compose when routers
  include routers.
- `tags:` — OpenAPI operation tags so `/docs` groups the endpoints.
- `depends:` — dependencies shared by every route in the router.

### Shared dependencies

Dependencies declared on the router are injected into every route. A per-route
`depends:` wins on key conflict:

```ruby
UsersRouter = FunApi::Router.new(prefix: '/users', depends: { db: :db }) do |r|
  # `db` is injected here
  r.get '/' do |input, req, task, db:|
    [db.all_users, 200]
  end

  # route-level `store` overrides any shared `store`
  r.get '/audit', depends: { store: :audit_store } do |input, req, task, db:, store:|
    [store.recent, 200]
  end
end

app = FunApi::App.new do |api|
  api.register(:db) { Database.connect }
  api.include_router(UsersRouter)
end
```

### Nesting routers

Routers can include other routers. Prefixes, tags, and shared dependencies
compose from the outside in:

```ruby
ApiV1 = FunApi::Router.new(prefix: '/api/v1') do |r|
  r.include_router(UsersRouter)   # -> /api/v1/users/...
  r.include_router(PostsRouter)   # -> /api/v1/posts/...
end

app = FunApi::App.new { |api| api.include_router(ApiV1) }
```

`include_router` also accepts `prefix:`, `depends:`, and `tags:` at the
inclusion site, applied on top of whatever the router already declares:

```ruby
api.include_router(UsersRouter, prefix: '/admin', tags: ['admin'])
```
