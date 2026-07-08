# frozen_string_literal: true

require "spec_helper"

# Structured outputs default to a widely-supported json_object request with the
# schema described in the prompt. Native provider-side json_schema is opt-in via
# `native: true`. The model capability registry never gates the request.
RSpec.describe "Structured output request modes" do
  let(:schema) do
    OpenRouter::Schema.define("test_user") do
      string :name, required: true
      integer :age, required: true
    end
  end

  let(:response_format) do
    {
      type: "json_schema",
      json_schema: schema
    }
  end

  let(:messages) { [{ role: "user", content: "Create a user" }] }

  describe "Client#complete" do
    let(:client) { OpenRouter::Client.new(access_token: "test") }

    context "by default (json_object + prompt-injected schema)" do
      it "sends response_format json_object, never json_schema" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:response_format]).to eq({ type: "json_object" })
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "any-model", response_format:)
      end

      it "injects schema instructions into messages" do
        injected_messages = nil
        expect(client).to receive(:post) do |path:, parameters:|
          injected_messages = parameters[:messages]
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "any-model", response_format:)

        expect(injected_messages).to have_attributes(size: 2)
        expect(injected_messages.last[:role]).to eq("system")
        expect(injected_messages.last[:content]).to include("JSON")
        expect(injected_messages.last[:content]).to include("schema")
      end

      it "returns a Response flagged for lenient extraction" do
        allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] })

        response = client.complete(messages, model: "any-model", response_format:)

        expect(response).to be_a(OpenRouter::Response)
        expect(response.forced_extraction).to be true
      end

      it "does not consult the model registry for capability" do
        expect(OpenRouter::ModelRegistry).not_to receive(:has_capability?)
        allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => "{}" } }] })

        client.complete(messages, model: "some-obscure-model", response_format:)
      end
    end

    context "with native: true" do
      it "sends native json_schema response_format" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:response_format][:type]).to eq("json_schema")
          expect(parameters[:response_format][:json_schema]).to be_a(Hash)
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "supported-model", response_format:, native: true)
      end

      it "does not inject schema instructions" do
        original_messages = messages.dup
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:messages]).to eq(original_messages)
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "supported-model", response_format:, native: true)
      end

      it "returns a Response without the lenient-extraction flag" do
        allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] })

        response = client.complete(messages, model: "supported-model", response_format:, native: true)

        expect(response.forced_extraction).to be false
      end
    end

    context "without response_format" do
      it "does not add response_format or inject anything" do
        original_messages = messages.dup
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:messages]).to eq(original_messages)
          expect(parameters).not_to have_key(:response_format)
          { "choices" => [{ "message" => { "content" => "Regular response" } }] }
        end

        client.complete(messages, model: "any-model")
      end
    end
  end

  describe "Response#structured_output with lenient extraction" do
    context "with JSON in markdown code blocks" do
      let(:response_content) do
        <<~CONTENT
          Here's the user data you requested:

          ```json
          {"name": "John", "age": 30}
          ```

          This represents a typical user profile.
        CONTENT
      end

      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => response_content } }] }, response_format:, forced_extraction: true) }

      it "extracts JSON from markdown code blocks" do
        result = response.structured_output
        expect(result).to eq({ "name" => "John", "age" => 30 })
      end

      it "works in gentle mode" do
        result = response.structured_output(mode: :gentle)
        expect(result).to eq({ "name" => "John", "age" => 30 })
      end
    end

    context "with JSON in plain text response" do
      let(:response_content) { '{"name": "Alice", "age": 25}' }
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => response_content } }] }, response_format:, forced_extraction: true) }

      it "extracts JSON from plain text response" do
        result = response.structured_output
        expect(result).to eq({ "name" => "Alice", "age" => 25 })
      end
    end

    context "with malformed JSON requiring healing" do
      let(:response_content) do
        <<~CONTENT
          ```json
          {"name": "Bob", "age": "twenty-five"}
          ```
        CONTENT
      end

      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => response_content } }] }, response_format:, forced_extraction: true) }
      let(:mock_client) do
        double("client",
               configuration: double(auto_heal_responses: true, max_heal_attempts: 2, healer_model: "gpt-3.5-turbo"))
      end

      before do
        response.client = mock_client
      end

      it "sends full response content to first heal attempt (strict mode)" do
        expect(response).to receive(:heal_structured_response) do |content, _schema|
          expect(content).to include("```json") # Full response, not just JSON
          expect(content).to include("twenty-five")
          { "name" => "Bob", "age" => 25 }
        end

        result = response.structured_output(mode: :strict, auto_heal: true)
        expect(result).to eq({ "name" => "Bob", "age" => 25 })
      end

      it "heals extracted JSON in strict mode without additional validation" do
        # When healing is enabled, the healing process handles validation internally
        # No additional validation should happen after healing succeeds
        expect(response).to receive(:heal_structured_response).and_return({ "name" => "Bob", "age" => 25 })

        result = response.structured_output(mode: :strict, auto_heal: true)
        expect(result).to eq({ "name" => "Bob", "age" => 25 })
      end

      it "returns extracted JSON without validation or healing in gentle mode" do
        # Gentle mode should not attempt healing
        expect(response).not_to receive(:heal_structured_response)

        result = response.structured_output(mode: :gentle)
        expect(result).to eq({ "name" => "Bob", "age" => "twenty-five" }) # Valid JSON, no schema validation in gentle mode
      end
    end

    context "with no JSON found in response" do
      let(:response_content) { "I cannot provide that information." }
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => response_content } }] }, response_format:, forced_extraction: true) }

      it "returns nil in gentle mode" do
        result = response.structured_output(mode: :gentle)
        expect(result).to be_nil
      end

      it "attempts healing with full content in strict mode" do
        mock_client = double("client",
                             configuration: double(auto_heal_responses: true, max_heal_attempts: 2,
                                                   healer_model: "gpt-3.5-turbo"))
        response.client = mock_client

        expect(response).to receive(:heal_structured_response) do |content, _schema|
          expect(content).to eq(response_content) # Full response sent to healer
          { "name" => "Generated", "age" => 0 }
        end

        result = response.structured_output(mode: :strict, auto_heal: true)
        expect(result).to eq({ "name" => "Generated", "age" => 0 })
      end
    end

    context "without forced_extraction flag" do
      let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '```json\n{"name": "John"}\n```' } }] }, response_format:) }

      it "does not extract from markdown blocks in normal mode" do
        # Should look for structured output in standard location, not extract from markdown
        result = response.structured_output
        expect(result).to be_nil
      end
    end
  end

  describe "schema instruction injection" do
    let(:client) { OpenRouter::Client.new(access_token: "test") }

    it "creates clear format instructions" do
      injected_messages = nil
      expect(client).to receive(:post) do |path:, parameters:|
        injected_messages = parameters[:messages]
        { "choices" => [{ "message" => { "content" => "{}" } }] }
      end

      client.complete(messages, model: "any-model", response_format:)

      instruction = injected_messages.last[:content]
      expect(instruction).to include("JSON")
      expect(instruction).to include("schema")
      expect(instruction).to include(schema.to_h.to_json)
      expect(instruction).to include("ONLY") # Emphasize only JSON response
    end
  end
end
