# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter response caching" do
  let(:client) { OpenRouter::Client.new(access_token: "test") }
  let(:messages) { [{ role: "user", content: "Hello" }] }
  let(:mock_response) do
    { "id" => "c1", "model" => "openai/gpt-4o-mini",
      "choices" => [{ "index" => 0, "message" => { "role" => "assistant", "content" => "hi" }, "finish_reason" => "stop" }] }
  end

  describe "building cache request headers" do
    it "enables caching for cache: true" do
      headers = client.send(:build_cache_headers, true)
      expect(headers).to eq("X-OpenRouter-Cache" => "true")
    end

    it "sets a TTL and enables caching for cache: { ttl: 600 }" do
      headers = client.send(:build_cache_headers, { ttl: 600 })
      expect(headers).to eq("X-OpenRouter-Cache" => "true", "X-OpenRouter-Cache-TTL" => "600")
    end

    it "requests a cache clear for cache: { clear: true }" do
      headers = client.send(:build_cache_headers, { clear: true })
      expect(headers["X-OpenRouter-Cache-Clear"]).to eq("true")
    end

    it "returns an empty hash when caching is not configured" do
      expect(client.send(:build_cache_headers, nil)).to eq({})
    end
  end

  describe "threading cache headers through a request" do
    it "passes the cache headers to the HTTP request" do
      captured = nil
      allow(client).to receive(:post) do |**kwargs|
        captured = kwargs[:request_headers]
        mock_response
      end

      client.complete(messages, model: "openai/gpt-4o-mini", cache: { ttl: 300 })

      expect(captured).to include("X-OpenRouter-Cache" => "true", "X-OpenRouter-Cache-TTL" => "300")
    end

    it "does not send the cache option in the request body" do
      captured = nil
      allow(client).to receive(:post) do |parameters:, **_kwargs|
        captured = parameters
        mock_response
      end

      client.complete(messages, model: "openai/gpt-4o-mini", cache: true)

      expect(captured).not_to have_key(:cache)
    end
  end

  describe "reading cache status from a response" do
    it "reports a cache hit from response metadata" do
      response = OpenRouter::Response.new(mock_response)
      client.send(:apply_cache_metadata!, response,
                  { headers: { "x-openrouter-cache-status" => "HIT", "x-openrouter-cache-age" => "12",
                               "x-openrouter-cache-ttl" => "300" } })

      expect(response.cache_status).to eq("HIT")
      expect(response.cache_hit?).to be true
      expect(response.cache_age).to eq("12")
    end

    it "reports a miss and is not a hit" do
      response = OpenRouter::Response.new(mock_response)
      client.send(:apply_cache_metadata!, response, { headers: { "x-openrouter-cache-status" => "MISS" } })

      expect(response.cache_status).to eq("MISS")
      expect(response.cache_hit?).to be false
    end

    it "defaults to no cache status when none present" do
      response = OpenRouter::Response.new(mock_response)
      expect(response.cache_status).to be_nil
      expect(response.cache_hit?).to be false
    end
  end
end
