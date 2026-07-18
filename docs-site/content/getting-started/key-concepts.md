---
title: Key Concepts
---

# Key Concepts

Understanding these core concepts will help you work effectively with FunApi.

## The App

Everything starts with `FunApi::App`. It's your application container that holds routes, middleware, and configuration.

```ruby
app = FunApi::App.new(
  title: "My API",        # Shows in OpenAPI docs
  version: "1.0.0",       # API version
  description: "..."      # Optional description
) do |api|
  # Define routes here
end
```

## Route Handlers

Route handlers are blocks that receive three arguments:

```ruby
api.get '/path' do |input, req, task|
  # input - Hash with :path, :query, :body
  # req   - Rack::Request object
  # task  - Async::Task for concurrent operations
  
  [response_data, status_code]
end
```

### The Input Hash

All request data is normalized into a single `input` hash:

```ruby
api.post '/users/:id' do |input, req, task|
  input[:path]     # => { id: '123' }
  input[:query]    # => { limit: 10, offset: 0 }
  input[:body]     # => { name: 'Alice', ... }
  input[:headers]  # => { 'content-type' => 'application/json' }
end
```

### Return Value

Handlers return a tuple of `[data, status_code]`:

```ruby
[{ user: user }, 200]        # Success
[{ error: 'Not found' }, 404] # Error
[created_user, 201]          # Created
```

## Models

A `FunApi::Model` defines the shape of request and response data. One
declaration gives you validation + coercion, serialization, and an OpenAPI
schema — while validated data stays a plain `Hash`.

```ruby
class User < FunApi::Model
  field :name,  :string
  field :email, :string, format: "email"
  field :age,   :integer, optional: true
end
```

Apply a model to a route — `body:`, `query:`, `path:`, and `response_schema:`
all accept a model class (or `[Model]` for a collection):

```ruby
api.post "/users", body: User, response_schema: User do |input, req|
  input[:body]      # validated and coerced Hash
  [db_user, 201]    # object serialized + filtered by User
end
```

See [Validation](/essential/validation) for the full field reference.

> The older `FunApi::Schema.define` DSL (a thin wrapper over dry-schema) still
> works everywhere a model is accepted, but `FunApi::Model` is preferred.

## Async Task

The `task` parameter is an `Async::Task` from Ruby's Async library. Use it for concurrent operations:

```ruby
api.get '/dashboard' do |input, req, task|
  # These run concurrently
  user_task = task.async { fetch_user }
  posts_task = task.async { fetch_posts }
  stats_task = task.async { fetch_stats }

  # Wait for all to complete
  [{
    user: user_task.wait,
    posts: posts_task.wait,
    stats: stats_task.wait
  }, 200]
end
```

## Middleware Stack

Middleware wraps your application, processing requests before they reach handlers and responses after:

```ruby
app = FunApi::App.new do |api|
  # Built-in middleware
  api.add_cors(allow_origins: ['*'])
  api.add_request_logger
  
  # Standard Rack middleware
  api.use Rack::Session::Cookie, secret: 'key'
  
  # Routes...
end
```

Middleware runs in order: first added runs first.

## Lifecycle Hooks

Run code when the application starts or stops:

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    DB.connect
    Cache.warm
  end

  api.on_shutdown do
    DB.disconnect
  end
end
```

## OpenAPI/Swagger

FunApi automatically generates OpenAPI documentation from your routes and schemas:

- `/docs` - Interactive Swagger UI
- `/openapi.json` - Raw OpenAPI specification

The docs are generated from:
- Route paths and methods
- Path parameters
- Query and body schemas
- Response schemas
