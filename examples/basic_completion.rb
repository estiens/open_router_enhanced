# frozen_string_literal: true

require "open_router"

# Basic completion example using OpenRouter Enhanced gem
#
# This example demonstrates:
# - Simple client initialization
# - Basic chat completion
# - Accessing response data
# - Cost tracking

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Basic Completion Example"
  config.site_url = "https://github.com/yourusername/open_router_enhanced"
end

# Initialize client
client = OpenRouter::Client.new

puts "=" * 60
puts "Basic Completion Example"
puts "=" * 60

# Simple completion
puts "\n1. Simple Chat Completion"
puts "-" * 60

messages = [
  { role: "user", content: "What is the capital of France?" }
]

response = client.complete(
  messages,
  model: "openai/gpt-4o-mini"
)

puts "Response: #{response.content}"
puts "Model: #{response.model}"
puts "Tokens used: #{response.total_tokens}"

# Multi-turn conversation
puts "\n2. Multi-turn Conversation"
puts "-" * 60

conversation = [
  { role: "user", content: "Tell me a short joke about programming" }
]

response = client.complete(
  conversation,
  model: "anthropic/claude-3-haiku"
)

puts "Assistant: #{response.content}"
conversation << { role: "assistant", content: response.content }

# Follow-up question
conversation << { role: "user", content: "Explain why that's funny" }

response = client.complete(
  conversation,
  model: "anthropic/claude-3-haiku"
)

puts "\nExplanation: #{response.content}"

# System message
puts "\n3. Using System Messages"
puts "-" * 60

messages = [
  { role: "system", content: "You are a helpful but concise assistant. Keep responses under 50 words." },
  { role: "user", content: "Explain quantum computing" }
]

response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  extras: { max_tokens: 100 }
)

puts "Concise response: #{response.content}"
puts "Completion tokens: #{response.completion_tokens}"

# Error handling
puts "\n4. Error Handling"
puts "-" * 60

begin
  client.complete(
    [{ role: "user", content: "Hello!" }],
    model: "invalid/model-name"
  )
rescue OpenRouter::ServerError => e
  puts "Caught error: #{e.message}"
end

# Response metadata
puts "\n5. Response Metadata"
puts "-" * 60

response = client.complete(
  [{ role: "user", content: "Say 'Hello, World!'" }],
  model: "openai/gpt-4o-mini"
)

puts "Response ID: #{response.id}"
puts "Model: #{response.model}"
puts "Provider: #{response.provider}" if response.provider
puts "Finish reason: #{response.finish_reason}"
puts "Created at: #{Time.at(response.created).strftime("%Y-%m-%d %H:%M:%S")}" if response.created
puts "Prompt tokens: #{response.prompt_tokens}"
puts "Completion tokens: #{response.completion_tokens}"
puts "Total tokens: #{response.total_tokens}"
puts "Cached tokens: #{response.cached_tokens}"

puts "\n#{"=" * 60}"
puts "Example completed successfully!"
puts "=" * 60
