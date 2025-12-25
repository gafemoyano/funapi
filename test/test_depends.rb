# frozen_string_literal: true

require "test_helper"

class TestDepends < Minitest::Test
  def test_simple_dependency
    dep = FunApi::Depends.new(-> { "hello" })
    result, _cleanup = dep.call({})
    assert_equal "hello", result
  end

  def test_dependency_with_no_cleanup
    dep = FunApi::Depends.new(-> { "value" })
    result, cleanup = dep.call({})
    assert_equal "value", result
    assert_nil cleanup
  end

  def test_dependency_with_cleanup
    dep = FunApi::Depends.new(-> { ["resource", -> { "cleanup" }] })
    result, cleanup = dep.call({})
    assert_equal "resource", result
    assert_equal "cleanup", cleanup.call
  end

  def test_dependency_with_context
    dep = FunApi::Depends.new(->(req:) { req[:value] })
    result, _cleanup = dep.call(req: {value: 42})
    assert_equal 42, result
  end

  def test_dependency_with_multiple_context_params
    dep = FunApi::Depends.new(->(req:, task:) { {req: req[:id], task: task[:name]} })
    result, _cleanup = dep.call(req: {id: 1}, task: {name: "test"})
    assert_equal({req: 1, task: "test"}, result)
  end

  def test_nested_dependencies
    db = FunApi::Depends.new(-> { "db_connection" })
    user = FunApi::Depends.new(->(db:) { "user_from_#{db}" }, db: db)

    result, _cleanup = user.call({})
    assert_equal "user_from_db_connection", result
  end

  def test_nested_dependencies_with_context
    db = FunApi::Depends.new(-> { "db" })
    user = FunApi::Depends.new(->(req:, db:) { "#{db}_user_#{req[:id]}" }, db: db)

    result, _cleanup = user.call(req: {id: 123})
    assert_equal "db_user_123", result
  end

  def test_caching_same_dependency
    call_count = 0
    dep = FunApi::Depends.new(lambda {
      call_count += 1
      "value"
    })

    cache = {}
    result1, _cleanup1 = dep.call({}, cache)
    result2, _cleanup2 = dep.call({}, cache)

    assert_equal "value", result1
    assert_equal "value", result2
    assert_equal 1, call_count
  end

  def test_callable_class
    klass = Class.new do
      def call
        "from_class"
      end
    end

    dep = FunApi::Depends.new(klass.new)
    result, _cleanup = dep.call({})
    assert_equal "from_class", result
  end

  def test_callable_class_with_params
    klass = Class.new do
      def call(req:)
        "value_#{req[:id]}"
      end
    end

    dep = FunApi::Depends.new(klass.new)
    result, _cleanup = dep.call({req: {id: 42}})
    assert_equal "value_42", result
  end

  def test_non_callable_raises_error
    assert_raises(ArgumentError) do
      FunApi::Depends.new("not_callable")
    end
  end

  def test_helper_method
    dep = FunApi::Depends(-> { "hello" })
    assert_instance_of FunApi::Depends, dep
    result, _cleanup = dep.call({})
    assert_equal "hello", result
  end
end
