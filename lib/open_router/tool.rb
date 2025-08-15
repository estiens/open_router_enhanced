# frozen_string_literal: true

module OpenRouter
  class Tool
    attr_reader :type, :function

    def initialize(definition = {})
      if definition.is_a?(Hash) && definition.key?(:function)
        @type = definition[:type] || "function"
        @function = definition[:function]
      elsif definition.is_a?(Hash)
        @type = "function"
        @function = definition
      else
        raise ArgumentError, "Tool definition must be a hash"
      end

      validate_definition!
    end

    # Class method for defining tools with a DSL
    def self.define(&block)
      builder = ToolBuilder.new
      builder.instance_eval(&block) if block_given?
      new(builder.to_h)
    end

    def to_h
      {
        type: @type,
        function: @function
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    def name
      @function[:name]
    end

    def description
      @function[:description]
    end

    def parameters
      @function[:parameters]
    end

    private

    def validate_definition!
      raise ArgumentError, "Function must have a name" unless @function[:name]
      raise ArgumentError, "Function must have a description" unless @function[:description]

      return unless @function[:parameters] && @function[:parameters][:type] != "object"

      raise ArgumentError,
            "Function parameters must be an object"
    end

    # Internal class for building tool definitions with DSL
    class ToolBuilder
      def initialize
        @definition = {
          name: nil,
          description: nil,
          parameters: {
            type: "object",
            properties: {},
            required: []
          }
        }
      end

      def name(value)
        @definition[:name] = value
      end

      def description(value)
        @definition[:description] = value
      end

      def parameters(&block)
        param_builder = ParametersBuilder.new(@definition[:parameters])
        param_builder.instance_eval(&block) if block_given?
      end

      def to_h
        @definition
      end
    end

    # Internal class for building parameter schemas
    class ParametersBuilder
      def initialize(params_hash)
        @params = params_hash
      end

      def string(name, required: false, description: nil, **options)
        add_property(name, { type: "string", description: }.merge(options).compact)
        mark_required(name) if required
      end

      def integer(name, required: false, description: nil, **options)
        add_property(name, { type: "integer", description: }.merge(options).compact)
        mark_required(name) if required
      end

      def number(name, required: false, description: nil, **options)
        add_property(name, { type: "number", description: }.merge(options).compact)
        mark_required(name) if required
      end

      def boolean(name, required: false, description: nil, **options)
        add_property(name, { type: "boolean", description: }.merge(options).compact)
        mark_required(name) if required
      end

      def array(name, required: false, description: nil, items: nil, &block)
        array_def = { type: "array", description: }.compact

        if items
          array_def[:items] = items
        elsif block_given?
          items_builder = ItemsBuilder.new
          items_builder.instance_eval(&block)
          array_def[:items] = items_builder.to_h
        end

        add_property(name, array_def)
        mark_required(name) if required
      end

      def object(name, required: false, description: nil, &block)
        object_def = {
          type: "object",
          description:,
          properties: {},
          required: []
        }.compact

        if block_given?
          object_builder = ParametersBuilder.new(object_def)
          object_builder.instance_eval(&block)
        end

        add_property(name, object_def)
        mark_required(name) if required
      end

      private

      def add_property(name, definition)
        processed_definition = definition.transform_values { |value| value.is_a?(Proc) ? value.call : value }
        @params[:properties][name] = processed_definition
      end

      def mark_required(name)
        @params[:required] << name unless @params[:required].include?(name)
      end
    end

    # Internal class for building array items
    class ItemsBuilder
      def initialize
        @items = {}
      end

      def string(description: nil, **options)
        @items = { type: "string", description: }.merge(options).compact
      end

      def integer(description: nil, **options)
        @items = { type: "integer", description: }.merge(options).compact
      end

      def number(description: nil, **options)
        @items = { type: "number", description: }.merge(options).compact
      end

      def boolean(description: nil, **options)
        @items = { type: "boolean", description: }.merge(options).compact
      end

      def object(&block)
        @items = {
          type: "object",
          properties: {},
          required: [],
          additionalProperties: false
        }

        return unless block_given?

        nested = Tool::ParametersBuilder.new(@items)
        nested.instance_eval(&block)
      end

      def items(schema = nil, &block)
        # This method allows for `array { items { object { ... }}}` or `items(hash)`
        if block_given?
          # Block defines what each item in the array looks like
          nested_builder = ItemsBuilder.new
          nested_builder.instance_eval(&block)
          @items = nested_builder.to_h
        elsif schema.is_a?(Hash)
          # Direct hash schema assignment
          @items = schema
        else
          raise ArgumentError, "items must be called with either a hash or a block"
        end
      end

      def to_h
        @items
      end
    end
  end
end
