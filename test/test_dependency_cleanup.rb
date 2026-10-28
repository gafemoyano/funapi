# frozen_string_literal: true

require "test_helper"

class TestDependencyCleanup < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_block_provider_async_work_uses_each_resuming_task
    [false, true].each do |new_reactor|
      events = []
      expected_task = nil
      app = FunApi::App.new do |api|
        api.register(:resource) do |provide|
          assert_same expected_task, Async::Task.current
          assert_same expected_task, FunApi.current_task
          FunApi.async do |child|
            assert_same expected_task, child.parent
            sleep 0.001
            events << :acquired
          end.wait
          provide.call(:resource)
        ensure
          assert_same expected_task, Async::Task.current
          assert_same expected_task, FunApi.current_task
          assert FunApi.current_task.running?
          FunApi.async do |child|
            assert_same expected_task, child.parent
            sleep 0.001
            events << :cleaned
          end.wait
        end
      end
      resource = app.resolve(:resource)

      acquisition_task = Async do |task|
        expected_task = task
        assert_equal :resource, resource.call
        resource.cleanup unless new_reactor
      end
      acquisition_task.wait

      if new_reactor
        refute acquisition_task.running?
        assert_equal [:acquired], events
        Async do |task|
          refute_same acquisition_task, task
          expected_task = task
          resource.cleanup
        end.wait
      end

      resource.cleanup
      assert_equal [:acquired, :cleaned], events
    end
  end

  def test_partial_resolution_unwinds_before_preserving_http_error
    events = []
    original = FunApi::HTTPException.new(status_code: 401, detail: "original authentication failure")
    app = FunApi::App.new do |api|
      api.register(:first) { ["first", -> { events << :first }] }
      api.register(:second) do |provide|
        provide.call("second")
      ensure
        sleep 0
        events << :second
        raise "cleanup failure"
      end
      api.get "/test", depends: {
        first: :first,
        nested: FunApi.Depends(->(second:) { raise original }, second: :second)
      } do
        flunk "Handler must not run after failed resolution"
      end
    end

    _, warnings = capture_io do
      response = async_request(app, :get, "/test")
      assert_equal 401, response.status
      assert_equal original.detail, JSON.parse(response.body)["detail"]
    end
    assert_match "cleanup failure", warnings
    assert_equal [:second, :first], events
  end

  def test_nested_only_resources_and_shared_dependencies_unwind_once_per_request
    [false, true].each do |direct_first|
      events = []
      shared = FunApi.Depends(->(resource:) {
        events << :acquire_shared
        [resource, -> { events << :release_shared }]
      }, resource: :resource)
      outer = FunApi.Depends(->(shared:) {
        events << :acquire_outer
        [shared, -> { events << :release_outer }]
      }, shared: shared)
      app = FunApi::App.new do |api|
        api.register(:resource) do |provide|
          events << :acquire_resource
          provide.call(Object.new)
        ensure
          events << :release_resource
        end
        dependencies = {outer: outer, shared: shared, alias: shared}
        dependencies = {direct: :resource}.merge(dependencies) if direct_first
        api.get "/test", depends: dependencies do |_input, _req, _task, **resolved|
          assert_same resolved[:outer], resolved[:shared]
          assert_same resolved[:shared], resolved[:alias]
          assert_same resolved[:direct], resolved[:outer] if direct_first
          [{ok: true}, 200]
        end
      end

      2.times do
        response = async_request(app, :get, "/test")
        assert_equal 200, response.status
      end
      assert_equal [:acquire_resource, :acquire_shared, :acquire_outer,
        :release_outer, :release_shared, :release_resource] * 2, events
    end
  end

  def test_nested_then_direct_container_resource_is_shared
    acquisitions = 0
    cleanups = 0
    app = FunApi::App.new do |api|
      api.register(:resource) do
        acquisitions += 1
        [Object.new, -> { cleanups += 1 }]
      end
      api.get "/test", depends: {
        nested: FunApi.Depends(->(resource:) { resource }, resource: :resource),
        direct: :resource
      } do |_input, _req, _task, nested:, direct:|
        assert_same nested, direct
        raise FunApi::HTTPException.new(status_code: 403, detail: "handler failed")
      end
    end

    response = async_request(app, :get, "/test")
    assert_equal 403, response.status
    assert_equal 1, acquisitions
    assert_equal 1, cleanups
  end

  def test_cancellation_during_resolution_or_handler_unwinds_yielding_cleanups
    [:inline, :container, :handler].each do |cancel_at|
      events = []
      app = FunApi::App.new do |api|
        api.register(:resource) do |provide|
          events << :acquired
          provide.call("resource")
        ensure
          events << :cleanup_started
          sleep 0.001
          events << :cleanup_finished
        end
        blocker = -> {
          events << :blocked
          sleep 60
        }
        api.register(:blocker, &blocker)
        dependencies = {resource: :resource}
        dependencies[:blocker] = blocker if cancel_at == :inline
        dependencies[:blocker] = :blocker if cancel_at == :container
        api.get "/test", depends: dependencies do |*, **|
          blocker.call
          flunk "Cancelled request must not complete"
        end
      end

      Async do |task|
        request = task.async { Rack::MockRequest.new(app).get("/test") }
        assert_equal [:acquired, :blocked], events
        request.stop
        request.wait
        assert request.stopped?
      end.wait
      assert_equal [:acquired, :blocked, :cleanup_started, :cleanup_finished], events
    end
  end

  def test_stop_during_yielding_cleanup_finishes_unwinding
    events = []
    app = FunApi::App.new do |api|
      api.register(:first) { ["first", -> { events << :first }] }
      api.register(:second) do |provide|
        provide.call("second")
      ensure
        events << :cleanup_started
        sleep 0.01
        events << :cleanup_finished
      end
      api.get "/test", depends: [:first, :second] do |*, **|
        raise FunApi::HTTPException.new(status_code: 401, detail: "original")
      end
    end

    Async do |task|
      request = task.async { Rack::MockRequest.new(app).get("/test") }
      assert_equal [:cleanup_started], events
      request.stop
      request.wait
      assert request.stopped?
    end.wait
    assert_equal [:cleanup_started, :cleanup_finished, :first], events
  end

  def test_failing_inline_cleanups_do_not_replace_handler_exception
    [StandardError, Async::Stop].each do |error_class|
      events = []
      app = FunApi::App.new do |api|
        api.get "/test", depends: {
          first: -> { ["first", -> { events << :first }] },
          second: -> {
            ["second", -> {
              sleep 0
              events << :second
              raise error_class, "cleanup failure"
            }]
          }
        } do |*, **|
          raise FunApi::HTTPException.new(status_code: 409, detail: "original conflict")
        end
      end

      capture_io do
        response = async_request(app, :get, "/test")
        assert_equal 409, response.status
        assert_equal "original conflict", JSON.parse(response.body)["detail"]
      end
      assert_equal [:second, :first], events
    end
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

  def test_cleanup_called_on_unhandled_error
    cleanup_called = false

    app = FunApi::App.new do |api|
      api.register(:resource) do
        [
          "my_resource",
          -> { cleanup_called = true }
        ]
      end

      api.get "/test", depends: [:resource] do |_input, _req, _task, resource:|
        raise StandardError, "boom"
      end
    end

    res = async_request(app, :get, "/test")

    assert_equal 500, res.status
    assert_equal "Internal Server Error", JSON.parse(res.body)["detail"]
    assert cleanup_called, "Cleanup should be called even when handler raises an unhandled exception"
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
