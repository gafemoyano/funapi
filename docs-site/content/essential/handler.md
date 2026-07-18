---
title: Handler
---

# Handler

The handler is the function that processes a request and returns a response.

## Handler Signature

Every handler receives two positional arguments:

```ruby
api.get '/path' do |input, req|
  [response_data, status_code]
end
```

| Argument | Type | Description |
|----------|------|-------------|
| `input` | Hash | Request data (path, query, body) |
| `req` | Rack::Request | Full Rack request object |

For concurrency, use the module functions `FunApi.async { ... }` and
`FunApi.sleep(n)` — no task parameter is required.

## The Input Hash

The `input` hash normalizes all request data:

```ruby
api.post '/users/:id' do |input, req|
  input[:path]     # Path parameters: { id: '123' }
  input[:query]    # Query params: { search: 'ruby' }
  input[:body]     # Parsed JSON body: { name: 'Alice' }
  input[:headers]  # Request headers: { 'content-type' => 'application/json' }
end
```

### Accessing Path Parameters

```ruby
api.get '/posts/:post_id/comments/:id' do |input, req|
  post_id = input[:path][:post_id]
  comment_id = input[:path][:id]
  # ...
end
```

### Accessing Query Parameters

```ruby
# GET /search?q=ruby&page=2
api.get '/search' do |input, req|
  query = input[:query][:q]
  page = input[:query][:page]
  # ...
end
```

### Accessing Request Body

```ruby
api.post '/users' do |input, req|
  name = input[:body][:name]
  email = input[:body][:email]
  # ...
end
```

## The Rack Request

The `req` object is a standard `Rack::Request`:

```ruby
api.get '/info' do |input, req|
  {
    method: req.request_method,
    path: req.path_info,
    host: req.host,
    content_type: req.content_type,
    user_agent: req.user_agent,
    ip: req.ip
  }
end
```

### Accessing Headers

```ruby
api.get '/auth' do |input, req|
  auth_header = req.get_header('HTTP_AUTHORIZATION')
  # or
  auth_header = req.env['HTTP_AUTHORIZATION']
end
```

## Concurrency

Use `FunApi.async { ... }` to run operations concurrently (and `FunApi.sleep(n)`
for non-blocking sleeps):

```ruby
api.get '/dashboard' do |input, req|
  # Run operations concurrently
  user = FunApi.async { UserService.find(id) }
  posts = FunApi.async { PostService.recent }
  
  [{
    user: user.wait,
    posts: posts.wait
  }, 200]
end
```

See [Async Operations](/docs/patterns/async-operations) for more.

## Return Value

Handlers must return `[data, status_code]`:

```ruby
# JSON response
[{ message: 'Hello' }, 200]

# Array response
[users, 200]

# Empty response
[{}, 204]

# Error response
[{ error: 'Not found' }, 404]
```

### Returning HTML

Return a `TemplateResponse` for HTML:

```ruby
api.get '/' do |input, req|
  templates.response('home.html.erb', title: 'Home')
end
```

See [Templates](/docs/patterns/templates) for more.

## Keyword Arguments (Dependencies)

When using dependency injection, dependencies come as keyword arguments:

```ruby
api.get '/users', depends: [:db, :logger] do |input, req, db:, logger:|
  logger.info("Fetching users")
  users = db.query("SELECT * FROM users")
  [{ users: users }, 200]
end
```

See [Dependencies](/docs/patterns/dependencies) for more.
