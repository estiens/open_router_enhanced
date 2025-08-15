# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Self-healing with detailed error context" do
  let(:schema) do
    OpenRouter::Schema.define("detailed_user") do
      string :name, required: true
      integer :age, required: true
      string :email, required: true, format: "email"
      string :status, enum: %w[active inactive]
    end
  end

  let(:response_format) do
    {
      type: "json_schema",
      json_schema: schema.to_h
    }
  end

  let(:mock_client) do
    double("client",
           configuration: double(
             auto_heal_responses: true,
             max_heal_attempts: 3,
             healer_model: "gpt-3.5-turbo"
           ))
  end

  let(:healed_json) { '{"name": "John", "age": 30, "email": "john@example.com", "status": "active"}' }

  describe "JSON parse error healing" do
    let(:invalid_json) { '{"name": "John", "age": thirty, "email": "john@example.com"}' } # Missing quotes around thirty
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => invalid_json } }] }, response_format:) }

    before do
      response.client = mock_client
    end

    it "includes JSON parse errors in healing prompt" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      expect(healing_prompt).to include("Invalid JSON")
      expect(healing_prompt).to include("unexpected token") # JSON parse error details
      expect(healing_prompt).to include(invalid_json) # Original content
    end

    it "succeeds after healing with parse error context" do
      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      )

      result = response.structured_output(auto_heal: true)
      expect(result).to eq(JSON.parse(healed_json))
    end
  end

  describe "schema validation error healing" do
    let(:invalid_data) { '{"name": "John", "age": "thirty", "email": "not-an-email", "status": "unknown"}' }
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => invalid_data } }] }, response_format:) }

    before do
      response.client = mock_client
      # Skip if json-schema gem not available
    end

    it "includes specific schema validation errors in healing prompt" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      expect(healing_prompt).to include("Schema validation failed")
      expect(healing_prompt).to include("age") # Field that failed
      expect(healing_prompt).to include("email") # Field that failed
      expect(healing_prompt).to include("status") # Field that failed
      expect(healing_prompt).to include("type") # Error about wrong type
    end

    it "provides field-level validation errors" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      # Check for specific validation errors
      expect(healing_prompt).to match(/age.*integer.*string/i) # Age should be integer, got string
      expect(healing_prompt).to match(/email.*format/i) # Email format violation
      expect(healing_prompt).to match(/status.*enum/i) # Status not in enum
    end

    it "succeeds more often with detailed error context" do
      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      )

      result = response.structured_output(auto_heal: true)
      expect(result).to eq(JSON.parse(healed_json))
    end
  end

  describe "forced extraction first heal attempt" do
    let(:response_with_explanation) do
      <<~CONTENT
        I'll create a user for you. Here's the JSON data:

        ```json
        {"name": "Bob", "age": "twenty-five", "email": "bob@example.com", "status": "active"}
        ```

        This user has an invalid age format that needs to be corrected.
      CONTENT
    end

    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => response_with_explanation } }] }, response_format:, forced_extraction: true) }

    before do
      response.client = mock_client
    end

    it "sends full response content to first heal attempt" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      # Should include the full response with explanation
      expect(healing_prompt).to include("I'll create a user for you")
      expect(healing_prompt).to include("```json")
      expect(healing_prompt).to include("This user has an invalid")
      expect(healing_prompt).to include("twenty-five") # The problematic value
    end

    it "provides context about extraction vs validation" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      expect(healing_prompt).to include("extract")
      expect(healing_prompt).to include("schema")
    end
  end

  describe "subsequent heal attempts with extracted JSON" do
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"name": "Alice", "age": "25", "email": "alice@example.com", "status": "active"}' } }] }, response_format:) }

    before do
      response.client = mock_client
      # Mock multiple heal attempts
      allow(mock_client).to receive(:complete).and_return(
        # First attempt still has errors
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"name": "Alice", "age": "still-wrong", "email": "alice@example.com", "status": "active"}' } }] }),
        # Second attempt succeeds
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      )
    end

    it "sends only extracted JSON for subsequent heals" do
      healing_prompts = []

      allow(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompts << messages.last[:content]
        case healing_prompts.size
        when 1
          # First heal still returns invalid data
          OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"name": "Alice", "age": "still-wrong", "email": "alice@example.com", "status": "active"}' } }] })
        when 2
          # Second heal succeeds
          OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
        end
      end

      response.structured_output(auto_heal: true)

      # First heal should get parsed JSON, not full response
      expect(healing_prompts.first).to include('{"name": "Alice"')
      expect(healing_prompts.first).not_to include("I'll create") # No explanation text

      # Second heal should also get just JSON
      expect(healing_prompts.last).to include('{"name": "Alice"')
      expect(healing_prompts.last).to include("still-wrong") # Previous attempt's output
    end
  end

  describe "maximum heal attempts with error progression" do
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"broken": "json"}' } }] }, response_format:) }

    before do
      response.client = mock_client
    end

    it "includes attempt count in final error message" do
      # Mock all healing attempts to fail
      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"still": "broken"}' } }] })
      )

      expect do
        response.structured_output(auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError, /after 3 healing attempts/)
    end

    it "includes last validation errors in final error message" do
      # Mock healing that continues to have validation errors
      allow(mock_client).to receive(:complete).and_return(
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"name": "John", "age": "invalid", "email": "not_an_email_at_all", "status": "wrong"}' } }] })
      )

      expect do
        response.structured_output(auto_heal: true)
      end.to raise_error(OpenRouter::StructuredOutputError, /Last error:.*(age|status)/)
    end
  end

  describe "healing prompt structure" do
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"name": "Test", "age": "invalid"}' } }] }, response_format:) }

    before do
      response.client = mock_client
    end

    it "includes clear sections in healing prompt" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      expect(healing_prompt).to include("Validation Errors:")
      expect(healing_prompt).to include("Original Content to Fix:")
      expect(healing_prompt).to include("Required JSON Schema:")
      expect(healing_prompt).to include("Return ONLY the fixed")
    end

    it "includes the schema in JSON format" do
      healing_prompt = nil

      expect(mock_client).to receive(:complete) do |messages, **_options|
        healing_prompt = messages.last[:content]
        OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => healed_json } }] })
      end

      response.structured_output(auto_heal: true)

      expect(healing_prompt).to include(schema.to_h.to_json)
    end
  end

  describe "no healing when disabled" do
    let(:response) { OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => '{"broken": json}' } }] }, response_format:) }

    before do
      response.client = mock_client
    end

    it "does not attempt healing when auto_heal is false" do
      expect(mock_client).not_to receive(:complete)

      expect do
        response.structured_output(auto_heal: false)
      end.to raise_error(OpenRouter::StructuredOutputError)
    end

    it "does not attempt healing in gentle mode" do
      expect(mock_client).not_to receive(:complete)

      result = response.structured_output(mode: :gentle, auto_heal: true)
      expect(result).to be_nil
    end
  end
end
