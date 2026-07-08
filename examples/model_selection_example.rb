#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the ModelSelector functionality
# Run this with: ruby -I lib examples/model_selection_example.rb

require "open_router"

# Configure OpenRouter (you would set your actual API key)
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"] || "your-api-key-here"
  config.site_name = "ModelSelector Example"
  config.site_url = "https://example.com"
end

puts "🤖 OpenRouter ModelSelector Examples"
puts "=" * 50

# Example 1: Basic cost optimization
puts "\n1. Basic cost optimization:"
selector = OpenRouter::ModelSelector.new
cheapest_model = selector.optimize_for(:cost).choose

if cheapest_model
  puts "   Cheapest model: #{cheapest_model}"
  cost_info = OpenRouter::ModelRegistry.get_model_info(cheapest_model)
  puts "   Cost: $#{cost_info[:cost_per_1k_tokens][:input]} per 1k input tokens"
else
  puts "   No models available"
end

# Example 2: Find models with specific capabilities
puts "\n2. Models with function calling capability:"
function_models = OpenRouter::ModelSelector.new
                                           .require(:function_calling)
                                           .optimize_for(:cost)
                                           .choose_with_fallbacks(limit: 3)

if function_models.any?
  function_models.each_with_index do |model, i|
    puts "   #{i + 1}. #{model}"
  end
else
  puts "   No models with function calling found"
end

# Example 3: Budget-constrained selection with multiple requirements
puts "\n3. Budget-constrained selection ($0.01 max, with vision):"
budget_model = OpenRouter::ModelSelector.new
                                        .within_budget(max_cost: 0.01)
                                        .require(:vision)
                                        .optimize_for(:cost)
                                        .choose

if budget_model
  puts "   Selected: #{budget_model}"
  model_info = OpenRouter::ModelRegistry.get_model_info(budget_model)
  puts "   Capabilities: #{model_info[:capabilities].join(", ")}"
  puts "   Cost: $#{model_info[:cost_per_1k_tokens][:input]} per 1k input tokens"
else
  puts "   No models found within budget with vision capability"
end

# Example 4: Provider preferences
puts "\n4. Prefer specific providers:"
provider_model = OpenRouter::ModelSelector.new
                                          .prefer_providers("anthropic", "openai")
                                          .require(:function_calling)
                                          .optimize_for(:cost)
                                          .choose

if provider_model
  puts "   Selected: #{provider_model}"
  provider = provider_model.split("/").first
  puts "   Provider: #{provider}"
else
  puts "   No models found from preferred providers"
end

# Example 5: Latest models with fallback
puts "\n5. Latest models (with graceful fallback):"
latest_model = OpenRouter::ModelSelector.new
                                        .optimize_for(:latest)
                                        .require(:function_calling)
                                        .min_context(100_000)
                                        .choose_with_fallback

if latest_model
  puts "   Selected: #{latest_model}"
  model_info = OpenRouter::ModelRegistry.get_model_info(latest_model)
  puts "   Context length: #{model_info[:context_length]} tokens"
  puts "   Released: #{Time.at(model_info[:created_at])}"
else
  puts "   No suitable models found"
end

# Example 6: Complex chaining example
puts "\n6. Complex requirements with method chaining:"
complex_selector = OpenRouter::ModelSelector.new
                                            .optimize_for(:performance)
                                            .require(:function_calling, :structured_outputs)
                                            .within_budget(max_cost: 0.05)
                                            .avoid_patterns("*-free", "*-preview")
                                            .prefer_providers("anthropic", "openai")

models = complex_selector.choose_with_fallbacks(limit: 2)
if models.any?
  puts "   Found #{models.length} suitable models:"
  models.each_with_index do |model, i|
    model_info = OpenRouter::ModelRegistry.get_model_info(model)
    puts "   #{i + 1}. #{model} (#{model_info[:performance_tier]} tier)"
  end
else
  puts "   No models meet all requirements"
end

# Example 7: Cost estimation
puts "\n7. Cost estimation:"
if cheapest_model
  estimated_cost = OpenRouter::ModelSelector.new.estimate_cost(
    cheapest_model,
    input_tokens: 2000,
    output_tokens: 500
  )
  puts "   Cost for 2000 input + 500 output tokens with #{cheapest_model}:"
  puts "   $#{estimated_cost.round(6)}"
end

# Example 8: Selection criteria inspection
puts "\n8. Selection criteria:"
criteria = OpenRouter::ModelSelector.new
                                    .optimize_for(:cost)
                                    .require(:function_calling)
                                    .within_budget(max_cost: 0.02)
                                    .selection_criteria

puts "   Strategy: #{criteria[:strategy]}"
puts "   Required capabilities: #{criteria[:requirements][:capabilities]}"
puts "   Max cost: $#{criteria[:requirements][:max_input_cost]}"

puts "\n✅ ModelSelector examples completed!"
