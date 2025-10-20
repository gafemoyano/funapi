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
end

app = FunApi::App.new do |api|
  # Option 1: Return raw hash (traditional way)
  api.post '/users/raw', body: UserInput do |input, _req, _task|
    user = {
      id: rand(1000),
      username: input[:body][:username],
      email: input[:body][:email],
      password: input[:body][:password],
      age: input[:body][:age]
    }
    [user, 201]
  end

  # Option 2: Return schema result directly (filters automatically)
  api.post '/users/schema', body: UserInput do |input, _req, _task|
    user_data = {
      id: rand(1000),
      username: input[:body][:username],
      email: input[:body][:email],
      password: input[:body][:password],
      age: input[:body][:age],
      internal_field: 'should be filtered'
    }

    # Call schema and return result directly
    result = UserOutput.call(user_data)
    [result, 201]
  end

  # Option 3: Combine schema result with response_schema validation
  api.post '/users/both',
           body: UserInput,
           response_schema: UserOutput do |input, _req, _task|
    user_data = {
      id: rand(1000),
      username: input[:body][:username],
      email: input[:body][:email],
      password: input[:body][:password],
      age: input[:body][:age]
    }

    # Return schema result, will be validated again by response_schema
    result = UserOutput.call(user_data)
    [result, 201]
  end

  # Option 4: Array of schema results
  api.post '/items/batch', body: [ItemSchema] do |input, _req, _task|
    results = input[:body].map do |item_data|
      data = {
        name: item_data[:name],
        price: item_data[:price],
        internal_cost: item_data[:price] * 0.5
      }
      ItemSchema.call(data)
    end

    [results, 201]
  end

  # Option 5: Mixed - some with schema result, some without response_schema
  api.get '/users/:id' do |input, _req, _task|
    user_data = {
      id: input[:path]['id'].to_i,
      username: "user_#{input[:path]['id']}",
      email: "user#{input[:path]['id']}@example.com",
      password: 'secret123',
      age: 25
    }

    # Return schema result directly - password filtered
    result = UserOutput.call(user_data)
    [result, 200]
  end
end

puts '🚀 Starting FunApi server with schema result support...'
puts '📍 Try these endpoints:'
puts
puts '   # Option 1: Raw hash (includes password!)'
puts '   curl -X POST http://localhost:3000/users/raw -H "Content-Type: application/json" -d \'{"username":"john","email":"john@example.com","password":"secret123","age":30}\''
puts
puts '   # Option 2: Schema result (password filtered automatically!)'
puts '   curl -X POST http://localhost:3000/users/schema -H "Content-Type: application/json" -d \'{"username":"alice","email":"alice@example.com","password":"secret123","age":25}\''
puts
puts '   # Option 3: Schema result + response_schema validation'
puts '   curl -X POST http://localhost:3000/users/both -H "Content-Type: application/json" -d \'{"username":"bob","email":"bob@example.com","password":"secret123","age":35}\''
puts
puts '   # Option 4: Array of schema results'
puts '   curl -X POST http://localhost:3000/items/batch -H "Content-Type: application/json" -d \'[{"name":"Widget","price":10.5},{"name":"Gadget","price":25.0}]\''
puts
puts '   # Option 5: GET with schema result'
puts '   curl http://localhost:3000/users/123'
puts

FunApi::Server::Falcon.start(app)
