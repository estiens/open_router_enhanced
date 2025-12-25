# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::ResponsesToolCall do
  let(:tool_call_data) do
    {
      "type" => "function_call",
      "id" => "fc_12345",
      "call_id" => "call_abc123",
      "name" => "get_weather",
      "arguments" => '{"location":"San Francisco","units":"celsius"}'
    }
  end

  subject(:tool_call) { described_class.new(tool_call_data) }

  describe "#initialize" do
    it "extracts the id" do
      expect(tool_call.id).to eq("fc_12345")
    end

    it "extracts the call_id" do
      expect(tool_call.call_id).to eq("call_abc123")
    end

    it "extracts the name" do
      expect(tool_call.name).to eq("get_weather")
    end

    it "extracts the arguments string" do
      expect(tool_call.arguments_string).to eq('{"location":"San Francisco","units":"celsius"}')
    end

    context "with missing arguments" do
      let(:tool_call_data) do
        { "type" => "function_call", "id" => "fc_1", "call_id" => "call_1", "name" => "test" }
      end

      it "defaults to empty object string" do
        expect(tool_call.arguments_string).to eq("{}")
      end
    end
  end

  describe "#arguments" do
    it "parses the JSON arguments string" do
      expect(tool_call.arguments).to eq({
        "location" => "San Francisco",
        "units" => "celsius"
      })
    end

    it "memoizes the parsed arguments" do
      first_call = tool_call.arguments
      second_call = tool_call.arguments
      expect(first_call).to equal(second_call)
    end

    context "with invalid JSON" do
      let(:tool_call_data) do
        { "id" => "fc_1", "call_id" => "call_1", "name" => "test", "arguments" => "not json" }
      end

      it "raises ToolCallError" do
        expect { tool_call.arguments }.to raise_error(OpenRouter::ToolCallError)
      end
    end
  end

  describe "#function_name" do
    it "aliases name for consistency" do
      expect(tool_call.function_name).to eq("get_weather")
    end
  end

  describe "#execute" do
    it "raises ArgumentError without a block" do
      expect { tool_call.execute }.to raise_error(ArgumentError, /Block required/)
    end

    it "passes name and arguments to the block" do
      received_name = nil
      received_args = nil

      tool_call.execute do |name, args|
        received_name = name
        received_args = args
        "result"
      end

      expect(received_name).to eq("get_weather")
      expect(received_args).to eq({ "location" => "San Francisco", "units" => "celsius" })
    end

    it "returns a ResponsesToolResult on success" do
      result = tool_call.execute { |_n, _a| { temperature: 20 } }

      expect(result).to be_a(OpenRouter::ResponsesToolResult)
      expect(result.success?).to be true
      expect(result.result).to eq({ temperature: 20 })
      expect(result.tool_call).to eq(tool_call)
    end

    it "returns a failed ResponsesToolResult on error" do
      result = tool_call.execute { |_n, _a| raise "API error" }

      expect(result).to be_a(OpenRouter::ResponsesToolResult)
      expect(result.failure?).to be true
      expect(result.error).to eq("API error")
    end
  end

  describe "#to_input_item" do
    it "converts to function_call format for conversation continuation" do
      expect(tool_call.to_input_item).to eq({
        "type" => "function_call",
        "id" => "fc_12345",
        "call_id" => "call_abc123",
        "name" => "get_weather",
        "arguments" => '{"location":"San Francisco","units":"celsius"}'
      })
    end
  end

  describe "#to_h" do
    it "delegates to to_input_item" do
      expect(tool_call.to_h).to eq(tool_call.to_input_item)
    end
  end

  describe "#to_json" do
    it "serializes to JSON" do
      parsed = JSON.parse(tool_call.to_json)
      expect(parsed["name"]).to eq("get_weather")
      expect(parsed["call_id"]).to eq("call_abc123")
    end
  end
end

RSpec.describe OpenRouter::ResponsesToolResult do
  let(:tool_call) do
    OpenRouter::ResponsesToolCall.new({
      "id" => "fc_1",
      "call_id" => "call_xyz",
      "name" => "get_weather",
      "arguments" => "{}"
    })
  end

  describe "#initialize" do
    it "stores the tool_call reference" do
      result = described_class.new(tool_call, "success")
      expect(result.tool_call).to eq(tool_call)
    end

    it "stores the result" do
      result = described_class.new(tool_call, { data: 123 })
      expect(result.result).to eq({ data: 123 })
    end

    it "stores the error" do
      result = described_class.new(tool_call, nil, "something failed")
      expect(result.error).to eq("something failed")
    end
  end

  describe "#success?" do
    it "returns true when no error" do
      result = described_class.new(tool_call, "ok")
      expect(result.success?).to be true
    end

    it "returns false when error present" do
      result = described_class.new(tool_call, nil, "error")
      expect(result.success?).to be false
    end
  end

  describe "#failure?" do
    it "returns false when no error" do
      result = described_class.new(tool_call, "ok")
      expect(result.failure?).to be false
    end

    it "returns true when error present" do
      result = described_class.new(tool_call, nil, "error")
      expect(result.failure?).to be true
    end
  end

  describe "#to_input_item" do
    it "returns function_call_output format with hash result" do
      result = described_class.new(tool_call, { temperature: 72 })
      item = result.to_input_item

      expect(item["type"]).to eq("function_call_output")
      expect(item["call_id"]).to eq("call_xyz")
      expect(item["output"]).to eq('{"temperature":72}')
      expect(item["id"]).to match(/^fc_output_[a-f0-9]{16}$/)
    end

    it "returns string output directly for string results" do
      result = described_class.new(tool_call, "Hello world")
      item = result.to_input_item

      expect(item["output"]).to eq("Hello world")
    end

    it "returns error JSON for failed results" do
      result = described_class.new(tool_call, nil, "API timeout")
      item = result.to_input_item

      expect(item["output"]).to eq('{"error":"API timeout"}')
    end
  end

  describe ".success" do
    it "creates a successful result" do
      result = described_class.success(tool_call, { data: 1 })
      expect(result.success?).to be true
      expect(result.result).to eq({ data: 1 })
    end
  end

  describe ".failure" do
    it "creates a failed result" do
      result = described_class.failure(tool_call, "failed")
      expect(result.failure?).to be true
      expect(result.error).to eq("failed")
    end
  end
end
