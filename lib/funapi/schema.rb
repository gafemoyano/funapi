require "dry-schema"

module FunApi
  class Schema
    def self.define(&block)
      Dry::Schema.Params(&block)
    end

    def self.model?(schema)
      schema.is_a?(Class) && schema < FunApi::Model
    end

    def self.validate(schema, data, location: "body")
      return data unless schema

      if schema.is_a?(Array) && schema.length == 1
        item_schema = schema.first
        data_array = data.is_a?(Array) ? data : []

        return data_array.map { |item| validate_one(item_schema, item) }
      end

      validate_one(schema, data)
    end

    def self.validate_one(schema, data)
      return schema.validate(data) if model?(schema)

      result = schema.call(data || {})
      raise ValidationError.new(errors: result.errors) unless result.success?

      result.to_h
    end

    def self.validate_response(schema, data)
      return data unless schema

      if schema.is_a?(Array) && schema.length == 1
        item_schema = schema.first
        data_array = data.is_a?(Array) ? data : []

        return data_array.map { |item| validate_response_one(item_schema, item) }
      end

      validate_response_one(schema, data)
    end

    def self.validate_response_one(schema, data)
      if model?(schema)
        dumped = schema.dump(data)
        result = schema.engine_schema.call(dumped || {})

        unless result.success?
          raise HTTPException.new(
            status_code: 500,
            detail: "Response validation failed: #{result.errors.to_h}"
          )
        end

        return result.to_h
      end

      result = schema.call(data)

      unless result.success?
        raise HTTPException.new(
          status_code: 500,
          detail: "Response validation failed: #{result.errors.to_h}"
        )
      end

      result.to_h
    end
  end
end
