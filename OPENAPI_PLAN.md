## OpenAPI/Swagger Documentation Generation - Implementation Plan

### Goal

Automatically generate OpenAPI 3.0 specification and serve Swagger UI for FunApi applications, similar
to FastAPI's /docs endpoint.

### Key Design Decisions

1. Architecture Overview

• Store route metadata during app initialization
• Generate OpenAPI spec on-demand (or cache at startup)
• Serve Swagger UI at /docs and /redoc endpoints
• Provide JSON spec at /openapi.json

2. Information to Extract from Routes

• Path - Route template (e.g., /users/:id)
• Method - HTTP verb (GET, POST, etc.)
• Parameters:
 • Path params (from template: /users/:id → id parameter)
 • Query params (from query: schema)
 • Body params (from body: schema)
• Responses:
 • Response schema (from response_schema:)
 • Status code (from handler return value)
• Tags - Group endpoints logically (future)
• Description/Summary - Optional metadata (future)

3. Dry-Schema Introspection Strategy From my research:

schema = Dry::Schema.Params { required(:name).filled(:string); required(:age).filled(:integer) }
# Available introspection:
# - schema.key_map → list of keys
# - schema.rules → validation rules (complex nested structure)
# - schema.types → type information per key

Need to build a schema-to-JSON-schema converter that traverses the dry-schema structure.

4. Route Metadata Storage

# Update Router to store rich route information
Route = Struct.new(:verb, :pattern, :keys, :handler, :metadata)

# metadata contains:
{
  path_template: '/users/:id',
  query_schema: QuerySchema,
  body_schema: UserInput,
  response_schema: UserOutput,
  summary: "Create user",  # future
  description: "...",      # future
  tags: ["users"]          # future
}

5. Implementation Components

#### Component 1: Route Metadata Collection

# lib/fun_api/openapi/route_metadata.rb
class RouteMetadata
  attr_reader :verb, :path, :query_schema, :body_schema, :response_schema

  def initialize(verb:, path:, **schemas)
    @verb = verb
    @path = path
    @query_schema = schemas[:query]
    @body_schema = schemas[:body]
    @response_schema = schemas[:response_schema]
  end

  def to_openapi_operation
    # Generate OpenAPI Operation Object
  end
end

#### Component 2: Schema to JSON Schema Converter

# lib/fun_api/openapi/schema_converter.rb
class SchemaConverter
  def self.to_json_schema(dry_schema)
    # Convert dry-schema to OpenAPI Schema Object
    # Traverse schema.key_map and schema.types
    # Build JSON Schema representation
  end

  def self.extract_field_info(key, types)
    # Determine: type, required, format, etc.
  end
end

#### Component 3: OpenAPI Spec Generator

# lib/fun_api/openapi/spec_generator.rb
class SpecGenerator
  def initialize(routes, info: {})
    @routes = routes
    @info = info
  end

  def generate
    {
      openapi: "3.0.3",
      info: build_info,
      paths: build_paths,
      components: build_components
    }
  end
end

#### Component 4: Documentation Endpoints

# Auto-register these routes:
# GET /docs → Swagger UI HTML
# GET /redoc → ReDoc HTML
# GET /openapi.json → OpenAPI spec

### Implementation Sequence

1. Phase 1: Route Metadata Storage ✓ Plan
 • Modify Router.add to store full metadata
 • Update App.add_route to pass all schema info
 • Create RouteMetadata class
2. Phase 2: Schema Introspection ✓ Plan
 • Create SchemaConverter class
 • Implement dry-schema → JSON Schema conversion
 • Handle: string, integer, float, boolean, arrays, nested objects
 • Handle: required vs optional fields
3. Phase 3: OpenAPI Spec Generation ✓ Plan
 • Create SpecGenerator class
 • Generate paths object from routes
 • Generate components/schemas from all schemas
 • Generate parameter objects for path/query params
4. Phase 4: Swagger UI Integration ✓ Plan
 • Add /openapi.json endpoint
 • Add /docs endpoint (Swagger UI)
 • Use CDN-hosted Swagger UI HTML
5. Phase 5: Testing & Refinement ✓ Plan
 • Test with complex schemas
 • Test with nested objects
 • Test with arrays
 • Ensure Swagger UI renders correctly


### Example Output

For this route:

api.post '/users', body: UserInput, response_schema: UserOutput do |input, req, task|
  # ...
end

Generate:

{
  "paths": {
    "/users": {
      "post": {
        "requestBody": {
          "content": {
            "application/json": {
              "schema": { "$ref": "#/components/schemas/UserInput" }
            }
          }
        },
        "responses": {
          "200": {
            "description": "Successful response",
            "content": {
              "application/json": {
                "schema": { "$ref": "#/components/schemas/UserOutput" }
              }
            }
          }
        }
      }
    }
  },
  "components": {
    "schemas": {
      "UserInput": {
        "type": "object",
        "properties": {
          "username": { "type": "string" },
          "email": { "type": "string" },
          "password": { "type": "string" }
        },
        "required": ["username", "email", "password"]
      },
      "UserOutput": {
        "type": "object",
        "properties": {
          "id": { "type": "integer" },
          "username": { "type": "string" },
          "email": { "type": "string" }
        },
        "required": ["id", "username", "email"]
      }
    }
  }
}

### Questions for You

1. Schema Names: Should we require users to name their schemas explicitly, or auto-generate names from
constants?
# Option A: Use constant name
UserInput = FunApi::Schema.define { ... }  # Name: "UserInput"

# Option B: Explicit naming
api.post '/users', body: { schema: UserInput, name: "UserCreateRequest" }

2. Default Info: What should the default info object contain? (title, version, description)
3. Docs Path: Should /docs be configurable or fixed?
4. Schema Deduplication: If the same schema is used multiple times, should we dedupe in components?

Ready to implement when you give the go-ahead! Should I proceed with the implementation in the next
session (since we're in READ-ONLY mode now)?
