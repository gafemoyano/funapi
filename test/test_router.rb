# frozen_string_literal: true

require "test_helper"

class TestRouter < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def openapi_spec(app)
    res = async_request(app, :get, "/openapi.json")
    JSON.parse(res.body)
  end

  def test_router_collects_route_definitions
    router = FunApi::Router.new(prefix: "/users") do |r|
      r.get("/:id") { |input, _req, _task| [{id: input[:path][:id]}, 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router) }
    res = async_request(app, :get, "/users/42")

    assert_equal 200, res.status
    assert_equal({"id" => "42"}, JSON.parse(res.body))
  end

  def test_prefix_applied_from_router
    router = FunApi::Router.new(prefix: "/api/v1") do |r|
      r.get("/ping") { |_input, _req, _task| [{ok: true}, 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router) }

    assert_equal 200, async_request(app, :get, "/api/v1/ping").status
    assert_equal 404, async_request(app, :get, "/ping").status
  end

  def test_include_router_can_add_extra_prefix
    router = FunApi::Router.new(prefix: "/users") do |r|
      r.get("/") { |_input, _req, _task| [{ok: true}, 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router, prefix: "/api") }

    assert_equal 200, async_request(app, :get, "/api/users").status
  end

  def test_root_route_inside_router
    router = FunApi::Router.new(prefix: "/health") do |r|
      r.get("/") { |_input, _req, _task| [{status: "up"}, 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router) }

    assert_equal 200, async_request(app, :get, "/health").status
  end

  def test_shared_depends_injected_into_routes
    router = FunApi::Router.new(prefix: "/users", depends: {db: :db}) do |r|
      r.get("/") { |_input, _req, _task, db:| [{name: db}, 200] }
    end

    app = FunApi::App.new do |api|
      api.register(:db) { "shared-db" }
      api.include_router(router)
    end

    res = async_request(app, :get, "/users")
    assert_equal({"name" => "shared-db"}, JSON.parse(res.body))
  end

  def test_route_level_depends_wins_over_shared
    router = FunApi::Router.new(prefix: "/users", depends: {store: :shared_store}) do |r|
      r.get("/shared") { |_input, _req, _task, store:| [{store: store}, 200] }
      r.get("/own", depends: {store: :own_store}) { |_input, _req, _task, store:| [{store: store}, 200] }
    end

    app = FunApi::App.new do |api|
      api.register(:shared_store) { "shared" }
      api.register(:own_store) { "own" }
      api.include_router(router)
    end

    assert_equal({"store" => "shared"}, JSON.parse(async_request(app, :get, "/users/shared").body))
    assert_equal({"store" => "own"}, JSON.parse(async_request(app, :get, "/users/own").body))
  end

  def test_nested_router_composition_composes_prefix_and_depends
    inner = FunApi::Router.new(prefix: "/posts", depends: {db: :db}) do |r|
      r.get("/:id") { |input, _req, _task, db:| [{id: input[:path][:id], db: db}, 200] }
    end

    outer = FunApi::Router.new(prefix: "/api") do |r|
      r.include_router(inner)
    end

    app = FunApi::App.new do |api|
      api.register(:db) { "db-conn" }
      api.include_router(outer)
    end

    res = async_request(app, :get, "/api/posts/7")
    assert_equal({"id" => "7", "db" => "db-conn"}, JSON.parse(res.body))
  end

  def test_tags_flow_into_openapi
    router = FunApi::Router.new(prefix: "/users", tags: ["users"]) do |r|
      r.get("/") { |_input, _req, _task| [[], 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router) }
    spec = openapi_spec(app)

    assert_equal ["users"], spec["paths"]["/users"]["get"]["tags"]
  end

  def test_route_tags_merge_with_router_tags
    router = FunApi::Router.new(prefix: "/users", tags: ["users"]) do |r|
      r.get("/admin", tags: ["admin"]) { |_input, _req, _task| [[], 200] }
    end

    app = FunApi::App.new { |api| api.include_router(router) }
    spec = openapi_spec(app)

    assert_equal ["users", "admin"], spec["paths"]["/users/admin"]["get"]["tags"]
  end

  def test_openapi_aggregates_routes_from_multiple_routers
    users = FunApi::Router.new(prefix: "/users", tags: ["users"]) do |r|
      r.get("/") { |_input, _req, _task| [[], 200] }
    end
    posts = FunApi::Router.new(prefix: "/posts", tags: ["posts"]) do |r|
      r.get("/") { |_input, _req, _task| [[], 200] }
    end

    app = FunApi::App.new do |api|
      api.include_router(users)
      api.include_router(posts)
    end

    spec = openapi_spec(app)
    assert spec["paths"].key?("/users")
    assert spec["paths"].key?("/posts")
    assert_equal ["users"], spec["paths"]["/users"]["get"]["tags"]
    assert_equal ["posts"], spec["paths"]["/posts"]["get"]["tags"]
  end

  def test_docs_and_openapi_registered_once_with_routers
    router = FunApi::Router.new(prefix: "/users") do |r|
      r.get("/") { |_input, _req, _task| [[], 200] }
    end
    app = FunApi::App.new { |api| api.include_router(router) }

    assert_equal 200, async_request(app, :get, "/docs").status
    assert_equal 200, async_request(app, :get, "/openapi.json").status
  end

  def test_single_app_routes_still_work
    app = FunApi::App.new do |api|
      api.get("/legacy") { |_input, _req, _task| [{legacy: true}, 200] }
    end

    assert_equal({"legacy" => true}, JSON.parse(async_request(app, :get, "/legacy").body))
  end

  def test_coerce_depends_from_array
    assert_equal({db: :db, cache: :cache}, FunApi::Router.coerce_depends([:db, :cache]))
  end
end
