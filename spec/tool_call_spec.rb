# frozen_string_literal: true

RSpec.describe OpenRouter::ToolCall do
  let(:tool_call_data) do
    {
      "id" => "call_abc123",
      "type" => "function",
      "function" => {
        "name" => "search_books",
        "arguments" => '{"query": "Ruby programming", "limit": 5}'
      }
    }
  end

  describe "#initialize" do
    it "parses tool call data correctly" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      expect(tool_call.id).to eq("call_abc123")
      expect(tool_call.type).to eq("function")
      expect(tool_call.function_name).to eq("search_books")
    end

    it "raises error for invalid data" do
      invalid_data = { "id" => "call_123", "type" => "function" }

      expect do
        OpenRouter::ToolCall.new(invalid_data)
      end.to raise_error(OpenRouter::ToolCallError, /missing function/)
    end
  end

  describe "#arguments" do
    it "parses JSON arguments correctly" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      expect(tool_call.arguments).to eq({
                                          "query" => "Ruby programming",
                                          "limit" => 5
                                        })
    end

    it "raises error for invalid JSON" do
      bad_data = tool_call_data.dup
      bad_data["function"]["arguments"] = "invalid json"

      tool_call = OpenRouter::ToolCall.new(bad_data)

      expect do
        tool_call.arguments
      end.to raise_error(OpenRouter::ToolCallError, /parse/)
    end

    it "caches parsed arguments" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      args1 = tool_call.arguments
      args2 = tool_call.arguments

      expect(args1).to be(args2) # Same object
    end
  end

  describe "#execute" do
    it "executes with block and returns result" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      result = tool_call.execute do |name, args|
        expect(name).to eq("search_books")
        expect(args["query"]).to eq("Ruby programming")
        "Found 3 books"
      end

      expect(result).to be_a(OpenRouter::ToolResult)
      expect(result.result).to eq("Found 3 books")
      expect(result.success?).to be true
    end

    it "requires a block" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      expect do
        tool_call.execute
      end.to raise_error(ArgumentError, /Block required/)
    end
  end

  describe "#to_message" do
    it "converts to assistant message format" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      message = tool_call.to_message

      expect(message[:role]).to eq("assistant")
      expect(message[:content]).to be_nil
      expect(message[:tool_calls]).to be_an(Array)
      expect(message[:tool_calls].first[:id]).to eq("call_abc123")
    end
  end

  describe "#to_result_message" do
    it "converts result to tool message format" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      message = tool_call.to_result_message("Search completed")

      expect(message[:role]).to eq("tool")
      expect(message[:tool_call_id]).to eq("call_abc123")
      expect(message).not_to have_key(:name) # Name should not be included per OpenRouter/OpenAI spec
      expect(message[:content]).to eq("Search completed")
    end

    it "converts non-string results to JSON" do
      tool_call = OpenRouter::ToolCall.new(tool_call_data)

      result = { books: ["Book 1", "Book 2"] }
      message = tool_call.to_result_message(result)

      expect(message[:content]).to eq(result.to_json)
    end
  end
end

RSpec.describe OpenRouter::ToolResult do
  let(:tool_call_data) do
    {
      "id" => "call_123",
      "type" => "function",
      "function" => {
        "name" => "test_tool",
        "arguments" => "{}"
      }
    }
  end

  let(:tool_call) { OpenRouter::ToolCall.new(tool_call_data) }

  describe ".success" do
    it "creates successful result" do
      result = OpenRouter::ToolResult.success(tool_call, "Success!")

      expect(result.success?).to be true
      expect(result.failure?).to be false
      expect(result.result).to eq("Success!")
      expect(result.error).to be_nil
    end
  end

  describe ".failure" do
    it "creates failed result" do
      result = OpenRouter::ToolResult.failure(tool_call, "Error occurred")

      expect(result.success?).to be false
      expect(result.failure?).to be true
      expect(result.result).to be_nil
      expect(result.error).to eq("Error occurred")
    end
  end

  describe "#to_message" do
    it "converts to tool message with result" do
      result = OpenRouter::ToolResult.success(tool_call, "Success!")
      message = result.to_message

      expect(message[:role]).to eq("tool")
      expect(message[:content]).to eq("Success!")
    end

    it "converts to tool message with error" do
      result = OpenRouter::ToolResult.failure(tool_call, "Failed!")
      message = result.to_message

      expect(message[:role]).to eq("tool")
      expect(message[:content]).to eq("Failed!")
    end
  end
end
