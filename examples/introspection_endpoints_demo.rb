# frozen_string_literal: true

require_relative "../lib/fun_api"
require_relative "../lib/fun_api/server/falcon"

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

app = FunApi::App.new(
  title: "Introspection Endpoints Demo",
  version: "1.0.0",
  description: "Demo app showing introspection HTTP endpoints"
) do |api|
  api.register(:db) { Object.new }
  api.register(:logger) { Object.new }
  api.register(:cache) { Object.new }

  api.add_cors
  api.add_request_logger

  api.get "/" do |_input, _req, _task|
    [{message: "Welcome! Try /introspect for API discovery"}, 200]
  end

  api.get "/users", query: QuerySchema, response_schema: [UserOutputSchema],
    depends: [:db] do |_input, _req, _task, db:|
    [
      [
        {id: 1, name: "John Doe", email: "john@example.com", age: 30},
        {id: 2, name: "Jane Smith", email: "jane@example.com"}
      ],
      200
    ]
  end

  api.get "/users/:id", response_schema: UserOutputSchema, depends: [:db] do |input, _req, _task, db:|
    [{id: input[:path]["id"].to_i, name: "John Doe", email: "john@example.com", age: 30}, 200]
  end

  api.post "/users", body: UserCreateSchema, response_schema: UserOutputSchema,
    depends: %i[db logger] do |input, _req, _task, db:, logger:|
    [input[:body].merge(id: rand(1000)), 201]
  end

  api.delete "/users/:id", depends: %i[db logger] do |input, _req, _task, db:, logger:|
    [{deleted: true, id: input[:path]["id"].to_i}, 200]
  end
end

puts "=" * 80
puts "FunApi Introspection Endpoints Demo"
puts "=" * 80
puts
puts "Available endpoints:"
puts
puts "  Application Routes:"
puts "    GET  /                - Welcome message"
puts "    GET  /users           - List users"
puts "    GET  /users/:id       - Get user by ID"
puts "    POST /users           - Create user"
puts "    DELETE /users/:id     - Delete user"
puts
puts "  Introspection Endpoints:"
puts "    GET  /introspect              - Overview (stats, health, endpoints)"
puts "    GET  /introspect/routes       - All routes with metadata"
puts "    GET  /introspect/routes/:verb/:path - Single route details"
puts "    GET  /introspect/dependencies - All dependencies"
puts "    GET  /introspect/dependencies/:name - Single dependency"
puts "    GET  /introspect/schemas      - All schemas"
puts "    GET  /introspect/middleware   - Middleware stack"
puts "    GET  /introspect/health       - Health check with issues"
puts "    GET  /introspect/relationships - Dependency graph"
puts
puts "  Query parameters:"
puts "    /introspect/routes?verb=POST"
puts "    /introspect/routes?has_body=true"
puts "    /introspect/routes?uses_dep=db"
puts "    /introspect/routes?search=users"
puts "    /introspect/dependencies?unused=true"
puts "    /introspect/schemas?has_field=email"
puts
puts "  Documentation:"
puts "    GET  /docs            - Swagger UI"
puts "    GET  /openapi.json    - OpenAPI spec"
puts
puts "=" * 80
puts "Starting server on http://localhost:3000"
puts "=" * 80

FunApi::Server::Falcon.start(app, port: 3000)
