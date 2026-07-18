# frozen_string_literal: true

require "test_helper"

class TestExceptions < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_http_exception_404
    app = FunApi::App.new do |api|
      api.get "/missing" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 404, detail: "Resource not found")
      end
    end

    res = async_request(app, :get, "/missing")
    data = parse(res)

    assert_equal 404, res.status
    assert_equal "Resource not found", data[:detail]
  end

  def test_http_exception_400
    app = FunApi::App.new do |api|
      api.get "/bad" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 400, detail: "Bad request")
      end
    end

    res = async_request(app, :get, "/bad")
    data = parse(res)

    assert_equal 400, res.status
    assert_equal "Bad request", data[:detail]
  end

  def test_http_exception_500
    app = FunApi::App.new do |api|
      api.get "/error" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 500, detail: "Internal server error")
      end
    end

    res = async_request(app, :get, "/error")
    data = parse(res)

    assert_equal 500, res.status
    assert_equal "Internal server error", data[:detail]
  end

  def test_http_exception_with_default_detail
    app = FunApi::App.new do |api|
      api.get "/not-found" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 404)
      end
    end

    res = async_request(app, :get, "/not-found")
    data = parse(res)

    assert_equal 404, res.status
    assert_equal "Not Found", data[:detail]
  end

  def test_http_exception_with_custom_headers
    app = FunApi::App.new do |api|
      api.get "/custom" do |_input, _req, _task|
        raise FunApi::HTTPException.new(
          status_code: 429,
          detail: "Too many requests",
          headers: {"Retry-After" => "60"}
        )
      end
    end

    res = async_request(app, :get, "/custom")
    data = parse(res)

    assert_equal 429, res.status
    assert_equal "Too many requests", data[:detail]
    assert_equal "60", res.headers["Retry-After"]
  end

  def test_http_exception_401
    app = FunApi::App.new do |api|
      api.get "/protected" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 401)
      end
    end

    res = async_request(app, :get, "/protected")
    data = parse(res)

    assert_equal 401, res.status
    assert_equal "Unauthorized", data[:detail]
  end

  def test_http_exception_403
    app = FunApi::App.new do |api|
      api.get "/forbidden" do |_input, _req, _task|
        raise FunApi::HTTPException.new(status_code: 403)
      end
    end

    res = async_request(app, :get, "/forbidden")
    data = parse(res)

    assert_equal 403, res.status
    assert_equal "Forbidden", data[:detail]
  end

  def test_validation_error_is_http_exception
    error = FunApi::ValidationError.new(errors: double("errors"))

    assert_kind_of FunApi::HTTPException, error
    assert_equal 422, error.status_code
  end

  def test_http_exception_response_format
    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, _task|
        raise FunApi::HTTPException.new(
          status_code: 418,
          detail: "I'm a teapot"
        )
      end
    end

    res = async_request(app, :get, "/test")

    assert_equal 418, res.status
    assert_equal "application/json", res.headers["content-type"]
    data = parse(res)
    assert data.key?(:detail)
  end

  def test_http_exception_with_complex_detail
    app = FunApi::App.new do |api|
      api.get "/complex" do |_input, _req, _task|
        raise FunApi::HTTPException.new(
          status_code: 400,
          detail: {
            error: "validation_failed",
            fields: %w[name email]
          }
        )
      end
    end

    res = async_request(app, :get, "/complex")
    data = parse(res)

    assert_equal 400, res.status
    assert_equal "validation_failed", data[:detail][:error]
    assert_equal %w[name email], data[:detail][:fields]
  end

  def test_registered_exception_handler
    my_error = Class.new(StandardError)

    app = FunApi::App.new do |api|
      api.exception_handler(my_error) do |error, _req|
        [{error: "handled", message: error.message}, 422]
      end

      api.get "/boom" do |_input, _req, _task|
        raise my_error, "something broke"
      end
    end

    res = async_request(app, :get, "/boom")
    data = parse(res)

    assert_equal 422, res.status
    assert_equal "handled", data[:error]
    assert_equal "something broke", data[:message]
  end

  def test_registered_exception_handler_matches_subclasses
    base_error = Class.new(StandardError)
    child_error = Class.new(base_error)

    app = FunApi::App.new do |api|
      api.exception_handler(base_error) do |_error, _req|
        [{handled: true}, 400]
      end

      api.get "/child" do |_input, _req, _task|
        raise child_error, "child raised"
      end
    end

    res = async_request(app, :get, "/child")

    assert_equal 400, res.status
    assert_equal true, parse(res)[:handled]
  end

  def test_unhandled_error_becomes_clean_500
    app = FunApi::App.new do |api|
      api.get "/crash" do |_input, _req, _task|
        raise "kaboom"
      end
    end

    res = async_request(app, :get, "/crash")
    data = parse(res)

    assert_equal 500, res.status
    assert_equal "Internal Server Error", data[:detail]
  end

  def test_unhandled_error_includes_detail_in_development
    app = FunApi::App.new do |api|
      api.get "/crash" do |_input, _req, _task|
        raise "kaboom in dev"
      end
    end

    original = ENV["FUNAPI_ENV"]
    ENV["FUNAPI_ENV"] = "development"
    begin
      res = async_request(app, :get, "/crash")
      data = parse(res)

      assert_equal 500, res.status
      assert_equal "RuntimeError", data[:detail][:error]
      assert_equal "kaboom in dev", data[:detail][:message]
      assert data[:detail][:backtrace].is_a?(Array)
    ensure
      ENV["FUNAPI_ENV"] = original
    end
  end

  private

  def double(_name)
    Class.new do
      define_method(:messages) { [] }
    end.new
  end
end
