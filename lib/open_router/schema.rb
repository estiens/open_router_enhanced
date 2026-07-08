# frozen_string_literal: true

begin
  require "json-schema"
rescue LoadError
  # json-schema gem not available
end

module OpenRouter
  class SchemaValidationError < Error; end

  class Schema
    attr_reader :name, :strict, :schema

    def initialize(name, schema_definition = {}, strict: true)
      @name = name
      @strict = strict
      raise ArgumentError, "Schema definition must be a hash" unless schema_definition.is_a?(Hash)

      @schema = schema_definition
      validate_schema!
    end

    # Class method for defining schemas with a DSL
    def self.define(name, strict: true, &block)
      builder = SchemaBuilder.new
      builder.instance_eval(&block) if block_given?
      new(name, builder.to_h, strict:)
    end

    # Convert to the format expected by OpenRouter API.
    #
    # This is the *honest* representation: it respects the `required` arrays
    # exactly as declared, so fields you left optional stay optional. It is what
    # we describe to the model (prompt injection), what we validate against, and
    # what we hand the healer — keeping "what we ask for" and "what we accept" in
    # agreement. The provider-strict, all-required form lives in #to_strict_h and
    # is used only when serializing a native `json_schema` request.
    def to_h
      {
        name: @name,
        strict: @strict,
        schema: @schema
      }
    end

    # Provider-strict form for native `json_schema` decoding.
    #
    # OpenRouter / OpenAI strict mode requires EVERY object — at every nesting
    # level, including nested objects and array items — to list all of its
    # properties in its `required` array; a nested `required: []` gets a 400.
    # We satisfy that WITHOUT silently making optional fields mandatory: any
    # property that was not declared required is made nullable (its type gains
    # "null"), which is exactly how strict mode expresses optionality. The model
    # may then return `null` for it instead of being forced to invent a value.
    def to_strict_h
      {
        name: @name,
        strict: @strict,
        schema: enforce_all_required(@schema)
      }
    end

    # Get the pure JSON Schema (respects required flags) for testing/validation
    def pure_schema
      @schema
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Check if JSON schema validation is available
    def validation_available?
      !!defined?(JSON::Validator)
    end

    # Validate data against this schema
    def validate(data)
      return true unless defined?(JSON::Validator)

      JSON::Validator.validate(@schema, data)
    end

    # Get validation errors for data
    def validation_errors(data)
      return [] unless defined?(JSON::Validator)

      JSON::Validator.fully_validate(@schema, data)
    end

    # Generate format instructions for model prompting
    def get_format_instructions(forced: false)
      schema_json = to_h.to_json

      if forced
        <<~INSTRUCTIONS
          You must format your output as a JSON value that conforms exactly to the following JSON Schema specification:

          #{schema_json}

          CRITICAL: Your entire response must be valid JSON that matches this schema. Do not include any text before or after the JSON. Return ONLY the JSON value itself - no other text, explanations, or formatting.

          example format:
          ```json
          {"field1": "value1", "field2": "value2"}
          ```

          Important guidelines:
          - Ensure all required fields match the schema exactly
          - Use proper JSON formatting (no trailing commas)
          - All string values must be properly quoted
        INSTRUCTIONS
      else
        <<~INSTRUCTIONS
          Please format your output as a JSON value that conforms to the following JSON Schema specification:

          #{schema_json}

          Your response should be valid JSON that matches this schema structure exactly.

          example format:
          ```json
          {"field1": "value1", "field2": "value2"}
          ```

          Important guidelines:
          - Ensure all required fields match the schema
          - Use proper JSON formatting (no trailing commas)
          - Return ONLY the JSON - no other text or explanations
        INSTRUCTIONS
      end
    end

    private

    # Recursively force every object to list all its properties in `required`,
    # keeping declared-optional properties optional by making them nullable.
    # Reads each node's OWN existing `required` before overwriting, so nested
    # optionality is preserved at every level.
    def enforce_all_required(node)
      case node
      when Hash
        transformed = node.each_with_object({}) { |(key, value), acc| acc[key] = enforce_all_required(value) }

        props = transformed[:properties] || transformed["properties"]
        if props.is_a?(Hash) && props.any?
          key = transformed.key?(:properties) ? :required : "required"
          already_required = Array(transformed[key]).map(&:to_s)
          props.each do |prop_name, prop_def|
            next if already_required.include?(prop_name.to_s)

            props[prop_name] = make_nullable(prop_def)
          end
          transformed[key] = props.keys.map(&:to_s)
        end

        transformed
      when Array
        node.map { |element| enforce_all_required(element) }
      else
        node
      end
    end

    # Add "null" to a property's type union so it can be omitted (as null) under
    # strict mode. Leaves the property untouched if it has no determinable type.
    def make_nullable(prop_def)
      return prop_def unless prop_def.is_a?(Hash)

      type_key = if prop_def.key?(:type) then :type
                 elsif prop_def.key?("type") then "type"
                 end
      return prop_def unless type_key

      types = Array(prop_def[type_key]).map(&:to_s)
      return prop_def if types.include?("null")

      prop_def.merge(type_key => types + ["null"])
    end

    def validate_schema!
      raise ArgumentError, "Schema name is required" if @name.nil? || @name.empty?
      raise ArgumentError, "Schema must be a hash" unless @schema.is_a?(Hash)
    end

    # Internal class for building schemas with DSL
    class SchemaBuilder
      def initialize
        @schema = {
          type: "object",
          properties: {},
          required: []
        }
        @strict_mode = true
        # Set additionalProperties to false by default in strict mode
        @schema[:additionalProperties] = false
      end

      def strict(value = true)
        @strict_mode = value
        additional_properties(!value)
      end

      def additional_properties(allowed = true)
        @schema[:additionalProperties] = allowed
      end

      def no_additional_properties
        additional_properties(false)
      end

      def property(name, type, required: false, description: nil, **options)
        prop_def = { type: type.to_s }
        prop_def[:description] = description if description
        prop_def.merge!(options)

        @schema[:properties][name] = prop_def
        mark_required(name) if required
      end

      def string(name, required: false, description: nil, **options)
        property(name, :string, required:, description:, **options)
      end

      def integer(name, required: false, description: nil, **options)
        property(name, :integer, required:, description:, **options)
      end

      def number(name, required: false, description: nil, **options)
        property(name, :number, required:, description:, **options)
      end

      def boolean(name, required: false, description: nil, **options)
        property(name, :boolean, required:, description:, **options)
      end

      def array(name, required: false, description: nil, items: nil, &block)
        array_def = { type: "array" }
        array_def[:description] = description if description

        if items
          array_def[:items] = items
        elsif block_given?
          items_builder = ItemsBuilder.new
          items_builder.instance_eval(&block)
          array_def[:items] = items_builder.to_h
        end

        @schema[:properties][name] = array_def
        mark_required(name) if required
      end

      def object(name, required: false, description: nil, &block)
        object_def = {
          type: "object",
          properties: {},
          required: []
        }
        object_def[:description] = description if description

        if block_given?
          object_builder = SchemaBuilder.new
          object_builder.instance_eval(&block)
          nested_schema = object_builder.to_h
          object_def[:properties] = nested_schema[:properties]
          object_def[:required] = nested_schema[:required]
          if nested_schema.key?(:additionalProperties)
            object_def[:additionalProperties] =
              nested_schema[:additionalProperties]
          end
        end

        @schema[:properties][name] = object_def
        mark_required(name) if required
      end

      def required(*field_names)
        field_names.each { |name| mark_required(name) }
      end

      def to_h
        @schema.dup
      end

      private

      def mark_required(name)
        # Convert to string to match OpenRouter API expectations
        string_name = name.to_s
        @schema[:required] << string_name unless @schema[:required].include?(string_name)
      end
    end

    # Internal class for building array items
    class ItemsBuilder
      def initialize
        @items = {}
      end

      def string(description: nil, **options)
        @items = { type: "string" }
        @items[:description] = description if description
        @items.merge!(options)
      end

      def integer(description: nil, **options)
        @items = { type: "integer" }
        @items[:description] = description if description
        @items.merge!(options)
      end

      def number(description: nil, **options)
        @items = { type: "number" }
        @items[:description] = description if description
        @items.merge!(options)
      end

      def boolean(description: nil, **options)
        @items = { type: "boolean" }
        @items[:description] = description if description
        @items.merge!(options)
      end

      def object(&block)
        @items = { type: "object", properties: {}, required: [], additionalProperties: false }

        return unless block_given?

        object_builder = SchemaBuilder.new
        object_builder.instance_eval(&block)
        nested_schema = object_builder.to_h
        @items[:properties] = nested_schema[:properties]
        @items[:required] = nested_schema[:required]
        return unless nested_schema.key?(:additionalProperties)

        @items[:additionalProperties] =
          nested_schema[:additionalProperties]
      end

      def to_h
        @items
      end
    end
  end
end
