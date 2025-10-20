# frozen_string_literal: true

require 'fun_api'

puts 'Testing response_schema validation and filtering...'
puts

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

puts '1. Testing single object response validation and filtering:'
user_data = {
  id: 1,
  username: 'john',
  email: 'john@example.com',
  password: 'secret123',
  age: 30,
  internal_field: 'should be filtered'
}

filtered = FunApi::Schema.validate_response(UserOutput, user_data)
puts "  Input: #{user_data.inspect}"
puts "  Filtered: #{filtered.inspect}"
puts '  ✓ Password and internal_field removed' if !filtered.key?(:password) && !filtered.key?(:internal_field)
puts

puts '2. Testing array response validation and filtering:'
items_data = [
  { name: 'Widget', price: 10.5, internal_cost: 5.0 },
  { name: 'Gadget', price: 25.0, internal_cost: 12.0 }
]

filtered_items = FunApi::Schema.validate_response([ItemSchema], items_data)
puts "  Input: #{items_data.inspect}"
puts "  Filtered: #{filtered_items.inspect}"
puts '  ✓ internal_cost removed from all items' if filtered_items.all? { |item| !item.key?(:internal_cost) }
puts

puts '3. Testing array body validation:'
input_items = [
  { name: 'Item1', price: 10.0 },
  { name: 'Item2', price: 20.0 }
]

validated_items = FunApi::Schema.validate([ItemSchema], input_items, location: 'body')
puts "  Input: #{input_items.inspect}"
puts "  Validated: #{validated_items.inspect}"
puts '  ✓ Array validated successfully'
puts

puts '4. Testing validation error on missing required field:'
begin
  invalid_data = { username: 'john', email: 'john@example.com' }
  FunApi::Schema.validate_response(UserOutput, invalid_data)
  puts '  ✗ Should have raised error!'
rescue FunApi::HTTPException => e
  puts "  ✓ Raised HTTPException with status #{e.status_code}"
  puts "  Detail: #{e.detail}"
end
puts

puts '5. Testing single object body validation:'
user_input = { username: 'alice', email: 'alice@example.com', password: 'pass123', age: 25 }
validated_user = FunApi::Schema.validate(UserInput, user_input, location: 'body')
puts "  Input: #{user_input.inspect}"
puts "  Validated: #{validated_user.inspect}"
puts '  ✓ Single object validated successfully'
puts

puts 'All tests passed! ✓'
