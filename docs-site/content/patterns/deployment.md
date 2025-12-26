---
title: Deployment
---

# Deployment

Deploy FunApi applications to production.

## Running with Falcon

FunApi uses Falcon as its server:

```ruby
# app.rb
require 'funapi'
require 'funapi/server/falcon'

app = FunApi::App.new do |api|
  # routes...
end

FunApi::Server::Falcon.start(app, 
  host: '0.0.0.0',
  port: ENV.fetch('PORT', 3000).to_i
)
```

```bash
ruby app.rb
```

## Environment Variables

Configure your app with environment variables:

```ruby
app = FunApi::App.new do |api|
  api.on_startup do
    DB.connect(ENV.fetch('DATABASE_URL'))
  end

  if ENV['RACK_ENV'] == 'production'
    api.add_trusted_host(allowed_hosts: [ENV['HOST']])
  end
end
```

## Docker

### Dockerfile

```dockerfile
FROM ruby:3.2-alpine

RUN apk add --no-cache build-base

WORKDIR /app

COPY Gemfile Gemfile.lock ./
RUN bundle install --without development test

COPY . .

EXPOSE 3000

CMD ["ruby", "app.rb"]
```

### docker-compose.yml

```yaml
version: '3.8'

services:
  web:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://postgres:password@db/myapp
      - RACK_ENV=production
    depends_on:
      - db

  db:
    image: postgres:15
    environment:
      - POSTGRES_PASSWORD=password
      - POSTGRES_DB=myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

## Fly.io

### fly.toml

```toml
app = "my-funapi-app"
primary_region = "iad"

[build]
  builder = "heroku/buildpacks:22"

[env]
  RACK_ENV = "production"

[http_service]
  internal_port = 3000
  force_https = true
  auto_stop_machines = true
  auto_start_machines = true
```

Deploy:

```bash
fly launch
fly deploy
```

## Render

Create a `render.yaml`:

```yaml
services:
  - type: web
    name: my-funapi-app
    env: ruby
    buildCommand: bundle install
    startCommand: ruby app.rb
    envVars:
      - key: RACK_ENV
        value: production
      - key: DATABASE_URL
        fromDatabase:
          name: mydb
          property: connectionString
```

## Production Checklist

### Security

```ruby
app = FunApi::App.new do |api|
  # Validate host header
  api.add_trusted_host(allowed_hosts: ['myapp.com', 'api.myapp.com'])
  
  # CORS with specific origins
  api.add_cors(allow_origins: ['https://myapp.com'])
end
```

### Logging

```ruby
api.add_request_logger(
  logger: Logger.new(STDOUT),
  level: :info
)
```

### Error Handling

Don't expose internal errors in production:

```ruby
class ProductionErrorHandler
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue => e
    # Log the real error
    Logger.new(STDOUT).error("#{e.class}: #{e.message}")
    
    # Return generic message
    [500, {'content-type' => 'application/json'}, 
     ['{"detail":"Internal server error"}']]
  end
end

app = FunApi::App.new do |api|
  api.use ProductionErrorHandler if ENV['RACK_ENV'] == 'production'
end
```

### Health Check

```ruby
api.get '/health' do |input, req, task|
  [{ status: 'ok', time: Time.now.iso8601 }, 200]
end
```

### Graceful Shutdown

FunApi handles SIGINT and SIGTERM automatically, running shutdown hooks before exiting.

```ruby
api.on_shutdown do
  puts "Draining connections..."
  ConnectionPool.shutdown
end
```
