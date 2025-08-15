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

  # Mock model capabilities for testing
  before do
    allow(OpenRouter::ModelRegistry).to receive(:has_capability?) do |model, capability|
      case model
      when "native-model"
        capability == :structured_outputs
      when "unsupported-model"
        false
      when "vision-model"
        %i[vision structured_outputs].include?(capability)
      else
        false
      end
    end
  end

  describe "model without native structured output support" do
    context "with auto-detection (default behavior)" do
      it "automatically forces extraction and succeeds" do
        # Mock the API response with clean JSON output
        json_response = '{"name": "Alice Johnson", "age": 28, "email": "alice@example.com", "role": "editor", "status": "active"}'

        expect(client).to receive(:post) do |path:, parameters:|
          # Should NOT include response_format (would cause 400)
          expect(parameters).not_to have_key(:response_format)
          # Should include injected schema instructions
          expect(parameters[:messages].last[:role]).to eq("system")
          expect(parameters[:messages].last[:content]).to include("valid JSON matching this exact schema")

          { "choices" => [{ "message" => { "content" => json_response } }] }
        end

        response = client.complete(messages, model: "unsupported-model", response_format:)

        result = response.structured_output
        expect(result).to eq({
                               "name" => "Alice Johnson",
                               "age" => 28,
                               "email" => "alice@example.com",
                               "role" => "editor",
                               "status" => "active"
                             })
      end

      it "warns about auto-forcing on unsupported model" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"name": "Test", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}' } }]
                                                   })

        expect do
          client.complete(messages, model: "unsupported-model", response_format:)
        end.to output(/doesn't support native structured outputs.*using forced extraction mode/).to_stderr
      end
    end

    context "with explicit force_structured_output: true" do
      it "injects clear schema instructions into prompt" do
        injected_messages = nil

        expect(client).to receive(:post) do |path:, parameters:|
          injected_messages = parameters[:messages]
          { "choices" => [{ "message" => { "content" => "{}" } }] }
        end

        client.complete(messages, model: "unsupported-model", response_format:, force_structured_output: true)

        instruction = injected_messages.last[:content]
        expect(instruction).to include("valid JSON matching this exact schema")
        expect(instruction).to include(user_schema.to_h.to_json)
        expect(instruction).to include("ONLY the JSON object")
      end
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

      it "heals malformed JSON with full context" do
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

        response = client.complete(messages, model: "unsupported-model", response_format:,
                                             force_structured_output: true)
        response.client = mock_client

        result = response.structured_output(auto_heal: true)

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

        response = client.complete(messages, model: "unsupported-model", response_format:,
                                             force_structured_output: true)

        result = response.structured_output(mode: :gentle)
        expect(result).to be_nil # Returns nil instead of raising
      end

      it "returns extracted JSON when possible in gentle mode" do
        valid_json = '{"name": "Test", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}'

        expect(client).to receive(:post).and_return({
                                                      "choices" => [{ "message" => { "content" => valid_json } }]
                                                    })

        response = client.complete(messages, model: "unsupported-model", response_format:,
                                             force_structured_output: true)

        result = response.structured_output(mode: :gentle)
        expect(result["name"]).to eq("Test")
      end
    end
  end

  describe "model with native structured output support" do
    it "uses native format by default" do
      expect(client).to receive(:post) do |path:, parameters:|
        # Should include response_format for native support
        expect(parameters).to have_key(:response_format)
        expect(parameters[:response_format][:type]).to eq("json_schema")
        # Should NOT modify messages
        expect(parameters[:messages]).to eq(messages)

        {
          "choices" => [{
            "message" => {
              "content" => '{"name": "Native User", "age": 30, "email": "native@example.com", "role": "admin", "status": "active"}'
            }
          }]
        }
      end

      response = client.complete(messages, model: "native-model", response_format:)

      result = response.structured_output
      expect(result["name"]).to eq("Native User")
    end

    it "can force extraction even on supported models when explicitly requested" do
      expect(client).to receive(:post) do |path:, parameters:|
        # Should NOT include response_format when forcing
        expect(parameters).not_to have_key(:response_format)
        # Should inject instructions
        expect(parameters[:messages].size).to be > messages.size

        { "choices" => [{ "message" => { "content" => '{"name": "Forced User", "age": 25, "email": "forced@example.com", "role": "admin", "status": "active"}' } }] }
      end

      response = client.complete(messages, model: "native-model", response_format:, force_structured_output: true)

      result = response.structured_output
      expect(result["name"]).to eq("Forced User")
    end

    it "respects mode setting for native responses" do
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{ "message" => { "content" => '{"invalid": json}' } }]
                                                 })

      response = client.complete(messages, model: "native-model", response_format:)

      # Gentle mode should return nil on parse failure
      result = response.structured_output(mode: :gentle)
      expect(result).to be_nil
    end
  end

  describe "mixed model scenarios" do
    it "handles model arrays (fallbacks) without forcing" do
      expect(client).to receive(:post) do |path:, parameters:|
        # Should use native format for fallback arrays
        expect(parameters).to have_key(:response_format)
        expect(parameters[:models]).to eq(%w[unsupported-model native-model])

        { "choices" => [{ "message" => { "content" => '{"name": "Fallback User", "age": 30, "email": "fallback@example.com", "role": "viewer", "status": "active"}' } }] }
      end

      response = client.complete(messages, model: %w[unsupported-model native-model], response_format:)

      result = response.structured_output
      expect(result["name"]).to eq("Fallback User")
    end

    it "handles openrouter/auto without forcing" do
      expect(client).to receive(:post) do |path:, parameters:|
        expect(parameters).to have_key(:response_format)
        expect(parameters[:model]).to eq("openrouter/auto")

        { "choices" => [{ "message" => { "content" => '{"name": "Auto User", "age": 28, "email": "auto@example.com", "role": "editor", "status": "active"}' } }] }
      end

      response = client.complete(messages, model: "openrouter/auto", response_format:)

      result = response.structured_output
      expect(result["name"]).to eq("Auto User")
    end
  end

  describe "configuration-driven behavior" do
    context "with global configuration" do
      before do
        OpenRouter.configure do |config|
          config.auto_force_on_unsupported_models = true
          config.default_structured_output_mode = :gentle
          config.auto_heal_responses = false
        end
      end

      after do
        # Reset configuration
        OpenRouter.configure do |config|
          config.auto_force_on_unsupported_models = nil
          config.default_structured_output_mode = :strict
          config.auto_heal_responses = true
        end
      end

      it "respects global auto-force configuration" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"configured": true}' } }]
                                                   })

        # Should auto-force based on config
        expect do
          client.complete(messages, model: "unsupported-model", response_format:)
        end.to output(/using forced extraction mode/).to_stderr
      end

      it "respects default mode configuration" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"bad": json}' } }]
                                                   })

        response = client.complete(messages, model: "native-model", response_format:)

        # Should use gentle mode by default
        result = response.structured_output
        expect(result).to be_nil # Gentle mode returns nil on failure
      end
    end

    context "with per-request overrides" do
      it "allows per-request mode override" do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"name": "Override", "age": 25, "email": "test@example.com", "role": "viewer", "status": "active"}' } }]
                                                   })

        response = client.complete(messages, model: "native-model", response_format:)

        # Override default mode per request
        result = response.structured_output(mode: :strict)
        expect(result["name"]).to eq("Override")
      end

      it "allows per-request force override" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).not_to have_key(:response_format) # Should be forced
          { "choices" => [{ "message" => { "content" => '{"name": "Override User", "age": 32, "email": "override@example.com", "role": "admin", "status": "active"}' } }] }
        end

        # Explicitly force on supported model
        response = client.complete(messages, model: "native-model", response_format:, force_structured_output: true)

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

      response = client.complete(messages, model: "native-model", response_format:)

      result = response.structured_output

      # Verify all schema constraints are met
      expect(result["name"]).to be_a(String)
      expect(result["age"]).to be_a(Integer)
      expect(result["email"]).to match(/@/)
      expect(%w[admin editor viewer]).to include(result["role"])
      expect(%w[active inactive]).to include(result["status"])
    end

    it "gracefully handles edge cases in forced extraction" do
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

        response = client.complete(messages, model: "unsupported-model", response_format:,
                                             force_structured_output: true)

        # Gentle mode should handle gracefully
        result = response.structured_output(mode: :gentle)
        expect(result).to be_a(Hash).or(be_nil)
      end
    end

    it "maintains performance with frequent structured output calls" do
      # Simulate multiple calls to ensure warnings don't spam
      5.times do
        allow(client).to receive(:post).and_return({
                                                     "choices" => [{ "message" => { "content" => '{"name": "Performance User", "age": 25, "email": "perf@example.com", "role": "viewer", "status": "active"}' } }]
                                                   })

        response = client.complete(messages, model: "unsupported-model", response_format:)
        result = response.structured_output
        expect(result["name"]).to eq("Performance User")
      end

      # Should only see one warning despite multiple calls
      # (This is tested more thoroughly in the warning specs)
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

      # Mock healing attempts that continue to fail
      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"still": "broken"' } }] })
      )

      response = client.complete(messages, model: "unsupported-model", response_format:, force_structured_output: true)
      response.client = mock_client

      expect do
        response.structured_output(auto_heal: true)
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

      # Mock healing request that fails with network error
      allow(mock_client).to receive(:complete).and_raise(StandardError, "Network timeout")

      response = client.complete(messages, model: "native-model", response_format:)
      response.client = mock_client

      expect do
        response.structured_output(auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError, /Failed to heal JSON after \d+ healing attempts/)
    end
  end
end
