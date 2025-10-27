require_relative "lib/fun_api"
require_relative "lib/fun_api/server/falcon"

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
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
  title: "User Management API",
  version: "1.0.0",
  description: "A simple user management API demonstrating OpenAPI generation"
) do |api|
  api.get "/users", query: QuerySchema, response_schema: [UserOutputSchema] do |_input, _req, _task|
    users = [
      {id: 1, name: "John Doe", email: "john@example.com", age: 30},
      {id: 2, name: "Jane Smith", email: "jane@example.com"}
    ]
    [users, 200]
  end

  api.get "/users/:id", response_schema: UserOutputSchema do |input, _req, _task|
    user_id = input[:path]["id"]
    user = {id: user_id.to_i, name: "John Doe", email: "john@example.com", age: 30}
    [user, 200]
  end

  api.post "/users", body: UserCreateSchema, response_schema: UserOutputSchema do |input, _req, _task|
    user = input[:body].merge(id: rand(1000))
    [user, 201]
  end

  api.put "/users/:id", body: UserCreateSchema, response_schema: UserOutputSchema do |input, _req, _task|
    user_id = input[:path]["id"]
    user = input[:body].merge(id: user_id.to_i)
    [user, 200]
  end

  api.delete "/users/:id" do |_input, _req, _task|
    [{message: "User deleted"}, 200]
  end
end

puts "Starting server on http://localhost:9292"
puts "OpenAPI spec: http://localhost:9292/openapi.json"
puts "Swagger UI: http://localhost:9292/docs"
puts

FunApi::Server::Falcon.start(app, port: 9292)
