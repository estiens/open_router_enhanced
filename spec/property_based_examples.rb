# frozen_string_literal: true

# Example property-based tests to consider adding

describe "ModelRegistry property-based tests" do
  it "cost calculation properties" do
    # Property: cost should be monotonic with token count
    100.times do
      input_tokens = rand(1..10_000)
      output_tokens = rand(1..10_000)

      cost1 = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "ai21/jamba-mini-1.7",
        input_tokens:,
        output_tokens:
      )

      cost2 = OpenRouter::ModelRegistry.calculate_estimated_cost(
        "ai21/jamba-mini-1.7",
        input_tokens: input_tokens * 2,
        output_tokens: output_tokens * 2
      )

      expect(cost2).to be > cost1
    end
  end

  it "model selection consistency" do
    # Property: same requirements should always return same model (when deterministic)
    requirements = { capabilities: [:function_calling], max_input_cost: 0.01 }

    10.times do
      model1 = OpenRouter::ModelRegistry.find_best_model(requirements)
      model2 = OpenRouter::ModelRegistry.find_best_model(requirements)
      expect(model1).to eq(model2)
    end
  end
end

describe "ModelSelector property-based tests" do
  it "chaining order independence for commutative operations" do
    # Property: order of capability requirements shouldn't matter
    caps = %i[function_calling vision structured_outputs].shuffle

    selector1 = OpenRouter::ModelSelector.new.require(*caps)
    selector2 = OpenRouter::ModelSelector.new.require(caps[0]).require(caps[1]).require(caps[2])

    expect(selector1.selection_criteria[:requirements][:capabilities].sort).to eq(
      selector2.selection_criteria[:requirements][:capabilities].sort
    )
  end
end
