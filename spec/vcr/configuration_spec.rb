# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Configuration Scenarios", :vcr do
  let(:base_token) { ENV["OPENROUTER_API_KEY"] }

  describe "Client Configuration" do
    it "allows explicit token override", vcr: { cassette_name: "config_explicit_token" } do
      client = OpenRouter::Client.new(access_token: base_token)

      response = client.complete(
        [{ role: "user", content: "Hello with explicit token" }],
        model: "openai/gpt-3.5-turbo",
        max_tokens: 30
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).not_to be_empty
    end
  end

  describe "Global Configuration" do
    after do
      # Reset configuration after each test
      OpenRouter.configure do |config|
        config.access_token = nil
        config.site_name = nil
        config.site_url = nil
        config.auto_heal_responses = true
        config.max_heal_attempts = 3
        config.healer_model = "gpt-3.5-turbo"
        config.auto_force_on_unsupported_models = nil
        config.default_structured_output_mode = :strict
      end
    end
  end

  describe "Response Healing Configuration" do
    it "respects auto_heal_responses setting", vcr: { cassette_name: "config_auto_heal_enabled" } do
      OpenRouter.configure do |config|
        config.auto_heal_responses = true
        config.max_heal_attempts = 2
        config.healer_model = "openai/gpt-3.5-turbo"
      end

      client = OpenRouter::Client.new(access_token: base_token)

      # Mock malformed JSON response
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{
                                                     "message" => {
                                                       "content" => '{"name": "Test", "age": invalid}'
                                                     }
                                                   }]
                                                 })

      schema = OpenRouter::Schema.define("test") do
        string :name, required: true
        integer :age, required: true
      end

      response = client.complete(
        [{ role: "user", content: "Generate test data" }],
        model: "test-model",
        response_format: {
          type: "json_schema",
          json_schema: schema.to_h
        },
        force_structured_output: true
      )

      # Should attempt healing automatically
      result = response.structured_output(mode: :gentle)
      expect(result).to be_a(Hash).or be_nil
    end

    it "uses custom healer model", vcr: { cassette_name: "config_custom_healer" } do
      OpenRouter.configure do |config|
        config.auto_heal_responses = true
        config.healer_model = "openai/gpt-4o-mini" # Different from default
        config.max_heal_attempts = 1
      end

      client = OpenRouter::Client.new(access_token: base_token)
      mock_client = double("healer_client")

      allow(mock_client).to receive(:configuration).and_return(
        double(
          auto_heal_responses: true,
          max_heal_attempts: 1,
          healer_model: "openai/gpt-4o-mini"
        )
      )

      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({
                                   "choices" => [{
                                     "message" => {
                                       "content" => '{"name": "Healed", "age": 25}'
                                     }
                                   }]
                                 })
      )

      # Mock malformed response
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{
                                                     "message" => {
                                                       "content" => '{"name": "Test", "age": invalid}'
                                                     }
                                                   }]
                                                 })

      schema = OpenRouter::Schema.define("test") do
        string :name, required: true
        integer :age, required: true
      end

      response = client.complete(
        [{ role: "user", content: "Generate test data" }],
        model: "test-model",
        response_format: {
          type: "json_schema",
          json_schema: schema.to_h
        }
      )

      response.client = mock_client

      result = response.structured_output(mode: :strict, auto_heal: true)
      expect(result["name"]).to eq("Healed")
    end
  end

  describe "Structured Output Configuration" do
    it "uses the json_object path regardless of model capability", vcr: { cassette_name: "config_json_object_default" } do
      client = OpenRouter::Client.new(access_token: base_token)

      # The registry must NOT be consulted to decide how to request structured output.
      expect(OpenRouter::ModelRegistry).not_to receive(:has_capability?)

      sent = nil
      allow(client).to receive(:post) do |path:, parameters:| # rubocop:disable Lint/UnusedBlockArgument
        sent = parameters
        { "choices" => [{ "message" => { "content" => '{"message": "ok"}' } }] }
      end

      schema = OpenRouter::Schema.define("simple") do
        string :message, required: true
      end

      response = client.complete(
        [{ role: "user", content: "Test default path" }],
        model: "test/unsupported-model",
        response_format: {
          type: "json_schema",
          json_schema: schema.to_h
        }
      )

      expect(sent[:response_format]).to eq({ type: "json_object" })
      expect(response.structured_output["message"]).to eq("ok")
    end

    it "respects structured_output_strict setting", vcr: { cassette_name: "config_default_mode" } do
      OpenRouter.configure do |config|
        config.structured_output_strict = false
      end

      client = OpenRouter::Client.new(access_token: base_token)

      # Mock malformed JSON response
      allow(client).to receive(:post).and_return({
                                                   "choices" => [{
                                                     "message" => {
                                                       "content" => '{"invalid": json}'
                                                     }
                                                   }]
                                                 })

      schema = OpenRouter::Schema.define("test") do
        string :name, required: true
        integer :age, required: true
      end

      response = client.complete(
        [{ role: "user", content: "Generate test data" }],
        model: "openai/gpt-4o-mini",
        response_format: {
          type: "json_schema",
          json_schema: schema.to_h
        }
      )

      # Should use gentle mode by default (returns nil instead of raising)
      result = response.structured_output
      expect(result).to be_nil
    end
  end

  describe "Configuration Validation" do
    it "provides helpful configuration errors", vcr: { cassette_name: "config_error_messages" } do
      client = OpenRouter::Client.new(access_token: "invalid_token")

      expect do
        client.complete(
          [{ role: "user", content: "Test with invalid token" }],
          model: "openai/gpt-3.5-turbo",
          max_tokens: 10
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end
  end
end
