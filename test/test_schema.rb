# frozen_string_literal: true

require 'test_helper'

class TestSchema < Minitest::Test
  def test_define_creates_schema
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    assert_instance_of Dry::Schema::Params, schema
  end

  def test_validate_success_returns_validated_data
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
      required(:age).filled(:integer)
    end

    result = FunApi::Schema.validate(schema, { name: 'Alice', age: 30 }, location: 'body')

    assert_equal 'Alice', result[:name]
    assert_equal 30, result[:age]
  end

  def test_validate_with_string_keys
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    result = FunApi::Schema.validate(schema, { 'name' => 'Bob' }, location: 'body')

    assert_equal 'Bob', result[:name]
  end

  def test_validate_failure_raises_validation_error
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(schema, {}, location: 'body')
    end

    assert_equal 422, error.status_code
  end

  def test_validation_error_detail_format
    schema = FunApi::Schema.define do
      required(:email).filled(:string)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(schema, {}, location: 'body')
    end

    detail = error.detail
    assert_instance_of Array, detail
    assert detail.first.key?(:loc)
    assert detail.first.key?(:msg)
    assert detail.first.key?(:type)
  end

  def test_validation_error_includes_field_name
    schema = FunApi::Schema.define do
      required(:username).filled(:string)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(schema, {}, location: 'body')
    end

    assert(error.detail.any? { |e| e[:loc].include?('username') })
  end

  def test_optional_fields_not_required
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
      optional(:age).filled(:integer)
    end

    result = FunApi::Schema.validate(schema, { name: 'Charlie' }, location: 'body')

    assert_equal 'Charlie', result[:name]
    refute result.key?(:age)
  end

  def test_invalid_type_raises_error
    schema = FunApi::Schema.define do
      required(:age).filled(:integer)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(schema, { age: 'not a number' }, location: 'body')
    end

    assert(error.detail.any? { |e| e[:loc].include?('age') })
  end

  def test_array_schema_validation
    item_schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    result = FunApi::Schema.validate(
      [item_schema],
      [{ name: 'Item 1' }, { name: 'Item 2' }],
      location: 'body'
    )

    assert_equal 2, result.length
    assert_equal 'Item 1', result[0][:name]
    assert_equal 'Item 2', result[1][:name]
  end

  def test_array_schema_validation_failure
    item_schema = FunApi::Schema.define do
      required(:name).filled(:string)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(
        [item_schema],
        [{ name: 'Good' }, { bad: 'data' }],
        location: 'body'
      )
    end

    assert_equal 422, error.status_code
  end

  def test_validate_response_filters_fields
    schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    data = { id: 1, name: 'User', password: 'secret', internal: 'data' }
    result = FunApi::Schema.validate_response(schema, data)

    assert_equal 1, result[:id]
    assert_equal 'User', result[:name]
    refute result.key?(:password)
    refute result.key?(:internal)
  end

  def test_validate_response_with_array
    schema = FunApi::Schema.define do
      required(:id).filled(:integer)
      required(:name).filled(:string)
    end

    data = [
      { id: 1, name: 'User 1', secret: 'data1' },
      { id: 2, name: 'User 2', secret: 'data2' }
    ]

    result = FunApi::Schema.validate_response([schema], data)

    assert_equal 2, result.length
    assert_equal 1, result[0][:id]
    assert_equal 'User 1', result[0][:name]
    refute result[0].key?(:secret)
  end

  def test_nested_schema
    schema = FunApi::Schema.define do
      required(:user).hash do
        required(:name).filled(:string)
        required(:email).filled(:string)
      end
    end

    result = FunApi::Schema.validate(
      schema,
      { user: { name: 'Alice', email: 'alice@example.com' } },
      location: 'body'
    )

    assert_equal 'Alice', result[:user][:name]
    assert_equal 'alice@example.com', result[:user][:email]
  end

  def test_multiple_validation_errors
    schema = FunApi::Schema.define do
      required(:name).filled(:string)
      required(:email).filled(:string)
      required(:age).filled(:integer)
    end

    error = assert_raises(FunApi::ValidationError) do
      FunApi::Schema.validate(schema, {}, location: 'body')
    end

    assert_equal 3, error.detail.length
  end
end
