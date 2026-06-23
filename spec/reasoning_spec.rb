# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter reasoning support" do
  let(:client) { OpenRouter::Client.new(access_token: "test") }
  let(:messages) { [{ role: "user", content: "What is 17 * 23? Think step by step." }] }
  let(:mock_response) do
    {
      "id" => "chatcmpl-1",
      "model" => "openai/gpt-5",
      "choices" => [
        { "index" => 0, "message" => { "role" => "assistant", "content" => "391" }, "finish_reason" => "stop" }
      ]
    }
  end

  describe "sending reasoning configuration in chat completions" do
    it "includes the reasoning object in the request parameters" do
      captured = nil
      allow(client).to receive(:post) do |parameters:, **|
        captured = parameters
        mock_response
      end

      client.complete(messages, model: "openai/gpt-5", reasoning: { effort: "high" })

      expect(captured[:reasoning]).to eq({ effort: "high" })
    end

    it "passes through the full reasoning object (max_tokens, exclude)" do
      captured = nil
      allow(client).to receive(:post) do |parameters:, **|
        captured = parameters
        mock_response
      end

      client.complete(messages, model: "openai/gpt-5", reasoning: { max_tokens: 2000, exclude: true })

      expect(captured[:reasoning]).to eq({ max_tokens: 2000, exclude: true })
    end

    it "does not include a reasoning key when none is configured" do
      captured = nil
      allow(client).to receive(:post) do |parameters:, **|
        captured = parameters
        mock_response
      end

      client.complete(messages, model: "openai/gpt-5")

      expect(captured).not_to have_key(:reasoning)
    end

    it "exposes the supported effort levels including the new ones" do
      expect(OpenRouter::REASONING_EFFORT_LEVELS).to include("max", "xhigh", "high", "medium", "low", "minimal", "none")
    end
  end

  describe "parsing reasoning from a chat completion response" do
    let(:raw) do
      {
        "id" => "chatcmpl-2",
        "model" => "openai/gpt-5",
        "choices" => [
          {
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "391",
              "reasoning" => "17 times 23 is 391.",
              "reasoning_details" => [
                { "type" => "reasoning.text", "text" => "17 * 23 = 391", "format" => "openai" }
              ]
            },
            "finish_reason" => "stop"
          }
        ]
      }
    end
    let(:response) { OpenRouter::Response.new(raw) }

    it "exposes the reasoning summary string" do
      expect(response.reasoning).to eq("17 times 23 is 391.")
    end

    it "exposes the structured reasoning_details array" do
      expect(response.reasoning_details).to be_an(Array)
      expect(response.reasoning_details.first["type"]).to eq("reasoning.text")
    end

    it "reports that reasoning is present" do
      expect(response.has_reasoning?).to be true
    end

    it "returns an empty array and false when no reasoning present" do
      plain = OpenRouter::Response.new({ "choices" => [{ "message" => { "content" => "hi" } }] })
      expect(plain.reasoning).to be_nil
      expect(plain.reasoning_details).to eq([])
      expect(plain.has_reasoning?).to be false
    end
  end
end
