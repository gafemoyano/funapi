require 'dry-schema'

module FunApi
  class Schema
    def self.define(&block)
      Dry::Schema.Params(&block)
    end

    def self.validate(schema, data, location: 'body')
      return data unless schema

      result = schema.call(data || {})

      raise ValidationError.new(errors: result.errors) unless result.success?

      result.to_h
    end
  end
end
