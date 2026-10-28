---
title: OpenAPI
---

# OpenAPI

FunApi automatically generates OpenAPI 3.0 documentation from your routes and schemas.

## Built-in Endpoints

Every FunApi application exposes:

| Endpoint | Description |
|----------|-------------|
| `/docs` | Interactive Swagger UI |
| `/openapi.json` | Raw OpenAPI specification |

## Configuring Your API

Set API metadata when creating the app:

```ruby
app = FunApi::App.new(
  title: "User Management API",
  version: "1.0.0",
  description: "A comprehensive user management system"
) do |api|
  # routes...
end
```

This appears in the OpenAPI spec and Swagger UI header.

## What Gets Documented

### Routes

All routes are automatically included:

```ruby
api.get '/users' do |input, req|
  # Documented as GET /users
end

api.post '/users' do |input, req|
  # Documented as POST /users
end
```

### Path Parameters

Path parameters are extracted and documented:

```ruby
api.get '/users/:id' do |input, req|
  # Documented with {id} parameter
end
```

### Schemas

Models become OpenAPI components:

```ruby
class UserCreate < FunApi::Model
  field :name,  :string
  field :email, :string, format: "email"
end

api.post '/users', body: UserCreate do |input, req|
  # Request body documented with the UserCreate schema
end
```

Field metadata flows straight into the schema — `description:`, `format:`,
`enum:`, `min:`/`max:`, `pattern:`, `nullable:`, and nested models all appear in
the generated component. `FunApi::Schema.define` schemas are documented too
(legacy path).

### Response Schemas

Response schemas document the output:

```ruby
api.get '/users/:id', response_schema: UserOutputSchema do |input, req|
  # Response documented with UserOutputSchema
end
```

### Tags

Tags group related operations in Swagger UI. Pass `tags:` on a route, or — more
commonly — on a [router](/essential/routing) so every endpoint it contributes is
grouped together:

```ruby
UsersRouter = FunApi::Router.new(prefix: '/users', tags: ['users']) do |r|
  r.get '/' do |input, req|
    # Documented under the "users" tag
    [[], 200]
  end
end

api.include_router(UsersRouter)
```

Router tags and inclusion-site tags accumulate, and a route can add its own:

```ruby
r.get '/audit', tags: ['admin'] do |input, req|
  # Tagged with both the router's tags and "admin"
end
```

Each operation's `tags` array is emitted in the spec, and Swagger UI renders one
collapsible section per tag.

## Swagger UI

The `/docs` endpoint serves an interactive Swagger UI where you can:

- Browse all endpoints
- See request/response schemas
- Try out API calls directly
- View example payloads

## OpenAPI JSON

Access the raw spec at `/openapi.json`:

```json
{
  "openapi": "3.0.0",
  "info": {
    "title": "User Management API",
    "version": "1.0.0",
    "description": "A comprehensive user management system"
  },
  "paths": {
    "/users": {
      "get": { ... },
      "post": { ... }
    }
  },
  "components": {
    "schemas": {
      "UserSchema": { ... }
    }
  }
}
```

## Schema Names

A model's component name is its class name (demodulized):

```ruby
class UserCreate < FunApi::Model; end
# Becomes "UserCreate" in OpenAPI

module Api
  class UserOut < FunApi::Model; end
end
# Becomes "UserOut" in OpenAPI
```

Legacy `FunApi::Schema.define` schemas are named after the Ruby constant they
are assigned to (e.g. `UserOutputSchema`).

## Use Cases

### Client Generation

Use the OpenAPI spec to generate clients:

```bash
# Generate TypeScript client
npx openapi-typescript http://localhost:3000/openapi.json -o api.ts

# Generate Python client
openapi-generator generate -i http://localhost:3000/openapi.json -g python
```

### API Testing

Import the spec into Postman, Insomnia, or other API tools.

### Documentation Hosting

Export the spec and host on platforms like:
- SwaggerHub
- Redoc
- Stoplight
