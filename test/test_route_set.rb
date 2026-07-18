# frozen_string_literal: true

require "test_helper"

class TestRouteSet < Minitest::Test
  def setup
    @route_set = FunApi::RouteSet.new
  end

  def test_root_route_matches
    @route_set.add("GET", "/") { |_req, _params| [200, {}, ["root"]] }

    env = Rack::MockRequest.env_for("/")
    status, _headers, _body = @route_set.call(env)

    assert_equal 200, status
  end

  def test_exact_path_matches
    @route_set.add("GET", "/hello") { |_req, _params| [200, {}, ["hello"]] }

    env = Rack::MockRequest.env_for("/hello")
    status, _headers, _body = @route_set.call(env)

    assert_equal 200, status
  end

  def test_path_with_single_param
    @route_set.add("GET", "/users/:id") do |_req, params|
      [200, {}, [params["id"]]]
    end

    env = Rack::MockRequest.env_for("/users/42")
    status, _headers, body = @route_set.call(env)

    assert_equal 200, status
    assert_equal "42", body.first
  end

  def test_path_with_multiple_params
    @route_set.add("GET", "/users/:user_id/posts/:post_id") do |_req, params|
      [200, {}, ["#{params["user_id"]}-#{params["post_id"]}"]]
    end

    env = Rack::MockRequest.env_for("/users/123/posts/456")
    status, _headers, body = @route_set.call(env)

    assert_equal 200, status
    assert_equal "123-456", body.first
  end

  def test_no_match_returns_404
    @route_set.add("GET", "/hello") { |_req, _params| [200, {}, ["hello"]] }

    env = Rack::MockRequest.env_for("/goodbye")
    status, headers, body = @route_set.call(env)

    assert_equal 404, status
    assert_equal "application/json", headers["content-type"]
    assert_equal '{"detail":"Not Found"}', body.first
  end

  def test_different_verbs_same_path
    @route_set.add("GET", "/users") { |_req, _params| [200, {}, ["get"]] }
    @route_set.add("POST", "/users") { |_req, _params| [201, {}, ["post"]] }

    get_env = Rack::MockRequest.env_for("/users", method: "GET")
    get_status, _headers, get_body = @route_set.call(get_env)

    post_env = Rack::MockRequest.env_for("/users", method: "POST")
    post_status, _headers, post_body = @route_set.call(post_env)

    assert_equal 200, get_status
    assert_equal "get", get_body.first

    assert_equal 201, post_status
    assert_equal "post", post_body.first
  end

  def test_route_metadata_storage
    @route_set.add("GET", "/test", metadata: {custom: "value"}) { |_req, _params| [200, {}, []] }

    route = @route_set.routes.first
    assert_equal "GET", route.verb
    assert_equal "/test", route.metadata[:path_template]
    assert_equal "value", route.metadata[:custom]
  end

  def test_params_as_hash
    @route_set.add("GET", "/users/:id") do |_req, params|
      assert_instance_of Hash, params
      [200, {}, []]
    end

    env = Rack::MockRequest.env_for("/users/123")
    @route_set.call(env)
  end

  def test_path_with_special_characters_in_segment
    @route_set.add("GET", "/files/:filename") do |_req, params|
      [200, {}, [params["filename"]]]
    end

    env = Rack::MockRequest.env_for("/files/my-file.txt")
    status, _headers, body = @route_set.call(env)

    assert_equal 200, status
    assert_equal "my-file.txt", body.first
  end

  def test_first_matching_route_wins
    @route_set.add("GET", "/users/:id") { |_req, _params| [200, {}, ["first"]] }
    @route_set.add("GET", "/users/:user_id") { |_req, _params| [200, {}, ["second"]] }

    env = Rack::MockRequest.env_for("/users/123")
    _status, _headers, body = @route_set.call(env)

    assert_equal "first", body.first
  end

  def test_empty_path_params_for_paramless_route
    @route_set.add("GET", "/hello") do |_req, params|
      assert_empty params
      [200, {}, []]
    end

    env = Rack::MockRequest.env_for("/hello")
    @route_set.call(env)
  end

  def test_mount_dispatches_to_rack_app
    mounted = ->(env) { [200, {}, ["mounted #{env["PATH_INFO"]}"]] }
    @route_set.mount("/admin", mounted)

    env = Rack::MockRequest.env_for("/admin/users")
    status, _headers, body = @route_set.call(env)

    assert_equal 200, status
    assert_equal "mounted /users", body.first
  end

  def test_mount_sets_script_name_and_strips_path_info
    captured = nil
    mounted = lambda do |env|
      captured = {script_name: env["SCRIPT_NAME"], path_info: env["PATH_INFO"]}
      [200, {}, []]
    end
    @route_set.mount("/admin", mounted)

    @route_set.call(Rack::MockRequest.env_for("/admin/dashboard"))

    assert_equal "/admin", captured[:script_name]
    assert_equal "/dashboard", captured[:path_info]
  end

  def test_mount_root_of_prefix_yields_empty_path_info
    captured = nil
    mounted = lambda do |env|
      captured = env["PATH_INFO"]
      [200, {}, []]
    end
    @route_set.mount("/admin", mounted)

    @route_set.call(Rack::MockRequest.env_for("/admin"))

    assert_equal "", captured
  end

  def test_mount_longest_prefix_wins
    @route_set.mount("/api", ->(_env) { [200, {}, ["api"]] })
    @route_set.mount("/api/admin", ->(_env) { [200, {}, ["admin"]] })

    _status, _headers, body = @route_set.call(Rack::MockRequest.env_for("/api/admin/x"))

    assert_equal "admin", body.first
  end

  def test_routes_take_over_when_no_mount_matches
    @route_set.mount("/admin", ->(_env) { [200, {}, ["mounted"]] })
    @route_set.add("GET", "/hello") { |_req, _params| [200, {}, ["hello"]] }

    _status, _headers, body = @route_set.call(Rack::MockRequest.env_for("/hello"))

    assert_equal "hello", body.first
  end
end
