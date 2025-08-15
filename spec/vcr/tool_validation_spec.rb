# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Tool Validation", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Simple calculator tool for testing validation
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

  # Tool with array of objects parameter (new DSL feature)
  let(:data_processor_tool) do
    OpenRouter::Tool.define do
      name "process_data"
      description "Process an array of data objects"
      parameters do
        array "items", required: true, description: "Array of items to process" do
          items do
            object do
              string "name", required: true, description: "Item name"
              number "value", required: true, description: "Item value"
              string "category", required: false, description: "Item category"
            end
          end
        end
      end
    end
  end

  describe "tool call validation", vcr: { cassette_name: "tool_validation_basic" } do
    it "validates successful tool calls with correct arguments" do
      messages = [
        { role: "user", content: "Calculate 15 + 27" }
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

      tool_call = response.tool_calls.first
      expect(tool_call).to be_a(OpenRouter::ToolCall)
      expect(tool_call.function_name).to eq("calculator")

      # Test our new validation methods
      expect(tool_call.valid?(tools: [calculator_tool])).to be true
      expect(tool_call.validation_errors(tools: [calculator_tool])).to be_empty
    end
  end

  describe "array of objects DSL feature", vcr: { cassette_name: "tool_validation_array_objects" } do
    it "successfully handles array of objects parameters" do
      messages = [
        { role: "user", content: "Process this data: [{name: 'item1', value: 10}, {name: 'item2', value: 20}]" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [data_processor_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response).to be_a(OpenRouter::Response)

      # Verify the tool definition includes proper array structure
      tool_def = data_processor_tool.to_h
      items_param = tool_def[:function][:parameters][:properties]["items"]

      expect(items_param[:type]).to eq("array")
      expect(items_param[:items][:type]).to eq("object")
      expect(items_param[:items][:properties]).to have_key("name")
      expect(items_param[:items][:properties]).to have_key("value")
      expect(items_param[:items][:required]).to eq(%w[name value])
    end
  end

  describe "to_result_message without name field", vcr: { cassette_name: "tool_validation_result_message" } do
    it "generates result messages without name field (fixed bug)" do
      messages = [
        { role: "user", content: "What is 10 * 5?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response.has_tool_calls?).to be true

      tool_call = response.tool_calls.first
      result_message = tool_call.to_result_message("50")

      # Should NOT include name field (this was the bug we fixed)
      expect(result_message).to eq({
                                     role: "tool",
                                     tool_call_id: tool_call.id,
                                     content: "50"
                                   })
      expect(result_message).not_to have_key(:name)
    end
  end

  describe "conversation continuation with validation", vcr: { cassette_name: "tool_validation_conversation" } do
    it "continues conversation with validated tool results" do
      # First request with tool call
      initial_messages = [
        { role: "user", content: "Calculate 8 + 12" }
      ]

      first_response = client.complete(
        initial_messages,
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(first_response.has_tool_calls?).to be true
      tool_call = first_response.tool_calls.first

      # Validate the tool call
      expect(tool_call.valid?(tools: [calculator_tool])).to be true

      # Continue conversation with tool result
      continued_messages = initial_messages + [
        first_response.to_message,
        tool_call.to_result_message("20"),
        { role: "user", content: "Now multiply that result by 3" }
      ]

      final_response = client.complete(
        continued_messages,
        model: "openai/gpt-4o-mini",
        extras: { max_tokens: 500 }
      )

      expect(final_response).to be_a(OpenRouter::Response)
      expect(final_response.has_content?).to be true
    end
  end
end
