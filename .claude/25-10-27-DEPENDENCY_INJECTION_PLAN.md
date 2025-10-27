# Dependency Injection Implementation Plan

## Date: 2024-10-27

## Goal

Implement FastAPI-style dependency injection for FunApi, providing a flexible, lightweight system that allows injecting dependencies into route handlers without heavy external frameworks.

## Research Summary

### FastAPI's Dependency Injection

**Core Mechanism:**
```python
from fastapi import Depends

def common_parameters(q: str = None):
    return {"q": q}

@app.get("/items/")
async def read_items(commons: dict = Depends(common_parameters)):
    return commons
```

**Key Features:**
1. Dependencies are functions that can take same parameters as path operations
2. `Depends()` wrapper marks parameters as dependencies
3. Dependencies can have sub-dependencies (nested)
4. Dependencies can be callable classes (using `__init__` for params, `__call__` for execution)
5. Dependencies with `yield` for setup/teardown
6. Type aliases for reusable dependency declarations
7. Integrated with OpenAPI documentation

**Execution Flow:**
1. FastAPI inspects route handler signature
2. Identifies parameters with `Depends()`
3. Executes dependency functions with their own dependencies
4. Injects results into route handler parameters

### Ruby Ecosystem Review

**dry-system + dry-auto_inject:**
- Full-featured DI framework
- Constructor injection focused
- Requires container setup, auto-registration
- Heavy for FunApi's minimal philosophy

**dry-container:**
- Simple key-value container
- Manual registration required
- Good for complex apps but overkill for our use case

**Recommendation: Custom Lightweight Implementation**
- Align with FunApi's minimal, explicit philosophy
- FastAPI-like API adapted to Ruby idioms
- No heavy dependencies beyond what we already use
- Clear, simple implementation users can understand

## Design

### API Design (Ruby-Idiomatic)

```ruby
# Define a dependency (just a proc, lambda, or method)
def get_db
  Database.connect
end

def get_current_user(req:, db: Depends(get_db))
  token = req.env['HTTP_AUTHORIZATION']
  db.find_user_by_token(token) || raise FunApi::HTTPException.new(status_code: 401)
end

# Use in routes
api.get '/users/:id', deps: { db: get_db } do |input, req, task, db:|
  user = db.find(input[:path]['id'])
  [user, 200]
end

# Or with Depends for sub-dependencies
api.get '/profile', deps: { user: get_current_user } do |input, req, task, user:|
  [user, 200]
end

# Class-based dependencies (callable)
class Paginator
  def initialize(max_limit: 100)
    @max_limit = max_limit
  end
  
  def call(limit: 10, offset: 0)
    {
      limit: [limit, @max_limit].min,
      offset: offset
    }
  end
end

pagination = Paginator.new(max_limit: 50)

api.get '/items', deps: { page: pagination } do |input, req, task, page:|
  [{ pagination: page }, 200]
end
```

### Alternative Syntax (More Ruby-like)

After consideration, let's use a simpler approach:

```ruby
# Dependencies as keyword arguments to route
api.get '/users/:id',
  depends: { db: -> { Database.connect } } do |input, req, task, db:|
  user = db.find(input[:path]['id'])
  [user, 200]
end

# Or use a helper for cleaner syntax
def db_connection
  -> { Database.connect }
end

api.get '/users/:id',
  depends: { db: db_connection } do |input, req, task, db:|
  user = db.find(input[:path]['id'])
  [user, 200]
end
```

### Core Components

1. **FunApi::Depends** - Wrapper class to mark dependencies with sub-dependencies
2. **Dependency Resolution** - Mechanism to resolve dependency graph
3. **Route Handler Enhancement** - Inject resolved dependencies as keyword args
4. **OpenAPI Integration** - Document dependencies in spec

### Implementation Strategy

**Phase 1: Core Functionality**
1. Create `FunApi::Depends` class
2. Add `depends:` parameter to route definition
3. Implement dependency resolution in request handling
4. Support simple dependencies (procs/lambdas)

**Phase 2: Advanced Features**
5. Support class-based dependencies (callable)
6. Support sub-dependencies (nested Depends)
7. Handle request-scoped dependencies

**Phase 3: Integration**
8. OpenAPI documentation
9. Error handling for dependency failures
10. Testing utilities

## Detailed Implementation

### 1. FunApi::Depends Class

```ruby
# lib/fun_api/depends.rb
module FunApi
  class Depends
    attr_reader :dependency, :kwargs
    
    def initialize(dependency, **kwargs)
      @dependency = dependency
      @kwargs = kwargs
    end
    
    def call(context)
      resolved_kwargs = resolve_kwargs(context)
      
      if @dependency.respond_to?(:call)
        if @dependency.arity == 0 || @dependency.arity == -1
          # Lambda/Proc with no args or variable args
          @dependency.call(**resolved_kwargs)
        else
          @dependency.call(**resolved_kwargs)
        end
      else
        raise ArgumentError, "Dependency must be callable"
      end
    end
    
    private
    
    def resolve_kwargs(context)
      @kwargs.transform_values do |value|
        if value.is_a?(Depends)
          value.call(context)
        elsif value.respond_to?(:call)
          value.call
        else
          value
        end
      end
    end
  end
end
```

### 2. Route Definition Enhancement

```ruby
# In lib/fun_api/application.rb

def add_route(verb, path, body: nil, query: nil, response_schema: nil, depends: {}, &handler)
  route = {
    handler: handler,
    body_schema: body,
    query_schema: query,
    response_schema: response_schema,
    dependencies: normalize_dependencies(depends)
  }
  
  router.add_route(verb, path, route)
end

private

def normalize_dependencies(depends)
  depends.transform_values do |dep|
    if dep.is_a?(Depends)
      dep
    elsif dep.respond_to?(:call)
      Depends.new(dep)
    else
      raise ArgumentError, "Dependency must be callable or Depends instance"
    end
  end
end
```

### 3. Dependency Resolution in Request Handling

```ruby
# In lib/fun_api/application.rb (call method)

def call(env)
  Async do |task|
    # ... existing route matching code ...
    
    # Resolve dependencies
    dependency_context = {
      input: validated_input,
      req: request,
      task: task
    }
    
    resolved_deps = resolve_dependencies(
      route[:dependencies],
      dependency_context
    )
    
    # Call handler with dependencies as keyword arguments
    response_data, status_code = handler.call(
      validated_input,
      request,
      task,
      **resolved_deps
    )
    
    # ... rest of response handling ...
  end.wait
end

private

def resolve_dependencies(dependencies, context)
  dependencies.transform_values do |dep|
    dep.call(context)
  end
rescue => e
  # Convert to HTTPException
  raise FunApi::HTTPException.new(
    status_code: 500,
    detail: "Dependency resolution failed: #{e.message}"
  )
end
```

### 4. Support for Request Parameters in Dependencies

Dependencies should be able to access request data:

```ruby
# Dependencies can declare what they need
api.get '/profile',
  depends: {
    user: ->(req:) {
      token = req.env['HTTP_AUTHORIZATION']
      find_user_by_token(token)
    }
  } do |input, req, task, user:|
  [{ user: user }, 200]
end
```

Implementation:
```ruby
class Depends
  def call(context)
    # Introspect what the dependency needs
    params = {}
    
    if @dependency.respond_to?(:parameters)
      @dependency.parameters.each do |type, name|
        next unless type == :keyreq || type == :key
        
        # Provide from context
        params[name] = context[name] if context.key?(name)
      end
    end
    
    # Merge with sub-dependencies
    params.merge!(resolve_kwargs(context))
    
    @dependency.call(**params)
  end
end
```

### 5. Class-based Dependencies

```ruby
class DatabaseConnection
  def call(req:, task:)
    # Use task for async operations if needed
    task.async { connect_to_db }.wait
  end
  
  private
  
  def connect_to_db
    Database.connect
  end
end

db_dep = DatabaseConnection.new

api.get '/users',
  depends: { db: db_dep } do |input, req, task, db:|
  users = db.all_users
  [users, 200]
end
```

### 6. Parameterized Dependencies (Callable Classes)

```ruby
class Paginator
  def initialize(max_limit: 100)
    @max_limit = max_limit
  end
  
  def call(input:)
    limit = [input[:query][:limit] || 10, @max_limit].min
    offset = input[:query][:offset] || 0
    { limit: limit, offset: offset }
  end
end

api.get '/items',
  query: PaginationSchema,
  depends: { page: Paginator.new(max_limit: 50) } do |input, req, task, page:|
  items = Item.limit(page[:limit]).offset(page[:offset])
  [items, 200]
end
```

### 7. Nested Dependencies (Sub-dependencies)

```ruby
def get_db
  ->(task:) { 
    task.async { Database.connect }.wait 
  }
end

def get_current_user
  ->(req:, db: FunApi::Depends(get_db)) {
    token = req.env['HTTP_AUTHORIZATION']
    db.find_user_by_token(token) || raise FunApi::HTTPException.new(status_code: 401)
  }
end

api.get '/profile',
  depends: { user: get_current_user } do |input, req, task, user:|
  [user, 200]
end
```

## Testing Strategy

### Unit Tests

```ruby
# test/test_depends.rb
class TestDepends < Minitest::Test
  def test_simple_dependency
    dep = FunApi::Depends.new(-> { "hello" })
    result = dep.call({})
    assert_equal "hello", result
  end
  
  def test_dependency_with_context
    dep = FunApi::Depends.new(->(req:) { req[:value] })
    result = dep.call(req: { value: 42 })
    assert_equal 42, result
  end
  
  def test_nested_dependencies
    db = FunApi::Depends.new(-> { "db_connection" })
    user = FunApi::Depends.new(->(db:) { "user_from_#{db}" }, db: db)
    
    result = user.call({})
    assert_equal "user_from_db_connection", result
  end
end

# test/test_dependency_injection.rb
class TestDependencyInjection < Minitest::Test
  def test_route_with_simple_dependency
    app = FunApi::App.new do |api|
      api.get '/test',
        depends: { value: -> { 42 } } do |input, req, task, value:|
        [{ value: value }, 200]
      end
    end
    
    res = async_request(app, :get, '/test')
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 42, data[:value]
  end
  
  def test_route_with_request_context_dependency
    app = FunApi::App.new do |api|
      api.get '/test',
        depends: { 
          auth: ->(req:) { req.env['HTTP_AUTHORIZATION'] }
        } do |input, req, task, auth:|
        [{ token: auth }, 200]
      end
    end
    
    res = async_request(app, :get, '/test', 'HTTP_AUTHORIZATION' => 'Bearer token123')
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 'Bearer token123', data[:token]
  end
  
  def test_route_with_nested_dependencies
    app = FunApi::App.new do |api|
      db = -> { { users: [{ id: 1, name: 'Alice' }] } }
      user = ->(db:) { db[:users].first }
      
      api.get '/user',
        depends: { 
          current_user: FunApi::Depends.new(user, db: FunApi::Depends.new(db))
        } do |input, req, task, current_user:|
        [current_user, 200]
      end
    end
    
    res = async_request(app, :get, '/user')
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 'Alice', data[:name]
  end
  
  def test_class_based_dependency
    class TestDep
      def call
        "from_class"
      end
    end
    
    app = FunApi::App.new do |api|
      api.get '/test',
        depends: { value: TestDep.new } do |input, req, task, value:|
        [{ value: value }, 200]
      end
    end
    
    res = async_request(app, :get, '/test')
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "from_class", data[:value]
  end
end
```

### Integration Tests

Test with real-world scenarios:
- Database connections
- Authentication/authorization
- Rate limiting
- Caching

## OpenAPI Integration

Dependencies should appear in OpenAPI spec when they affect request parameters:

```ruby
# If dependency uses query params, document them
api.get '/items',
  query: PaginationSchema,
  depends: { page: Paginator.new } do |input, req, task, page:|
  # The PaginationSchema is documented
  # The page dependency transforms those params
end
```

Dependencies themselves don't need to appear in OpenAPI (they're implementation details), but their effects on the API should be documented through schemas.

## Error Handling

```ruby
# Dependency raises exception
def require_auth
  ->(req:) {
    token = req.env['HTTP_AUTHORIZATION']
    raise FunApi::HTTPException.new(
      status_code: 401,
      detail: "Not authenticated"
    ) unless token
    verify_token(token)
  }
end

# FunApi should catch and convert to proper HTTP response
api.get '/protected',
  depends: { user: require_auth } do |input, req, task, user:|
  [{ user: user }, 200]
end
```

## Examples

### Authentication Example

```ruby
# examples/dependency_auth.rb
require 'fun_api'
require 'fun_api/server/falcon'

class AuthError < FunApi::HTTPException
  def initialize(detail = "Not authenticated")
    super(status_code: 401, detail: detail)
  end
end

FAKE_DB = {
  "token123" => { id: 1, name: "Alice", email: "alice@example.com" },
  "token456" => { id: 2, name: "Bob", email: "bob@example.com" }
}

def get_current_user
  ->(req:) {
    auth = req.env['HTTP_AUTHORIZATION']
    raise AuthError.new unless auth
    
    token = auth.split(' ').last
    user = FAKE_DB[token]
    raise AuthError.new("Invalid token") unless user
    
    user
  }
end

def get_admin_user
  ->(user: FunApi::Depends.new(get_current_user)) {
    raise FunApi::HTTPException.new(
      status_code: 403,
      detail: "Not authorized"
    ) unless user[:name] == "Alice"
    
    user
  }
end

app = FunApi::App.new(
  title: "Dependency Injection Auth Demo",
  version: "1.0.0"
) do |api|
  api.get '/public' do |input, req, task|
    [{ message: "Public endpoint" }, 200]
  end
  
  api.get '/profile',
    depends: { user: get_current_user } do |input, req, task, user:|
    [user, 200]
  end
  
  api.get '/admin',
    depends: { admin: get_admin_user } do |input, req, task, admin:|
    [{ message: "Admin area", user: admin }, 200]
  end
end

puts "Starting server on http://localhost:3000"
puts "Try:"
puts "  curl http://localhost:3000/public"
puts "  curl -H 'Authorization: Bearer token123' http://localhost:3000/profile"
puts "  curl -H 'Authorization: Bearer token123' http://localhost:3000/admin"
puts "  curl -H 'Authorization: Bearer token456' http://localhost:3000/admin"

FunApi::Server::Falcon.start(app, port: 3000)
```

### Database Connection Example

```ruby
# examples/dependency_database.rb
class Database
  def self.connect
    new
  end
  
  def find_user(id)
    { id: id, name: "User #{id}" }
  end
  
  def all_users
    [
      { id: 1, name: "Alice" },
      { id: 2, name: "Bob" }
    ]
  end
end

app = FunApi::App.new do |api|
  db_connection = -> { Database.connect }
  
  api.get '/users',
    depends: { db: db_connection } do |input, req, task, db:|
    users = db.all_users
    [users, 200]
  end
  
  api.get '/users/:id',
    depends: { db: db_connection } do |input, req, task, db:|
    user = db.find_user(input[:path]['id'].to_i)
    [user, 200]
  end
end
```

### Pagination Example

```ruby
# examples/dependency_pagination.rb
class Paginator
  def initialize(max_limit: 100)
    @max_limit = max_limit
  end
  
  def call(input:)
    limit = input[:query][:limit] || 10
    offset = input[:query][:offset] || 0
    
    {
      limit: [limit.to_i, @max_limit].min,
      offset: offset.to_i
    }
  end
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

app = FunApi::App.new do |api|
  pagination = Paginator.new(max_limit: 50)
  
  api.get '/items',
    query: QuerySchema,
    depends: { page: pagination } do |input, req, task, page:|
    
    items = (1..100).to_a
    paginated = items[page[:offset], page[:limit]]
    
    [{
      items: paginated,
      pagination: page,
      total: items.length
    }, 200]
  end
end
```

## Implementation Checklist

**Phase 1: Core (MVP)**
- [ ] Create `FunApi::Depends` class
- [ ] Add `depends:` parameter to `add_route`
- [ ] Implement basic dependency resolution
- [ ] Support proc/lambda dependencies
- [ ] Write core tests
- [ ] Update AGENTS.md with new patterns

**Phase 2: Advanced**
- [ ] Support class-based dependencies (callable)
- [ ] Support nested dependencies
- [ ] Request context injection (req, input, task)
- [ ] Write advanced tests
- [ ] Create example: authentication
- [ ] Create example: database connection
- [ ] Create example: pagination

**Phase 3: Polish**
- [ ] Error handling for dependency failures
- [ ] OpenAPI integration (if applicable)
- [ ] Performance optimization
- [ ] Documentation in README.md
- [ ] Add to DECISIONS.md

## Open Questions

1. **Dependency Caching**: Should dependencies be cached per-request?
   - Probably yes for request-scoped dependencies
   - Need to ensure same dependency called multiple times returns same instance
   
2. **Dependency with `yield`**: Support setup/teardown pattern?
   - Could be useful for database connections
   - Would need to track lifecycle carefully
   
3. **Global Dependencies**: Should we support app-level dependencies?
   - FastAPI has this
   - Could be useful for common auth, logging, etc.

4. **Testing Helpers**: How to override dependencies in tests?
   - FastAPI has dependency overrides
   - Could be very useful for testing

## Success Criteria

1. Clean, Ruby-idiomatic API that feels natural
2. Supports common use cases: auth, database, pagination
3. Works seamlessly with existing FunApi features
4. Well-tested with comprehensive test suite
5. Clear documentation and examples
6. No performance degradation for routes without dependencies

## Future Enhancements

- Dependency overrides for testing
- Background task dependencies
- Dependency lifecycle hooks (setup/teardown with yield)
- Global/application-level dependencies
- Dependency graph visualization/debugging tools
