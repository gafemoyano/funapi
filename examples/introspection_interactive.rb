# frozen_string_literal: true

require_relative "../lib/fun_api"
require "irb"

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

FunApi::App.new(
  title: "Interactive Introspection Test",
  version: "1.0.0"
) do |api|
  api.register(:db) { {users: []} }
  api.register(:logger) { Logger.new($stdout) }
  api.register(:cache) { {} }

  api.add_cors(allow_origins: ["*"])
  api.add_request_logger

  api.get "/" do |_input, _req, _task|
    [{message: "Welcome"}, 200]
  end

  api.get "/users", query: QuerySchema, response_schema: [UserOutputSchema],
    depends: [:db] do |_input, _req, _task, db:|
    [db[:users], 200]
  end

  api.get "/users/:id", response_schema: UserOutputSchema, depends: [:db] do |input, _req, _task, db:|
    user = db[:users].find { |u| u[:id] == input[:path]["id"].to_i }
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    [user, 200]
  end

  api.post "/users", body: UserCreateSchema, response_schema: UserOutputSchema,
    depends: %i[db logger] do |input, _req, _task, db:, logger:|
    user = input[:body].merge(id: db[:users].length + 1)
    db[:users] << user
    logger.info("Created user: #{user[:name]}")
    [user, 201]
  end

  api.delete "/users/:id", depends: %i[db logger] do |input, _req, _task, db:, logger:|
    id = input[:path]["id"].to_i
    user = db[:users].find { |u| u[:id] == id }
    raise FunApi::HTTPException.new(status_code: 404, detail: "User not found") unless user

    db[:users].reject! { |u| u[:id] == id }
    logger.info("Deleted user: #{user[:name]}")
    [{message: "User deleted"}, 200]
  end
end

puts "\n" + ("=" * 80)
puts "FunApi Introspection - Interactive Console"
puts "=" * 80
puts "\nThe 'app' variable is available with introspection enabled."
puts "\nTry these commands:"
puts "  app.introspect.routes.count"
puts "  app.introspect.routes.map(&:path)"
puts "  app.introspect.routes.where_verb('GET')"
puts "  app.introspect.routes.where_uses_dependency(:db)"
puts "  app.introspect.dependencies.names"
puts "  app.introspect.dependencies.unused"
puts "  app.introspect.schemas.count"
puts "  app.introspect.schemas.where_has_field(:email)"
puts "  app.introspect.stats"
puts "  app.introspect.validate"
puts "  app.introspect.to_json"
puts "\nRoute details:"
puts "  route = app.introspect.route('POST', '/users')"
puts "  route.dependencies"
puts "  route.body_schema"
puts "  route.to_h"
puts "\nDependency details:"
puts "  dep = app.introspect.dependency(:db)"
puts "  dep.used_by_count"
puts "  dep.used_by.map(&:path)"
puts "\nSchema details:"
puts "  schema = app.introspect.schemas.first"
puts "  schema.fields"
puts "  schema.required_fields"
puts "  schema.field_types"
puts "\nPress Ctrl+D to exit"
puts "=" * 80
puts

IRB.start(__FILE__)
