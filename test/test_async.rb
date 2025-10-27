# frozen_string_literal: true

require "test_helper"

class TestAsync < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_concurrent_tasks
    app = FunApi::App.new do |api|
      api.get "/concurrent" do |_input, _req, task|
        task1 = task.async do
          sleep 0.01
          {result: "task1"}
        end

        task2 = task.async do
          sleep 0.01
          {result: "task2"}
        end

        results = [task1.wait, task2.wait]
        [{results: results}, 200]
      end
    end

    res = async_request(app, :get, "/concurrent")
    data = parse(res)

    assert_equal 2, data[:results].length
    assert_equal "task1", data[:results][0][:result]
    assert_equal "task2", data[:results][1][:result]
  end

  def test_task_wait_returns_value
    app = FunApi::App.new do |api|
      api.get "/wait" do |_input, _req, task|
        result = task.async { 42 }.wait
        [{value: result}, 200]
      end
    end

    res = async_request(app, :get, "/wait")
    data = parse(res)

    assert_equal 42, data[:value]
  end

  def test_nested_async_tasks
    app = FunApi::App.new do |api|
      api.get "/nested" do |_input, _req, task|
        outer = task.async do
          inner = task.async { "inner value" }
          {outer: "outer value", inner: inner.wait}
        end

        result = outer.wait
        [result, 200]
      end
    end

    res = async_request(app, :get, "/nested")
    data = parse(res)

    assert_equal "outer value", data[:outer]
    assert_equal "inner value", data[:inner]
  end

  def test_multiple_concurrent_requests
    app = FunApi::App.new do |api|
      api.get "/hello/:id" do |input, _req, _task|
        id = input[:path]["id"]
        [{id: id, message: "hello"}, 200]
      end
    end

    results = Async do |task|
      tasks = 3.times.map do |i|
        task.async { async_request(app, :get, "/hello/#{i}") }
      end

      tasks.map(&:wait)
    end.wait

    assert_equal 3, results.length
    results.each { |res| assert_equal 200, res.status }
  end

  def test_task_with_dependencies
    app = FunApi::App.new do |api|
      api.get "/deps" do |_input, _req, task|
        user_task = task.async do
          sleep 0.01
          {id: 1, name: "Alice"}
        end

        user = user_task.wait

        posts_task = task.async do
          sleep 0.01
          [{id: 1, user_id: user[:id], title: "Post 1"}]
        end

        [{user: user, posts: posts_task.wait}, 200]
      end
    end

    res = async_request(app, :get, "/deps")
    data = parse(res)

    assert_equal "Alice", data[:user][:name]
    assert_equal 1, data[:posts].length
    assert_equal 1, data[:posts][0][:user_id]
  end

  def test_async_with_middleware
    call_order = []

    middleware = Class.new do
      define_method(:initialize) do |app|
        @app = app
        @call_order = call_order
      end

      define_method(:call) do |env|
        @call_order << :before
        result = @app.call(env)
        @call_order << :after
        result
      end
    end

    app = FunApi::App.new do |api|
      api.use middleware

      api.get "/test" do |_input, _req, task|
        call_order << :handler_start
        task.async { call_order << :async_task }.wait
        call_order << :handler_end
        [{ok: true}, 200]
      end
    end

    async_request(app, :get, "/test")

    assert_equal %i[before handler_start async_task handler_end after], call_order
  end

  def test_async_error_handling
    app = FunApi::App.new do |api|
      api.get "/error" do |_input, _req, task|
        result = nil
        begin
          task.async { raise StandardError, "Async error" }.wait
          result = [{ok: true}, 200]
        rescue => e
          result = [{error: e.message}, 500]
        end

        result
      end
    end

    res = async_request(app, :get, "/error")
    data = parse(res)

    assert_equal 500, res.status
    assert_equal "Async error", data[:error]
  end

  def test_async_timeout
    app = FunApi::App.new do |api|
      api.get "/timeout" do |_input, _req, task|
        result = nil
        begin
          task.with_timeout(0.01) do
            sleep 1
          end
          result = [{ok: true}, 200]
        rescue Async::TimeoutError
          result = [{error: "timeout"}, 408]
        end

        result
      end
    end

    res = async_request(app, :get, "/timeout")
    data = parse(res)

    assert_equal 408, res.status
    assert_equal "timeout", data[:error]
  end

  def test_task_available_in_handler
    app = FunApi::App.new do |api|
      api.get "/test" do |_input, _req, task|
        assert_instance_of Async::Task, task
        [{ok: true}, 200]
      end
    end

    async_request(app, :get, "/test")
  end

  def test_parallel_data_fetching
    app = FunApi::App.new do |api|
      api.get "/dashboard/:id" do |input, _req, task|
        user_id = input[:path]["id"]

        user_task = task.async do
          sleep 0.01
          {id: user_id, name: "User"}
        end

        posts_task = task.async do
          sleep 0.01
          [{title: "Post 1"}, {title: "Post 2"}]
        end

        stats_task = task.async do
          sleep 0.01
          {views: 100, likes: 50}
        end

        [
          {
            user: user_task.wait,
            posts: posts_task.wait,
            stats: stats_task.wait
          },
          200
        ]
      end
    end

    start_time = Time.now
    res = async_request(app, :get, "/dashboard/123")
    duration = Time.now - start_time

    data = parse(res)
    assert_equal "User", data[:user][:name]
    assert_equal 2, data[:posts].length
    assert_equal 100, data[:stats][:views]

    assert duration < 0.05, "Expected parallel execution to be fast, took #{duration}s"
  end
end
