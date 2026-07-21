---
title: Response Schema
---

# Response Schema

Filter and validate response data before sending it to clients.

## Why Response Schemas?

A `response_schema:` helps you:

1. **Filter sensitive data** — remove passwords, tokens, internal fields
2. **Validate output** — catch bugs before they reach clients
3. **Document responses** — auto-generate OpenAPI response schemas

## Basic Usage

Use a `FunApi::Model` as the response schema. Because a model can `dump` any
object that responds to its field names, you can hand it your ORM record
directly — only declared fields survive.

```ruby
class UserOut < FunApi::Model
  field :id,    :integer
  field :name,  :string
  field :email, :string
end

api.get "/users/:id", response_schema: UserOut do |input, req|
  user = find_user(input[:path][:id])   # a Sequel::Model, Struct, Hash, …
  # password, api_key, internal_notes, etc. are filtered out
  [user, 200]
end
```

The client receives only the declared fields:

```json
{ "id": 1, "name": "Alice", "email": "alice@example.com" }
```

## Serializing Objects

`Model.dump` reads a `Hash` **or any object responding to the field names**, so a
database record needs no manual mapping:

```ruby
Record = Struct.new(:id, :name, :email, :password_hash)

api.get "/me", response_schema: UserOut do |input, req|
  [Record.new(1, "Alice", "alice@example.com", "secret"), 200]
end
# password_hash is never in the response
```

## Array Responses

Wrap the model in brackets:

```ruby
api.get "/users", response_schema: [UserOut] do |input, req|
  [fetch_all_users, 200]
end
```

## Different Input / Output Models

A common pattern: accept more fields than you return.

```ruby
class UserCreate < FunApi::Model
  field :name,     :string
  field :email,    :string, format: "email"
  field :password, :string, min: 8
end

class UserOut < FunApi::Model
  field :id,    :integer
  field :name,  :string
  field :email, :string
end

api.post "/users", body: UserCreate, response_schema: UserOut do |input, req|
  user = create_user(input[:body])   # password is filtered out of the response
  [user, 201]
end
```

## Nested Objects

Nested models are dumped and filtered recursively:

```ruby
class Address < FunApi::Model
  field :city,    :string
  field :country, :string
end

class UserWithAddress < FunApi::Model
  field :id,      :integer
  field :name,    :string
  field :address, Address
end

api.get "/users/:id", response_schema: UserWithAddress do |input, req|
  [find_user_with_address(input[:path][:id]), 200]
end
```

## Validation Errors

If the dumped response doesn't satisfy the model, FunApi returns a `500`:

```ruby
api.get "/broken", response_schema: UserOut do |input, req|
  [{id: 1, name: "Alice"}, 200]   # missing required :email
end

# Response: 500
# {"detail":"Response validation failed: {email: [\"is missing\"]}"}
```

This catches serialization bugs in development before they reach production.

## OpenAPI Integration

Response models appear in your OpenAPI document, named after the model class
(demodulized), and referenced from the operation:

```json
{
  "responses": {
    "200": {
      "content": {
        "application/json": {
          "schema": { "$ref": "#/components/schemas/UserOut" }
        }
      }
    }
  }
}
```

> **Legacy:** `FunApi::Schema.define` schemas still work as `response_schema:`
> values (they validate and filter, but cannot serialize plain objects). Prefer
> `FunApi::Model` for new code.
