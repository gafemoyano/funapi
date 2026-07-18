---
title: Testing
---

# Testing

The idiomatic way to test a FunApi app is `FunApi::TestClient` — an async-aware
wrapper over the Rack interface with FastAPI `TestClient` ergonomics. It drives
your app in-process (no server boot) and runs each request inside an Async
reactor for you, so there is no `Async { }.wait` in your tests.

## FunApi::TestClient

```ruby
require "funapi"
require "funapi/test_client"
require "minitest/autorun"

class TestMyApi < Minitest::Test
  def app
    @app ||= FunApi::App.new do |api|
      api.get "/hello" do |input, _req|
        [{message: "Hello, #{input[:query]["name"] || "world"}"}, 200]
      end

      api.post "/users", body: UserModel do |input, _req|
        [{created: input[:body]}, 201]
      end
    end
  end

  def client
    @client ||= FunApi::TestClient.new(app)
  end

  def test_hello
    res = client.get("/hello", params: {name: "Ada"})
    assert_equal 200, res.status
    assert_equal "Ada", res.json[:message].split(", ").last.chomp("!")
  end

  def test_create_user
    res = client.post("/users", json: {name: "Alice", email: "a@b.com"})
    assert_equal 201, res.status
    assert_equal "Alice", res.json[:created][:name]
  end
end
```

### The API

- `client.get(path, params: {}, headers: {})`
- `client.post(path, json: {...}, headers: {})` — also `put`, `patch`, `delete`
- `params:` become query-string parameters; `json:` is JSON-encoded as the body
  with the right `Content-Type`.

Each call returns a **Response** with:

- `res.status` — Integer
- `res.json` — parsed body with **symbol** keys
- `res.body` — raw String body
- `res.headers` / `res["content-type"]` — case-insensitive header access

### Testing streaming and SSE

`client.stream(path)` (aliased `client.sse(path)`) drives a `StreamingResponse`
body and collects the output without a server:

```ruby
def test_events
  res = client.sse("/events")
  assert_equal 200, res.status

  # Raw chunks:
  assert_includes res.body, "data:"

  # Parsed SSE events ({event:, id:, data:}):
  events = res.events
  assert_equal "tick", events.first[:event]
end
```

## Dependency overrides

Swap any dependency for a fake with `override_dependency`, and restore the real
ones with `reset_overrides!` (FunApi's take on FastAPI's `dependency_overrides`):

```ruby
class FakeDb
  def all_users = [{id: 1, name: "Test User"}]
end

def test_users_with_fake_db
  app.override_dependency(:db, FakeDb.new)
  res = FunApi::TestClient.new(app).get("/users")

  assert_equal 1, res.json[:users].length
ensure
  app.reset_overrides!
end
```

The replacement can be a plain object (used as-is) or a callable (invoked per
request). Overrides apply to both container dependencies (`api.register(:db)`,
used via `depends: [:db]`) and `Depends`-style dependencies, matched by the name
the route uses.

## Basic Setup with Minitest

```ruby
require 'minitest/autorun'
require 'rack/test'
require 'async'

class TestMyApi < Minitest::Test
  include Rack::Test::Methods

  def app
    @app ||= FunApi::App.new do |api|
      api.get '/hello' do |input, req|
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
      api.get '/hello' do |input, req|
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
    
    api.get '/users', depends: [:db] do |input, req, db:|
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
