---
title: Validation
---

# Validation

FunApi uses [dry-schema](https://dry-rb.org/gems/dry-schema/) for request and response validation.

## Defining Schemas

Create schemas with `FunApi::Schema.define`:

```ruby
UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
  optional(:role).filled(:string)
end
```

> **Technical Detail**: `FunApi::Schema.define` is a thin wrapper around `Dry::Schema.Params`. You have access to the full dry-schema DSL.

## Applying Schemas

### Body Validation

```ruby
api.post '/users', body: UserSchema do |input, req, task|
  user = input[:body]  # Validated and coerced
  [{ created: user }, 201]
end
```

### Query Validation

```ruby
SearchSchema = FunApi::Schema.define do
  required(:q).filled(:string)
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

api.get '/search', query: SearchSchema do |input, req, task|
  [{ results: search(input[:query]) }, 200]
end
```

### Response Validation

Filter and validate response data:

```ruby
UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
end

api.get '/users/:id', response_schema: UserOutputSchema do |input, req, task|
  user = find_user(input[:path]['id'])
  # password and other fields are filtered out
  [user, 200]
end
```

## Schema DSL

### Required vs Optional

```ruby
FunApi::Schema.define do
  required(:name).filled(:string)   # Must be present and non-empty
  optional(:nickname).filled(:string)  # Can be absent, but if present must be valid
end
```

### Types

```ruby
FunApi::Schema.define do
  required(:name).filled(:string)
  required(:age).filled(:integer)
  required(:price).filled(:float)
  required(:active).filled(:bool)
  required(:tags).filled(:array)
  required(:metadata).filled(:hash)
end
```

### Nested Objects

```ruby
AddressSchema = FunApi::Schema.define do
  required(:street).filled(:string)
  required(:city).filled(:string)
  required(:zip).filled(:string)
end

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:address).hash(AddressSchema)
end
```

### Arrays of Objects

```ruby
ItemSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:quantity).filled(:integer)
end

OrderSchema = FunApi::Schema.define do
  required(:items).array(:hash) do
    required(:name).filled(:string)
    required(:quantity).filled(:integer)
  end
end
```

Or validate an array of items:

```ruby
api.post '/users/batch', body: [UserSchema] do |input, req, task|
  users = input[:body]  # Array of validated users
  [{ created: users.length }, 201]
end
```

## Validation Errors

When validation fails, FunApi returns a FastAPI-style error response:

```json
{
  "detail": [
    {
      "loc": ["body", "email"],
      "msg": "is missing",
      "type": "value_error"
    },
    {
      "loc": ["body", "age"],
      "msg": "must be an integer",
      "type": "value_error"
    }
  ]
}
```

Status code: `422 Unprocessable Entity`

## Custom Validation

For complex validation, use dry-schema's full DSL:

```ruby
UserSchema = FunApi::Schema.define do
  required(:email).filled(:string, format?: /@/)
  required(:age).filled(:integer, gt?: 0, lt?: 150)
  required(:password).filled(:string, min_size?: 8)
end
```

See the [dry-schema documentation](https://dry-rb.org/gems/dry-schema/) for the complete DSL reference.
