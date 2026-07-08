#!/usr/bin/env ruby
# frozen_string_literal: true

# Dynamic Model Switching & Lookup Example
# =========================================
# This example demonstrates how to dynamically select and switch between models
# based on requirements, capabilities, cost, and performance considerations.
#
# Run with: ruby -I lib examples/dynamic_model_switching_example.rb

require "open_router"
require "json"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV.fetch("OPENROUTER_API_KEY") do
    abort "Please set OPENROUTER_API_KEY environment variable"
  end
  config.site_name = "Model Switching Examples"
end

client = OpenRouter::Client.new

puts "=" * 60
puts "DYNAMIC MODEL SWITCHING & LOOKUP"
puts "=" * 60

# -----------------------------------------------------------------------------
# Example 1: Browse Available Models
# -----------------------------------------------------------------------------
puts "\n1. BROWSING AVAILABLE MODELS"
puts "-" * 40

# Get all models from the registry
all_models = OpenRouter::ModelRegistry.all_models
puts "Total models available: #{all_models.count}"

# Show a few random models
puts "\nSample of available models:"
all_models.keys.sample(5).each do |model_id|
  info = all_models[model_id]
  puts "  - #{model_id}"
  puts "    Cost: $#{info[:cost_per_1k_tokens][:input]}/1k input, $#{info[:cost_per_1k_tokens][:output]}/1k output"
  puts "    Context: #{info[:context_length]} tokens"
  puts "    Capabilities: #{info[:capabilities].join(", ")}"
end

# -----------------------------------------------------------------------------
# Example 2: Check Model Capabilities
# -----------------------------------------------------------------------------
puts "\n\n2. CHECKING MODEL CAPABILITIES"
puts "-" * 40

models_to_check = %w[
  openai/gpt-4o-mini
  anthropic/claude-3-5-sonnet
  google/gemini-2.0-flash-001
]

models_to_check.each do |model_id|
  if OpenRouter::ModelRegistry.model_exists?(model_id)
    info = OpenRouter::ModelRegistry.get_model_info(model_id)
    puts "\n#{model_id}:"
    puts "  Function calling: #{info[:capabilities].include?(:function_calling)}"
    puts "  Structured outputs: #{info[:capabilities].include?(:structured_outputs)}"
    puts "  Vision: #{info[:capabilities].include?(:vision)}"
    puts "  Long context: #{info[:capabilities].include?(:long_context)}"
  else
    puts "\n#{model_id}: Not found in registry"
  end
end

# -----------------------------------------------------------------------------
# Example 3: Find Cheapest Model with Capabilities
# -----------------------------------------------------------------------------
puts "\n\n3. FIND CHEAPEST MODEL FOR TASK"
puts "-" * 40

# Task: Need function calling, optimize for cost
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

puts "Cheapest model with function calling: #{model}"

if model
  info = OpenRouter::ModelRegistry.get_model_info(model)
  puts "  Cost: $#{info[:cost_per_1k_tokens][:input]}/1k input"
end

# Task: Need vision + function calling
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling, :vision)
                                 .optimize_for(:cost)
                                 .choose

puts "\nCheapest model with vision + function calling: #{model || "None found"}"

# -----------------------------------------------------------------------------
# Example 4: Budget-Constrained Selection
# -----------------------------------------------------------------------------
puts "\n\n4. BUDGET-CONSTRAINED MODEL SELECTION"
puts "-" * 40

# Find models under specific price point
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .within_budget(max_cost: 0.0005) # Under $0.50 per million tokens
                                 .optimize_for(:performance)
                                 .choose

puts "Best performing model under $0.50/M tokens: #{model || "None found"}"

# Get cost estimate for a typical request
if model
  estimated_cost = OpenRouter::ModelSelector.new.estimate_cost(
    model,
    input_tokens: 1000,
    output_tokens: 500
  )
  puts "  Estimated cost for 1k in / 500 out: $#{"%.6f" % estimated_cost}"
end

# -----------------------------------------------------------------------------
# Example 5: Provider-Based Selection
# -----------------------------------------------------------------------------
puts "\n\n5. PROVIDER-BASED SELECTION"
puts "-" * 40

# Prefer Anthropic models
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .prefer_providers("anthropic")
                                 .optimize_for(:cost)
                                 .choose

puts "Preferred Anthropic model: #{model || "None found"}"

# Require only OpenAI models
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .require_providers("openai")
                                 .optimize_for(:cost)
                                 .choose

puts "Required OpenAI model: #{model || "None found"}"

# Avoid certain providers
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .avoid_providers("google", "meta-llama")
                                 .avoid_patterns("*-free", "*-preview")
                                 .optimize_for(:cost)
                                 .choose

puts "Model avoiding Google/Meta and free/preview: #{model || "None found"}"

# -----------------------------------------------------------------------------
# Example 6: Get Fallback Options
# -----------------------------------------------------------------------------
puts "\n\n6. FALLBACK MODEL SELECTION"
puts "-" * 40

# Get top 3 models for fallback strategy
models = OpenRouter::ModelSelector.new
                                  .require(:function_calling)
                                  .optimize_for(:cost)
                                  .choose_with_fallbacks(limit: 3)

puts "Top 3 fallback models (by cost):"
models.each_with_index do |model_id, i|
  info = OpenRouter::ModelRegistry.get_model_info(model_id)
  puts "  #{i + 1}. #{model_id} ($#{info[:cost_per_1k_tokens][:input]}/1k)"
end

# Graceful degradation - will drop requirements if needed
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling, :vision, :long_context)
                                 .within_budget(max_cost: 0.0001) # Very tight budget
                                 .optimize_for(:cost)
                                 .choose_with_fallback # Drops requirements progressively

puts "\nWith graceful degradation: #{model || "None found"}"

# -----------------------------------------------------------------------------
# Example 7: Runtime Model Switching
# -----------------------------------------------------------------------------
puts "\n\n7. RUNTIME MODEL SWITCHING"
puts "-" * 40

def smart_complete(client, messages, requirements: {}, budget: nil)
  # Build selector based on requirements
  selector = OpenRouter::ModelSelector.new

  requirements.each do |cap|
    selector = selector.require(cap)
  end

  selector = selector.within_budget(max_cost: budget) if budget
  selector = selector.optimize_for(:cost)

  # Get model with fallbacks
  models = selector.choose_with_fallbacks(limit: 3)

  if models.empty?
    puts "  No models match requirements, using fallback strategy..."
    models = [selector.choose_with_fallback].compact
  end

  return nil if models.empty?

  # Try each model until one succeeds
  models.each do |model|
    puts "  Trying: #{model}"
    response = client.complete(messages, model: model)
    puts "  Success with: #{model}"
    return response
  rescue OpenRouter::Error => e
    puts "  Failed with #{model}: #{e.message}"
    next
  end

  nil
end

# Simple request - use cheapest model
puts "\nSimple question:"
response = smart_complete(
  client,
  [{ role: "user", content: "What is 2+2?" }],
  requirements: [:chat]
)
puts "Answer: #{response&.content&.slice(0, 100)}..."

# Complex request - need function calling
puts "\nRequest needing tools:"
smart_complete(
  client,
  [{ role: "user", content: "Help me plan a trip" }],
  requirements: [:function_calling],
  budget: 0.001
)

# -----------------------------------------------------------------------------
# Example 8: Context-Aware Model Selection
# -----------------------------------------------------------------------------
puts "\n\n8. CONTEXT-AWARE SELECTION"
puts "-" * 40

def select_model_for_content(content_length)
  # Estimate tokens (rough: 4 chars per token)
  estimated_tokens = content_length / 4

  selector = OpenRouter::ModelSelector.new.require(:chat)

  if estimated_tokens > 100_000
    puts "  Long content detected, requiring 200k+ context..."
    selector = selector.min_context(200_000)
  elsif estimated_tokens > 30_000
    puts "  Medium content, requiring 50k+ context..."
    selector = selector.min_context(50_000)
  end

  selector.optimize_for(:cost).choose
end

# Test with different content sizes
[1000, 50_000, 500_000].each do |chars|
  puts "\nContent size: #{chars} characters"
  model = select_model_for_content(chars)
  if model
    info = OpenRouter::ModelRegistry.get_model_info(model)
    puts "  Selected: #{model} (#{info[:context_length]} context)"
  end
end

# -----------------------------------------------------------------------------
# Example 9: Cost Comparison
# -----------------------------------------------------------------------------
puts "\n\n9. COST COMPARISON ACROSS MODELS"
puts "-" * 40

# Get several models with function calling
models = OpenRouter::ModelSelector.new
                                  .require(:function_calling)
                                  .optimize_for(:cost)
                                  .choose_with_fallbacks(limit: 10)

puts "Cost comparison for 10k input + 2k output tokens:\n"

costs = models.map do |model_id|
  cost = OpenRouter::ModelSelector.new.estimate_cost(
    model_id,
    input_tokens: 10_000,
    output_tokens: 2_000
  )
  [model_id, cost]
end

costs.sort_by(&:last).each do |model_id, cost|
  puts "  $#{"%.4f" % cost} - #{model_id}"
end

# -----------------------------------------------------------------------------
# Example 10: View Selection Criteria
# -----------------------------------------------------------------------------
puts "\n\n10. INTROSPECTING SELECTION CRITERIA"
puts "-" * 40

selector = OpenRouter::ModelSelector.new
                                    .require(:function_calling, :structured_outputs)
                                    .within_budget(max_cost: 0.01)
                                    .prefer_providers("anthropic", "openai")
                                    .avoid_patterns("*-free")
                                    .optimize_for(:performance)

criteria = selector.selection_criteria

puts "Current selection criteria:"
puts JSON.pretty_generate(criteria)

model = selector.choose
puts "\nSelected model: #{model}"

puts "\n#{"=" * 60}"
puts "Examples complete!"
puts "=" * 60
