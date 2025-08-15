# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Streaming", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:streaming_client) do
    OpenRouter::StreamingClient.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  describe "basic streaming completions" do
    it "streams a simple completion", vcr: { cassette_name: "streaming_simple_completion" } do
      messages = [
        { role: "user", content: "Count from 1 to 5" }
      ]

      chunks = []
      content = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        content += chunk.dig("choices", 0, "delta", "content") if chunk.dig("choices", 0, "delta", "content")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        accumulate_response: true,
        extras: { max_tokens: 100 }
      )

      expect(chunks).not_to be_empty
      expect(content).to include("1")
      expect(chunks.first).to have_key("choices")

      # Verify streaming structure
      expect(chunks.any? { |chunk| chunk.dig("choices", 0, "delta", "content") }).to be true
    end

    it "handles streaming with system messages", vcr: { cassette_name: "streaming_with_system" } do
      messages = [
        { role: "system", content: "You are a helpful assistant. Be concise." },
        { role: "user", content: "What is the capital of France?" }
      ]

      chunks = []
      final_content = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        final_content += chunk.dig("choices", 0, "delta", "content") if chunk.dig("choices", 0, "delta", "content")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(chunks).not_to be_empty
      expect(final_content.downcase).to include("paris")
    end
  end

  describe "streaming with tools" do
    let(:simple_tool) do
      OpenRouter::Tool.define do
        name "get_time"
        description "Get the current time"
        parameters do
          string "timezone", required: false, description: "Timezone (optional)"
        end
      end
    end

    it "handles tool calls in streaming mode", vcr: { cassette_name: "streaming_with_tools" } do
      messages = [
        { role: "user", content: "What time is it?" }
      ]

      chunks = []
      tool_calls_found = false

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        tool_calls_found = true if chunk.dig("choices", 0, "delta", "tool_calls")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-4o-mini",
        tools: [simple_tool],
        tool_choice: "auto",
        extras: { max_tokens: 200 }
      )

      expect(chunks).not_to be_empty
      expect(tool_calls_found).to be true

      # Find the chunk with tool call information
      tool_chunk = chunks.find { |chunk| chunk.dig("choices", 0, "delta", "tool_calls") }
      expect(tool_chunk).not_to be_nil
    end
  end

  describe "streaming error handling" do
    it "handles authentication errors gracefully", vcr: { cassette_name: "streaming_auth_error" } do
      bad_client = OpenRouter::StreamingClient.new(access_token: "invalid_token")

      messages = [
        { role: "user", content: "Hello" }
      ]

      expect do
        bad_client.stream_complete(messages, model: "openai/gpt-3.5-turbo")
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "handles invalid model errors", vcr: { cassette_name: "streaming_invalid_model" } do
      messages = [
        { role: "user", content: "Hello" }
      ]

      expect do
        streaming_client.stream_complete(messages, model: "invalid/nonexistent-model")
      end.to raise_error(OpenRouter::ServerError)
    end
  end

  describe "streaming configuration" do
    it "respects max_tokens parameter", vcr: { cassette_name: "streaming_max_tokens" } do
      messages = [
        { role: "user", content: "Write a very long story about a dragon" }
      ]

      chunks = []
      content = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        content += chunk.dig("choices", 0, "delta", "content") if chunk.dig("choices", 0, "delta", "content")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      # Should be limited by max_tokens
      expect(content.split.count).to be <= 25 # Allow some flexibility
    end

    it "respects temperature parameter", vcr: { cassette_name: "streaming_temperature" } do
      messages = [
        { role: "user", content: "Say exactly: 'Hello world'" }
      ]

      chunks = []
      content = ""

      streaming_client.on_stream(:on_chunk) do |chunk|
        chunks << chunk
        content += chunk.dig("choices", 0, "delta", "content") if chunk.dig("choices", 0, "delta", "content")
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { temperature: 0.1, max_tokens: 10 }
      )

      expect(chunks).not_to be_empty
      expect(content).not_to be_empty
    end
  end

  describe "streaming with model fallbacks" do
    it "does not support model arrays in streaming mode", vcr: { cassette_name: "streaming_fallback_models" } do
      messages = [
        { role: "user", content: "Say 'Hello from fallback'" }
      ]

      # Model fallback arrays are not supported in streaming mode
      # OpenRouter returns a 400 error when attempting to use them
      expect do
        streaming_client.stream_complete(
          messages,
          model: ["some/nonexistent-model", "openai/gpt-3.5-turbo"],
          extras: { max_tokens: 20 }
        )
      end.to raise_error(OpenRouter::ServerError, /Bad Request/)
    end
  end

  describe "streaming response accumulation" do
    it "can accumulate streaming responses", vcr: { cassette_name: "streaming_accumulation" } do
      messages = [
        { role: "user", content: "List three colors" }
      ]

      accumulated_response = streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        accumulate_response: true,
        extras: { max_tokens: 50 }
      )

      expect(accumulated_response).not_to be_nil
      expect(accumulated_response).to be_a(OpenRouter::Response)
      expect(accumulated_response.content).not_to be_empty
    end
  end

  describe "streaming performance characteristics" do
    it "receives chunks in reasonable time intervals", vcr: { cassette_name: "streaming_timing" } do
      messages = [
        { role: "user", content: "Count slowly from 1 to 10" }
      ]

      chunk_times = []
      start_time = Time.now

      streaming_client.on_stream(:on_chunk) do |_chunk|
        chunk_times << (Time.now - start_time)
      end

      streaming_client.stream_complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 100 }
      )

      expect(chunk_times).not_to be_empty
      # First chunk should arrive relatively quickly (within 10 seconds)
      expect(chunk_times.first).to be < 10.0
    end
  end
end
