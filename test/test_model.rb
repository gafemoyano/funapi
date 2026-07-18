# frozen_string_literal: true

require "test_helper"

class ModelAddress < FunApi::Model
  field :street, :string
  field :zip, :string, optional: true
end

class ModelPost < FunApi::Model
  field :title, :string
end

class ModelUser < FunApi::Model
  field :id, :integer
  field :name, :string, description: "Display name"
  field :email, :string, format: "email"
  field :role, :string, enum: %w[admin member], default: "member"
  field :age, :integer, optional: true, nullable: true, min: 0, max: 120
  field :address, ModelAddress, optional: true
  field :tags, [:string], default: []
  field :posts, [ModelPost], default: []
end

class ModelAnimal < FunApi::Model
  field :name, :string
  field :legs, :integer, default: 4
end

class ModelDog < ModelAnimal
  field :breed, :string
end

class TestModelFields < Minitest::Test
  def test_fields_returns_metadata
    meta = ModelUser.fields[:id]
    assert_equal :integer, meta[:type]
    assert_equal true, meta[:required]
  end

  def test_fields_is_frozen
    assert ModelUser.fields.frozen?
  end

  def test_required_by_default
    assert ModelUser.fields[:name][:required]
  end

  def test_optional_not_required
    refute ModelUser.fields[:age][:required]
  end

  def test_default_makes_field_not_required
    refute ModelUser.fields[:role][:required]
    assert_equal "member", ModelUser.fields[:role][:default]
  end

  def test_unknown_option_raises_at_definition
    error = assert_raises(ArgumentError) do
      Class.new(FunApi::Model) do
        field :x, :string, bogus: true
      end
    end
    assert_match(/bogus/, error.message)
  end

  def test_unknown_type_raises
    assert_raises(ArgumentError) do
      Class.new(FunApi::Model) do
        field :x, :not_a_type
      end
    end
  end

  def test_array_type_must_be_single_element
    assert_raises(ArgumentError) do
      Class.new(FunApi::Model) do
        field :x, %i[string integer]
      end
    end
  end

  def test_inheritance_composes_fields
    assert_equal %i[name legs breed], ModelDog.fields.keys
    assert_equal :string, ModelDog.fields[:breed][:type]
    assert_equal :string, ModelDog.fields[:name][:type]
  end

  def test_inheritance_does_not_mutate_parent
    refute ModelAnimal.fields.key?(:breed)
  end
end

class TestModelValidate < Minitest::Test
  def test_coerces_types
    result = ModelUser.validate(id: "5", name: "Al", email: "a@b.com")
    assert_equal 5, result[:id]
  end

  def test_applies_defaults
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com")
    assert_equal "member", result[:role]
    assert_equal [], result[:tags]
    assert_equal [], result[:posts]
  end

  def test_default_array_is_not_shared
    a = ModelUser.validate(id: 1, name: "Al", email: "a@b.com")
    a[:tags] << "x"
    b = ModelUser.validate(id: 2, name: "Bo", email: "b@c.com")
    assert_equal [], b[:tags]
  end

  def test_optional_field_omitted
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com")
    refute result.key?(:address)
  end

  def test_nullable_allows_nil
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com", age: nil)
    assert_nil result[:age]
  end

  def test_missing_required_raises_validation_error
    error = assert_raises(FunApi::ValidationError) do
      ModelUser.validate(id: 1, email: "a@b.com")
    end
    assert(error.detail.any? { |e| e[:loc].include?("name") })
  end

  def test_enum_violation_raises
    error = assert_raises(FunApi::ValidationError) do
      ModelUser.validate(id: 1, name: "Al", email: "a@b.com", role: "hacker")
    end
    assert(error.detail.any? { |e| e[:loc].include?("role") })
  end

  def test_min_max_violation
    error = assert_raises(FunApi::ValidationError) do
      ModelUser.validate(id: 1, name: "Al", email: "a@b.com", age: 200)
    end
    assert(error.detail.any? { |e| e[:loc].include?("age") })
  end

  def test_pattern_violation
    klass = Class.new(FunApi::Model) do
      field :code, :string, pattern: /\A[A-Z]{3}\z/
    end
    assert_raises(FunApi::ValidationError) { klass.validate(code: "abc") }
    assert_equal({code: "ABC"}, klass.validate(code: "ABC"))
  end

  def test_array_size_bounds_enforced
    klass = Class.new(FunApi::Model) do
      field :tags, [:string], min: 2, max: 3
    end

    error = assert_raises(FunApi::ValidationError) { klass.validate(tags: ["one"]) }
    assert(error.detail.any? { |e| e[:loc].include?("tags") })
    assert_raises(FunApi::ValidationError) { klass.validate(tags: %w[a b c d]) }
    assert_equal({tags: %w[a b]}, klass.validate(tags: %w[a b]))
    assert_equal({tags: [1, 2]}, Class.new(FunApi::Model) { field :tags, [:integer], min: 2 }.validate(tags: %w[1 2]))

    schema = klass.json_schema[:properties]["tags"]
    assert_equal 2, schema[:minItems]
    assert_equal 3, schema[:maxItems]
  end

  def test_array_of_models_size_bounds_enforced
    item = Class.new(FunApi::Model) { field :name, :string }
    klass = Class.new(FunApi::Model) { field :items, [item], min: 1 }

    assert_raises(FunApi::ValidationError) { klass.validate(items: []) }
    assert_equal({items: [{name: "x"}]}, klass.validate(items: [{name: "x"}]))
  end

  def test_string_min_length
    klass = Class.new(FunApi::Model) do
      field :password, :string, min: 8
    end
    assert_raises(FunApi::ValidationError) { klass.validate(password: "short") }
    assert_equal({password: "longenough"}, klass.validate(password: "longenough"))
  end

  def test_nested_model_validation
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com", address: {street: "Main"})
    assert_equal "Main", result[:address][:street]
  end

  def test_nested_model_error_path
    error = assert_raises(FunApi::ValidationError) do
      ModelUser.validate(id: 1, name: "Al", email: "a@b.com", address: {})
    end
    assert(error.detail.any? { |e| e[:loc] == ["address", "street"] })
  end

  def test_array_of_models
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com", posts: [{title: "P1"}, {title: "P2"}])
    assert_equal 2, result[:posts].length
    assert_equal "P1", result[:posts].first[:title]
  end

  def test_array_of_primitives
    result = ModelUser.validate(id: 1, name: "Al", email: "a@b.com", tags: %w[a b])
    assert_equal %w[a b], result[:tags]
  end

  def test_error_format_shape
    error = assert_raises(FunApi::ValidationError) do
      ModelUser.validate({})
    end
    first = error.detail.first
    assert first.key?(:loc)
    assert first.key?(:msg)
    assert_equal "value_error", first[:type]
  end
end

class TestModelDump < Minitest::Test
  def test_dump_from_hash_filters_undeclared
    out = ModelUser.dump(id: 1, name: "Al", email: "a@b.com", password: "secret")
    refute out.key?(:password)
    assert_equal 1, out[:id]
  end

  def test_dump_from_struct
    struct = Struct.new(:id, :name, :email, :password).new(2, "Bo", "b@c.com", "x")
    out = ModelUser.dump(struct)
    assert_equal "Bo", out[:name]
    refute out.key?(:password)
  end

  def test_dump_from_object
    obj = Object.new
    def obj.id = 7
    def obj.name = "Zed"
    def obj.email = "z@z.com"
    out = ModelUser.dump(obj)
    assert_equal 7, out[:id]
    assert_equal "Zed", out[:name]
  end

  def test_dump_omits_missing_optional
    out = ModelUser.dump(id: 1, name: "Al", email: "a@b.com")
    refute out.key?(:address)
  end

  def test_dump_recurses_into_nested_model
    source = {id: 1, name: "Al", email: "a@b.com", address: {street: "Main", secret: "no"}}
    out = ModelUser.dump(source)
    assert_equal({street: "Main"}, out[:address])
  end

  def test_dump_recurses_into_array_of_models
    source = {id: 1, name: "Al", email: "a@b.com", posts: [{title: "P1", extra: "x"}]}
    out = ModelUser.dump(source)
    assert_equal [{title: "P1"}], out[:posts]
  end

  def test_dump_keeps_nullable_nil
    out = ModelUser.dump(id: 1, name: "Al", email: "a@b.com", age: nil)
    assert out.key?(:age)
    assert_nil out[:age]
  end

  def test_dump_nil_source
    assert_nil ModelUser.dump(nil)
  end
end

class TestModelJsonSchema < Minitest::Test
  def test_basic_structure
    schema = ModelUser.json_schema
    assert_equal "object", schema[:type]
    assert_includes schema[:required], "id"
    assert_includes schema[:required], "name"
    refute_includes schema[:required], "role"
  end

  def test_description_and_format
    props = ModelUser.json_schema[:properties]
    assert_equal "Display name", props["name"][:description]
    assert_equal "email", props["email"][:format]
  end

  def test_enum
    assert_equal %w[admin member], ModelUser.json_schema[:properties]["role"][:enum]
  end

  def test_min_max_nullable
    age = ModelUser.json_schema[:properties]["age"]
    assert_equal 0, age[:minimum]
    assert_equal 120, age[:maximum]
    assert age[:nullable]
  end

  def test_string_min_maps_to_min_length
    klass = Class.new(FunApi::Model) do
      field :password, :string, min: 8, max: 64
    end
    props = klass.json_schema[:properties]["password"]
    assert_equal 8, props[:minLength]
    assert_equal 64, props[:maxLength]
  end

  def test_nested_model_inlined
    address = ModelUser.json_schema[:properties]["address"]
    assert_equal "object", address[:type]
    assert_equal "string", address[:properties]["street"][:type]
  end

  def test_array_of_primitives
    tags = ModelUser.json_schema[:properties]["tags"]
    assert_equal "array", tags[:type]
    assert_equal "string", tags[:items][:type]
  end

  def test_array_of_models
    posts = ModelUser.json_schema[:properties]["posts"]
    assert_equal "array", posts[:type]
    assert_equal "object", posts[:items][:type]
    assert_equal "string", posts[:items][:properties]["title"][:type]
  end
end
