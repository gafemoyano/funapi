# frozen_string_literal: true

require_relative "test_helper"

class TestLifecycle < Minitest::Test
  def test_on_startup_registers_hook
    app = FunApi::App.new do |api|
      api.on_startup { :startup }
    end

    assert_equal 1, app.startup_hooks.size
  end

  def test_on_shutdown_registers_hook
    app = FunApi::App.new do |api|
      api.on_shutdown { :shutdown }
    end

    assert_equal 1, app.shutdown_hooks.size
  end

  def test_multiple_startup_hooks
    app = FunApi::App.new do |api|
      api.on_startup { :first }
      api.on_startup { :second }
    end

    assert_equal 2, app.startup_hooks.size
  end

  def test_multiple_shutdown_hooks
    app = FunApi::App.new do |api|
      api.on_shutdown { :first }
      api.on_shutdown { :second }
    end

    assert_equal 2, app.shutdown_hooks.size
  end

  def test_run_startup_hooks_executes_in_order
    order = []
    app = FunApi::App.new do |api|
      api.on_startup { order << 1 }
      api.on_startup { order << 2 }
      api.on_startup { order << 3 }
    end

    app.run_startup_hooks

    assert_equal [1, 2, 3], order
  end

  def test_run_shutdown_hooks_executes_in_order
    order = []
    app = FunApi::App.new do |api|
      api.on_shutdown { order << 1 }
      api.on_shutdown { order << 2 }
    end

    app.run_shutdown_hooks

    assert_equal [1, 2], order
  end

  def test_shutdown_hook_error_does_not_stop_other_hooks
    order = []
    app = FunApi::App.new do |api|
      api.on_shutdown { order << 1 }
      api.on_shutdown { raise "error" }
      api.on_shutdown { order << 3 }
    end

    app.run_shutdown_hooks

    assert_equal [1, 3], order
  end

  def test_startup_hook_error_propagates
    app = FunApi::App.new do |api|
      api.on_startup { raise "startup failed" }
    end

    assert_raises(RuntimeError) { app.run_startup_hooks }
  end

  def test_on_startup_requires_block
    app = FunApi::App.new

    assert_raises(ArgumentError) { app.on_startup }
  end

  def test_on_shutdown_requires_block
    app = FunApi::App.new

    assert_raises(ArgumentError) { app.on_shutdown }
  end

  def test_on_startup_returns_self_for_chaining
    app = FunApi::App.new

    result = app.on_startup { :hook }

    assert_same app, result
  end

  def test_on_shutdown_returns_self_for_chaining
    app = FunApi::App.new

    result = app.on_shutdown { :hook }

    assert_same app, result
  end

  def test_hooks_work_with_async_context
    order = []
    app = FunApi::App.new do |api|
      api.on_startup do
        Async do
          sleep(0.001)
          order << :async_startup
        end.wait
      end
    end

    Async { app.run_startup_hooks }.wait

    assert_equal [:async_startup], order
  end

  def test_empty_startup_hooks_runs_without_error
    app = FunApi::App.new

    app.run_startup_hooks
  end

  def test_empty_shutdown_hooks_runs_without_error
    app = FunApi::App.new

    app.run_shutdown_hooks
  end
end
