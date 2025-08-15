# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Force structured output on unsupported models" do
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

  # Mock model data for testing
  before do
    allow(OpenRouter::ModelRegistry).to receive(:has_capability?) do |model, capability|
      case [model, capability]
      when ["supported-model", :structured_outputs]
        true
      when ["unsupported-model", :structured_outputs]
        false
      else
        false
      end
    end
  end

  describe "Client#complete" do
    let(:client) { OpenRouter::Client.new(access_token: "test") }

    context "with force_structured_output: true" do
      it "does NOT send response_format to API" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).not_to have_key(:response_format)
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "any-model", response_format:, force_structured_output: true)
      end

      it "injects schema instructions into messages" do
        injected_messages = nil
        expect(client).to receive(:post) do |path:, parameters:|
          injected_messages = parameters[:messages]
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "any-model", response_format:, force_structured_output: true)

        expect(injected_messages).to have_attributes(size: 2)
        expect(injected_messages.last[:role]).to eq("system")
        expect(injected_messages.last[:content]).to include("JSON")
        expect(injected_messages.last[:content]).to include("schema")
      end

      it "returns Response with forced_extraction flag" do
        allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] })

        response = client.complete(messages, model: "any-model", response_format:, force_structured_output: true)

        expect(response).to be_a(OpenRouter::Response)
        expect(response.instance_variable_get(:@forced_extraction)).to be true
      end

      it "warns about forcing on any model" do
        allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => "{}" } }] })

        # When explicitly forcing, no warning is expected (it's intentional)
        expect do
          client.complete(messages, model: "unsupported-model", response_format:, force_structured_output: true)
        end.not_to output(/warning/i).to_stderr
      end
    end

    context "with force_structured_output: false" do
      it "sends response_format to API normally" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).to have_key(:response_format)
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "supported-model", response_format:, force_structured_output: false)
      end

      it "does not inject schema instructions" do
        original_messages = messages.dup
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:messages]).to eq(original_messages)
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "supported-model", response_format:, force_structured_output: false)
      end
    end

    context "with force_structured_output: nil (auto-detect)" do
      it "auto-forces when model lacks structured_outputs capability" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).not_to have_key(:response_format) # Should be forced
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        expect do
          client.complete(messages, model: "unsupported-model", response_format:)
        end.to output(/doesn't support native structured outputs.*Automatically using forced extraction/).to_stderr
      end

      it "uses native format when model supports structured outputs" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).to have_key(:response_format)  # Should use native
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "supported-model", response_format:)
      end

      it "skips auto-detection for model arrays (fallbacks)" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).to have_key(:response_format)  # Should use native
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: %w[unsupported-model supported-model], response_format:)
      end

      it "skips auto-detection for openrouter/auto" do
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters).to have_key(:response_format)  # Should use native
          { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
        end

        client.complete(messages, model: "openrouter/auto", response_format:)
      end

      context "respects configuration.auto_force_on_unsupported_models flag" do
        context "when auto_force_on_unsupported_models is false" do
          it "should NOT auto-force for unsupported models" do
            # Configure to disable auto-forcing
            allow(OpenRouter.configuration).to receive(:auto_force_on_unsupported_models).and_return(false)

            # Should use native mode (include response_format in API call) instead of forcing
            expect(client).to receive(:post) do |path:, parameters:|
              expect(parameters).to have_key(:response_format) # Should use native, not force
              { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
            end

            # Should NOT output warning about auto-forcing
            expect do
              client.complete(messages, model: "unsupported-model", response_format:)
            end.not_to output(/Automatically using forced extraction/).to_stderr
          end
        end

        context "when auto_force_on_unsupported_models is true" do
          it "should auto-force for unsupported models (current behavior)" do
            # Configure to enable auto-forcing
            allow(OpenRouter.configuration).to receive(:auto_force_on_unsupported_models).and_return(true)

            expect(client).to receive(:post) do |path:, parameters:|
              expect(parameters).not_to have_key(:response_format) # Should be forced
              { "choices" => [{ "message" => { "content" => '{"name": "John", "age": 30}' } }] }
            end

            expect do
              client.complete(messages, model: "unsupported-model", response_format:)
            end.to output(/doesn't support native structured outputs.*Automatically using forced extraction/).to_stderr
          end
        end
      end
    end

    context "without response_format" do
      it "does not force or modify anything" do
        original_messages = messages.dup
        expect(client).to receive(:post) do |path:, parameters:|
          expect(parameters[:messages]).to eq(original_messages)
          expect(parameters).not_to have_key(:response_format)
          { "choices" => [{ "message" => { "content" => "Regular response" } }] }
        end

        client.complete(messages, model: "unsupported-model")
      end
    end
  end

  describe "Response#structured_output with forced extraction" do
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

      it "sends full response content to first heal attempt" do
        expect(response).to receive(:heal_structured_response) do |content, _schema|
          expect(content).to include("```json") # Full response, not just JSON
          expect(content).to include("twenty-five")
          { "name" => "Bob", "age" => 25 }
        end

        result = response.structured_output(auto_heal: true)
        expect(result).to eq({ "name" => "Bob", "age" => 25 })
      end

      it "heals extracted JSON in strict mode without additional validation" do
        # When healing is enabled, the healing process handles validation internally
        # No additional validation should happen after healing succeeds
        expect(response).to receive(:heal_structured_response).and_return({ "name" => "Bob", "age" => 25 })

        result = response.structured_output(mode: :strict, auto_heal: true)
        expect(result).to eq({ "name" => "Bob", "age" => 25 })
      end

      it "returns extracted JSON without validation in gentle mode" do
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

        result = response.structured_output(auto_heal: true)
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
      allow(client).to receive(:post).and_return({ "choices" => [{ "message" => { "content" => "{}" } }] })

      injected_messages = nil
      expect(client).to receive(:post) do |path:, parameters:|
        injected_messages = parameters[:messages]
        { "choices" => [{ "message" => { "content" => "{}" } }] }
      end

      client.complete(messages, model: "any-model", response_format:, force_structured_output: true)

      instruction = injected_messages.last[:content]
      expect(instruction).to include("JSON")
      expect(instruction).to include("schema")
      expect(instruction).to include(schema.to_h.to_json)
      expect(instruction).to include("ONLY") # Emphasize only JSON response
    end
  end
end
