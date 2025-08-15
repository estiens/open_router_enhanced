#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the Client's smart completion methods
# Run this with: ruby -I lib examples/smart_completion_example.rb

require "open_router"

# NOTE: This example shows the interface but won't make real API calls
# To test with real API calls, set your OPENROUTER_API_KEY environment variable

puts "🧠 Smart Completion Examples"
puts "=" * 40

# Create a client
client = OpenRouter::Client.new

# Example 1: Using the select_model helper
puts "\n1. Using select_model helper:"
selector = client.select_model
                 .optimize_for(:cost)
                 .require(:function_calling)
                 .within_budget(max_cost: 0.01)

selected_model = selector.choose
puts "   Selected model: #{selected_model}"

# Example 2: Smart completion with requirements
puts "\n2. Smart completion interface:"
requirements = {
  capabilities: [:function_calling],
  max_input_cost: 0.01,
  providers: {
    prefer: %w[anthropic openai],
    avoid: ["google"]
  }
}

messages = [
  { role: "user", content: "What is the weather like today?" }
]

puts "   Requirements: #{requirements}"
puts "   Messages: #{messages}"

# NOTE: This would make a real API call if OPENROUTER_API_KEY is set
# For demo purposes, we'll show what model would be selected
selector_for_smart = OpenRouter::ModelSelector.new
                                              .optimize_for(:cost)
                                              .require(*requirements[:capabilities])
                                              .within_budget(max_cost: requirements[:max_input_cost])
                                              .prefer_providers(*requirements[:providers][:prefer])
                                              .avoid_providers(*requirements[:providers][:avoid])

smart_model = selector_for_smart.choose
puts "   Would use model: #{smart_model}"

# Example 3: Smart completion with fallback
puts "\n3. Smart completion with fallback:"
fallback_requirements = {
  capabilities: %i[function_calling vision],
  max_input_cost: 0.005, # Very restrictive budget
  min_context_length: 100_000
}

fallback_selector = OpenRouter::ModelSelector.new
                                             .optimize_for(:cost)
                                             .require(*fallback_requirements[:capabilities])
                                             .within_budget(max_cost: fallback_requirements[:max_input_cost])
                                             .min_context(fallback_requirements[:min_context_length])

fallback_models = fallback_selector.choose_with_fallbacks(limit: 3)
puts "   Fallback candidates: #{fallback_models}"

# Example 4: Demonstrating graceful degradation
puts "\n4. Graceful degradation example:"
degradation_model = fallback_selector.choose_with_fallback
puts "   Graceful fallback selected: #{degradation_model}"

# Example 5: Show the actual method signatures
puts "\n5. Available Client methods:"
puts "   - client.select_model() -> ModelSelector"
puts "   - client.smart_complete(messages, requirements:, optimization:)"
puts "   - client.smart_complete_with_fallback(messages, requirements:, max_retries:)"

puts "\n✅ Smart completion examples completed!"
puts "\n💡 To test with real API calls:"
puts "   export OPENROUTER_API_KEY=your_key_here"
puts "   ruby -I lib examples/smart_completion_example.rb"
