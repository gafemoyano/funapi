---
title: Routing
---

# Routing

Routes map HTTP requests to handler functions based on the path and method.

## Defining Routes

FunApi provides methods for each HTTP verb:

```ruby
api.get '/users' do |input, req, task|
  [{ users: [] }, 200]
end

api.post '/users' do |input, req, task|
  [{ created: input[:body] }, 201]
end

api.put '/users/:id' do |input, req, task|
  [{ updated: true }, 200]
end

api.patch '/users/:id' do |input, req, task|
  [{ patched: true }, 200]
end

api.delete '/users/:id' do |input, req, task|
  [{}, 204]
end
```

## Path Parameters

Capture dynamic segments with `:param` syntax:

```ruby
api.get '/users/:id' do |input, req, task|
  user_id = input[:path]['id']  # Always a string
  [{ id: user_id }, 200]
end

api.get '/posts/:post_id/comments/:comment_id' do |input, req, task|
  post_id = input[:path]['post_id']
  comment_id = input[:path]['comment_id']
  [{ post_id: post_id, comment_id: comment_id }, 200]
end
```

> **Note**: Path parameters are always strings. Convert them manually if needed:
> ```ruby
> id = input[:path]['id'].to_i
> ```

## Query Parameters

Query parameters come from the URL query string:

```ruby
# GET /search?q=ruby&limit=10
api.get '/search' do |input, req, task|
  query = input[:query][:q]
  limit = input[:query][:limit]&.to_i || 20
  [{ query: query, limit: limit }, 200]
end
```

With validation:

```ruby
SearchSchema = FunApi::Schema.define do
  required(:q).filled(:string)
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

api.get '/search', query: SearchSchema do |input, req, task|
  # input[:query] is validated and coerced
  [{ results: search(input[:query]) }, 200]
end
```

## Request Body

POST, PUT, and PATCH routes typically receive a JSON body:

```ruby
UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

api.post '/users', body: UserSchema do |input, req, task|
  user = input[:body]  # Validated hash
  [{ created: user }, 201]
end
```

## Route Priority

Routes are matched in the order they're defined. More specific routes should come first:

```ruby
api.get '/users/me' do |input, req, task|
  # Matches /users/me
end

api.get '/users/:id' do |input, req, task|
  # Matches /users/123, /users/anything
end
```

## The Root Route

The root path `/` works like any other route:

```ruby
api.get '/' do |input, req, task|
  [{ status: 'ok' }, 200]
end
```
