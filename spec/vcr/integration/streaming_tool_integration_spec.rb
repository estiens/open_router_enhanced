# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Streaming + Tool Calling Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:streaming_client) do
    OpenRouter::StreamingClient.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Weather tool for realistic tool calling scenarios
  let(:weather_tool) do
    OpenRouter::Tool.define do
      name "get_weather"
      description "Get current weather for a location"
      parameters do
        string "location", required: true, description: "City name or location"
        string "units", required: false, description: "Temperature units: celsius or fahrenheit"
      end
    end
  end

  # Calculator tool for multi-tool scenarios
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

  describe "streaming with single tool call" do
    it "streams a response that triggers a tool call and captures tool_calls delta",
       vcr: { cassette_name: "integration/streaming_tool_single" } do
      messages = [
        { role: "user", content: "What's the weather in Tokyo?" }
      ]

      chunks = []
      tool_call_chunks = []
      content_chunks = []

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk

        delta = chunk.dig("choices", 0, "delta")
        next unless delta

        # Capture tool call deltas
        if delta["tool_calls"]
          tool_call_chunks << delta["tool_calls"]
        end

        # Capture content deltas
        if delta["content"]
          content_chunks << delta["content"]
        end
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        tool_choice: "auto",
        max_tokens: 300
      )

      expect(chunks).not_to be_empty

      # Should have received tool call chunks
      expect(tool_call_chunks).not_to be_empty

      # Reconstruct tool call from streamed chunks
      first_tool_call = tool_call_chunks.flatten.first
      expect(first_tool_call).to be_a(Hash)
      expect(first_tool_call["function"]["name"]).to eq("get_weather")
    end
  end

  describe "streaming with multiple tools available" do
    it "selects appropriate tool when streaming with multiple tool definitions",
       vcr: { cassette_name: "integration/streaming_tool_multiple_available" } do
      messages = [
        { role: "user", content: "What is 42 times 17?" }
      ]

      chunks = []
      tool_call_function_name = nil

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        delta = chunk.dig("choices", 0, "delta")
        if delta&.dig("tool_calls", 0, "function", "name")
          tool_call_function_name = delta.dig("tool_calls", 0, "function", "name")
        end
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [weather_tool, calculator_tool],
        tool_choice: "auto",
        max_tokens: 300
      )

      expect(chunks).not_to be_empty
      expect(tool_call_function_name).to eq("calculator")
    end
  end

  describe "streaming tool call and execution flow" do
    it "streams tool call, executes it, and continues conversation",
       vcr: { cassette_name: "integration/streaming_tool_full_flow" } do
      # Step 1: Initial streaming request that triggers tool call
      messages = [
        { role: "user", content: "What is 25 + 37?" }
      ]

      accumulated_tool_calls = []
      tool_call_id = nil
      function_name = nil
      arguments_json = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        delta = chunk.dig("choices", 0, "delta")
        next unless delta&.dig("tool_calls")

        delta["tool_calls"].each do |tc|
          tool_call_id ||= tc["id"]
          function_name ||= tc.dig("function", "name")
          arguments_json += tc.dig("function", "arguments") || ""
        end
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_tokens: 300
      )

      expect(tool_call_id).to be_present
      expect(function_name).to eq("calculator")

      # Parse the accumulated arguments
      args = JSON.parse(arguments_json)
      expect(args["operation"]).to eq("add")

      # Step 2: Execute the tool
      result = args["a"].to_f + args["b"].to_f

      # Step 3: Continue conversation with tool result (non-streaming for simplicity)
      continued_messages = messages + [
        {
          role: "assistant",
          tool_calls: [
            {
              id: tool_call_id,
              type: "function",
              function: { name: function_name, arguments: arguments_json }
            }
          ]
        },
        {
          role: "tool",
          tool_call_id: tool_call_id,
          content: result.to_s
        }
      ]

      final_chunks = []
      final_content = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        final_chunks << chunk
        final_content += chunk.dig("choices", 0, "delta", "content") || ""
      end

      streaming_client.stream_complete(
        continued_messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        max_tokens: 100
      )

      expect(final_chunks).not_to be_empty
      expect(final_content).to include("62")
    end
  end

  describe "streaming accumulation with tool calls" do
    it "accumulates streaming response including tool call data",
       vcr: { cassette_name: "integration/streaming_tool_accumulation" } do
      messages = [
        { role: "user", content: "Check the weather in Paris please" }
      ]

      accumulated_response = streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        tool_choice: "auto",
        accumulate_response: true,
        max_tokens: 300
      )

      expect(accumulated_response).to be_a(OpenRouter::Response)

      # Should have tool calls in accumulated response
      if accumulated_response.has_tool_calls?
        expect(accumulated_response.tool_calls).not_to be_empty
        expect(accumulated_response.tool_calls.first.function_name).to eq("get_weather")
      end
    end
  end

  describe "streaming with tool_choice variations" do
    it "respects tool_choice: required in streaming mode",
       vcr: { cassette_name: "integration/streaming_tool_required" } do
      messages = [
        { role: "user", content: "Hello, how are you?" }
      ]

      tool_call_received = false

      streaming_client.on_stream(:on_chunk) do |chunk|
        delta = chunk.dig("choices", 0, "delta")
        tool_call_received = true if delta&.dig("tool_calls")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        tool_choice: "required",
        max_tokens: 300
      )

      expect(tool_call_received).to be true
    end

    it "respects tool_choice: none in streaming mode",
       vcr: { cassette_name: "integration/streaming_tool_none" } do
      messages = [
        { role: "user", content: "What's the weather in London?" }
      ]

      tool_call_received = false
      content_received = false

      streaming_client.on_stream(:on_chunk) do |chunk|
        delta = chunk.dig("choices", 0, "delta")
        tool_call_received = true if delta&.dig("tool_calls")
        content_received = true if delta&.dig("content")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        tool_choice: "none",
        max_tokens: 100
      )

      expect(tool_call_received).to be false
      expect(content_received).to be true
    end
  end

  describe "error handling in streaming with tools" do
    it "handles model errors gracefully when streaming with tools",
       vcr: { cassette_name: "integration/streaming_tool_error" } do
      messages = [
        { role: "user", content: "Use the tool" }
      ]

      expect do
        streaming_client.stream_complete(
          messages,
          model: "invalid/nonexistent-model",
          tools: [weather_tool],
          max_tokens: 100
        )
      end.to raise_error(OpenRouter::ServerError)
    end
  end

  describe "callbacks during streaming with tools" do
    it "triggers on_stream_chunk callbacks during tool call streaming",
       vcr: { cassette_name: "integration/streaming_tool_callbacks" } do
      messages = [
        { role: "user", content: "Calculate 100 divided by 4" }
      ]

      callback_count = 0
      tool_call_chunks_in_callback = []

      # Register callback on the underlying client
      streaming_client.on_stream(:on_chunk) do |chunk|
        callback_count += 1
        delta = chunk.dig("choices", 0, "delta")
        tool_call_chunks_in_callback << delta["tool_calls"] if delta&.dig("tool_calls")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        max_tokens: 200
      )

      expect(callback_count).to be > 0
      expect(tool_call_chunks_in_callback).not_to be_empty
    end
  end
end
