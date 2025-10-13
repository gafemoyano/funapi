# frozen_string_literal: true

require 'fun_api'
require 'fun_api/server/falcon'
require 'dry/validation'

class NewUserContract < Dry::Validation::Contract
  params do
    required(:email).filled(:string)
    required(:age).value(:integer)
  end
end

# Build the application
app = FunApi::App.new do |api|
  api.get '/hello' do |_input, _req|
    [{ msg: 'Hello from FunApi!' }, 200]
  end

  api.get '/users/:id', contract: NewUserContract do |input, _req|
    [{ id: input[:path]['id'], message: 'User found' }, 200]
  end
end

# app.run!(port: 9292) if __FILE__ == $0

FunApi::Server::Falcon.start(app)
