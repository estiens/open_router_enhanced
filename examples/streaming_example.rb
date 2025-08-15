# frozen_string_literal: true

require "open_router"

# Streaming example using OpenRouter Enhanced gem
#
# This example demonstrates:
# - Streaming responses
# - Real-time token processing
# - Callback-based streaming
# - Response accumulation

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Streaming Example"
  config.site_url = "https://github.com/yourusername/open_router_enhanced"
end

# Initialize streaming client
client = OpenRouter::StreamingClient.new

puts "=" * 60
puts "Streaming Example"
puts "=" * 60

# Example 1: Basic streaming with block
puts "\n1. Basic Streaming"
puts "-" * 60
puts "Assistant: "

messages = [
  { role: "user", content: "Count from 1 to 10, saying each number on a new line." }
]

accumulated = ""
client.stream(messages, model: "openai/gpt-4o-mini") do |chunk|
  content = chunk.dig("choices", 0, "delta", "content")
  if content
    print content
    accumulated += content
  end
end

puts "\n\nFull response:\n#{accumulated}"

# Example 2: Streaming with callbacks
puts "\n2. Streaming with Callbacks"
puts "-" * 60

full_response = ""

client.on(:stream_start) do
  puts "Stream started..."
end

client.on(:stream_chunk) do |chunk|
  content = chunk.dig("choices", 0, "delta", "content")
  if content
    print content
    full_response += content
  end
end

client.on(:stream_end) do |response|
  puts "\n\nStream completed!"
  puts "Total tokens: #{response.usage&.dig("total_tokens") || "N/A"}"
end

client.on(:stream_error) do |error|
  puts "\nError during streaming: #{error}"
end

puts "\nAssistant: "
client.stream(
  [{ role: "user", content: "Write a haiku about coding" }],
  model: "anthropic/claude-3-haiku"
)

# Example 3: Streaming with tool calls
puts "\n\n3. Streaming with Tool Calls"
puts "-" * 60

tools = [
  OpenRouter::Tool.define do
    name "get_weather"
    description "Get current weather for a location"
    parameters do
      string :location, required: true, description: "City name"
      string :units, enum: %w[celsius fahrenheit], description: "Temperature units"
    end
  end
]

puts "Requesting weather..."
client.stream(
  [{ role: "user", content: "What's the weather in Tokyo?" }],
  model: "anthropic/claude-3.5-sonnet",
  tools: tools
) do |chunk|
  # Handle tool calls in streaming
  tool_calls = chunk.dig("choices", 0, "delta", "tool_calls")
  tool_calls&.each do |tc|
    puts "Tool call detected: #{tc.dig("function", "name")}"
  end

  # Handle content
  content = chunk.dig("choices", 0, "delta", "content")
  print content if content
end

# Example 4: Streaming with metadata collection
puts "\n\n4. Streaming with Metadata Collection"
puts "-" * 60

metadata = {
  chunks_received: 0,
  total_content_length: 0,
  start_time: Time.now,
  finish_reason: nil
}

accumulated_response = ""

client.stream(
  [{ role: "user", content: "Explain async/await in JavaScript in one paragraph" }],
  model: "openai/gpt-4o-mini"
) do |chunk|
  metadata[:chunks_received] += 1

  content = chunk.dig("choices", 0, "delta", "content")
  if content
    metadata[:total_content_length] += content.length
    accumulated_response += content
    print content
  end

  finish_reason = chunk.dig("choices", 0, "finish_reason")
  metadata[:finish_reason] = finish_reason if finish_reason
end

metadata[:end_time] = Time.now
metadata[:duration] = metadata[:end_time] - metadata[:start_time]

puts "\n\nMetadata:"
puts "  Chunks received: #{metadata[:chunks_received]}"
puts "  Content length: #{metadata[:total_content_length]} characters"
puts "  Duration: #{metadata[:duration].round(2)} seconds"
puts "  Finish reason: #{metadata[:finish_reason]}"

# Example 5: Streaming long-form content
puts "\n\n5. Streaming Long-Form Content"
puts "-" * 60

puts "Generating story..."
print "\n"

client.stream(
  [
    { role: "system", content: "You are a creative storyteller." },
    { role: "user", content: "Write a very short 2-sentence story about a robot learning to paint." }
  ],
  model: "anthropic/claude-3-haiku",
  extras: { max_tokens: 200 }
) do |chunk|
  content = chunk.dig("choices", 0, "delta", "content")
  print content if content
  $stdout.flush # Ensure immediate output
end

puts "\n\n#{"=" * 60}"
puts "Streaming examples completed!"
puts "=" * 60

# Clean up callbacks
client.callbacks.clear
