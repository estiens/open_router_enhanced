# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Responses API", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

  describe "basic responses", vcr: { cassette_name: "responses_api_basic" } do
    it "returns a ResponsesResponse for a simple query" do
      response = client.responses(
        "What is 2 + 2? Reply with just the number.",
        model: "openai/gpt-4o-mini",
        max_output_tokens: 50
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.status).to eq("completed")
      expect(response.content).to include("4")
      expect(response.total_tokens).to be > 0
    end
  end

  describe "responses with reasoning", vcr: { cassette_name: "responses_api_reasoning" } do
    it "includes reasoning summary when effort is specified" do
      response = client.responses(
        "What is 15% of 80? Show your reasoning.",
        model: "openai/o4-mini",
        reasoning: { effort: "medium" },
        max_output_tokens: 500
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.status).to eq("completed")
      expect(response.content).to be_a(String)

      # Reasoning may or may not be present depending on model/API behavior
      if response.has_reasoning?
        expect(response.reasoning_summary).to be_an(Array)
        expect(response.reasoning_tokens).to be >= 0
      end
    end
  end

  describe "token usage tracking", vcr: { cassette_name: "responses_api_usage" } do
    it "tracks token usage correctly" do
      response = client.responses(
        "Say hello in exactly 5 words.",
        model: "openai/gpt-4o-mini",
        max_output_tokens: 50
      )

      expect(response.input_tokens).to be > 0
      expect(response.output_tokens).to be > 0
      expect(response.total_tokens).to eq(response.input_tokens + response.output_tokens)
    end
  end

  describe "structured input", vcr: { cassette_name: "responses_api_structured_input" } do
    it "accepts structured message array input" do
      structured_input = [
        {
          "type" => "message",
          "role" => "user",
          "content" => [
            { "type" => "input_text", "text" => "What color is the sky?" }
          ]
        }
      ]

      response = client.responses(
        structured_input,
        model: "openai/gpt-4o-mini",
        max_output_tokens: 50
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.content.downcase).to include("blue")
    end
  end

  describe "temperature parameter", vcr: { cassette_name: "responses_api_temperature" } do
    it "accepts temperature parameter" do
      response = client.responses(
        "Generate a random number between 1 and 10.",
        model: "openai/gpt-4o-mini",
        temperature: 0.0,
        max_output_tokens: 50
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.status).to eq("completed")
    end
  end

  describe "tool calling", vcr: { cassette_name: "responses_api_tool_calling" } do
    let(:weather_tool) do
      {
        type: "function",
        function: {
          name: "get_weather",
          description: "Get the current weather for a location",
          parameters: {
            type: "object",
            properties: {
              location: {
                type: "string",
                description: "The city name, e.g. San Francisco"
              },
              units: {
                type: "string",
                enum: %w[celsius fahrenheit],
                description: "Temperature units"
              }
            },
            required: ["location"]
          }
        }
      }
    end

    it "returns tool calls when model decides to use a tool" do
      response = client.responses(
        "What's the weather like in Tokyo?",
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.has_tool_calls?).to be true

      # Check tool call structure
      tool_call = response.tool_calls.first
      expect(tool_call).to be_a(OpenRouter::ResponsesToolCall)
      expect(tool_call.name).to eq("get_weather")
      expect(tool_call.arguments).to have_key("location")
      expect(tool_call.arguments["location"].downcase).to include("tokyo")
    end

    it "executes tool calls and builds follow-up input" do
      response = client.responses(
        "What's the weather like in Paris?",
        model: "openai/gpt-4o-mini",
        tools: [weather_tool],
        max_output_tokens: 200
      )

      expect(response.has_tool_calls?).to be true

      # Execute the tool call
      results = response.execute_tool_calls do |name, args|
        case name
        when "get_weather"
          { temperature: 18, condition: "partly cloudy", location: args["location"] }
        else
          { error: "Unknown tool" }
        end
      end

      expect(results.length).to eq(1)
      expect(results.first).to be_a(OpenRouter::ResponsesToolResult)
      expect(results.first.success?).to be true
      expect(results.first.result[:temperature]).to eq(18)

      # Build follow-up input
      follow_up = response.build_follow_up_input(
        original_input: "What's the weather like in Paris?",
        tool_results: results
      )

      expect(follow_up).to be_an(Array)
      expect(follow_up.find { |i| i["type"] == "function_call" }).not_to be_nil
      expect(follow_up.find { |i| i["type"] == "function_call_output" }).not_to be_nil
    end
  end

  describe "tool calling with tool_choice", vcr: { cassette_name: "responses_api_tool_choice" } do
    let(:calculator_tool) do
      {
        type: "function",
        function: {
          name: "calculate",
          description: "Perform a mathematical calculation",
          parameters: {
            type: "object",
            properties: {
              expression: {
                type: "string",
                description: "The math expression to evaluate"
              }
            },
            required: ["expression"]
          }
        }
      }
    end

    it "forces tool use with tool_choice required" do
      response = client.responses(
        "What is 42 times 17?",
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "required",
        max_output_tokens: 200
      )

      expect(response).to be_a(OpenRouter::ResponsesResponse)
      expect(response.has_tool_calls?).to be true

      tool_call = response.tool_calls.first
      expect(tool_call.name).to eq("calculate")
    end
  end
end
