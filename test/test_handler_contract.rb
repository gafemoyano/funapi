# frozen_string_literal: true

require "test_helper"

class TestHandlerContract < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def parse(response)
    JSON.parse(response.body, symbolize_names: true)
  end

  def test_two_arg_handler_works
    app = FunApi::App.new do |api|
      api.get "/two" do |input, req|
        [{path: req.path_info, has_input: !input.nil?}, 200]
      end
    end

    res = async_request(app, :get, "/two")
    assert_equal 200, res.status
    data = parse(res)
    assert_equal "/two", data[:path]
    assert_equal true, data[:has_input]
  end

  def test_three_arg_handler_still_works
    app = FunApi::App.new do |api|
      api.get "/three" do |_input, _req, task|
        [{same: task.equal?(Async::Task.current)}, 200]
      end
    end

    res = async_request(app, :get, "/three")
    assert_equal true, parse(res)[:same]
  end

  def test_funapi_async_runs_concurrently
    app = FunApi::App.new do |api|
      api.get "/dashboard" do |_input, _req|
        user = FunApi.async do
          FunApi.sleep(0.01)
          {name: "Alice"}
        end

        posts = FunApi.async do
          FunApi.sleep(0.01)
          [{title: "Post"}]
        end

        [{user: user.wait, posts: posts.wait}, 200]
      end
    end

    res = async_request(app, :get, "/dashboard")
    data = parse(res)
    assert_equal "Alice", data[:user][:name]
    assert_equal 1, data[:posts].length
  end

  def test_funapi_async_is_parallel
    app = FunApi::App.new do |api|
      api.get "/parallel" do |_input, _req|
        tasks = 3.times.map do
          FunApi.async do
            FunApi.sleep(0.05)
            :done
          end
        end
        [{results: tasks.map(&:wait)}, 200]
      end
    end

    start = Async::Clock.now
    res = async_request(app, :get, "/parallel")
    duration = Async::Clock.now - start

    assert_equal 200, res.status
    assert_equal 3, parse(res)[:results].length
    assert duration < 0.12, "expected parallel execution, took #{duration}s"
  end
end
