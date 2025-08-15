# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::JsonHealer do
  let(:client) { double("client", configuration: configuration) }
  let(:configuration) do
    double("configuration",
           auto_heal_responses: true,
           healer_model: "openai/gpt-4o-mini",
           max_heal_attempts: 2)
  end
  let(:healer) { described_class.new(client) }

  describe "#heal" do
    let(:schema) do
      double("schema",
             validation_available?: true,
             validate: true,
             validation_errors: [],
             pure_schema: { type: "object", properties: { name: { type: "string" } } })
    end

    context "with valid JSON in code block" do
      let(:raw_text) { "```json\n{\"name\": \"John\"}\n```" }

      it "extracts and parses JSON successfully" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "John" })
      end
    end

    context "with JSON in code block without language identifier" do
      let(:raw_text) { "```\n{\"name\": \"Alice\"}\n```" }

      it "extracts and parses JSON successfully" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Alice" })
      end
    end

    context "with text after JSON: label" do
      let(:raw_text) { "Here is the JSON: {\"name\": \"Bob\"}" }

      it "extracts JSON after the colon" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Bob" })
      end
    end

    context "with loose JSON in text" do
      let(:raw_text) { "Some explanation and then {\"name\": \"Carol\"} followed by more text" }

      it "finds and extracts the JSON object" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Carol" })
      end
    end

    context "with trailing commas" do
      let(:raw_text) { "{\"name\": \"Dave\",}" }

      it "cleans up trailing commas before parsing" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Dave" })
      end
    end

    context "with array trailing commas" do
      let(:raw_text) { "[\"item1\", \"item2\",]" }

      it "cleans up trailing commas in arrays" do
        result = healer.heal(raw_text, schema)
        expect(result).to eq(%w[item1 item2])
      end
    end

    context "with no JSON-like content" do
      let(:raw_text) { "This is just plain text with no JSON" }

      it "raises StructuredOutputError" do
        expect { healer.heal(raw_text, schema) }.to raise_error(
          OpenRouter::StructuredOutputError,
          "No JSON-like content found in the response."
        )
      end
    end

    context "with schema validation failure" do
      let(:raw_text) { "{\"invalid\": \"field\"}" }
      let(:schema) do
        double("schema",
               validation_available?: true,
               pure_schema: { type: "object", properties: { name: { type: "string" } } })
      end

      before do
        # First call to validate returns false (validation fails)
        # Second call (after healing) returns true (validation passes)
        allow(schema).to receive(:validate).and_return(false, true)
        allow(schema).to receive(:validation_errors).and_return(["Missing required field: name"])

        allow(client).to receive(:complete).and_return(
          double("response", content: "{\"name\": \"Healed Name\"}")
        )
      end

      it "attempts healing with the healer model" do
        expect(client).to receive(:complete).with(
          [{ role: "user", content: kind_of(String) }],
          model: "openai/gpt-4o-mini",
          extras: { temperature: 0.0, max_tokens: 4000 }
        )

        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Healed Name" })
      end
    end

    context "with JSON parsing failure and healing" do
      let(:raw_text) { "{invalid json}" }

      before do
        allow(client).to receive(:complete).and_return(
          double("response", content: "{\"name\": \"Fixed JSON\"}")
        )
      end

      it "attempts to heal malformed JSON" do
        expect(client).to receive(:complete).with(
          [{ role: "user", content: kind_of(String) }],
          model: "openai/gpt-4o-mini",
          extras: { temperature: 0.0, max_tokens: 4000 }
        )

        result = healer.heal(raw_text, schema)
        expect(result).to eq({ "name" => "Fixed JSON" })
      end
    end

    context "when healing fails after max attempts" do
      let(:raw_text) { "{invalid json}" }
      let(:configuration) do
        double("configuration",
               auto_heal_responses: true,
               healer_model: "openai/gpt-4o-mini",
               max_heal_attempts: 1)
      end

      before do
        allow(client).to receive(:complete).and_return(
          double("response", content: "{still invalid}")
        )
      end

      it "raises StructuredOutputError after max attempts" do
        expect { healer.heal(raw_text, schema) }.to raise_error(
          OpenRouter::StructuredOutputError,
          /Failed to heal JSON after 1 healing attempts/
        )
      end
    end

    context "when healing request itself fails" do
      let(:raw_text) { "{invalid json}" }

      before do
        allow(client).to receive(:complete).and_raise(StandardError, "Network error")
        allow(healer).to receive(:warn) # Suppress warning in tests
      end

      it "returns original content and lets the loop fail naturally" do
        expect { healer.heal(raw_text, schema) }.to raise_error(
          OpenRouter::StructuredOutputError,
          /Failed to heal JSON after \d+ healing attempts/
        )
      end
    end
  end

  describe "private methods" do
    describe "#extract_json_candidate" do
      let(:extract_method) { healer.method(:extract_json_candidate) }

      it "prioritizes markdown code blocks" do
        text = "Some text ```json\n{\"key\": \"value\"}\n``` and {\"other\": \"json\"}"
        result = extract_method.call(text)
        expect(result).to eq("{\"key\": \"value\"}")
      end

      it "handles code blocks without language identifier" do
        text = "```\n{\"key\": \"value\"}\n```"
        result = extract_method.call(text)
        expect(result).to eq("{\"key\": \"value\"}")
      end

      it "finds text after JSON: label" do
        text = "Here is the JSON: {\"key\": \"value\"}"
        result = extract_method.call(text)
        expect(result).to eq("{\"key\": \"value\"}")
      end

      it "falls back to loose JSON matching" do
        text = "Some text {\"key\": \"value\"} more text"
        result = extract_method.call(text)
        expect(result).to eq("{\"key\": \"value\"}")
      end

      it "returns whole text as fallback" do
        text = "{\"key\": \"value\"}"
        result = extract_method.call(text)
        expect(result).to eq("{\"key\": \"value\"}")
      end
    end

    describe "#cleanup_syntax" do
      let(:cleanup_method) { healer.method(:cleanup_syntax) }

      it "removes trailing commas from objects" do
        json = "{\"key\": \"value\",}"
        result = cleanup_method.call(json)
        expect(result).to eq("{\"key\": \"value\"}")
      end

      it "removes trailing commas from arrays" do
        json = "[\"item1\", \"item2\",]"
        result = cleanup_method.call(json)
        expect(result).to eq("[\"item1\", \"item2\"]")
      end

      it "handles multiple trailing commas" do
        json = "{\"obj\": {\"nested\": \"value\",}, \"array\": [1, 2,],}"
        result = cleanup_method.call(json)
        expect(result).to eq("{\"obj\": {\"nested\": \"value\"}, \"array\": [1, 2]}")
      end
    end

    describe "#build_healing_prompt" do
      let(:schema) do
        double("schema",
               pure_schema: { type: "object", properties: { name: { type: "string" } } },
               to_h: { type: "object", properties: { name: { type: "string" } } })
      end
      let(:build_prompt_method) { healer.method(:build_healing_prompt) }

      it "builds a comprehensive healing prompt" do
        content = "{invalid json}"
        error_reason = "Invalid JSON syntax"
        error_class = StandardError # Generic error class for this test
        original_content = content
        context = :generic

        result = build_prompt_method.call(content, schema, error_reason, error_class, original_content, context)

        expect(result).to include("You are an expert JSON fixing bot")
        expect(result).to include(error_reason)
        expect(result).to include(content)
        expect(result).to include("\"type\":\"object\"")
        expect(result).to include("ONLY the raw, corrected JSON object")
      end
    end
  end

  describe "integration scenarios" do
    let(:schema) do
      OpenRouter::Schema.define("test_schema") do
        string :name, required: true
        integer :age
      end
    end

    before do
      allow(client).to receive(:complete).and_return(
        double("response", content: "{\"name\": \"John Doe\", \"age\": 30}")
      )
    end

    context "with complex nested JSON in markdown" do
      let(:raw_text) do
        <<~TEXT
          Here's your response:

          ```json
          {
            "name": "Complex User",
            "age": 25,
          }
          ```

          This should work perfectly!
        TEXT
      end

      it "successfully extracts and heals the JSON" do
        result = healer.heal(raw_text, schema)
        expect(result).to be_a(Hash)
        expect(result["name"]).to eq("Complex User")
        expect(result["age"]).to eq(25)
      end
    end

    context "with multiple JSON-like structures" do
      let(:raw_text) { "Config: {\"debug\": true} and data: {\"name\": \"Test\", \"age\": 20,}" }

      before do
        # The first JSON structure doesn't match the schema, so it should be healed
        allow(schema).to receive(:validate).and_return(false, true)
        allow(schema).to receive(:validation_errors).and_return(["Missing required field: name"])
      end

      it "picks the first JSON structure and heals it" do
        result = healer.heal(raw_text, schema)
        expect(result).to be_a(Hash)
        expect(result["name"]).to eq("John Doe")
      end
    end
  end
end
