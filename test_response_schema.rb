# frozen_string_literal: true

require 'fun_api'
require 'fun_api/server/falcon'

UserInput = FunApi::Schema.define do
  required(:username).filled(:string)
  required(:email).filled(:string)
  required(:password).filled(:string)
  optional(:age).filled(:integer)
end

UserOutput = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

ItemSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:price).filled(:float)
  optional(:description).filled(:string)
end

def create_user(data)
  {
    id: rand(1000),
    username: data[:username],
    email: data[:email],
    password: data[:password],
    age: data[:age],
    internal_field: 'secret'
  }
end

def create_item(data)
  {
    id: rand(1000),
    name: data[:name],
    price: data[:price],
    description: data[:description],
    internal_cost: data[:price] * 0.5
  }
end

app = FunApi::App.new do |api|
  api.post '/users',
           body: UserInput,
           response_schema: UserOutput do |input, _req, _task|
    user = create_user(input[:body])
    [user, 201]
  end

  api.post '/users/batch',
           body: [UserInput],
           response_schema: [UserOutput] do |input, _req, _task|
    users = input[:body].map { |u| create_user(u) }
    [users, 201]
  end

  api.get '/users/:id',
          response_schema: UserOutput do |input, _req, _task|
    user = {
      id: input[:path]['id'].to_i,
      username: "user_#{input[:path]['id']}",
      email: "user#{input[:path]['id']}@example.com",
      password: 'secret123',
      age: 25
    }
    [user, 200]
  end

  api.post '/items/batch',
           body: [ItemSchema],
           response_schema: [ItemSchema] do |input, _req, _task|
    items = input[:body].map { |item_data| create_item(item_data) }
    [items, 201]
  end

  api.post '/items',
           body: ItemSchema do |input, _req, _task|
    item = create_item(input[:body])
    [item, 201]
  end
end

puts '🚀 Starting FunApi server with response_schema support...'
puts '📍 Try these endpoints:'
puts '   # Single user creation (password filtered)'
puts '   curl -X POST http://localhost:3000/users -H "Content-Type: application/json" -d \'{"username":"john","email":"john@example.com","password":"secret123","age":30}\''
puts
puts '   # Batch user creation (passwords filtered)'
puts '   curl -X POST http://localhost:3000/users/batch -H "Content-Type: application/json" -d \'[{"username":"alice","email":"alice@example.com","password":"secret1"},{"username":"bob","email":"bob@example.com","password":"secret2"}]\''
puts
puts '   # Get user (password filtered)'
puts '   curl http://localhost:3000/users/123'
puts
puts '   # Batch items (internal_cost filtered)'
puts '   curl -X POST http://localhost:3000/items/batch -H "Content-Type: application/json" -d \'[{"name":"Widget","price":10.5},{"name":"Gadget","price":25.0}]\''
puts
puts '   # Single item (no response_schema, returns all fields)'
puts '   curl -X POST http://localhost:3000/items -H "Content-Type: application/json" -d \'{"name":"Thing","price":15.0}\''
puts

FunApi::Server::Falcon.start(app)
