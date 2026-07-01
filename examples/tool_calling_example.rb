#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "open_router"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "OpenRouter Ruby Gem Example"
  config.site_url = "https://github.com/OlympiaAI/open_router"
end

OpenRouter::Client.new

# Example 1: Define a tool using the DSL
puts "=== Example 1: Tool Definition with DSL ==="

search_tool = OpenRouter::Tool.define do
  name "search_gutenberg_books"
  description "Search for books in the Project Gutenberg library"

  parameters do
    array :search_terms, required: true do
      string description: "Search term for finding books"
    end
    integer :max_results, description: "Maximum number of results to return"
  end
end

puts "Tool definition:"
puts search_tool.to_json

# Example 2: Define a tool using hash format
puts "\n=== Example 2: Tool Definition with Hash ==="

weather_tool = OpenRouter::Tool.new({
                                      name: "get_weather",
                                      description: "Get current weather for a location",
                                      parameters: {
                                        type: "object",
                                        properties: {
                                          location: {
                                            type: "string",
                                            description: "City and state, e.g. San Francisco, CA"
                                          },
                                          unit: {
                                            type: "string",
                                            enum: %w[celsius fahrenheit],
                                            description: "Temperature unit"
                                          }
                                        },
                                        required: ["location"]
                                      }
                                    })

puts "Tool definition:"
puts weather_tool.to_json

# Example 3: Tool calling conversation
puts "\n=== Example 3: Tool Calling Conversation ==="

def simulate_search(_search_terms, max_results = 10)
  # Simulate a search function
  results = [
    { title: "Programming Ruby", author: "Dave Thomas", year: 2004 },
    { title: "The Ruby Programming Language", author: "David Flanagan", year: 2008 }
  ]

  results.first(max_results).to_json
end

def simulate_weather(location, unit = "fahrenheit")
  # Simulate a weather API call
  {
    location:,
    temperature: unit == "celsius" ? 22 : 72,
    conditions: "Sunny",
    unit:
  }.to_json
end

# Initial message
messages = [
  { role: "user", content: "Can you search for Ruby programming books and also tell me the weather in San Francisco?" }
]

puts "User: #{messages.first[:content]}"

# Uncomment the following lines to make a real API call:
# begin
#   # Make the tool call request
#   response = client.complete(
#     messages,
#     model: "anthropic/claude-3.5-sonnet",
#     tools: [search_tool, weather_tool],
#     tool_choice: "auto"
#   )
#
#   puts "\nAssistant response:"
#   puts response.content if response.has_content?
#
#   # Handle tool calls
#   if response.has_tool_calls?
#     puts "\nTool calls requested:"
#
#     # Add the assistant's message to conversation
#     messages << response.to_message
#
#     # Execute each tool call
#     response.tool_calls.each do |tool_call|
#       puts "- #{tool_call.name} with arguments: #{tool_call.arguments}"
#
#       # Execute the tool based on its name
#       result = case tool_call.name
#                when "search_gutenberg_books"
#                  args = tool_call.arguments
#                  simulate_search(args["search_terms"], args["max_results"])
#                when "get_weather"
#                  args = tool_call.arguments
#                  simulate_weather(args["location"], args["unit"])
#                else
#                  "Unknown tool: #{tool_call.name}"
#                end
#
#       puts "  Result: #{result}"
#
#       # Add tool result to conversation
#       messages << tool_call.to_result_message(result)
#     end
#
#     # Get final response with tool results
#     final_response = client.complete(
#       messages,
#       model: "anthropic/claude-3.5-sonnet",
#       tools: [search_tool, weather_tool]
#     )
#
#     puts "\nFinal assistant response:"
#     puts final_response.content
#   end
#
# rescue OpenRouter::ServerError => e
#   puts "Error: #{e.message}"
# rescue => e
#   puts "Unexpected error: #{e.message}"
# end

puts "\n(Tool calling example complete - uncomment the API call section to test with real API)"
