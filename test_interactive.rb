#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative 'lib/fun_api'
require 'rack'
require 'json'

# Build the same test app from the test suite
app = FunApi::App.new do |app|
  # GET /hello?name=Ada
  app.get '/hello' do |input, _req|
    [{ msg: "Hello, #{input[:query]['name'] || 'world'}" }, 200]
  end

  # GET /users/:id
  app.get '/users/:id' do |input, _req|
    [{ id: input[:path]['id'], ok: true }, 200]
  end

  # POST /users (with body)
  app.post '/users' do |input, _req|
    body = input[:body] || {}
    [{ created: true, user: body }, 201]
  end
end

# Test with Rack::MockRequest
request = Rack::MockRequest.new(app)

puts '=== Testing FunApi ==='
puts

# Test 1: GET /hello
puts '1. GET /hello'
res = request.get('/hello')
puts "   Status: #{res.status}"
puts "   Body: #{res.body}"
puts

# Test 2: GET /hello with query param
puts '2. GET /hello?name=Ruby'
res = request.get('/hello?name=Ruby')
puts "   Status: #{res.status}"
puts "   Body: #{res.body}"
puts

# Test 3: GET /users/123
puts '3. GET /users/123'
res = request.get('/users/123')
puts "   Status: #{res.status}"
puts "   Body: #{res.body}"
puts

# Test 4: POST /users with JSON
puts '4. POST /users with JSON body'
res = request.post(
  '/users',
  'CONTENT_TYPE' => 'application/json',
  :input => { name: 'Alice', email: 'alice@example.com' }.to_json
)
puts "   Status: #{res.status}"
puts "   Body: #{res.body}"
puts

# Test 5: 404 case
puts '5. GET /nonexistent (should be 404)'
res = request.get('/nonexistent')
puts "   Status: #{res.status}"
puts "   Body: #{res.body}"

puts
puts '=== Interactive Console ==='
puts "The 'app' variable contains your FunApi::Application instance"
puts "The 'request' variable contains a Rack::MockRequest for testing"
puts "Try: request.get('/hello?name=YourName')"
puts

require 'irb'
IRB.start
