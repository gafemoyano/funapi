# frozen_string_literal: true

require_relative "../lib/funapi"
require_relative "../lib/funapi/server/falcon"

# FunApi::Model — one declaration gives validation, serialization, and JSON Schema.
# A model class *is* the schema: an inspectable value you pass to routes.

class Address < FunApi::Model
  field :street, :string
  field :city, :string
  field :zip, :string, optional: true
end

class PostInput < FunApi::Model
  field :title, :string, description: "Post title"
  field :body, :string
end

# Request model — what the client is allowed to send.
class UserCreate < FunApi::Model
  field :name, :string, description: "Display name"
  field :email, :string, format: "email"
  field :password, :string, min: 8
  field :role, :string, enum: %w[admin member], default: "member"
  field :age, :integer, optional: true, nullable: true, min: 0, max: 120
  field :address, Address, optional: true
  field :posts, [PostInput], default: []
end

# Response model — what the client is allowed to see (no password field).
class UserOut < FunApi::Model
  field :id, :integer
  field :name, :string
  field :email, :string
  field :role, :string
  field :address, Address, optional: true
end

# A stand-in for an ORM record (Sequel::Model, ActiveRecord, …). `dump` reads
# any object that responds to the field names, so no manual mapping is needed.
UserRecord = Struct.new(:id, :name, :email, :password, :role, :address, :posts, :created_at)

app = FunApi::App.new(
  title: "Model Demo API",
  version: "1.0.0",
  description: "FunApi::Model — validation + serialization + OpenAPI from one declaration"
) do |api|
  api.post "/users", body: UserCreate, response_schema: UserOut do |input, _req, _task|
    data = input[:body]

    record = UserRecord.new(
      id: rand(1000),
      name: data[:name],
      email: data[:email],
      password: "hashed:#{data[:password]}",
      role: data[:role],
      address: data[:address],
      posts: data[:posts],
      created_at: Time.now
    )

    # `password` and `created_at` are filtered out by UserOut.dump.
    [record, 201]
  end

  api.get "/users/:id", response_schema: UserOut do |input, _req, _task|
    record = UserRecord.new(
      id: input[:path][:id].to_i,
      name: "Ada Lovelace",
      email: "ada@example.com",
      password: "hashed:secret",
      role: "admin",
      address: {street: "1 Analytical Ave", city: "London", zip: "SW1"},
      posts: [],
      created_at: Time.now
    )

    [record, 200]
  end
end

if $PROGRAM_NAME == __FILE__
  puts "UserCreate.json_schema:"
  puts JSON.pretty_generate(UserCreate.json_schema)
  puts
  puts "Starting server on http://localhost:9292"
  puts "Swagger UI: http://localhost:9292/docs"
  puts

  FunApi::Server::Falcon.start(app, port: 9292)
end
