---
title: At Glance
---

# At Glance

## What is FunApi?

FunApi is a minimal, async-first Ruby web framework for building APIs. It draws heavy inspiration from Python's FastAPI, bringing that same developer experience to Ruby.

## Philosophy

<!-- 
TODO: Fill in your philosophy here. Some prompts:
- Why did you create this?
- What's wrong with existing Ruby frameworks for APIs?
- What makes async-first important?
- Who is this for?
-->

### Async-first

FunApi is built from the ground up for async operations. Every route handler receives an `Async::Task` that enables true concurrent execution within your routes.

### Minimal Magic

Unlike larger frameworks, FunApi keeps things explicit. No hidden callbacks, no implicit behavior. You see exactly what's happening.

### Validation at the Edges

Request validation happens before your handler runs. Response filtering happens after. Your business logic stays clean.

### Auto-Documentation

Your API documentation is generated from your code. Define a schema once, get validation AND documentation.

## Where FunApi Fits

<!-- 
TODO: Fill in comparison with other Ruby frameworks:
- vs Rails API-only
- vs Sinatra
- vs Roda
- vs Grape
-->

| Framework | Use Case | FunApi Difference |
|-----------|----------|-------------------|
| Rails API | Full-featured API | FunApi is lighter, async-first |
| Sinatra | Simple APIs | FunApi adds validation, OpenAPI |
| Roda | Routing-focused | FunApi is async, has schemas |
| Grape | API-focused | FunApi is simpler, async |

## Core Concepts Preview

```ruby
app = FunApi::App.new do |api|
  # Validation schemas
  UserSchema = FunApi::Schema.define do
    required(:name).filled(:string)
  end

  # Routes with validation
  api.post '/users', body: UserSchema do |input, req, task|
    # input[:body] is already validated
    [{ user: input[:body] }, 201]
  end

  # Async operations
  api.get '/dashboard/:id' do |input, req, task|
    # Concurrent fetches
    user = task.async { fetch_user(input[:path]['id']) }
    posts = task.async { fetch_posts(input[:path]['id']) }
    
    [{ user: user.wait, posts: posts.wait }, 200]
  end

  # Lifecycle hooks
  api.on_startup { DB.connect }
  api.on_shutdown { DB.disconnect }
end
```
