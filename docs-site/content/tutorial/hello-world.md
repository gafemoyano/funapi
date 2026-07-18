---
title: "Tutorial 1: Hello World"
---

# Tutorial 1: Hello World

This tutorial builds a small API step by step. Each page is runnable on its
own and picks up where the last left off. By the end you'll have request
validation, dependency injection, and streaming — the core of FunApi.

Start here: a running server with interactive docs in under a minute.

## Install and scaffold

FunApi ships a CLI. Scaffold a new application with `funapi new`:

```bash
gem install funapi
funapi new blog
cd blog
bundle install
```

This creates a small project:

```
blog/
├── app.rb            # models + routes (the heart of the app)
├── config.ru         # Rack entry point
├── Gemfile
├── AGENTS.md         # instructions for AI coding agents
├── README.md
└── test/
    ├── test_helper.rb
    └── app_test.rb   # example test using FunApi::TestClient
```

## The app

Open `app.rb`. The essential shape is a `FunApi::App` with routes:

```ruby
require "funapi"

Application = FunApi::App.new(
  title: "Blog",
  version: "0.1.0"
) do |api|
  api.get "/" do |_input, _req|
    [{message: "Hello, World!"}, 200]
  end

  api.get "/hello/:name" do |input, _req|
    [{message: "Hello, #{input[:path][:name]}!"}, 200]
  end
end
```

Two things to notice:

- **Handlers receive `|input, req|`** and return `[payload, status]`. The
  payload is serialized to JSON automatically.
- **The app is exposed as the `Application` constant** so `config.ru`,
  `funapi dev`, and your tests can all reach it.

## Run it with reloading

```bash
funapi dev
```

```
FunApi dev server: http://localhost:3000
Interactive docs:  http://localhost:3000/docs
Code reloading:    on (restarts on file change)
Press Ctrl+C to stop
```

`funapi dev` boots the app under Falcon and watches your files — edit `app.rb`
and the server restarts automatically.

## Try it

```bash
$ curl http://localhost:3000/
{"message":"Hello, World!"}

$ curl http://localhost:3000/hello/Ruby
{"message":"Hello, Ruby!"}
```

## The docs are automatic

Open [http://localhost:3000/docs](http://localhost:3000/docs) for interactive
Swagger UI, generated from your routes. The raw spec is at `/openapi.json`.

## Inspect your routes

```bash
$ funapi routes
VERB  PATH          TAGS  SCHEMAS
GET   /                   -
GET   /hello/:name        -
```

Add `--json` for machine-readable output.

## Next

[Tutorial 2: Request Validation with Models →](/docs/tutorial/validation)
