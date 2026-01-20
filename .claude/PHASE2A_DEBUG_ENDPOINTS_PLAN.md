# Phase 2A: Debug Endpoints Plan

**Date**: 2025-01-19
**Status**: Planning
**Goal**: Expose full introspection via HTTP endpoints for AI agent runtime discovery

## Overview

Add `/introspect/*` endpoints that expose the introspection API via HTTP, enabling AI agents to query a running FunAPI application without file access.

## Endpoints

### Core Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/introspect` | GET | Overview: stats, health score, quick summary |
| `/introspect/routes` | GET | All routes with full metadata |
| `/introspect/routes/:verb/:path` | GET | Single route details (path URL-encoded) |
| `/introspect/dependencies` | GET | All dependencies with usage info |
| `/introspect/dependencies/:name` | GET | Single dependency details |
| `/introspect/schemas` | GET | All schemas with field info |
| `/introspect/middleware` | GET | Middleware stack in order |
| `/introspect/health` | GET | Full validation with issues/warnings |
| `/introspect/relationships` | GET | Dependency graph |

### Query Parameters (where applicable)

```
GET /introspect/routes?verb=POST           # Filter by verb
GET /introspect/routes?has_body=true       # Filter by has body schema
GET /introspect/routes?uses_dep=db         # Filter by dependency
GET /introspect/routes?search=user         # Fuzzy search
GET /introspect/dependencies?unused=true   # Only unused deps
GET /introspect/schemas?has_field=email    # Filter by field
```

## Response Format

All responses return JSON with consistent structure:

```json
{
  "ok": true,
  "data": { ... },
  "meta": {
    "generated_at": "2025-01-19T16:30:00Z",
    "funapi_version": "0.1.0",
    "introspection_version": "1.0"
  }
}
```

### Example: GET /introspect

```json
{
  "ok": true,
  "data": {
    "stats": {
      "routes": 15,
      "dependencies": 5,
      "schemas": 8,
      "middleware": 3
    },
    "health": {
      "score": 0.95,
      "issues_count": 1,
      "warnings_count": 2
    },
    "verbs": ["GET", "POST", "PUT", "DELETE"],
    "endpoints": {
      "routes": "/introspect/routes",
      "dependencies": "/introspect/dependencies",
      "schemas": "/introspect/schemas",
      "middleware": "/introspect/middleware",
      "health": "/introspect/health"
    }
  }
}
```

### Example: GET /introspect/routes

```json
{
  "ok": true,
  "data": {
    "count": 15,
    "routes": [
      {
        "verb": "POST",
        "path": "/users",
        "path_params": [],
        "dependencies": ["db", "logger"],
        "body_schema": "UserCreateSchema",
        "query_schema": null,
        "response_schema": "UserOutputSchema",
        "has_body_schema": true,
        "has_response_schema": true
      }
    ]
  }
}
```

### Example: GET /introspect/routes/POST/users

```json
{
  "ok": true,
  "data": {
    "verb": "POST",
    "path": "/users",
    "path_params": [],
    "dependencies": ["db", "logger"],
    "schemas": {
      "body": {
        "name": "UserCreateSchema",
        "required_fields": ["name", "email"],
        "optional_fields": ["age"],
        "field_types": {
          "name": "string",
          "email": "string",
          "age": "integer"
        }
      },
      "response": {
        "name": "UserOutputSchema",
        "required_fields": ["id", "name", "email"],
        "optional_fields": ["age"],
        "field_types": {
          "id": "integer",
          "name": "string",
          "email": "string",
          "age": "integer"
        }
      }
    },
    "example_request": {
      "name": "string",
      "email": "string",
      "age": 0
    },
    "similar_routes": [
      {"verb": "POST", "path": "/posts", "similarity": 0.85}
    ]
  }
}
```

### Example: GET /introspect/health

```json
{
  "ok": true,
  "data": {
    "score": 0.95,
    "status": "healthy",
    "issues": [
      {
        "type": "unused_dependency",
        "severity": "warning",
        "name": "cache",
        "message": "Dependency :cache is registered but not used by any route"
      }
    ],
    "warnings": [
      {
        "type": "missing_response_schema",
        "severity": "info",
        "path": "/health",
        "verb": "GET",
        "message": "Route GET /health has no response schema defined"
      }
    ],
    "summary": {
      "routes_with_body_schema": 8,
      "routes_without_body_schema": 7,
      "routes_with_response_schema": 12,
      "routes_without_response_schema": 3,
      "dependencies_used": 4,
      "dependencies_unused": 1
    }
  }
}
```

## Security

### Development-Only by Default

```ruby
app = FunApi::App.new do |api|
  # Enabled automatically when RACK_ENV != 'production'
  # Or explicitly:
  api.enable_introspection_endpoints  # Force enable
  api.disable_introspection_endpoints # Force disable
end
```

### Environment Detection

```ruby
def introspection_enabled?
  return @introspection_enabled if defined?(@introspection_enabled)
  ENV['RACK_ENV'] != 'production' && ENV['FUNAPI_ENV'] != 'production'
end
```

### Production Warning

If someone tries to access `/introspect/*` in production:

```json
{
  "ok": false,
  "error": "Introspection endpoints are disabled in production",
  "hint": "Set FUNAPI_INTROSPECTION=enabled to force enable (not recommended)"
}
```

## Implementation

### File Structure

```
lib/fun_api/
  introspection/
    endpoints.rb          # NEW: HTTP endpoint handlers
    endpoint_helpers.rb   # NEW: Response formatting, filtering
  application.rb          # MODIFY: Add introspection routes
```

### Integration with Application

```ruby
# In application.rb initialize
def initialize(...)
  # ... existing code ...
  setup_introspection_endpoints if introspection_enabled?
end

def setup_introspection_endpoints
  require_relative 'introspection/endpoints'
  Introspection::Endpoints.register(self)
end
```

### Endpoint Implementation Pattern

```ruby
module FunApi
  module Introspection
    class Endpoints
      def self.register(app)
        app.get '/introspect' do |_input, _req, _task|
          data = {
            stats: app.introspect.stats,
            health: {
              score: app.introspect.validate[:score],
              issues_count: app.introspect.validate[:issues].size,
              warnings_count: app.introspect.validate[:warnings].size
            },
            endpoints: {
              routes: '/introspect/routes',
              dependencies: '/introspect/dependencies',
              schemas: '/introspect/schemas',
              middleware: '/introspect/middleware',
              health: '/introspect/health'
            }
          }
          [wrap_response(data), 200]
        end
        
        # ... more endpoints
      end
      
      def self.wrap_response(data)
        {
          ok: true,
          data: data,
          meta: {
            generated_at: Time.now.iso8601,
            funapi_version: FunApi::VERSION,
            introspection_version: '1.0'
          }
        }
      end
    end
  end
end
```

## Testing Strategy

### Unit Tests

```ruby
class TestIntrospectionEndpoints < Minitest::Test
  def setup
    @app = FunApi::App.new do |api|
      api.enable_introspection_endpoints
      
      api.register(:db) { Object.new }
      
      api.get '/users', depends: [:db] do |_input, _req, _task|
        [[], 200]
      end
      
      api.post '/users', body: UserSchema, depends: [:db] do |input, _req, _task|
        [input[:body], 201]
      end
    end
  end
  
  def test_introspect_overview
    response = get '/introspect'
    assert_equal 200, response.status
    
    data = JSON.parse(response.body)
    assert data['ok']
    assert_equal 2, data['data']['stats']['routes']
  end
  
  def test_introspect_routes
    response = get '/introspect/routes'
    assert_equal 200, response.status
    
    data = JSON.parse(response.body)
    assert_equal 2, data['data']['count']
  end
  
  def test_introspect_single_route
    response = get '/introspect/routes/POST/users'
    assert_equal 200, response.status
    
    data = JSON.parse(response.body)
    assert_equal 'POST', data['data']['verb']
    assert_equal '/users', data['data']['path']
  end
  
  def test_introspect_disabled_in_production
    ENV['RACK_ENV'] = 'production'
    app = FunApi::App.new { |api| }
    
    response = get '/introspect', app: app
    assert_equal 403, response.status
  ensure
    ENV['RACK_ENV'] = 'test'
  end
end
```

### Manual Testing

```bash
# Start demo app
ruby examples/introspection_endpoints_demo.rb

# Test endpoints
curl http://localhost:3000/introspect | jq
curl http://localhost:3000/introspect/routes | jq
curl http://localhost:3000/introspect/routes/POST/users | jq
curl http://localhost:3000/introspect/health | jq
curl "http://localhost:3000/introspect/routes?verb=POST" | jq
```

## Edge Cases

1. **Path encoding**: `/introspect/routes/GET/%2Fusers%2F%3Aid` for `/users/:id`
2. **Not found**: Return 404 with helpful message if route/dep/schema doesn't exist
3. **Empty app**: Handle apps with no routes gracefully
4. **Circular deps**: Handle if dependency graph has cycles (shouldn't happen but be safe)

## Success Criteria

- [ ] All 9 core endpoints implemented
- [ ] Query parameter filtering works
- [ ] Dev-only security enforced
- [ ] Tests for all endpoints
- [ ] Demo script works
- [ ] Response format consistent
- [ ] Documentation updated

## Future Enhancements (Out of Scope)

- WebSocket endpoint for live introspection updates
- GraphQL introspection endpoint
- OpenAPI enhancement endpoint
- Test generation endpoint (Phase 2B)
