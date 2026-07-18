# frozen_string_literal: true

require "test_helper"
require "funapi/test_client"

class TestDevErrorPages < Minitest::Test
  def build_app
    FunApi::App.new do |api|
      api.get "/boom" do |_input, _req|
        raise "kaboom"
      end
    end
  end

  def with_env(value)
    previous = ENV["FUNAPI_ENV"]
    ENV["FUNAPI_ENV"] = value
    yield
  ensure
    ENV["FUNAPI_ENV"] = previous
  end

  def test_json_traceback_when_accept_is_json
    with_env("development") do
      client = FunApi::TestClient.new(build_app)
      res = client.get("/boom", headers: {"Accept" => "application/json"})

      assert_equal 500, res.status
      assert_equal "application/json", res.content_type
      assert_equal "RuntimeError", res.json[:detail][:error]
      assert_equal "kaboom", res.json[:detail][:message]
      assert res.json[:detail][:backtrace].is_a?(Array)
    end
  end

  def test_html_traceback_when_browser_prefers_html
    with_env("development") do
      client = FunApi::TestClient.new(build_app)
      res = client.get("/boom", headers: {"Accept" => "text/html,application/xhtml+xml"})

      assert_equal 500, res.status
      assert_includes res.content_type, "text/html"
      assert_includes res.body, "RuntimeError"
      assert_includes res.body, "kaboom"
      assert_includes res.body, "Backtrace"
    end
  end

  def test_production_hides_details
    with_env("production") do
      client = FunApi::TestClient.new(build_app)
      res = client.get("/boom", headers: {"Accept" => "text/html"})

      assert_equal 500, res.status
      assert_equal "Internal Server Error", res.json[:detail]
    end
  end
end
