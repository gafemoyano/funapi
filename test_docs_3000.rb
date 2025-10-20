require_relative 'lib/fun_api'
require_relative 'lib/fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
end

app = FunApi::App.new(
  title: "Test API",
  version: "1.0.0",
  description: "Testing on port 3000"
) do |api|
  api.get '/users' do |input, req, task|
    [{ message: 'Users endpoint' }, 200]
  end
  
  api.post '/users', body: UserSchema do |input, req, task|
    [input[:body], 201]
  end
end

puts "Server starting on port 3000"
puts "Docs: http://localhost:3000/docs"
puts "OpenAPI: http://localhost:3000/openapi.json"
puts

FunApi::Server::Falcon.start(app, port: 3000)
