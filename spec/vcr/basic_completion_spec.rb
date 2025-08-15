# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Basic Completions", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:simple_messages) do
    [{ role: "user", content: "Say hello world" }]
  end

  describe "single model completion", vcr: { cassette_name: "basic_completion_single_model" } do
    it "completes a simple message with gpt-3.5-turbo" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)
      expect(response.content.length).to be > 0
      expect(response.id).to be_a(String)
      expect(response.model).to include("gpt-3.5-turbo")
      expect(response.usage).to be_a(Hash)
      expect(response.usage["prompt_tokens"]).to be > 0
      expect(response.usage["completion_tokens"]).to be > 0
      expect(response.usage["total_tokens"]).to be > 0
    end
  end

  describe "completion with parameters", vcr: { cassette_name: "basic_completion_with_parameters" } do
    it "respects max_tokens parameter" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        extras: {
          max_tokens: 10,
          temperature: 0.7,
          top_p: 0.9
        }
      )

      expect(response.content).to be_a(String)
      expect(response.usage["completion_tokens"]).to be <= 10
    end
  end

  describe "completion with different models", vcr: { cassette_name: "basic_completion_different_models" } do
    it "works with Claude model" do
      response = client.complete(
        simple_messages,
        model: "anthropic/claude-3-haiku",
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to include("claude-3-haiku")
      expect(response.usage).to be_a(Hash)
    end

    it "works with GPT-4 model" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-4o-mini",
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to include("gpt-4o-mini")
      expect(response.usage).to be_a(Hash)
    end
  end

  describe "conversation continuation", vcr: { cassette_name: "basic_completion_conversation" } do
    it "handles multi-turn conversations" do
      messages = [
        { role: "user", content: "What is 2+2?" },
        { role: "assistant", content: "2+2 equals 4." },
        { role: "user", content: "What about 3+3?" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.content.downcase).to include("6")
    end
  end

  describe "system message support", vcr: { cassette_name: "basic_completion_system_message" } do
    it "respects system messages" do
      messages = [
        { role: "system", content: "You are a helpful assistant that always responds in all caps." },
        { role: "user", content: "Hello" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.content).to eq(response.content.upcase)
    end
  end

  describe "response metadata", vcr: { cassette_name: "basic_completion_metadata" } do
    it "includes all expected response fields" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      # Test Response object methods
      expect(response.id).to be_a(String)
      expect(response.object).to eq("chat.completion")
      expect(response.created).to be_a(Integer)
      expect(response.model).to be_a(String)
      expect(response.choices).to be_an(Array)
      expect(response.choices.length).to eq(1)

      # Test choice structure
      choice = response.choices.first
      expect(choice["message"]["role"]).to eq("assistant")
      expect(choice["message"]["content"]).to be_a(String)
      expect(%w[stop length]).to include(choice["finish_reason"])

      # Test usage information
      expect(response.usage["prompt_tokens"]).to be > 0
      expect(response.usage["completion_tokens"]).to be > 0
      expect(response.usage["total_tokens"]).to be > 0

      # Test convenience methods
      expect(response.has_content?).to be true
      expect(response.error?).to be false
      expect(response.has_tool_calls?).to be false
    end
  end

  describe "backward compatibility", vcr: { cassette_name: "basic_completion_backward_compatibility" } do
    it "maintains hash access patterns" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      # Test hash-style access (backward compatibility)
      expect(response["id"]).to eq(response.id)
      expect(response["model"]).to eq(response.model)
      expect(response["usage"]).to eq(response.usage)
      expect(response.dig("choices", 0, "message", "content")).to eq(response.content)
      expect(response.key?("id")).to be true
      expect(response.key?("nonexistent")).to be false

      # Test to_h conversion
      hash_response = response.to_h
      expect(hash_response).to be_a(Hash)
      expect(hash_response["id"]).to eq(response.id)
    end
  end

  describe "providers parameter", vcr: { cassette_name: "basic_completion_providers" } do
    it "accepts provider preferences" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        providers: ["openai"],
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.model).to include("gpt-3.5-turbo")
    end
  end

  describe "transforms parameter", vcr: { cassette_name: "basic_completion_transforms" } do
    it "accepts transform instructions" do
      response = client.complete(
        simple_messages,
        model: "openai/gpt-3.5-turbo",
        transforms: ["middle-out"],
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
    end
  end
end
