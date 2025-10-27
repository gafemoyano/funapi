# FunApi

A minimal, async-first Ruby web framework inspired by FastAPI. Built on top of Falcon and dry-schema, FunApi provides a simple, performant way to build web APIs in Ruby with a focus on developer experience.

## Philosophy

FunApi aims to bring FastAPI's excellent developer experience to Ruby by providing:

- **Async-first**: Built on Ruby's Async library and Falcon server for high-performance concurrent operations
- **Simple validation**: Using dry-schema for straightforward request validation
- **Minimal magic**: Clear, explicit APIs without heavy DSLs
- **Easy to start**: Get an API up and running in minutes
- **Auto-documentation**: Automatic OpenAPI/Swagger documentation generation

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'fun_api'
```

And then execute:

```bash
bundle install
```

## Quick Start

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

app = FunApi::App.new(
  title: "My API",
  version: "1.0.0",
  description: "A simple API example"
) do |api|
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello, World!' }, 200]
  end
  
  api.post '/users', body: UserSchema do |input, req, task|
    user = input[:body]
    [{ created: user }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 9292)
```

Visit http://localhost:9292/docs to see your interactive API documentation!

## Core Features

### 1. Async-First Request Handling

All route handlers receive the current `Async::Task` as the third parameter, enabling true concurrent execution within your routes:

```ruby
api.get '/dashboard/:id' do |input, req, task|
  user_id = input[:path]['id']
  
  user_task = task.async { fetch_user_data(user_id) }
  posts_task = task.async { fetch_user_posts(user_id) }
  stats_task = task.async { fetch_user_stats(user_id) }
  
  data = {
    user: user_task.wait,
    posts: posts_task.wait,
    stats: stats_task.wait
  }
  
  [{ dashboard: data }, 200]
end
```

### 2. Request Validation

FastAPI-style request validation using dry-schema:

```ruby
UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

app = FunApi::App.new do |api|
  api.get '/hello', query: QuerySchema do |input, req, task|
    name = input[:query][:name] || 'World'
    [{ msg: "Hello, #{name}!" }, 200]
  end

  api.post '/users', body: UserCreateSchema do |input, req, task|
    user = input[:body]
    [{ created: user }, 201]
  end
  
  api.post '/users/batch', body: [UserCreateSchema] do |input, req, task|
    users = input[:body].map { |u| create_user(u) }
    [users, 201]
  end
end
```

### 3. Response Schema Validation & Filtering

Automatically validate and filter response data, similar to FastAPI's `response_model`:

```ruby
UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

app = FunApi::App.new do |api|
  api.post '/users', 
    body: UserCreateSchema,
    response_schema: UserOutputSchema do |input, req, task|
      
    user = {
      id: 1,
      name: input[:body][:name],
      email: input[:body][:email],
      password: input[:body][:password],
      age: input[:body][:age]
    }
    
    [user, 201]
  end
  
  api.get '/users',
    response_schema: [UserOutputSchema] do |input, req, task|
    users = fetch_all_users()
    [users, 200]
  end
end
```

### 4. Automatic OpenAPI Documentation

FunApi automatically generates OpenAPI 3.0 specifications from your route definitions and schemas:

```ruby
app = FunApi::App.new(
  title: "User Management API",
  version: "1.0.0",
  description: "A comprehensive user management system"
) do |api|
  api.get '/users', query: QuerySchema, response_schema: [UserOutputSchema] do |input, req, task|
    [fetch_users(input[:query]), 200]
  end
  
  api.post '/users', body: UserCreateSchema, response_schema: UserOutputSchema do |input, req, task|
    [create_user(input[:body]), 201]
  end
end

FunApi::Server::Falcon.start(app, port: 9292)
```

Once running, you can access:
- **Interactive docs**: http://localhost:9292/docs (Swagger UI)
- **OpenAPI spec**: http://localhost:9292/openapi.json

The documentation is automatically generated from:
- Route paths and HTTP methods
- Path parameters (`:id` → `{id}`)
- Query parameter schemas
- Request body schemas
- Response schemas
- Schema names (from constant names)

### 5. FastAPI-Style Error Handling

Validation errors return detailed, structured responses:

```json
{
  "detail": [
    {
      "loc": ["body", "email"],
      "msg": "is missing",
      "type": "value_error"
    }
  ]
}
```

Custom exceptions with proper HTTP status codes:

```ruby
raise FunApi::HTTPException.new(status_code: 404, detail: "User not found")
raise FunApi::ValidationError.new(errors: schema_errors)
```

### 6. Middleware Support

FunApi supports both standard Rack middleware and provides FastAPI-style convenience methods for common use cases.

#### Built-in Middleware

```ruby
app = FunApi::App.new do |api|
  api.add_cors(
    allow_origins: ['http://localhost:3000'],
    allow_methods: ['GET', 'POST', 'PUT', 'DELETE'],
    allow_headers: ['Content-Type', 'Authorization']
  )
  
  api.add_request_logger
  
  api.add_trusted_host(
    allowed_hosts: ['localhost', '127.0.0.1', /\.example\.com$/]
  )
  
  api.add_gzip
end
```

#### Using Standard Rack Middleware

Any Rack middleware works out of the box:

```ruby
app = FunApi::App.new do |api|
  api.use Rack::Attack
  api.use Rack::ETag
  api.use Rack::Session::Cookie, secret: 'your_secret'
  
  api.get '/protected' do |input, req, task|
    [{ data: 'Protected resource' }, 200]
  end
end
```

#### Custom Middleware

Create your own middleware following the Rack pattern:

```ruby
class MyCustomMiddleware
  def initialize(app)
    @app = app
  end
  
  def call(env)
    status, headers, body = @app.call(env)
    headers['X-Custom-Header'] = 'my-value'
    [status, headers, body]
  end
end

app.use MyCustomMiddleware
```

### 7. Input Structure

All route handlers receive a unified `input` hash:

```ruby
{
  path: { id: "123" },
  query: { name: "John" },
  body: { email: "..." }
}
```

## Complete Example

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

app = FunApi::App.new(
  title: "User Management API",
  version: "1.0.0",
  description: "A simple user management API"
) do |api|
  api.add_cors(allow_origins: ['*'])
  api.add_request_logger
  
  api.get '/users', query: QuerySchema, response_schema: [UserOutputSchema] do |input, req, task|
    users = [
      { id: 1, name: 'John Doe', email: 'john@example.com', age: 30 },
      { id: 2, name: 'Jane Smith', email: 'jane@example.com' }
    ]
    [users, 200]
  end

  api.get '/users/:id', response_schema: UserOutputSchema do |input, req, task|
    user_id = input[:path]['id']
    user = { id: user_id.to_i, name: 'John Doe', email: 'john@example.com', age: 30 }
    [user, 200]
  end

  api.post '/users', body: UserCreateSchema, response_schema: UserOutputSchema do |input, req, task|
    user = input[:body].merge(id: rand(1000))
    [user, 201]
  end
  
  api.get '/dashboard/:id' do |input, req, task|
    user_id = input[:path]['id']
    
    user_task = task.async { fetch_user(user_id) }
    posts_task = task.async { fetch_posts(user_id) }
    stats_task = task.async { fetch_stats(user_id) }
    
    data = {
      user: user_task.wait,
      posts: posts_task.wait,
      stats: stats_task.wait
    }
    
    [{ dashboard: data }, 200]
  end
end

FunApi::Server::Falcon.start(app, port: 9292)
```

## Architecture

- **Router**: Simple pattern-based routing with path parameter extraction
- **Async Helpers**: Wrapper around Ruby's Async library for concurrent operations
- **Schema**: Thin wrapper around dry-schema for validation
- **Exceptions**: FastAPI-inspired exception classes with proper HTTP responses
- **Server**: Falcon-based async HTTP server
- **OpenAPI**: Automatic OpenAPI 3.0 specification generation from routes and schemas

## Dependencies

- **rack** (>= 3.0.0): Web server interface
- **async** (>= 2.8): Async/await and concurrency primitives
- **dry-schema** (>= 1.13): Schema validation
- **falcon** (>= 0.44): High-performance async HTTP server

## Design Goals

1. **Performance**: Leverage Ruby's async capabilities for concurrent operations
2. **Simplicity**: Minimal API surface, easy to learn
3. **Explicitness**: No hidden magic, clear separation of concerns
4. **Type Safety**: Validation at the edges using dry-schema
5. **FastAPI-inspired**: Bring the best ideas from Python's FastAPI to Ruby

## Current Status

Active development. Core features implemented:
- ✅ Async-first request handling with Async::Task
- ✅ Route definition with path params
- ✅ Request validation (body/query) with array support
- ✅ Response schema validation and filtering
- ✅ FastAPI-style error responses
- ✅ Falcon server integration
- ✅ OpenAPI/Swagger documentation generation
- ✅ Middleware support (Rack-compatible + convenience methods)

## Future Enhancements

- Path parameter type validation
- Response schema options (exclude_unset, include, exclude)
- Dependency injection system
- Background tasks
- WebSocket support
- Content negotiation (JSON, XML, etc.)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/fun_api.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
