# frozen_string_literal: true

require_relative 'test_helper'

class TestBackgroundTasks < Minitest::Test
  def async_request(app, method, path, **options)
    Async do
      Rack::MockRequest.new(app).send(method, path, **options)
    end.wait
  end

  def test_background_tasks_execute_after_handler
    execution_order = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        execution_order << :handler
        background.add_task(-> { execution_order << :background })
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal %i[handler background], execution_order
    assert_equal 200, res.status
  end

  def test_multiple_background_tasks_execute_in_order
    execution_order = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        execution_order << :handler
        background.add_task(-> { execution_order << :task1 })
        background.add_task(-> { execution_order << :task2 })
        background.add_task(-> { execution_order << :task3 })
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal %i[handler task1 task2 task3], execution_order
    assert_equal 200, res.status
  end

  def test_background_tasks_with_arguments
    results = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        background.add_task(->(a, b) { results << a + b }, 5, 3)
        background.add_task(->(x) { results << x * 2 }, 10)
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal [8, 20], results
    assert_equal 200, res.status
  end

  def test_background_tasks_with_keyword_arguments
    results = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        background.add_task(->(name:, age:) { results << "#{name}-#{age}" }, name: 'Alice', age: 30)
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal ['Alice-30'], results
    assert_equal 200, res.status
  end

  def test_background_tasks_with_mixed_arguments
    results = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        background.add_task(
          ->(prefix, suffix:) { results << "#{prefix}-#{suffix}" },
          'hello',
          suffix: 'world'
        )
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal ['hello-world'], results
    assert_equal 200, res.status
  end

  def test_background_tasks_can_access_dependencies
    connection_state = []

    app = FunApi::App.new do |api|
      api.register(:db) do |provide|
        connection_state << :connected
        provide.call(:fake_db)
      ensure
        connection_state << :closed
      end

      api.post '/test', depends: [:db] do |_input, _req, _task, db:, background:|
        connection_state << :handler
        background.add_task(lambda {
          connection_state << :background_start
          connection_state << db
          connection_state << :background_end
        })
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    expected = %i[
      connected
      handler
      background_start
      fake_db
      background_end
      closed
    ]
    assert_equal expected, connection_state
    assert_equal 200, res.status
  end

  def test_background_task_errors_are_handled
    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        background.add_task(-> { raise StandardError, 'Task failed!' })
        [{ ok: true }, 200]
      end
    end

    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      res = async_request(app, :post, '/test')
      warning_output = $stderr.string

      assert_equal 200, res.status
      assert_match(/Background task failed/, warning_output)
      assert_match(/Task failed!/, warning_output)
    ensure
      $stderr = original_stderr
    end
  end

  def test_background_task_error_does_not_prevent_other_tasks
    results = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        background.add_task(-> { results << :task1 })
        background.add_task(-> { raise 'Error!' })
        background.add_task(-> { results << :task3 })
        [{ ok: true }, 200]
      end
    end

    original_stderr = $stderr
    $stderr = StringIO.new

    begin
      res = async_request(app, :post, '/test')
      assert_equal 200, res.status
      assert_equal %i[task1 task3], results
    ensure
      $stderr = original_stderr
    end
  end

  def test_background_tasks_work_without_dependencies
    executed = false

    app = FunApi::App.new do |api|
      api.get '/test' do |_input, _req, _task, background:|
        background.add_task(-> { executed = true })
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :get, '/test')

    assert executed
    assert_equal 200, res.status
  end

  def test_background_tasks_with_proc_object
    results = []

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        my_proc = proc { |msg| results << msg }
        background.add_task(my_proc, 'Hello from background')
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal ['Hello from background'], results
    assert_equal 200, res.status
  end

  def test_background_tasks_empty_when_initialized
    app = FunApi::App.new do |api|
      api.get '/test' do |_input, _req, _task, background:|
        assert background.empty?
        assert_equal 0, background.size
        [{ ok: true }, 200]
      end
    end

    async_request(app, :get, '/test')
  end

  def test_background_tasks_size_tracking
    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        assert_equal 0, background.size
        background.add_task(-> {})
        assert_equal 1, background.size
        background.add_task(-> {})
        assert_equal 2, background.size
        refute background.empty?
        [{ ok: true }, 200]
      end
    end

    async_request(app, :post, '/test')
  end

  def test_background_tasks_execute_with_validation
    results = []

    create_schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    app = FunApi::App.new do |api|
      api.post '/users', body: create_schema do |input, _req, _task, background:|
        name = input[:body][:name]
        background.add_task(->(n) { results << "Created: #{n}" }, name)
        [{ user: name }, 201]
      end
    end

    res = async_request(app, :post, '/users',
                        'CONTENT_TYPE' => 'application/json',
                        :input => JSON.dump(name: 'Alice'))

    assert_equal ['Created: Alice'], results
    assert_equal 201, res.status
  end

  def test_background_tasks_execute_before_dependency_cleanup
    timeline = []

    app = FunApi::App.new do |api|
      api.register(:resource) do |provide|
        timeline << :resource_created
        obj = Object.new
        provide.call(obj)
      ensure
        timeline << :resource_cleaned_up
      end

      api.post '/test', depends: [:resource] do |_input, _req, _task, resource:, background:|
        timeline << :handler_executing
        background.add_task(lambda {
          timeline << :background_task_executing
          timeline << :resource_still_available if resource
        })
        timeline << :handler_returning
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal %i[
      resource_created
      handler_executing
      handler_returning
      background_task_executing
      resource_still_available
      resource_cleaned_up
    ], timeline
    assert_equal 200, res.status
  end

  def test_background_tasks_with_proc
    result = nil

    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        my_proc = proc { |x| result = x * 2 }
        background.add_task(my_proc, 21)
        [{ ok: true }, 200]
      end
    end

    res = async_request(app, :post, '/test')

    assert_equal 42, result
    assert_equal 200, res.status
  end

  def test_add_task_returns_nil
    app = FunApi::App.new do |api|
      api.post '/test' do |_input, _req, _task, background:|
        return_value = background.add_task(-> {})
        assert_nil return_value
        [{ ok: true }, 200]
      end
    end

    async_request(app, :post, '/test')
  end
end
