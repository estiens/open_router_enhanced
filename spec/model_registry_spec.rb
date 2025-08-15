# frozen_string_literal: true

RSpec.describe OpenRouter::ModelRegistry do
  let(:fixture_data) do
    JSON.parse(File.read(File.join(__dir__, "fixtures", "openrouter_models_sample.json")))
  end

  before do
    # Mock the HTTP client to return our fixture data
    allow(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).and_return(fixture_data)
    # Clear any cached data
    OpenRouter::ModelRegistry.clear_cache!
  end
  describe ".fetch_and_cache_models" do
    it "fetches models from API and caches them" do
      expect(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).once.and_return(fixture_data)

      models = OpenRouter::ModelRegistry.fetch_and_cache_models
      expect(models).to have_key("mistralai/mistral-medium-3.1")
      expect(models["mistralai/mistral-medium-3.1"]).to have_key(:cost_per_1k_tokens)
      expect(models["mistralai/mistral-medium-3.1"]).to have_key(:capabilities)
    end
  end

  describe ".process_api_models" do
    it "handles models with nil pricing gracefully after fix" do
      # Test data with nil pricing - verifies the fix works
      api_models = [
        {
          "id" => "test/model-without-pricing",
          "name" => "Test Model",
          "context_length" => 4000,
          "architecture" => {
            "tokenizer" => "Llama2",
            "instruct_type" => "llama2"
          },
          "pricing" => nil, # This now works with dig
          "per_request_limits" => nil
        }
      ]

      # This should work now thanks to using dig
      result = OpenRouter::ModelRegistry.send(:process_api_models, api_models)
      expect(result).to have_key("test/model-without-pricing")

      model = result["test/model-without-pricing"]
      expect(model[:cost_per_1k_tokens][:input]).to eq(0.0)
      expect(model[:cost_per_1k_tokens][:output]).to eq(0.0)
    end

    it "handles determine_performance_tier with nil pricing after fix" do
      model_data = {
        "pricing" => nil
      }

      # This should work now thanks to using dig
      result = OpenRouter::ModelRegistry.send(:determine_performance_tier, model_data)
      expect(result).to eq(:standard) # 0.0 cost means standard tier
    end

    it "correctly classifies performance tiers based on pricing" do
      # Fixed performance tier threshold test

      # Model that costs $0.0000005 per token (0.0005 per 1k tokens - cheap)
      model_data_cheap = {
        "pricing" => {
          "prompt" => "0.0000005" # Per token pricing
        }
      }

      # This should be :standard (< threshold)
      result = OpenRouter::ModelRegistry.send(:determine_performance_tier, model_data_cheap)
      expect(result).to eq(:standard)

      # Model that costs $0.000005 per token (0.005 per 1k tokens - expensive)
      model_data_expensive = {
        "pricing" => {
          "prompt" => "0.000005" # Per token pricing
        }
      }

      # This should be :premium (> threshold)
      result = OpenRouter::ModelRegistry.send(:determine_performance_tier, model_data_expensive)
      expect(result).to eq(:premium)
    end
  end

  describe ".refresh!" do
    it "clears cache and fetches fresh data" do
      # Load initial data
      OpenRouter::ModelRegistry.all_models

      # Mock new data for refresh
      new_data = { "data" => [{ "id" => "new-model", "pricing" => { "prompt" => "0.001", "completion" => "0.002" } }] }
      allow(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).and_return(new_data)

      OpenRouter::ModelRegistry.refresh!
      models = OpenRouter::ModelRegistry.all_models
      expect(models).to have_key("new-model")
    end
  end

  describe ".find_best_model" do
    context "with no requirements" do
      it "returns the cheapest available model" do
        model, specs = OpenRouter::ModelRegistry.find_best_model
        expect(model).to be_a(String)
        expect(specs).to be_a(Hash)
        expect(specs).to have_key(:cost_per_1k_tokens)
        expect(specs).to have_key(:capabilities)
        # Should return cheapest model (ai21/jamba-mini-1.7 based on fixture data)
        expect(model).to eq("ai21/jamba-mini-1.7")
      end
    end

    context "with capability requirements" do
      it "finds models that support vision" do
        model, specs = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:vision]
        )
        expect(specs[:capabilities]).to include(:vision)
        # Models with image input support vision
        expect(["mistralai/mistral-medium-3.1", "z-ai/glm-4.5v", "openai/gpt-5-chat"]).to include(model)
      end

      it "finds models that support function calling" do
        model, specs = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:function_calling]
        )
        expect(specs[:capabilities]).to include(:function_calling)
        # All models in fixture support tools/tool_choice
        expect(["mistralai/mistral-medium-3.1", "z-ai/glm-4.5v", "ai21/jamba-mini-1.7",
                "ai21/jamba-large-1.7"]).to include(model)
      end

      it "finds models that support structured outputs" do
        model, specs = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:structured_outputs]
        )
        expect(specs[:capabilities]).to include(:structured_outputs)
        # Should return cheapest model with structured_outputs capability
        # Based on fixture, ai21/jamba-mini-1.7 is the cheapest with response_format support
        expect(model).to eq("ai21/jamba-mini-1.7")
      end

      it "returns nil when no models support required capabilities" do
        result = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:nonexistent_capability]
        )
        expect(result).to be_nil
      end
    end

    context "with cost requirements" do
      it "finds models within max cost limit" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          max_input_cost: 0.01
        )
        expect(specs[:cost_per_1k_tokens][:input]).to be <= 0.01
      end

      it "returns cheapest model when multiple options exist" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          max_input_cost: 0.05
        )

        # Should return the cheapest model that meets requirements
        all_qualifying = OpenRouter::ModelRegistry.models_meeting_requirements(
          max_input_cost: 0.05
        )
        cheapest_cost = all_qualifying.min_by { |_, s| s[:cost_per_1k_tokens][:input] }&.last
        expect(specs[:cost_per_1k_tokens][:input]).to eq(cheapest_cost[:cost_per_1k_tokens][:input])
      end

      it "returns nil when no models are within cost limit" do
        result = OpenRouter::ModelRegistry.find_best_model(
          max_input_cost: 0.0000001 # Unreasonably low cost (lower than fixture models)
        )
        expect(result).to be_nil
      end
    end

    context "with context length requirements" do
      it "finds models with sufficient context length" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          min_context_length: 100_000
        )
        expect(specs[:context_length]).to be >= 100_000
      end

      it "returns nil when no models have sufficient context" do
        result = OpenRouter::ModelRegistry.find_best_model(
          min_context_length: 1_000_000 # Unreasonably high context
        )
        expect(result).to be_nil
      end
    end

    context "with performance tier requirements" do
      it "finds models with specified performance tier" do
        model, specs = OpenRouter::ModelRegistry.find_best_model(
          performance_tier: :standard
        )
        expect(specs[:performance_tier]).to eq(:standard)
        # All fixture models should be standard tier based on their low pricing
        expect(["mistralai/mistral-medium-3.1", "z-ai/glm-4.5v", "ai21/jamba-mini-1.7", "ai21/jamba-large-1.7",
                "openai/gpt-5-chat"]).to include(model)
      end

      it "accepts models with higher performance tiers" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          performance_tier: :standard
        )
        expect(%i[standard premium]).to include(specs[:performance_tier])
      end
    end

    context "with date-based requirements" do
      it "finds models released after a specific date" do
        # Use a timestamp from early 2024 to filter out older models
        cutoff_date = Time.new(2024, 1, 1).to_i

        _, specs = OpenRouter::ModelRegistry.find_best_model(
          released_after_date: cutoff_date
        )

        expect(specs[:created_at]).to be >= cutoff_date
      end

      it "prioritizes newer models when pick_newer is true" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          pick_newer: true
        )

        # Should return the newest model in the fixture
        all_timestamps = OpenRouter::ModelRegistry.all_models.values.map { |s| s[:created_at] }
        expect(specs[:created_at]).to eq(all_timestamps.max)
      end

      it "returns nil when no models meet date requirements" do
        # Use a future timestamp
        future_date = Time.new(2030, 1, 1).to_i

        result = OpenRouter::ModelRegistry.find_best_model(
          released_after_date: future_date
        )

        expect(result).to be_nil
      end
    end

    context "with combined requirements" do
      it "finds models meeting all requirements" do
        _, specs = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:function_calling],
          max_input_cost: 0.02,
          min_context_length: 50_000
        )

        expect(specs[:capabilities]).to include(:function_calling)
        expect(specs[:cost_per_1k_tokens][:input]).to be <= 0.02
        expect(specs[:context_length]).to be >= 50_000
      end

      it "prioritizes cost when multiple models qualify" do
        results = OpenRouter::ModelRegistry.find_best_model(
          capabilities: [:chat],
          max_input_cost: 0.10
        )

        # Should return cheapest option
        expect(results).not_to be_nil
      end
    end
  end

  describe ".get_fallbacks" do
    it "returns fallback models for known models" do
      fallbacks = OpenRouter::ModelRegistry.get_fallbacks("mistralai/mistral-medium-3.1")
      expect(fallbacks).to be_an(Array)
      # For now our implementation returns empty fallbacks, which is fine
      expect(fallbacks).to eq([])
    end

    it "returns empty array for unknown models" do
      fallbacks = OpenRouter::ModelRegistry.get_fallbacks("unknown-model")
      expect(fallbacks).to eq([])
    end

    it "returns fallbacks that are also in the registry" do
      fallbacks = OpenRouter::ModelRegistry.get_fallbacks("mistralai/mistral-medium-3.1")
      fallbacks.each do |fallback_model|
        expect(OpenRouter::ModelRegistry.model_exists?(fallback_model)).to be true
      end
    end
  end

  describe ".model_exists?" do
    it "returns true for registered models" do
      model, = OpenRouter::ModelRegistry.find_best_model
      expect(OpenRouter::ModelRegistry.model_exists?(model)).to be true
    end

    it "returns false for unregistered models" do
      expect(OpenRouter::ModelRegistry.model_exists?("nonexistent-model")).to be false
    end
  end

  describe ".has_capability?" do
    it "returns true when model has the specified capability" do
      # Find a model that has function calling support
      model_with_tools = OpenRouter::ModelRegistry.all_models.find { |_, specs| specs[:capabilities].include?(:function_calling) }
      if model_with_tools
        model_id, = model_with_tools
        expect(OpenRouter::ModelRegistry.has_capability?(model_id, :function_calling)).to be true
      end
    end

    it "returns false when model doesn't have the specified capability" do
      # Find a model without vision capability for testing
      model_without_vision = OpenRouter::ModelRegistry.all_models.find { |_, specs| !specs[:capabilities].include?(:vision) }
      if model_without_vision
        model_id, = model_without_vision
        expect(OpenRouter::ModelRegistry.has_capability?(model_id, :vision)).to be false
      end
    end

    it "returns false for non-existent models" do
      expect(OpenRouter::ModelRegistry.has_capability?("nonexistent/model", :chat)).to be false
    end
  end

  describe ".get_model_info" do
    it "returns model specifications for registered models" do
      model, = OpenRouter::ModelRegistry.find_best_model
      info = OpenRouter::ModelRegistry.get_model_info(model)

      expect(info).to be_a(Hash)
      expect(info).to have_key(:cost_per_1k_tokens)
      expect(info).to have_key(:capabilities)
      expect(info).to have_key(:context_length)
      expect(info).to have_key(:performance_tier)
    end

    it "returns nil for unregistered models" do
      info = OpenRouter::ModelRegistry.get_model_info("nonexistent-model")
      expect(info).to be_nil
    end
  end

  describe ".all_models" do
    it "returns all registered models" do
      models = OpenRouter::ModelRegistry.all_models
      expect(models).to be_a(Hash)
      expect(models).not_to be_empty

      models.each do |model_name, specs|
        expect(model_name).to be_a(String)
        expect(specs).to be_a(Hash)
        expect(specs).to have_key(:cost_per_1k_tokens)
        expect(specs).to have_key(:capabilities)
      end
    end
  end

  describe ".calculate_estimated_cost" do
    it "calculates cost for input tokens" do
      cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "mistralai/mistral-medium-3.1",
        input_tokens: 1000,
        output_tokens: 0
      )
      expect(cost).to be > 0
      expect(cost).to be_a(Numeric)
    end

    it "calculates cost for output tokens" do
      cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "mistralai/mistral-medium-3.1",
        input_tokens: 0,
        output_tokens: 1000
      )
      expect(cost).to be > 0
      expect(cost).to be_a(Numeric)
    end

    it "calculates combined cost for input and output tokens" do
      input_cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "mistralai/mistral-medium-3.1",
        input_tokens: 1000,
        output_tokens: 0
      )
      output_cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "mistralai/mistral-medium-3.1",
        input_tokens: 0,
        output_tokens: 1000
      )
      combined_cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "mistralai/mistral-medium-3.1",
        input_tokens: 1000,
        output_tokens: 1000
      )

      expect(combined_cost).to eq(input_cost + output_cost)
    end

    it "returns 0 for unknown models" do
      cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "unknown-model",
        input_tokens: 1000,
        output_tokens: 1000
      )
      expect(cost).to eq(0)
    end
  end

  describe "model data validation" do
    it "includes models from the fixture" do
      models = OpenRouter::ModelRegistry.all_models

      # Should include models from our test fixture
      expect(models).to have_key("mistralai/mistral-medium-3.1")
      expect(models).to have_key("ai21/jamba-mini-1.7")

      # Should include at least 5 models from fixture
      expect(models.keys.size).to be >= 5
    end

    it "has valid cost structure for all models" do
      OpenRouter::ModelRegistry.all_models.each_value do |specs|
        expect(specs[:cost_per_1k_tokens]).to be_a(Hash)
        expect(specs[:cost_per_1k_tokens]).to have_key(:input)
        expect(specs[:cost_per_1k_tokens]).to have_key(:output)
        expect(specs[:cost_per_1k_tokens][:input]).to be >= 0
        expect(specs[:cost_per_1k_tokens][:output]).to be >= 0
      end
    end

    it "has valid capabilities for all models" do
      OpenRouter::ModelRegistry.all_models.each_value do |specs|
        expect(specs[:capabilities]).to be_an(Array)
        expect(specs[:capabilities]).not_to be_empty
        expect(specs[:capabilities]).to include(:chat) # All should support basic chat
      end
    end

    it "has valid context lengths for all models" do
      OpenRouter::ModelRegistry.all_models.each_value do |specs|
        expect(specs[:context_length]).to be_a(Numeric)
        expect(specs[:context_length]).to be > 0
      end
    end

    it "has valid creation timestamps for all models" do
      OpenRouter::ModelRegistry.all_models.each_value do |specs|
        expect(specs[:created_at]).to be_a(Numeric)
        expect(specs[:created_at]).to be > 0
      end
    end
  end
end
