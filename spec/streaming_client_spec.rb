# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::StreamingClient do
  let(:client) { described_class.new(access_token: "test-key") }

  describe "initialization" do
    it "inherits from Client" do
      expect(client).to be_a(OpenRouter::Client)
    end

    it "initializes streaming callbacks" do
      expect(client.instance_variable_get(:@streaming_callbacks)).to be_a(Hash)
      expect(client.instance_variable_get(:@streaming_callbacks)).to have_key(:on_chunk)
    end

    it "supports all Client initialization options" do
      streaming_client = described_class.new(
        access_token: "test-key",
        track_usage: false
      )

      expect(streaming_client.usage_tracker).to be_nil
    end
  end

  describe "#on_stream" do
    it "registers streaming callbacks for valid events" do
      callback_called = false

      expect do
        client.on_stream(:on_chunk) { |_chunk| callback_called = true }
      end.not_to raise_error

      callbacks = client.instance_variable_get(:@streaming_callbacks)
      expect(callbacks[:on_chunk].length).to eq(1)
    end

    it "raises error for invalid streaming events" do
      expect do
        client.on_stream(:invalid_event) { |data| }
      end.to raise_error(ArgumentError, /Invalid streaming event: invalid_event/)
    end

    it "supports method chaining" do
      result = client.on_stream(:on_chunk) { |chunk| }
                     .on_stream(:on_start) { |data| }

      expect(result).to eq(client)
    end
  end

  describe "#stream_complete" do
    let(:mock_chunks) do
      [
        {
          "id" => "chatcmpl-123",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "openai/gpt-4o-mini",
          "choices" => [
            {
              "index" => 0,
              "delta" => { "role" => "assistant", "content" => "Hello" },
              "finish_reason" => nil
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "openai/gpt-4o-mini",
          "choices" => [
            {
              "index" => 0,
              "delta" => { "content" => " world" },
              "finish_reason" => nil
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "openai/gpt-4o-mini",
          "choices" => [
            {
              "index" => 0,
              "delta" => {},
              "finish_reason" => "stop"
            }
          ],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      ]
    end

    before do
      # Mock the complete method to simulate streaming
      allow(client).to receive(:complete) do |*_args, **kwargs|
        mock_chunks.each { |chunk| kwargs[:stream].call(chunk) } if kwargs[:stream]
        nil
      end
    end

    it "triggers on_start callback" do
      start_data = nil
      client.on_stream(:on_start) { |data| start_data = data }

      client.stream_complete(
        [{ role: "user", content: "Hello" }],
        model: "openai/gpt-4o-mini"
      )

      expect(start_data).to include(model: "openai/gpt-4o-mini")
      expect(start_data[:messages]).to eq([{ role: "user", content: "Hello" }])
    end

    it "triggers on_chunk callback for each chunk" do
      chunks_received = []
      client.on_stream(:on_chunk) { |chunk| chunks_received << chunk }

      client.stream_complete([{ role: "user", content: "Hello" }])

      expect(chunks_received.length).to eq(3)
      expect(chunks_received.first["id"]).to eq("chatcmpl-123")
    end

    it "triggers on_finish callback" do
      finish_data = nil
      client.on_stream(:on_finish) { |response| finish_data = response }

      result = client.stream_complete(
        [{ role: "user", content: "Hello" }],
        accumulate_response: true
      )

      expect(finish_data).to eq(result)
      expect(finish_data).to be_a(OpenRouter::Response)
    end

    it "returns accumulated response when requested" do
      result = client.stream_complete(
        [{ role: "user", content: "Hello" }],
        accumulate_response: true
      )

      expect(result).to be_a(OpenRouter::Response)
      expect(result.content).to eq("Hello world")
    end

    it "returns nil when not accumulating response" do
      result = client.stream_complete(
        [{ role: "user", content: "Hello" }],
        accumulate_response: false
      )

      expect(result).to be_nil
    end

    it "triggers on_error callback when error occurs" do
      error_data = nil
      client.on_stream(:on_error) { |error| error_data = error }

      allow(client).to receive(:complete).and_raise(StandardError, "test error")

      expect do
        client.stream_complete([{ role: "user", content: "Hello" }])
      end.to raise_error(StandardError, "test error")

      expect(error_data).to be_a(StandardError)
      expect(error_data.message).to eq("test error")
    end
  end

  describe "#stream" do
    before do
      # Mock streaming response
      allow(client).to receive(:stream_complete) do |*_args, **_kwargs, &block|
        mock_chunks = [
          { "choices" => [{ "delta" => { "content" => "Hello" } }] },
          { "choices" => [{ "delta" => { "content" => " world" } }] },
          { "choices" => [{ "delta" => {} }] }
        ]

        mock_chunks.each { |chunk| block&.call(chunk) }
        nil
      end
    end

    it "yields content chunks to block" do
      content_chunks = []

      client.stream([{ role: "user", content: "Hello" }]) do |chunk|
        content_chunks << chunk
      end

      expect(content_chunks).to eq(["Hello", " world"])
    end

    it "raises error when no block given" do
      expect do
        client.stream([{ role: "user", content: "Hello" }])
      end.to raise_error(ArgumentError, "Block required for streaming")
    end

    it "passes model parameter correctly" do
      expect(client).to receive(:stream_complete).with(
        [{ role: "user", content: "Hello" }],
        hash_including(model: "openai/gpt-4o-mini", accumulate_response: false)
      )

      client.stream(
        [{ role: "user", content: "Hello" }],
        model: "openai/gpt-4o-mini"
      ) { |chunk| }
    end
  end

  describe "tool call streaming" do
    let(:tool_call_chunks) do
      [
        {
          "choices" => [
            {
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "id" => "call_123",
                    "type" => "function",
                    "function" => { "name" => "get_weather" }
                  }
                ]
              }
            }
          ]
        },
        {
          "choices" => [
            {
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => { "arguments" => "{\"location\":" }
                  }
                ]
              }
            }
          ]
        },
        {
          "choices" => [
            {
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => { "arguments" => "\"New York\"}" }
                  }
                ]
              }
            }
          ]
        }
      ]
    end

    before do
      allow(client).to receive(:complete) do |*_args, **kwargs|
        tool_call_chunks.each { |chunk| kwargs[:stream].call(chunk) } if kwargs[:stream]
        nil
      end
    end

    it "triggers on_tool_call_chunk callback" do
      tool_chunks = []
      client.on_stream(:on_tool_call_chunk) { |chunk| tool_chunks << chunk }

      client.stream_complete([{ role: "user", content: "Get weather" }])

      expect(tool_chunks.length).to eq(3)
      expect(tool_chunks.first.dig("choices", 0, "delta", "tool_calls")).to be_present
    end
  end
end

RSpec.describe OpenRouter::ResponseAccumulator do
  let(:accumulator) { described_class.new }

  describe "#add_chunk" do
    let(:content_chunks) do
      [
        {
          "id" => "chatcmpl-123",
          "object" => "chat.completion.chunk",
          "created" => 1_234_567_890,
          "model" => "openai/gpt-4o-mini",
          "choices" => [
            {
              "index" => 0,
              "delta" => { "role" => "assistant", "content" => "Hello" },
              "finish_reason" => nil
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "choices" => [
            {
              "index" => 0,
              "delta" => { "content" => " world" },
              "finish_reason" => nil
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "choices" => [
            {
              "index" => 0,
              "delta" => {},
              "finish_reason" => "stop"
            }
          ],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      ]
    end

    it "accumulates content from chunks" do
      content_chunks.each { |chunk| accumulator.add_chunk(chunk) }

      response = accumulator.build_response
      expect(response.content).to eq("Hello world")
    end

    it "preserves metadata from first and last chunks" do
      content_chunks.each { |chunk| accumulator.add_chunk(chunk) }

      response = accumulator.build_response
      expect(response.id).to eq("chatcmpl-123")
      expect(response.model).to eq("openai/gpt-4o-mini")
      expect(response.finish_reason).to eq("stop")
      expect(response.usage).to eq({ "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 })
    end
  end

  describe "tool call accumulation" do
    let(:tool_call_chunks) do
      [
        {
          "id" => "chatcmpl-123",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "role" => "assistant",
                "tool_calls" => [
                  {
                    "index" => 0,
                    "id" => "call_123",
                    "type" => "function",
                    "function" => { "name" => "get_weather", "arguments" => "" }
                  }
                ]
              }
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => { "arguments" => "{\"location\":" }
                  }
                ]
              }
            }
          ]
        },
        {
          "id" => "chatcmpl-123",
          "choices" => [
            {
              "index" => 0,
              "delta" => {
                "tool_calls" => [
                  {
                    "index" => 0,
                    "function" => { "arguments" => "\"New York\"}" }
                  }
                ]
              },
              "finish_reason" => "tool_calls"
            }
          ]
        }
      ]
    end

    it "accumulates tool call arguments" do
      tool_call_chunks.each { |chunk| accumulator.add_chunk(chunk) }

      response = accumulator.build_response
      tool_calls = response.tool_calls

      expect(tool_calls.length).to eq(1)
      expect(tool_calls.first.name).to eq("get_weather")
      expect(tool_calls.first.arguments).to eq({ "location" => "New York" })
    end
  end

  describe "#build_response" do
    it "returns nil for empty accumulator" do
      response = accumulator.build_response
      expect(response).to be_nil
    end
  end
end
