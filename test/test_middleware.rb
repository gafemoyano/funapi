# frozen_string_literal: true

require "test_helper"

class TestMiddleware < Minitest::Test
  class TestMiddleware1
    def initialize(app)
      @app = app
    end

    def call(env)
      env["test.order"] ||= []
      env["test.order"] << "1-before"
      status, headers, body = @app.call(env)
      env["test.order"] << "1-after"
      headers["X-Test-1"] = "true"
      [status, headers, body]
    end
  end

  class TestMiddleware2
    def initialize(app)
      @app = app
    end

    def call(env)
      env["test.order"] ||= []
      env["test.order"] << "2-before"
      status, headers, body = @app.call(env)
      env["test.order"] << "2-after"
      headers["X-Test-2"] = "true"
      [status, headers, body]
    end
  end

  class OptionsMiddleware
    def initialize(app, **options)
      @app = app
      @prefix = options[:prefix] || "default"
    end

    def call(env)
      status, headers, body = @app.call(env)
      headers["X-Prefix"] = @prefix
      [status, headers, body]
    end
  end

  def app_with_middleware(&block)
    FunApi::App.new do |api|
      block&.call(api)
      api.get "/test" do |_input, _req, _task|
        [{message: "test"}, 200]
      end
    end
  end

  def async_request(app, method, path)
    Async do
      Rack::MockRequest.new(app).send(method, path)
    end.wait
  end

  def test_middleware_chain_executes
    app = app_with_middleware do |api|
      api.use TestMiddleware1
    end

    res = async_request(app, :get, "/test")

    assert_equal "200", res.status.to_s
    assert_equal "true", res.headers["X-Test-1"]
  end

  def test_middleware_execution_order_fifo
    app = app_with_middleware do |api|
      api.use TestMiddleware1
      api.use TestMiddleware2
    end

    env = Rack::MockRequest.env_for("/test")
    env["test.order"] = []

    Async do
      app.call(env)
    end.wait

    assert_equal %w[1-before 2-before 2-after 1-after], env["test.order"]
  end

  def test_multiple_middleware_headers
    app = app_with_middleware do |api|
      api.use TestMiddleware1
      api.use TestMiddleware2
    end

    res = async_request(app, :get, "/test")

    assert_equal "true", res.headers["X-Test-1"]
    assert_equal "true", res.headers["X-Test-2"]
  end

  def test_middleware_with_keyword_arguments
    app = app_with_middleware do |api|
      api.use OptionsMiddleware, prefix: "custom"
    end

    res = async_request(app, :get, "/test")

    assert_equal "custom", res.headers["X-Prefix"]
  end

  def test_middleware_chain_with_no_middleware
    app = app_with_middleware

    res = async_request(app, :get, "/test")

    assert_equal "200", res.status.to_s
  end

  def test_trusted_host_middleware_allows_valid_host
    app = app_with_middleware do |api|
      api.add_trusted_host(allowed_hosts: ["example.org"])
    end

    env = Rack::MockRequest.env_for("/test", "HTTP_HOST" => "example.org")
    status, _headers, _body = Async { app.call(env) }.wait

    assert_equal 200, status
  end

  def test_trusted_host_middleware_blocks_invalid_host
    app = app_with_middleware do |api|
      api.add_trusted_host(allowed_hosts: ["example.com"])
    end

    env = Rack::MockRequest.env_for("/test", "HTTP_HOST" => "evil.com")
    status, _headers, _body = Async { app.call(env) }.wait

    assert_equal 400, status
  end

  def test_trusted_host_middleware_allows_all_when_empty
    app = app_with_middleware do |api|
      api.add_trusted_host(allowed_hosts: [])
    end

    res = async_request(app, :get, "/test")

    assert_equal "200", res.status.to_s
  end

  def test_trusted_host_middleware_with_regex
    app = app_with_middleware do |api|
      api.add_trusted_host(allowed_hosts: [/\.example\.com$/])
    end

    env = Rack::MockRequest.env_for("/test", "HTTP_HOST" => "api.example.com")
    status, _headers, _body = Async { app.call(env) }.wait

    assert_equal 200, status
  end

  def test_cors_middleware_adds_headers
    app = app_with_middleware do |api|
      api.add_cors(
        allow_origins: ["http://example.com"],
        allow_methods: %w[GET POST]
      )
    end

    env = Rack::MockRequest.env_for("/test", "HTTP_ORIGIN" => "http://example.com")
    _status, headers, _body = Async { app.call(env) }.wait

    assert_equal "http://example.com", headers["access-control-allow-origin"]
  end

  def test_request_logger_middleware
    logger_output = StringIO.new
    logger = Logger.new(logger_output)

    app = app_with_middleware do |api|
      api.add_request_logger(logger: logger, level: :info)
    end

    async_request(app, :get, "/test")

    log_content = logger_output.string
    assert_match(/GET/, log_content)
    assert_match(%r{/test}, log_content)
    assert_match(/200/, log_content)
    assert_match(/ms/, log_content)
  end

  def test_middleware_stack_returns_self
    app = FunApi::App.new

    result = app.use(TestMiddleware1)

    assert_same app, result
  end
end
