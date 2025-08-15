# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Tool Calling", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Simple calculator tool for testing
  let(:calculator_tool) do
    OpenRouter::Tool.define do
      name "calculator"
      description "Perform basic arithmetic operations"
      parameters do
        string "operation", required: true, description: "The operation to perform: add, subtract, multiply, divide"
        number "a", required: true, description: "First number"
        number "b", required: true, description: "Second number"
      end
    end
  end

  # Weather tool for testing
  let(:weather_tool) do
    OpenRouter::Tool.define do
      name "get_weather"
      description "Get current weather for a location"
      parameters do
        string "location", required: true, description: "City name"
        string "units", required: false, description: "Temperature units (celsius/fahrenheit)"
      end
    end
  end

  # Hash-based tool definition
  let(:hash_tool) do
    {
      type: "function",
      function: {
        name: "search_database",
        description: "Search for information in the database",
        parameters: {
          type: "object",
          properties: {
            query: {
              type: "string",
              description: "Search query"
            },
            limit: {
              type: "integer",
              description: "Maximum number of results"
            }
          },
          required: ["query"]
        }
      }
    }
  end

  describe "single tool call" do
    it "successfully makes a tool call with DSL-defined tool", vcr: { cassette_name: "tool_calling_dsl_tool" } do
      messages = [
        { role: "user", content: "What is 15 + 27?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.has_tool_calls?).to be true
      expect(response.tool_calls.length).to eq(1)

      tool_call = response.tool_calls.first
      expect(tool_call).to be_a(OpenRouter::ToolCall)
      expect(tool_call.function_name).to eq("calculator")
      expect(tool_call.id).to be_a(String)
      expect(tool_call.type).to eq("function")

      # Check arguments
      args = tool_call.arguments
      expect(args).to be_a(Hash)
      expect(args["operation"]).to eq("add")
      expect([15, 15.0]).to include(args["a"])
      expect([27, 27.0]).to include(args["b"])
    end

    it "works with hash-defined tools", vcr: { cassette_name: "tool_calling_hash_tool" } do
      messages = [
        { role: "user", content: "Search for 'ruby programming' in the database" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [hash_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first
      expect(tool_call.function_name).to eq("search_database")

      args = tool_call.arguments
      expect(args["query"]).to include("ruby")
    end
  end

  describe "multiple tools available" do
    it "chooses appropriate tool from multiple options", vcr: { cassette_name: "tool_calling_multiple_tools" } do
      messages = [
        { role: "user", content: "What's the weather like in San Francisco?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool, weather_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first
      expect(tool_call.function_name).to eq("get_weather")

      args = tool_call.arguments
      expect(args["location"]).to include("San Francisco")
    end
  end

  describe "tool choice parameter" do
    it "respects specific tool choice", vcr: { cassette_name: "tool_calling_specific_choice" } do
      messages = [
        { role: "user", content: "Calculate something for me" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool, weather_tool],
        tool_choice: { type: "function", function: { name: "calculator" } },
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first
      expect(tool_call.function_name).to eq("calculator")
    end

    it "respects required tool choice", vcr: { cassette_name: "tool_calling_required_choice" } do
      messages = [
        { role: "user", content: "Hello there" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "required",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
    end

    it "respects none tool choice", vcr: { cassette_name: "tool_calling_none_choice" } do
      messages = [
        { role: "user", content: "What is 5 + 5?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "none",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be false
      expect(response.content).to be_a(String)
    end
  end

  describe "tool execution and conversation continuation",
           vcr: { cassette_name: "tool_calling_execution_continuation" } do
    it "completes full tool calling workflow" do
      # Initial message
      messages = [
        { role: "user", content: "What is 25 * 4?" }
      ]

      # First request - should trigger tool call
      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first

      # Execute the tool call
      tool_result = tool_call.execute do |name, args|
        case name
        when "calculator"
          a = args["a"]
          b = args["b"]
          case args["operation"]
          when "add"
            a + b
          when "subtract"
            a - b
          when "multiply"
            a * b
          when "divide"
            a / b
          end
        end
      end

      expect(tool_result).to be_a(OpenRouter::ToolResult)
      expect(tool_result.success?).to be true
      expect(tool_result.result).to eq(100)

      # Continue conversation with tool result
      updated_messages = messages + [
        response.to_message,
        tool_result.to_message
      ]

      final_response = client.complete(
        updated_messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 500 }
      )

      expect(final_response.has_content?).to be true
      expect(final_response.content.downcase).to include("100")
    end
  end

  describe "multiple tool calls in one response", vcr: { cassette_name: "tool_calling_multiple_calls" } do
    it "handles multiple tool calls when requested" do
      messages = [
        { role: "user", content: "Calculate 10 + 5 and also 20 * 3" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      # May have multiple tool calls or one call that handles both
      expect(response.has_tool_calls?).to be true
      expect(response.tool_calls.length).to be >= 1

      # Verify each tool call is valid
      response.tool_calls.each do |tool_call|
        expect(tool_call.function_name).to eq("calculator")
        expect(tool_call.arguments).to be_a(Hash)
        expect(%w[add multiply]).to include(tool_call.arguments["operation"])
      end
    end
  end

  describe "tool call serialization", vcr: { cassette_name: "tool_calling_serialization" } do
    it "properly serializes tool calls to conversation messages" do
      messages = [
        { role: "user", content: "What is 7 + 3?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      # Test Response.to_message
      message = response.to_message
      expect(message[:role]).to eq("assistant")
      expect(message[:tool_calls]).to be_an(Array)
      expect(message[:tool_calls].length).to be > 0

      # Test ToolCall.to_message
      tool_call = response.tool_calls.first
      tool_message = tool_call.to_message
      expect(tool_message[:role]).to eq("assistant")
      expect(tool_message[:tool_calls]).to be_an(Array)

      # Test tool result message
      result_message = tool_call.to_result_message("Result: 10")
      expect(result_message[:role]).to eq("tool")
      expect(result_message[:tool_call_id]).to eq(tool_call.id)
      expect(result_message[:content]).to eq("Result: 10")
      # NOTE: 'name' field is correctly excluded per OpenAI specification
    end
  end

  describe "tool call error handling", vcr: { cassette_name: "tool_calling_error_handling" } do
    it "handles tool execution errors gracefully" do
      messages = [
        { role: "user",
          content: "Use the calculator tool to divide 10 by 0. Please call the calculator function with operation='divide', a=10, b=0" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "required", # Force tool usage
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first

      # Execute with error handling
      tool_result = tool_call.execute do |name, args|
        case name
        when "calculator"
          _ = args["a"]
          b = args["b"]
          raise "Division by zero error" if args["operation"] == "divide" && b == 0
          # ... other operations
        end
      end

      expect(tool_result.failure?).to be true
      expect(tool_result.error).to include("Division by zero")
    end

    it "handles malformed tool arguments" do
      # This test would require a response with malformed JSON,
      # which is unlikely from the real API but worth testing the error handling
      malformed_data = {
        "id" => "test_id",
        "type" => "function",
        "function" => {
          "name" => "calculator",
          "arguments" => "invalid json content"
        }
      }

      expect do
        tool_call = OpenRouter::ToolCall.new(malformed_data)
        tool_call.arguments
      end.to raise_error(OpenRouter::ToolCallError, /Failed to parse tool call arguments/)
    end
  end

  describe "tool validation", vcr: { cassette_name: "tool_calling_validation" } do
    it "validates tool definitions correctly" do
      expect do
        OpenRouter::Tool.define do
          # Missing name - should raise error
          description "A tool without a name"
        end
      end.to raise_error(ArgumentError, /Function must have a name/)

      expect do
        OpenRouter::Tool.define do
          name "test_tool"
          # Missing description - should raise error
        end
      end.to raise_error(ArgumentError, /Function must have a description/)
    end

    it "validates hash-based tool definitions" do
      invalid_tool = {
        type: "function",
        function: {
          name: "test_tool"
          # Missing description
        }
      }

      expect do
        OpenRouter::Tool.new(invalid_tool)
      end.to raise_error(ArgumentError, /Function must have a description/)
    end
  end

  describe "complex parameter types", vcr: { cassette_name: "tool_calling_complex_parameters" } do
    let(:complex_tool) do
      OpenRouter::Tool.define do
        name "process_data"
        description "Process complex data structures"
        parameters do
          string "name", required: true, description: "Name of the dataset"
          array "items", required: true, description: "Array of items to process" do
            string description: "Individual item"
          end
          object "config", required: false, description: "Configuration object" do
            boolean "enabled", required: true, description: "Whether processing is enabled"
            integer "max_items", required: false, description: "Maximum items to process"
          end
        end
      end
    end

    it "handles complex parameter structures" do
      messages = [
        { role: "user",
          content: "Process a dataset called 'test_data' with items ['a', 'b', 'c'] and enable processing with max 100 items" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [complex_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first
      expect(tool_call.function_name).to eq("process_data")

      args = tool_call.arguments
      expect(args["name"]).to be_a(String)
      expect(args["items"]).to be_an(Array)

      if args["config"]
        expect(args["config"]).to be_a(Hash)
        expect([true, false]).to include(args["config"]["enabled"])
      end
    end
  end

  describe "response structure validation", vcr: { cassette_name: "tool_calling_response_structure" } do
    it "validates complete response structure with tool calls" do
      messages = [
        { role: "user", content: "Add 5 and 10" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      # Test Response structure
      expect(response.id).to be_a(String)
      expect(response.object).to eq("chat.completion")
      expect(response.created).to be_a(Integer)
      expect(response.model).to include("gpt-4o-mini")
      expect(response.usage).to be_a(Hash)
      expect(response.usage["prompt_tokens"]).to be > 0

      # Test tool call structure
      expect(response.has_tool_calls?).to be true
      tool_call = response.tool_calls.first

      expect(tool_call.id).to be_a(String)
      expect(tool_call.type).to eq("function")
      expect(tool_call.function_name).to be_a(String)
      expect(tool_call.arguments_string).to be_a(String)
      expect(tool_call.arguments).to be_a(Hash)

      # Test serialization
      expect(tool_call.to_h).to be_a(Hash)
      expect(tool_call.to_json).to be_a(String)

      # Test backward compatibility
      expect(response["choices"]).to be_an(Array)
      choice = response["choices"].first
      expect(choice["message"]["tool_calls"]).to be_an(Array)
    end
  end
end
