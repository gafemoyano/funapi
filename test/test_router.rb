# frozen_string_literal: true

require "test_helper"

class TestRouter < Minitest::Test
  def setup
    @router = FunApi::Router.new
  end

  def test_root_route_matches
    @router.add("GET", "/") { |_req, _params| [200, {}, ["root"]] }

    env = Rack::MockRequest.env_for("/")
    status, _headers, _body = @router.call(env)

    assert_equal 200, status
  end

  def test_exact_path_matches
    @router.add("GET", "/hello") { |_req, _params| [200, {}, ["hello"]] }

    env = Rack::MockRequest.env_for("/hello")
    status, _headers, _body = @router.call(env)

    assert_equal 200, status
  end

  def test_path_with_single_param
    @router.add("GET", "/users/:id") do |_req, params|
      [200, {}, [params["id"]]]
    end

    env = Rack::MockRequest.env_for("/users/42")
    status, _headers, body = @router.call(env)

    assert_equal 200, status
    assert_equal "42", body.first
  end

  def test_path_with_multiple_params
    @router.add("GET", "/users/:user_id/posts/:post_id") do |_req, params|
      [200, {}, ["#{params["user_id"]}-#{params["post_id"]}"]]
    end

    env = Rack::MockRequest.env_for("/users/123/posts/456")
    status, _headers, body = @router.call(env)

    assert_equal 200, status
    assert_equal "123-456", body.first
  end

  def test_no_match_returns_404
    @router.add("GET", "/hello") { |_req, _params| [200, {}, ["hello"]] }

    env = Rack::MockRequest.env_for("/goodbye")
    status, headers, body = @router.call(env)

    assert_equal 404, status
    assert_equal "application/json", headers["content-type"]
    assert_equal '{"error":"Not found"}', body.first
  end

  def test_different_verbs_same_path
    @router.add("GET", "/users") { |_req, _params| [200, {}, ["get"]] }
    @router.add("POST", "/users") { |_req, _params| [201, {}, ["post"]] }

    get_env = Rack::MockRequest.env_for("/users", method: "GET")
    get_status, _headers, get_body = @router.call(get_env)

    post_env = Rack::MockRequest.env_for("/users", method: "POST")
    post_status, _headers, post_body = @router.call(post_env)

    assert_equal 200, get_status
    assert_equal "get", get_body.first

    assert_equal 201, post_status
    assert_equal "post", post_body.first
  end

  def test_route_metadata_storage
    @router.add("GET", "/test", metadata: {custom: "value"}) { |_req, _params| [200, {}, []] }

    route = @router.routes.first
    assert_equal "GET", route.verb
    assert_equal "/test", route.metadata[:path_template]
    assert_equal "value", route.metadata[:custom]
  end

  def test_params_as_hash
    @router.add("GET", "/users/:id") do |_req, params|
      assert_instance_of Hash, params
      [200, {}, []]
    end

    env = Rack::MockRequest.env_for("/users/123")
    @router.call(env)
  end

  def test_path_with_special_characters_in_segment
    @router.add("GET", "/files/:filename") do |_req, params|
      [200, {}, [params["filename"]]]
    end

    env = Rack::MockRequest.env_for("/files/my-file.txt")
    status, _headers, body = @router.call(env)

    assert_equal 200, status
    assert_equal "my-file.txt", body.first
  end

  def test_first_matching_route_wins
    @router.add("GET", "/users/:id") { |_req, _params| [200, {}, ["first"]] }
    @router.add("GET", "/users/:user_id") { |_req, _params| [200, {}, ["second"]] }

    env = Rack::MockRequest.env_for("/users/123")
    _status, _headers, body = @router.call(env)

    assert_equal "first", body.first
  end

  def test_empty_path_params_for_paramless_route
    @router.add("GET", "/hello") do |_req, params|
      assert_empty params
      [200, {}, []]
    end

    env = Rack::MockRequest.env_for("/hello")
    @router.call(env)
  end
end
