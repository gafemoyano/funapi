# frozen_string_literal: true

require "test_helper"

class TestResponseSchema < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_response_schema_filters_extra_fields
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.get "/user", response_schema: output_schema do |_input, _req, _task|
        user = {
          id: 1,
          name: "Alice",
          password: "secret",
          internal_data: "should not be visible"
        }
        [user, 200]
      end
    end

    res = async_request(app, :get, "/user")
    data = parse(res)

    assert_equal 1, data[:id]
    assert_equal "Alice", data[:name]
    refute data.key?(:password)
    refute data.key?(:internal_data)
  end

  def test_response_schema_with_optional_field
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
      optional(:email).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.get "/user/:id", response_schema: output_schema do |input, _req, _task|
        if input[:path]["id"] == "1"
          [{id: 1, name: "Alice", email: "alice@example.com"}, 200]
        else
          [{id: 2, name: "Bob"}, 200]
        end
      end
    end

    res1 = async_request(app, :get, "/user/1")
    data1 = parse(res1)
    assert_equal "alice@example.com", data1[:email]

    res2 = async_request(app, :get, "/user/2")
    data2 = parse(res2)
    refute data2.key?(:email)
  end

  def test_response_schema_array
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.get "/users", response_schema: [output_schema] do |_input, _req, _task|
        users = [
          {id: 1, name: "Alice", password: "secret1"},
          {id: 2, name: "Bob", password: "secret2"}
        ]
        [users, 200]
      end
    end

    res = async_request(app, :get, "/users")
    data = parse(res)

    assert_equal 2, data.length
    assert_equal "Alice", data[0][:name]
    assert_equal "Bob", data[1][:name]
    refute data[0].key?(:password)
    refute data[1].key?(:password)
  end

  def test_response_schema_preserves_nested_objects
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:profile).hash do
        required(:name).filled(:string)
        required(:age).filled(:integer)
      end
    end

    app = FunApi::App.new do |api|
      api.get "/user", response_schema: output_schema do |_input, _req, _task|
        user = {
          id: 1,
          profile: {name: "Alice", age: 30, secret: "hidden"},
          password: "should not appear"
        }
        [user, 200]
      end
    end

    res = async_request(app, :get, "/user")
    data = parse(res)

    assert_equal 1, data[:id]
    assert_equal "Alice", data[:profile][:name]
    assert_equal 30, data[:profile][:age]
    refute data.key?(:password)
  end

  def test_response_schema_without_schema_returns_all_fields
    app = FunApi::App.new do |api|
      api.get "/user" do |_input, _req, _task|
        [{id: 1, name: "Alice", password: "visible"}, 200]
      end
    end

    res = async_request(app, :get, "/user")
    data = parse(res)

    assert_equal 1, data[:id]
    assert_equal "Alice", data[:name]
    assert_equal "visible", data[:password]
  end

  def test_response_schema_filters_each_item_in_array
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:title).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.get "/posts", response_schema: [output_schema] do |_input, _req, _task|
        posts = [
          {id: 1, title: "Post 1", author_id: 100, internal: "data"},
          {id: 2, title: "Post 2", author_id: 101, internal: "more"}
        ]
        [posts, 200]
      end
    end

    res = async_request(app, :get, "/posts")
    data = parse(res)

    assert_equal 2, data.length
    data.each do |post|
      assert post.key?(:id)
      assert post.key?(:title)
      refute post.key?(:author_id)
      refute post.key?(:internal)
    end
  end

  def test_response_schema_with_empty_array
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
    end

    app = FunApi::App.new do |api|
      api.get "/items", response_schema: [output_schema] do |_input, _req, _task|
        [[], 200]
      end
    end

    res = async_request(app, :get, "/items")
    data = parse(res)

    assert_equal [], data
  end

  def test_response_schema_different_for_different_routes
    user_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    post_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:title).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.get "/user", response_schema: user_schema do |_input, _req, _task|
        [{id: 1, name: "Alice", password: "secret"}, 200]
      end

      api.get "/post", response_schema: post_schema do |_input, _req, _task|
        [{id: 1, title: "Post", author: "Alice"}, 200]
      end
    end

    user_res = async_request(app, :get, "/user")
    user_data = parse(user_res)
    assert_equal "Alice", user_data[:name]
    refute user_data.key?(:password)

    post_res = async_request(app, :get, "/post")
    post_data = parse(post_res)
    assert_equal "Post", post_data[:title]
    refute post_data.key?(:author)
  end

  def test_response_schema_with_post_request
    output_schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:email).filled(:string)
    end

    input_schema = FunApi::Schema.define do
      required(:email).filled(:string)
      required(:password).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post "/users", body: input_schema, response_schema: output_schema do |input, _req, _task|
        user = {
          id: 123,
          email: input[:body][:email],
          password: input[:body][:password],
          created_at: Time.now.to_i
        }
        [user, 201]
      end
    end

    res = async_request(
      app,
      :post,
      "/users",
      "CONTENT_TYPE" => "application/json",
      :input => {email: "test@example.com", password: "secret"}.to_json
    )

    assert_equal 201, res.status
    data = parse(res)
    assert_equal 123, data[:id]
    assert_equal "test@example.com", data[:email]
    refute data.key?(:password)
    refute data.key?(:created_at)
  end
end
