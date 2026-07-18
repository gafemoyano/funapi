---
title: Incremental Adoption
---

# Incremental Adoption

You don't have to rewrite an application to start using FunApi. Because
`FunApi::App#call(env)` is a plain Rack endpoint, a FunApi app can live *inside*
an existing Rack or Rails application — and existing Rack apps can live *inside*
FunApi. Adopt one endpoint at a time.

There are two directions:

1. **FunApi inside another app** — mount a FunApi app under a path in a
   `Rack::URLMap` or a Rails routes file.
2. **Another app inside FunApi** — `mount` an arbitrary Rack app under a path in
   FunApi.

## FunApi inside a Rack::URLMap

A FunApi app is Rack-compatible, so `Rack::URLMap` can route a path prefix to it
while everything else keeps flowing to your legacy app:

```ruby
# config.ru
require 'funapi'
require_relative 'legacy_app'

api = FunApi::App.new(title: 'New API') do |app|
  app.get '/status' do |input, req, task|
    [{ ok: true }, 200]
  end
end

run Rack::URLMap.new(
  '/'    => LegacyApp.new,   # existing app keeps serving everything
  '/api' => api             # new endpoints served by FunApi
)
```

`Rack::URLMap` strips the prefix before calling FunApi: a request to
`/api/status` arrives at the FunApi app as `PATH_INFO=/status` with
`SCRIPT_NAME=/api`, so your routes are written prefix-free. The FunApi app's own
`/api/docs` and `/api/openapi.json` are served automatically.

This exact composition is covered by an automated test in
`test/test_mount.rb` (`test_funapi_app_mounted_in_rack_urlmap`).

## FunApi inside Rails

Rails routes can mount any Rack app, and a FunApi app is one. Add it to your
routes file:

```ruby
# config/routes.rb
require 'funapi'

MyApi = FunApi::App.new(title: 'Embedded API') do |app|
  app.get '/health' do |input, req, task|
    [{ status: 'up' }, 200]
  end
end

Rails.application.routes.draw do
  # ...existing Rails routes...
  mount MyApi => '/api'
end
```

Requests to `/api/health` are handled entirely by FunApi — Rails strips the
`/api` prefix via `SCRIPT_NAME`/`PATH_INFO` the same way `Rack::URLMap` does. The
FunApi app runs its own validation, dependency injection, and OpenAPI generation
independently of Rails. This lets you build new endpoints the FunApi way while
the rest of the monolith is unchanged.

> Run FunApi's async endpoints under an async-capable server (Falcon) to get
> non-blocking I/O. Under a threaded server the routes still work, just without
> the fiber-level concurrency.

## Mounting Rack apps inside FunApi

The reverse direction uses `mount`. Point a path prefix at any Rack app — a
Sinatra app, a static file server, a legacy Rack handler, or a lambda:

```ruby
require 'rack/static'

app = FunApi::App.new do |api|
  api.get '/users' do |input, req, task|
    [{ users: [] }, 200]
  end

  # Anything under /admin is handled by the mounted Rack app
  api.mount '/admin', LegacyAdmin.new

  # Serve static assets straight from Rack
  api.mount '/assets', Rack::Files.new('public/assets')
end
```

How `mount` behaves:

- **Longest-prefix wins.** Mounting both `/api` and `/api/admin` routes
  `/api/admin/...` to the more specific app.
- **Rack path conventions.** The matched prefix is moved from `PATH_INFO` onto
  `SCRIPT_NAME`, so mounted apps see prefix-free paths exactly as they expect.
- **No FunApi processing.** Mounted apps bypass FunApi validation, dependency
  injection, and serialization — they own their request and response entirely.
- **Excluded from OpenAPI.** Mounted paths are not FunApi routes, so they never
  appear in `/openapi.json` or `/docs`.

## A full example

See `examples/multi_router_demo.rb` for a runnable app that composes two routers
with prefixes, tags, and a shared dependency, and mounts a plain Rack app under
`/admin` — all visible together in Swagger UI at `/docs`.
