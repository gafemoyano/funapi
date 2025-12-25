# frozen_string_literal: true

require "test_helper"

class TestDependencyInjection < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_route_with_simple_inline_dependency
    app = FunApi::App.new do |api|
      api.get "/test",
        depends: {value: -> { 42 }} do |_input, _req, _task, value:|
        [{value: value}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 42, data[:value]
  end

  def test_route_with_registered_dependency
    app = FunApi::App.new do |api|
      api.register(:db) { "db_connection" }

      api.get "/users",
        depends: [:db] do |_input, _req, _task, db:|
        [{connection: db}, 200]
      end
    end

    res = async_request(app, :get, "/users")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "db_connection", data[:connection]
  end

  def test_route_with_hash_registered_dependency
    app = FunApi::App.new do |api|
      api.register(:db) { "db_connection" }

      api.get "/users",
        depends: {db: nil} do |_input, _req, _task, db:|
        [{connection: db}, 200]
      end
    end

    res = async_request(app, :get, "/users")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "db_connection", data[:connection]
  end

  def test_dependency_accessing_request_context
    app = FunApi::App.new do |api|
      api.get "/test",
        depends: {
          auth: ->(req:) { req.env["HTTP_AUTHORIZATION"] }
        } do |_input, _req, _task, auth:|
        [{token: auth}, 200]
      end
    end

    res = async_request(app, :get, "/test", "HTTP_AUTHORIZATION" => "Bearer token123")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "Bearer token123", data[:token]
  end

  def test_dependency_accessing_input
    query_schema = FunApi::Schema.define do
      optional(:page).filled(:integer)
    end

    app = FunApi::App.new do |api|
      api.get "/items",
        query: query_schema,
        depends: {
          page: ->(input:) { input[:query][:page] || 1 }
        } do |_input, _req, _task, page:|
        [{page: page}, 200]
      end
    end

    res = async_request(app, :get, "/items?page=5")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 5, data[:page]
  end

  def test_nested_dependencies
    app = FunApi::App.new do |api|
      api.register(:db) { {users: [{id: 1, name: "Alice"}]} }

      api.get "/user",
        depends: {
          current_user: FunApi::Depends(->(db:) { db[:users].first }, db: :db)
        } do |_input, _req, _task, current_user:|
        [current_user, 200]
      end
    end

    res = async_request(app, :get, "/user")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "Alice", data[:name]
  end

  def test_class_based_dependency
    test_dep_class = Class.new do
      def call
        "from_class"
      end
    end

    app = FunApi::App.new do |api|
      api.get "/test",
        depends: {value: test_dep_class.new} do |_input, _req, _task, value:|
        [{value: value}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "from_class", data[:value]
  end

  def test_dependency_with_cleanup
    cleanup_called = false

    app = FunApi::App.new do |api|
      api.get "/test",
        depends: {
          resource: -> { ["resource_value", -> { cleanup_called = true }] }
        } do |_input, _req, _task, resource:|
        [{value: resource}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    assert cleanup_called, "Cleanup should have been called"
  end

  def test_multiple_dependencies
    app = FunApi::App.new do |api|
      api.register(:db) { "db_connection" }
      api.register(:cache) { "cache_connection" }

      api.get "/test",
        depends: %i[db cache] do |_input, _req, _task, db:, cache:|
        [{db: db, cache: cache}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "db_connection", data[:db]
    assert_equal "cache_connection", data[:cache]
  end

  def test_dependency_caching_per_request
    call_count = 0

    app = FunApi::App.new do |api|
      api.register(:counter) do
        call_count += 1
        call_count
      end

      api.get "/test",
        depends: {
          count1: :counter,
          count2: :counter
        } do |_input, _req, _task, count1:, count2:|
        [{count1: count1, count2: count2}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal 1, data[:count1]
    assert_equal 1, data[:count2]
    assert_equal 1, call_count
  end

  def test_route_without_dependencies_still_works
    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, _task|
        [{message: "no deps"}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "no deps", data[:message]
  end

  def test_dependency_with_async_task
    app = FunApi::App.new do |api|
      api.get "/test",
        depends: {
          async_value: lambda { |task:|
            result = task.async { "async_result" }
            result.wait
          }
        } do |_input, _req, _task, async_value:|
        [{value: async_value}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "async_result", data[:value]
  end
end
