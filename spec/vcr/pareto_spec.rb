# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Pareto Code Router", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }
  let(:messages) { [{ role: "user", content: "Write a Ruby method that merges two sorted arrays." }] }

  it "routes to the cheapest code-capable model meeting the score",
     vcr: { cassette_name: "pareto_basic" } do
    response = client.pareto_complete(messages, min_coding_score: 0.5, max_tokens: 200)

    expect(response).to be_a(OpenRouter::Response)
    # The router resolves to a concrete model, surfaced via selected_model.
    # This is the primary assertion: pareto routing selects a concrete model, not the router alias.
    expect(response.selected_model).to be_a(String)
    expect(response.selected_model).not_to eq("openrouter/pareto-code")
    # Note: when the selected model is a reasoning model and max_tokens is small,
    # the model may exhaust tokens during reasoning and return nil content.
    # The content check is conditional on what the real API returned.
    if response.content
      expect(response.content).to be_a(String)
    else
      # Reasoning model hit token limit during thinking — finish_reason is "length"
      expect(response.finish_reason).to eq("length")
    end
  end

  it "propagates a real API error for an invalid request",
     vcr: { cassette_name: "pareto_error" } do
    # Bypass client-side validation to capture genuine server-side rejection:
    # a malformed pareto-router plugin value the API rejects.
    expect do
      client.complete(
        messages,
        model: "openrouter/pareto-code",
        plugins: [{ id: "pareto-router", min_coding_score: "definitely-not-a-number" }],
        max_tokens: 50
      )
    end.to raise_error(OpenRouter::ServerError)
  end
end
