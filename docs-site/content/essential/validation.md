---
title: Validation
---

# Validation

FunApi validates requests and responses with **models**. A `FunApi::Model`
subclass *is* a schema: one declaration gives you input validation and coercion,
output serialization, and an OpenAPI schema. Validated data stays a plain
symbolized `Hash` — FunApi never wraps your data in framework objects.

## Defining a Model

```ruby
class User < FunApi::Model
  field :id,      :integer
  field :name,    :string,  description: "Display name"
  field :email,   :string,  format: "email"
  field :role,    :string,  enum: %w[admin member], default: "member"
  field :age,     :integer, optional: true, nullable: true, min: 0, max: 120
  field :address, Address,  optional: true          # nested model
  field :tags,    [:string], default: []            # array of primitives
  field :posts,   [Post],    default: []            # array of models
end
```

### Field types

- Primitives: `:string`, `:integer`, `:float`, `:decimal`, `:bool`, `:date`, `:time`, `:hash`
- A `FunApi::Model` subclass for a nested object
- A one-element array of either — `[:string]`, `[Post]`

### Field options

| Option | Meaning |
|---|---|
| `optional: true` | field may be absent |
| `default:` | value used when the key is missing (also makes the field optional) |
| `nullable: true` | explicit `nil` is allowed |
| `description:` | documentation string, surfaced in OpenAPI |
| `format:` | OpenAPI `format` hint (e.g. `"email"`, `"uuid"`) |
| `enum:` | allowed values |
| `min:` / `max:` | value bounds for numbers, length bounds for strings/arrays |
| `pattern:` | a `Regexp` (or string) the value must match |

A field is **required** unless you pass `optional: true` or a `default:`.
Unknown options and unknown types raise immediately at class-definition time.

## Applying a Model to a Route

The `body:`, `query:`, `path:`, and `response_schema:` keywords all accept a
model class (or `[Model]` for a collection):

```ruby
api.post "/users", body: UserCreate, response_schema: User do |input, req|
  input[:body]              # plain validated Hash, defaults applied
  [db_user, 201]            # object serialized + filtered by User
end
```

- **Request side** runs `Model.validate` — coerces types, applies defaults, and
  raises a `422` with FastAPI-style errors on failure.
- **Response side** runs `Model.dump` then validates the result. `dump` reads a
  `Hash` or **any object responding to the field names** (a `Struct`, a
  `Sequel::Model`, …), keeps only declared fields, and recurses into nested
  models and arrays. Response mismatches stay `500`.

### Path and query

```ruby
class UserId < FunApi::Model
  field :id, :integer
end

api.get "/users/:id", path: UserId do |input, req|
  input[:path][:id]         # => 42 (Integer, coerced from "42")
  [{id: input[:path][:id]}, 200]
end
```

Declared types flow into the generated OpenAPI parameters (e.g.
`type: integer`).

### Collections

```ruby
api.post "/users/batch", body: [UserCreate] do |input, req|
  input[:body]              # Array of validated Hashes
  [{created: input[:body].length}, 201]
end
```

## Inheritance

Subclasses compose their parent's fields:

```ruby
class Animal < FunApi::Model
  field :name, :string
  field :legs, :integer, default: 4
end

class Dog < Animal
  field :breed, :string       # Dog has name, legs, breed
end
```

## Introspection

A model is a value you can inspect:

```ruby
User.fields        # frozen metadata Hash, keyed by field name
User.validate(h)   # => coerced symbolized Hash
User.dump(record)  # => filtered plain Hash
User.json_schema   # => JSON Schema Hash
```

## Validation Errors

When request validation fails, FunApi returns a FastAPI-style `422`:

```json
{
  "detail": [
    {
      "loc": ["email"],
      "msg": "is missing",
      "type": "value_error"
    },
    {
      "loc": ["address", "street"],
      "msg": "is missing",
      "type": "value_error"
    }
  ]
}
```

## Legacy: `FunApi::Schema.define`

> `FunApi::Schema.define` predates `FunApi::Model` and remains supported
> everywhere a model is accepted. It is a thin wrapper around
> [`Dry::Schema.Params`](https://dry-rb.org/gems/dry-schema/) that validates but
> does **not** serialize objects. Prefer `FunApi::Model` for new code.

```ruby
UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  optional(:age).filled(:integer)
end

api.post "/users", body: UserSchema do |input, req|
  [{created: input[:body]}, 201]
end
```

Because `define` returns a raw dry-schema, you have the full dry-schema DSL
(nested `hash(...)`, `array(:hash)`, predicates like `min_size?`/`gteq?`, …).
See the [dry-schema documentation](https://dry-rb.org/gems/dry-schema/) for the
complete reference.
