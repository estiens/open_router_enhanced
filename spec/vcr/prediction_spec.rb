# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Prediction Parameter", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

  it "sends prediction to OpenRouter for latency optimization", vcr: { cassette_name: "prediction_parameter" } do
    response = client.complete(
      [{ role: "user", content: "What is the capital of France?" }],
      model: "openai/gpt-4o-mini",
      prediction: { type: "content", content: "The capital of France is Paris." },
      extras: { max_tokens: 50 }
    )

    expect(response).to be_a(OpenRouter::Response)
    expect(response.content).to include("Paris")
  end
end
