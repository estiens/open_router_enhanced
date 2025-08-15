# frozen_string_literal: true

require "json"

module OpenRouter
  class ToolCallError < Error; end

  class ToolCall
    attr_reader :id, :type, :function_name, :arguments_string

    def initialize(tool_call_data)
      @id = tool_call_data["id"]
      @type = tool_call_data["type"]

      raise ToolCallError, "Invalid tool call data: missing function" unless tool_call_data["function"]

      @function_name = tool_call_data["function"]["name"]
      @arguments_string = tool_call_data["function"]["arguments"]
    end

    # Parse the arguments JSON string into a Ruby hash
    def arguments
      @arguments ||= begin
        JSON.parse(@arguments_string)
      rescue JSON::ParserError => e
        raise ToolCallError, "Failed to parse tool call arguments: #{e.message}"
      end
    end

    # Get the function name (alias for consistency)
    def name
      @function_name
    end

    # Execute the tool call with a provided block
    # The block should accept (name, arguments) and return the result
    def execute(&block)
      raise ArgumentError, "Block required for tool execution" unless block_given?

      begin
        result = block.call(@function_name, arguments)
        ToolResult.new(self, result)
      rescue StandardError => e
        ToolResult.new(self, nil, e.message)
      end
    end

    # Convert this tool call to a message format for conversation continuation
    def to_message
      {
        role: "assistant",
        content: nil,
        tool_calls: [
          {
            id: @id,
            type: @type,
            function: {
              name: @function_name,
              arguments: @arguments_string
            }
          }
        ]
      }
    end

    # Convert a tool result to a tool message for the conversation
    def to_result_message(result)
      content = case result
                when String then result
                when nil then ""
                else result.to_json
                end

      {
        role: "tool",
        tool_call_id: @id,
        content: content
      }
    end

    def to_h
      {
        id: @id,
        type: @type,
        function: {
          name: @function_name,
          arguments: @arguments_string
        }
      }
    end

    def to_json(*args)
      to_h.to_json(*args)
    end

    # Validate against a provided array of tools (Tool instances or hashes)
    def valid?(tools:)
      # tools is now a required keyword argument

      schema = find_schema_for_call(tools)
      return true unless schema # No validation if tool not found

      return JSON::Validator.validate(schema, arguments) if validation_available?

      # Fallback: shallow required check
      required = Array(schema[:required]).map(&:to_s)
      required.all? { |k| arguments.key?(k) }
    rescue StandardError
      false
    end

    def validation_errors(tools:)
      # tools is now a required keyword argument

      schema = find_schema_for_call(tools)
      return [] unless schema # No errors if tool not found

      return JSON::Validator.fully_validate(schema, arguments) if validation_available?

      # Fallback: check required fields
      required = Array(schema[:required]).map(&:to_s)
      missing = required.reject { |k| arguments.key?(k) }
      missing.any? ? ["Missing required keys: #{missing.join(", ")}"] : []
    rescue StandardError => e
      ["Validation error: #{e.message}"]
    end

    private

    # Check if JSON schema validation is available
    def validation_available?
      !!defined?(JSON::Validator)
    end

    def find_schema_for_call(tools)
      tool = Array(tools).find do |t|
        t_name = t.is_a?(OpenRouter::Tool) ? t.name : t.dig(:function, :name)
        t_name == @function_name
      end
      return nil unless tool

      params = tool.is_a?(OpenRouter::Tool) ? tool.parameters : tool.dig(:function, :parameters)
      params.is_a?(Hash) ? params : nil
    end
  end

  # Represents the result of executing a tool call
  class ToolResult
    attr_reader :tool_call, :result, :error

    def initialize(tool_call, result = nil, error = nil)
      @tool_call = tool_call
      @result = result
      @error = error
    end

    def success?
      @error.nil?
    end

    def failure?
      !success?
    end

    # Convert to message format for conversation continuation
    def to_message
      @tool_call.to_result_message(@error || @result)
    end

    # Create a failed result
    def self.failure(tool_call, error)
      new(tool_call, nil, error)
    end

    # Create a successful result
    def self.success(tool_call, result)
      new(tool_call, result, nil)
    end
  end
end
