require 'dry-schema'

module FunApi
  class Schema
    def self.define(&block)
      Dry::Schema.Params(&block)
    end

    def self.validate(schema, data, location: 'body')
      return data unless schema

      if schema.is_a?(Array) && schema.length == 1
        item_schema = schema.first
        data_array = data.is_a?(Array) ? data : []

        results = data_array.map do |item|
          result = item_schema.call(item || {})
          raise ValidationError.new(errors: result.errors) unless result.success?

          result.to_h
        end

        return results
      end

      result = schema.call(data || {})
      raise ValidationError.new(errors: result.errors) unless result.success?

      result.to_h
    end

    def self.validate_response(schema, data)
      return data unless schema

      if schema.is_a?(Array) && schema.length == 1
        item_schema = schema.first
        data_array = data.is_a?(Array) ? data : []

        return data_array.map do |item|
          result = item_schema.call(item)

          unless result.success?
            raise HTTPException.new(
              status_code: 500,
              detail: "Response validation failed: #{result.errors.to_h}"
            )
          end

          result.to_h
        end
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
