# frozen_string_literal: true

require "securerandom"

module OpenRouter
  # Represents a tool/function call from the Responses API.
  # Format: type="function_call" with name/arguments at top level (not nested)
  class ResponsesToolCall
    include ToolCallBase

    attr_reader :id, :call_id, :arguments_string

    def initialize(tool_call_data)
      @id = tool_call_data["id"]
      @call_id = tool_call_data["call_id"]
      @name = tool_call_data["name"]
      @arguments_string = tool_call_data["arguments"] || "{}"
    end

    # Get the function name
    attr_reader :name

    # Alias for consistency with ToolCall
    def function_name
      @name
    end

    # Build result for execute method (required by ToolCallBase)
    def build_result(result, error = nil)
      ResponsesToolResult.new(self, result, error)
    end

    # Convert to the function_call format for conversation continuation
    def to_input_item
      {
        "type" => "function_call",
        "id" => @id,
        "call_id" => @call_id,
        "name" => @name,
        "arguments" => @arguments_string
      }
    end

    def to_h
      to_input_item
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end

  # Represents the result of executing a Responses API tool call
  class ResponsesToolResult
    include ToolResultBase

    attr_reader :tool_call, :result, :error

    def initialize(tool_call, result = nil, error = nil)
      @tool_call = tool_call
      @result = result
      @error = error
    end

    # Convert to function_call_output format for conversation continuation
    #
    # @return [Hash] The output item for the input array
    def to_input_item
      output_content = if @error
                         { error: @error }.to_json
                       elsif @result.is_a?(String)
                         @result
                       else
                         @result.to_json
                       end

      {
        "type" => "function_call_output",
        "id" => "fc_output_#{SecureRandom.hex(8)}",
        "call_id" => @tool_call.call_id,
        "output" => output_content
      }
    end

    def to_h
      to_input_item
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
