# frozen_string_literal: true

RSpec.describe OpenRouter::Response do
  let(:basic_response) do
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

  let(:tool_call_response) do
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
            "content" => nil,
            "tool_calls" => [
              {
                "id" => "call_abc123",
                "type" => "function",
                "function" => {
                  "name" => "search_books",
                  "arguments" => '{"query": "Ruby programming"}'
                }
              }
            ]
          },
          "finish_reason" => "tool_calls"
        }
      ]
    }
  end

  let(:structured_response) do
    {
      "id" => "chatcmpl-123",
      "object" => "chat.completion",
      "created" => 1_677_652_288,
      "model" => "gpt-4",
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
    }
  end

  describe "#initialize" do
    it "wraps hash response" do
      response = OpenRouter::Response.new(basic_response)
      expect(response.id).to eq("chatcmpl-123")
      expect(response.model).to eq("gpt-3.5-turbo")
    end

    it "handles non-hash input" do
      response = OpenRouter::Response.new("not a hash")
      expect(response.to_h).to eq({})
    end
  end

  describe "basic accessors" do
    let(:response) { OpenRouter::Response.new(basic_response) }

    it "provides access to response fields" do
      expect(response.id).to eq("chatcmpl-123")
      expect(response.object).to eq("chat.completion")
      expect(response.created).to eq(1_677_652_288)
      expect(response.model).to eq("gpt-3.5-turbo")
      expect(response.usage).to eq(basic_response["usage"])
    end

    it "provides content access" do
      expect(response.content).to eq("Hello! How can I help you today?")
      expect(response.has_content?).to be true
    end

    it "provides choices access" do
      expect(response.choices).to be_an(Array)
      expect(response.choices.first["message"]["content"]).to eq("Hello! How can I help you today?")
    end
  end

  describe "hash delegation" do
    let(:response) { OpenRouter::Response.new(basic_response) }

    it "delegates hash methods" do
      expect(response["id"]).to eq("chatcmpl-123")
      expect(response.dig("choices", 0, "message", "content")).to eq("Hello! How can I help you today?")
      expect(response.key?("model")).to be true
      expect(response.fetch("model")).to eq("gpt-3.5-turbo")
    end

    it "converts to json" do
      json = response.to_json
      expect(JSON.parse(json)["id"]).to eq("chatcmpl-123")
    end
  end

  describe "tool calling" do
    let(:response) { OpenRouter::Response.new(tool_call_response) }

    it "detects tool calls" do
      expect(response.has_tool_calls?).to be true
      expect(response.tool_calls).to be_an(Array)
      expect(response.tool_calls.size).to eq(1)
    end

    it "parses tool calls correctly" do
      tool_call = response.tool_calls.first
      expect(tool_call).to be_a(OpenRouter::ToolCall)
      expect(tool_call.id).to eq("call_abc123")
      expect(tool_call.name).to eq("search_books")
    end

    it "converts to message format" do
      message = response.to_message
      expect(message[:role]).to eq("assistant")
      expect(message[:content]).to be_nil
      expect(message[:tool_calls]).to be_an(Array)
    end
  end

  describe "message conversion" do
    it "converts regular response to message format correctly" do
      response = OpenRouter::Response.new(basic_response)
      message = response.to_message
      expect(message[:role]).to eq("assistant")
      expect(message[:content]).to eq("Hello! How can I help you today?")
      expect(message).not_to have_key(:tool_calls)
    end

    it "converts tool call response to message format correctly" do
      response = OpenRouter::Response.new(tool_call_response)
      message = response.to_message
      expect(message[:role]).to eq("assistant")
      expect(message[:content]).to be_nil
      expect(message[:tool_calls]).to be_an(Array)
    end
  end

  describe "structured outputs" do
    let(:weather_schema) do
      OpenRouter::Schema.define("weather") do
        string :location, required: true
        number :temperature, required: true
        string :conditions, required: true
      end
    end

    let(:response_format) do
      {
        type: "json_schema",
        json_schema: weather_schema
      }
    end

    let(:response) { OpenRouter::Response.new(structured_response, response_format:) }

    it "parses structured output" do
      output = response.structured_output
      expect(output).to be_a(Hash)
      expect(output["location"]).to eq("London")
      expect(output["temperature"]).to eq(18)
      expect(output["conditions"]).to eq("Partly cloudy")
    end

    it "handles Schema object as response_format" do
      schema_response = OpenRouter::Response.new(structured_response, response_format: weather_schema)
      output = schema_response.structured_output
      expect(output["location"]).to eq("London")
    end

    it "handles hash response_format with explicit strict: false" do
      response_format_with_strict_false = {
        type: "json_schema",
        json_schema: {
          name: "weather",
          schema: {
            type: "object",
            properties: {
              location: { type: "string" },
              temperature: { type: "number" }
            }
          },
          strict: false
        }
      }

      response = OpenRouter::Response.new(structured_response, response_format: response_format_with_strict_false)

      # The schema should be created with strict: false, not defaulting to true
      schema = response.send(:extract_schema_from_response_format)
      expect(schema.strict).to be false
    end

    it "handles hash response_format with explicit strict: true" do
      response_format_with_strict_true = {
        type: "json_schema",
        json_schema: {
          name: "weather",
          schema: {
            type: "object",
            properties: {
              location: { type: "string" },
              temperature: { type: "number" }
            }
          },
          strict: true
        }
      }

      response = OpenRouter::Response.new(structured_response, response_format: response_format_with_strict_true)

      # The schema should be created with strict: true
      schema = response.send(:extract_schema_from_response_format)
      expect(schema.strict).to be true
    end

    it "defaults to strict: true when strict key is missing" do
      response_format_without_strict = {
        type: "json_schema",
        json_schema: {
          name: "weather",
          schema: {
            type: "object",
            properties: {
              location: { type: "string" },
              temperature: { type: "number" }
            }
          }
          # no strict key
        }
      }

      response = OpenRouter::Response.new(structured_response, response_format: response_format_without_strict)

      # The schema should default to strict: true
      schema = response.send(:extract_schema_from_response_format)
      expect(schema.strict).to be true
    end

    it "handles invalid JSON gracefully" do
      bad_response = structured_response.dup
      bad_response["choices"][0]["message"]["content"] = "invalid json"

      response = OpenRouter::Response.new(bad_response, response_format:)

      expect do
        response.structured_output
      end.to raise_error(OpenRouter::StructuredOutputError, /parse/)
    end

    # Only test validation if json-schema is available
    if defined?(JSON::Validator)
      it "validates structured output" do
        expect(response.valid_structured_output?).to be true
        expect(response.validation_errors).to be_empty
      end

      it "detects invalid structured output" do
        bad_response = structured_response.dup
        bad_response["choices"][0]["message"]["content"] = '{"location": "London"}' # Missing required fields

        response = OpenRouter::Response.new(bad_response, response_format:)

        expect(response.valid_structured_output?).to be false
        expect(response.validation_errors).not_to be_empty
      end
    end

    it "returns true for validation when no schema provided" do
      basic_resp = OpenRouter::Response.new(basic_response)
      expect(basic_resp.valid_structured_output?).to be true
    end

    it "returns true for validation when JSON::Validator not available" do
      # This test ensures we handle missing validation gracefully
      allow(response).to receive(:validation_available?).and_return(false)
      expect(response.valid_structured_output?).to be true
    end
  end

  describe "error handling" do
    let(:error_response) do
      {
        "error" => {
          "message" => "Invalid API key",
          "type" => "invalid_request_error",
          "code" => "invalid_api_key"
        }
      }
    end

    let(:response) { OpenRouter::Response.new(error_response) }

    it "detects errors" do
      expect(response.error?).to be true
      expect(response.error_message).to eq("Invalid API key")
    end
  end

  describe "empty responses" do
    let(:empty_response) { OpenRouter::Response.new({}) }

    it "handles empty responses gracefully" do
      expect(empty_response.content).to be_nil
      expect(empty_response.has_content?).to be false
      expect(empty_response.has_tool_calls?).to be false
      expect(empty_response.tool_calls).to be_empty
      expect(empty_response.error?).to be false
    end
  end
end
