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
ruby examples/demo_openapi.rb

# Middleware test demo
ruby examples/demo_middleware.rb
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
- Core framework: `lib/funapi/`
- Middleware: `lib/funapi/middleware/`
- OpenAPI: `lib/funapi/openapi/`
- Server adapters: `lib/funapi/server/`
- Examples: `examples/`
- Tests/Demos: `test/`

## Architecture Patterns

### Route Handlers

Route handlers receive two parameters:
```ruby
api.get '/path' do |input, req|
  # input: { path: {...}, query: {...}, body: {...}, headers: {...} }
  # req: Rack::Request object

  [response_data, status_code]
end
```

The old three-argument form `|input, req, task|` still works during the
deprecation window, but new code should use `FunApi.async` / `FunApi.sleep`.

### Async Operations

Use `FunApi.async` for concurrent operations and `FunApi.sleep` to suspend
without blocking the reactor. Handler code never touches a task object:
```ruby
api.get '/dashboard/:id' do |input, req|
  user_task = FunApi.async { fetch_user(id) }
  posts_task = FunApi.async { fetch_posts(id) }

  data = {
    user: user_task.wait,
    posts: posts_task.wait
  }

  [data, 200]
end
```

Reach `Async::Task.current` directly for `with_timeout`, `annotate`, or `yield`.

### Streaming, SSE & WebSockets

Return a `FunApi::StreamingResponse` (callable Rack 3 body) for chunked output,
`FunApi::SSE.response` for Server-Sent Events (with optional `heartbeat:`), or
register `api.websocket "/ws/:room"` for WebSockets (via `async-websocket`;
non-upgrade requests get 426). See `docs-site/content/patterns/streaming.md`.

### Database (Sequel)

`require "funapi/sequel"` and `FunApi::Sequel.connect(url, max_connections: 10)`
returns a Sequel DB backed by the fibered connection pool. Users add `sequel`
and a driver (`pg` >= 1.3) to their own Gemfile.

### Validation Schemas

Use dry-schema for request validation:
```ruby
MySchema = FunApi::Schema.define do
  required(:name).filled(:string)
  optional(:age).filled(:integer)
end

# Apply to routes
api.post '/users', body: MySchema do |input, req|
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
require 'funapi/templates'

templates = FunApi::Templates.new(
  directory: 'templates',
  layout: 'layouts/application.html.erb'  # optional default layout
)

api.get '/' do |input, req|
  templates.response('home.html.erb', title: 'Home', user: current_user)
end

# Disable layout for HTMX partials
api.post '/items' do |input, req|
  templates.response('_item.html.erb', layout: false, item: item, status: 201)
end

# Use with_layout for route groups
admin = templates.with_layout('layouts/admin.html.erb')
api.get '/admin' do |input, req|
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

- `lib/funapi/application.rb` - Main App class, route registration, middleware system
- `lib/funapi/router.rb` - Route matching and path parameter extraction
- `lib/funapi/schema.rb` - Validation wrapper around dry-schema
- `lib/funapi/exceptions.rb` - HTTPException, ValidationError, TemplateNotFoundError
- `lib/funapi/templates.rb` - ERB template rendering with layouts/partials
- `lib/funapi/template_response.rb` - HTML response wrapper
- `lib/funapi/middleware/` - Built-in middleware (CORS, TrustedHost, RequestLogger)
- `lib/funapi/openapi/` - OpenAPI spec generation from routes and schemas
- `lib/funapi/server/falcon.rb` - Falcon server integration

## Common Tasks

### Adding a New Built-in Middleware

1. Create file in `lib/funapi/middleware/my_middleware.rb`
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
3. Add convenience method to `lib/funapi/application.rb`:
   ```ruby
   def add_my_middleware(**options)
     require_relative 'middleware/my_middleware'
     use FunApi::Middleware::MyMiddleware, **options
   end
   ```
4. Require in `lib/funapi/middleware.rb`
5. Add example to `examples/middleware_demo.rb`
6. Update README.md middleware section

### Adding a New Route Helper

1. Add method to `lib/funapi/application.rb`
2. Follow existing pattern (get, post, put, patch, delete)
3. Use `add_route` internally with proper verb

### Extending OpenAPI Generation

1. Schema conversion: `lib/funapi/openapi/schema_converter.rb`
2. Spec generation: `lib/funapi/openapi/spec_generator.rb`
3. Test with `ruby examples/demo_openapi.rb` and check `/docs`

## Testing Instructions

**Test Framework**: Minitest
**Test Structure**: Flat (following Sidekiq pattern)
**Current Status**: run `bundle exec rake test` — the full suite passes in a few seconds

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
      api.get '/test' do |input, req|
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


## Roadmap

The roadmap lives on GitHub issues — the master plan is [#4](https://github.com/gafemoyano/funapi/issues/4), with one issue per phase (#5–#10):
1. Harden the core (#5)
2. Router composition & incremental adoption (#6)
3. FunApi::Model (#7)
4. Streaming, SSE, WebSockets, Sequel bridge (#8)
5. DX: CLI, reloading, TestClient, docs (#9)
6. Agentic Experience (#10) — in progress. Landed so far: `llms.txt` +
   `llms-full.txt` served dynamically from `docs-site/app.rb`; `funapi check`
   (boots the app, validates schemas/OpenAPI, detects spec drift vs.
   `openapi.snapshot.json`, `--json` / `--update-snapshot`); a unified
   `{detail: ...}` error contract everywhere (documented in
   `docs-site/content/patterns/errors-reference.md`); MCP investigation at
   `proposals/mcp-server.md`. The AX eval harness (Layer 3) is not yet built.

## Questions?

Check these resources:
- `/examples` - Working demo applications
- `/.claude/DECISIONS.md` - Architectural decision records
- GitHub issues - Roadmap and active plans (master plan: #4)
- `README.md` - User-facing documentation
