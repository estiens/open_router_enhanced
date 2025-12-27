# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Multi-Turn Tool Conversations Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Calculator tool for arithmetic
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

  # Weather tool for location queries
  let(:weather_tool) do
    OpenRouter::Tool.define do
      name "get_weather"
      description "Get current weather for a location"
      parameters do
        string "location", required: true, description: "City name"
        string "units", required: false, description: "Temperature units: celsius or fahrenheit"
      end
    end
  end

  # Database lookup tool
  let(:database_tool) do
    OpenRouter::Tool.define do
      name "lookup_user"
      description "Look up user information by ID"
      parameters do
        string "user_id", required: true, description: "The user ID to look up"
      end
    end
  end

  def execute_tool(tool_call)
    case tool_call.function_name
    when "calculator"
      args = tool_call.arguments
      result = case args["operation"]
               when "add" then args["a"] + args["b"]
               when "subtract" then args["a"] - args["b"]
               when "multiply" then args["a"] * args["b"]
               when "divide" then args["a"].to_f / args["b"]
               else "Unknown operation"
               end
      result.to_s
    when "get_weather"
      args = tool_call.arguments
      units = args["units"] || "celsius"
      temp = units == "fahrenheit" ? "72°F" : "22°C"
      "Weather in #{args["location"]}: Sunny, #{temp}"
    when "lookup_user"
      args = tool_call.arguments
      "User #{args["user_id"]}: John Doe, john@example.com, Premium member"
    else
      "Unknown tool"
    end
  end

  describe "single tool call round-trip" do
    it "completes full conversation: request → tool_call → result → response",
       vcr: { cassette_name: "integration/multi_turn_single_tool" } do
      # Turn 1: User asks a question
      messages = [
        { role: "user", content: "What is 15 multiplied by 7?" }
      ]

      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response1.has_tool_calls?).to be true
      tool_call = response1.tool_calls.first
      expect(tool_call.function_name).to eq("calculator")

      # Execute the tool
      result = execute_tool(tool_call)
      expect(result).to eq("105")

      # Turn 2: Continue with tool result
      messages << response1.to_message
      messages << {
        role: "tool",
        tool_call_id: tool_call.id,
        content: result
      }

      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 100 }
      )

      expect(response2.has_content?).to be true
      expect(response2.content).to include("105")
    end
  end

  describe "multiple sequential tool calls" do
    it "handles multiple tool calls in sequence across turns",
       vcr: { cassette_name: "integration/multi_turn_sequential", record: :none },
       skip: "Cassette needs re-recording with VCR_RECORD_NEW=true" do
      messages = [
        { role: "user", content: "First add 10 and 20, then multiply the result by 3" }
      ]

      # Turn 1: First calculation
      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 300 }
      )

      expect(response1.has_tool_calls?).to be true

      # Execute all tool calls from turn 1
      response1.tool_calls.each do |tc|
        result = execute_tool(tc)
        messages << response1.to_message unless messages.last[:role] == "assistant"
        messages << {
          role: "tool",
          tool_call_id: tc.id,
          content: result
        }
      end

      # Turn 2: Continue for second calculation if needed
      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 300 }
      )

      # May have another tool call or final answer
      if response2.has_tool_calls?
        response2.tool_calls.each do |tc|
          result = execute_tool(tc)
          messages << response2.to_message unless messages.last[:role] == "assistant"
          messages << {
            role: "tool",
            tool_call_id: tc.id,
            content: result
          }
        end

        # Final turn
        response3 = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          tools: [calculator_tool],
          extras: { max_tokens: 100 }
        )

        expect(response3.has_content?).to be true
        # Should contain the result (90) or acknowledge the calculation
        expect(response3.content).to match(/90|result|answer/i)
      else
        # Direct answer from response2
        expect(response2.content).to match(/90|result|answer/i)
      end
    end
  end

  describe "parallel tool calls in single turn" do
    it "handles multiple tool calls in a single response",
       vcr: { cassette_name: "integration/multi_turn_parallel" } do
      messages = [
        { role: "user", content: "What is 5+5 and what is 10*10? Calculate both." }
      ]

      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 400 }
      )

      expect(response1.has_tool_calls?).to be true
      # May have 1 or 2 tool calls depending on model behavior
      expect(response1.tool_calls.length).to be >= 1

      # Execute all tool calls
      tool_results = response1.tool_calls.map do |tc|
        {
          role: "tool",
          tool_call_id: tc.id,
          content: execute_tool(tc)
        }
      end

      # Continue conversation with all results
      messages << response1.to_message
      messages.concat(tool_results)

      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 150 }
      )

      expect(response2.has_content?).to be true
      # Should mention both results
      content_lower = response2.content.downcase
      expect(content_lower).to include("10").or include("100")
    end
  end

  describe "multi-tool conversation" do
    it "uses different tools across a conversation",
       vcr: { cassette_name: "integration/multi_turn_multi_tool" } do
      messages = [
        { role: "user", content: "Look up user 12345 and tell me their name" }
      ]

      # Turn 1: Database lookup
      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool, database_tool, weather_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response1.has_tool_calls?).to be true
      tool_call1 = response1.tool_calls.first
      expect(tool_call1.function_name).to eq("lookup_user")

      result1 = execute_tool(tool_call1)

      messages << response1.to_message
      messages << {
        role: "tool",
        tool_call_id: tool_call1.id,
        content: result1
      }

      # Turn 2: Follow-up
      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool, database_tool, weather_tool],
        extras: { max_tokens: 100 }
      )

      expect(response2.has_content?).to be true
      expect(response2.content).to include("John Doe")
    end
  end

  describe "tool conversation with context retention" do
    it "maintains conversation context across tool calls",
       vcr: { cassette_name: "integration/multi_turn_context" } do
      messages = [
        { role: "system", content: "You are a helpful math assistant. Always show your work." },
        { role: "user", content: "I need to calculate 25 + 17" }
      ]

      # First calculation
      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response1.has_tool_calls?).to be true
      tool_call1 = response1.tool_calls.first
      result1 = execute_tool(tool_call1)

      messages << response1.to_message
      messages << { role: "tool", tool_call_id: tool_call1.id, content: result1 }

      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 150 }
      )

      expect(response2.content).to include("42")

      # Follow-up question referencing previous result
      messages << { role: "assistant", content: response2.content }
      messages << { role: "user", content: "Now double that result" }

      response3 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      if response3.has_tool_calls?
        tool_call3 = response3.tool_calls.first
        result3 = execute_tool(tool_call3)

        messages << response3.to_message
        messages << { role: "tool", tool_call_id: tool_call3.id, content: result3 }

        response4 = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          tools: [calculator_tool],
          extras: { max_tokens: 100 }
        )

        expect(response4.content).to include("84")
      else
        expect(response3.content).to include("84")
      end
    end
  end

  describe "tool error handling in conversation" do
    it "gracefully handles tool execution errors",
       vcr: { cassette_name: "integration/multi_turn_tool_error" } do
      messages = [
        { role: "user", content: "Divide 10 by 0" }
      ]

      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response1.has_tool_calls?).to be true
      tool_call = response1.tool_calls.first

      # Simulate error result
      error_result = "Error: Division by zero is undefined"

      messages << response1.to_message
      messages << {
        role: "tool",
        tool_call_id: tool_call.id,
        content: error_result
      }

      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 150 }
      )

      expect(response2.has_content?).to be true
      # Model should acknowledge the error
      expect(response2.content.downcase).to match(/cannot|undefined|error|zero|impossible/i)
    end
  end

  describe "ToolCall and ToolResult helpers" do
    it "uses execute method for cleaner tool execution flow",
       vcr: { cassette_name: "integration/multi_turn_execute_helper" } do
      messages = [
        { role: "user", content: "Calculate 8 times 9" }
      ]

      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response1.has_tool_calls?).to be true
      tool_call = response1.tool_calls.first

      # Use the execute helper
      tool_result = tool_call.execute do |name, args|
        case name
        when "calculator"
          case args["operation"]
          when "multiply" then args["a"] * args["b"]
          else 0
          end
        end
      end

      expect(tool_result).to be_a(OpenRouter::ToolResult)
      expect(tool_result.success?).to be true
      expect(tool_result.result).to eq(72)

      # Use to_message helpers
      messages << response1.to_message
      messages << tool_result.to_message

      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 100 }
      )

      expect(response2.content).to include("72")
    end
  end

  describe "callbacks during multi-turn tool conversations" do
    it "triggers callbacks correctly across multiple turns",
       vcr: { cassette_name: "integration/multi_turn_callbacks" } do
      request_count = 0
      tool_call_count = 0

      client.on(:before_request) { request_count += 1 }
      client.on(:on_tool_call) { |tools| tool_call_count += tools.length }

      messages = [
        { role: "user", content: "What is 3 + 4?" }
      ]

      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(request_count).to eq(1)
      expect(tool_call_count).to be >= 1 if response1.has_tool_calls?

      if response1.has_tool_calls?
        tool_call = response1.tool_calls.first
        messages << response1.to_message
        messages << { role: "tool", tool_call_id: tool_call.id, content: "7" }

        client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          tools: [calculator_tool],
          extras: { max_tokens: 100 }
        )

        expect(request_count).to eq(2)
      end
    end
  end
end
