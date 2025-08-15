# frozen_string_literal: true

RSpec.describe OpenRouter::Client do
  let(:client) do
    OpenRouter::Client.new(access_token: "test_token")
  end

  let(:mock_response) do
    {
      "id" => "chatcmpl-123",
      "object" => "chat.completion",
      "created" => 1_677_652_288,
      "model" => "gpt-3.5-turbo",
      "choices" => [
        {
          "index" => 0,
          "message" => {
            "role" => "assistant",
            "content" => "Hello! How can I help you today?"
          },
          "finish_reason" => "stop"
        }
      ],
      "usage" => {
        "prompt_tokens" => 12,
        "completion_tokens" => 8,
        "total_tokens" => 20
      }
    }
  end

  describe "#complete with tools" do
    let(:search_tool) do
      OpenRouter::Tool.define do
        name "search_books"
        description "Search for books"
        parameters do
          string :query, required: true, description: "Search query"
          integer :limit, description: "Maximum results"
        end
      end
    end

    let(:tool_response) do
      mock_response.merge(
        "choices" => [
          {
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => nil,
              "tool_calls" => [
                {
                  "id" => "call_abc123",
                  "type" => "function",
                  "function" => {
                    "name" => "search_books",
                    "arguments" => '{"query": "Ruby programming", "limit": 5}'
                  }
                }
              ]
            },
            "finish_reason" => "tool_calls"
          }
        ]
      )
    end

    it "includes tools in the request" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          tools: [search_tool.to_h],
          tool_choice: "auto"
        )
      ).and_return(mock_response)

      messages = [{ role: "user", content: "Search for Ruby books" }]
      client.complete(messages, tools: [search_tool], tool_choice: "auto")
    end

    it "handles Tool objects and hashes" do
      tool_hash = {
        type: "function",
        function: {
          name: "test_tool",
          description: "A test tool",
          parameters: { type: "object", properties: {} }
        }
      }

      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          tools: [search_tool.to_h, tool_hash]
        )
      ).and_return(mock_response)

      messages = [{ role: "user", content: "Test" }]
      client.complete(messages, tools: [search_tool, tool_hash])
    end

    it "returns Response object with tool calls" do
      allow(client).to receive(:post).and_return(tool_response)

      messages = [{ role: "user", content: "Search for Ruby books" }]
      response = client.complete(messages, tools: [search_tool])

      expect(response).to be_a(OpenRouter::Response)
      expect(response.has_tool_calls?).to be true
      expect(response.tool_calls.first.name).to eq("search_books")
    end
  end

  describe "#complete with structured outputs" do
    let(:weather_schema) do
      OpenRouter::Schema.define("weather") do
        string :location, required: true, description: "City name"
        number :temperature, required: true, description: "Temperature"
        string :conditions, required: true, description: "Weather conditions"
      end
    end

    let(:structured_response) do
      mock_response.merge(
        "choices" => [
          {
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => '{"location": "London", "temperature": 18, "conditions": "Partly cloudy"}'
            },
            "finish_reason" => "stop"
          }
        ]
      )
    end

    it "includes response_format in the request with Schema object" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          response_format: {
            type: "json_schema",
            json_schema: weather_schema.to_h
          }
        )
      ).and_return(mock_response)

      messages = [{ role: "user", content: "What's the weather in London?" }]
      client.complete(messages, response_format: weather_schema)
    end

    it "includes response_format in the request with hash format" do
      response_format = {
        type: "json_schema",
        json_schema: weather_schema
      }

      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          response_format: {
            type: "json_schema",
            json_schema: weather_schema.to_h
          }
        )
      ).and_return(mock_response)

      messages = [{ role: "user", content: "What's the weather in London?" }]
      client.complete(messages, response_format:)
    end

    it "returns Response object with structured output" do
      allow(client).to receive(:post).and_return(structured_response)

      messages = [{ role: "user", content: "What's the weather in London?" }]
      response = client.complete(messages, response_format: weather_schema)

      expect(response).to be_a(OpenRouter::Response)
      expect(response.structured_output).to be_a(Hash)
      expect(response.structured_output["location"]).to eq("London")
    end
  end

  describe "#complete backward compatibility" do
    it "maintains backward compatibility for basic requests" do
      allow(client).to receive(:post).and_return(mock_response)

      messages = [{ role: "user", content: "Hello" }]
      response = client.complete(messages)

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to eq("Hello! How can I help you today?")

      # Should still work as hash for backward compatibility
      expect(response["id"]).to eq("chatcmpl-123")
      expect(response.dig("choices", 0, "message", "content")).to eq("Hello! How can I help you today?")
    end

    it "handles extras parameter" do
      expect(client).to receive(:post).with(
        path: "/chat/completions",
        parameters: hash_including(
          max_tokens: 100,
          temperature: 0.7
        )
      ).and_return(mock_response)

      messages = [{ role: "user", content: "Hello" }]
      client.complete(messages, extras: { max_tokens: 100, temperature: 0.7 })
    end
  end

  describe "error handling" do
    it "raises ServerError for API errors" do
      error_response = {
        "error" => {
          "message" => "Invalid API key",
          "type" => "invalid_request_error"
        }
      }

      allow(client).to receive(:post).and_return(error_response)

      expect do
        client.complete([{ role: "user", content: "Hello" }])
      end.to raise_error(OpenRouter::ServerError, "Invalid API key")
    end

    it "raises ServerError for empty responses" do
      allow(client).to receive(:post).and_return(nil)

      expect do
        client.complete([{ role: "user", content: "Hello" }])
      end.to raise_error(OpenRouter::ServerError, /Empty response/)
    end
  end

  describe "parameter validation" do
    it "validates tool parameters" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          tools: ["invalid tool"]
        )
      end.to raise_error(ArgumentError, /Tools must be/)
    end
  end
end
