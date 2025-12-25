# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::ResponsesResponse do
  let(:basic_response) do
    {
      "id" => "resp_123",
      "object" => "response",
      "created_at" => 1_234_567_890,
      "model" => "openai/o4-mini",
      "status" => "completed",
      "output" => [
        {
          "type" => "message",
          "id" => "msg_abc",
          "status" => "completed",
          "role" => "assistant",
          "content" => [
            {
              "type" => "output_text",
              "text" => "The answer is 4."
            }
          ]
        }
      ],
      "usage" => {
        "input_tokens" => 10,
        "output_tokens" => 5,
        "total_tokens" => 15
      }
    }
  end

  let(:response_with_reasoning) do
    {
      "id" => "resp_456",
      "object" => "response",
      "created_at" => 1_234_567_890,
      "model" => "openai/o4-mini",
      "status" => "completed",
      "output" => [
        {
          "type" => "reasoning",
          "id" => "rs_xyz",
          "summary" => [
            "First, I need to add 2 and 2.",
            "2 + 2 = 4",
            "The answer is 4."
          ],
          "encrypted_content" => "encrypted_data_here"
        },
        {
          "type" => "message",
          "id" => "msg_abc",
          "status" => "completed",
          "role" => "assistant",
          "content" => [
            {
              "type" => "output_text",
              "text" => "The answer is 4."
            }
          ]
        }
      ],
      "usage" => {
        "input_tokens" => 10,
        "output_tokens" => 50,
        "total_tokens" => 60,
        "output_tokens_details" => {
          "reasoning_tokens" => 45
        }
      }
    }
  end

  let(:response_with_tool_calls) do
    {
      "id" => "resp_789",
      "object" => "response",
      "created_at" => 1_234_567_890,
      "model" => "openai/o4-mini",
      "status" => "completed",
      "output" => [
        {
          "type" => "function_call",
          "id" => "fc_001",
          "call_id" => "call_abc123",
          "name" => "get_weather",
          "arguments" => '{"location": "San Francisco"}'
        },
        {
          "type" => "message",
          "id" => "msg_abc",
          "status" => "completed",
          "role" => "assistant",
          "content" => [
            {
              "type" => "output_text",
              "text" => "Let me check the weather for you."
            }
          ]
        }
      ],
      "usage" => {
        "input_tokens" => 20,
        "output_tokens" => 15,
        "total_tokens" => 35
      }
    }
  end

  describe "basic accessors" do
    subject(:response) { described_class.new(basic_response) }

    it "returns id" do
      expect(response.id).to eq("resp_123")
    end

    it "returns status" do
      expect(response.status).to eq("completed")
    end

    it "returns model" do
      expect(response.model).to eq("openai/o4-mini")
    end

    it "returns created_at" do
      expect(response.created_at).to eq(1_234_567_890)
    end

    it "returns output array" do
      expect(response.output).to be_an(Array)
      expect(response.output.length).to eq(1)
    end

    it "returns usage hash" do
      expect(response.usage).to be_a(Hash)
      expect(response.usage["total_tokens"]).to eq(15)
    end
  end

  describe "#content" do
    it "returns the assistant message text" do
      response = described_class.new(basic_response)
      expect(response.content).to eq("The answer is 4.")
    end

    it "returns nil when no message output exists" do
      response = described_class.new({ "output" => [] })
      expect(response.content).to be_nil
    end
  end

  describe "reasoning methods" do
    context "with reasoning" do
      subject(:response) { described_class.new(response_with_reasoning) }

      it "returns reasoning summary" do
        expect(response.reasoning_summary).to eq([
                                                   "First, I need to add 2 and 2.",
                                                   "2 + 2 = 4",
                                                   "The answer is 4."
                                                 ])
      end

      it "has_reasoning? returns true" do
        expect(response.has_reasoning?).to be true
      end

      it "returns reasoning_tokens" do
        expect(response.reasoning_tokens).to eq(45)
      end
    end

    context "without reasoning" do
      subject(:response) { described_class.new(basic_response) }

      it "returns empty array for reasoning_summary" do
        expect(response.reasoning_summary).to eq([])
      end

      it "has_reasoning? returns false" do
        expect(response.has_reasoning?).to be false
      end

      it "returns 0 for reasoning_tokens" do
        expect(response.reasoning_tokens).to eq(0)
      end
    end
  end

  describe "tool call methods" do
    context "with tool calls" do
      subject(:response) { described_class.new(response_with_tool_calls) }

      it "returns tool_calls as ResponsesToolCall objects" do
        expect(response.tool_calls).to be_an(Array)
        expect(response.tool_calls.length).to eq(1)
        expect(response.tool_calls.first).to be_a(OpenRouter::ResponsesToolCall)
        expect(response.tool_calls.first.name).to eq("get_weather")
      end

      it "returns tool_calls_raw as hashes" do
        expect(response.tool_calls_raw).to be_an(Array)
        expect(response.tool_calls_raw.first).to be_a(Hash)
        expect(response.tool_calls_raw.first["name"]).to eq("get_weather")
      end

      it "has_tool_calls? returns true" do
        expect(response.has_tool_calls?).to be true
      end
    end

    context "without tool calls" do
      subject(:response) { described_class.new(basic_response) }

      it "returns empty tool_calls array" do
        expect(response.tool_calls).to eq([])
      end

      it "has_tool_calls? returns false" do
        expect(response.has_tool_calls?).to be false
      end
    end
  end

  describe "#execute_tool_calls" do
    let(:multi_tool_response) do
      {
        "id" => "resp_multi",
        "status" => "completed",
        "output" => [
          {
            "type" => "function_call",
            "id" => "fc_001",
            "call_id" => "call_abc",
            "name" => "get_weather",
            "arguments" => '{"location": "NYC"}'
          },
          {
            "type" => "function_call",
            "id" => "fc_002",
            "call_id" => "call_def",
            "name" => "get_time",
            "arguments" => '{"timezone": "EST"}'
          }
        ]
      }
    end

    subject(:response) { described_class.new(multi_tool_response) }

    it "executes all tool calls and returns results" do
      results = response.execute_tool_calls do |name, _args|
        case name
        when "get_weather" then { temp: 72 }
        when "get_time" then "3:00 PM"
        end
      end

      expect(results.length).to eq(2)
      expect(results.all? { |r| r.is_a?(OpenRouter::ResponsesToolResult) }).to be true
      expect(results[0].result).to eq({ temp: 72 })
      expect(results[1].result).to eq("3:00 PM")
    end

    it "captures errors in results" do
      results = response.execute_tool_calls do |name, _args|
        raise "API error" if name == "get_weather"

        "ok"
      end

      expect(results[0].failure?).to be true
      expect(results[0].error).to eq("API error")
      expect(results[1].success?).to be true
    end
  end

  describe "#build_follow_up_input" do
    subject(:response) { described_class.new(response_with_tool_calls) }

    let(:tool_result) do
      tool_call = response.tool_calls.first
      OpenRouter::ResponsesToolResult.new(tool_call, { temperature: 68 })
    end

    it "builds input with string original_input" do
      input = response.build_follow_up_input(
        original_input: "What's the weather?",
        tool_results: [tool_result]
      )

      expect(input).to be_an(Array)
      expect(input.first["type"]).to eq("message")
      expect(input.first["role"]).to eq("user")
      expect(input.first["content"].first["text"]).to eq("What's the weather?")
    end

    it "includes function calls from the response" do
      input = response.build_follow_up_input(
        original_input: "What's the weather?",
        tool_results: [tool_result]
      )

      function_call = input.find { |i| i["type"] == "function_call" }
      expect(function_call).not_to be_nil
      expect(function_call["name"]).to eq("get_weather")
    end

    it "includes function call outputs" do
      input = response.build_follow_up_input(
        original_input: "What's the weather?",
        tool_results: [tool_result]
      )

      output_item = input.find { |i| i["type"] == "function_call_output" }
      expect(output_item).not_to be_nil
      expect(output_item["call_id"]).to eq("call_abc123")
    end

    it "includes assistant message if present" do
      input = response.build_follow_up_input(
        original_input: "What's the weather?",
        tool_results: [tool_result]
      )

      message = input.find { |i| i["type"] == "message" && i["role"] == "assistant" }
      expect(message).not_to be_nil
    end

    it "includes follow-up message when provided" do
      input = response.build_follow_up_input(
        original_input: "What's the weather?",
        tool_results: [tool_result],
        follow_up_message: "Is that cold?"
      )

      user_messages = input.select { |i| i["type"] == "message" && i["role"] == "user" }
      expect(user_messages.length).to eq(2)
      expect(user_messages.last["content"].first["text"]).to eq("Is that cold?")
    end

    it "handles array original_input" do
      original = [
        { "type" => "message", "role" => "user", "content" => [{ "type" => "input_text", "text" => "Hello" }] }
      ]

      input = response.build_follow_up_input(
        original_input: original,
        tool_results: [tool_result]
      )

      expect(input.first).to eq(original.first)
    end
  end

  describe "token methods" do
    subject(:response) { described_class.new(basic_response) }

    it "returns input_tokens" do
      expect(response.input_tokens).to eq(10)
    end

    it "returns output_tokens" do
      expect(response.output_tokens).to eq(5)
    end

    it "returns total_tokens" do
      expect(response.total_tokens).to eq(15)
    end
  end

  describe "hash-like access" do
    subject(:response) { described_class.new(basic_response) }

    it "allows bracket access to raw data" do
      expect(response["id"]).to eq("resp_123")
    end

    it "allows dig access to nested data" do
      expect(response.dig("usage", "total_tokens")).to eq(15)
    end
  end

  describe "nil handling" do
    it "handles nil input gracefully" do
      response = described_class.new(nil)
      expect(response.id).to be_nil
      expect(response.output).to eq([])
      expect(response.usage).to eq({})
      expect(response.content).to be_nil
    end

    it "handles empty hash gracefully" do
      response = described_class.new({})
      expect(response.id).to be_nil
      expect(response.output).to eq([])
      expect(response.total_tokens).to eq(0)
    end
  end
end
