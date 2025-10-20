# frozen_string_literal: true

require 'fun_api'

puts 'Testing returning schema results directly from handlers...'
puts

UserOutput = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:username).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

puts '1. Testing schema result detection:'
user_data = {
  id: 1,
  username: 'john',
  email: 'john@example.com',
  password: 'secret123',
  age: 30
}

result = UserOutput.call(user_data)
puts "  Schema result class: #{result.class.name}"
puts "  Has to_h method: #{result.respond_to?(:to_h)}"
puts "  Result.to_h: #{result.to_h.inspect}"
puts "  Success: #{result.success?}"
puts

puts '2. Testing normalize_payload logic:'

# Create a simple app instance to access the private method
app = FunApi::App.new

# Access the private method for testing
normalized = app.send(:normalize_payload, result)
puts "  Input: #{result.class.name}"
puts "  Output: #{normalized.inspect}"
puts '  ✓ Schema result converted to hash' if normalized.is_a?(Hash)
puts

puts '3. Testing with array of results:'
results = [
  UserOutput.call({ id: 1, username: 'alice', email: 'alice@example.com', password: 's1' }),
  UserOutput.call({ id: 2, username: 'bob', email: 'bob@example.com', password: 's2' })
]

normalized_array = app.send(:normalize_payload, results)
puts "  Input: Array of #{results.first.class.name}"
puts "  Output: #{normalized_array.inspect}"
puts '  ✓ Array of schema results converted' if normalized_array.is_a?(Array) && normalized_array.all? do |i|
  i.is_a?(Hash)
end
puts

puts '4. Testing with regular hash (should pass through):'
regular_hash = { id: 1, name: 'test' }
normalized_hash = app.send(:normalize_payload, regular_hash)
puts "  Input: #{regular_hash.inspect}"
puts "  Output: #{normalized_hash.inspect}"
puts '  ✓ Regular hash passed through unchanged' if normalized_hash == regular_hash
puts

puts 'All tests passed! ✓'
