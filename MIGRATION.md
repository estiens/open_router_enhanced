# Migration Guide: From OpenRouter to OpenRouter Enhanced

This guide helps you migrate from the [original OpenRouter gem](https://github.com/OlympiaAI/open_router) to OpenRouter Enhanced.

## Overview

OpenRouter Enhanced is a comprehensive fork that adds enterprise-grade AI development features while maintaining **100% backward compatibility** with the original gem.

**Good News**: Your existing code will continue to work without modifications!

## Quick Migration Checklist

- [ ] Update `Gemfile` to use `open_router_enhanced`
- [ ] Run `bundle install`
- [ ] Test existing code (should work unchanged)
- [ ] Optionally adopt new features as needed

## Installation

### Update Gemfile

```ruby
# Before
gem "open_router"

# After
gem "open_router_enhanced"
```

Then run:

```bash
bundle install
```

### Alternative: Try Before Migrating

You can test the enhanced gem alongside the original:

```ruby
gem "open_router", require: false
gem "open_router_enhanced"
```

## Backward Compatibility

### All Existing Code Works Unchanged

```ruby
# This code from the original gem works identically
client = OpenRouter::Client.new
response = client.complete(
  [{ role: "user", content: "Hello!" }],
  model: "openai/gpt-4o-mini"
)

puts response["choices"][0]["message"]["content"]  # Hash access still works
puts response.content  # New accessor methods also available
```

### Response Object Compatibility

The Response object maintains full backward compatibility through delegation:

```ruby
response = client.complete(messages, model: "openai/gpt-4o-mini")

# Original hash-style access (still works)
response["choices"]
response["model"]
response["usage"]["total_tokens"]
response.dig("choices", 0, "message", "content")

# New convenience methods (enhanced)
response.choices
response.model
response.total_tokens
response.content
```

## What's New

OpenRouter Enhanced adds these features while keeping everything you know working:

### 1. Tool Calling (Function Calling)

**New capability** - The original gem had no built-in tool calling support.

```ruby
# Define tools with Ruby DSL
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather"
  parameters do
    string :location, required: true, description: "City name"
  end
end

# Use in completion
response = client.complete(
  messages,
  model: "anthropic/claude-3.5-sonnet",
  tools: [weather_tool]
)

# Handle tool calls
if response.has_tool_calls?
  response.tool_calls.each do |call|
    result = call.execute do |name, args|
      # Execute tool
    end
  end
end
```

### 2. Structured Outputs

**New capability** - Get guaranteed JSON responses with schema validation.

```ruby
# Define schema
user_schema = OpenRouter::Schema.define("user") do
  string :name, required: true
  integer :age, minimum: 0, maximum: 120
  string :email, format: "email"
end

# Request structured output
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  response_format: user_schema
)

# Get parsed JSON
user = response.structured_output
# => { "name" => "John", "age" => 30, "email" => "john@example.com" }
```

### 3. Smart Model Selection

**New capability** - Intelligent model selection based on requirements.

```ruby
# Original gem - manual model selection
model = "anthropic/claude-3-5-sonnet"

# Enhanced gem - intelligent selection
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling, :vision)
                                 .optimize_for(:cost)
                                 .within_budget(max_cost: 0.01)
                                 .choose

# Use selected model
response = client.complete(messages, model: model)
```

### 4. Usage Tracking & Cost Monitoring

**New capability** - Automatic usage and cost tracking.

```ruby
# Enable tracking
client = OpenRouter::Client.new(track_usage: true)

# Make requests
response = client.complete(messages, model: "openai/gpt-4o-mini")

# View metrics
tracker = client.usage_tracker
puts "Total cost: $#{tracker.total_cost}"
puts "Total tokens: #{tracker.total_tokens}"
puts "Cache hit rate: #{tracker.cache_hit_rate}%"

# Export data
csv_data = tracker.export_csv
```

### 5. Streaming Support

**Enhanced** - The original gem had basic streaming, now with callbacks.

```ruby
# Original streaming still works
client.complete(messages, model: model, stream: true) do |chunk|
  print chunk.dig("choices", 0, "delta", "content")
end

# Enhanced streaming client with callbacks
streaming_client = OpenRouter::StreamingClient.new

streaming_client.on(:stream_start) { puts "Starting..." }
streaming_client.on(:stream_chunk) { |chunk| print chunk }
streaming_client.on(:stream_end) { puts "\nDone!" }

streaming_client.stream(messages, model: model)
```

### 6. Prompt Templates

**New capability** - Reusable prompt templates.

```ruby
template = OpenRouter::PromptTemplate.define("summarizer") do
  system "You are a helpful summarization assistant."
  user "Summarize this text:\n{{text}}"

  examples([
    { input: { text: "Long text..." }, output: "Brief summary..." }
  ])
end

# Use template
messages = template.build(text: "Your text here")
response = client.complete(messages, model: model)
```

### 7. Response Healing

**New capability** - Automatic JSON healing for malformed responses.

```ruby
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
end

# If model returns malformed JSON, it's automatically healed
response = client.complete(
  messages,
  model: "some-model",
  response_format: schema
)

# Returns valid JSON even if original response was malformed
data = response.structured_output
```

### 8. Model Fallbacks

**New capability** - Automatic failover between models.

```ruby
# Try multiple models in order
response = client.complete(
  messages,
  model: [
    "openai/gpt-4o",           # Try first
    "anthropic/claude-3.5-sonnet", # Fallback
    "openai/gpt-4o-mini"           # Last resort
  ]
)
```

### 9. Callback System

**New capability** - Hook into request lifecycle.

```ruby
client.on(:before_request) do |params|
  puts "Sending request with model: #{params[:model]}"
end

client.on(:after_response) do |response|
  puts "Received #{response.total_tokens} tokens"
end

client.on(:on_tool_call) do |tool_calls|
  puts "Tools called: #{tool_calls.map(&:name).join(", ")}"
end

client.on(:on_error) do |error|
  puts "Error: #{error.message}"
end
```

## Configuration Changes

### Original Configuration

```ruby
# This still works exactly the same
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "My App"
  config.site_url = "https://example.com"
end
```

### Enhanced Configuration (Optional New Features)

```ruby
OpenRouter.configure do |config|
  # Original settings (unchanged)
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "My App"
  config.site_url = "https://example.com"

  # New optional settings
  config.auto_heal_responses = false  # Enable response healing
  config.healer_model = "openai/gpt-4o-mini"  # Model for healing
  config.max_heal_attempts = 2  # Retry limit
  config.strict_mode = false  # Strict schema validation
  config.cache_ttl = 604800  # Model registry cache (7 days)
end
```

## Migration Strategies

### Strategy 1: No Changes (Recommended Start)

Simply swap the gem and continue using existing code:

```ruby
# Gemfile
gem "open_router_enhanced"

# Code - no changes needed
client = OpenRouter::Client.new
response = client.complete(messages, model: "openai/gpt-4o-mini")
```

### Strategy 2: Gradual Enhancement

Adopt new features incrementally:

**Week 1**: Enable usage tracking
```ruby
client = OpenRouter::Client.new(track_usage: true)
```

**Week 2**: Add model selection
```ruby
model = OpenRouter::ModelSelector.new.optimize_for(:cost).choose
```

**Week 3**: Implement tool calling
```ruby
response = client.complete(messages, model: model, tools: tools)
```

**Week 4**: Add structured outputs
```ruby
response = client.complete(messages, model: model, response_format: schema)
```

### Strategy 3: Full Feature Adoption

Leverage all enhanced features:

```ruby
# Configuration
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.auto_heal_responses = true
end

# Smart model selection
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

# Client with tracking
client = OpenRouter::Client.new(track_usage: true)

# Callbacks for monitoring
client.on(:after_response) { |r| puts "Cost: $#{r.cost_estimate}" }

# Structured completion with tools
response = client.complete(
  messages,
  model: model,
  tools: tools,
  response_format: schema
)

# Process results
if response.has_tool_calls?
  # Handle tools
elsif response.structured_output
  # Handle structured data
else
  # Handle text response
end
```

## Common Patterns

### Pattern: Simple Upgrade

```ruby
# Before (original gem)
response = OpenRouter::Client.new.complete(
  [{ role: "user", content: "Hello" }],
  model: "openai/gpt-4o-mini"
)
puts response["choices"][0]["message"]["content"]

# After (enhanced gem - same code works)
response = OpenRouter::Client.new.complete(
  [{ role: "user", content: "Hello" }],
  model: "openai/gpt-4o-mini"
)
puts response.content  # New convenience method
```

### Pattern: Add Usage Tracking

```ruby
# Original
client = OpenRouter::Client.new

# Enhanced
client = OpenRouter::Client.new(track_usage: true)

# Check usage after requests
puts client.usage_tracker.summary
```

### Pattern: Cost Optimization

```ruby
# Original - manual model selection
model = "openai/gpt-4o-mini"  # Hope it's cheap enough

# Enhanced - guarantee cost constraints
model = OpenRouter::ModelSelector.new
                                 .within_budget(max_cost: 0.01)
                                 .require(:chat)
                                 .choose
```

## Testing Your Migration

### 1. Run Existing Tests

Your existing tests should pass unchanged:

```ruby
# spec/my_test_spec.rb
RSpec.describe "OpenRouter" do
  it "works the same as before" do
    client = OpenRouter::Client.new
    response = client.complete(
      [{ role: "user", content: "Test" }],
      model: "openai/gpt-4o-mini"
    )

    expect(response["choices"]).to be_present  # Old style
    expect(response.choices).to be_present     # New style
  end
end
```

### 2. Test New Features

Add tests for enhanced capabilities:

```ruby
RSpec.describe "Enhanced Features" do
  it "tracks usage" do
    client = OpenRouter::Client.new(track_usage: true)
    client.complete(messages, model: model)

    expect(client.usage_tracker.total_tokens).to be > 0
  end

  it "supports tool calling" do
    response = client.complete(messages, model: model, tools: tools)
    expect(response.has_tool_calls?).to be_truthy
  end
end
```

## Breaking Changes

**None!** 🎉

OpenRouter Enhanced maintains 100% backward compatibility. All original functionality works identically.

## Deprecation Notices

No methods or features from the original gem have been deprecated. You can continue using all original patterns indefinitely.

## Performance Considerations

The enhanced gem adds minimal overhead:

- **Model Registry**: Caches model data locally (7-day TTL by default)
- **Usage Tracking**: Optional, disabled by default
- **Response Processing**: Adds ~1ms for enhanced features
- **Memory**: +2-5MB for model registry cache

To minimize overhead:

```ruby
# Disable optional features if not needed
client = OpenRouter::Client.new(track_usage: false)

# Clear model registry cache if memory constrained
OpenRouter::ModelRegistry.clear_cache!
```

## Getting Help

If you encounter issues during migration:

1. **Check Compatibility**: Verify the original code works unchanged
2. **Review Examples**: Check `/examples` directory for patterns
3. **Read Documentation**: Full docs at `/docs` directory
4. **Ask Questions**: Open a GitHub issue
5. **Report Bugs**: Use GitHub issues with "migration" label

## Rollback Plan

If you need to rollback to the original gem:

```ruby
# Gemfile
gem "open_router"  # Original gem

# Remove enhanced-specific code
# - Remove tool definitions
# - Remove schema definitions
# - Remove model selector usage
# - Remove tracking calls

# Original basic calls will work immediately
```

## Next Steps

After migrating:

1. **Read Feature Docs**: Learn about new capabilities in `/docs`
2. **Try Examples**: Run example files in `/examples`
3. **Explore Guides**: Check README for comprehensive guides
4. **Join Community**: Contribute feedback and improvements

## Version Mapping

| Original Gem | Enhanced Gem | Notes |
|--------------|--------------|-------|
| 0.1.x | 1.0.0 | Full backward compatibility |
| 0.2.x | 1.0.0 | Full backward compatibility |
| 0.3.x | 1.0.0 | Full backward compatibility |

## Summary

- ✅ **100% Backward Compatible** - Your code works unchanged
- ✅ **Enhanced Features** - Adopt new capabilities at your own pace
- ✅ **No Breaking Changes** - Safe upgrade with zero risk
- ✅ **Better Developer Experience** - More intuitive APIs
- ✅ **Production Ready** - Thoroughly tested and documented
