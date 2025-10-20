require_relative 'lib/fun_api'
require_relative 'lib/fun_api/server/falcon'

UserSchema = FunApi::Schema.define do
  required(:name).filled(:string)
end

app = FunApi::App.new(title: "Port 3000 Test", version: "1.0.0") do |api|
  api.get '/hello' do |input, req, task|
    [{ message: 'Hello from port 3000!' }, 200]
  end
  
  api.post '/users', body: UserSchema do |input, req, task|
    [{ created: input[:body] }, 201]
  end
end

FunApi::Server::Falcon.start(app, port: 3000)
