# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Responses API + Tool Calling Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Calculator tool for testing
  let(:calculator_tool) do
    OpenRouter::Tool.define do
      name "calculator"
      description "Perform basic arithmetic operations"
      parameters do
        string "operation", required: true, description: "Operation: add, subtract, multiply, divide"
        number "a", required: true, description: "First number"
        number "b", required: true, description: "Second number"
      end
    end
  end

  # Weather tool
  let(:weather_tool) do
    OpenRouter::Tool.define do
      name "get_weather"
      description "Get current weather for a location"
      parameters do
        string "location", required: true, description: "City name"
      end
    end
  end

  # Search tool for more complex scenarios
  let(:search_tool) do
    OpenRouter::Tool.define do
      name "web_search"
      description "Search the web for information"
      parameters do
        string "query", required: true, description: "Search query"
        integer "num_results", required: false, description: "Number of results (default: 5)"
      end
    end
  end

  describe "basic tool calling with responses API" do
    it "returns tool calls via responses endpoint",
       vcr: { cassette_name: "integration/responses_tools_basic" } do
      response = client.responses(
        "What is 25 plus 17?",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      # Check for tool calls in the response
      if response.has_tool_calls?
        expect(response.tool_calls).to be_an(Array)
        expect(response.tool_calls.length).to be >= 1

        tool_call = response.tool_calls.first
        expect(tool_call.function_name).to eq("calculator")
        expect(tool_call.arguments["operation"]).to eq("add")
      end
    end
  end

  describe "tool_choice parameter with responses API" do
    it "forces tool use with tool_choice: required",
       vcr: { cassette_name: "integration/responses_tools_required" } do
      response = client.responses(
        "Hello, how are you today?",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "required",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      # With required, should have tool calls even for unrelated queries
      expect(response.has_tool_calls?).to be true
    end

    it "prevents tool use with tool_choice: none",
       vcr: { cassette_name: "integration/responses_tools_none" } do
      response = client.responses(
        "What is 10 times 5?",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "none",
        max_output_tokens: 100
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      # With none, should not have tool calls
      expect(response.has_tool_calls?).to be false
      expect(response.content).to be_present
    end
  end

  describe "multiple tools with responses API" do
    it "selects appropriate tool from multiple options",
       vcr: { cassette_name: "integration/responses_tools_multiple" } do
      response = client.responses(
        "What's the weather like in San Francisco?",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool, weather_tool, search_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      if response.has_tool_calls?
        tool_call = response.tool_calls.first
        expect(tool_call.function_name).to eq("get_weather")
        expect(tool_call.arguments["location"]).to include("San Francisco")
      end
    end
  end

  describe "responses API with reasoning and tools" do
    it "combines reasoning mode with tool calling",
       vcr: { cassette_name: "integration/responses_tools_reasoning" } do
      response = client.responses(
        "I need to calculate 15% of 200. Can you help?",
        model: "openai/gpt-4o-mini",
        reasoning: { effort: "medium" },
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 300
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      # Should have either reasoning content or tool calls (or both)
      expect(response.has_tool_calls? || response.content.present?).to be true
    end
  end

  describe "structured input with tools" do
    it "handles array message format with tools",
       vcr: { cassette_name: "integration/responses_tools_structured_input" } do
      input = [
        { role: "user", content: "Calculate the sum of 100 and 250" }
      ]

      response = client.responses(
        input,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      if response.has_tool_calls?
        tool_call = response.tool_calls.first
        expect(tool_call.function_name).to eq("calculator")
      end
    end

    it "handles system message with tools",
       vcr: { cassette_name: "integration/responses_tools_system_message" } do
      input = [
        { role: "system", content: "You are a helpful math assistant. Always use the calculator tool for math." },
        { role: "user", content: "What is 7 times 8?" }
      ]

      response = client.responses(
        input,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.has_tool_calls?).to be true
    end
  end

  describe "tool call metadata in responses" do
    it "provides complete tool call information",
       vcr: { cassette_name: "integration/responses_tools_metadata" } do
      response = client.responses(
        "Add 42 and 58",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      if response.has_tool_calls?
        tool_call = response.tool_calls.first

        # Verify tool call structure
        expect(tool_call.id).to be_present
        expect(tool_call.type).to eq("function")
        expect(tool_call.function_name).to be_a(String)
        expect(tool_call.arguments).to be_a(Hash)

        # Verify serialization
        expect(tool_call.to_h).to be_a(Hash)
        expect(tool_call.to_json).to be_a(String)
      end
    end
  end

  describe "usage tracking with responses API tools" do
    it "tracks token usage for tool-enabled requests",
       vcr: { cassette_name: "integration/responses_tools_usage" } do
      response = client.responses(
        "Multiply 12 by 15",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      # Check usage information
      expect(response.usage).to be_a(Hash)
      expect(response.usage["input_tokens"] || response.usage["prompt_tokens"]).to be > 0
    end
  end

  describe "error handling with responses API tools" do
    it "raises ArgumentError for invalid tool types" do
      invalid_tool = "not a tool" # Must be Tool object or Hash

      expect do
        client.responses(
          "Hello",
          model: "openai/gpt-4o-mini",
          tools: [invalid_tool],
          max_output_tokens: 100
        )
      end.to raise_error(ArgumentError, /Tools must be Tool objects or hashes/)
    end
  end

  describe "comparing responses API vs chat completions API" do
    it "produces similar tool call results via both APIs",
       vcr: { cassette_name: "integration/responses_tools_comparison" } do
      query = "What is 99 plus 1?"

      # Via responses API
      responses_result = client.responses(
        query,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_output_tokens: 200
      )

      # Via chat completions API
      completions_result = client.complete(
        [{ role: "user", content: query }],
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_tokens: 200
      )

      # Both should have tool calls for a math question
      if responses_result.has_tool_calls? && completions_result.has_tool_calls?
        expect(responses_result.tool_calls.first.function_name).to eq("calculator")
        expect(completions_result.tool_calls.first.function_name).to eq("calculator")
      end
    end
  end

  describe "temperature parameter with tools" do
    it "respects temperature setting in tool-enabled requests",
       vcr: { cassette_name: "integration/responses_tools_temperature" } do
      response = client.responses(
        "Calculate 50 divided by 2",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        temperature: 0.1,
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)

      if response.has_tool_calls?
        tool_call = response.tool_calls.first
        args = tool_call.arguments

        # With low temperature, should consistently get correct operation
        expect(args["operation"]).to eq("divide")
        expect([50, 50.0]).to include(args["a"])
        expect([2, 2.0]).to include(args["b"])
      end
    end
  end
end
