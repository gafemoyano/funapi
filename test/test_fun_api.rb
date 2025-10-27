# frozen_string_literal: true

require 'test_helper'

class TestFunApi < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::FunApi::VERSION
  end

  def build_app
    query_schema = FunApi::Schema.define do
      optional(:name).filled(:string)
    end

    user_schema = FunApi::Schema.define do
      required(:name).filled(:string)
      required(:email).filled(:string)
    end

    invalid_schema = FunApi::Schema.define do
      required(:required_field).filled(:string)
    end

    FunApi::App.new do |app|
      app.get '/hello', query: query_schema do |input, _req, _task|
        [{ msg: "Hello, #{input[:query][:name] || 'world'}" }, 200]
      end

      app.get '/users/:id' do |input, _req, _task|
        [{ id: input[:path]['id'], ok: true }, 200]
      end

      app.post '/users', body: user_schema do |input, _req, _task|
        body = input[:body] || {}
        [{ created: true, user: body }, 201]
      end

      app.put '/users/:id' do |input, _req, _task|
        [{ updated: true, id: input[:path]['id'], attrs: input[:body] }, 200]
      end

      app.delete '/users/:id' do |input, _req, _task|
        [{ deleted: true, id: input[:path]['id'] }, 200]
      end

      app.get '/validated', query: query_schema do |input, _req, _task|
        [{ ok: true, echo: input[:query] }, 200]
      end

      app.get '/invalid', query: invalid_schema do |_input, _req, _task|
        [{ unreachable: true }, 200]
      end
    end
  end

  def app
    @app ||= build_app
  end

  def request(method, path, **options)
    Async do
      mock_request = Rack::MockRequest.new(app)
      mock_request.send(method, path, **options)
    end.wait
  end

  def parse(res)
    JSON.parse(res.body)
  end

  def test_get_with_query_params
    res = request(:get, '/hello?name=Ada')
    assert_equal 200, res.status
    assert_equal 'application/json', res['content-type']
    assert_equal({ 'msg' => 'Hello, Ada' }, parse(res))
  end

  def test_get_without_query_params
    res = request(:get, '/hello')
    assert_equal 200, res.status
    assert_equal({ 'msg' => 'Hello, world' }, parse(res))
  end

  def test_get_with_path_param
    res = request(:get, '/users/42')
    assert_equal 200, res.status
    assert_equal({ 'id' => '42', 'ok' => true }, parse(res))
  end

  def test_post_with_json_body
    res = request(
      :post,
      '/users',
      'CONTENT_TYPE' => 'application/json',
      :input => { name: 'Tess', email: 'tess@example.com' }.to_json
    )
    assert_equal 201, res.status
    data = parse(res)
    assert_equal true, data['created']
    assert_equal 'Tess', data['user']['name']
    assert_equal 'tess@example.com', data['user']['email']
  end

  def test_put_with_json_body_and_path
    res = request(
      :put,
      '/users/7',
      'CONTENT_TYPE' => 'application/json',
      :input => { email: 'tess@example.com' }.to_json
    )
    assert_equal 200, res.status
    assert_equal(
      { 'updated' => true, 'id' => '7', 'attrs' => { 'email' => 'tess@example.com' } },
      parse(res)
    )
  end

  def test_delete_with_path
    res = request(:delete, '/users/9')
    assert_equal 200, res.status
    assert_equal({ 'deleted' => true, 'id' => '9' }, parse(res))
  end

  def test_schema_validation_success
    res = request(:get, '/validated?name=Alice')
    assert_equal 200, res.status
    data = parse(res)
    assert_equal true, data['ok']
    assert_equal 'Alice', data['echo']['name']
  end

  def test_schema_validation_failure_returns_422
    res = request(:get, '/invalid')
    assert_equal 422, res.status
    data = parse(res)
    assert data['detail'].is_a?(Array)
    assert(data['detail'].any? { |e| e['loc'].include?('required_field') })
    assert_equal 'is missing', data['detail'].first['msg']
  end

  def test_content_type_header_is_json
    res = request(:get, '/hello')
    assert_equal 'application/json', res['content-type']
  end
end
