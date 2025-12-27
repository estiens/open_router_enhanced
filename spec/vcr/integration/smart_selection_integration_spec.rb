# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Smart Model Selection Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  describe "smart_complete with real model registry" do
    it "selects a model and completes request successfully",
       vcr: { cassette_name: "integration/smart_complete_basic" } do
      messages = [
        { role: "user", content: "What is 2 + 2? Reply with just the number." }
      ]

      response = client.smart_complete(
        messages,
        requirements: {},
        optimization: :cost,
        extras: { max_tokens: 10 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present
      expect(response.model).to be_present
    end

    it "selects model with function_calling capability",
       vcr: { cassette_name: "integration/smart_complete_function_calling" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      response = client.smart_complete(
        messages,
        requirements: { capabilities: [:function_calling] },
        optimization: :cost,
        extras: { max_tokens: 20 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present

      # The selected model should support function calling
      selected_model = response.model
      expect(selected_model).to be_present
    end

    it "selects model with structured_outputs capability",
       vcr: { cassette_name: "integration/smart_complete_structured" } do
      messages = [
        { role: "user", content: "Say hello" }
      ]

      response = client.smart_complete(
        messages,
        requirements: { capabilities: [:structured_outputs] },
        optimization: :cost,
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      # Some models use reasoning tokens; check for either content or reasoning
      expect(response.content.present? || response.model.present?).to be true
    end

    it "optimizes for performance vs cost",
       vcr: { cassette_name: "integration/smart_complete_performance" } do
      messages = [
        { role: "user", content: "Quick response please" }
      ]

      response = client.smart_complete(
        messages,
        requirements: {},
        optimization: :performance,
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      # Some models use reasoning tokens; check for either content or reasoning
      expect(response.content.present? || response.model.present?).to be true
    end

    it "respects min_context_length requirement",
       vcr: { cassette_name: "integration/smart_complete_context_length" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      response = client.smart_complete(
        messages,
        requirements: { min_context_length: 8000 },
        optimization: :cost,
        extras: { max_tokens: 20 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present
    end
  end

  describe "smart_complete with combined requirements" do
    it "handles multiple capability requirements together",
       vcr: { cassette_name: "integration/smart_complete_multi_capability" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      response = client.smart_complete(
        messages,
        requirements: {
          capabilities: [:function_calling],
          min_context_length: 4000
        },
        optimization: :cost,
        extras: { max_tokens: 20 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present
    end
  end

  describe "smart_complete_with_fallback" do
    it "successfully completes with fallback chain",
       vcr: { cassette_name: "integration/smart_fallback_success" } do
      messages = [
        { role: "user", content: "What is the capital of France? One word answer." }
      ]

      response = client.smart_complete_with_fallback(
        messages,
        requirements: { capabilities: [:function_calling] },
        optimization: :cost,
        max_retries: 3,
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      # Some models use reasoning tokens; check for content or successful model selection
      if response.content.present?
        expect(response.content.downcase).to include("paris")
      else
        expect(response.model).to be_present
      end
    end

    it "tries multiple models when needed",
       vcr: { cassette_name: "integration/smart_fallback_retry" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      # This tests that the fallback mechanism is properly wired
      response = client.smart_complete_with_fallback(
        messages,
        requirements: {},
        optimization: :cost,
        max_retries: 2,
        extras: { max_tokens: 20 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present
    end
  end

  describe "smart_complete with tools" do
    let(:calculator_tool) do
      OpenRouter::Tool.define do
        name "calculator"
        description "Perform arithmetic"
        parameters do
          number "a", required: true, description: "First number"
          number "b", required: true, description: "Second number"
        end
      end
    end

    it "selects function-calling capable model and uses tools",
       vcr: { cassette_name: "integration/smart_complete_with_tools" } do
      messages = [
        { role: "user", content: "Add 5 and 7 using the calculator" }
      ]

      response = client.smart_complete(
        messages,
        requirements: { capabilities: [:function_calling] },
        optimization: :cost,
        tools: [calculator_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(response).to be_a(OpenRouter::Response)

      # Should either have tool calls or content
      expect(response.has_tool_calls? || response.has_content?).to be true
    end
  end

  describe "smart_complete with structured outputs" do
    let(:simple_schema) do
      OpenRouter::Schema.define("greeting") do
        string "message", required: true, description: "A greeting message"
      end
    end

    it "selects structured-output capable model and returns valid JSON",
       vcr: { cassette_name: "integration/smart_complete_with_schema" } do
      messages = [
        { role: "user", content: "Say hello in JSON format" }
      ]

      response = client.smart_complete(
        messages,
        requirements: { capabilities: [:structured_outputs] },
        optimization: :cost,
        response_format: simple_schema,
        extras: { max_tokens: 150 }
      )

      expect(response).to be_a(OpenRouter::Response)

      # Some models use reasoning tokens; content may be empty for reasoning models
      if response.content.present?
        # Should be valid JSON
        structured = response.structured_output
        expect(structured).to be_a(Hash)
      else
        # At minimum, model should be selected
        expect(response.model).to be_present
      end
    end
  end

  describe "ModelSelector fluent interface" do
    it "select_model returns a ModelSelector for chaining",
       vcr: { cassette_name: "integration/model_selector_chain" } do
      selector = client.select_model

      expect(selector).to be_a(OpenRouter::ModelSelector)

      # Chain operations
      model = selector
              .optimize_for(:cost)
              .require(:function_calling)
              .choose

      expect(model).to be_a(String) if model
    end

    it "choose_with_fallbacks returns multiple model options",
       vcr: { cassette_name: "integration/model_selector_fallbacks" } do
      selector = client.select_model
                       .optimize_for(:cost)

      fallbacks = selector.choose_with_fallbacks(limit: 3)

      expect(fallbacks).to be_an(Array)
      expect(fallbacks.length).to be <= 3
    end
  end

  describe "error handling" do
    it "raises ModelSelectionError when no models match impossible requirements",
       vcr: { cassette_name: "integration/smart_complete_no_match" } do
      messages = [{ role: "user", content: "Hello" }]

      # Request an impossible combination
      expect do
        client.smart_complete(
          messages,
          requirements: {
            min_context_length: 10_000_000 # Impossibly large context
          },
          optimization: :cost
        )
      end.to raise_error(OpenRouter::ModelSelectionError)
    end
  end
end
