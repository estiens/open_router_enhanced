# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Comprehensive Integration", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  describe "Multi-turn Tool Calling with Structured Output" do
    let(:research_tool) do
      OpenRouter::Tool.define do
        name "research_topic"
        description "Research information about a topic"
        parameters do
          string "topic", required: true, description: "Topic to research"
        end
      end
    end

    let(:research_schema) do
      OpenRouter::Schema.define("research_result") do
        string :topic, required: true, description: "Research topic"
        array :key_findings, items: { type: "string" }, description: "Key research findings"
        number :confidence_score, required: true, description: "Confidence in findings (0-1)"
      end
    end

    it "handles tool calling with structured output in multi-turn conversation",
       vcr: { cassette_name: "integration_multi_turn_workflow" } do
      pending "VCR cassette mismatch - needs re-recording with current API"

      messages = [
        { role: "system", content: "You are a research assistant with access to tools." },
        { role: "user", content: "Research quantum computing." }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [research_tool],
        tool_choice: "auto",
        extras: { max_tokens: 300 }
      )

      expect(response).to be_a(OpenRouter::Response)

      if response.has_tool_calls?
        response.tool_calls.each do |tool_call|
          result = tool_call.execute do |args|
            "Research on #{args["topic"]}: Quantum computing is a rapidly growing field."
          end
          messages << result.to_message
        end

        messages << { role: "user", content: "Provide a structured summary in JSON format." }

        final_response = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          response_format: {
            type: "json_schema",
            json_schema: research_schema.to_h
          },
          extras: { max_tokens: 200 }
        )

        structured_result = final_response.structured_output
        expect(structured_result).to be_a(Hash)
        expect(structured_result).to have_key("topic")
        expect(structured_result).to have_key("key_findings")
        expect(structured_result).to have_key("confidence_score")
      end
    end
  end

  describe "Model Fallback with Feature Integration" do
    it "demonstrates model fallbacks with tools and structured outputs",
       vcr: { cassette_name: "integration_model_fallback_features" } do
      pending "VCR cassette mismatch - needs re-recording with current API"

      messages = [
        { role: "user", content: "Explain machine learning in simple terms." }
      ]

      response = client.complete(
        messages,
        model: ["some/expensive-model", "openai/gpt-3.5-turbo"],
        extras: { max_tokens: 200 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)
      expect(response.content.length).to be > 50
    end
  end
end
