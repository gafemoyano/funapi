# frozen_string_literal: true

require "test_helper"

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
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def build_app
    FunApi::App.new do |api|
      api.post "/users", body: IntUserIn, response_schema: IntUserOut do |input, _req, _task|
        record = Struct.new(:id, :name, :email, :password)
          .new(123, input[:body][:name], input[:body][:email], "secret")
        [record, 201]
      end

      api.get "/users", response_schema: [IntUserOut] do |_input, _req, _task|
        [[{id: 1, name: "Al", email: "a@b.com", password: "x"}], 200]
      end
    end
  end

  def test_request_validation_with_model
    app = build_app
    res = async_request(app, :post, "/users",
      "CONTENT_TYPE" => "application/json",
      :input => {name: "Al", email: "a@b.com"}.to_json)

    assert_equal 201, res.status
    data = parse(res)
    assert_equal 123, data[:id]
    assert_equal "Al", data[:name]
    refute data.key?(:password)
  end

  def test_request_validation_failure_returns_422
    app = build_app
    res = async_request(app, :post, "/users",
      "CONTENT_TYPE" => "application/json",
      :input => {email: "a@b.com"}.to_json)

    assert_equal 422, res.status
    data = parse(res)
    assert(data[:detail].any? { |e| e[:loc].include?("name") })
  end

  def test_response_array_of_models_filters
    app = build_app
    res = async_request(app, :get, "/users")

    assert_equal 200, res.status
    data = parse(res)
    assert_equal 1, data.length
    refute data.first.key?(:password)
  end

  def test_response_missing_required_field_is_500
    app = FunApi::App.new do |api|
      api.get "/broken", response_schema: IntUserOut do |_input, _req, _task|
        [{name: "Al", email: "a@b.com"}, 200]
      end
    end

    res = async_request(app, :get, "/broken")
    assert_equal 500, res.status
  end

  def test_openapi_uses_model_class_name
    app = build_app
    spec = parse(async_request(app, :get, "/openapi.json"))

    assert spec[:components][:schemas].key?(:IntUserIn)
    assert spec[:components][:schemas].key?(:IntUserOut)

    ref = spec.dig(:paths, :"/users", :post, :requestBody, :content, :"application/json", :schema)
    assert_equal "#/components/schemas/IntUserIn", ref[:$ref]
  end

  def test_openapi_nested_model_inlined
    app = build_app
    spec = parse(async_request(app, :get, "/openapi.json"))
    user_in = spec[:components][:schemas][:IntUserIn]
    assert_equal "object", user_in[:properties][:address][:type]
  end

  def test_schema_define_still_works
    legacy = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post "/legacy", body: legacy do |input, _req, _task|
        [{received: input[:body][:name]}, 200]
      end
    end

    res = async_request(app, :post, "/legacy",
      "CONTENT_TYPE" => "application/json",
      :input => {name: "Legacy"}.to_json)

    assert_equal 200, res.status
    assert_equal "Legacy", parse(res)[:received]
  end

  def test_model_query_params
    query_model = Class.new(FunApi::Model) do
      field :q, :string
      field :limit, :integer, optional: true
    end

    app = FunApi::App.new do |api|
      api.get "/search", query: query_model do |input, _req, _task|
        [{q: input[:query][:q], limit: input[:query][:limit]}, 200]
      end
    end

    res = async_request(app, :get, "/search?q=ruby&limit=5")
    assert_equal 200, res.status
    data = parse(res)
    assert_equal "ruby", data[:q]
    assert_equal 5, data[:limit]
  end
end
