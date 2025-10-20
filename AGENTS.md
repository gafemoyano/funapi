# FunApi

A minimal, async-first Ruby web framework inspired by FastAPI. Built on top of Falcon and dry-schema, FunApi provides a simple, performant way to build web APIs in Ruby with a focus on developer experience.

## Philosophy

FunApi aims to bring FastAPI's excellent developer experience to Ruby by providing:

- **Async-first**: Built on Ruby's Async library and Falcon server for high-performance concurrent operations
- **Simple validation**: Using dry-schema for straightforward request validation
- **Minimal magic**: Clear, explicit APIs without heavy DSLs
- **Easy to start**: Get an API up and running in minutes

## Core Features

### 1. Async-First Request Handling

All route handlers receive the current `Async::Task` as the third parameter, enabling true concurrent execution within your routes:

```ruby
# Routes receive: input, request, and async task
api.get '/dashboard/:id' do |input, req, task|
  user_id = input[:path]['id']
  
  # Use task to run operations concurrently
  user_task = task.async { fetch_user_data(user_id) }
  posts_task = task.async { fetch_user_posts(user_id) }
  stats_task = task.async { fetch_user_stats(user_id) }
  
  # Wait for all to complete
  data = {
    user: user_task.wait,
    posts: posts_task.wait,
    stats: stats_task.wait
  }
  
  [{ dashboard: data }, 200]
end

# Advanced concurrent operations with dependencies
api.get '/profile/:id' do |input, req, task|
  user_id = input[:path]['id']
  
  # Start fetching user first
  user_task = task.async { fetch_user_data(user_id) }
  user = user_task.wait
  
  # Then fetch dependent data concurrently
  posts_task = task.async { fetch_user_posts(user[:id]) }
  stats_task = task.async { fetch_user_stats(user[:id]) }
  
  [{ 
    user: user,
    posts: posts_task.wait,
    stats: stats_task.wait
  }, 200]
end

# Timeouts for slow operations
api.get '/slow/:id' do |input, req, task|
  begin
    data = task.with_timeout(0.5) { slow_operation() }
    [{ data: data }, 200]
  rescue Async::TimeoutError
    [{ error: 'Request timed out' }, 408]
  end
end
```

### 2. Request Validation

FastAPI-style request validation using dry-schema:

```ruby
# Define schemas with dry-schema
UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

# Apply validation to routes
app = FunApi::App.new do |api|
  # Query param validation (GET/DELETE)
  api.get '/hello', query: QuerySchema do |input, req, task|
    name = input[:query][:name] || 'World'
    [{ msg: "Hello, #{name}!" }, 200]
  end

  # Body validation (POST/PUT/PATCH)
  api.post '/users', body: UserCreateSchema do |input, req, task|
    user = input[:body]
    [{ created: user }, 201]
  end
  
  # Array body validation
  api.post '/users/batch', body: [UserCreateSchema] do |input, req, task|
    users = input[:body].map { |u| create_user(u) }
    [users, 201]
  end
  
  # Path params are automatically extracted (no validation needed)
  api.get '/users/:id' do |input, req, task|
    user_id = input[:path]['id']  # Always a string
    [{ user: fetch_user(user_id) }, 200]
  end
end
```

### 3. Response Schema Validation & Filtering

Automatically validate and filter response data, similar to FastAPI's `response_model`:

```ruby
# Define output schema (without sensitive fields)
UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
  # Note: password NOT included
end

app = FunApi::App.new do |api|
  # Response schema filters out password field
  api.post '/users', 
    body: UserCreateSchema,
    response_schema: UserOutputSchema do |input, req, task|
      
    # Handler returns full user with password
    user = {
      id: 1,
      name: input[:body][:name],
      email: input[:body][:email],
      password: input[:body][:password],  # This will be filtered!
      age: input[:body][:age]
    }
    
    [user, 201]
    # Client receives: { "id": 1, "name": "...", "email": "...", "age": ... }
    # Password automatically removed by response_schema!
  end
  
  # Array responses also supported
  api.get '/users',
    response_schema: [UserOutputSchema] do |input, req, task|
    users = fetch_all_users()  # Returns users with passwords
    [users, 200]  # All passwords filtered from response
  end
end
```

### 4. FastAPI-Style Error Handling

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

### 5. Input Structure

All route handlers receive a unified `input` hash:

```ruby
{
  path: { id: "123" },           # Path parameters (strings)
  query: { name: "John" },       # Query parameters (validated if schema provided)
  body: { email: "..." }         # Request body (validated if schema provided)
}
```

## Architecture

- **Router**: Simple pattern-based routing with path parameter extraction
- **Async Helpers**: Wrapper around Ruby's Async library for concurrent operations
- **Schema**: Thin wrapper around dry-schema for validation
- **Exceptions**: FastAPI-inspired exception classes with proper HTTP responses
- **Server**: Falcon-based async HTTP server

## Dependencies

- **rack** (>= 3.0.0): Web server interface
- **async** (>= 2.8): Async/await and concurrency primitives
- **dry-schema** (>= 1.13): Schema validation
- **falcon** (>= 0.44): High-performance async HTTP server

## Example Application

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

# Define validation schemas
UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

# Build the app
app = FunApi::App.new do |api|
  api.get '/users/:id' do |input, req, task|
    user_id = input[:path]['id']
    user = fetch_user(user_id)
    [{ user: user }, 200]
  end

  api.post '/users', body: UserCreateSchema do |input, req, task|
    user = create_user(input[:body])
    [{ user: user }, 201]
  end
  
  # Concurrent operations using the async task
  api.get '/dashboard/:id' do |input, req, task|
    user_id = input[:path]['id']
    
    # Execute multiple operations concurrently
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

# Start the server
FunApi::Server::Falcon.start(app)
```

## Design Goals

1. **Performance**: Leverage Ruby's async capabilities for concurrent operations
2. **Simplicity**: Minimal API surface, easy to learn
3. **Explicitness**: No hidden magic, clear separation of concerns
4. **Type Safety**: Validation at the edges using dry-schema
5. **FastAPI-inspired**: Bring the best ideas from Python's FastAPI to Ruby

## Current Status

Early development. Core features implemented:
- ✅ Async-first request handling with Async::Task
- ✅ Route definition with path params
- ✅ Request validation (body/query) with array support
- ✅ Response schema validation and filtering
- ✅ FastAPI-style error responses
- ✅ Falcon server integration

## Future Enhancements

- Path parameter type validation
- Middleware support
- OpenAPI/Swagger documentation generation
- Response schema options (exclude_unset, include, exclude)
- Dependency injection system
- WebSocket support
- Content negotiation (JSON, XML, etc.)
