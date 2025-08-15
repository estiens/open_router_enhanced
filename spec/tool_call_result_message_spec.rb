# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::ToolCall do
  describe "#to_result_message" do
    let(:tool_call) do
      OpenRouter::ToolCall.new({
                                 "id" => "call_123",
                                 "type" => "function",
                                 "function" => {
                                   "name" => "search_books",
                                   "arguments" => '{"query": "Ruby programming"}'
                                 }
                               })
    end

    it "returns valid tool role message format" do
      result = tool_call.to_result_message("Found 5 Ruby books")

      expect(result).to eq({
                             role: "tool",
                             tool_call_id: "call_123",
                             content: "Found 5 Ruby books"
                           })
    end

    it "does not include name field which can break OpenAI/OpenRouter tool calling" do
      result = tool_call.to_result_message("Some result")

      # Critical: name field should NOT be present as it can break multi-step tool calling
      expect(result).not_to have_key(:name)
      expect(result).not_to have_key("name")
    end

    it "converts non-string results to JSON" do
      result = tool_call.to_result_message({ "status" => "success", "count" => 5 })

      expect(result[:role]).to eq("tool")
      expect(result[:tool_call_id]).to eq("call_123")
      expect(result[:content]).to eq('{"status":"success","count":5}')
    end

    it "handles nil result" do
      result = tool_call.to_result_message(nil)

      expect(result[:role]).to eq("tool")
      expect(result[:tool_call_id]).to eq("call_123")
      expect(result[:content]).to eq("")
    end
  end
end
