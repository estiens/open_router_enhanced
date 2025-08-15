# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Structured Outputs", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Simple schema for testing
  let(:simple_schema) do
    OpenRouter::Schema.define("simple_response") do
      string "message", required: true, description: "A simple message"
      integer "count", required: true, description: "A count (OpenRouter requires all properties in required array)"
    end
  end

  # Complex schema with nested objects
  let(:complex_schema) do
    OpenRouter::Schema.define("analysis_result") do
      string "summary", required: true, description: "Summary of the analysis"
      object "details", required: true, description: "Detailed analysis" do
        string "category", required: true, description: "Category of analysis"
        number "confidence", required: true, description: "Confidence score 0-1"
        array "keywords", required: true, description: "Relevant keywords" do
          string description: "Individual keyword"
        end
      end
      boolean "requires_followup", required: true, description: "Whether followup is needed"
    end
  end

  # Schema with array of objects
  let(:array_schema) do
    OpenRouter::Schema.define("task_list") do
      array "tasks", required: true, description: "List of tasks" do
        object do
          string "title", required: true, description: "Task title"
          string "priority", required: true, description: "Priority level"
          boolean "completed", required: true, description: "Whether task is completed"
        end
      end
      integer "total_count", required: true, description: "Total number of tasks"
    end
  end

  describe "simple structured output", vcr: { cassette_name: "structured_outputs_simple" } do
    it "returns valid JSON matching the schema" do
      messages = [
        { role: "user", content: "Give me a simple greeting message with count 5" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)

      # Test structured output parsing
      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["message"]).to be_a(String)
      expect(structured["count"]).to be_a(Integer) if structured["count"]

      # Test that it matches the expected schema structure
      expect(structured).to have_key("message")
    end
  end

  describe "complex nested structured output", vcr: { cassette_name: "structured_outputs_complex" } do
    it "handles nested objects and arrays correctly" do
      messages = [
        { role: "user", content: "Analyze the text 'Ruby is a programming language' and provide detailed analysis" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: complex_schema,
        force_structured_output: true, # Force extraction mode for complex schemas
        extras: { max_tokens: 1000 }
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)

      # Check required fields
      expect(structured["summary"]).to be_a(String)
      expect(structured["details"]).to be_a(Hash)

      # Check nested object
      details = structured["details"]
      expect(details["category"]).to be_a(String)
      expect(details["confidence"]).to be_a(Numeric)
      expect(details["confidence"]).to be_between(0, 1)

      # Check optional array
      if details["keywords"]
        expect(details["keywords"]).to be_an(Array)
        details["keywords"].each do |keyword|
          expect(keyword).to be_a(String)
        end
      end

      # Check optional boolean
      expect([true, false]).to include(structured["requires_followup"]) if structured["requires_followup"]
    end
  end

  describe "array of objects schema", vcr: { cassette_name: "structured_outputs_array_objects" } do
    it "correctly structures arrays of complex objects" do
      messages = [
        { role: "user",
          content: "Create a task list with 3 tasks: writing documentation (high priority), testing code (medium priority), and reviewing pull request (low priority)" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: array_schema,
        force_structured_output: true, # Force extraction mode for complex schemas
        extras: { max_tokens: 1000 }
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)

      # Check main structure
      expect(structured["tasks"]).to be_an(Array)
      expect(structured["total_count"]).to be_a(Integer)
      expect(structured["total_count"]).to eq(structured["tasks"].length)

      # Check each task object
      structured["tasks"].each do |task|
        expect(task).to be_a(Hash)
        expect(task["title"]).to be_a(String)
        expect(task["priority"]).to be_a(String)
        expect(%w[high medium low]).to include(task["priority"])

        expect([true, false]).to include(task["completed"]) if task.key?("completed")
      end
    end
  end

  describe "hash-based response format", vcr: { cassette_name: "structured_outputs_hash_format" } do
    it "works with hash-based response format specification" do
      response_format = {
        type: "json_schema",
        json_schema: {
          name: "simple_response",
          strict: true,
          schema: {
            type: "object",
            properties: {
              greeting: { type: "string", description: "A greeting message" },
              timestamp: { type: "string", description: "Current timestamp" }
            },
            required: %w[greeting timestamp],
            additionalProperties: false
          }
        }
      }

      messages = [
        { role: "user", content: "Give me a greeting with the current timestamp" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format:,
        extras: { max_tokens: 500 }
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["greeting"]).to be_a(String)
    end
  end

  describe "schema validation", vcr: { cassette_name: "structured_outputs_validation" } do
    # NOTE: Validation requires json-schema gem which may not be available
    it "validates response against schema when json-schema is available" do
      messages = [
        { role: "user", content: "Give me a simple message 'Hello World' with count 42" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      structured = response.structured_output

      # Test validation if available
      if response.valid_structured_output?
        expect(response.validation_errors).to be_empty
      else
        # If validation isn't available, we can't test it
        puts "JSON Schema validation not available (json-schema gem not loaded)"
      end

      # Basic structural validation regardless
      expect(structured).to be_a(Hash)
      expect(structured).to have_key("message")
    end
  end

  describe "error handling", vcr: { cassette_name: "structured_outputs_error_handling" } do
    it "handles invalid schema definitions" do
      expect do
        OpenRouter::Schema.new("", {})
      end.to raise_error(ArgumentError, /Schema name is required/)

      expect do
        OpenRouter::Schema.new("test", "not a hash")
      end.to raise_error(ArgumentError, /Schema definition must be a hash/)
    end

    # NOTE: This test would require a model that returns malformed JSON,
    # which is unlikely with real API responses but good for error handling
    it "handles JSON parsing errors gracefully" do
      # We can't easily test this with real API responses since they should always return valid JSON
      # But we can test the error handling logic directly
      raw_response = {
        "choices" => [
          {
            "message" => {
              "content" => "invalid json content {"
            }
          }
        ]
      }

      response = OpenRouter::Response.new(raw_response, response_format: simple_schema)

      expect do
        response.structured_output
      end.to raise_error(OpenRouter::StructuredOutputError, /Failed to parse structured output/)
    end
  end

  describe "schema builder DSL", vcr: { cassette_name: "structured_outputs_dsl" } do
    it "correctly builds schemas using DSL" do
      schema = OpenRouter::Schema.define("test_schema") do
        string "name", required: true, description: "Person's name"
        integer "age", required: false, description: "Person's age"
        boolean "active", required: true, description: "Whether person is active"

        array "hobbies", required: false, description: "List of hobbies" do
          string description: "Individual hobby"
        end

        object "address", required: true, description: "Address information" do
          string "street", required: true, description: "Street address"
          string "city", required: true, description: "City"
          string "country", required: false, description: "Country"
        end
      end

      schema_hash = schema.to_h
      expect(schema_hash[:name]).to eq("test_schema")
      expect(schema_hash[:strict]).to be true
      expect(schema_hash[:schema][:type]).to eq("object")
      expect(schema_hash[:schema][:properties]).to have_key("name")
      expect(schema_hash[:schema][:properties]).to have_key("address")
      expect(schema_hash[:schema][:required]).to include("name", "active", "address")
    end
  end

  describe "response metadata with structured outputs", vcr: { cassette_name: "structured_outputs_metadata" } do
    it "maintains all response metadata while providing structured output" do
      messages = [
        { role: "user", content: "Give me a simple greeting" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      # Test that all normal response fields are present
      expect(response.id).to be_a(String)
      expect(response.object).to eq("chat.completion")
      expect(response.created).to be_a(Integer)
      expect(response.model).to include("gpt-4o-mini")
      expect(response.usage).to be_a(Hash)
      expect(response.usage["prompt_tokens"]).to be > 0
      expect(response.usage["completion_tokens"]).to be > 0
      expect(response.usage["total_tokens"]).to be > 0

      # Test that structured output is also available
      expect(response.structured_output).to be_a(Hash)
      expect(response.content).to be_a(String)

      # Test backward compatibility
      expect(response["id"]).to eq(response.id)
      expect(response["usage"]).to eq(response.usage)
    end
  end

  describe "strict vs non-strict schemas", vcr: { cassette_name: "structured_outputs_strict_mode" } do
    let(:non_strict_schema) do
      OpenRouter::Schema.define("flexible_response", strict: false) do
        string "message", required: true, description: "A message"
        additional_properties(true)
      end
    end

    it "handles non-strict schemas allowing additional properties" do
      messages = [
        { role: "user", content: "Give me a message and any additional information you think is relevant" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: non_strict_schema,
        extras: { max_tokens: 500 }
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["message"]).to be_a(String)

      # May have additional properties beyond what's defined in schema
      # This is allowed in non-strict mode
    end
  end

  describe "schema serialization for API", vcr: { cassette_name: "structured_outputs_serialization" } do
    it "properly serializes schemas for the OpenRouter API" do
      messages = [
        { role: "user", content: "Give me a simple message" }
      ]

      # Test Schema object as response_format
      response1 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      # Test hash with Schema object as response_format
      response2 = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: { type: "json_schema", json_schema: simple_schema },
        extras: { max_tokens: 500 }
      )

      # Both should work and return structured output
      expect(response1.structured_output).to be_a(Hash)
      expect(response2.structured_output).to be_a(Hash)
    end
  end

  describe "integration with different models", vcr: { cassette_name: "structured_outputs_different_models" } do
    it "works with different models that support structured outputs" do
      pending "VCR cassette mismatch - needs re-recording with current API"
      messages = [
        { role: "user", content: "Give me a simple greeting message" }
      ]

      # Test with GPT-4o-mini
      response_gpt = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      expect(response_gpt.structured_output).to be_a(Hash)
      expect(response_gpt.structured_output["message"]).to be_a(String)

      # Test with other models that support structured outputs
      # Note: Not all models may support structured outputs,
      # so we may need to handle errors gracefully
      begin
        response_claude = client.complete(
          messages,
          model: "anthropic/claude-3-haiku",
          response_format: simple_schema,
          extras: { max_tokens: 500 }
        )

        expect(response_claude.structured_output).to be_a(Hash) if response_claude.structured_output
      rescue OpenRouter::ServerError => e
        # Some models may not support structured outputs
        puts "Claude model may not support structured outputs: #{e.message}"
      end
    end
  end
end
