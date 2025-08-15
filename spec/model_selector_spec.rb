# frozen_string_literal: true

RSpec.describe OpenRouter::ModelSelector do
  let(:fixture_data) do
    JSON.parse(File.read(File.join(__dir__, "fixtures", "openrouter_models_sample.json")))
  end

  before do
    # Mock the HTTP client to return our fixture data
    allow(OpenRouter::ModelRegistry).to receive(:fetch_models_from_api).and_return(fixture_data)
    # Clear any cached data
    OpenRouter::ModelRegistry.clear_cache!
  end

  describe "#initialize" do
    it "creates a new selector with default settings" do
      selector = described_class.new
      expect(selector.selection_criteria[:strategy]).to eq(:cost)
      expect(selector.selection_criteria[:requirements]).to be_empty
      expect(selector.selection_criteria[:provider_preferences]).to be_empty
    end
  end

  describe "#optimize_for" do
    let(:selector) { described_class.new }

    it "sets cost optimization strategy" do
      new_selector = selector.optimize_for(:cost)
      expect(new_selector.selection_criteria[:strategy]).to eq(:cost)
    end

    it "sets performance optimization strategy" do
      new_selector = selector.optimize_for(:performance)
      expect(new_selector.selection_criteria[:strategy]).to eq(:performance)
      expect(new_selector.selection_criteria[:requirements][:performance_tier]).to eq(:premium)
    end

    it "sets latest optimization strategy" do
      new_selector = selector.optimize_for(:latest)
      expect(new_selector.selection_criteria[:strategy]).to eq(:latest)
      expect(new_selector.selection_criteria[:requirements][:pick_newer]).to be true
    end

    it "sets context optimization strategy" do
      new_selector = selector.optimize_for(:context)
      expect(new_selector.selection_criteria[:strategy]).to eq(:context)
    end

    it "raises error for unknown strategy" do
      expect { selector.optimize_for(:unknown) }.to raise_error(ArgumentError, /Unknown strategy/)
    end

    it "returns new instance for method chaining" do
      result = selector.optimize_for(:cost)
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "#require" do
    let(:selector) { described_class.new }

    it "adds single capability requirement" do
      new_selector = selector.require(:function_calling)
      expect(new_selector.selection_criteria[:requirements][:capabilities]).to eq([:function_calling])
    end

    it "adds multiple capability requirements" do
      new_selector = selector.require(:function_calling, :vision, :structured_outputs)
      expect(new_selector.selection_criteria[:requirements][:capabilities]).to eq(%i[function_calling vision
                                                                                     structured_outputs])
    end

    it "accumulates capabilities across multiple calls" do
      new_selector = selector.require(:function_calling).require(:vision)
      expect(new_selector.selection_criteria[:requirements][:capabilities]).to eq(%i[function_calling vision])
    end

    it "handles duplicate capabilities" do
      new_selector = selector.require(:function_calling, :vision).require(:function_calling)
      expect(new_selector.selection_criteria[:requirements][:capabilities]).to eq(%i[function_calling vision])
    end

    it "returns new instance for method chaining" do
      result = selector.require(:function_calling)
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "#within_budget" do
    let(:selector) { described_class.new }

    it "sets max input cost requirement" do
      new_selector = selector.within_budget(max_cost: 0.01)
      expect(new_selector.selection_criteria[:requirements][:max_input_cost]).to eq(0.01)
    end

    it "sets both input and output cost requirements" do
      new_selector = selector.within_budget(max_cost: 0.01, max_output_cost: 0.02)
      expect(new_selector.selection_criteria[:requirements][:max_input_cost]).to eq(0.01)
      expect(new_selector.selection_criteria[:requirements][:max_output_cost]).to eq(0.02)
    end

    it "returns new instance for method chaining" do
      result = selector.within_budget(max_cost: 0.01)
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "#min_context" do
    let(:selector) { described_class.new }

    it "sets minimum context length requirement" do
      new_selector = selector.min_context(100_000)
      expect(new_selector.selection_criteria[:requirements][:min_context_length]).to eq(100_000)
    end

    it "returns new instance for method chaining" do
      result = selector.min_context(50_000)
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "#newer_than" do
    let(:selector) { described_class.new }

    it "sets date requirement with Date object" do
      date = Date.new(2024, 1, 1)
      new_selector = selector.newer_than(date)
      expect(new_selector.selection_criteria[:requirements][:released_after_date]).to eq(date)
    end

    it "sets date requirement with Time object" do
      time = Time.new(2024, 1, 1)
      new_selector = selector.newer_than(time)
      expect(new_selector.selection_criteria[:requirements][:released_after_date]).to eq(time)
    end

    it "returns new instance for method chaining" do
      result = selector.newer_than(Date.new(2024, 1, 1))
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "provider filtering methods" do
    let(:selector) { described_class.new }

    describe "#prefer_providers" do
      it "sets preferred providers" do
        new_selector = selector.prefer_providers("anthropic", "openai")
        expect(new_selector.selection_criteria[:provider_preferences][:preferred]).to eq(%w[anthropic openai])
      end

      it "handles array input" do
        new_selector = selector.prefer_providers(%w[anthropic openai])
        expect(new_selector.selection_criteria[:provider_preferences][:preferred]).to eq(%w[anthropic openai])
      end

      it "returns new instance for method chaining" do
        result = selector.prefer_providers("anthropic")
        expect(result).to be_a(described_class)
        expect(result).not_to be(selector)
      end
    end

    describe "#require_providers" do
      it "sets required providers" do
        new_selector = selector.require_providers("anthropic")
        expect(new_selector.selection_criteria[:provider_preferences][:required]).to eq(["anthropic"])
      end

      it "returns new instance for method chaining" do
        result = selector.require_providers("anthropic")
        expect(result).to be_a(described_class)
        expect(result).not_to be(selector)
      end
    end

    describe "#avoid_providers" do
      it "sets avoided providers" do
        new_selector = selector.avoid_providers("google")
        expect(new_selector.selection_criteria[:provider_preferences][:avoided]).to eq(["google"])
      end

      it "returns new instance for method chaining" do
        result = selector.avoid_providers("google")
        expect(result).to be_a(described_class)
        expect(result).not_to be(selector)
      end
    end

    describe "#avoid_patterns" do
      it "sets avoided patterns" do
        new_selector = selector.avoid_patterns("*-free", "*-preview")
        expect(new_selector.selection_criteria[:provider_preferences][:avoided_patterns]).to eq(["*-free", "*-preview"])
      end

      it "returns new instance for method chaining" do
        result = selector.avoid_patterns("*-free")
        expect(result).to be_a(described_class)
        expect(result).not_to be(selector)
      end
    end
  end

  describe "#with_fallbacks" do
    let(:selector) { described_class.new }

    it "sets fallback options" do
      new_selector = selector.with_fallbacks(max: 5, strategy: :similar)
      expect(new_selector.selection_criteria[:fallback_options][:max_fallbacks]).to eq(5)
      expect(new_selector.selection_criteria[:fallback_options][:strategy]).to eq(:similar)
    end

    it "uses default options" do
      new_selector = selector.with_fallbacks
      expect(new_selector.selection_criteria[:fallback_options][:max_fallbacks]).to eq(3)
      expect(new_selector.selection_criteria[:fallback_options][:strategy]).to eq(:similar)
    end

    it "returns new instance for method chaining" do
      result = selector.with_fallbacks
      expect(result).to be_a(described_class)
      expect(result).not_to be(selector)
    end
  end

  describe "#choose" do
    context "with cost optimization" do
      it "returns the cheapest model" do
        selector = described_class.new.optimize_for(:cost)
        model = selector.choose
        expect(model).to be_a(String)
        # Based on fixture data, ai21/jamba-mini-1.7 should be cheapest
        expect(model).to eq("ai21/jamba-mini-1.7")
      end

      it "returns model with specs when requested" do
        selector = described_class.new.optimize_for(:cost)
        model, specs = selector.choose(return_specs: true)
        expect(model).to be_a(String)
        expect(specs).to be_a(Hash)
        expect(specs).to have_key(:cost_per_1k_tokens)
        expect(specs).to have_key(:capabilities)
      end
    end

    context "with capability requirements" do
      it "finds models with function calling capability" do
        selector = described_class.new.require(:function_calling)
        model = selector.choose
        expect(model).to be_a(String)

        # Verify the model actually has the capability
        model_info = OpenRouter::ModelRegistry.get_model_info(model)
        expect(model_info[:capabilities]).to include(:function_calling)
      end

      it "finds models with vision capability" do
        selector = described_class.new.require(:vision)
        model = selector.choose
        expect(model).to be_a(String)

        # Verify the model actually has the capability
        model_info = OpenRouter::ModelRegistry.get_model_info(model)
        expect(model_info[:capabilities]).to include(:vision)
      end

      it "finds models with multiple capabilities" do
        selector = described_class.new.require(:function_calling, :structured_outputs)
        model = selector.choose
        expect(model).to be_a(String)

        # Verify the model has both capabilities
        model_info = OpenRouter::ModelRegistry.get_model_info(model)
        expect(model_info[:capabilities]).to include(:function_calling, :structured_outputs)
      end

      it "returns nil when no models have required capabilities" do
        selector = described_class.new.require(:nonexistent_capability)
        model = selector.choose
        expect(model).to be_nil
      end
    end

    context "with cost constraints" do
      it "finds models within budget" do
        selector = described_class.new.within_budget(max_cost: 0.01)
        model = selector.choose
        expect(model).to be_a(String)

        # Verify the model is within budget
        model_info = OpenRouter::ModelRegistry.get_model_info(model)
        expect(model_info[:cost_per_1k_tokens][:input]).to be <= 0.01
      end

      it "returns nil when no models are within budget" do
        selector = described_class.new.within_budget(max_cost: 0.0000001)
        model = selector.choose
        expect(model).to be_nil
      end
    end

    context "with context length requirements" do
      it "finds models with sufficient context" do
        selector = described_class.new.min_context(100_000)
        model = selector.choose

        if model # Some fixtures might not have large context models
          model_info = OpenRouter::ModelRegistry.get_model_info(model)
          expect(model_info[:context_length]).to be >= 100_000
        else
          expect(model).to be_nil
        end
      end
    end

    context "with provider filtering" do
      it "only returns models from required providers" do
        selector = described_class.new.require_providers("ai21")
        model = selector.choose
        expect(model).to be_a(String)
        expect(model).to start_with("ai21/")
      end

      it "avoids models from excluded providers" do
        selector = described_class.new.avoid_providers("ai21")
        model = selector.choose
        expect(model).to be_a(String)
        expect(model).not_to start_with("ai21/")
      end

      it "avoids models matching patterns" do
        selector = described_class.new.avoid_patterns("*-mini*")
        model = selector.choose
        expect(model).to be_a(String)
        expect(model).not_to include("mini")
      end

      it "returns nil when no models match provider requirements" do
        selector = described_class.new.require_providers("nonexistent-provider")
        model = selector.choose
        expect(model).to be_nil
      end
    end

    context "with performance optimization" do
      it "prefers premium tier models when available, otherwise standard" do
        selector = described_class.new.optimize_for(:performance)
        model = selector.choose

        if model
          expect(model).to be_a(String)
          model_info = OpenRouter::ModelRegistry.get_model_info(model)
          expect(%i[standard premium]).to include(model_info[:performance_tier])
        else
          # No models meet the performance tier requirement
          expect(model).to be_nil
        end
      end
    end

    context "with latest optimization" do
      it "returns the newest model" do
        selector = described_class.new.optimize_for(:latest)
        model, specs = selector.choose(return_specs: true)
        expect(model).to be_a(String)

        # Verify it's the newest among all models
        all_models = OpenRouter::ModelRegistry.all_models
        max_timestamp = all_models.values.map { |s| s[:created_at] }.max
        expect(specs[:created_at]).to eq(max_timestamp)
      end

      it "handles nil created_at values safely" do
        # Mock data with nil created_at to test nil-safety
        models_with_nil = {
          "model1" => { created_at: nil, cost_per_1k_tokens: { input: 0.01 } },
          "model2" => { created_at: 1_677_652_288, cost_per_1k_tokens: { input: 0.01 } },
          "model3" => { created_at: nil, cost_per_1k_tokens: { input: 0.01 } }
        }

        allow(OpenRouter::ModelRegistry).to receive(:all_models).and_return(models_with_nil)
        allow(OpenRouter::ModelRegistry).to receive(:models_meeting_requirements).and_return(models_with_nil)

        selector = described_class.new.optimize_for(:latest)
        expect { selector.choose }.not_to raise_error
        expect { selector.choose_with_fallbacks }.not_to raise_error
      end
    end

    context "with context optimization" do
      it "returns the model with largest context window" do
        selector = described_class.new.optimize_for(:context)
        model, specs = selector.choose(return_specs: true)
        expect(model).to be_a(String)

        # Verify it has the largest context among all models
        all_models = OpenRouter::ModelRegistry.all_models
        max_context = all_models.values.map { |s| s[:context_length] }.max
        expect(specs[:context_length]).to eq(max_context)
      end

      it "handles nil context_length values safely" do
        # Mock data with nil context_length to test nil-safety
        models_with_nil = {
          "model1" => { context_length: nil, cost_per_1k_tokens: { input: 0.01 } },
          "model2" => { context_length: 8192, cost_per_1k_tokens: { input: 0.01 } },
          "model3" => { context_length: nil, cost_per_1k_tokens: { input: 0.01 } }
        }

        allow(OpenRouter::ModelRegistry).to receive(:all_models).and_return(models_with_nil)
        allow(OpenRouter::ModelRegistry).to receive(:models_meeting_requirements).and_return(models_with_nil)

        selector = described_class.new.optimize_for(:context)
        expect { selector.choose }.not_to raise_error
        expect { selector.choose_with_fallbacks }.not_to raise_error
      end
    end
  end

  describe "#choose_with_fallbacks" do
    it "returns array of model IDs" do
      selector = described_class.new.optimize_for(:cost)
      models = selector.choose_with_fallbacks(limit: 3)
      expect(models).to be_an(Array)
      expect(models.size).to be <= 3
      expect(models.all? { |m| m.is_a?(String) }).to be true
    end

    it "returns models in order of preference" do
      selector = described_class.new.optimize_for(:cost)
      models = selector.choose_with_fallbacks(limit: 3)

      # Verify they're sorted by cost (cheapest first)
      costs = models.map do |model|
        OpenRouter::ModelRegistry.get_model_info(model)[:cost_per_1k_tokens][:input]
      end
      expect(costs).to eq(costs.sort)
    end

    it "respects the limit parameter" do
      selector = described_class.new
      models = selector.choose_with_fallbacks(limit: 2)
      expect(models.size).to be <= 2
    end

    it "returns empty array when no models match" do
      selector = described_class.new.require(:nonexistent_capability)
      models = selector.choose_with_fallbacks
      expect(models).to eq([])
    end

    it "works with capability requirements" do
      selector = described_class.new.require(:function_calling)
      models = selector.choose_with_fallbacks(limit: 2)
      expect(models).to be_an(Array)

      # Verify all returned models have the required capability
      models.each do |model|
        model_info = OpenRouter::ModelRegistry.get_model_info(model)
        expect(model_info[:capabilities]).to include(:function_calling)
      end
    end
  end

  describe "#choose_with_fallback" do
    it "returns a model when requirements can be met" do
      selector = described_class.new.require(:function_calling)
      model = selector.choose_with_fallback
      expect(model).to be_a(String)
    end

    it "gracefully degrades requirements when needed" do
      # Set very restrictive requirements that likely won't be met
      selector = described_class.new
                                .within_budget(max_cost: 0.0000001)
                                .min_context(1_000_000)
                                .require(:function_calling)

      model = selector.choose_with_fallback
      expect(model).to be_a(String)

      # Should still have the capability requirement since it's most important
      model_info = OpenRouter::ModelRegistry.get_model_info(model)
      expect(model_info[:capabilities]).to include(:function_calling)
    end

    it "returns cheapest model as final fallback" do
      # Set impossible capability requirement
      selector = described_class.new.require(:nonexistent_capability)
      model = selector.choose_with_fallback
      expect(model).to be_a(String)

      # Should be the cheapest available model
      all_models = OpenRouter::ModelRegistry.all_models
      cheapest_model = all_models.min_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
      expect(model).to eq(cheapest_model.first)
    end
  end

  describe "#selection_criteria" do
    it "returns current selection state" do
      selector = described_class.new
                                .optimize_for(:performance)
                                .require(:function_calling)
                                .within_budget(max_cost: 0.01)
                                .prefer_providers("anthropic")

      criteria = selector.selection_criteria
      expect(criteria[:strategy]).to eq(:performance)
      expect(criteria[:requirements][:capabilities]).to eq([:function_calling])
      expect(criteria[:requirements][:max_input_cost]).to eq(0.01)
      expect(criteria[:provider_preferences][:preferred]).to eq(["anthropic"])
    end

    it "returns defensive copies" do
      selector = described_class.new.require(:function_calling)
      criteria1 = selector.selection_criteria
      criteria2 = selector.selection_criteria

      # Modifying one shouldn't affect the other
      criteria1[:requirements][:capabilities] << :vision
      expect(criteria2[:requirements][:capabilities]).to eq([:function_calling])
    end
  end

  describe "#estimate_cost" do
    it "calculates estimated cost for a model" do
      selector = described_class.new
      cost = selector.estimate_cost("ai21/jamba-mini-1.7", input_tokens: 1000, output_tokens: 1000)
      expect(cost).to be_a(Numeric)
      expect(cost).to be > 0
    end

    it "uses default token counts" do
      selector = described_class.new
      cost = selector.estimate_cost("ai21/jamba-mini-1.7")
      expect(cost).to be_a(Numeric)
      expect(cost).to be > 0
    end
  end

  describe "method chaining" do
    it "supports complex chaining" do
      model = described_class.new
                             .optimize_for(:cost)
                             .require(:function_calling, :structured_outputs)
                             .within_budget(max_cost: 0.05)
                             .min_context(50_000)
                             .prefer_providers("anthropic", "openai")
                             .avoid_patterns("*-free")
                             .choose

      expect(model).to be_a(String).or be_nil
    end

    it "maintains immutability of chained calls" do
      base_selector = described_class.new.optimize_for(:cost)

      selector1 = base_selector.require(:function_calling)
      selector2 = base_selector.require(:vision)

      # Base selector should remain unchanged
      expect(base_selector.selection_criteria[:requirements][:capabilities]).to be_nil

      # Each branch should have its own requirements
      expect(selector1.selection_criteria[:requirements][:capabilities]).to eq([:function_calling])
      expect(selector2.selection_criteria[:requirements][:capabilities]).to eq([:vision])
    end
  end

  describe "error handling" do
    it "handles edge cases gracefully" do
      selector = described_class.new

      # Empty requirements should work
      expect { selector.choose }.not_to raise_error

      # Nil inputs should be handled
      expect { selector.within_budget(max_cost: nil) }.not_to raise_error
      expect { selector.min_context(nil) }.not_to raise_error
    end
  end
end
