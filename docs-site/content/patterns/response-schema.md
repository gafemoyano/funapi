---
title: Response Schema
---

# Response Schema

Filter and validate response data before sending to clients.

## Why Response Schemas?

Response schemas help you:

1. **Filter sensitive data** - Remove passwords, tokens, internal IDs
2. **Validate output** - Catch bugs before they reach clients
3. **Document responses** - Auto-generate OpenAPI response schemas

## Basic Usage

Define a schema for the response:

```ruby
UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
end

api.get '/users/:id', response_schema: UserOutputSchema do |input, req, task|
  user = find_user(input[:path]['id'])
  # Even if user has :password, :api_key, etc., they're filtered out
  [user, 200]
end
```

## Filtering Sensitive Data

```ruby
# Internal user record
user = {
  id: 1,
  name: "Alice",
  email: "alice@example.com",
  password_hash: "abc123...",
  api_key: "secret...",
  internal_notes: "VIP customer"
}

# With response_schema: UserOutputSchema
# Client receives only:
{
  "id": 1,
  "name": "Alice",
  "email": "alice@example.com"
}
```

## Array Responses

For array responses, wrap the schema in brackets:

```ruby
api.get '/users', response_schema: [UserOutputSchema] do |input, req, task|
  users = fetch_all_users
  [users, 200]
end
```

## Different Input/Output Schemas

Common pattern: accept more fields than you return.

```ruby
UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:created_at).filled(:string)
end

api.post '/users', 
  body: UserCreateSchema, 
  response_schema: UserOutputSchema do |input, req, task|
  
  user = create_user(input[:body])
  # password is filtered out of response
  [user, 201]
end
```

## Nested Objects

```ruby
AddressSchema = FunApi::Schema.define do
  required(:city).filled(:string)
  required(:country).filled(:string)
end

UserWithAddressSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:address).hash do
    required(:city).filled(:string)
    required(:country).filled(:string)
  end
end

api.get '/users/:id', response_schema: UserWithAddressSchema do |input, req, task|
  user = find_user_with_address(input[:path]['id'])
  [user, 200]
end
```

## Validation Errors

If your response doesn't match the schema, FunApi returns a 500 error:

```ruby
api.get '/broken', response_schema: UserOutputSchema do |input, req, task|
  # Missing required :email field
  [{ id: 1, name: "Alice" }, 200]
end

# Response: 500
# {"detail":"Response validation failed: {:email=>[\"is missing\"]}"}
```

This helps catch bugs in development before they reach production.

## OpenAPI Integration

Response schemas appear in your OpenAPI documentation:

```json
{
  "paths": {
    "/users/{id}": {
      "get": {
        "responses": {
          "200": {
            "content": {
              "application/json": {
                "schema": {
                  "$ref": "#/components/schemas/UserOutputSchema"
                }
              }
            }
          }
        }
      }
    }
  }
}
```
