# frozen_string_literal: true

require "open_router"

# Observability example using OpenRouter Enhanced gem
#
# This example demonstrates:
# - Usage tracking and analytics
# - Cost monitoring
# - Performance metrics
# - Callback system for observability
# - Export capabilities

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Observability Example"
  config.site_url = "https://github.com/yourusername/open_router_enhanced"
end

puts "=" * 60
puts "Observability & Usage Tracking Example"
puts "=" * 60

# Example 1: Basic usage tracking
puts "\n1. Basic Usage Tracking"
puts "-" * 60

client = OpenRouter::Client.new(track_usage: true)

# Make some requests
3.times do |i|
  response = client.complete(
    [{ role: "user", content: "Count to #{i + 1}" }],
    model: "openai/gpt-4o-mini"
  )
  puts "Request #{i + 1}: #{response.total_tokens} tokens"
end

# View usage summary
tracker = client.usage_tracker
puts "\nUsage Summary:"
puts "  Total requests: #{tracker.request_count}"
puts "  Total tokens: #{tracker.total_tokens}"
puts "  Prompt tokens: #{tracker.total_prompt_tokens}"
puts "  Completion tokens: #{tracker.total_completion_tokens}"
puts "  Cached tokens: #{tracker.total_cached_tokens}"
puts "  Total cost: $#{tracker.total_cost.round(4)}"
puts "  Average tokens/request: #{tracker.average_tokens_per_request.round(0)}"
puts "  Average cost/request: $#{tracker.average_cost_per_request.round(4)}"

# Example 2: Per-model breakdown
puts "\n2. Per-Model Usage Breakdown"
puts "-" * 60

client.usage_tracker.reset! # Start fresh

# Use different models
client.complete([{ role: "user", content: "Say hi" }], model: "openai/gpt-4o-mini")
client.complete([{ role: "user", content: "Say hi" }], model: "anthropic/claude-3-haiku")
client.complete([{ role: "user", content: "Say hi" }], model: "openai/gpt-4o-mini")

# View per-model stats
puts "\nModel usage breakdown:"
client.usage_tracker.model_usage.each do |model, stats|
  puts "\n  #{model}:"
  puts "    Requests: #{stats[:requests]}"
  puts "    Tokens: #{stats[:prompt_tokens] + stats[:completion_tokens]}"
  puts "    Cost: $#{stats[:cost].round(4)}"
end

puts "\nMost used model: #{client.usage_tracker.most_used_model}"
puts "Most expensive model: #{client.usage_tracker.most_expensive_model}"

# Example 3: Cache hit rate tracking
puts "\n3. Cache Hit Rate Tracking"
puts "-" * 60

client.usage_tracker.reset!

# Make repeated requests (OpenRouter may cache)
3.times do
  client.complete(
    [{ role: "user", content: "What is 2+2?" }],
    model: "openai/gpt-4o-mini"
  )
end

puts "Cache hit rate: #{client.usage_tracker.cache_hit_rate.round(2)}%"
puts "Cached tokens: #{client.usage_tracker.total_cached_tokens}"

# Example 4: Performance metrics
puts "\n4. Performance Metrics"
puts "-" * 60

tracker = client.usage_tracker
duration = tracker.session_duration

puts "Session duration: #{duration.round(2)} seconds"
puts "Tokens per second: #{tracker.tokens_per_second.round(2)}"
puts "Average tokens per request: #{tracker.average_tokens_per_request.round(0)}"

# Example 5: Callback-based monitoring
puts "\n5. Callback-Based Monitoring"
puts "-" * 60

monitored_client = OpenRouter::Client.new(track_usage: true)

# Set up monitoring callbacks
monitored_client.on(:before_request) do |params|
  puts "→ Request starting (model: #{params[:model]})"
end

monitored_client.on(:after_response) do |response|
  tokens = response.total_tokens
  cost = response.cost_estimate
  puts "← Response received: #{tokens} tokens" + (cost ? ", $#{cost.round(4)}" : "")
end

monitored_client.on(:on_error) do |error|
  puts "✗ Error occurred: #{error.message}"
end

# Make some requests
monitored_client.complete(
  [{ role: "user", content: "Hello!" }],
  model: "openai/gpt-4o-mini"
)

# Example 6: Cost tracking and budgets
puts "\n6. Cost Tracking & Budget Monitoring"
puts "-" * 60

budget_client = OpenRouter::Client.new(track_usage: true)
budget_limit = 0.10 # $0.10 budget

budget_client.on(:after_response) do |_response|
  total_cost = budget_client.usage_tracker.total_cost

  puts "⚠️  Warning: 80% of budget used ($#{total_cost.round(4)}/$#{budget_limit})" if total_cost > budget_limit * 0.8

  puts "🛑 Budget exceeded! Total: $#{total_cost.round(4)}" if total_cost > budget_limit
end

# Make requests
5.times do |i|
  budget_client.complete(
    [{ role: "user", content: "Short response #{i}" }],
    model: "openai/gpt-4o-mini",
    extras: { max_tokens: 10 }
  )
end

# Example 7: Export usage data
puts "\n7. Export Usage Data"
puts "-" * 60

# Print detailed summary
puts "\nDetailed summary:"
client.usage_tracker.print_summary

# Export as CSV
csv_data = client.usage_tracker.export_csv
puts "\nCSV export (first 200 chars):"
puts "#{csv_data[0...200]}..."

# Get structured summary
summary = client.usage_tracker.summary
puts "\nStructured summary available with keys:"
puts summary.keys.inspect

# Example 8: Request history
puts "\n8. Request History"
puts "-" * 60

history_client = OpenRouter::Client.new(track_usage: true)

# Make some requests
history_client.complete([{ role: "user", content: "Test 1" }], model: "openai/gpt-4o-mini")
history_client.complete([{ role: "user", content: "Test 2" }], model: "anthropic/claude-3-haiku")
history_client.complete([{ role: "user", content: "Test 3" }], model: "openai/gpt-4o-mini")

# View recent history
recent = history_client.usage_tracker.history(limit: 5)
puts "\nRecent requests:"
recent.each_with_index do |entry, i|
  puts "  #{i + 1}. #{entry[:model]} - #{entry[:prompt_tokens] + entry[:completion_tokens]} tokens at #{entry[:timestamp].strftime("%H:%M:%S")}"
end

puts "\n#{"=" * 60}"
puts "Observability examples completed!"
puts "=" * 60
puts "\nKey Takeaways:"
puts "  • Use track_usage: true to enable automatic tracking"
puts "  • Access tracker via client.usage_tracker"
puts "  • Set up callbacks for real-time monitoring"
puts "  • Export data as CSV for external analysis"
puts "  • Monitor costs and set budget alerts"
puts "=" * 60
