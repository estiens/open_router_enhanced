# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "OpenRouter Performance Regression Tests", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Simple smoke tests to ensure API calls complete in reasonable time
  # Not comprehensive benchmarks - just regression protection

  it "completes simple requests within reasonable time", vcr: { cassette_name: "performance_simple_response_time" } do
    messages = [{ role: "user", content: "Hello, world!" }]

    response_time = Benchmark.realtime do
      @response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )
    end

    expect(@response).to be_a(OpenRouter::Response)
    expect(@response.content).not_to be_empty
    expect(response_time).to be < 30.0 # 30 seconds max for simple request
  end

  it "handles complex requests without hanging", vcr: { cassette_name: "performance_complex_response_time" } do
    complex_prompt = "Write a detailed analysis of machine learning algorithms, covering supervised learning, unsupervised learning, and reinforcement learning. Include examples and use cases for each type."
    messages = [{ role: "user", content: complex_prompt }]

    response_time = Benchmark.realtime do
      @response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        extras: { max_tokens: 500 }
      )
    end

    expect(@response.content.length).to be > 200
    expect(response_time).to be < 60.0 # 60 seconds max for complex request
  end
end
