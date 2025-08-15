# Streaming Client

The OpenRouter gem provides an enhanced streaming client that offers real-time response streaming with comprehensive callback support and automatic response reconstruction. This is ideal for applications that need to display responses as they're generated or process large responses efficiently.

## Quick Start

```ruby
require 'open_router'

# Create streaming client
streaming_client = OpenRouter::StreamingClient.new(
  access_token: ENV["OPENROUTER_API_KEY"]
)

# Basic streaming
response = streaming_client.stream_complete(
  [{ role: "user", content: "Write a short story about a robot" }],
  model: "openai/gpt-4o-mini",
  accumulate_response: true
)

puts response.content  # Complete response after streaming
```

## Streaming with Callbacks

The streaming client supports extensive callback events for monitoring and custom processing.

### Available Streaming Events

- `:on_start` - Triggered when streaming begins
- `:on_chunk` - Triggered for each content chunk
- `:on_tool_call_chunk` - Triggered for tool call chunks
- `:on_finish` - Triggered when streaming completes
- `:on_error` - Triggered on errors

### Basic Callback Setup

```ruby
streaming_client = OpenRouter::StreamingClient.new

# Set up callbacks
streaming_client
  .on_stream(:on_start) do |data|
    puts "Starting request to #{data[:model]}"
    puts "Messages: #{data[:messages].size} messages"
  end
  .on_stream(:on_chunk) do |chunk|
    print chunk.content if chunk.content
  end
  .on_stream(:on_finish) do |response|
    puts "\nCompleted!"
    puts "Total tokens: #{response.total_tokens}"
    puts "Cost: $#{response.cost_estimate}"
  end
  .on_stream(:on_error) do |error|
    puts "Error: #{error.message}"
  end

# Stream the request
streaming_client.stream_complete(
  [{ role: "user", content: "Tell me about quantum computing" }],
  model: "anthropic/claude-3-5-sonnet"
)
```

## Streaming with Tool Calls

The streaming client fully supports tool calling with real-time notifications.

```ruby
# Define a tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"
  parameters do
    string :location, required: true, description: "City name"
    string :units, enum: ["celsius", "fahrenheit"], default: "celsius"
  end
end

# Set up tool call monitoring
streaming_client.on_stream(:on_tool_call_chunk) do |chunk|
  chunk.tool_calls.each do |tool_call|
    puts "Tool call: #{tool_call.name}"
    puts "Arguments: #{tool_call.arguments}"
  end
end

# Stream with tools
response = streaming_client.stream_complete(
  [{ role: "user", content: "What's the weather in Tokyo and London?" }],
  model: "anthropic/claude-3-5-sonnet",
  tools: [weather_tool],
  accumulate_response: true
)

# Handle tool calls after streaming
if response.has_tool_calls?
  response.tool_calls.each do |tool_call|
    case tool_call.name
    when "get_weather"
      weather_data = fetch_weather(tool_call.arguments["location"])
      puts "Weather: #{weather_data}"
    end
  end
end
```

## Advanced Streaming Patterns

### Real-time Processing

Process chunks immediately without accumulating the full response:

```ruby
streaming_client.stream_complete(
  messages,
  model: "openai/gpt-4o-mini",
  accumulate_response: false  # Don't store full response
) do |chunk|
  # Process each chunk immediately
  if chunk.content
    # Send to real-time display
    websocket.send(chunk.content)

    # Log to database
    log_chunk(chunk.content, timestamp: Time.now)

    # Trigger real-time analytics
    update_metrics(chunk)
  end
end
```

### Error Handling and Fallbacks

Implement robust error handling with automatic fallbacks:

```ruby
streaming_client.on_stream(:on_error) do |error|
  logger.error "Streaming failed: #{error.message}"

  # Implement fallback to non-streaming
  fallback_client = OpenRouter::Client.new
  fallback_response = fallback_client.complete(
    messages,
    model: "openai/gpt-4o-mini"
  )

  # Process fallback response
  process_complete_response(fallback_response)
end
```

### Performance Monitoring

Monitor streaming performance in real-time:

```ruby
start_time = nil
token_count = 0

streaming_client
  .on_stream(:on_start) { |data| start_time = Time.now }
  .on_stream(:on_chunk) do |chunk|
    if chunk.usage
      token_count = chunk.usage["total_tokens"] || token_count
      elapsed = Time.now - start_time
      tokens_per_second = token_count / elapsed
      puts "Speed: #{tokens_per_second.round(2)} tokens/sec"
    end
  end
  .on_stream(:on_finish) do |response|
    total_time = Time.now - start_time
    final_tps = response.total_tokens / total_time
    puts "Final speed: #{final_tps.round(2)} tokens/sec"

    # Log performance metrics
    log_performance({
      model: response.model,
      tokens: response.total_tokens,
      duration: total_time,
      tokens_per_second: final_tps
    })
  end
```

## Response Accumulation

The streaming client can automatically accumulate responses for you:

```ruby
# Accumulate full response (default)
response = streaming_client.stream_complete(
  messages,
  accumulate_response: true  # Default behavior
)

# Access complete response
puts response.content
puts response.total_tokens
puts response.cost_estimate

# Don't accumulate (memory efficient for large responses)
streaming_client.stream_complete(
  messages,
  accumulate_response: false
) do |chunk|
  # Process each chunk as it arrives
  process_chunk_immediately(chunk)
end
```

## Structured Outputs with Streaming

Streaming works seamlessly with structured outputs:

```ruby
# Define schema
user_schema = OpenRouter::Schema.define("user") do
  string :name, required: true
  integer :age, required: true
  string :email, required: true
end

# Stream with structured output
response = streaming_client.stream_complete(
  [{ role: "user", content: "Create a user: John Doe, 30, john@example.com" }],
  model: "openai/gpt-4o",
  response_format: user_schema,
  accumulate_response: true
)

# Access structured output after streaming
user_data = response.structured_output
puts "User: #{user_data['name']}, Age: #{user_data['age']}"
```

## Configuration Options

The streaming client accepts all the same configuration options as the regular client:

```ruby
streaming_client = OpenRouter::StreamingClient.new(
  access_token: ENV["OPENROUTER_API_KEY"],
  request_timeout: 60,    # Shorter timeout for streaming
  site_name: "My App",
  site_url: "https://myapp.com",
  track_usage: true       # Enable usage tracking
)

# Configure healing for streaming
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
end
```

## Memory Management

For long-running applications, manage memory efficiently:

```ruby
# Process large batches with memory management
messages_batch.each_slice(10) do |batch_slice|
  batch_slice.each do |messages|
    streaming_client.stream_complete(
      messages,
      accumulate_response: false  # Don't store in memory
    ) do |chunk|
      # Process and discard immediately
      process_and_save_chunk(chunk)
    end
  end

  # Force garbage collection periodically
  GC.start if batch_slice.size == 10
end
```

## Integration Patterns

### WebSocket Integration

```ruby
class StreamingController
  def stream_chat
    streaming_client = OpenRouter::StreamingClient.new

    streaming_client.on_stream(:on_chunk) do |chunk|
      if chunk.content
        ActionCable.server.broadcast(
          "chat_#{session_id}",
          { type: 'chunk', content: chunk.content }
        )
      end
    end

    streaming_client.on_stream(:on_finish) do |response|
      ActionCable.server.broadcast(
        "chat_#{session_id}",
        { type: 'complete', total_tokens: response.total_tokens }
      )
    end

    streaming_client.stream_complete(messages, model: model)
  end
end
```

### Background Job Integration

```ruby
class StreamingChatJob < ApplicationJob
  def perform(user_id, messages, model)
    streaming_client = OpenRouter::StreamingClient.new

    streaming_client.on_stream(:on_chunk) do |chunk|
      # Broadcast to user's channel
      ActionCable.server.broadcast(
        "user_#{user_id}",
        { chunk: chunk.content }
      )
    end

    streaming_client.on_stream(:on_finish) do |response|
      # Save complete response to database
      ChatMessage.create!(
        user_id: user_id,
        content: response.content,
        token_count: response.total_tokens,
        cost: response.cost_estimate
      )
    end

    streaming_client.stream_complete(messages, model: model)
  end
end
```

## Comparison: Streaming vs Regular Client

| Feature | Streaming Client | Regular Client |
|---------|-----------------|----------------|
| Response Time | Real-time chunks | Complete response at end |
| Memory Usage | Lower (optional accumulation) | Higher (full response) |
| User Experience | Immediate feedback | Wait for completion |
| Error Handling | Mid-stream error handling | End-of-request errors |
| Tool Calls | Real-time notifications | Post-completion processing |
| Complexity | Higher (callbacks) | Lower (simple request/response) |

## Best Practices

### When to Use Streaming

- **Long responses**: Stories, articles, detailed explanations
- **Real-time applications**: Chat interfaces, live content generation
- **Memory-constrained environments**: Processing large responses
- **User experience**: Showing progress to users

### When to Use Regular Client

- **Short responses**: Quick questions, simple completions
- **Batch processing**: Processing many requests sequentially
- **Simple integrations**: When callbacks add unnecessary complexity
- **Structured outputs**: When you need the complete JSON before processing

### Error Handling

Always implement comprehensive error handling:

```ruby
streaming_client.on_stream(:on_error) do |error|
  case error
  when OpenRouter::ServerError
    # API errors - might be transient
    retry_with_backoff
  when Faraday::TimeoutError
    # Network timeout - try different model
    fallback_to_faster_model
  else
    # Unknown error - log and fail gracefully
    logger.error "Streaming error: #{error.message}"
    send_error_to_user
  end
end
```

### Performance Optimization

```ruby
# Use connection pooling for high-throughput applications
streaming_client = OpenRouter::StreamingClient.new do |config|
  config.faraday do |f|
    f.adapter :net_http_persistent, pool_size: 10
  end
end

# Monitor performance
streaming_client.on_stream(:on_finish) do |response|
  if response.response_time > 5000  # 5 seconds
    logger.warn "Slow streaming response: #{response.response_time}ms"
  end
end
```

## Troubleshooting

### Common Issues

#### Connection Timeouts
```ruby
# Problem: Streaming connections timeout
streaming_client = OpenRouter::StreamingClient.new(
  request_timeout: 300  # Increase timeout for long responses
)

# Or handle timeouts gracefully
streaming_client.on_stream(:on_error) do |error|
  if error.is_a?(Faraday::TimeoutError)
    puts "Request timed out, falling back to regular client"
    fallback_response = regular_client.complete(messages, model: model)
  end
end
```

#### Memory Leaks
```ruby
# Problem: Memory usage grows over time
# Solution: Use non-accumulating streaming
streaming_client.stream_complete(
  messages,
  accumulate_response: false  # Don't store full response
) do |chunk|
  process_chunk_immediately(chunk)
end

# Or reset callbacks periodically
streaming_client.clear_callbacks if request_count % 1000 == 0
```

#### Missing Chunks
```ruby
# Problem: Some chunks appear empty
# Solution: Check for different content types
streaming_client.on_stream(:on_chunk) do |chunk|
  if chunk.content && !chunk.content.empty?
    process_content(chunk.content)
  elsif chunk.tool_calls && !chunk.tool_calls.empty?
    process_tool_calls(chunk.tool_calls)
  elsif chunk.usage
    update_usage_metrics(chunk.usage)
  end
end
```

### Best Practices

1. **Always handle errors**: Implement comprehensive error handling
2. **Set appropriate timeouts**: Balance responsiveness with reliability
3. **Use non-accumulating mode for large responses**: Avoid memory issues
4. **Monitor performance**: Track tokens per second and response times
5. **Implement fallbacks**: Have a backup plan for streaming failures
6. **Clean up resources**: Clear callbacks and reset trackers periodically

The streaming client provides a powerful foundation for building responsive AI applications that can process and display results in real-time while maintaining full compatibility with all of OpenRouter's advanced features.