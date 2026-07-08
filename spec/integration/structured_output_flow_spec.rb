# frozen_string_literal: true

require "spec_helper"

RSpec.describe "End-to-end structured output scenarios" do
  let(:client) { OpenRouter::Client.new(access_token: "test_token") }

  let(:user_schema) do
    OpenRouter::Schema.define("complete_user") do
      string :name, required: true, description: "User's full name"
      integer :age, required: true
      string :email, required: true, format: "email"
      string :role, enum: %w[admin editor viewer], description: "User role"
      string :status, enum: %w[active inactive], description: "Account status"
    end
  end

  let(:response_format) do
    {
      type: "json_schema",
      json_schema: user_schema.to_h
    }
  end

  let(:messages) { [{ role: "user", content: "Create a user profile" }] }

  describe "default json_object path (no native flag)" do
    it "requests a json_object and injects the schema, then parses the result" do
      json_response = '{"name": "Alice Johnson", "age": 28, "email": "alice@example.com", "role": "editor", "status": "active"}'

      expect(client).to receive(:post) do |path:, parameters:|
        # Widely-supported json_object request — never native json_schema by default.
        expect(parameters[:response_format]).to eq({ type: "json_object" })
        # Schema described in an injected system message.
        expect(parameters[:messages].last[:role]).to eq("system")
        expect(parameters[:messages].last[:content]).to include("JSON")

        { "choices" => [{ "message" => { "content" => json_response } }] }
      end

      response = client.complete(messages, model: "any-model", response_format:)

      result = response.structured_output
      expect(result).to eq({
                             "name" => "Alice Johnson",
                             "age" => 28,
                             "email" => "alice@example.com",
                             "role" => "editor",
                             "status" => "active"
                           })
    end

    it "does not warn about capability or forced extraction" do
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => '{"name": "Test", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}' } }]
                                                 })

      expect do
        client.complete(messages, model: "some-obscure-model", response_format:)
      end.not_to output(/forced extraction|doesn't support/i).to_stderr
    end

    it "injects clear schema instructions into the prompt" do
      injected_messages = nil

      expect(client).to receive(:post) do |path:, parameters:|
        injected_messages = parameters[:messages]
        { "choices" => [{ "message" => { "content" => "{}" } }] }
      end

      client.complete(messages, model: "any-model", response_format:)

      instruction = injected_messages.last[:content]
      expect(instruction).to include("JSON")
      expect(instruction).to include(user_schema.to_h.to_json)
      expect(instruction).to include("ONLY")
    end

    context "with malformed JSON requiring healing" do
      let(:malformed_response) do
        <<~RESPONSE
          Here's the user data:

          ```json
          {
            "name": "Bob Wilson",
            "age": "thirty-two",#{" "}
            "email": "bob-at-example-dot-com",
            "role": "administrator",
            "status": "enabled"
          }
          ```
        RESPONSE
      end

      let(:healed_response) do
        '{"name": "Bob Wilson", "age": 32, "email": "bob@example.com", "role": "admin", "status": "active"}'
      end

      it "heals malformed JSON with full context in strict mode" do
        mock_client = double("client",
                             configuration: double(
                               auto_heal_responses: true,
                               max_heal_attempts: 2,
                               healer_model: "gpt-3.5-turbo"
                             ))

        healing_prompt = nil

        expect(client).to receive(:post).and_return({
                                                      "choices" => [{ "message" => { "content" => malformed_response } }]
                                                    })

        expect(mock_client).to receive(:complete) do |messages, **_options|
          healing_prompt = messages.last[:content]
          OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_response } }] })
        end

        response = client.complete(messages, model: "any-model", response_format:)
        response.client = mock_client

        result = response.structured_output(mode: :strict, auto_heal: true)

        # Should include full response context in healing
        expect(healing_prompt).to include("Here's the user data")
        expect(healing_prompt).to include("thirty-two")
        expect(healing_prompt).to include("bob-at-example-dot-com")

        expect(result).to eq({
                               "name" => "Bob Wilson",
                               "age" => 32,
                               "email" => "bob@example.com",
                               "role" => "admin",
                               "status" => "active"
                             })
      end
    end

    context "with gentle mode for resilience" do
      it "works in gentle mode without errors on malformed JSON" do
        malformed_json = '{"name": "Test", "age": invalid}'

        expect(client).to receive(:post).and_return({
                                                      "choices" => [{ "message" => { "content" => malformed_json } }]
                                                    })

        response = client.complete(messages, model: "any-model", response_format:)

        result = response.structured_output(mode: :gentle)
        expect(result).to be_nil # Returns nil instead of raising
      end

      it "returns extracted JSON when possible in gentle mode" do
        valid_json = '{"name": "Test", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}'

        expect(client).to receive(:post).and_return({
                                                      "choices" => [{ "message" => { "content" => valid_json } }]
                                                    })

        response = client.complete(messages, model: "any-model", response_format:)

        result = response.structured_output(mode: :gentle)
        expect(result["name"]).to eq("Test")
      end
    end
  end

  describe "native: true (provider-side json_schema)" do
    it "sends a native json_schema response_format and leaves messages untouched" do
      expect(client).to receive(:post) do |path:, parameters:|
        expect(parameters[:response_format][:type]).to eq("json_schema")
        expect(parameters[:messages]).to eq(messages)

        {
          "choices" => [{
            "message" => {
              "content" => '{"name": "Native User", "age": 30, "email": "native@example.com", "role": "admin", "status": "active"}'
            }
          }]
        }
      end

      response = client.complete(messages, model: "native-model", response_format:, native: true)

      result = response.structured_output
      expect(result["name"]).to eq("Native User")
    end

    it "respects gentle mode on parse failure for native responses" do
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => '{"invalid": json}' } }]
                                                 })

      response = client.complete(messages, model: "native-model", response_format:, native: true)

      result = response.structured_output(mode: :gentle)
      expect(result).to be_nil
    end
  end

  describe "mixed model scenarios" do
    it "handles model arrays (fallbacks) with the json_object path" do
      expect(client).to receive(:post) do |path:, parameters:|
        expect(parameters[:response_format]).to eq({ type: "json_object" })
        expect(parameters[:models]).to eq(%w[model-a model-b])

        { "choices" => [{ "message" => { "content" => '{"name": "Fallback User", "age": 30, "email": "fallback@example.com", "role": "viewer", "status": "active"}' } }] }
      end

      response = client.complete(messages, model: %w[model-a model-b], response_format:)

      result = response.structured_output
      expect(result["name"]).to eq("Fallback User")
    end

    it "handles openrouter/auto with the json_object path" do
      expect(client).to receive(:post) do |path:, parameters:|
        expect(parameters[:response_format]).to eq({ type: "json_object" })
        expect(parameters[:model]).to eq("openrouter/auto")

        { "choices" => [{ "message" => { "content" => '{"name": "Auto User", "age": 28, "email": "auto@example.com", "role": "editor", "status": "active"}' } }] }
      end

      response = client.complete(messages, model: "openrouter/auto", response_format:)

      result = response.structured_output
      expect(result["name"]).to eq("Auto User")
    end
  end

  describe "configuration-driven behavior" do
    context "with structured_output_strict enabled globally" do
      before do
        OpenRouter.configure do |config|
          config.structured_output_strict = true
          config.auto_heal_responses = false
        end
      end

      after do
        OpenRouter.configure do |config|
          config.structured_output_strict = false
          config.auto_heal_responses = false
        end
      end

      it "raises on parse failure by default when strict is configured" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"bad": json}' } }]
                                                   })

        response = client.complete(messages, model: "any-model", response_format:)

        expect { response.structured_output }.to raise_error(OpenRouter::StructuredOutputError)
      end
    end

    context "with per-request overrides" do
      it "allows per-request strict override on a loose default" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"name": "Override", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}' } }]
                                                   })

        response = client.complete(messages, model: "any-model", response_format:)

        result = response.structured_output(mode: :strict)
        expect(result["name"]).to eq("Override")
      end

      it "allows per-request native override" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:response_format][:type]).to eq("json_schema")
          { "choices" => [{ "message" => { "content" => '{"name": "Override User", "age": 32, "email": "override@example.com", "role": "admin", "status": "active"}' } }] }
        end

        response = client.complete(messages, model: "native-model", response_format:, native: true)

        result = response.structured_output
        expect(result["name"]).to eq("Override User")
      end
    end
  end

  describe "complex real-world scenarios" do
    it "handles schema with multiple validation constraints" do
      complex_response = '{"name": "Complex User", "age": 35, "email": "complex@example.com", "role": "admin", "status": "active"}'

      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => complex_response } }]
                                                 })

      response = client.complete(messages, model: "any-model", response_format:)

      result = response.structured_output

      expect(result["name"]).to be_a(String)
      expect(result["age"]).to be_a(Integer)
      expect(result["email"]).to match(/@/)
      expect(%w[admin editor viewer]).to include(result["role"])
      expect(%w[active inactive]).to include(result["status"])
    end

    it "gracefully handles edge cases in lenient extraction" do
      edge_case_responses = [
        "No JSON found in this response at all",
        "```json\n// This is a comment\n{}\n```",
        "```\n{\"no_json_marker\": true}\n```",
        '{"unquoted": field, "trailing": "comma",}'
      ]

      edge_case_responses.each do |response_content|
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => response_content } }]
                                                   })

        response = client.complete(messages, model: "any-model", response_format:)

        result = response.structured_output(mode: :gentle)
        expect(result).to be_a(Hash).or(be_nil)
      end
    end

    it "maintains performance with frequent structured output calls" do
      5.times do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"name": "Performance User", "age": 25, "email": "perf@example.com", "role": "viewer", "status": "active"}' } }]
                                                   })

        response = client.complete(messages, model: "any-model", response_format:)
        result = response.structured_output
        expect(result["name"]).to eq("Performance User")
      end
    end
  end

  describe "error scenarios and recovery" do
    it "provides helpful error messages when all healing attempts fail" do
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => '{"permanently": "broken"' } }]
                                                 })

      mock_client = double("client",
                           configuration: double(
                             auto_heal_responses: true,
                             max_heal_attempts: 2,
                             healer_model: "gpt-3.5-turbo"
                           ))

      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"still": "broken"' } }] })
      )

      response = client.complete(messages, model: "any-model", response_format:)
      response.client = mock_client

      expect do
        response.structured_output(mode: :strict, auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError, /after 2 healing attempts/)
    end

    it "handles network errors gracefully during healing" do
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => '{"broken": json}' } }]
                                                 })

      mock_client = double("client",
                           configuration: double(
                             auto_heal_responses: true,
                             max_heal_attempts: 1,
                             healer_model: "gpt-3.5-turbo"
                           ))

      allow(mock_client).to receive(:complete).and_raise(StandardError, "Network timeout")

      response = client.complete(messages, model: "native-model", response_format:, native: true)
      response.client = mock_client

      expect do
        response.structured_output(mode: :strict, auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError, /Failed to heal JSON after \d+ healing attempts/)
    end
  end
end
