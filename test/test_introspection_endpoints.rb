# frozen_string_literal: true

require_relative "test_helper"
require "json"

UserCreateSchema = FunApi::Schema.define do
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

UserOutputSchema = FunApi::Schema.define do
  required(:id).filled(:integer)
  required(:name).filled(:string)
  required(:email).filled(:string)
  optional(:age).filled(:integer)
end

QuerySchema = FunApi::Schema.define do
  optional(:limit).filled(:integer)
  optional(:offset).filled(:integer)
end

class TestIntrospectionEndpoints < Minitest::Test
  def setup
    @app = FunApi::App.new do |api|
      api.register(:db) { Object.new }
      api.register(:logger) { Object.new }
      api.register(:cache) { Object.new }

      api.add_cors

      api.get "/users", query: QuerySchema, response_schema: [UserOutputSchema],
        depends: [:db] do |_input, _req, _task, db:|
        [[{id: 1, name: "John", email: "john@example.com"}], 200]
      end

      api.get "/users/:id", response_schema: UserOutputSchema, depends: [:db] do |input, _req, _task, db:|
        [{id: input[:path]["id"].to_i, name: "John", email: "john@example.com"}, 200]
      end

      api.post "/users", body: UserCreateSchema, response_schema: UserOutputSchema,
        depends: %i[db logger] do |input, _req, _task, db:, logger:|
        [input[:body].merge(id: 1), 201]
      end

      api.delete "/users/:id", depends: %i[db logger] do |_input, _req, _task, db:, logger:|
        [{deleted: true}, 200]
      end
    end
  end

  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def json_response(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_introspect_overview
    response = async_request(@app, :get, "/introspect")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal 4, data[:data][:stats][:routes]
    assert_equal 3, data[:data][:stats][:dependencies]
    assert data[:data][:health][:score] > 0
    assert_includes data[:data][:verbs], "GET"
    assert_includes data[:data][:verbs], "POST"
    assert_equal "/introspect/routes", data[:data][:endpoints][:routes]
  end

  def test_introspect_routes_list
    response = async_request(@app, :get, "/introspect/routes")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal 4, data[:data][:count]

    routes = data[:data][:routes]
    post_route = routes.find { |r| r[:verb] == "POST" && r[:path] == "/users" }
    assert post_route
    assert_equal %w[db logger], post_route[:dependencies].map(&:to_s)
    assert post_route[:body_schema]
    assert post_route[:has_body_schema]
    assert post_route[:response_schema]
    assert post_route[:has_response_schema]
  end

  def test_introspect_routes_filter_by_verb
    response = async_request(@app, :get, "/introspect/routes?verb=GET")
    assert_equal 200, response.status

    data = json_response(response)
    assert_equal 2, data[:data][:count]
    data[:data][:routes].each do |route|
      assert_equal "GET", route[:verb]
    end
  end

  def test_introspect_routes_filter_by_dependency
    response = async_request(@app, :get, "/introspect/routes?uses_dep=logger")
    assert_equal 200, response.status

    data = json_response(response)
    assert_equal 2, data[:data][:count]
    data[:data][:routes].each do |route|
      assert_includes route[:dependencies].map(&:to_s), "logger"
    end
  end

  def test_introspect_routes_filter_by_has_body
    response = async_request(@app, :get, "/introspect/routes?has_body=true")
    assert_equal 200, response.status

    data = json_response(response)
    assert_equal 1, data[:data][:count]
    assert_equal "POST", data[:data][:routes].first[:verb]
  end

  def test_introspect_routes_search
    response = async_request(@app, :get, "/introspect/routes?search=users")
    assert_equal 200, response.status

    data = json_response(response)
    assert_equal 4, data[:data][:count]
    data[:data][:routes].each do |route|
      assert_includes route[:path].downcase, "users"
    end
  end

  def test_introspect_single_route
    response = async_request(@app, :get, "/introspect/routes/POST/users")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal "POST", data[:data][:verb]
    assert_equal "/users", data[:data][:path]
    assert data[:data][:schemas][:body]
    assert_equal %w[name email], data[:data][:schemas][:body][:required_fields].map(&:to_s)
    assert data[:data][:example_request]
  end

  def test_introspect_single_route_with_path_param
    response = async_request(@app, :get, "/introspect/routes/GET/%2Fusers%2F%3Aid")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal "GET", data[:data][:verb]
    assert_equal "/users/:id", data[:data][:path]
    assert_equal ["id"], data[:data][:path_params]
  end

  def test_introspect_single_route_not_found
    response = async_request(@app, :get, "/introspect/routes/PUT/nonexistent")
    assert_equal 404, response.status

    data = json_response(response)
    refute data[:ok]
    assert_includes data[:error], "not found"
  end

  def test_introspect_dependencies_list
    response = async_request(@app, :get, "/introspect/dependencies")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal 3, data[:data][:count]

    db_dep = data[:data][:dependencies].find { |d| d[:name].to_s == "db" }
    assert db_dep
    assert_equal 4, db_dep[:used_by_count]
  end

  def test_introspect_dependencies_filter_unused
    response = async_request(@app, :get, "/introspect/dependencies?unused=true")
    assert_equal 200, response.status

    data = json_response(response)
    assert_equal 1, data[:data][:count]
    assert_equal "cache", data[:data][:dependencies].first[:name].to_s
  end

  def test_introspect_single_dependency
    response = async_request(@app, :get, "/introspect/dependencies/db")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert_equal "db", data[:data][:name].to_s
    assert_equal 4, data[:data][:used_by_count]
    assert_includes data[:data][:used_by_routes], "/users"
  end

  def test_introspect_single_dependency_not_found
    response = async_request(@app, :get, "/introspect/dependencies/nonexistent")
    assert_equal 404, response.status

    data = json_response(response)
    refute data[:ok]
    assert_includes data[:error], "not found"
  end

  def test_introspect_schemas_list
    response = async_request(@app, :get, "/introspect/schemas")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert data[:data][:count] >= 3

    user_create = data[:data][:schemas].find { |s| s[:name] == "UserCreateSchema" }
    assert user_create
    assert_includes user_create[:required_fields].map(&:to_s), "name"
    assert_includes user_create[:required_fields].map(&:to_s), "email"
  end

  def test_introspect_schemas_filter_by_field
    response = async_request(@app, :get, "/introspect/schemas?has_field=email")
    assert_equal 200, response.status

    data = json_response(response)
    data[:data][:schemas].each do |schema|
      all_fields = (schema[:required_fields] + schema[:optional_fields]).map(&:to_s)
      assert_includes all_fields, "email"
    end
  end

  def test_introspect_middleware_list
    response = async_request(@app, :get, "/introspect/middleware")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert data[:data][:count] >= 1

    cors = data[:data][:middleware].find { |m| m[:name].include?("Cors") }
    assert cors
    assert cors[:builtin]
  end

  def test_introspect_health
    response = async_request(@app, :get, "/introspect/health")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert data[:data][:score] > 0
    assert_includes %w[healthy degraded unhealthy], data[:data][:status]
    assert data[:data][:summary]
    assert data[:data][:summary][:routes_with_body_schema]
  end

  def test_introspect_health_detects_unused_dependency
    response = async_request(@app, :get, "/introspect/health")
    data = json_response(response)

    unused_issue = data[:data][:issues].find { |i| i[:type].to_s == "unused_dependency" }
    assert unused_issue
    assert_equal "cache", unused_issue[:name].to_s
  end

  def test_introspect_relationships
    response = async_request(@app, :get, "/introspect/relationships")
    assert_equal 200, response.status

    data = json_response(response)
    assert data[:ok]
    assert data[:data][:dependencies]

    db_rel = data[:data][:dependencies][:db]
    assert db_rel
    assert_equal 4, db_rel[:route_count]
  end

  def test_response_meta_included
    response = async_request(@app, :get, "/introspect")
    data = json_response(response)

    assert data[:meta]
    assert data[:meta][:generated_at]
    assert data[:meta][:introspection_version]
  end

  def test_introspection_disabled_in_production
    original_env = ENV["RACK_ENV"]
    ENV["RACK_ENV"] = "production"

    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, _task|
        [{ok: true}, 200]
      end
    end

    response = async_request(app, :get, "/introspect")
    assert_equal 404, response.status
  ensure
    ENV["RACK_ENV"] = original_env
  end

  def test_introspection_force_enabled_in_production
    original_env = ENV["RACK_ENV"]
    original_introspect = ENV["FUNAPI_INTROSPECTION"]
    ENV["RACK_ENV"] = "production"
    ENV["FUNAPI_INTROSPECTION"] = "enabled"

    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, _task|
        [{ok: true}, 200]
      end
    end

    response = async_request(app, :get, "/introspect")
    assert_equal 200, response.status
  ensure
    ENV["RACK_ENV"] = original_env
    ENV["FUNAPI_INTROSPECTION"] = original_introspect
  end

  def test_introspection_explicitly_enabled
    original_env = ENV["RACK_ENV"]
    ENV["RACK_ENV"] = "production"

    app = FunApi::App.new do |api|
      api.enable_introspection_endpoints

      api.get "/test" do |_input, _req, _task|
        [{ok: true}, 200]
      end
    end

    response = async_request(app, :get, "/introspect")
    assert_equal 200, response.status
  ensure
    ENV["RACK_ENV"] = original_env
  end

  def test_introspection_explicitly_disabled
    app = FunApi::App.new do |api|
      api.disable_introspection_endpoints

      api.get "/test" do |_input, _req, _task|
        [{ok: true}, 200]
      end
    end

    response = async_request(app, :get, "/introspect")
    assert_equal 404, response.status
  end
end
