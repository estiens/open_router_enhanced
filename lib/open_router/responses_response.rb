# frozen_string_literal: true

module OpenRouter
  # Response wrapper for the Responses API Beta (/api/v1/responses)
  # This API differs from chat completions in its response structure,
  # using an `output` array with typed items instead of `choices`.
  class ResponsesResponse
    attr_reader :raw

    def initialize(raw)
      @raw = raw || {}
    end

    # Core accessors
    def id
      raw["id"]
    end

    def status
      # Status can be at top level or derived from message output
      raw["status"] || message_output&.dig("status")
    end

    def model
      raw["model"]
    end

    def created_at
      raw["created_at"]
    end

    def output
      raw["output"] || []
    end

    def usage
      raw["usage"] || {}
    end

    # Convenience method to get the assistant's text content
    def content
      message_output&.dig("content", 0, "text")
    end

    # Get reasoning summary steps (array of strings)
    def reasoning_summary
      reasoning_output&.dig("summary") || []
    end

    # Check if reasoning was included in the response
    def reasoning?
      !reasoning_output.nil?
    end
    alias has_reasoning? reasoning?

    # Get tool/function calls from the response as ResponsesToolCall objects
    #
    # @return [Array<ResponsesToolCall>] Array of tool call objects
    def tool_calls
      @tool_calls ||= output
                      .select { |o| o["type"] == "function_call" }
                      .map { |tc| ResponsesToolCall.new(tc) }
    end

    # Get raw tool call data (hashes) from the response
    #
    # @return [Array<Hash>] Array of raw tool call hashes
    def tool_calls_raw
      output.select { |o| o["type"] == "function_call" }
    end

    def tool_calls?
      tool_calls.any?
    end
    alias has_tool_calls? tool_calls?

    # Execute all tool calls and return results
    #
    # @yield [name, arguments] Block to execute each tool
    # @return [Array<ResponsesToolResult>] Results from all tool executions
    #
    # @example
    #   results = response.execute_tool_calls do |name, args|
    #     case name
    #     when "get_weather" then fetch_weather(args["location"])
    #     when "search" then search_web(args["query"])
    #     end
    #   end
    def execute_tool_calls(&block)
      tool_calls.map { |tc| tc.execute(&block) }
    end

    # Build a follow-up input array that includes tool results
    # Use this to continue the conversation after executing tools
    #
    # @param original_input [String, Array] The original input sent to the API
    # @param tool_results [Array<ResponsesToolResult>] Results from execute_tool_calls
    # @param follow_up_message [String, nil] Optional follow-up user message
    # @return [Array] Input array for the next API call
    #
    # @example
    #   # First call with tools
    #   response = client.responses("What's the weather?", model: "...", tools: [...])
    #
    #   # Execute tools
    #   results = response.execute_tool_calls { |name, args| ... }
    #
    #   # Build follow-up input
    #   next_input = response.build_follow_up_input(
    #     original_input: "What's the weather?",
    #     tool_results: results,
    #     follow_up_message: "Is that good for a picnic?"
    #   )
    #
    #   # Continue conversation
    #   next_response = client.responses(next_input, model: "...")
    def build_follow_up_input(original_input:, tool_results:, follow_up_message: nil)
      input_items = []

      # Add original user message
      if original_input.is_a?(String)
        input_items << {
          "type" => "message",
          "role" => "user",
          "content" => [{ "type" => "input_text", "text" => original_input }]
        }
      elsif original_input.is_a?(Array)
        input_items.concat(original_input)
      end

      # Add function calls from this response
      tool_calls_raw.each do |tc|
        input_items << tc
      end

      # Add function call outputs
      tool_results.each do |result|
        input_items << result.to_input_item
      end

      # Add assistant message if present
      input_items << message_output if message_output

      # Add follow-up user message if provided
      if follow_up_message
        input_items << {
          "type" => "message",
          "role" => "user",
          "content" => [{ "type" => "input_text", "text" => follow_up_message }]
        }
      end

      input_items
    end

    # Token counts
    def input_tokens
      usage["input_tokens"] || 0
    end

    def output_tokens
      usage["output_tokens"] || 0
    end

    def total_tokens
      usage["total_tokens"] || 0
    end

    def reasoning_tokens
      usage.dig("output_tokens_details", "reasoning_tokens") || 0
    end

    # Hash-like access for raw data
    def [](key)
      raw[key]
    end

    def dig(*keys)
      raw.dig(*keys)
    end

    private

    def message_output
      @message_output ||= output.find { |o| o["type"] == "message" }
    end

    def reasoning_output
      @reasoning_output ||= output.find { |o| o["type"] == "reasoning" }
    end
  end
end
