# Dependency Injection Implementation Summary

## Date: 2024-10-27

## What We Built

A complete FastAPI-inspired dependency injection system for FunApi with a **Ruby-idiomatic block-based cleanup pattern**.

## Key Features Implemented

### 1. Dependency Registration with Cleanup

**Three supported patterns:**

```ruby
# 1. Simple (no cleanup)
api.register(:config) { Config.load }

# 2. Tuple pattern (backward compatible)
api.register(:cache) do
  [Cache.new, -> { Cache.shutdown }]
end

# 3. Block with ensure (RECOMMENDED - most Ruby-like)
api.register(:db) do |provide|
  conn = Database.connect
  provide.call(conn)
ensure
  conn.close
end
```

### 2. Request-Scoped Caching

Dependencies resolved once per request, even if referenced multiple times:

```ruby
api.get '/dashboard',
  depends: { db1: :db, db2: :db } do |input, req, task, db1:, db2:|
  # db1 and db2 are the SAME instance
  # Connection opened once, closed once
end
```

### 3. Automatic Cleanup

Cleanup runs in `ensure` block:
- ✅ Always runs after response sent
- ✅ Runs even if handler raises error
- ✅ Runs even if earlier cleanup fails
- ✅ Failures logged but don't break response

### 4. Nested Dependencies

```ruby
api.register(:db) { |provide| ... }

def get_current_user
  ->(req:, db:) { authenticate(req, db) }
end

api.get '/profile',
  depends: { user: FunApi::Depends(get_current_user, db: :db) }
```

### 5. Multiple Dependency Styles

```ruby
# Array syntax
api.get '/test', depends: [:db, :cache]

# Hash with symbols
api.get '/test', depends: { db: nil, cache: nil }

# Hash with inline lambdas
api.get '/test', depends: { value: -> { 42 } }

# Hash with callable classes
api.get '/test', depends: { page: Paginator.new(max: 50) }
```

## Architecture

### Component Structure

```
lib/fun_api/
├── depends.rb              # Depends wrapper for nested deps
├── dependency_wrapper.rb   # Three wrapper types
│   ├── SimpleDependency    # No cleanup
│   ├── ManagedDependency   # Tuple pattern
│   └── BlockDependency     # Block with ensure (Fiber-based)
└── application.rb          # Container & resolution logic
```

### Fiber-Based Lifecycle

`BlockDependency` uses Ruby Fiber for resource lifecycle:

```ruby
class BlockDependency
  def call
    @fiber = Fiber.new do
      @block.call(proc { |resource|
        Fiber.yield resource  # Provide to handler
      })
    end
    @resource = @fiber.resume  # Get resource
  end

  def cleanup
    @fiber.resume if @fiber.alive?  # Trigger ensure block
  end
end
```

### Resolution Flow

1. Route handler matched
2. Dependencies normalized (detect pattern type)
3. Dependencies resolved (with caching)
4. Handler called with injected kwargs
5. Response prepared
6. **Cleanup runs in ensure block**

## Test Coverage

**121 tests, 281 assertions, all passing**

Test files:
- `test/test_depends.rb` - Depends class unit tests (12 tests)
- `test/test_dependency_injection.rb` - Integration tests (12 tests)
- `test/test_dependency_cleanup.rb` - Cleanup behavior (7 tests)
- All existing tests still pass (90 tests)

## FastAPI Alignment

Our pattern matches FastAPI's dependencies with yield:

**Python:**
```python
def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/users")
def read_users(db: Session = Depends(get_db)):
    return db.query(User).all()
```

**Ruby:**
```ruby
api.register(:db) do |provide|
  db = Database.connect
  provide.call(db)
ensure
  db.close
end

api.get '/users', depends: [:db] do |input, req, task, db:|
  [db.all_users, 200]
end
```

## Design Decisions

### Why Block-Based Pattern?

1. **Most idiomatic Ruby** - Matches patterns like:
   - `File.open { |f| ... }`
   - `Dir.chdir { ... }`
   - `Mutex.synchronize { ... }`

2. **Safety** - `ensure` guarantees cleanup runs

3. **Can't forget** - Cleanup is built into the pattern

4. **Explicit lifecycle** - Clear setup → use → cleanup flow

5. **FastAPI parity** - Same concept as context managers

### Why Not Dry-System/Dry-Effects?

- Too heavy for FunApi's minimal philosophy
- Constructor injection vs parameter injection mismatch
- Adds significant complexity
- Our custom solution is simpler and more aligned

### Tuple Pattern Still Supported

For backward compatibility and simple cases:
```ruby
api.register(:cache) { [Cache.new, -> { Cache.shutdown }] }
```

## Examples

Created three comprehensive examples:
1. `examples/dependency_injection_demo.rb` - Full auth example with nested deps
2. `examples/dependency_cleanup_demo.rb` - Shows cleanup lifecycle (tuple pattern)
3. `examples/dependency_block_demo.rb` - Shows new block pattern (RECOMMENDED)

## Usage Patterns

### Database Connection

```ruby
api.register(:db) do |provide|
  conn = Database.connect
  puts "✅ Connection opened"
  provide.call(conn)
ensure
  conn&.close
  puts "❌ Connection closed"
end
```

### File Handles

```ruby
api.register(:log_file) do |provide|
  file = File.open('app.log', 'a')
  provide.call(file)
ensure
  file&.close
end
```

### Transactions

```ruby
api.register(:transaction) do |provide|
  tx = db.begin_transaction
  begin
    provide.call(tx)
    tx.commit
  rescue
    tx.rollback
    raise
  ensure
    tx.close
  end
end
```

### Authentication (Nested)

```ruby
api.register(:db) { |provide| ... }

def require_auth
  ->(req:, db:) {
    token = req.env['HTTP_AUTHORIZATION']
    user = db.find_user_by_token(token)
    raise HTTPException.new(status_code: 401) unless user
    user
  }
end

api.get '/profile',
  depends: { user: FunApi::Depends(require_auth, db: :db) }
```

## Performance Considerations

- **Request-scoped caching** - Dependencies resolved once per request
- **No overhead without deps** - Routes without dependencies have no DI overhead  
- **Fiber cost** - Minimal (Ruby Fibers are lightweight)
- **Cleanup always runs** - Even on errors, no resource leaks

## Future Enhancements

Could add later (not needed now):
- Global dependencies (apply to all routes)
- Dependency overrides for testing
- Async context managers (for async resources)
- Dependency graph visualization

## Migration Guide

For users upgrading from tuple pattern:

**Before:**
```ruby
api.register(:db) do
  conn = Database.connect
  [conn, -> { conn.close }]
end
```

**After (recommended):**
```ruby
api.register(:db) do |provide|
  conn = Database.connect
  provide.call(conn)
ensure
  conn.close
end
```

Both patterns work! The block pattern is recommended for better Ruby idioms.

## Success Metrics

✅ All 121 tests passing
✅ Zero regressions
✅ FastAPI parity achieved
✅ Ruby-idiomatic API
✅ Production-ready

## References

- FastAPI Dependencies: https://fastapi.tiangolo.com/tutorial/dependencies/
- FastAPI with yield: https://fastapi.tiangolo.com/tutorial/dependencies/dependencies-with-yield/
- Ruby Fiber documentation
- dry-rb ecosystem review

---

**Status:** ✅ Complete and production-ready
**Date:** October 27, 2024
**Tests:** 121 passing, 281 assertions
