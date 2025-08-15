# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Callback System" do
  let(:client) { OpenRouter::Client.new(access_token: "test-key") }

  describe "callback registration" do
    it "allows registering callbacks for valid events" do
      callback_called = false

      expect do
        client.on(:after_response) { |_response| callback_called = true }
      end.not_to raise_error

      expect(client.callbacks[:after_response].length).to eq(1)
    end

    it "raises error for invalid events" do
      expect do
        client.on(:invalid_event) { |data| }
      end.to raise_error(ArgumentError, /Invalid event: invalid_event/)
    end

    it "supports method chaining" do
      result = client.on(:after_response) { |response| }
                     .on(:before_request) { |params| }

      expect(result).to eq(client)
    end
  end

  describe "callback clearing" do
    before do
      client.on(:after_response) { |_response| "callback1" }
      client.on(:after_response) { |_response| "callback2" }
      client.on(:before_request) { |_params| "callback3" }
    end

    it "clears callbacks for specific event" do
      client.clear_callbacks(:after_response)

      expect(client.callbacks[:after_response]).to be_empty
      expect(client.callbacks[:before_request].length).to eq(1)
    end

    it "clears all callbacks when no event specified" do
      client.clear_callbacks

      expect(client.callbacks.values.all?(&:empty?)).to be true
    end

    it "supports method chaining" do
      result = client.clear_callbacks(:after_response)
      expect(result).to eq(client)
    end
  end

  describe "callback triggering" do
    let(:callback_data) { [] }

    before do
      client.on(:after_response) { |response| callback_data << "first: #{response&.class}" }
      client.on(:after_response) { |response| callback_data << "second: #{response&.class}" }
    end

    it "triggers all callbacks for an event" do
      mock_response = double("Response", class: "MockResponse")
      client.send(:trigger_callbacks, :after_response, mock_response)

      expect(callback_data).to eq([
                                    "first: MockResponse",
                                    "second: MockResponse"
                                  ])
    end

    it "handles callback errors gracefully" do
      client.on(:after_response) { |_response| raise "callback error" }

      expect do
        client.send(:trigger_callbacks, :after_response, "test")
      end.not_to raise_error

      # Other callbacks should still execute
      expect(callback_data.length).to eq(2)
    end

    it "handles nil data" do
      expect do
        client.send(:trigger_callbacks, :after_response, nil)
      end.not_to raise_error

      expect(callback_data).to eq(["first: ", "second: "])
    end
  end

  describe "callback integration with API calls" do
    let(:mock_response_data) do
      {
        "id" => "test-id",
        "choices" => [
          {
            "message" => { "content" => "Hello world", "role" => "assistant" },
            "finish_reason" => "stop"
          }
        ],
        "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
      }
    end

    before do
      # Mock the HTTP post method
      allow(client).to receive(:post).and_return(mock_response_data)
    end

    it "triggers before_request callback" do
      request_data = nil
      client.on(:before_request) { |params| request_data = params }

      client.complete([{ role: "user", content: "Hello" }])

      expect(request_data).to include(:messages)
      expect(request_data[:messages]).to eq([{ role: "user", content: "Hello" }])
    end

    it "triggers after_response callback" do
      response_data = nil
      client.on(:after_response) { |response| response_data = response }

      result = client.complete([{ role: "user", content: "Hello" }])

      expect(response_data).to eq(result)
      expect(response_data).to be_a(OpenRouter::Response)
    end

    it "doesn't trigger on_tool_call when no tool calls present" do
      tool_call_triggered = false
      client.on(:on_tool_call) { |_tool_calls| tool_call_triggered = true }

      client.complete([{ role: "user", content: "Hello" }])

      expect(tool_call_triggered).to be false
    end
  end

  describe "callback integration with tool calls" do
    let(:mock_response_with_tools) do
      {
        "id" => "test-id",
        "choices" => [
          {
            "message" => {
              "content" => nil,
              "role" => "assistant",
              "tool_calls" => [
                {
                  "id" => "call_123",
                  "type" => "function",
                  "function" => { "name" => "test_tool", "arguments" => "{}" }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      }
    end

    before do
      allow(client).to receive(:post).and_return(mock_response_with_tools)
    end

    it "triggers on_tool_call callback when tool calls are present" do
      tool_calls_data = nil
      client.on(:on_tool_call) { |tool_calls| tool_calls_data = tool_calls }

      client.complete([{ role: "user", content: "Use a tool" }])

      expect(tool_calls_data.length).to eq(1)
      expect(tool_calls_data.first).to be_a(OpenRouter::ToolCall)
      expect(tool_calls_data.first.name).to eq("test_tool")
    end
  end

  describe "callback integration with errors" do
    it "triggers on_error callback for configuration errors" do
      error_data = nil
      client.on(:on_error) { |error| error_data = error }

      allow(client).to receive(:post).and_raise(OpenRouter::ConfigurationError, "test error")

      expect do
        client.complete([{ role: "user", content: "Hello" }])
      end.to raise_error(OpenRouter::ServerError)

      expect(error_data).to be_a(OpenRouter::ConfigurationError)
      expect(error_data.message).to eq("test error")
    end

    it "triggers on_error callback for Faraday errors" do
      error_data = nil
      client.on(:on_error) { |error| error_data = error }

      allow(client).to receive(:post).and_raise(Faraday::BadRequestError.new("Bad request"))

      expect do
        client.complete([{ role: "user", content: "Hello" }])
      end.to raise_error(OpenRouter::ServerError)

      expect(error_data).to be_a(Faraday::BadRequestError)
    end
  end
end
