# frozen_string_literal: true

require "test_helper"

class TestDependencyCleanup < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_cleanup_called_on_success
    cleanup_called = false
    resource_value = nil

    app = FunApi::App.new do |api|
      api.register(:resource) do
        resource = "my_resource"
        cleanup = lambda {
          cleanup_called = true
          resource_value = resource
        }
        [resource, cleanup]
      end

      api.get "/test",
        depends: [:resource] do |_input, _req, _task, resource:|
        [{value: resource}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status

    assert cleanup_called, "Cleanup should have been called"
    assert_equal "my_resource", resource_value
  end

  def test_cleanup_called_on_error
    cleanup_called = false

    app = FunApi::App.new do |api|
      api.register(:resource) do
        [
          "my_resource",
          -> { cleanup_called = true }
        ]
      end

      api.get "/test",
        depends: [:resource] do |_input, _req, _task, resource:|
        raise FunApi::HTTPException.new(status_code: 500, detail: "Error")
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 500, res.status

    assert cleanup_called, "Cleanup should be called even when handler raises exception"
  end

  def test_no_cleanup_on_validation_error_before_dependency_resolution
    cleanup_called = false

    schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.register(:resource) do
        [
          "my_resource",
          -> { cleanup_called = true }
        ]
      end

      api.post "/test",
        body: schema,
        depends: [:resource] do |_input, _req, _task, resource:|
        [{value: resource}, 200]
      end
    end

    res = async_request(app, :post, "/test",
      "CONTENT_TYPE" => "application/json",
      :input => "{}")
    assert_equal 422, res.status

    refute cleanup_called, "Cleanup should NOT be called if validation fails before dependencies are resolved"
  end

  def test_multiple_cleanups_all_called
    cleanup1_called = false
    cleanup2_called = false
    cleanup3_called = false

    app = FunApi::App.new do |api|
      api.register(:res1) { ["resource1", -> { cleanup1_called = true }] }
      api.register(:res2) { ["resource2", -> { cleanup2_called = true }] }

      api.get "/test",
        depends: {
          res1: nil,
          res2: nil,
          res3: -> { ["resource3", -> { cleanup3_called = true }] }
        } do |_input, _req, _task, res1:, res2:, res3:|
        [{values: [res1, res2, res3]}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status

    assert cleanup1_called, "Cleanup 1 should be called"
    assert cleanup2_called, "Cleanup 2 should be called"
    assert cleanup3_called, "Cleanup 3 should be called"
  end

  def test_cleanup_failure_does_not_break_request
    cleanup_error_logged = false

    app = FunApi::App.new do |api|
      api.register(:resource) do
        [
          "my_resource",
          lambda {
            cleanup_error_logged = true
            raise StandardError, "Cleanup failed"
          }
        ]
      end

      api.get "/test",
        depends: [:resource] do |_input, _req, _task, resource:|
        [{value: resource}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "my_resource", data[:value]

    assert cleanup_error_logged, "Cleanup should have been attempted"
  end

  def test_database_like_cleanup_pattern
    connections = []
    closed_connections = []

    fake_db = Class.new do
      def self.connect
        connection = {id: rand(1000), open: true}
        new(connection)
      end

      def initialize(connection)
        @connection = connection
      end

      def query(sql)
        raise "Connection closed" unless @connection[:open]

        "Results for: #{sql}"
      end

      def close
        @connection[:open] = false
        @connection
      end

      attr_reader :connection
    end

    app = FunApi::App.new do |api|
      api.register(:db) do
        conn = fake_db.connect
        connections << conn.connection
        cleanup = lambda {
          closed = conn.close
          closed_connections << closed
        }
        [conn, cleanup]
      end

      api.get "/query",
        depends: [:db] do |_input, _req, _task, db:|
        result = db.query("SELECT * FROM users")
        [{result: result}, 200]
      end
    end

    res = async_request(app, :get, "/query")
    assert_equal 200, res.status

    assert_equal 1, connections.length, "Should have opened 1 connection"
    assert_equal 1, closed_connections.length, "Should have closed 1 connection"
    assert connections.first[:open] == false, "Connection should be closed"
  end

  def test_nested_dependency_cleanups
    outer_cleanup_called = false
    inner_cleanup_called = false

    app = FunApi::App.new do |api|
      api.register(:inner) do |provide|
        provide.call("inner_resource")
      ensure
        inner_cleanup_called = true
      end

      api.get "/test",
        depends: {
          inner: :inner,
          outer: FunApi::Depends(
            lambda { |inner:|
              [
                "outer_#{inner}",
                -> { outer_cleanup_called = true }
              ]
            },
            inner: :inner
          )
        } do |_input, _req, _task, inner:, outer:|
        [{value: outer, inner: inner}, 200]
      end
    end

    res = async_request(app, :get, "/test")
    assert_equal 200, res.status
    data = JSON.parse(res.body, symbolize_names: true)
    assert_equal "outer_inner_resource", data[:value]

    assert inner_cleanup_called, "Inner cleanup should be called (resolved at route level)"
    assert outer_cleanup_called, "Outer cleanup should be called"
  end
end
