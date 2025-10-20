module FunApi
  module OpenAPI
    class SchemaConverter
      def self.to_json_schema(dry_schema, schema_name = nil)
        return nil unless dry_schema

        if dry_schema.is_a?(Array) && dry_schema.length == 1
          return {
            type: 'array',
            items: to_json_schema(dry_schema.first, schema_name)
          }
        end

        properties = {}
        required = []

        dry_schema.rules.each do |key, rule|
          field_name = key.to_s
          field_info = extract_field_info(rule)

          properties[field_name] = field_info[:schema]
          required << field_name if field_info[:required]
        end

        schema = {
          type: 'object',
          properties: properties
        }

        schema[:required] = required unless required.empty?
        schema
      end

      def self.extract_field_info(rule)
        rule_str = rule.to_s
        is_required = rule.class.name.include?('And')

        type_info = if rule_str.include?('array?')
                      items_type = if rule_str.include?('str?')
                                     { type: 'string' }
                                   elsif rule_str.include?('int?')
                                     { type: 'integer' }
                                   elsif rule_str.include?('float?') || rule_str.include?('decimal?')
                                     { type: 'number' }
                                   elsif rule_str.include?('bool?')
                                     { type: 'boolean' }
                                   else
                                     {}
                                   end
                      { type: 'array', items: items_type }
                    elsif rule_str.include?('hash?')
                      { type: 'object' }
                    elsif rule_str.include?('str?')
                      { type: 'string' }
                    elsif rule_str.include?('int?')
                      { type: 'integer' }
                    elsif rule_str.include?('float?') || rule_str.include?('decimal?')
                      { type: 'number' }
                    elsif rule_str.include?('bool?')
                      { type: 'boolean' }
                    else
                      { type: 'string' }
                    end

        {
          schema: type_info,
          required: is_required
        }
      end

      def self.extract_schema_name(schema_obj)
        ObjectSpace.each_object(Class).each do |klass|
          klass.constants.each do |const_name|
            const_value = klass.const_get(const_name)
            return const_name.to_s if const_value == schema_obj
          rescue StandardError
            next
          end
        end

        nil
      end
    end
  end
end
