# frozen_string_literal: true

require 'test_helper'

class TestValidation < Minitest::Test
  def app_with_schemas(&block)
    query_schema = FunApi::Schema.define do
      required(:name).filled(:string)
      optional(:limit).filled(:integer)
    end

    body_schema = FunApi::Schema.define do
      required(:email).filled(:string)
      required(:password).filled(:string)
      optional(:age).filled(:integer)
    end

    strict_schema = FunApi::Schema.define do
      required(:field1).filled(:string)
      required(:field2).filled(:integer)
    end

    FunApi::App.new do |api|
      block.call(api, query_schema, body_schema, strict_schema) if block

      api.get '/query-test', query: query_schema do |input, _req, _task|
        [{ received: input[:query] }, 200]
      end

      api.post '/body-test', body: body_schema do |input, _req, _task|
        [{ received: input[:body] }, 201]
      end

      api.post '/strict', body: strict_schema do |input, _req, _task|
        [{ received: input[:body] }, 200]
      end
    end
  end

  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_query_validation_success
    app = app_with_schemas
    res = async_request(app, :get, '/query-test?name=Alice&limit=10')

    assert_equal 200, res.status
    data = parse(res)
    assert_equal 'Alice', data[:received][:name]
    assert_equal 10, data[:received][:limit]
  end

  def test_query_validation_missing_required_field
    app = app_with_schemas
    res = async_request(app, :get, '/query-test?limit=10')

    assert_equal 422, res.status
    data = parse(res)
    assert data[:detail].is_a?(Array)
    assert(data[:detail].any? { |e| e[:loc].include?('name') })
  end

  def test_query_validation_wrong_type
    app = app_with_schemas
    res = async_request(app, :get, '/query-test?name=Alice&limit=not_a_number')

    assert_equal 422, res.status
    data = parse(res)
    assert(data[:detail].any? { |e| e[:loc].include?('limit') })
  end

  def test_body_validation_success
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: 'test@example.com', password: 'secret123' }.to_json
    )

    assert_equal 201, res.status
    data = parse(res)
    assert_equal 'test@example.com', data[:received][:email]
    assert_equal 'secret123', data[:received][:password]
  end

  def test_body_validation_with_optional_field
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: 'test@example.com', password: 'secret', age: 25 }.to_json
    )

    assert_equal 201, res.status
    data = parse(res)
    assert_equal 25, data[:received][:age]
  end

  def test_body_validation_missing_required_field
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: 'test@example.com' }.to_json
    )

    assert_equal 422, res.status
    data = parse(res)
    assert(data[:detail].any? { |e| e[:loc].include?('password') })
  end

  def test_body_validation_empty_required_field
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: '', password: 'secret' }.to_json
    )

    assert_equal 422, res.status
    data = parse(res)
    assert(data[:detail].any? { |e| e[:loc].include?('email') })
  end

  def test_body_validation_wrong_type
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: 'test@example.com', password: 'secret', age: 'not a number' }.to_json
    )

    assert_equal 422, res.status
    data = parse(res)
    assert(data[:detail].any? { |e| e[:loc].include?('age') })
  end

  def test_multiple_validation_errors
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/strict',
      'CONTENT_TYPE' => 'application/json',
      :input => {}.to_json
    )

    assert_equal 422, res.status
    data = parse(res)
    assert_equal 2, data[:detail].length
    assert(data[:detail].any? { |e| e[:loc].include?('field1') })
    assert(data[:detail].any? { |e| e[:loc].include?('field2') })
  end

  def test_validation_error_format
    app = app_with_schemas
    res = async_request(app, :get, '/query-test')

    assert_equal 422, res.status
    data = parse(res)

    error = data[:detail].first
    assert error.key?(:loc)
    assert error.key?(:msg)
    assert error.key?(:type)
    assert_equal 'value_error', error[:type]
  end

  def test_extra_fields_allowed_in_body
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => {
        email: 'test@example.com',
        password: 'secret',
        extra_field: 'ignored'
      }.to_json
    )

    assert_equal 201, res.status
  end

  def test_malformed_json_body
    app = app_with_schemas
    res = async_request(
      app,
      :post,
      '/body-test',
      'CONTENT_TYPE' => 'application/json',
      :input => 'not valid json'
    )

    assert_equal 422, res.status
  end

  def test_array_body_validation
    item_schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post '/items', body: [item_schema] do |input, _req, _task|
        [{ count: input[:body].length }, 200]
      end
    end

    res = async_request(
      app,
      :post,
      '/items',
      'CONTENT_TYPE' => 'application/json',
      :input => [{ name: 'Item 1' }, { name: 'Item 2' }].to_json
    )

    assert_equal 200, res.status
    data = parse(res)
    assert_equal 2, data[:count]
  end

  def test_array_body_validation_failure
    item_schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post '/items', body: [item_schema] do |input, _req, _task|
        [{ count: input[:body].length }, 200]
      end
    end

    res = async_request(
      app,
      :post,
      '/items',
      'CONTENT_TYPE' => 'application/json',
      :input => [{ name: 'Good' }, { bad: 'item' }].to_json
    )

    assert_equal 422, res.status
  end
end
