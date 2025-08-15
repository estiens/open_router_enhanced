# frozen_string_literal: true

# Contract tests for external API assumptions

RSpec.describe "OpenRouter API Contract Tests" do
  describe "API response structure contracts" do
    let(:sample_model) do
      JSON.parse(File.read(File.join(__dir__, "fixtures", "openrouter_models_sample.json")))["data"][0]
    end

    it "validates expected model structure from OpenRouter API" do
      # These tests document our assumptions about the API structure
      expect(sample_model).to have_key("id")
      expect(sample_model).to have_key("name")
      expect(sample_model).to have_key("context_length")
      expect(sample_model).to have_key("pricing")
      expect(sample_model).to have_key("supported_parameters")

      # Pricing structure
      pricing = sample_model["pricing"]
      expect(pricing).to have_key("prompt")
      expect(pricing).to have_key("completion")
      expect(pricing["prompt"]).to be_a(String) # API returns as string
      expect(pricing["completion"]).to be_a(String)

      # Context length
      expect(sample_model["context_length"]).to be_a(Numeric)
      expect(sample_model["context_length"]).to be > 0

      # Supported parameters (our capability detection depends on this)
      supported = sample_model["supported_parameters"]
      expect(supported).to be_an(Array)

      # These are the parameters we use for capability detection

      # At least some models should support these
      has_tools = supported.include?("tools") && supported.include?("tool_choice")
      has_response_format = supported.include?("response_format")

      # Document what we expect to find
      puts "✅ Model #{sample_model["id"]} supports function calling" if has_tools

      puts "✅ Model #{sample_model["id"]} supports structured outputs" if has_response_format
    end

    it "validates architecture structure for vision capability detection" do
      architecture = sample_model["architecture"]

      if architecture
        expect(architecture).to have_key("input_modalities")

        input_modalities = architecture["input_modalities"]
        puts "✅ Model #{sample_model["id"]} supports vision (image input)" if input_modalities&.include?("image")
      end
    end

    it "ensures pricing values can be converted to floats" do
      pricing = sample_model["pricing"]

      # Our cost calculations depend on these being convertible to Float
      expect { Float(pricing["prompt"]) }.not_to raise_error
      expect { Float(pricing["completion"]) }.not_to raise_error

      prompt_cost = Float(pricing["prompt"])
      completion_cost = Float(pricing["completion"])

      expect(prompt_cost).to be >= 0
      expect(completion_cost).to be >= 0
    end

    it "validates created timestamp format" do
      created = sample_model["created"]
      expect(created).to be_a(Numeric)
      expect(created).to be > 0

      # Should be a reasonable Unix timestamp (after year 2000)
      expect(created).to be > 946_684_800 # Jan 1, 2000

      # Should be before far future (year 2100)
      expect(created).to be < 4_102_444_800 # Jan 1, 2100
    end
  end

  describe "ModelRegistry assumptions validation" do
    before do
      fixture_data = JSON.parse(File.read(File.join(__dir__, "fixtures", "openrouter_models_sample.json")))
      allow(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).and_return(fixture_data)
      OpenRouter::ModelRegistry.clear_cache!
    end

    it "validates our capability detection logic" do
      models = OpenRouter::ModelRegistry.all_models

      models.each do |model_id, specs|
        capabilities = specs[:capabilities]

        # Every model should have basic chat capability
        expect(capabilities).to include(:chat)

        # If we detected function_calling, verify the logic
        if capabilities.include?(:function_calling)
          # This model should support tools in its original data
          original_model = OpenRouter::ModelRegistry.find_original_model_data(model_id)
          supported = original_model&.dig("supported_parameters") || []
          expect(supported).to include("tools").or include("tool_choice")
        end

        # If we detected vision, verify the logic
        next unless capabilities.include?(:vision)

        original_model = OpenRouter::ModelRegistry.find_original_model_data(model_id)
        input_modalities = original_model&.dig("architecture", "input_modalities") || []
        expect(input_modalities).to include("image")
      end
    end

    it "validates performance tier logic is consistent" do
      models = OpenRouter::ModelRegistry.all_models

      premium_models = models.select { |_, specs| specs[:performance_tier] == :premium }
      standard_models = models.select { |_, specs| specs[:performance_tier] == :standard }

      # Premium models should generally be more expensive than standard
      if premium_models.any? && standard_models.any?
        avg_premium_cost = premium_models.values.map { |s| s[:cost_per_1k_tokens][:input] }.sum / premium_models.size
        avg_standard_cost = standard_models.values.map { |s| s[:cost_per_1k_tokens][:input] }.sum / standard_models.size

        # This is a business logic assumption we should validate
        puts "Average premium model cost: $#{avg_premium_cost}"
        puts "Average standard model cost: $#{avg_standard_cost}"

        # Premium should generally cost more (allow some overlap)
        expect(avg_premium_cost).to be >= avg_standard_cost * 0.5
      end
    end
  end
end
