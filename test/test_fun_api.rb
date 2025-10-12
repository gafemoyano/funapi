# frozen_string_literal: true

require 'test_helper'

# Minimal “contract” fakes to avoid pulling in dry-validation in tests:
class FakeContractSuccess
  def call(input)
    @input = input
    self
  end

  def success? = true
  def to_h = @input # echo back (pretend coercion)
  def errors = {}   # for symmetry
end

class FakeContractFailure
  def call(_input) = self
  def success? = false
  def to_h = {}
  def errors = { query: ['invalid'] }
end

class TestFunApi < Minitest::Test
  def test_that_it_has_a_version_number
    refute_nil ::FunApi::VERSION
  end

  def build_app
    FunApi::Application.new do |app|
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

      # PUT /users/:id (with body)
      app.put '/users/:id' do |input, _req|
        [{ updated: true, id: input[:path]['id'], attrs: input[:body] }, 200]
      end

      # DELETE /users/:id
      app.delete '/users/:id' do |input, _req|
        [{ deleted: true, id: input[:path]['id'] }, 200]
      end

      # GET /validated uses a passing contract
      app.get '/validated', contract: FakeContractSuccess.new do |input, _req|
        [{ ok: true, echo: input[:query] }, 200]
      end

      # GET /invalid uses a failing contract
      app.get '/invalid', contract: FakeContractFailure.new do |_input, _req|
        # won't be called
        [{ unreachable: true }, 200]
      end
    end
  end

  def request
    @request ||= Rack::MockRequest.new(build_app)
  end

  def parse(res)
    JSON.parse(res.body)
  end

  def test_get_with_query_params
    res = request.get('/hello?name=Ada')
    assert_equal 200, res.status
    assert_equal 'application/json', res['content-type']
    assert_equal({ 'msg' => 'Hello, Ada' }, parse(res))
  end

  def test_get_without_query_params
    res = request.get('/hello')
    assert_equal 200, res.status
    assert_equal({ 'msg' => 'Hello, world' }, parse(res))
  end

  def test_get_with_path_param
    res = request.get('/users/42')
    assert_equal 200, res.status
    assert_equal({ 'id' => '42', 'ok' => true }, parse(res))
  end

  def test_post_with_json_body
    res = request.post(
      '/users',
      'CONTENT_TYPE' => 'application/json',
      input: { name: 'Tess' }.to_json
    )
    assert_equal 201, res.status
    assert_equal({ 'created' => true, 'user' => { 'name' => 'Tess' } }, parse(res))
  end

  def test_put_with_json_body_and_path
    res = request.put(
      '/users/7',
      'CONTENT_TYPE' => 'application/json',
      input: { email: 'tess@example.com' }.to_json
    )
    assert_equal 200, res.status
    assert_equal(
      { 'updated' => true, 'id' => '7', 'attrs' => { 'email' => 'tess@example.com' } },
      parse(res)
    )
  end

  def test_delete_with_path
    res = request.delete('/users/9')
    assert_equal 200, res.status
    assert_equal({ 'deleted' => true, 'id' => '9' }, parse(res))
  end

  def test_contract_success_returns_200
    res = request.get('/validated?limit=10')
    assert_equal 200, res.status
    assert_equal({ 'ok' => true, 'echo' => { 'limit' => '10' } }, parse(res))
  end

  def test_contract_failure_returns_422
    res = request.get('/invalid')
    assert_equal 422, res.status
    assert_equal({ 'errors' => { 'query' => ['invalid'] } }, parse(res))
  end

  def test_content_type_header_is_json
    res = request.get('/hello')
    assert_equal 'application/json', res['content-type']
  end
end
