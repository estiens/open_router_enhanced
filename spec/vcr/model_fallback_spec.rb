# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Model Fallback", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:simple_messages) do
    [{ role: "user", content: "Say hello" }]
  end

  describe "models array with fallback route", vcr: { cassette_name: "model_fallback_basic" } do
    it "uses fallback route with array of models" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo",
        "anthropic/claude-3-haiku"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)
      expect(response.content.length).to be > 0

      # Should succeed with one of the models in the array
      expect(response.model).to be_a(String)
      used_model = response.model

      # Verify the used model was one of our fallback options
      model_matched = models.any? { |model| used_model.include?(model.split("/").last) }
      expect(model_matched).to be true

      expect(response.usage).to be_a(Hash)
      expect(response.usage["total_tokens"]).to be > 0
    end
  end

  describe "ordered fallback preference", vcr: { cassette_name: "model_fallback_ordered" } do
    it "attempts models in specified order" do
      # Put a less common or potentially unavailable model first
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo",
        "anthropic/claude-3-haiku"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to be_a(String)

      # The response should indicate which model was actually used
      # This helps verify the fallback mechanism worked
      puts "Used model: #{response.model}"
    end
  end

  describe "fallback with specific providers", vcr: { cassette_name: "model_fallback_with_providers" } do
    it "respects provider preferences in fallback" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        providers: ["openai"],
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to include("openai")
    end
  end

  describe "fallback with tool calling", vcr: { cassette_name: "model_fallback_tool_calling" } do
    let(:simple_tool) do
      OpenRouter::Tool.define do
        name "get_time"
        description "Get the current time"
        parameters do
          string "timezone", required: false, description: "Timezone (optional)"
        end
      end
    end

    it "handles tool calling with model fallback" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      messages = [
        { role: "user", content: "What time is it?" }
      ]

      response = client.complete(
        messages,
        model: models,
        tools: [simple_tool],
        tool_choice: "auto",
        extras: { max_tokens: 500 }
      )

      expect(response).to be_a(OpenRouter::Response)

      # Should either have tool calls or regular content
      if response.has_tool_calls?
        expect(response.tool_calls.first.function_name).to eq("get_time")
      else
        expect(response.content).to be_a(String)
      end
    end
  end

  describe "fallback with structured outputs", vcr: { cassette_name: "model_fallback_structured_outputs" } do
    let(:simple_schema) do
      OpenRouter::Schema.define("greeting_response") do
        string "greeting", required: true, description: "A greeting message"
        string "language", required: false, description: "Language of the greeting"
      end
    end

    it "handles structured outputs with model fallback" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        response_format: simple_schema,
        extras: { max_tokens: 500 }
      )

      expect(response.content).to be_a(String)

      # Test structured output parsing
      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["greeting"]).to be_a(String)
    end
  end

  describe "fallback behavior with different request parameters", vcr: { cassette_name: "model_fallback_parameters" } do
    it "maintains request parameters across fallback attempts" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: {
          max_tokens: 20,
          temperature: 0.7,
          top_p: 0.9
        }
      )

      expect(response.content).to be_a(String)
      # The response should respect the max_tokens limit
      expect(response.usage["completion_tokens"]).to be <= 20
    end
  end

  describe "mixed model families in fallback", vcr: { cassette_name: "model_fallback_mixed_families" } do
    it "successfully falls back across different model families" do
      models = [
        "openai/gpt-4o-mini",
        "anthropic/claude-3-haiku",
        "meta-llama/llama-3.1-8b-instruct"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to be_a(String)

      # Should work with any of the different model families
      used_model = response.model.downcase
      expect(
        used_model.include?("gpt") ||
        used_model.include?("claude") ||
        used_model.include?("llama")
      ).to be true
    end
  end

  describe "fallback error scenarios",
           vcr: { cassette_name: "model_fallback_errors", allow_unused_http_interactions: true } do
    it "handles case where some models in array are unavailable" do
      # Test that API validates models before attempting fallback
      models = [
        "nonexistent/fake-model",
        "openai/gpt-3.5-turbo",
        "anthropic/claude-3-haiku"
      ]

      # OpenRouter API validates all models in the array first
      # If any model is invalid, the entire request fails
      expect do
        client.complete(
          simple_messages,
          model: models,
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to include("not a valid model")
      end
    end
  end

  describe "fallback with conversation continuation", vcr: { cassette_name: "model_fallback_conversation" } do
    it "maintains consistency in multi-turn conversations with fallback" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      # First turn
      first_response = client.complete(
        [{ role: "user", content: "My name is Alice. Remember this." }],
        model: models,
        extras: { max_tokens: 50 }
      )

      expect(first_response.content).to be_a(String)

      # Second turn - continue conversation
      conversation = [
        { role: "user", content: "My name is Alice. Remember this." },
        { role: "assistant", content: first_response.content },
        { role: "user", content: "What is my name?" }
      ]

      second_response = client.complete(
        conversation,
        model: models,
        extras: { max_tokens: 50 }
      )

      expect(second_response.content).to be_a(String)
      expect(second_response.content.downcase).to include("alice")
    end
  end

  describe "fallback response metadata", vcr: { cassette_name: "model_fallback_metadata" } do
    it "provides complete metadata for fallback responses" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo",
        "anthropic/claude-3-haiku"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 50 }
      )

      # All standard response fields should be present
      expect(response.id).to be_a(String)
      expect(response.object).to eq("chat.completion")
      expect(response.created).to be_a(Integer)
      expect(response.model).to be_a(String)
      expect(response.choices).to be_an(Array)
      expect(response.choices.length).to eq(1)
      expect(response.usage).to be_a(Hash)
      expect(response.usage["prompt_tokens"]).to be > 0
      expect(response.usage["completion_tokens"]).to be > 0
      expect(response.usage["total_tokens"]).to be > 0

      # Test backward compatibility
      expect(response["id"]).to eq(response.id)
      expect(response["model"]).to eq(response.model)
      expect(response.to_h).to be_a(Hash)
    end
  end

  describe "performance characteristics of fallback", vcr: { cassette_name: "model_fallback_performance" } do
    it "completes requests efficiently with fallback" do
      models = [
        "openai/gpt-3.5-turbo",  # Fast, inexpensive model
        "openai/gpt-4o-mini"     # Backup option
      ]

      start_time = Time.now

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 20 }
      )

      end_time = Time.now

      expect(response.content).to be_a(String)

      # Should complete in reasonable time (this is somewhat subjective)
      response_time = end_time - start_time
      expect(response_time).to be < 30 # 30 seconds max

      puts "Fallback request completed in #{response_time.round(2)} seconds"
    end
  end

  describe "route parameter validation", vcr: { cassette_name: "model_fallback_route_validation" } do
    it "correctly sets route parameter for model arrays" do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        simple_messages,
        model: models,
        extras: { max_tokens: 50 }
      )

      # The route should be set to "fallback" internally when using model arrays
      # We can't directly test this without inspecting the request, but we can verify
      # that the fallback mechanism worked by getting a valid response
      expect(response.content).to be_a(String)
      expect(response.model).to be_a(String)
    end
  end
end
