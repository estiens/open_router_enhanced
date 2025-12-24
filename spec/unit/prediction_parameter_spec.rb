# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Prediction Parameter" do
  let(:client) { OpenRouter::Client.new(access_token: "test-key") }

  before do
    allow(OpenRouter::ModelRegistry).to receive(:has_capability?).and_return(true)
  end

  describe "passing prediction to API" do
    it "includes prediction parameter in request" do
      parameters = nil
      allow(client).to receive(:execute_request) do |params|
        parameters = params
        {
          "id" => "test",
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => "openai/gpt-4o",
          "choices" => [{ "message" => { "content" => "The capital of France is Paris." } }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 8, "total_tokens" => 18 }
        }
      end

      client.complete(
        [{ role: "user", content: "What is the capital of France?" }],
        model: "openai/gpt-4o",
        prediction: { type: "content", content: "The capital of France is Paris." }
      )

      expect(parameters[:prediction]).to eq({ type: "content", content: "The capital of France is Paris." })
    end

    it "does not include prediction when nil" do
      parameters = nil
      allow(client).to receive(:execute_request) do |params|
        parameters = params
        {
          "id" => "test",
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => "openai/gpt-4o",
          "choices" => [{ "message" => { "content" => "Hello!" } }],
          "usage" => { "prompt_tokens" => 5, "completion_tokens" => 2, "total_tokens" => 7 }
        }
      end

      client.complete(
        [{ role: "user", content: "Hello" }],
        model: "openai/gpt-4o"
      )

      expect(parameters).not_to have_key(:prediction)
    end
  end
end
