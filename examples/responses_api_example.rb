#!/usr/bin/env ruby
# frozen_string_literal: true

# Responses API Multi-Turn Tool Loop Example
# ===========================================
# This example demonstrates the Responses API, which provides a streamlined
# way to handle multi-turn tool conversations with automatic input building.
#
# The Responses API differs from Chat Completions:
# - Uses `output` array with typed items instead of `choices`
# - Provides `build_follow_up_input()` for easy conversation continuation
# - Tool calls have a flat structure (not nested under `function`)
# - Supports reasoning output as a first-class type
#
# Run with: ruby -I lib examples/responses_api_example.rb

require "open_router"
require "json"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV.fetch("OPENROUTER_API_KEY") do
    abort "Please set OPENROUTER_API_KEY environment variable"
  end
  config.site_name = "Responses API Examples"
end

client = OpenRouter::Client.new

# Use a model that supports the Responses API
MODEL = "openai/gpt-4o-mini"

puts "=" * 60
puts "RESPONSES API TOOL LOOP EXAMPLE"
puts "=" * 60

# -----------------------------------------------------------------------------
# Define Our Tools
# -----------------------------------------------------------------------------

calculator_tool = OpenRouter::Tool.define do
  name "calculate"
  description "Perform mathematical calculations"
  parameters do
    string :expression, required: true, description: "Math expression to evaluate"
  end
end

weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"
  parameters do
    string :location, required: true, description: "City name"
  end
end

stock_tool = OpenRouter::Tool.define do
  name "get_stock_price"
  description "Get current stock price for a ticker symbol"
  parameters do
    string :symbol, required: true, description: "Stock ticker symbol (e.g., AAPL, GOOGL)"
  end
end

TOOLS = [calculator_tool, weather_tool, stock_tool].freeze

# -----------------------------------------------------------------------------
# Tool Execution Function
# -----------------------------------------------------------------------------

def execute_tool(name, args)
  case name
  when "calculate"
    expr = args["expression"]
    # Handle percentage expressions like "15% of 378.90"
    if expr =~ /(\d+(?:\.\d+)?)\s*%\s*of\s*(\d+(?:\.\d+)?)/i
      result = (Regexp.last_match(1).to_f / 100) * Regexp.last_match(2).to_f
      return { result: result.round(2), expression: expr }
    end
    # Standard math expression
    expression = expr.gsub(%r{[^0-9+\-*/.()\s]}, "")
    begin
      { result: eval(expression), expression: expr }
    rescue StandardError
      { error: "Invalid expression" }
    end

  when "get_weather"
    location = args["location"]
    temp = rand(10..35)
    {
      location: location,
      temperature_celsius: temp,
      conditions: %w[sunny cloudy rainy partly_cloudy].sample,
      humidity: rand(30..90)
    }

  when "get_stock_price"
    symbol = args["symbol"].upcase
    prices = { "AAPL" => 178.50, "GOOGL" => 141.20, "MSFT" => 378.90, "AMZN" => 185.30 }
    price = prices[symbol] || (100 + rand * 200).round(2)
    {
      symbol: symbol,
      price: price,
      currency: "USD",
      change: (rand * 10 - 5).round(2)
    }

  else
    { error: "Unknown tool: #{name}" }
  end
end

# -----------------------------------------------------------------------------
# Example 1: Basic Responses API Call
# -----------------------------------------------------------------------------
puts "\n1. BASIC RESPONSES API CALL"
puts "-" * 40

response = client.responses(
  "What is 25 times 17?",
  model: MODEL,
  tools: TOOLS
)

puts "Response ID: #{response.id}"
puts "Model: #{response.model}"
puts "Status: #{response.status}"

if response.has_tool_calls?
  puts "\nTool calls requested:"
  response.tool_calls.each do |tc|
    puts "  - #{tc.name}: #{tc.arguments}"
  end
end

# -----------------------------------------------------------------------------
# Example 2: execute_tool_calls with Block
# -----------------------------------------------------------------------------
puts "\n\n2. EXECUTE_TOOL_CALLS WITH BLOCK"
puts "-" * 40

response = client.responses(
  "What's the weather in Seattle?",
  model: MODEL,
  tools: TOOLS
)

if response.has_tool_calls?
  # Execute all tool calls with a single block
  results = response.execute_tool_calls do |name, args|
    puts "  Executing: #{name}(#{args})"
    execute_tool(name, args)
  end

  puts "\nResults:"
  results.each do |result|
    if result.success?
      puts "  Success: #{result.result}"
    else
      puts "  Error: #{result.error}"
    end
  end
end

# -----------------------------------------------------------------------------
# Example 3: Multi-Turn with build_follow_up_input
# -----------------------------------------------------------------------------
puts "\n\n3. MULTI-TURN WITH BUILD_FOLLOW_UP_INPUT"
puts "-" * 40

original_query = "What's the weather in Tokyo and what's Apple stock at?"
puts "User: #{original_query}"

# First request
response = client.responses(
  original_query,
  model: MODEL,
  tools: TOOLS
)

if response.has_tool_calls?
  puts "\nTool calls (Round 1):"
  response.tool_calls.each do |tc|
    puts "  - #{tc.name}: #{tc.arguments}"
  end

  # Execute the tools
  results = response.execute_tool_calls do |name, args|
    execute_tool(name, args)
  end

  puts "\nExecuted tools, building follow-up..."

  # Build the follow-up input automatically
  follow_up_input = response.build_follow_up_input(
    original_input: original_query,
    tool_results: results
  )

  puts "Follow-up input has #{follow_up_input.length} items"

  # Continue the conversation
  final_response = client.responses(
    follow_up_input,
    model: MODEL,
    tools: TOOLS
  )

  if final_response.has_tool_calls?
    puts "\nMore tool calls requested (Round 2)..."
  else
    puts "\nAssistant: #{final_response.content}"
  end
end

# -----------------------------------------------------------------------------
# Example 4: Complete Multi-Turn Loop Until Done
# -----------------------------------------------------------------------------
puts "\n\n4. COMPLETE MULTI-TURN LOOP"
puts "-" * 40

query = "I need to: 1) Check the weather in London, 2) Get Microsoft stock price, 3) Calculate 15% of $378.90"
puts "User: #{query}"

current_input = query
max_rounds = 5
round = 0

loop do
  round += 1
  puts "\n[Round #{round}]"

  response = client.responses(
    current_input,
    model: MODEL,
    tools: TOOLS
  )

  if response.has_tool_calls?
    puts "Tool calls:"
    response.tool_calls.each { |tc| puts "  - #{tc.name}(#{tc.arguments})" }

    # Execute tools
    results = response.execute_tool_calls do |name, args|
      result = execute_tool(name, args)
      puts "  -> #{result.to_json[0..60]}..."
      result
    end

    # Build next input
    current_input = response.build_follow_up_input(
      original_input: current_input.is_a?(String) ? current_input : current_input,
      tool_results: results
    )
  else
    # Final response - no more tool calls
    puts "\nFinal Answer:"
    puts response.content
    break
  end

  if round >= max_rounds
    puts "\n[Max rounds reached]"
    break
  end
end

puts "\nToken usage: #{response.total_tokens} total (#{response.input_tokens} in, #{response.output_tokens} out)"

# -----------------------------------------------------------------------------
# Example 5: Adding Follow-Up Questions
# -----------------------------------------------------------------------------
puts "\n\n5. FOLLOW-UP QUESTIONS"
puts "-" * 40

original = "What's the current price of Google stock?"
puts "User: #{original}"

response = client.responses(original, model: MODEL, tools: TOOLS)

if response.has_tool_calls?
  results = response.execute_tool_calls { |name, args| execute_tool(name, args) }

  # Build follow-up WITH an additional question
  follow_up = response.build_follow_up_input(
    original_input: original,
    tool_results: results,
    follow_up_message: "Is that higher or lower than last week?"
  )

  next_response = client.responses(follow_up, model: MODEL, tools: TOOLS)
  puts "\nAssistant: #{next_response.content}"
end

# -----------------------------------------------------------------------------
# Example 6: Comparing Responses API vs Chat Completions
# -----------------------------------------------------------------------------
puts "\n\n6. RESPONSES API vs CHAT COMPLETIONS COMPARISON"
puts "-" * 40

puts <<~COMPARISON
  Key differences:

  CHAT COMPLETIONS API:
  - response["choices"][0]["message"]["content"]
  - Tool calls under: choices[0].message.tool_calls[].function.{name, arguments}
  - Manual message construction for continuation
  - Use: response.to_message + tool_call.to_result_message(result)

  RESPONSES API:
  - response.content (or response["output"])
  - Tool calls at: output[] where type="function_call"
  - Automatic continuation with: response.build_follow_up_input()
  - Use: response.execute_tool_calls { |name, args| ... }

  When to use each:
  - Chat Completions: Standard chat, fine-grained control, streaming
  - Responses API: Multi-turn tool loops, reasoning output, simpler code
COMPARISON

puts "\n#{"=" * 60}"
puts "Examples complete!"
puts "=" * 60
