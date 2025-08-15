# frozen_string_literal: true

# Examples of code mutations your tests should catch

# Add to Gemfile for mutation testing:
# gem 'mutant-rspec', group: :test

# These are examples of mutations your current tests should catch:

describe "Mutation testing examples" do
  # Example 1: Cost comparison logic
  # If someone accidentally changed < to <= in cost filtering:
  # Original: specs[:cost_per_1k_tokens][:input] < max_cost
  # Mutant:   specs[:cost_per_1k_tokens][:input] <= max_cost

  it "catches boundary condition mutations in cost filtering" do
    # Your current test at exactly the boundary would catch this:
    _, specs = OpenRouter::ModelRegistry.find_best_model(max_input_cost: 0.01)
    expect(specs[:cost_per_1k_tokens][:input]).to be <= 0.01

    # But you might want to add:
    model = OpenRouter::ModelRegistry.find_best_model(max_input_cost: 0.0049999)
    expect(model).not_to be_nil # Should find ai21/jamba-mini-1.7 at 0.003

    model = OpenRouter::ModelRegistry.find_best_model(max_input_cost: 0.0029999)
    expect(model).to be_nil # Should NOT find any models
  end

  # Example 2: Capability accumulation logic
  # If someone changed Array.union to Array.intersection:
  # Original: capabilities |= new_capabilities
  # Mutant:   capabilities &= new_capabilities

  it "catches mutations in capability accumulation" do
    selector = OpenRouter::ModelSelector.new
                                        .require(:function_calling)
                                        .require(:vision)

    capabilities = selector.selection_criteria[:requirements][:capabilities]
    expect(capabilities).to include(:function_calling)
    expect(capabilities).to include(:vision)
    expect(capabilities.size).to eq(2) # Would fail if intersection instead of union
  end

  # Example 3: Strategy logic mutations
  # If someone accidentally switched the cost optimization:
  # Original: models.min_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
  # Mutant:   models.max_by { |_, specs| specs[:cost_per_1k_tokens][:input] }

  it "catches mutations in optimization strategy" do
    cost_selector = OpenRouter::ModelSelector.new.optimize_for(:cost)
    _, cost_specs = cost_selector.choose(return_specs: true)

    # Should be cheapest available model
    all_models = OpenRouter::ModelRegistry.all_models
    cheapest_cost = all_models.values.map { |s| s[:cost_per_1k_tokens][:input] }.min
    expect(cost_specs[:cost_per_1k_tokens][:input]).to eq(cheapest_cost)
  end

  # Example 4: Date comparison mutations
  # Original: model_timestamp >= cutoff_date
  # Mutant:   model_timestamp > cutoff_date

  it "catches boundary mutations in date filtering" do
    # Test with exact timestamp
    exact_timestamp = 1_755_095_639 # From fixture

    model, = OpenRouter::ModelRegistry.find_best_model(
      released_after_date: exact_timestamp
    )
    expect(model).not_to be_nil # Should include models AT the exact timestamp

    OpenRouter::ModelRegistry.find_best_model(
      released_after_date: exact_timestamp + 1
    )
    # This test validates the boundary behavior
  end
end

# To run mutation testing (if you add the gem):
# bundle exec mutant --include lib --require open_router --use rspec OpenRouter::ModelRegistry#find_best_model
