---
title: Quick Start
---

# Quick Start

Get a FunApi application running in under 5 minutes.

## Installation

Add FunApi to your Gemfile:

```ruby
gem 'fun_api'
```

Then install:

```bash
bundle install
```

## Create Your First App

Create a file called `app.rb`:

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

app = FunApi::App.new(
  title: "My First API",
  version: "1.0.0"
) do |api|
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello, World!' }, 200]
  end

  api.get '/hello/:name' do |input, req, task|
    name = input[:path]['name']
    [{ message: "Hello, #{name}!" }, 200]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

## Run It

```bash
ruby app.rb
```

You should see:

```
Falcon listening on 0.0.0.0:3000
Try: curl http://0.0.0.0:3000/hello
Press Ctrl+C to stop
```

## Test It

```bash
$ curl http://localhost:3000/hello
{"message":"Hello, World!"}

$ curl http://localhost:3000/hello/Ruby
{"message":"Hello, Ruby!"}
```

## Check the Docs

Open your browser to `http://localhost:3000/docs`

You'll see interactive Swagger UI documentation automatically generated from your routes.

## Add Validation

Let's add a POST endpoint with request validation:

```ruby
require 'fun_api'
require 'fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

app = FunApi::App.new(title: "My API") do |api|
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello, World!' }, 200]
  end

  api.post '/users', body: UserSchema do |input, req, task|
    user = input[:body]
    # user is already validated!
    [{ created: user }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
```

Test the validation:

```bash
# Valid request
$ curl -X POST http://localhost:3000/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Alice","email":"alice@example.com"}'
{"created":{"name":"Alice","email":"alice@example.com"}}

# Invalid request (missing email)
$ curl -X POST http://localhost:3000/users \
  -H 'Content-Type: application/json' \
  -d '{"name":"Alice"}'
{"detail":[{"loc":["body","email"],"msg":"is missing","type":"value_error"}]}
```

## Next Steps

- [Key Concepts](/docs/getting-started/key-concepts) - Understand the core ideas
- [Routing](/docs/essential/routing) - Learn about path parameters and HTTP methods
- [Validation](/docs/essential/validation) - Deep dive into dry-schema
