# frozen_string_literal: true

require "spec_helper"
require "open_router"

RSpec.describe "Response Healing" do
  let(:client) do
    OpenRouter::Client.new(access_token: "test-key") do |config|
      config.auto_heal_responses = true
      config.healer_model = "openai/gpt-4o-mini"
      config.max_heal_attempts = 2
    end
  end

  let(:valid_json) { '{"name": "John", "age": 30}' }
  let(:malformed_json) { '{"name": "John", age: 30}' } # Missing quotes around key
  let(:partial_json) { '{"name": "John"' } # Incomplete
  let(:json_with_text) { 'Here is the JSON: {"name": "John", "age": 30} and some extra text' }
  let(:basic_schema) { { type: "json_schema", json_schema: { schema: { type: "object" } } } }

  describe "JSON healing" do
    context "with malformed JSON" do
      it "heals JSON parsing errors with simple mock" do
        # Mock the healing response with fixed JSON
        healed_response = double("Response", content: valid_json)
        allow(client).to receive(:complete).and_return(healed_response)

        # Create response with healing enabled
        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => malformed_json } }] },
          response_format: basic_schema
        )
        response.client = client

        result = response.structured_output(auto_heal: true)
        expect(result).to eq({ "name" => "John", "age" => 30 })

        # Verify healing was attempted
        expect(client).to have_received(:complete).at_least(:once)
      end
    end

    context "with valid JSON" do
      it "returns parsed JSON without healing" do
        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => valid_json } }] },
          response_format: basic_schema
        )
        response.client = client

        # Should not call the healing client
        expect(client).not_to receive(:complete)

        result = response.structured_output(auto_heal: true)
        expect(result).to eq({ "name" => "John", "age" => 30 })
      end
    end

    context "when auto_heal is disabled" do
      it "raises JSON::ParserError for malformed JSON" do
        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => malformed_json } }] },
          response_format: basic_schema
        )

        expect do
          response.structured_output(auto_heal: false)
        end.to raise_error(OpenRouter::StructuredOutputError)
      end
    end

    context "when client is not available" do
      it "cannot heal and raises the original error" do
        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => malformed_json } }] },
          response_format: basic_schema
        )
        # No client set

        expect do
          response.structured_output(auto_heal: true)
        end.to raise_error(OpenRouter::StructuredOutputError)
      end
    end
  end

  describe "schema healing" do
    let(:schema) do
      OpenRouter::Schema.define("person") do
        string :name, required: true
        integer :age, required: true
        string :email, required: false
      end
    end

    context "with schema validation errors" do
      it "heals schema validation failures" do
        # JSON that parses but fails schema validation (skip if no json-schema)
        skip "json-schema gem not available" unless defined?(JSON::Validator)

        invalid_data = '{"name": "John", "age": "thirty"}' # age should be integer
        valid_data = '{"name": "John", "age": 30}'

        healed_response = double("Response", content: valid_data)
        allow(client).to receive(:complete).and_return(healed_response)

        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => invalid_data } }] },
          response_format: schema
        )
        response.client = client

        result = response.structured_output(auto_heal: true)
        expect(result).to eq({ "name" => "John", "age" => 30 })
      end
    end

    context "when json-schema gem is not available" do
      before do
        # Temporarily hide JSON::Validator if it exists
        if defined?(JSON::Validator)
          @original_validator = JSON::Validator
          JSON.send(:remove_const, :Validator) if JSON.const_defined?(:Validator)
        end
      end

      after do
        # Restore JSON::Validator if it existed
        JSON::Validator = @original_validator if @original_validator
      end

      it "skips schema validation but still heals JSON parsing" do
        response = OpenRouter::Response.new(
          { "choices" => [{ "message" => { "content" => malformed_json } }] },
          response_format: schema
        )
        response.client = client

        healed_response = double("Response", content: valid_json)
        expect(client).to receive(:complete).and_return(healed_response)

        result = response.structured_output(auto_heal: true)
        expect(result).to eq({ "name" => "John", "age" => 30 })
      end
    end
  end

  describe "configuration options" do
    it "respects custom healer model" do
      custom_client = OpenRouter::Client.new(access_token: "test") do |config|
        config.healer_model = "anthropic/claude-3-haiku"
      end

      response = OpenRouter::Response.new(
        { "choices" => [{ "message" => { "content" => malformed_json } }] },
        response_format: basic_schema
      )
      response.client = custom_client

      healed_response = double("Response", content: valid_json)
      expect(custom_client).to receive(:complete).with(
        anything,
        hash_including(model: "anthropic/claude-3-haiku")
      ).and_return(healed_response)

      response.structured_output(auto_heal: true)
    end

    it "respects custom max_heal_attempts" do
      custom_client = OpenRouter::Client.new(access_token: "test") do |config|
        config.max_heal_attempts = 1
      end
      bad_response = double("Response", content: '{"still": broken}') # Still invalid JSON
      expect(custom_client).to receive(:complete).exactly(1).time.and_return(bad_response)

      response = OpenRouter::Response.new(
        { "choices" => [{ "message" => { "content" => malformed_json } }] },
        response_format: basic_schema
      )
      response.client = custom_client

      expect do
        response.structured_output(auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError)
    end
  end

  describe "healing prompts" do
    it "generates appropriate healing prompts for JSON errors" do
      response = OpenRouter::Response.new(
        { "choices" => [{ "message" => { "content" => malformed_json } }] },
        response_format: basic_schema
      )
      response.client = client

      healed_response = double("Response", content: valid_json)

      expect(client).to receive(:complete).with(
        [{ role: "user", content: match(/fix.*json/i) }],
        hash_including(model: "openai/gpt-4o-mini")
      ) do |messages, _options|
        prompt = messages.first[:content]
        expect(prompt).to include(malformed_json)
        expect(prompt).to include("valid JSON")
        expect(prompt).to include("ONLY")
        healed_response
      end

      response.structured_output(auto_heal: true)
    end

    it "includes schema information in healing prompts when available" do
      schema = OpenRouter::Schema.define("test") do
        string :name, required: true
      end

      response = OpenRouter::Response.new(
        { "choices" => [{ "message" => { "content" => '{"age": 30}' } }] },
        response_format: schema
      )
      response.client = client

      healed_response = double("Response", content: '{"name": "John"}')

      expect(client).to receive(:complete) do |messages, _options|
        prompt = messages.first[:content]
        expect(prompt).to include("schema")
        expect(prompt).to include("validation failed")
        healed_response
      end

      response.structured_output(auto_heal: true)
    end
  end
end
