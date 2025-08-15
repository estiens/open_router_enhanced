# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Client Capability Validation" do
  let(:mock_models) do
    {
      "basic/text-model" => {
        name: "Basic Text Model",
        capabilities: [:chat],
        cost_per_1k_tokens: { input: 0.0005, output: 0.001 },
        context_length: 2048
      },
      "advanced/tool-model" => {
        name: "Advanced Tool Model",
        capabilities: %i[chat function_calling],
        cost_per_1k_tokens: { input: 0.001, output: 0.002 },
        context_length: 4096
      },
      "vision/multimodal-model" => {
        name: "Vision Multimodal Model",
        capabilities: %i[chat vision structured_outputs],
        cost_per_1k_tokens: { input: 0.01, output: 0.03 },
        context_length: 8192
      }
    }
  end

  before do
    allow(OpenRouter::ModelRegistry).to receive(:all_models).and_return(mock_models)
    # Mock HTTP to avoid actual API calls
    allow_any_instance_of(OpenRouter::Client).to receive(:post).and_raise(Faraday::UnauthorizedError.new("Mocked error"))
  end

  describe "strict mode disabled (default)" do
    let(:client) do
      OpenRouter::Client.new(access_token: "test_token") do |config|
        config.strict_mode = false
      end
    end

    it "shows warnings for unsupported tool calling but allows request" do
      # Expected API error, not capability error
      expect do
        expect do
          client.complete(
            [{ role: "user", content: "Hello" }],
            model: "basic/text-model",
            tools: [{ name: "test_tool", description: "A test tool" }]
          )
        end.to output(/OpenRouter Warning.*tool calling/).to_stderr
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "shows warnings for unsupported structured outputs but allows request" do
      expect do
        expect do
          client.complete(
            [{ role: "user", content: "Hello" }],
            model: "basic/text-model",
            response_format: { type: "json_schema", json_schema: { name: "test" } }
          )
        end.to output(/OpenRouter Warning.*structured outputs/).to_stderr
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "shows warnings for unsupported vision but allows request" do
      expect do
        expect do
          client.complete([
                            {
                              role: "user",
                              content: [
                                { type: "text", text: "What's in this image?" },
                                { type: "image_url", image_url: { url: "data:image/png;base64,abc123" } }
                              ]
                            }
                          ], model: "basic/text-model")
        end.to output(/OpenRouter Warning.*vision/).to_stderr
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "detects images with string keys and shows vision warnings" do
      expect do
        expect do
          client.complete([
                            {
                              "role" => "user",
                              "content" => [
                                { "type" => "text", "text" => "What's in this image?" },
                                { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,abc123" } }
                              ]
                            }
                          ], model: "basic/text-model")
        end.to output(/OpenRouter Warning.*vision/).to_stderr
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "doesn't show warnings when model supports the feature" do
      # Only API error, no warning
      expect do
        expect do
          client.complete(
            [{ role: "user", content: "Hello" }],
            model: "advanced/tool-model",
            tools: [{ name: "test_tool", description: "A test tool" }]
          )
        end.not_to output.to_stderr
      end.to raise_error(Faraday::UnauthorizedError)
    end
  end

  describe "strict mode enabled" do
    let(:client) do
      OpenRouter::Client.new(access_token: "test_token") do |config|
        config.strict_mode = true
      end
    end

    it "raises CapabilityError for unsupported tool calling" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "basic/text-model",
          tools: [{ name: "test_tool", description: "A test tool" }]
        )
      end.to raise_error(OpenRouter::CapabilityError, /tool calling.*missing :function_calling/)
    end

    it "raises CapabilityError for unsupported structured outputs" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "basic/text-model",
          response_format: { type: "json_schema", json_schema: { name: "test" } }
        )
      end.to raise_error(OpenRouter::CapabilityError, /structured outputs.*missing :structured_outputs/)
    end

    it "raises CapabilityError for unsupported vision" do
      expect do
        client.complete([
                          {
                            role: "user",
                            content: [
                              { type: "text", text: "What's in this image?" },
                              { type: "image_url", image_url: { url: "data:image/png;base64,abc123" } }
                            ]
                          }
                        ], model: "basic/text-model")
      end.to raise_error(OpenRouter::CapabilityError, /vision.*missing :vision/)
    end

    it "detects images with string keys and raises CapabilityError" do
      expect do
        client.complete([
                          {
                            "role" => "user",
                            "content" => [
                              { "type" => "text", "text" => "What's in this image?" },
                              { "type" => "image_url", "image_url" => { "url" => "data:image/png;base64,abc123" } }
                            ]
                          }
                        ], model: "basic/text-model")
      end.to raise_error(OpenRouter::CapabilityError, /vision.*missing :vision/)
    end

    it "allows requests when model supports the feature" do
      # API error, not capability error
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "advanced/tool-model",
          tools: [{ name: "test_tool", description: "A test tool" }]
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "doesn't raise for array models (fallbacks)" do
      # Should not raise CapabilityError
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: ["basic/text-model", "advanced/tool-model"],
          tools: [{ name: "test_tool", description: "A test tool" }]
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end

    it "doesn't raise for auto model selection" do
      # Should not raise CapabilityError
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "openrouter/auto",
          tools: [{ name: "test_tool", description: "A test tool" }]
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end
  end

  describe "configuration" do
    it "defaults strict_mode to false" do
      config = OpenRouter::Configuration.new
      expect(config.strict_mode).to be false
    end

    it "can be configured via environment variable" do
      ENV["OPENROUTER_STRICT_MODE"] = "true"
      config = OpenRouter::Configuration.new
      expect(config.strict_mode).to be true
      ENV.delete("OPENROUTER_STRICT_MODE")
    end

    it "can be configured programmatically" do
      OpenRouter.configure do |config|
        config.strict_mode = true
      end
      expect(OpenRouter.configuration.strict_mode).to be true

      # Reset for other tests
      OpenRouter.configure { |config| config.strict_mode = false }
    end
  end
end
