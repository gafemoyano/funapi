# frozen_string_literal: true

require "test_helper"
require "funapi/test_client"

class IntAddress < FunApi::Model
  field :street, :string
end

class IntUserIn < FunApi::Model
  field :name, :string
  field :email, :string, format: "email"
  field :address, IntAddress, optional: true
end

class IntUserOut < FunApi::Model
  field :id, :integer
  field :name, :string
  field :email, :string
end

class TestModelIntegration < Minitest::Test
  def build_app
    FunApi::App.new do |api|
      api.post "/users", body: IntUserIn, response_schema: IntUserOut do |input, _req|
        record = Struct.new(:id, :name, :email, :password)
          .new(123, input[:body][:name], input[:body][:email], "secret")
        [record, 201]
      end

      api.get "/users", response_schema: [IntUserOut] do |_input, _req|
        [[{id: 1, name: "Al", email: "a@b.com", password: "x"}], 200]
      end
    end
  end

  def client(app = build_app)
    FunApi::TestClient.new(app)
  end

  def test_request_validation_with_model
    res = client.post("/users", json: {name: "Al", email: "a@b.com"})

    assert_equal 201, res.status
    data = res.json
    assert_equal 123, data[:id]
    assert_equal "Al", data[:name]
    refute data.key?(:password)
  end

  def test_request_validation_failure_returns_422
    res = client.post("/users", json: {email: "a@b.com"})

    assert_equal 422, res.status
    assert(res.json[:detail].any? { |e| e[:loc].include?("name") })
  end

  def test_response_array_of_models_filters
    res = client.get("/users")

    assert_equal 200, res.status
    data = res.json
    assert_equal 1, data.length
    refute data.first.key?(:password)
  end

  def test_response_missing_required_field_is_500
    app = FunApi::App.new do |api|
      api.get "/broken", response_schema: IntUserOut do |_input, _req|
        [{name: "Al", email: "a@b.com"}, 200]
      end
    end

    res = client(app).get("/broken")
    assert_equal 500, res.status
  end

  def test_openapi_uses_model_class_name
    spec = client.get("/openapi.json").json

    assert spec[:components][:schemas].key?(:IntUserIn)
    assert spec[:components][:schemas].key?(:IntUserOut)

    ref = spec.dig(:paths, :"/users", :post, :requestBody, :content, :"application/json", :schema)
    assert_equal "#/components/schemas/IntUserIn", ref[:$ref]
  end

  def test_openapi_nested_model_inlined
    spec = client.get("/openapi.json").json
    user_in = spec[:components][:schemas][:IntUserIn]
    assert_equal "object", user_in[:properties][:address][:type]
  end

  def test_schema_define_still_works
    legacy = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post "/legacy", body: legacy do |input, _req|
        [{received: input[:body][:name]}, 200]
      end
    end

    res = client(app).post("/legacy", json: {name: "Legacy"})

    assert_equal 200, res.status
    assert_equal "Legacy", res.json[:received]
  end

  def test_model_query_params
    query_model = Class.new(FunApi::Model) do
      field :q, :string
      field :limit, :integer, optional: true
    end

    app = FunApi::App.new do |api|
      api.get "/search", query: query_model do |input, _req|
        [{q: input[:query][:q], limit: input[:query][:limit]}, 200]
      end
    end

    res = client(app).get("/search", params: {q: "ruby", limit: 5})
    assert_equal 200, res.status
    data = res.json
    assert_equal "ruby", data[:q]
    assert_equal 5, data[:limit]
  end
end
