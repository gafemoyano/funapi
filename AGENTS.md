# FunApi - Agent Instructions

FunApi is a minimal, async-first Ruby web framework inspired by FastAPI. This file contains essential context for AI coding agents working on this project.

## Project Overview

**Goal**: Bring FastAPI's excellent developer experience to Ruby with async-first architecture.

**Core Philosophy**:
- Async-first using Ruby's `Async` library and Falcon server
- Simple validation with dry-schema
- Minimal magic, clear explicit APIs
- Automatic OpenAPI/Swagger documentation
- Rack-compatible middleware system

**Target Ruby Version**: >= 3.2.0

## Setup Commands

```bash
# Install dependencies
./bin/bundle install

# Run tests
./bin/bundle exec rake test

# Run linter (Standard Ruby)
./bin/bundle exec rake standard

# Run linter with auto-fix
./bin/bundle exec standardrb --fix

# Run both tests and linting
./bin/bundle exec rake
```

## Development Workflow

### Running Examples

```bash
# Middleware demo (port 3000)
ruby examples/middleware_demo.rb

# OpenAPI demo (port 9292)
ruby test/demo_openapi.rb

# Middleware test demo
ruby test/demo_middleware.rb
```

### Testing Changes

1. Run examples to verify functionality manually
2. Run `bundle exec rake test` to ensure tests pass
3. Run `bundle exec rake standard` to check code style
4. Check OpenAPI docs at `http://localhost:PORT/docs` when running examples

## Code Style Guidelines

**Linter**: Standard Ruby (standardrb)
- Ruby version: 3.2 (configured in `.standard.yml`)
- **IMPORTANT**: DO NOT add comments unless explicitly requested
- Follow Standard Ruby formatting automatically

**Conventions**:
- Use frozen string literals: `# frozen_string_literal: true`
- Prefer keyword arguments for options
- Use Ruby 3+ pattern matching where appropriate
- Keep methods focused and single-purpose
- Use descriptive variable names (no abbreviations)

**File Organization**:
- Core framework: `lib/fun_api/`
- Middleware: `lib/fun_api/middleware/`
- OpenAPI: `lib/fun_api/openapi/`
- Server adapters: `lib/fun_api/server/`
- Examples: `examples/`
- Tests/Demos: `test/`

## Architecture Patterns

### Route Handlers

All route handlers receive three parameters:
```ruby
api.get '/path' do |input, req, task|
  # input: { path: {...}, query: {...}, body: {...} }
  # req: Rack::Request object
  # task: Async::Task for concurrent operations

  [response_data, status_code]
end
```

### Async Operations

Use the `task` parameter for concurrent operations:
```ruby
api.get '/dashboard/:id' do |input, req, task|
  user_task = task.async { fetch_user(id) }
  posts_task = task.async { fetch_posts(id) }

  data = {
    user: user_task.wait,
    posts: posts_task.wait
  }

  [data, 200]
end
```

### Validation Schemas

Use dry-schema for request validation:
```ruby
MySchema = FunApi::Schema.define do
  required(:name).filled(:string)
  optional(:age).filled(:integer)
end

# Apply to routes
api.post '/users', body: MySchema do |input, req, task|
  user = input[:body]  # Already validated
  [user, 201]
end
```

### Middleware

Follow standard Rack middleware pattern:
```ruby
class MyMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    # Before request
    status, headers, body = @app.call(env)
    # After request
    [status, headers, body]
  end
end

# Use keyword arguments for options
class ConfigurableMiddleware
  def initialize(app, **options)
    @app = app
    @option = options[:option]
  end
end
```

### Lifecycle Hooks

Run code at startup/shutdown:
```ruby
api.on_startup do
  DB.connect
  Cache.warm
end

api.on_shutdown do
  DB.disconnect
end
```

- Multiple hooks allowed (run in registration order)
- Startup hooks run before server accepts requests
- Shutdown hooks run after server stops
- Shutdown errors logged but don't stop other hooks

### Template Rendering

Return `TemplateResponse` for HTML instead of JSON:
```ruby
require 'fun_api/templates'

templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'  # optional default layout
)

api.get '/' do |input, req, task|
  templates.response('home.html.erb', title: 'Home', user: current_user)
end

# Disable layout for HTMX partials
api.post '/items' do |input, req, task|
  templates.response('_item.html.erb', layout: false, item: item, status: 201)
end

# Use with_layout for route groups
admin = templates.with_layout('layouts/admin.html.erb')
api.get '/admin' do |input, req, task|
  admin.response('dashboard.html.erb', title: 'Admin')
end
```

**Layout templates** use `yield_content`:
```erb
<!DOCTYPE html>
<html>
<head><title><%= title %></title></head>
<body><%= yield_content %></body>
</html>
```

**Partials** via `render_partial`:
```erb
<% items.each do |item| %>
  <%= render_partial('_item.html.erb', item: item) %>
<% end %>
```

## Key Files and Their Purpose

- `lib/fun_api/application.rb` - Main App class, route registration, middleware system
- `lib/fun_api/router.rb` - Route matching and path parameter extraction
- `lib/fun_api/schema.rb` - Validation wrapper around dry-schema
- `lib/fun_api/exceptions.rb` - HTTPException, ValidationError, TemplateNotFoundError
- `lib/fun_api/templates.rb` - ERB template rendering with layouts/partials
- `lib/fun_api/template_response.rb` - HTML response wrapper
- `lib/fun_api/middleware/` - Built-in middleware (CORS, TrustedHost, RequestLogger)
- `lib/fun_api/openapi/` - OpenAPI spec generation from routes and schemas
- `lib/fun_api/server/falcon.rb` - Falcon server integration

## Common Tasks

### Adding a New Built-in Middleware

1. Create file in `lib/fun_api/middleware/my_middleware.rb`
2. Follow pattern:
   ```ruby
   module FunApi
     module Middleware
       class MyMiddleware
         def initialize(app, **options)
           @app = app
           # Store options
         end

         def call(env)
           # Middleware logic
           @app.call(env)
         end
       end
     end
   end
   ```
3. Add convenience method to `lib/fun_api/application.rb`:
   ```ruby
   def add_my_middleware(**options)
     require_relative 'middleware/my_middleware'
     use FunApi::Middleware::MyMiddleware, **options
   end
   ```
4. Require in `lib/fun_api/middleware.rb`
5. Add example to `examples/middleware_demo.rb`
6. Update README.md middleware section

### Adding a New Route Helper

1. Add method to `lib/fun_api/application.rb`
2. Follow existing pattern (get, post, put, patch, delete)
3. Use `add_route` internally with proper verb

### Extending OpenAPI Generation

1. Schema conversion: `lib/fun_api/openapi/schema_converter.rb`
2. Spec generation: `lib/fun_api/openapi/spec_generator.rb`
3. Test with `ruby test/demo_openapi.rb` and check `/docs`

## Testing Instructions

**Test Framework**: Minitest
**Test Structure**: Flat (following Sidekiq pattern)
**Current Status**: 174 tests, 487 assertions, all passing (~220ms)

### Running Tests

```bash
# All tests
bundle exec rake test

# Single test file
bundle exec ruby -Itest test/test_router.rb

# Single test
bundle exec ruby -Itest test/test_router.rb -n test_root_route_matches

# Tests + linting
bundle exec rake
```

### Test Files

All tests live in `test/` (flat structure):
- `test_fun_api.rb` - Basic smoke tests (10 tests)
- `test_router.rb` - Router functionality (11 tests)
- `test_schema.rb` - Schema validation (14 tests)
- `test_middleware.rb` - Middleware chain (12 tests)
- `test_validation.rb` - Request validation (14 tests)
- `test_response_schema.rb` - Response filtering (9 tests)
- `test_async.rb` - Async operations (10 tests)
- `test_exceptions.rb` - Error handling (10 tests)
- `test_templates.rb` - Template rendering (37 tests)
- `test_lifecycle.rb` - Lifecycle hooks (14 tests)

### Writing Tests

Follow existing patterns:
```ruby
class TestMyFeature < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_something
    app = FunApi::App.new do |api|
      api.get '/test' do |input, req, task|
        [{ message: 'test' }, 200]
      end
    end

    res = async_request(app, :get, '/test')
    assert_equal 200, res.status
  end
end
```

### Test Coverage

✅ Router (path matching, parameters, 404s)
✅ Schema validation (success, failure, errors, arrays)
✅ Middleware (chain building, ordering, built-ins)
✅ Request validation (query/body, error format)
✅ Response schemas (filtering, arrays, nested)
✅ Async operations (concurrency, timeouts, dependencies)
✅ Exceptions (HTTPException, custom errors)
✅ Templates (rendering, layouts, partials, with_layout)
✅ Lifecycle hooks (startup/shutdown, error handling)

### Manual Testing

1. Run example apps in `examples/`
2. Test with curl:
   ```bash
   curl http://localhost:3000/
   curl -X POST http://localhost:3000/users \
     -H 'Content-Type: application/json' \
     -d '{"name":"Test","email":"test@example.com"}'
   ```
3. Check OpenAPI docs at `/docs`
4. Verify middleware behavior (CORS headers, logging, etc.)

### Before Committing

- Run `bundle exec rake` (tests + linting)
- Ensure all tests pass
- Check no temporary files in project root
- Update tests if adding new features

## Security Considerations

- **Sensitive Data**: Never log passwords, tokens, or API keys
- **Response Schemas**: Use response_schema to filter sensitive fields from responses
- **Trusted Host**: Always use `add_trusted_host` in production
- **CORS**: Configure `add_cors` with specific origins, not `['*']` in production
- **Validation**: Always validate user input with schemas

## Common Pitfalls

1. **Root Route Bug**: The router has special handling for `/` - don't change it
2. **Keyword Arguments**: Middleware must accept `**options`, not positional args
3. **Async Context**: Route handlers must be called within Async::Task context
4. **Path Params**: Always strings in `input[:path]`, convert types manually
5. **Response Format**: Must return `[data, status_code]` from handlers
6. **Middleware Order**: First registered runs first (FIFO execution, LIFO wrapping)

## Dependencies

**Core**:
- `async` (>= 2.8) - Async/concurrency primitives
- `falcon` (>= 0.44) - Async HTTP server
- `rack` (>= 3.0.0) - Web server interface
- `dry-schema` (>= 1.13) - Validation

**Middleware**:
- `rack-cors` (>= 2.0) - CORS support

**Development**:
- `standard` - Ruby style guide and linter
- `minitest` - Testing framework


## Future Enhancements Roadmap

See `README.md` for full list. Key priorities:
1. ~~Dependency injection system~~ ✅ Done
2. ~~Background tasks~~ ✅ Done
3. ~~Template rendering~~ ✅ Done
4. ~~Lifecycle hooks (startup/shutdown)~~ ✅ Done
5. Path parameter type validation
6. WebSocket support

## Questions?

Check these resources:
- `/examples` - Working demo applications
- `/test` - Demo scripts showing features
- `/.claude` - Implementation plans and notes
- `README.md` - User-facing documentation
