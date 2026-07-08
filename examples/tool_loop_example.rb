#!/usr/bin/env ruby
# frozen_string_literal: true

# Tool Calling Loop Example (Chat Completions API)
# =================================================
# This example demonstrates a complete tool calling workflow using the
# Chat Completions API, including multi-tool calls and conversation continuation.
#
# Run with: ruby -I lib examples/tool_loop_example.rb

require "open_router"
require "json"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV.fetch("OPENROUTER_API_KEY") do
    abort "Please set OPENROUTER_API_KEY environment variable"
  end
  config.site_name = "Tool Loop Examples"
end

client = OpenRouter::Client.new

# Use a model with function calling support
MODEL = "openai/gpt-4o-mini"

puts "=" * 60
puts "TOOL CALLING LOOP EXAMPLE"
puts "=" * 60

# -----------------------------------------------------------------------------
# Define Our Tools
# -----------------------------------------------------------------------------

# Calculator tool for math operations
calculator_tool = OpenRouter::Tool.define do
  name "calculate"
  description "Perform mathematical calculations. Use this for any math operations."

  parameters do
    string :expression, required: true, description: "Mathematical expression to evaluate (e.g., '2 + 2', '15 * 7')"
  end
end

# Weather lookup tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"

  parameters do
    string :location, required: true, description: "City name (e.g., 'San Francisco', 'London')"
    string :units, enum: %w[celsius fahrenheit], description: "Temperature units"
  end
end

# Search tool
search_tool = OpenRouter::Tool.define do
  name "search"
  description "Search for information on a topic"

  parameters do
    string :query, required: true, description: "Search query"
    integer :max_results, description: "Maximum number of results (default: 3)"
  end
end

TOOLS = [calculator_tool, weather_tool, search_tool].freeze

# -----------------------------------------------------------------------------
# Tool Execution Functions (simulated)
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
    # Standard math expression - safe eval for basic math
    expression = expr.gsub(%r{[^0-9+\-*/.()\s]}, "")
    result = begin
      eval(expression)
    rescue StandardError
      "Error: Invalid expression"
    end
    { result: result, expression: expr }

  when "get_weather"
    # Simulated weather data
    location = args["location"]
    units = args["units"] || "celsius"
    temp = rand(15..30)
    temp = (temp * 9 / 5) + 32 if units == "fahrenheit"
    {
      location: location,
      temperature: temp,
      units: units,
      conditions: %w[sunny cloudy partly_cloudy rainy].sample,
      humidity: rand(40..80)
    }

  when "search"
    # Simulated search results
    query = args["query"]
    max_results = args["max_results"] || 3
    results = max_results.times.map do |i|
      {
        title: "Result #{i + 1} for '#{query}'",
        snippet: "This is a simulated search result about #{query}.",
        url: "https://example.com/result-#{i + 1}"
      }
    end
    { query: query, results: results }

  else
    { error: "Unknown tool: #{name}" }
  end
end

# -----------------------------------------------------------------------------
# Example 1: Simple Single Tool Call
# -----------------------------------------------------------------------------
puts "\n1. SIMPLE TOOL CALL"
puts "-" * 40

messages = [
  { role: "user", content: "What is 15 multiplied by 23?" }
]

puts "User: #{messages.last[:content]}"

response = client.complete(messages, model: MODEL, tools: TOOLS)

if response.has_tool_calls?
  puts "\nAssistant wants to call tools:"
  response.tool_calls.each do |tc|
    puts "  - #{tc.name}(#{tc.arguments})"
  end

  # Execute the tool calls and collect results
  tool_results = response.tool_calls.map do |tc|
    result = execute_tool(tc.name, tc.arguments)
    puts "  -> Result: #{result}"
    tc.to_result_message(result)
  end

  # Continue the conversation with tool results
  messages << response.to_message
  messages.concat(tool_results)

  final_response = client.complete(messages, model: MODEL, tools: TOOLS)
  puts "\nAssistant: #{final_response.content}"
else
  puts "Assistant: #{response.content}"
end

# -----------------------------------------------------------------------------
# Example 2: Multiple Tool Calls at Once
# -----------------------------------------------------------------------------
puts "\n\n2. MULTIPLE TOOL CALLS"
puts "-" * 40

messages = [
  { role: "user", content: "I'm planning a trip. What's the weather like in Tokyo and Paris? Also, calculate how many hours are in 2 weeks." }
]

puts "User: #{messages.last[:content]}"

response = client.complete(messages, model: MODEL, tools: TOOLS)

if response.has_tool_calls?
  puts "\nAssistant wants to call #{response.tool_calls.length} tools:"
  response.tool_calls.each do |tc|
    puts "  - #{tc.name}(#{tc.arguments})"
  end

  # Execute all tool calls
  tool_results = response.tool_calls.map do |tc|
    result = execute_tool(tc.name, tc.arguments)
    puts "  -> #{tc.name} result: #{result.to_json[0..80]}..."
    tc.to_result_message(result)
  end

  # Continue conversation
  messages << response.to_message
  messages.concat(tool_results)

  final_response = client.complete(messages, model: MODEL, tools: TOOLS)
  puts "\nAssistant: #{final_response.content}"
end

# -----------------------------------------------------------------------------
# Example 3: Multi-Turn Tool Loop
# -----------------------------------------------------------------------------
puts "\n\n3. MULTI-TURN TOOL LOOP"
puts "-" * 40

messages = [
  { role: "system", content: "You are a helpful assistant. Use tools when needed to provide accurate information." },
  { role: "user", content: "Search for 'Ruby programming' and tell me what you find." }
]

puts "User: #{messages.last[:content]}"

max_iterations = 5
iteration = 0

loop do
  iteration += 1
  puts "\n[Iteration #{iteration}]"

  response = client.complete(messages, model: MODEL, tools: TOOLS)

  if response.has_tool_calls?
    # Process tool calls
    response.tool_calls.each do |tc|
      puts "  Tool call: #{tc.name}(#{JSON.pretty_generate(tc.arguments)[0..50]}...)"
    end

    tool_results = response.tool_calls.map do |tc|
      result = execute_tool(tc.name, tc.arguments)
      tc.to_result_message(result)
    end

    # Add to conversation
    messages << response.to_message
    messages.concat(tool_results)
  else
    # No more tool calls - we have the final response
    puts "\nAssistant: #{response.content}"
    break
  end

  if iteration >= max_iterations
    puts "\n[Max iterations reached]"
    break
  end
end

# -----------------------------------------------------------------------------
# Example 4: Error Handling in Tools
# -----------------------------------------------------------------------------
puts "\n\n4. ERROR HANDLING"
puts "-" * 40

# Define a tool handler that includes error handling
def safe_execute_tool(name, args)
  result = execute_tool(name, args)
  { success: true, data: result }
rescue StandardError => e
  { success: false, error: e.message }
end

messages = [
  { role: "user", content: "Calculate the result of: 100 / (5 - 5)" }
]

puts "User: #{messages.last[:content]}"

response = client.complete(messages, model: MODEL, tools: TOOLS)

if response.has_tool_calls?
  response.tool_calls.each do |tc|
    puts "  Tool call: #{tc.name}"

    # Use the built-in execute method which handles errors
    result = tc.execute do |name, args|
      execute_tool(name, args)
    end

    if result.success?
      puts "  -> Success: #{result.result}"
    else
      puts "  -> Error: #{result.error}"
    end

    # Continue with the result either way
    messages << response.to_message
    messages << result.to_message
  end

  final_response = client.complete(messages, model: MODEL, tools: TOOLS)
  puts "\nAssistant: #{final_response.content}"
end

# -----------------------------------------------------------------------------
# Example 5: Tool Call Validation
# -----------------------------------------------------------------------------
puts "\n\n5. TOOL CALL VALIDATION"
puts "-" * 40

messages = [
  { role: "user", content: "What's the weather in Boston?" }
]

response = client.complete(messages, model: MODEL, tools: TOOLS)

if response.has_tool_calls?
  response.tool_calls.each do |tc|
    # Validate the tool call against our tool definitions
    if tc.valid?(tools: TOOLS)
      puts "Tool call '#{tc.name}' is valid"
      puts "  Arguments: #{tc.arguments}"
    else
      errors = tc.validation_errors(tools: TOOLS)
      puts "Tool call '#{tc.name}' has validation errors:"
      errors.each { |e| puts "  - #{e}" }
    end
  end
end

puts "\n#{"=" * 60}"
puts "Examples complete!"
puts "=" * 60
