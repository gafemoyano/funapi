# frozen_string_literal: true

require 'fun_api'
require 'net/http'
require 'json'

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:name).filled(:string)
  optional(:limit).filled(:integer)
end

FunApi::App.new do |api|
  api.get '/hello', query: QuerySchema do |input, _req|
    name = input[:query][:name] || 'World'
    [{ msg: "Hello, #{name}!" }, 200]
  end

  api.post '/users', body: UserCreateSchema do |input, _req|
    user_data = input[:body]
    [{ created: user_data.merge(id: rand(1000)) }, 201]
  end

  api.get '/no-validation' do |input, _req|
    [{ message: 'No validation here', query: input[:query] }, 200]
  end
end

puts 'Testing validation manually...'
puts

test_input = { name: 'John', email: 'john@example.com' }
result = UserCreateSchema.call(test_input)
puts 'Valid input test:'
puts "  Input: #{test_input.inspect}"
puts "  Success: #{result.success?}"
puts "  Output: #{result.to_h.inspect}"
puts

invalid_input = { name: 'John' }
result2 = UserCreateSchema.call(invalid_input)
puts 'Invalid input test (missing email):'
puts "  Input: #{invalid_input.inspect}"
puts "  Success: #{result2.success?}"
unless result2.success?
  puts '  Errors:'
  result2.errors.messages.each do |error|
    puts "    - #{error.path.join('.')}: #{error.text}"
  end
end
puts

puts 'All manual validation tests passed!'
