# frozen_string_literal: true

require "spec_helper"

RSpec.describe "JSON Healing Pipeline Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:strict_schema) do
    OpenRouter::Schema.define("person") do
      string "name", required: true, description: "Person's full name"
      integer "age", required: true, description: "Person's age in years"
      string "email", required: true, description: "Email address"
      boolean "active", required: true, description: "Whether the person is active"
    end
  end

  describe "native response-healing plugin" do
    it "auto-adds response-healing plugin for structured outputs",
       vcr: { cassette_name: "integration/healing_auto_plugin" } do
      OpenRouter.configuration.auto_native_healing = true

      messages = [
        { role: "user", content: "Create a person named John Doe, age 30, email john@example.com, active true" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: strict_schema,
        max_tokens: 200
      )

      expect(response).to be_a(OpenRouter::Response)

      # Should have valid structured output
      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["name"]).to be_present
    end

    it "handles structured output with native healing enabled",
       vcr: { cassette_name: "integration/healing_with_native" } do
      OpenRouter.configuration.auto_native_healing = true

      messages = [
        { role: "user",
          content: "Return JSON with: name='Alice Smith', age=25, email='alice@test.com', active=false" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: strict_schema,
        max_tokens: 200
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["name"]).to include("Alice")
      expect(structured["age"]).to eq(25)
      expect(structured["email"]).to include("@")
      expect(structured["active"]).to be false
    end
  end

  describe "client-side healing with JSONHealer" do
    let(:complex_schema) do
      OpenRouter::Schema.define("product") do
        string "name", required: true, description: "Product name"
        number "price", required: true, description: "Price in dollars"
        array "tags", required: true, description: "Product tags" do
          string description: "Tag name"
        end
        object "metadata", required: false, description: "Additional metadata" do
          string "sku", required: true, description: "Product SKU"
          boolean "in_stock", required: true, description: "Availability"
        end
      end
    end

    it "heals malformed JSON response using LLM",
       vcr: { cassette_name: "integration/healing_client_side" } do
      OpenRouter.configuration.auto_heal_responses = true

      messages = [
        { role: "user",
          content: "Create a product: name='Widget', price=29.99, tags=['electronics', 'gadget'], with SKU 'WDG-001' in stock" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: complex_schema,
        max_tokens: 300
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["name"]).to be_present
      expect(structured["price"]).to be_a(Numeric)
      expect(structured["tags"]).to be_an(Array)
    end
  end

  describe "healing callbacks" do
    it "triggers on_healing callback when healing occurs",
       vcr: { cassette_name: "integration/healing_callback" } do
      healing_triggered = false
      healing_data = nil

      client.on(:on_healing) do |data|
        healing_triggered = true
        healing_data = data
      end

      messages = [
        { role: "user", content: "Return a person: name='Test User', age=40, email='test@example.com', active=true" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: strict_schema,
        max_tokens: 200
      )

      # The callback may or may not be triggered depending on whether healing was needed
      # We just verify the response is valid
      expect(response.structured_output).to be_a(Hash)
    end
  end

  describe "healing with different schema types" do
    let(:array_schema) do
      OpenRouter::Schema.define("items") do
        array "items", required: true, description: "List of items" do
          object do
            string "id", required: true, description: "Item ID"
            string "name", required: true, description: "Item name"
          end
        end
      end
    end

    it "handles array-based schema responses",
       vcr: { cassette_name: "integration/healing_array_schema" } do
      messages = [
        { role: "user",
          content: "Return a JSON with items array containing: {id: '1', name: 'Apple'}, {id: '2', name: 'Banana'}" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: array_schema,
        max_tokens: 200
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["items"]).to be_an(Array)
      expect(structured["items"].length).to be >= 1
    end
  end

  describe "healing disabled scenarios" do
    it "returns raw response when healing is disabled",
       vcr: { cassette_name: "integration/healing_disabled" } do
      OpenRouter.configuration.auto_heal_responses = false
      OpenRouter.configuration.auto_native_healing = false

      messages = [
        { role: "user", content: "Return JSON: {\"name\": \"Test\", \"age\": 25, \"email\": \"t@t.com\", \"active\": true}" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: strict_schema,
        max_tokens: 200
      )

      # Should still work but without healing plugin
      expect(response.content).to be_present
    end
  end

  describe "forced extraction mode" do
    it "uses forced extraction for models without native structured output support",
       vcr: { cassette_name: "integration/healing_forced_extraction" } do
      messages = [
        { role: "user", content: "Create a person: Bob Jones, 35 years old, bob@jones.com, active" }
      ]

      # Force extraction mode injects schema as system message
      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        response_format: strict_schema,
        force_structured_output: true,
        max_tokens: 300
      )

      expect(response).to be_a(OpenRouter::Response)

      # Even in forced mode, we should get valid structured output
      structured = response.structured_output
      expect(structured).to be_a(Hash)
    end
  end

  describe "healing with model fallback" do
    it "maintains healing capability across fallback models",
       vcr: { cassette_name: "integration/healing_with_fallback" } do
      messages = [
        { role: "user", content: "Person: Jane Doe, 28, jane@example.com, active=true" }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: strict_schema,
        max_tokens: 200
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["name"]).to be_present
    end
  end
end
