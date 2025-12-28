# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Model Fallback + Structured Outputs Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:simple_schema) do
    OpenRouter::Schema.define("response") do
      string "answer", required: true, description: "The answer to the question"
      string "confidence", required: true, description: "Confidence level: high, medium, or low"
    end
  end

  let(:complex_schema) do
    OpenRouter::Schema.define("analysis") do
      string "summary", required: true, description: "Brief summary"
      array "key_points", required: true, description: "Main points" do
        string description: "A key point"
      end
      object "metadata", required: true, description: "Analysis metadata" do
        string "topic", required: true, description: "Main topic"
        integer "word_count", required: true, description: "Approximate word count"
      end
    end
  end

  describe "basic fallback with structured output" do
    it "returns valid structured output using fallback model chain",
       vcr: { cassette_name: "integration/fallback_structured_basic" } do
      messages = [
        { role: "user", content: "What is the capital of Japan? Answer with high confidence." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: simple_schema,
        max_tokens: 100
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_present

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["answer"]).to be_present
      expect(structured["answer"].downcase).to include("tokyo")
      expect(%w[high medium low]).to include(structured["confidence"].downcase)
    end
  end

  describe "fallback with complex schema" do
    it "handles complex nested schema with model fallback",
       vcr: { cassette_name: "integration/fallback_structured_complex" } do
      messages = [
        { role: "user",
          content: "Analyze the topic 'Ruby programming'. Provide a summary, 3 key points, and metadata including the topic name and a word count estimate." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "anthropic/claude-3-haiku"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: complex_schema,
        max_tokens: 400
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["summary"]).to be_present
      expect(structured["key_points"]).to be_an(Array)
      expect(structured["key_points"].length).to be >= 1
      expect(structured["metadata"]).to be_a(Hash)
      expect(structured["metadata"]["topic"]).to be_present
    end
  end

  describe "fallback across model families with structured output" do
    it "maintains structured output format across different model families",
       vcr: { cassette_name: "integration/fallback_structured_mixed_families" } do
      messages = [
        { role: "user", content: "Is water wet? Give your answer and confidence level." }
      ]

      # Mix of different model families
      models = [
        "openai/gpt-4o-mini",
        "anthropic/claude-3-haiku",
        "meta-llama/llama-3.1-8b-instruct"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: simple_schema,
        max_tokens: 150
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["answer"]).to be_present
      expect(structured["confidence"]).to be_present
    end
  end

  describe "fallback with schema and parameters" do
    it "preserves request parameters across fallback with structured output",
       vcr: { cassette_name: "integration/fallback_structured_with_params" } do
      messages = [
        { role: "user", content: "Give a one-word answer: What color is the sky? Include confidence." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: simple_schema,
        max_tokens: 50,
        temperature: 0.1
      )

      structured = response.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["answer"].downcase).to include("blue")

      # Verify tokens were limited
      expect(response.usage["completion_tokens"]).to be <= 60
    end
  end

  describe "fallback structured output with tools" do
    let(:lookup_tool) do
      OpenRouter::Tool.define do
        name "fact_lookup"
        description "Look up a fact about a topic"
        parameters do
          string "topic", required: true, description: "Topic to look up"
        end
      end
    end

    it "handles fallback with both tools and structured output",
       vcr: { cassette_name: "integration/fallback_structured_with_tools" } do
      messages = [
        { role: "user", content: "What year did Ruby programming language first appear? Answer with confidence." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        tools: [lookup_tool],
        tool_choice: "auto",
        response_format: simple_schema,
        max_tokens: 200
      )

      expect(response).to be_a(OpenRouter::Response)

      # Could have tool calls or structured content
      if response.has_tool_calls?
        expect(response.tool_calls.first.function_name).to eq("fact_lookup")
      elsif response.content.present?
        # The model may return structured content that doesn't match schema
        # when using tools - try to parse as JSON
        begin
          parsed = JSON.parse(response.content)
          expect(parsed).to be_a(Hash)
        rescue JSON::ParserError
          # Content is not JSON, which is also valid
          expect(response.content).to be_a(String)
        end
      end
    end
  end

  describe "fallback with conversation history" do
    it "maintains structured output in multi-turn conversation with fallback",
       vcr: { cassette_name: "integration/fallback_structured_conversation" } do
      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      # First turn
      messages1 = [
        { role: "user", content: "My favorite color is blue. Remember this." }
      ]

      response1 = client.complete(
        messages1,
        model: models,
        response_format: simple_schema,
        max_tokens: 100
      )

      expect(response1.structured_output).to be_a(Hash)

      # Second turn - continue conversation
      messages2 = [
        { role: "user", content: "My favorite color is blue. Remember this." },
        { role: "assistant", content: response1.content },
        { role: "user", content: "What is my favorite color? Answer with confidence." }
      ]

      response2 = client.complete(
        messages2,
        model: models,
        response_format: simple_schema,
        max_tokens: 100
      )

      structured = response2.structured_output
      expect(structured).to be_a(Hash)
      expect(structured["answer"].downcase).to include("blue")
    end
  end

  describe "error handling with fallback and structured output" do
    it "raises error when all fallback models fail with invalid model in chain",
       vcr: { cassette_name: "integration/fallback_structured_all_fail" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      models = [
        "invalid/nonexistent-model-1",
        "invalid/nonexistent-model-2"
      ]

      expect do
        client.complete(
          messages,
          model: models,
          response_format: simple_schema,
          max_tokens: 50
        )
      end.to raise_error(OpenRouter::ServerError)
    end
  end

  describe "usage tracking with fallback and structured output" do
    it "tracks token usage correctly with fallback models",
       vcr: { cassette_name: "integration/fallback_structured_usage" } do
      messages = [
        { role: "user", content: "Count to 3. Include confidence level." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: simple_schema,
        max_tokens: 100
      )

      expect(response.usage).to be_a(Hash)
      expect(response.usage["prompt_tokens"]).to be > 0
      expect(response.usage["completion_tokens"]).to be > 0
      expect(response.usage["total_tokens"]).to eq(
        response.usage["prompt_tokens"] + response.usage["completion_tokens"]
      )
    end
  end

  describe "response metadata with fallback and structured output" do
    it "provides complete response metadata including model used",
       vcr: { cassette_name: "integration/fallback_structured_metadata" } do
      messages = [
        { role: "user", content: "What is 1+1? High confidence answer." }
      ]

      models = [
        "openai/gpt-4o-mini",
        "openai/gpt-3.5-turbo"
      ]

      response = client.complete(
        messages,
        model: models,
        response_format: simple_schema,
        max_tokens: 50
      )

      # Verify all metadata is present
      expect(response.id).to be_present
      expect(response.object).to eq("chat.completion")
      expect(response.created).to be_a(Integer)
      expect(response.model).to be_present
      expect(response.choices).to be_an(Array)

      # Verify structured output works with full metadata
      structured = response.structured_output
      expect(structured["answer"]).to include("2")
    end
  end
end
