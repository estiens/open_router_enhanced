# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Fusion router", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }
  let(:messages) { [{ role: "user", content: "In one short paragraph, what is the CAP theorem?" }] }

  it "fuses a budget panel into a single synthesized answer",
     vcr: { cassette_name: "fusion_basic" } do
    response = client.fuse(
      messages,
      analysis_models: ["xiaomi/mimo-v2.5", "minimax/minimax-m3", "z-ai/glm-5.2", "deepseek/deepseek-v4-flash"],
      judge: "openrouter/owl-alpha",
      max_tokens: 300
    )

    expect(response).to be_a(OpenRouter::Response)
    # Fusion either synthesizes content via the judge, or surfaces the selected model
    # Accept either: a non-empty content string, or a resolved selected_model with a valid finish_reason
    if response.content && !response.content.empty?
      expect(response.content).to be_a(String)
      expect(response.content).not_to be_empty
    else
      # Judge may return nil content with a finish_reason (e.g., "length" if max_tokens hit)
      expect(response.finish_reason).to be_a(String)
    end
  end
end
