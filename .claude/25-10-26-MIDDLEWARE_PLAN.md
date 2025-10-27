# Middleware Implementation Plan

## Goal

Implement a comprehensive middleware system for FunApi that leverages the battle-tested Rack middleware ecosystem while providing FastAPI-like convenience methods.

## Architecture Decision: Hybrid Approach

Support both standard Rack middleware AND FunApi-specific convenience wrappers:

```ruby
# 1. Standard Rack middleware (existing ecosystem)
app = FunApi::App.new do |api|
  api.use Rack::Cors do |config|
    config.allow do |allow|
      allow.origins '*'
      allow.resource '*', headers: :any, methods: [:get, :post]
    end
  end
end

# 2. FunApi-specific middleware (FastAPI-style convenience)
app = FunApi::App.new do |api|
  api.add_cors(
    allow_origins: ['*'],
    allow_methods: ['*'],
    allow_headers: ['*']
  )
  
  # Or custom FunApi middleware with async support
  api.use FunApi::Middleware::RateLimit, max_requests: 100, window: 60
end
```

## Implementation Phases

### Phase 1: Core Middleware System ⭐⭐⭐⭐⭐

**File**: `lib/fun_api/application.rb`

**Changes**:
1. Uncomment and fix `build_middleware_chain` method (lines 144-152)
2. Add `use(middleware, *args, &block)` method
3. Update `call(env)` to use middleware chain instead of router directly
4. Ensure middleware is applied in correct order (LIFO - Last In, First Out)

**Why First**: This unblocks everything else and enables the entire Rack ecosystem.

**Implementation**:
```ruby
class App
  def use(middleware, *args, &block)
    @middleware_stack << [middleware, args, block]
    self
  end
  
  def call(env)
    app = build_middleware_chain
    app.call(env)
  end
  
  private
  
  def build_middleware_chain
    # Start with router as the innermost app
    app = @router
    
    # Wrap with middleware in reverse order (LIFO)
    @middleware_stack.reverse_each do |middleware, args, block|
      app = middleware.new(app, *args, &block)
    end
    
    app
  end
end
```

### Phase 2: Built-in Middleware ⭐⭐⭐⭐

Create FunApi-specific middleware with async awareness and FastAPI-style convenience.

#### A. Base Middleware Class
**File**: `lib/fun_api/middleware/base.rb`

```ruby
module FunApi
  module Middleware
    class Base
      def initialize(app)
        @app = app
      end
      
      def call(env)
        @app.call(env)
      end
    end
  end
end
```

#### B. CORS Middleware (Delegate to rack-cors)
**File**: `lib/fun_api/middleware/cors.rb`

Wrapper around the battle-tested `rack-cors` gem.

```ruby
module FunApi
  module Middleware
    class Cors
      def self.new(app, allow_origins: ['*'], allow_methods: ['*'], 
                   allow_headers: ['*'], expose_headers: [], 
                   max_age: 600, allow_credentials: false)
        require 'rack/cors'
        
        Rack::Cors.new(app) do |config|
          config.allow do |allow|
            allow.origins(*allow_origins)
            allow.resource '*',
              methods: allow_methods,
              headers: allow_headers,
              expose: expose_headers,
              max_age: max_age,
              credentials: allow_credentials
          end
        end
      end
    end
  end
  
  class App
    def add_cors(**options)
      use FunApi::Middleware::Cors, **options
    end
  end
end
```

**Dependencies**: Add `rack-cors` to gemspec

#### C. Trusted Host Middleware
**File**: `lib/fun_api/middleware/trusted_host.rb`

Validates the `Host` header to prevent host header attacks.

```ruby
module FunApi
  module Middleware
    class TrustedHost < Base
      def initialize(app, allowed_hosts: [])
        super(app)
        @allowed_hosts = Array(allowed_hosts)
      end
      
      def call(env)
        host = env['HTTP_HOST']&.split(':')&.first
        
        unless host_allowed?(host)
          return [
            400,
            {'content-type' => 'application/json'},
            [JSON.dump(detail: 'Invalid host header')]
          ]
        end
        
        @app.call(env)
      end
      
      private
      
      def host_allowed?(host)
        return true if @allowed_hosts.empty?
        @allowed_hosts.any? { |pattern|
          pattern.is_a?(Regexp) ? pattern.match?(host) : pattern == host
        }
      end
    end
  end
  
  class App
    def add_trusted_host(allowed_hosts:)
      use FunApi::Middleware::TrustedHost, allowed_hosts: allowed_hosts
    end
  end
end
```

#### D. Request Logger Middleware
**File**: `lib/fun_api/middleware/request_logger.rb`

Logs incoming requests with timing information.

```ruby
module FunApi
  module Middleware
    class RequestLogger < Base
      def initialize(app, logger: nil, level: :info)
        super(app)
        @logger = logger || Logger.new($stdout)
        @level = level
      end
      
      def call(env)
        start = Time.now
        status, headers, body = @app.call(env)
        duration = Time.now - start
        
        log_request(env, status, duration)
        
        [status, headers, body]
      end
      
      private
      
      def log_request(env, status, duration)
        request = Rack::Request.new(env)
        @logger.send(@level,
          "#{request.request_method} #{request.path} " \
          "#{status} #{(duration * 1000).round(2)}ms"
        )
      end
    end
  end
  
  class App
    def add_request_logger(logger: nil, level: :info)
      use FunApi::Middleware::RequestLogger, logger: logger, level: level
    end
  end
end
```

#### E. Gzip Compression (Delegate to Rack::Deflater)
**File**: Convenience method only

```ruby
class App
  def add_gzip
    use Rack::Deflater, if: ->(env, status, headers, body) {
      headers['content-type']&.start_with?('application/json')
    }
  end
end
```

### Phase 3: Documentation & Examples ⭐⭐⭐

#### Update README.md
Add middleware section with examples:
- Basic middleware usage
- Built-in middleware
- Compatible Rack middleware ecosystem
- Custom middleware creation

#### Create Example App
**File**: `examples/middleware_demo.rb`

Demonstrate all middleware features.

### Phase 4: Testing ⭐⭐⭐⭐

**File**: `test/test_middleware.rb`

Test:
- Middleware ordering (LIFO)
- Built-in middleware functionality
- Async compatibility
- Integration with Rack middleware
- Edge cases (no middleware, single middleware, multiple middleware)

## Benefits

1. ✅ **Leverage Ruby ecosystem** - All existing Rack middleware works out of the box
2. ✅ **Battle-tested** - Rack middleware pattern is 15+ years proven
3. ✅ **FastAPI-like DX** - Convenience methods (`add_cors`, `add_gzip`) for common needs
4. ✅ **Flexibility** - Support both Rack standard and custom middleware
5. ✅ **Async-compatible** - Rack 3.0+ supports async natively
6. ✅ **Zero reinvention** - Delegate to proven gems (rack-cors, rack-deflater)

## Compatible Rack Middleware (to document)

Popular Rack middleware that works immediately:

```ruby
# Rate limiting
gem 'rack-attack'
app.use Rack::Attack

# Authentication
gem 'warden'
app.use Warden::Manager

# Caching
app.use Rack::Cache

# ETags
app.use Rack::ETag

# Conditional GET
app.use Rack::ConditionalGet

# Static files
app.use Rack::Static, urls: ['/public']

# Session
app.use Rack::Session::Cookie, secret: 'your_secret'
```

## Implementation Checklist

### Phase 1: Core System
- [ ] Add `use` method to `App` class
- [ ] Implement `build_middleware_chain` method
- [ ] Update `call` method to use middleware chain
- [ ] Test with existing Rack middleware (Rack::Cors)
- [ ] Ensure middleware ordering is correct (LIFO)

### Phase 2: Built-in Middleware
- [ ] Create `lib/fun_api/middleware/base.rb`
- [ ] Create `lib/fun_api/middleware/cors.rb` (wrapper)
- [ ] Create `lib/fun_api/middleware/trusted_host.rb`
- [ ] Create `lib/fun_api/middleware/request_logger.rb`
- [ ] Add convenience methods: `add_cors`, `add_gzip`, etc.
- [ ] Add `rack-cors` to gemspec dependencies

### Phase 3: Documentation
- [ ] Update README with middleware section
- [ ] Document built-in middleware
- [ ] List compatible Rack middleware
- [ ] Create middleware guide
- [ ] Add examples for common use cases (auth, CORS, logging)
- [ ] Create `examples/middleware_demo.rb`

### Phase 4: Testing
- [ ] Create `test/test_middleware.rb`
- [ ] Test middleware ordering
- [ ] Test async compatibility
- [ ] Test with popular Rack middleware
- [ ] Integration tests for built-in middleware
- [ ] Edge case testing

## Questions Resolved

**Q: Should we leverage Rack for middleware?**
A: YES! Rack middleware is battle-tested and gives us access to the entire Ruby ecosystem. We should support standard Rack middleware while providing FastAPI-style convenience wrappers.

**Q: Which middleware should be built-in vs ecosystem?**
A: 
- **Built-in**: CORS (wrapped), TrustedHost, RequestLogger (most common needs)
- **Ecosystem**: Rate limiting (rack-attack), Auth (warden), Caching (rack-cache)
- **Delegate to Rack**: Gzip (Rack::Deflater), ETag (Rack::ETag)

**Q: How to maintain async compatibility?**
A: Rack 3.0+ already supports async via Fiber/Async. Our middleware just needs to follow standard Rack interface (`call(env)` returns `[status, headers, body]`).
