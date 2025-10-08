# Observability & Analytics

The OpenRouter gem provides comprehensive observability features to help you monitor usage, costs, performance, and errors in your AI applications.

## Quick Start

```ruby
# Create client with automatic usage tracking
client = OpenRouter::Client.new(track_usage: true)

# Make some API calls
response = client.complete(
  [{ role: "user", content: "Hello world" }],
  model: "openai/gpt-4o-mini"
)

# View usage summary
puts "Used #{response.total_tokens} tokens"
puts "Cost: $#{response.cost_estimate}"
puts "Cache hit rate: #{client.usage_tracker.cache_hit_rate}%"

# Print detailed usage report
client.usage_tracker.print_summary
```

## Features Overview

### 1. Response Metadata
Enhanced response objects provide detailed metadata:

```ruby
response = client.complete(messages, model: "openai/gpt-4o-mini")

# Token usage
response.prompt_tokens      # => 150
response.completion_tokens  # => 75
response.total_tokens       # => 225
response.cached_tokens      # => 50

# Cost information
response.cost_estimate      # => 0.0023

# Provider and model info
response.provider           # => "OpenAI"
response.model              # => "openai/gpt-4o-mini"
response.system_fingerprint # => "fp_abc123"
response.finish_reason      # => "stop"
```

### 2. Usage Tracking
Automatic tracking of token usage and costs across all API calls:

```ruby
# Enable usage tracking (default: true)
client = OpenRouter::Client.new(track_usage: true)

# Access usage tracker
tracker = client.usage_tracker

# Key metrics
tracker.total_tokens          # Total tokens across all requests
tracker.total_cost            # Total estimated cost
tracker.request_count         # Number of API calls made
tracker.cache_hit_rate        # Percentage of tokens served from cache
tracker.session_duration      # Time since tracker initialization

# Performance metrics
tracker.tokens_per_second     # Processing speed
tracker.average_cost_per_request
tracker.average_tokens_per_request

# Model insights
tracker.most_used_model       # Model with most requests
tracker.most_expensive_model  # Model with highest total cost
```

### 3. Callback System
Event-driven observability with callbacks for key events:

```ruby
client = OpenRouter::Client.new

# Register callbacks for different events
client.on(:before_request) do |params|
  puts "Making request to model: #{params[:model]}"
end

client.on(:after_response) do |response|
  puts "Response received: #{response.total_tokens} tokens"
  puts "Cost: $#{response.cost_estimate}"
end

client.on(:on_tool_call) do |tool_calls|
  tool_calls.each do |tc|
    puts "Tool called: #{tc.name}"
  end
end

client.on(:on_error) do |error|
  puts "Error occurred: #{error.message}"
  # Log to monitoring system, send alerts, etc.
end

client.on(:on_healing) do |healing_data|
  if healing_data[:healed]
    puts "Successfully healed JSON response"
    puts "Attempts: #{healing_data[:attempts]}"
  else
    puts "JSON healing failed: #{healing_data[:error]}"
  end
end
```

**Note**: For detailed information about when auto-healing triggers, how it works, and configuration options, see the [Structured Outputs documentation](structured_outputs.md#json-auto-healing).

### 4. Streaming Observability
Enhanced streaming support with detailed event callbacks:

```ruby
streaming_client = OpenRouter::StreamingClient.new

streaming_client.on_stream(:on_start) do |data|
  puts "Starting stream with model: #{data[:model]}"
end

streaming_client.on_stream(:on_chunk) do |chunk|
  # Log chunk details, measure latency, etc.
  puts "Chunk received: #{chunk.dig('choices', 0, 'delta', 'content')}"
end

streaming_client.on_stream(:on_finish) do |final_response|
  puts "Stream completed. Total tokens: #{final_response&.total_tokens}"
end

streaming_client.on_stream(:on_tool_call_chunk) do |chunk|
  # Track tool calling progress
  puts "Tool call chunk received"
end

# Stream with accumulation
response = streaming_client.stream_complete(
  messages,
  model: "openai/gpt-4o-mini",
  accumulate_response: true
)
```

## Usage Analytics

### Detailed Reporting
Get comprehensive usage summaries:

```ruby
summary = client.usage_tracker.summary

# Returns structured data:
{
  session: {
    start: Time,
    duration_seconds: Float,
    requests: Integer
  },
  tokens: {
    total: Integer,
    prompt: Integer,
    completion: Integer,
    cached: Integer,
    cache_hit_rate: String # "15.2%"
  },
  cost: {
    total: Float,
    average_per_request: Float
  },
  performance: {
    tokens_per_second: Float,
    average_tokens_per_request: Float
  },
  models: {
    most_used: String,
    most_expensive: String,
    breakdown: Hash # Per-model stats
  }
}
```

### Model Breakdown
Analyze usage by model:

```ruby
breakdown = client.usage_tracker.model_breakdown

# Returns:
{
  "openai/gpt-4o-mini" => {
    requests: 15,
    tokens: 2500,
    cost: 0.025,
    cached_tokens: 200
  },
  "anthropic/claude-3-haiku" => {
    requests: 8,
    tokens: 1800,
    cost: 0.018,
    cached_tokens: 150
  }
}
```

### Export Options
Export usage data for external analysis:

```ruby
# Export as CSV
csv_data = client.usage_tracker.export_csv
File.write("usage_report.csv", csv_data)

# Get raw history
history = client.usage_tracker.history(limit: 100)
history.each do |entry|
  puts "#{entry[:timestamp]}: #{entry[:model]} - #{entry[:tokens]} tokens"
end

# Reset tracking
client.usage_tracker.reset!
```

## Performance Monitoring

### Cache Optimization
Monitor cache effectiveness:

```ruby
# Check cache performance
tracker = client.usage_tracker
puts "Cache hit rate: #{tracker.cache_hit_rate}%"
puts "Cached tokens: #{tracker.total_cached_tokens}"
puts "Savings: #{tracker.cache_savings_estimate}"

# Per-model cache analysis
tracker.model_breakdown.each do |model, stats|
  cache_rate = (stats[:cached_tokens].to_f / stats[:prompt_tokens]) * 100
  puts "#{model}: #{cache_rate.round(1)}% cache hit rate"
end
```

### Response Time Tracking
Monitor API response times:

```ruby
client.on(:before_request) do |params|
  @request_start = Time.now
end

client.on(:after_response) do |response|
  duration = Time.now - @request_start
  puts "Request took #{duration.round(3)}s"
  puts "Processing speed: #{response.total_tokens / duration} tokens/sec"
end
```

## Error Monitoring

### Comprehensive Error Tracking
Monitor and respond to different error types:

```ruby
client.on(:on_error) do |error|
  case error
  when Faraday::UnauthorizedError
    # Handle authentication issues
    alert_system("Authentication failed")
  when Faraday::TooManyRequestsError
    # Handle rate limiting
    exponential_backoff()
  when OpenRouter::ServerError
    # Handle server errors
    log_error(error)
  end
end

client.on(:on_healing) do |healing_data|
  if healing_data[:healed] == false
    # JSON healing failed - may indicate model issues
    alert_system("JSON healing failed for #{healing_data[:original]}")
  end
end
```

### Health Checks
Monitor system health:

```ruby
def health_check
  tracker = client.usage_tracker

  health_status = {
    uptime: tracker.session_duration,
    total_requests: tracker.request_count,
    error_rate: calculate_error_rate(),
    avg_response_time: calculate_avg_response_time(),
    cache_hit_rate: tracker.cache_hit_rate,
    total_cost: tracker.total_cost
  }

  # Alert if metrics exceed thresholds
  alert_if_unhealthy(health_status)

  health_status
end
```

## Integration Examples

### Datadog Integration
Send metrics to Datadog:

```ruby
require 'dogapi'

dog = Dogapi::Client.new(api_key, app_key)

client.on(:after_response) do |response|
  dog.emit_point('openrouter.tokens.total', response.total_tokens)
  dog.emit_point('openrouter.cost.estimate', response.cost_estimate)
  dog.emit_point('openrouter.cache.hit_rate',
                 response.cached_tokens.to_f / response.prompt_tokens * 100)
end
```

### Prometheus Metrics
Export Prometheus metrics:

```ruby
require 'prometheus/client'

prometheus = Prometheus::Client.registry

tokens_counter = prometheus.counter(
  :openrouter_tokens_total,
  docstring: 'Total tokens processed'
)

cost_counter = prometheus.counter(
  :openrouter_cost_total,
  docstring: 'Total estimated cost'
)

client.on(:after_response) do |response|
  tokens_counter.increment(by: response.total_tokens,
                          labels: { model: response.model })
  cost_counter.increment(by: response.cost_estimate || 0,
                        labels: { model: response.model })
end
```

### Custom Analytics Dashboard
Build real-time analytics:

```ruby
class OpenRouterAnalytics
  def initialize(client)
    @client = client
    @metrics = {}

    setup_callbacks
  end

  private

  def setup_callbacks
    @client.on(:after_response) do |response|
      update_metrics(response)
      broadcast_update(response)
    end

    @client.on(:on_error) do |error|
      track_error(error)
    end
  end

  def update_metrics(response)
    @metrics[:requests] ||= 0
    @metrics[:tokens] ||= 0
    @metrics[:cost] ||= 0

    @metrics[:requests] += 1
    @metrics[:tokens] += response.total_tokens
    @metrics[:cost] += response.cost_estimate || 0
  end

  def broadcast_update(response)
    # Send to WebSocket, EventSource, etc.
    ActionCable.server.broadcast("analytics_channel", {
      type: "response_completed",
      tokens: response.total_tokens,
      cost: response.cost_estimate,
      model: response.model,
      timestamp: Time.now.iso8601
    })
  end
end

# Usage
analytics = OpenRouterAnalytics.new(client)
```

## Best Practices

### 1. Monitoring Setup
- Enable usage tracking in production
- Set up alerts for cost thresholds
- Monitor cache hit rates for optimization opportunities
- Track error rates and response times

### 2. Cost Management
- Set budget alerts using usage tracker
- Monitor per-model costs to optimize model selection
- Track cache effectiveness to reduce costs
- Use fallback models for cost optimization

### 3. Performance Optimization
- Monitor tokens per second for performance
- Track cache hit rates by model
- Use streaming for better perceived performance
- Monitor healing frequency to identify model issues

### 4. Error Handling
- Implement comprehensive error callbacks
- Set up alerting for authentication failures
- Monitor rate limiting and implement backoff
- Track healing failures as quality indicators

The OpenRouter gem's observability features provide everything you need to monitor, optimize, and maintain reliable AI applications at scale.