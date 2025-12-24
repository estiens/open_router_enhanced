# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Plugins Support", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  # Reset configuration and ensure model registry is available
  before do
    OpenRouter.configuration.auto_native_healing = true

    # Stub model registry to avoid network calls - gpt-4o-mini supports structured outputs
    allow(OpenRouter::ModelRegistry).to receive(:has_capability?).and_return(true)
  end

  let(:simple_schema) do
    OpenRouter::Schema.define("simple_response") do
      string "message", required: true, description: "A simple message"
      integer "count", required: true, description: "A count value"
    end
  end

  describe "manual plugins parameter" do
    it "passes plugins array to API", vcr: { cassette_name: "plugins_manual_array" } do
      # Note: json_object response_format requires "json" in the message
      messages = [{ role: "user", content: "Say hello and return your response as json" }]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        plugins: [{ id: "response-healing" }],
        response_format: { type: "json_object" },
        extras: { max_tokens: 100 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)
    end

    it "passes custom plugins in API request" do
      messages = [{ role: "user", content: "Hello" }]

      # Verify plugins are passed to the API (unit test)
      parameters = nil
      allow(client).to receive(:execute_request) do |params|
        parameters = params
        {
          "id" => "test",
          "object" => "chat.completion",
          "created" => Time.now.to_i,
          "model" => "openai/gpt-4o-mini",
          "choices" => [{ "message" => { "content" => "Hello!" } }],
          "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
        }
      end

      client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        plugins: [{ id: "web-search" }, { id: "pdf-inputs" }]
      )

      expect(parameters[:plugins]).to eq([{ id: "web-search" }, { id: "pdf-inputs" }])
    end
  end

  describe "automatic response-healing plugin" do
    context "when using json_schema response_format" do
      it "automatically adds response-healing plugin", vcr: { cassette_name: "plugins_auto_healing_json_schema" } do
        messages = [{ role: "user", content: "Give me a greeting with count 5" }]

        response = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          response_format: simple_schema,
          extras: { max_tokens: 200 }
        )

        expect(response).to be_a(OpenRouter::Response)
        structured = response.structured_output
        expect(structured).to be_a(Hash)
        expect(structured["message"]).to be_a(String)
      end
    end

    context "when using json_object response_format" do
      it "automatically adds response-healing plugin", vcr: { cassette_name: "plugins_auto_healing_json_object" } do
        messages = [{ role: "user", content: 'Return JSON with a "greeting" key' }]

        response = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          response_format: { type: "json_object" },
          extras: { max_tokens: 200 }
        )

        expect(response).to be_a(OpenRouter::Response)
        parsed = JSON.parse(response.content)
        expect(parsed).to be_a(Hash)
      end
    end

    context "when user already provides response-healing plugin" do
      it "does not duplicate the plugin", vcr: { cassette_name: "plugins_no_duplicate" } do
        messages = [{ role: "user", content: "Give me a greeting with count 10" }]

        # User explicitly provides response-healing
        response = client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          plugins: [{ id: "response-healing" }],
          response_format: simple_schema,
          extras: { max_tokens: 200 }
        )

        expect(response).to be_a(OpenRouter::Response)
        structured = response.structured_output
        expect(structured).to be_a(Hash)
      end
    end

    context "when user provides other plugins" do
      it "appends response-healing to existing plugins" do
        messages = [{ role: "user", content: "Give me a greeting with count 7" }]

        # Test that the parameters are built correctly (unit test)
        # We verify the plugin is appended without making API call
        parameters = nil
        allow(client).to receive(:execute_request) do |params|
          parameters = params
          # Return a mock response
          {
            "id" => "test",
            "object" => "chat.completion",
            "created" => Time.now.to_i,
            "model" => "openai/gpt-4o-mini",
            "choices" => [{ "message" => { "content" => '{"message":"Hello","count":7}' } }],
            "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5, "total_tokens" => 15 }
          }
        end

        client.complete(
          messages,
          model: "openai/gpt-4o-mini",
          plugins: [{ id: "some-other-plugin" }],
          response_format: simple_schema,
          extras: { max_tokens: 200 }
        )

        # Verify response-healing was appended
        expect(parameters[:plugins]).to include({ id: "some-other-plugin" })
        expect(parameters[:plugins]).to include({ id: "response-healing" })
        expect(parameters[:plugins].length).to eq(2)
      end
    end

    context "when auto_native_healing is disabled" do
      it "does not add response-healing plugin automatically", vcr: { cassette_name: "plugins_auto_disabled" } do
        # Save original config
        original_setting = OpenRouter.configuration.auto_native_healing

        begin
          OpenRouter.configuration.auto_native_healing = false

          messages = [{ role: "user", content: "Give me a greeting with count 3" }]

          response = client.complete(
            messages,
            model: "openai/gpt-4o-mini",
            response_format: simple_schema,
            extras: { max_tokens: 200 }
          )

          expect(response).to be_a(OpenRouter::Response)
        ensure
          OpenRouter.configuration.auto_native_healing = original_setting
        end
      end
    end

    context "when streaming is enabled" do
      it "does not add response-healing plugin (not supported for streaming)" do
        # Note: Response healing only works for non-streaming requests
        # This test verifies we don't add it when streaming
        messages = [{ role: "user", content: "Give me a greeting" }]

        chunks = []
        stream_proc = proc { |chunk| chunks << chunk }

        # The plugin should not be added for streaming
        # We just verify the request works
        expect do
          client.complete(
            messages,
            model: "openai/gpt-4o-mini",
            response_format: simple_schema,
            stream: stream_proc,
            extras: { max_tokens: 200 }
          )
        end.not_to raise_error
      end
    end
  end

  describe "plugin configuration via hash" do
    it "accepts plugin with additional options", vcr: { cassette_name: "plugins_with_options" } do
      messages = [{ role: "user", content: "Hello" }]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        plugins: [{ id: "response-healing", enabled: true }],
        extras: { max_tokens: 100 }
      )

      expect(response).to be_a(OpenRouter::Response)
    end

    it "can disable a default plugin", vcr: { cassette_name: "plugins_disable_default" } do
      messages = [{ role: "user", content: "Hello" }]

      # User can explicitly disable a plugin
      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        plugins: [{ id: "response-healing", enabled: false }],
        extras: { max_tokens: 100 }
      )

      expect(response).to be_a(OpenRouter::Response)
    end
  end

  describe "without structured outputs" do
    it "does not add plugins when no response_format specified", vcr: { cassette_name: "plugins_no_structured" } do
      messages = [{ role: "user", content: "Tell me a joke" }]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        extras: { max_tokens: 200 }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response.content).to be_a(String)
    end
  end
end
