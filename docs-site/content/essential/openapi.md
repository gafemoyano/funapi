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
api.get '/users' do |input, req, task|
  # Documented as GET /users
end

api.post '/users' do |input, req, task|
  # Documented as POST /users
end
```

### Path Parameters

Path parameters are extracted and documented:

```ruby
api.get '/users/:id' do |input, req, task|
  # Documented with {id} parameter
end
```

### Schemas

Schemas become OpenAPI components:

```ruby
UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

api.post '/users', body: UserSchema do |input, req, task|
  # Request body documented with UserSchema
end
```

### Response Schemas

Response schemas document the output:

```ruby
api.get '/users/:id', response_schema: UserOutputSchema do |input, req, task|
  # Response documented with UserOutputSchema
end
```

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

Schema names in OpenAPI come from your Ruby constant names:

```ruby
UserCreateSchema = FunApi::Schema.define { ... }
# Becomes "UserCreateSchema" in OpenAPI

UserOutputSchema = FunApi::Schema.define { ... }
# Becomes "UserOutputSchema" in OpenAPI
```

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
