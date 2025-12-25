---
title: Middleware
---

# Middleware

Middleware wraps your application, processing requests before handlers and responses after.

## Built-in Middleware

FunApi provides convenience methods for common middleware:

### CORS

Handle Cross-Origin Resource Sharing:

```ruby
api.add_cors(
  allow_origins: ['http://localhost:3000', 'https://myapp.com'],
  allow_methods: ['GET', 'POST', 'PUT', 'DELETE'],
  allow_headers: ['Content-Type', 'Authorization'],
  expose_headers: ['X-Request-Id'],
  max_age: 600,
  allow_credentials: true
)
```

For development, allow all origins:

```ruby
api.add_cors(allow_origins: ['*'])
```

### Request Logger

Log incoming requests:

```ruby
api.add_request_logger
```

With custom logger:

```ruby
api.add_request_logger(
  logger: Logger.new('logs/requests.log'),
  level: :info
)
```

### Trusted Host

Validate the Host header (security):

```ruby
api.add_trusted_host(
  allowed_hosts: ['myapp.com', 'api.myapp.com']
)
```

With regex patterns:

```ruby
api.add_trusted_host(
  allowed_hosts: ['localhost', /\.myapp\.com$/]
)
```

### Gzip Compression

Compress JSON responses:

```ruby
api.add_gzip
```

## Using Rack Middleware

Any Rack middleware works with FunApi:

```ruby
app = FunApi::App.new do |api|
  api.use Rack::Session::Cookie, secret: ENV['SESSION_SECRET']
  api.use Rack::Attack
  api.use Rack::ETag
end
```

## Custom Middleware

Create middleware following the Rack pattern:

```ruby
class TimingMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    start = Time.now
    status, headers, body = @app.call(env)
    duration = Time.now - start
    
    headers['X-Response-Time'] = "#{(duration * 1000).round}ms"
    [status, headers, body]
  end
end

app = FunApi::App.new do |api|
  api.use TimingMiddleware
end
```

### With Options

```ruby
class AuthMiddleware
  def initialize(app, secret:, exclude: [])
    @app = app
    @secret = secret
    @exclude = exclude
  end

  def call(env)
    path = env['PATH_INFO']
    
    if @exclude.include?(path)
      return @app.call(env)
    end

    token = env['HTTP_AUTHORIZATION']&.delete_prefix('Bearer ')
    
    unless valid_token?(token)
      return [401, {'content-type' => 'application/json'}, ['{"error":"Unauthorized"}']]
    end

    @app.call(env)
  end

  private

  def valid_token?(token)
    # Verify token with @secret
  end
end

app = FunApi::App.new do |api|
  api.use AuthMiddleware, 
    secret: ENV['JWT_SECRET'],
    exclude: ['/health', '/docs', '/openapi.json']
end
```

## Middleware Order

Middleware runs in the order registered (first in, first out):

```ruby
app = FunApi::App.new do |api|
  api.use LoggingMiddleware    # 1. Runs first
  api.use AuthMiddleware       # 2. Runs second
  api.use TimingMiddleware     # 3. Runs third
  
  # Then your routes handle the request
  # Response goes back through in reverse order
end
```

Request flow:
```
Request → Logging → Auth → Timing → Handler
Response ← Logging ← Auth ← Timing ← Handler
```

## Complete Example

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

app = FunApi::App.new(title: "My API") do |api|
  # Security
  api.add_trusted_host(allowed_hosts: ['localhost', 'myapi.com'])
  api.add_cors(allow_origins: ['https://myapp.com'])
  
  # Logging
  api.add_request_logger
  
  # Compression
  api.add_gzip
  
  # Custom
  api.use Rack::Session::Cookie, secret: 'secret'
  
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello!' }, 200]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```
