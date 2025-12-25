---
title: FunApi
---

# FunApi

A minimal, async-first Ruby web framework inspired by FastAPI.

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

app = FunApi::App.new(title: "My API", version: "1.0.0") do |api|
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello, World!' }, 200]
  end

  api.post '/users', body: UserSchema do |input, req, task|
    [{ created: input[:body] }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

Visit `http://localhost:3000/docs` to see your interactive API documentation.

## Key Features

- **Async-first** - Built on Falcon and Ruby's Async library for high-performance concurrent operations
- **Simple validation** - Using dry-schema for straightforward request/response validation
- **Auto-documentation** - Automatic OpenAPI/Swagger docs generated from your code
- **Minimal magic** - Clear, explicit APIs without heavy DSLs
- **Rack-compatible** - Works with any Rack middleware

## Standing on Giants

FunApi brings together proven Ruby libraries:

- **[Falcon](https://github.com/socketry/falcon)** - High-performance async HTTP server
- **[dry-schema](https://dry-rb.org/gems/dry-schema/)** - Powerful, composable validation

## Installation

Add to your Gemfile:

```ruby
gem 'fun_api'
```

Then run:

```bash
bundle install
```

## Quick Example

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

app = FunApi::App.new do |api|
  api.get '/hello/:name' do |input, req, task|
    name = input[:path]['name']
    [{ message: "Hello, #{name}!" }, 200]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

```bash
$ curl http://localhost:3000/hello/world
{"message":"Hello, world!"}
```
