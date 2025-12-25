---
title: Testing
---

# Testing

Test FunApi applications with any Ruby testing framework.

## Basic Setup with Minitest

```ruby
require 'minitest/autorun'
require 'rack/test'
require 'async'

class TestMyApi < Minitest::Test
  include Rack::Test::Methods

  def app
    @app ||= FunApi::App.new do |api|
      api.get '/hello' do |input, req, task|
        [{ message: 'Hello!' }, 200]
      end
    end
  end

  def async_request(method, path, **options)
    Async do
      send(method, path, **options)
      last_response
    end.wait
  end

  def test_hello
    response = async_request(:get, '/hello')
    assert_equal 200, response.status
    assert_equal({ 'message' => 'Hello!' }, JSON.parse(response.body))
  end
end
```

## Testing with RSpec

```ruby
require 'rack/test'
require 'async'

RSpec.describe 'My API' do
  include Rack::Test::Methods

  let(:app) do
    FunApi::App.new do |api|
      api.get '/hello' do |input, req, task|
        [{ message: 'Hello!' }, 200]
      end
    end
  end

  def async_request(method, path, **options)
    Async do
      send(method, path, **options)
      last_response
    end.wait
  end

  it 'returns hello' do
    response = async_request(:get, '/hello')
    expect(response.status).to eq(200)
    expect(JSON.parse(response.body)).to eq({ 'message' => 'Hello!' })
  end
end
```

## Testing POST Requests

```ruby
def test_create_user
  response = async_request(:post, '/users',
    input: JSON.dump({ name: 'Alice', email: 'alice@example.com' }),
    'CONTENT_TYPE' => 'application/json'
  )
  
  assert_equal 201, response.status
  body = JSON.parse(response.body)
  assert_equal 'Alice', body['created']['name']
end
```

## Testing Validation Errors

```ruby
def test_validation_error
  response = async_request(:post, '/users',
    input: JSON.dump({ name: 'Alice' }),  # Missing email
    'CONTENT_TYPE' => 'application/json'
  )
  
  assert_equal 422, response.status
  body = JSON.parse(response.body)
  assert body['detail'].any? { |e| e['loc'].include?('email') }
end
```

## Testing with Dependencies

Mock dependencies for testing:

```ruby
def app
  @app ||= FunApi::App.new do |api|
    api.register(:db) { MockDatabase.new }
    
    api.get '/users', depends: [:db] do |input, req, task, db:|
      [{ users: db.all_users }, 200]
    end
  end
end

class MockDatabase
  def all_users
    [{ id: 1, name: 'Test User' }]
  end
end

def test_users_with_mock_db
  response = async_request(:get, '/users')
  assert_equal 200, response.status
  assert_equal 1, JSON.parse(response.body)['users'].length
end
```

## Testing Path Parameters

```ruby
def test_get_user_by_id
  response = async_request(:get, '/users/123')
  assert_equal 200, response.status
  assert_equal '123', JSON.parse(response.body)['id']
end
```

## Testing Query Parameters

```ruby
def test_search
  response = async_request(:get, '/search?q=ruby&limit=10')
  assert_equal 200, response.status
end
```

## Testing Headers

```ruby
def test_auth_header
  response = async_request(:get, '/protected',
    'HTTP_AUTHORIZATION' => 'Bearer token123'
  )
  assert_equal 200, response.status
end
```

## Integration Testing with Real Database

```ruby
class TestWithDatabase < Minitest::Test
  def setup
    @db = PG.connect(ENV['TEST_DATABASE_URL'])
    @db.exec("TRUNCATE users")
  end

  def teardown
    @db.close
  end

  def app
    FunApi::App.new do |api|
      api.register(:db) { @db }
      # routes...
    end
  end

  def test_creates_user_in_database
    async_request(:post, '/users',
      input: JSON.dump({ name: 'Alice', email: 'alice@test.com' }),
      'CONTENT_TYPE' => 'application/json'
    )
    
    result = @db.exec("SELECT * FROM users WHERE email = 'alice@test.com'")
    assert_equal 1, result.ntuples
  end
end
```

## Helper Module

Extract common test helpers:

```ruby
module FunApiTestHelpers
  def async_request(method, path, **options)
    Async do
      send(method, path, **options)
      last_response
    end.wait
  end

  def json_body
    JSON.parse(last_response.body)
  end

  def post_json(path, body)
    async_request(:post, path,
      input: JSON.dump(body),
      'CONTENT_TYPE' => 'application/json'
    )
  end
end
```
