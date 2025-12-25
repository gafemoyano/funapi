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
./bin/bundle install
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

### 8. Background Tasks

Execute tasks after the response is sent, perfect for emails, logging, and webhooks:

```ruby
api.post '/signup', body: UserSchema do |input, req, task, background:|
  user = create_user(input[:body])
  
  # Tasks execute AFTER response is sent but BEFORE dependencies close
  background.add_task(method(:send_welcome_email), user[:email])
  background.add_task(method(:log_signup_event), user[:id])
  background.add_task(method(:notify_admin), user)
  
  [{ user: user, message: 'Signup successful!' }, 201]
end
```

**Key Benefits:**
- ✅ Response sent immediately to client
- ✅ Tasks run after handler completes
- ✅ Dependencies still available to tasks
- ✅ Multiple tasks execute in order
- ✅ Errors are handled gracefully

**Perfect for:**
- Email notifications
- Logging and analytics
- Cache warming
- Simple webhook calls
- Audit trail recording

**Not for:**
- Long-running jobs (> 30 seconds)
- Jobs requiring persistence/retries
- Jobs that must survive server restart
→ Use Sidekiq, GoodJob, or Que for these cases

**With callable objects:**

```ruby
# Lambda
background.add_task(->(email) { send_email(email) }, user[:email])

# Proc
background.add_task(proc { |id| log_event(id) }, user[:id])

# Method reference
background.add_task(method(:send_email), user[:email])
```

**With arguments:**

```ruby
# Positional arguments
background.add_task(->(a, b) { sum(a, b) }, 5, 3)

# Keyword arguments
background.add_task(->(name:, age:) { greet(name, age) }, name: 'Alice', age: 30)

# Mixed
background.add_task(->(msg, to:) { send(msg, to) }, 'Hello', to: 'user@example.com')
```

**Access dependencies in background tasks:**

```ruby
api.register(:mailer) { Mailer.new }
api.register(:logger) { Logger.new }

api.post '/signup', depends: [:mailer, :logger] do |input, req, task, mailer:, logger:, background:|
  user = create_user(input[:body])
  
  # Dependencies captured in closure, available to background tasks
  background.add_task(lambda {
    mailer.send_welcome(user[:email])
    logger.info("Welcome email sent to #{user[:email]}")
  })
  
  [{ user: user }, 201]
end
```

### 9. Template Rendering

Render ERB templates for HTML responses, perfect for HTMX-style applications:

```ruby
require 'fun_api'
require 'fun_api/templates'

templates = FunApi::Templates.new(directory: 'templates')

app = FunApi::App.new do |api|
  api.get '/' do |input, req, task|
    templates.response('index.html.erb', title: 'Home', message: 'Welcome!')
  end

  api.get '/users/:id' do |input, req, task|
    user = fetch_user(input[:path]['id'])
    templates.response('user.html.erb', user: user)
  end
end
```

#### Layouts

Use layouts to wrap your templates with common HTML structure:

```ruby
templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'
)

api.get '/' do |input, req, task|
  templates.response('home.html.erb', title: 'Home')
end

# Disable layout for partials/HTMX responses
api.post '/items' do |input, req, task|
  item = create_item(input[:body])
  templates.response('items/_item.html.erb', layout: false, item: item, status: 201)
end
```

Use `with_layout` to create a scoped templates object for route groups:

```ruby
templates = FunApi::Templates.new(directory: 'templates')

# Create scoped templates for different sections
public_templates = templates.with_layout('layouts/public.html.erb')
admin_templates = templates.with_layout('layouts/admin.html.erb')

api.get '/' do |input, req, task|
  public_templates.response('home.html.erb', title: 'Home')
end

api.get '/admin' do |input, req, task|
  admin_templates.response('admin/dashboard.html.erb', title: 'Dashboard')
end
```

Layout template with `yield_content`:

```erb
<!-- templates/layouts/application.html.erb -->
<!DOCTYPE html>
<html>
<head>
  <title><%= title %></title>
</head>
<body>
  <%= yield_content %>
</body>
</html>
```

#### Partials

Render partials within templates using `render_partial`:

```erb
<!-- templates/items/index.html.erb -->
<ul>
<% items.each do |item| %>
  <%= render_partial('items/_item.html.erb', item: item) %>
<% end %>
</ul>
```

#### With HTMX

FunApi templates work great with HTMX for dynamic HTML updates:

```ruby
api.get '/items' do |input, req, task|
  items = fetch_items
  templates.response('items/index.html.erb', items: items)
end

api.post '/items', body: ItemSchema do |input, req, task|
  item = create_item(input[:body])
  # Return partial for HTMX to insert
  templates.response('items/_item.html.erb', layout: false, item: item, status: 201)
end

api.delete '/items/:id' do |input, req, task|
  delete_item(input[:path]['id'])
  # Return empty response for HTMX delete
  FunApi::TemplateResponse.new('')
end
```

```erb
<!-- With HTMX attributes -->
<form hx-post="/items" hx-target="#items" hx-swap="beforeend">
  <input name="title" placeholder="New item">
  <button type="submit">Add</button>
</form>
```

See `examples/templates_demo.rb` for a complete HTMX todo app example.

### 10. Lifecycle Hooks

Execute code when the application starts up or shuts down:

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
  
  api.on_shutdown do
    puts "Disconnecting..."
    DB.disconnect
  end
end
```

**Key behaviors:**
- Multiple hooks supported (executed in registration order)
- Startup hooks run before server accepts requests
- Shutdown hooks run after server stops accepting requests
- Startup errors prevent server from starting
- Shutdown errors are logged but don't prevent other hooks from running

**Use cases:**
- Database connection pool initialization
- Cache warming
- Background task supervisor setup
- Metrics/logging initialization
- Graceful resource cleanup

See `examples/lifecycle_demo.rb` for a complete example.

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
- ✅ Dependency injection with cleanup
- ✅ Background tasks (post-response execution)
- ✅ Template rendering (ERB with layouts and partials)
- ✅ Lifecycle hooks (startup/shutdown)

## Future Enhancements

- ~~Dependency injection system~~ ✅ Implemented
- ~~Background tasks~~ ✅ Implemented
- ~~Template rendering~~ ✅ Implemented
- ~~Lifecycle hooks (startup/shutdown)~~ ✅ Implemented
- Path parameter type validation
- Response schema options (exclude_unset, include, exclude)
- WebSocket support
- Content negotiation (JSON, XML, etc.)

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/[USERNAME]/fun_api.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
