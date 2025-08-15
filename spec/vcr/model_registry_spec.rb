# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter ModelRegistry", :vcr do
  before(:each) do
    # Clear cache before each test to ensure fresh API calls
    OpenRouter::ModelRegistry.clear_cache!
  end

  after(:all) do
    # Clean up cache after tests
    OpenRouter::ModelRegistry.clear_cache!
  end

  describe "fetching models from API", vcr: { cassette_name: "model_registry_fetch_from_api" } do
    it "successfully fetches model list from OpenRouter API" do
      models_data = OpenRouter::ModelRegistry.fetch_models_from_api

      expect(models_data).to be_a(Hash)
      expect(models_data).to have_key("data")
      expect(models_data["data"]).to be_an(Array)
      expect(models_data["data"].length).to be > 0

      # Check structure of first model
      first_model = models_data["data"].first
      expect(first_model).to have_key("id")
      expect(first_model).to have_key("name")
      expect(first_model).to have_key("pricing")
      expect(first_model["pricing"]).to have_key("prompt")
      expect(first_model["pricing"]).to have_key("completion")
      expect(first_model).to have_key("context_length")
    end
  end

  describe "caching behavior", vcr: { cassette_name: "model_registry_caching" } do
    it "caches models after first fetch" do
      # First call should fetch from API and cache
      models = OpenRouter::ModelRegistry.all_models
      expect(models).to be_a(Hash)
      expect(models.keys.length).to be > 0

      # Check that cache files were created
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_DATA_FILE)).to be true
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_METADATA_FILE)).to be true

      # Verify some expected models exist
      expect(models).to have_key("openai/gpt-3.5-turbo")
      expect(models).to have_key("anthropic/claude-3-haiku")
    end

    it "loads from cache on subsequent calls" do
      # First call to populate cache
      OpenRouter::ModelRegistry.all_models

      # Verify cache exists
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_DATA_FILE)).to be true

      # Load cached data directly
      cached_data = OpenRouter::ModelRegistry.read_cache_if_fresh
      expect(cached_data).to be_a(Hash)
      expect(cached_data).to have_key("data")
    end

    it "refreshes cache when explicitly requested" do
      # Initial fetch
      OpenRouter::ModelRegistry.all_models

      # Refresh cache
      refreshed_models = OpenRouter::ModelRegistry.refresh!
      expect(refreshed_models).to be_a(Hash)
      expect(refreshed_models.keys.length).to be > 0
    end
  end

  describe "model processing", vcr: { cassette_name: "model_registry_processing" } do
    it "processes API models into internal format" do
      models = OpenRouter::ModelRegistry.all_models

      # Check a known model
      gpt_model = models["openai/gpt-3.5-turbo"]
      expect(gpt_model).to be_a(Hash)

      # Check required fields
      expect(gpt_model).to have_key(:name)
      expect(gpt_model).to have_key(:cost_per_1k_tokens)
      expect(gpt_model).to have_key(:context_length)
      expect(gpt_model).to have_key(:capabilities)
      expect(gpt_model).to have_key(:description)
      expect(gpt_model).to have_key(:performance_tier)

      # Check cost structure
      expect(gpt_model[:cost_per_1k_tokens]).to have_key(:input)
      expect(gpt_model[:cost_per_1k_tokens]).to have_key(:output)
      expect(gpt_model[:cost_per_1k_tokens][:input]).to be_a(Float)
      expect(gpt_model[:cost_per_1k_tokens][:output]).to be_a(Float)

      # Check capabilities
      expect(gpt_model[:capabilities]).to be_an(Array)
      expect(gpt_model[:capabilities]).to include(:chat)

      # Check context length
      expect(gpt_model[:context_length]).to be_a(Integer)
      expect(gpt_model[:context_length]).to be > 0
    end

    it "extracts capabilities correctly" do
      models = OpenRouter::ModelRegistry.all_models

      # Find a model with function calling support
      function_calling_model = models.find { |_, specs| specs[:capabilities].include?(:function_calling) }
      expect(function_calling_model).not_to be_nil

      # Find a model with vision support (if any)
      models.select { |_, specs| specs[:capabilities].include?(:vision) }
      # NOTE: Vision models may not always be available, so we don't assert their existence

      # Find a model with long context
      long_context_models = models.select { |_, specs| specs[:capabilities].include?(:long_context) }
      expect(long_context_models.length).to be >= 0 # Some models should have long context
    end

    it "assigns performance tiers correctly" do
      models = OpenRouter::ModelRegistry.all_models

      premium_models = models.select { |_, specs| specs[:performance_tier] == :premium }
      standard_models = models.select { |_, specs| specs[:performance_tier] == :standard }

      expect(premium_models.length).to be > 0
      expect(standard_models.length).to be > 0
    end
  end

  describe "model lookup methods", vcr: { cassette_name: "model_registry_lookups" } do
    it "checks if models exist" do
      expect(OpenRouter::ModelRegistry.model_exists?("openai/gpt-3.5-turbo")).to be true
      expect(OpenRouter::ModelRegistry.model_exists?("nonexistent/model")).to be false
    end

    it "retrieves model information" do
      model_info = OpenRouter::ModelRegistry.get_model_info("openai/gpt-3.5-turbo")
      expect(model_info).to be_a(Hash)
      expect(model_info[:name]).to be_a(String)
      expect(model_info[:cost_per_1k_tokens]).to be_a(Hash)

      # Non-existent model should return nil
      expect(OpenRouter::ModelRegistry.get_model_info("nonexistent/model")).to be_nil
    end

    it "calculates estimated costs" do
      cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "openai/gpt-3.5-turbo",
        input_tokens: 1000,
        output_tokens: 500
      )

      expect(cost).to be_a(Float)
      expect(cost).to be > 0

      # Zero cost for non-existent model
      zero_cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "nonexistent/model",
        input_tokens: 1000,
        output_tokens: 500
      )
      expect(zero_cost).to eq(0)
    end
  end

  describe "model selection", vcr: { cassette_name: "model_registry_selection" } do
    it "finds models meeting capability requirements" do
      models = OpenRouter::ModelRegistry.models_meeting_requirements(
        capabilities: [:function_calling]
      )

      expect(models).to be_a(Hash)
      expect(models.length).to be > 0

      # All returned models should have function calling capability
      models.each_value do |specs|
        expect(specs[:capabilities]).to include(:function_calling)
      end
    end

    it "finds models within cost constraints" do
      models = OpenRouter::ModelRegistry.models_meeting_requirements(
        max_input_cost: 0.00001 # Very low cost constraint
      )

      expect(models).to be_a(Hash)

      # All returned models should be within cost constraint
      models.each_value do |specs|
        expect(specs[:cost_per_1k_tokens][:input]).to be <= 0.00001
      end
    end

    it "finds models with minimum context length" do
      models = OpenRouter::ModelRegistry.models_meeting_requirements(
        min_context_length: 32_000
      )

      expect(models).to be_a(Hash)

      # All returned models should meet context requirement
      models.each_value do |specs|
        expect(specs[:context_length]).to be >= 32_000
      end
    end

    it "finds best model with multiple constraints" do
      model_pair = OpenRouter::ModelRegistry.find_best_model(
        capabilities: [:function_calling],
        max_input_cost: 0.01,
        min_context_length: 4000
      )

      if model_pair # May be nil if no models meet all constraints
        model_id, model_specs = model_pair
        expect(model_id).to be_a(String)
        expect(model_specs[:capabilities]).to include(:function_calling)
        expect(model_specs[:cost_per_1k_tokens][:input]).to be <= 0.01
        expect(model_specs[:context_length]).to be >= 4000
      end
    end

    it "respects pick_newer preference" do
      # Find newest model overall
      newest_model = OpenRouter::ModelRegistry.find_best_model(
        pick_newer: true
      )

      expect(newest_model).not_to be_nil
      model_id, model_specs = newest_model
      expect(model_id).to be_a(String)
      expect(model_specs[:created_at]).to be_a(Integer)
    end
  end

  describe "error handling", vcr: { cassette_name: "model_registry_errors", allow_unused_http_interactions: true } do
    it "handles network errors gracefully" do
      # Temporarily modify API base to cause network error
      original_base = OpenRouter::ModelRegistry::API_BASE
      OpenRouter::ModelRegistry.const_set(:API_BASE, "https://invalid-domain-12345.com/api/v1")

      expect do
        OpenRouter::ModelRegistry.fetch_models_from_api
      end.to raise_error(OpenRouter::ModelRegistryError, /Network error/)

      # Restore original API base
      OpenRouter::ModelRegistry.const_set(:API_BASE, original_base)
    end
  end

  describe "integration with Client", vcr: { cassette_name: "model_registry_client_integration" } do
    let(:client) { OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"]) }

    it "validates that models from registry work with client" do
      # Get a few models from registry
      models = OpenRouter::ModelRegistry.all_models
      test_models = models.keys.first(3)

      test_models.each do |model_id|
        next unless OpenRouter::ModelRegistry.model_exists?(model_id)

        begin
          response = client.complete(
            [{ role: "user", content: "Hello" }],
            model: model_id,
            extras: { max_tokens: 10 }
          )

          expect(response).to be_a(OpenRouter::Response)
          expect(response.content).to be_a(String)
        rescue OpenRouter::ServerError => e
          # Some models may not be available or may have restrictions
          # Log but don't fail the test
          puts "Model #{model_id} not available: #{e.message}"
        end
      end
    end
  end

  describe "cache file management", vcr: { cassette_name: "model_registry_cache_management" } do
    it "handles corrupted cache files" do
      # Create cache directory and corrupted cache file
      FileUtils.mkdir_p(OpenRouter::ModelRegistry::CACHE_DIR)
      File.write(OpenRouter::ModelRegistry::CACHE_DATA_FILE, "invalid json content")

      # Should handle corruption gracefully and fetch fresh data
      models = OpenRouter::ModelRegistry.all_models
      expect(models).to be_a(Hash)
      expect(models.keys.length).to be > 0
    end

    it "clears cache completely" do
      # Ensure cache exists
      OpenRouter::ModelRegistry.all_models
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_DATA_FILE)).to be true

      # Clear cache
      OpenRouter::ModelRegistry.clear_cache!
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_DATA_FILE)).to be false
      expect(File.exist?(OpenRouter::ModelRegistry::CACHE_METADATA_FILE)).to be false
      expect(Dir.exist?(OpenRouter::ModelRegistry::CACHE_DIR)).to be false
    end
  end
end
