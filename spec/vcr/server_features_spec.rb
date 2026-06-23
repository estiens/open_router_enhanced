# frozen_string_literal: true

require "spec_helper"

# Live, VCR-backed coverage for the Chat Completions reasoning option, OpenRouter
# server tools (web_search), and response caching. These hit the real API when no
# cassette exists and otherwise replay recorded fixtures, so they run offline in
# CI. To re-record, run with a valid OPENROUTER_API_KEY and VCR_RECORD_NEW=true
# (or delete the cassette to re-record just that one).
RSpec.describe "OpenRouter API features", :vcr do
  let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

  describe "reasoning on chat completions", vcr: { cassette_name: "server_features_reasoning" } do
    it "sends the reasoning object and parses reasoning back from the response" do
      response = client.complete(
        [{ role: "user", content: "What is 17 * 23? Think briefly, then state the number." }],
        model: "deepseek/deepseek-r1",
        reasoning: { effort: "low" }
      )

      expect(response.content).to include("391")
      expect(response.has_reasoning?).to be true
      expect(response.reasoning_details).to be_an(Array)
    end
  end

  describe "web_search server tool", vcr: { cassette_name: "server_features_web_search" } do
    it "completes a request that carries an openrouter:web_search server tool" do
      response = client.complete(
        [{ role: "user", content: "Give me one recent headline about space exploration." }],
        model: "openai/gpt-4o-mini",
        tools: [OpenRouter::ServerTool.web_search(max_results: 1)]
      )

      expect(response.content).to be_a(String)
      expect(response.content).not_to be_empty
    end
  end

  describe "response caching",
           vcr: { cassette_name: "server_features_caching", allow_playback_repeats: false } do
    it "serves an identical second request from the cache (MISS then HIT)" do
      messages = [{ role: "user", content: "Reply with exactly: cached-pong" }]
      params = { model: "openai/gpt-4o-mini", temperature: 0, cache: true }

      first = client.complete(messages, **params)
      second = client.complete(messages, **params)

      expect(first.content).not_to be_empty
      expect(second.cache_hit?).to be true
      expect(second.cache_age).not_to be_nil
    end
  end
end
