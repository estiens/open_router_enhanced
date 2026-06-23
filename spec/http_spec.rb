# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::HTTP do
  let(:client) { OpenRouter::Client.new }

  describe "#uri" do
    it "properly builds URLs with default configuration" do
      # This test just verifies the current working behavior
      result = client.send(:uri, path: "/chat/completions")
      expected = "https://openrouter.ai/api/v1/chat/completions"
      expect(result).to eq(expected)
    end

    context "edge cases with various slash combinations" do
      before do
        allow(client.configuration).to receive(:uri_base).and_return(base)
        allow(client.configuration).to receive(:api_version).and_return(version)
      end

      context "when uri_base has trailing slash" do
        let(:base) { "https://openrouter.ai/" }
        let(:version) { "v1" }

        it "handles path with leading slash correctly" do
          result = client.send(:uri, path: "/chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end

        it "handles path without leading slash correctly" do
          result = client.send(:uri, path: "chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end
      end

      context "when uri_base has no trailing slash" do
        let(:base) { "https://openrouter.ai" }
        let(:version) { "v1" }

        it "handles path with leading slash correctly" do
          result = client.send(:uri, path: "/chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end

        it "handles path without leading slash correctly" do
          result = client.send(:uri, path: "chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end
      end

      context "when api_version has leading slash" do
        let(:base) { "https://openrouter.ai" }
        let(:version) { "/v1" }

        it "handles correctly without double slashes" do
          result = client.send(:uri, path: "/chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end
      end

      context "when api_version has leading and trailing slashes" do
        let(:base) { "https://openrouter.ai" }
        let(:version) { "/v1/" }

        it "handles correctly without double slashes" do
          result = client.send(:uri, path: "/chat/completions")
          expected = "https://openrouter.ai/v1/chat/completions"
          expect(result).to eq(expected)
        end
      end

      context "File.join bug demonstration" do
        let(:base) { "https://openrouter.ai/api" }
        let(:version) { "v1" }

        it "shows the File.join bug with leading slash in path" do
          # This test demonstrates the File.join bug
          result = client.send(:uri, path: "/chat/completions")
          # File.join("https://openrouter.ai/api", "v1", "/chat/completions")
          # incorrectly returns "/chat/completions" (drops base and version)
          expect(result).not_to eq("/chat/completions") # This will fail with current implementation
          expect(result).to eq("https://openrouter.ai/api/v1/chat/completions") # This is what we want
        end
      end
    end
  end

  describe "#conn middleware configuration" do
    it "works correctly after removing MiddlewareErrors reference" do
      # This verifies the fix: MiddlewareErrors reference has been removed
      client.instance_variable_set(:@log_errors, true)

      expect do
        connection = client.send(:conn)
        expect(connection).to be_a(Faraday::Connection)
      end.not_to raise_error
    end

    it "works when @log_errors is false or nil" do
      client.instance_variable_set(:@log_errors, false)

      expect do
        connection = client.send(:conn)
        expect(connection).to be_a(Faraday::Connection)
      end.not_to raise_error
    end
  end

  describe "#to_json_stream" do
    it "parses a single complete SSE data line" do
      received = []
      stream = client.send(:to_json_stream, user_proc: ->(obj) { received << obj })

      stream.call(%({"unused":true}\ndata: {"choices":[{"delta":{"content":"hi"}}]}\n), nil)

      expect(received).to eq([{ "choices" => [{ "delta" => { "content" => "hi" } }] }])
    end

    it "reassembles a data line split across two network chunks" do
      received = []
      stream = client.send(:to_json_stream, user_proc: ->(obj) { received << obj })

      # The JSON object is split mid-way across two chunks, as can happen at a
      # TCP read boundary. The fragment must not be dropped.
      stream.call(%(data: {"choices":[{"delta":{"con), nil)
      stream.call(%(tent":"world"}}]}\n), nil)

      expect(received).to eq([{ "choices" => [{ "delta" => { "content" => "world" } }] }])
    end

    it "ignores SSE comment lines and the [DONE] sentinel" do
      received = []
      stream = client.send(:to_json_stream, user_proc: ->(obj) { received << obj })

      stream.call(": OPENROUTER PROCESSING\n\ndata: [DONE]\n", nil)

      expect(received).to be_empty
    end
  end

  describe "#validate_response!" do
    it "does not raise NoMethodError when the body is a non-JSON String" do
      expect do
        client.send(:validate_response!, "upstream timeout, not json", nil)
      end.not_to raise_error
    end

    it "raises a clean ServerError when the body carries an error hash" do
      expect do
        client.send(:validate_response!, { "error" => { "message" => "boom" } }, nil)
      end.to raise_error(OpenRouter::ServerError, /boom/)
    end
  end
end
