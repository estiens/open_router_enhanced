# frozen_string_literal: true

# Integration scenarios that could be added

RSpec.describe "OpenRouter Integration Scenarios" do
  before do
    # Use fixture data
    fixture_data = JSON.parse(File.read(File.join(__dir__, "fixtures", "openrouter_models_sample.json")))
    allow(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).and_return(fixture_data)
    OpenRouter::ModelRegistry.clear_cache!
  end

  describe "Client + ModelSelector integration" do
    let(:client) { OpenRouter::Client.new(access_token: "test_token") }

    it "uses ModelSelector for smart_complete" do
      # Mock the completion response
      allow(client).to receive(:post).and_return({
                                                   "id" => "completion-123",
                                                   "choices" => [{ "message" => { "role" => "assistant",
                                                                                  "content" => "Hello!" } }]
                                                 })

      # This would test a theoretical smart_complete method
      # response = client.smart_complete(
      #   messages: [{ role: "user", content: "Hello" }],
      #   requirements: { capabilities: [:function_calling], max_cost: 0.01 }
      # )

      # expect(response).to be_a(OpenRouter::Response)
    end
  end

  describe "Full workflow scenarios" do
    it "handles model selection -> tool creation -> completion flow" do
      # 1. Select appropriate model for function calling
      selector = OpenRouter::ModelSelector.new
                                          .require(:function_calling)
                                          .optimize_for(:cost)

      model = selector.choose
      expect(model).not_to be_nil

      # 2. Create tool for the task
      search_tool = OpenRouter::Tool.define do
        name "search"
        description "Search for information"
        parameters do
          string :query, required: true
        end
      end

      # 3. Mock completion with tool call
      client = OpenRouter::Client.new(access_token: "test_token")
      tool_response = {
        "choices" => [{
          "message" => {
            "role" => "assistant",
            "tool_calls" => [{
              "id" => "call_123",
              "type" => "function",
              "function" => {
                "name" => "search",
                "arguments" => '{"query": "test"}'
              }
            }]
          }
        }]
      }

      allow(client).to receive(:post).and_return(tool_response)

      response = client.complete(
        [{ role: "user", content: "Search for something" }],
        model:,
        tools: [search_tool]
      )

      expect(response.has_tool_calls?).to be true
    end

    it "handles graceful degradation across the stack" do
      # Scenario: very restrictive requirements that need fallback
      selector = OpenRouter::ModelSelector.new
                                          .require(:function_calling, :vision, :structured_outputs)
                                          .within_budget(max_cost: 0.0000001)  # Impossibly low
                                          .min_context(1_000_000)              # Impossibly high

      # Should still find a model via fallback
      model = selector.choose_with_fallback
      expect(model).not_to be_nil

      # The model should still have core requirements (function calling)
      info = OpenRouter::ModelRegistry.get_model_info(model)
      expect(info[:capabilities]).to include(:function_calling)
    end
  end

  describe "Performance edge cases" do
    it "handles large model registries efficiently" do
      # Test with many models to ensure O(n) operations don't become O(n²)
      start_time = Time.now

      10.times do
        OpenRouter::ModelRegistry.find_best_model(capabilities: [:function_calling])
      end

      elapsed = Time.now - start_time
      expect(elapsed).to be < 0.1 # Should be fast even with repeated calls
    end
  end
end
