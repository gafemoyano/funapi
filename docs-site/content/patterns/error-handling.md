---
title: Error Handling
---

# Error Handling

FunApi provides FastAPI-style error responses.

## HTTPException

Raise `HTTPException` to return an error response:

```ruby
api.get '/users/:id' do |input, req, task|
  user = find_user(input[:path]['id'])
  
  unless user
    raise FunApi::HTTPException.new(
      status_code: 404,
      detail: "User not found"
    )
  end
  
  [{ user: user }, 200]
end
```

Response:

```json
{
  "detail": "User not found"
}
```

## Common Status Codes

```ruby
# 400 Bad Request
raise FunApi::HTTPException.new(status_code: 400, detail: "Invalid input")

# 401 Unauthorized
raise FunApi::HTTPException.new(status_code: 401, detail: "Authentication required")

# 403 Forbidden
raise FunApi::HTTPException.new(status_code: 403, detail: "Permission denied")

# 404 Not Found
raise FunApi::HTTPException.new(status_code: 404, detail: "Resource not found")

# 409 Conflict
raise FunApi::HTTPException.new(status_code: 409, detail: "Already exists")

# 422 Unprocessable Entity
raise FunApi::HTTPException.new(status_code: 422, detail: "Validation failed")

# 500 Internal Server Error
raise FunApi::HTTPException.new(status_code: 500, detail: "Something went wrong")
```

## Custom Headers

Add headers to error responses:

```ruby
raise FunApi::HTTPException.new(
  status_code: 401,
  detail: "Token expired",
  headers: { 'WWW-Authenticate' => 'Bearer' }
)
```

## ValidationError

`ValidationError` is raised automatically by schema validation, but you can raise it manually:

```ruby
raise FunApi::ValidationError.new(
  errors: [
    { path: [:email], text: "is invalid" }
  ]
)
```

Response (422):

```json
{
  "detail": [
    {
      "loc": ["email"],
      "msg": "is invalid",
      "type": "value_error"
    }
  ]
}
```

## Handling Exceptions in Handlers

Use standard Ruby exception handling:

```ruby
api.get '/external' do |input, req, task|
  begin
    data = ExternalAPI.fetch
    [{ data: data }, 200]
  rescue ExternalAPI::Timeout
    raise FunApi::HTTPException.new(
      status_code: 504,
      detail: "External service timeout"
    )
  rescue ExternalAPI::Error => e
    raise FunApi::HTTPException.new(
      status_code: 502,
      detail: "External service error: #{e.message}"
    )
  end
end
```

## Custom Error Classes

Create domain-specific errors:

```ruby
class NotFoundError < FunApi::HTTPException
  def initialize(resource, id)
    super(
      status_code: 404,
      detail: "#{resource} with id #{id} not found"
    )
  end
end

class UnauthorizedError < FunApi::HTTPException
  def initialize(message = "Authentication required")
    super(
      status_code: 401,
      detail: message,
      headers: { 'WWW-Authenticate' => 'Bearer' }
    )
  end
end

# Usage
api.get '/users/:id' do |input, req, task|
  user = find_user(input[:path]['id'])
  raise NotFoundError.new('User', input[:path]['id']) unless user
  [{ user: user }, 200]
end
```

## Error Middleware

Handle errors globally with middleware:

```ruby
class ErrorHandlerMiddleware
  def initialize(app)
    @app = app
  end

  def call(env)
    @app.call(env)
  rescue StandardError => e
    # Log the error
    puts "Error: #{e.message}"
    puts e.backtrace.first(5).join("\n")
    
    # Return generic error in production
    [
      500,
      { 'content-type' => 'application/json' },
      [JSON.dump(detail: 'Internal server error')]
    ]
  end
end

app = FunApi::App.new do |api|
  api.use ErrorHandlerMiddleware
  # routes...
end
```
