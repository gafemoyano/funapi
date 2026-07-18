# frozen_string_literal: true

require "test_helper"
require "funapi/test_client"

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
      app.get "/hello", query: query_schema do |input, _req|
        [{msg: "Hello, #{input[:query][:name] || "world"}"}, 200]
      end

      app.get "/users/:id" do |input, _req|
        [{id: input[:path][:id], ok: true}, 200]
      end

      app.post "/users", body: user_schema do |input, _req|
        body = input[:body] || {}
        [{created: true, user: body}, 201]
      end

      app.put "/users/:id" do |input, _req|
        [{updated: true, id: input[:path][:id], attrs: input[:body]}, 200]
      end

      app.delete "/users/:id" do |input, _req|
        [{deleted: true, id: input[:path][:id]}, 200]
      end

      app.get "/validated", query: query_schema do |input, _req|
        [{ok: true, echo: input[:query]}, 200]
      end

      app.get "/invalid", query: invalid_schema do |_input, _req|
        [{unreachable: true}, 200]
      end

      app.get "/headers" do |input, _req|
        [{auth: input[:headers]["authorization"], custom: input[:headers]["x-custom-header"]}, 200]
      end
    end
  end

  def client
    @client ||= FunApi::TestClient.new(build_app)
  end

  def test_get_with_query_params
    res = client.get("/hello", params: {name: "Ada"})
    assert_equal 200, res.status
    assert_equal "application/json", res["content-type"]
    assert_equal({msg: "Hello, Ada"}, res.json)
  end

  def test_get_without_query_params
    res = client.get("/hello")
    assert_equal 200, res.status
    assert_equal({msg: "Hello, world"}, res.json)
  end

  def test_get_with_path_param
    res = client.get("/users/42")
    assert_equal 200, res.status
    assert_equal({id: "42", ok: true}, res.json)
  end

  def test_post_with_json_body
    res = client.post("/users", json: {name: "Tess", email: "tess@example.com"})
    assert_equal 201, res.status
    data = res.json
    assert_equal true, data[:created]
    assert_equal "Tess", data[:user][:name]
    assert_equal "tess@example.com", data[:user][:email]
  end

  def test_put_with_json_body_and_path
    res = client.put("/users/7", json: {email: "tess@example.com"})
    assert_equal 200, res.status
    assert_equal(
      {updated: true, id: "7", attrs: {email: "tess@example.com"}},
      res.json
    )
  end

  def test_delete_with_path
    res = client.delete("/users/9")
    assert_equal 200, res.status
    assert_equal({deleted: true, id: "9"}, res.json)
  end

  def test_schema_validation_success
    res = client.get("/validated", params: {name: "Alice"})
    assert_equal 200, res.status
    data = res.json
    assert_equal true, data[:ok]
    assert_equal "Alice", data[:echo][:name]
  end

  def test_schema_validation_failure_returns_422
    res = client.get("/invalid")
    assert_equal 422, res.status
    data = res.json
    assert data[:detail].is_a?(Array)
    assert(data[:detail].any? { |e| e[:loc].include?("required_field") })
    assert_equal "is missing", data[:detail].first[:msg]
  end

  def test_content_type_header_is_json
    res = client.get("/hello")
    assert_equal "application/json", res["content-type"]
  end

  def test_input_includes_downcased_headers
    res = client.get("/headers",
      headers: {"X-Custom-Header" => "value", "Authorization" => "Bearer token"})
    assert_equal "value", res.json[:custom]
    assert_equal "Bearer token", res.json[:auth]
  end
end
