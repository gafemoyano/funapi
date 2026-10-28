# frozen_string_literal: true

require "test_helper"
require "rack/urlmap"

class TestMount < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_mount_rack_app_bypasses_funapi_validation
    admin = lambda do |env|
      [200, {"content-type" => "text/plain"}, ["admin:#{env["PATH_INFO"]}"]]
    end

    app = FunApi::App.new do |api|
      api.mount("/admin", admin)
      api.get("/") { |_input, _req, _task| [{home: true}, 200] }
    end

    res = async_request(app, :get, "/admin/users")
    assert_equal 200, res.status
    assert_equal "admin:/users", res.body
  end

  def test_funapi_routes_still_served_alongside_mount
    app = FunApi::App.new do |api|
      api.mount("/admin", ->(_env) { [200, {}, ["admin"]] })
      api.get("/hello") { |_input, _req, _task| [{msg: "hi"}, 200] }
    end

    res = async_request(app, :get, "/hello")
    assert_equal({"msg" => "hi"}, JSON.parse(res.body))
  end

  def test_mounted_paths_excluded_from_openapi
    app = FunApi::App.new do |api|
      api.mount("/admin", ->(_env) { [200, {}, ["admin"]] })
      api.get("/hello") { |_input, _req, _task| [{msg: "hi"}, 200] }
    end

    spec = JSON.parse(async_request(app, :get, "/openapi.json").body)
    assert spec["paths"].key?("/hello")
    refute spec["paths"].keys.any? { |path| path.start_with?("/admin") }
  end

  def test_funapi_app_mounted_in_rack_urlmap
    api = FunApi::App.new do |a|
      a.get("/status") { |_input, _req, _task| [{ok: true}, 200] }
    end

    other = lambda do |_env|
      [200, {"content-type" => "text/plain"}, ["legacy home"]]
    end

    urlmap = Rack::URLMap.new(
      "/" => other,
      "/api" => api
    )

    api_res = async_request(urlmap, :get, "/api/status")
    assert_equal 200, api_res.status
    assert_equal({"ok" => true}, JSON.parse(api_res.body))

    home_res = async_request(urlmap, :get, "/")
    assert_equal "legacy home", home_res.body
  end

  def test_funapi_app_under_urlmap_serves_own_docs
    api = FunApi::App.new do |a|
      a.get("/status") { |_input, _req, _task| [{ok: true}, 200] }
    end
    urlmap = Rack::URLMap.new("/api" => api)

    assert_equal 200, async_request(urlmap, :get, "/api/openapi.json").status
  end
end
