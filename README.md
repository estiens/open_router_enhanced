# OpenRouter Enhanced - Ruby Gem

The future will bring us hundreds of language models and dozens of providers for each. How will you choose the best?

The [OpenRouter API](https://openrouter.ai/docs) is a single unified interface for all LLMs! And now you can easily use it with Ruby! 🤖🌌

**OpenRouter Enhanced** is an advanced fork of the [original OpenRouter Ruby gem](https://github.com/OlympiaAI/open_router) by [Obie Fernandez](https://github.com/obie) that adds comprehensive AI application development features including tool calling, structured outputs, intelligent model selection, prompt templates, observability, and automatic response healing—all while maintaining full backward compatibility.

📖 **[Read the story behind OpenRouter Enhanced](https://lowlevelmagic.io/writings/why-i-built-open-router-enhanced/)** - Learn why this gem was built and the philosophy behind its design.

## Enhanced Features

This fork extends the original OpenRouter gem with enterprise-grade AI development capabilities:

### Core AI Features
- **Tool Calling**: Full support for OpenRouter's function calling API with Ruby-idiomatic DSL for tool definitions
- **Structured Outputs**: JSON Schema validation with automatic healing for non-native models and Ruby DSL for schema definitions
- **Smart Model Selection**: Intelligent model selection with fluent DSL for cost optimization, capability requirements, and provider preferences
- **Prompt Templates**: Reusable prompt templates with variable interpolation and few-shot learning support

### Performance & Reliability
- **Model Registry**: Local caching and querying of OpenRouter model data with capability detection
- **Enhanced Response Handling**: Rich Response objects with automatic parsing for tool calls and structured outputs
- **Automatic Healing**: Self-healing responses for malformed JSON from models that don't natively support structured outputs
- **Model Fallbacks**: Automatic failover between models with graceful degradation
- **Streaming Support**: Enhanced streaming client with callback system and response reconstruction

### Observability & Analytics
- **Usage Tracking**: Comprehensive token usage and cost tracking across all API calls
- **Response Analytics**: Detailed metadata including tokens, costs, cache hits, and performance metrics
- **Callback System**: Extensible event system for monitoring requests, responses, and errors
- **Cost Management**: Built-in cost estimation and budget constraints

### Development & Testing
- **Comprehensive Testing**: VCR-based integration tests with real API interactions
- **Debug Support**: Detailed error reporting and validation feedback
- **Configuration Options**: Extensive configuration for healing, validation, and performance tuning
- **Backward Compatible**: All existing code continues to work unchanged

### Core OpenRouter Benefits

- **Prioritize price or performance**: OpenRouter scouts for the lowest prices and best latencies/throughputs across dozens of providers, and lets you choose how to prioritize them.
- **Standardized API**: No need to change your code when switching between models or providers. You can even let users choose and pay for their own.
- **Easy integration**: This Ruby gem provides a simple and intuitive interface to interact with the OpenRouter API, making it effortless to integrate AI capabilities into your Ruby applications.

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Core Features](#core-features)
  - [Basic Completions](#basic-completions)
  - [Model Selection](#model-selection)
- [Enhanced AI Features](#enhanced-ai-features)
  - [Tool Calling](#tool-calling)
  - [Structured Outputs](#structured-outputs)
  - [Smart Model Selection](#smart-model-selection)
  - [Prompt Templates](#prompt-templates)
- [Streaming & Real-time](#streaming--real-time)
  - [Streaming Client](#streaming-client)
  - [Streaming Callbacks](#streaming-callbacks)
- [Observability & Analytics](#observability--analytics)
  - [Usage Tracking](#usage-tracking)
  - [Response Analytics](#response-analytics)
  - [Callback System](#callback-system)
  - [Cost Management](#cost-management)
- [Advanced Features](#advanced-features)
  - [Model Registry](#model-registry)
  - [Model Fallbacks](#model-fallbacks)
  - [Response Healing](#response-healing)
  - [Performance Optimization](#performance-optimization)
- [Testing & Development](#testing--development)
  - [Running Tests](#running-tests)
  - [VCR Testing](#vcr-testing)
  - [Examples](#examples)
- [Troubleshooting](#troubleshooting)
- [API Reference](#api-reference)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Bundler

Add this line to your application's Gemfile:

```ruby
gem "open_router_enhanced"
```

And then execute:

```bash
bundle install
```

### Gem install

Or install it directly:

```bash
gem install open_router_enhanced
```

And require it in your code:

```ruby
require "open_router"
```

## Quick Start

### 1. Get Your API Key
- Sign up at [OpenRouter](https://openrouter.ai)
- Get your API key from [https://openrouter.ai/keys](https://openrouter.ai/keys)

### 2. Basic Setup and Usage

```ruby
require "open_router"

# Configure the gem
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Your App Name"
  config.site_url = "https://yourapp.com"
end

# Create a client
client = OpenRouter::Client.new

# Basic completion
response = client.complete([
  { role: "user", content: "What is the capital of France?" }
])

puts response.content
# => "The capital of France is Paris."
```

### 3. Enhanced Features Quick Example

```ruby
# Smart model selection
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

# Tool calling with structured output
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather"
  parameters do
    string :location, required: true
  end
end

weather_schema = OpenRouter::Schema.define("weather") do
  string :location, required: true
  number :temperature, required: true
  string :conditions, required: true
end

response = client.complete(
  [{ role: "user", content: "What's the weather in Tokyo?" }],
  model: model,
  tools: [weather_tool],
  response_format: weather_schema
)

# Process results
if response.has_tool_calls?
  weather_data = response.structured_output
  puts "Temperature in #{weather_data['location']}: #{weather_data['temperature']}°"
end
```

## Configuration

### Global Configuration

Configure the gem globally, for example in an `open_router.rb` initializer file. Never hardcode secrets into your codebase - instead use `Rails.application.credentials` or something like [dotenv](https://github.com/motdotla/dotenv) to pass the keys safely into your environments.

```ruby
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Your App Name"
  config.site_url = "https://yourapp.com"
  
  # Optional: Configure response healing for non-native structured output models
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2
  
  # Optional: Configure strict mode for capability validation
  config.strict_mode = true
  
  # Optional: Configure automatic forcing for unsupported models
  config.auto_force_on_unsupported_models = true
end
```

### Per-Client Configuration

You can also configure clients individually:

```ruby
client = OpenRouter::Client.new(
  access_token: ENV["OPENROUTER_API_KEY"],
  request_timeout: 120
)
```

### Faraday Configuration

The configuration object exposes a [`faraday`](https://github.com/lostisland/faraday-retry) method that you can pass a block to configure Faraday settings and middleware.

This example adds `faraday-retry` and a logger that redacts the api key so it doesn't get leaked to logs.

```ruby
require 'faraday/retry'

retry_options = {
  max: 2,
  interval: 0.05,
  interval_randomness: 0.5,
  backoff_factor: 2
}

OpenRouter::Client.new(access_token: ENV["ACCESS_TOKEN"]) do |config|
  config.faraday do |f|
    f.request :retry, retry_options
    f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true, errors: true } do |logger|
      logger.filter(/(Bearer) (\S+)/, '\1[REDACTED]')
    end
  end
end
```

#### Change version or timeout

The default timeout for any request using this library is 120 seconds. You can change that by passing a number of seconds to the `request_timeout` when initializing the client.

```ruby
client = OpenRouter::Client.new(
    access_token: "access_token_goes_here",
    request_timeout: 240 # Optional
)
```

## Core Features

### Basic Completions

Hit the OpenRouter API for a completion:

```ruby
messages = [
  { role: "system", content: "You are a helpful assistant." },
  { role: "user", content: "What is the color of the sky?" }
]

response = client.complete(messages)
puts response.content
# => "The sky is typically blue during the day due to a phenomenon called Rayleigh scattering. Sunlight..."
```

### Model Selection

Pass an array to the `model` parameter to enable [explicit model routing](https://openrouter.ai/docs#model-routing).

```ruby
OpenRouter::Client.new.complete(
  [
    { role: "system", content: SYSTEM_PROMPT },
    { role: "user", content: "Provide analysis of the data formatted as JSON:" }
  ],
  model: [
    "mistralai/mixtral-8x7b-instruct:nitro",
    "mistralai/mixtral-8x7b-instruct"
  ],
  extras: {
    response_format: {
      type: "json_object"
    }
  }
)
```

[Browse full list of models available](https://openrouter.ai/models) or fetch from the OpenRouter API:

```ruby
models = client.models
puts models
# => [{"id"=>"openrouter/auto", "object"=>"model", "created"=>1684195200, "owned_by"=>"openrouter", "permission"=>[], "root"=>"openrouter", "parent"=>nil}, ...]
```

### Generation Stats

Query the generation stats for a given generation ID:

```ruby
generation_id = "generation-abcdefg"
stats = client.query_generation_stats(generation_id)
puts stats
# => {"id"=>"generation-abcdefg", "object"=>"generation", "created"=>1684195200, "model"=>"openrouter/auto", "usage"=>{"prompt_tokens"=>10, "completion_tokens"=>50, "total_tokens"=>60}, "cost"=>0.0006}
```

## Enhanced AI Features

### Tool Calling

Enable AI models to call functions and interact with external APIs using OpenRouter's function calling with an intuitive Ruby DSL.

#### Quick Example

```ruby
# Define a tool using the DSL
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"
  
  parameters do
    string :location, required: true, description: "City name"
    string :units, enum: ["celsius", "fahrenheit"], default: "celsius"
  end
end

# Use in completion
response = client.complete(
  [{ role: "user", content: "What's the weather in London?" }],
  model: "anthropic/claude-3.5-sonnet",
  tools: [weather_tool],
  tool_choice: "auto"
)

# Handle tool calls
if response.has_tool_calls?
  response.tool_calls.each do |tool_call|
    result = fetch_weather(tool_call.arguments["location"], tool_call.arguments["units"])
    puts "Weather in #{tool_call.arguments['location']}: #{result}"
  end
end
```

#### Key Features

- **Ruby DSL**: Define tools with intuitive Ruby syntax
- **Parameter Validation**: Automatic validation against JSON Schema
- **Tool Choice Control**: Auto, required, none, or specific tool selection
- **Conversation Continuation**: Easy message building for multi-turn conversations
- **Error Handling**: Graceful error handling and validation

📖 **[Complete Tool Calling Documentation](docs/tools.md)**

### Structured Outputs

Get JSON responses that conform to specific schemas with automatic validation and healing for non-native models.

#### Quick Example

```ruby
# Define a schema using the DSL
user_schema = OpenRouter::Schema.define("user") do
  string :name, required: true, description: "Full name"
  integer :age, required: true, minimum: 0, maximum: 150
  string :email, required: true, description: "Email address"
  boolean :premium, description: "Premium account status"
end

# Get structured response
response = client.complete(
  [{ role: "user", content: "Create a user: John Doe, 30, john@example.com" }],
  model: "openai/gpt-4o",
  response_format: user_schema
)

# Access parsed JSON data
user = response.structured_output
puts user["name"]    # => "John Doe"
puts user["age"]     # => 30
puts user["email"]   # => "john@example.com"
```

#### Key Features

- **Ruby DSL**: Define JSON schemas with Ruby syntax
- **Automatic Healing**: Self-healing for models without native structured output support
- **Validation**: Optional validation with detailed error reporting
- **Complex Schemas**: Support for nested objects, arrays, and advanced constraints
- **Fallback Support**: Graceful degradation for unsupported models

📖 **[Complete Structured Outputs Documentation](docs/structured_outputs.md)**

### Smart Model Selection

Automatically choose the best AI model based on your specific requirements using a fluent DSL.

#### Quick Example

```ruby
# Find the cheapest model with function calling
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

# Advanced selection with multiple criteria
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling, :vision)
                                 .within_budget(max_cost: 0.01)
                                 .min_context(50_000)
                                 .prefer_providers("anthropic", "openai")
                                 .optimize_for(:performance)
                                 .choose

# Get multiple options with fallbacks
models = OpenRouter::ModelSelector.new
                                  .require(:structured_outputs)
                                  .choose_with_fallbacks(limit: 3)
# => ["openai/gpt-4o-mini", "anthropic/claude-3-haiku", "google/gemini-flash"]
```

#### Key Features

- **Fluent DSL**: Chain requirements and preferences intuitively
- **Cost Optimization**: Find models within budget constraints
- **Capability Matching**: Require specific features like function calling or vision
- **Provider Preferences**: Prefer or avoid specific providers
- **Graceful Fallbacks**: Automatic fallback with requirement relaxation
- **Performance Tiers**: Choose between cost and performance optimization

📖 **[Complete Model Selection Documentation](docs/model_selection.md)**

### Prompt Templates

Create reusable, parameterized prompts with variable interpolation and few-shot learning support.

#### Quick Example

```ruby
# Basic template with variables
translation_template = OpenRouter::PromptTemplate.new(
  template: "Translate '{text}' from {source_lang} to {target_lang}",
  input_variables: [:text, :source_lang, :target_lang]
)

# Use with client
client = OpenRouter::Client.new
response = client.complete(
  translation_template.to_messages(
    text: "Hello world",
    source_lang: "English",
    target_lang: "French"
  ),
  model: "openai/gpt-4o-mini"
)

# Few-shot learning template
classification_template = OpenRouter::PromptTemplate.new(
  prefix: "Classify the sentiment of the following text. Examples:",
  suffix: "Now classify: {text}",
  examples: [
    { text: "I love this product!", sentiment: "positive" },
    { text: "This is terrible.", sentiment: "negative" },
    { text: "It's okay, nothing special.", sentiment: "neutral" }
  ],
  example_template: "Text: {text}\nSentiment: {sentiment}",
  input_variables: [:text]
)

# Render complete prompt
prompt = classification_template.format(text: "This is amazing!")
puts prompt
# =>
# Classify the sentiment of the following text. Examples:
#
# Text: I love this product!
# Sentiment: positive
#
# Text: This is terrible.
# Sentiment: negative
#
# Text: It's okay, nothing special.
# Sentiment: neutral
#
# Now classify: This is amazing!
```

#### Key Features

- **Variable Interpolation**: Use `{variable}` syntax for dynamic content
- **Few-Shot Learning**: Include examples to improve model performance
- **Chat Formatting**: Automatic conversion to OpenRouter message format
- **Partial Variables**: Pre-fill common variables for reuse
- **Template Composition**: Combine templates for complex prompts
- **Validation**: Automatic validation of required input variables

📖 **[Complete Prompt Templates Documentation](docs/prompt_templates.md)**

### Model Registry

Access detailed information about available models and their capabilities.

#### Quick Example

```ruby
# Get specific model information
model_info = OpenRouter::ModelRegistry.get_model_info("anthropic/claude-3-5-sonnet")
puts model_info[:capabilities]  # [:chat, :function_calling, :structured_outputs, :vision]
puts model_info[:cost_per_1k_tokens]  # { input: 0.003, output: 0.015 }

# Find models matching requirements
candidates = OpenRouter::ModelRegistry.models_meeting_requirements(
  capabilities: [:function_calling],
  max_input_cost: 0.01
)

# Estimate costs for specific usage
cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
  "openai/gpt-4o",
  input_tokens: 1000,
  output_tokens: 500
)
puts "Estimated cost: $#{cost.round(4)}"  # => "Estimated cost: $0.0105"
```

#### Key Features

- **Model Discovery**: Browse all available models and their specifications
- **Capability Detection**: Check which features each model supports
- **Cost Calculation**: Estimate costs for specific token usage
- **Local Caching**: Fast model data access with automatic cache management
- **Real-time Updates**: Refresh model data from OpenRouter API

## Streaming & Real-time

### Streaming Client

The enhanced streaming client provides real-time response streaming with callback support and automatic response reconstruction.

#### Quick Example

```ruby
# Create streaming client
streaming_client = OpenRouter::StreamingClient.new

# Set up callbacks
streaming_client
  .on_stream(:on_start) { |data| puts "Starting request to #{data[:model]}" }
  .on_stream(:on_chunk) { |chunk| print chunk.content }
  .on_stream(:on_tool_call_chunk) { |chunk| puts "Tool call: #{chunk.name}" }
  .on_stream(:on_finish) { |response| puts "\nCompleted. Total tokens: #{response.total_tokens}" }
  .on_stream(:on_error) { |error| puts "Error: #{error.message}" }

# Stream with automatic response accumulation
response = streaming_client.stream_complete(
  [{ role: "user", content: "Write a short story about a robot" }],
  model: "openai/gpt-4o-mini",
  accumulate_response: true
)

# Access complete response after streaming
puts "Final response: #{response.content}"
puts "Cost: $#{response.cost_estimate}"
```

#### Streaming with Tool Calls

```ruby
# Define a tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather"
  parameters { string :location, required: true }
end

# Stream with tool calling
streaming_client.stream_complete(
  [{ role: "user", content: "What's the weather in Tokyo?" }],
  model: "anthropic/claude-3-5-sonnet",
  tools: [weather_tool]
) do |chunk|
  if chunk.has_tool_calls?
    chunk.tool_calls.each do |tool_call|
      puts "Calling #{tool_call.name} with #{tool_call.arguments}"
    end
  else
    print chunk.content
  end
end
```

### Streaming Callbacks

The streaming client supports extensive callback events for monitoring and analytics.

```ruby
streaming_client = OpenRouter::StreamingClient.new

# Monitor token usage in real-time
streaming_client.on_stream(:on_chunk) do |chunk|
  if chunk.usage
    puts "Tokens so far: #{chunk.usage['total_tokens']}"
  end
end

# Handle errors gracefully
streaming_client.on_stream(:on_error) do |error|
  logger.error "Streaming failed: #{error.message}"
  # Implement fallback logic
  fallback_response = client.complete(messages, model: "openai/gpt-4o-mini")
end

# Track performance metrics
start_time = nil
streaming_client
  .on_stream(:on_start) { |data| start_time = Time.now }
  .on_stream(:on_finish) do |response|
    duration = Time.now - start_time
    puts "Request completed in #{duration.round(2)}s"
    puts "Tokens per second: #{response.total_tokens / duration}"
  end
```

## Observability & Analytics

### Usage Tracking

Track token usage, costs, and performance metrics across all API calls.

#### Quick Example

```ruby
# Create client with usage tracking enabled
client = OpenRouter::Client.new(track_usage: true)

# Make multiple requests
3.times do |i|
  response = client.complete(
    [{ role: "user", content: "Tell me a fact about space #{i + 1}" }],
    model: "openai/gpt-4o-mini"
  )
  puts "Request #{i + 1}: #{response.total_tokens} tokens, $#{response.cost_estimate}"
end

# View comprehensive usage statistics
tracker = client.usage_tracker
puts "\n=== Usage Summary ==="
puts "Total requests: #{tracker.request_count}"
puts "Total tokens: #{tracker.total_tokens}"
puts "Total cost: $#{tracker.total_cost.round(4)}"
puts "Average cost per request: $#{(tracker.total_cost / tracker.request_count).round(4)}"

# View per-model breakdown
tracker.model_usage.each do |model, stats|
  puts "\n#{model}:"
  puts "  Requests: #{stats[:request_count]}"
  puts "  Tokens: #{stats[:total_tokens]}"
  puts "  Cost: $#{stats[:cost].round(4)}"
end

# Print detailed report
tracker.print_summary
```

#### Advanced Usage Tracking

```ruby
# Track specific operations
client.usage_tracker.reset! # Start fresh

# Simulate different workload types
client.complete(messages, model: "openai/gpt-4o")  # Expensive, high-quality
client.complete(messages, model: "openai/gpt-4o-mini")  # Cheap, fast

# Get usage metrics
cache_hit_rate = client.usage_tracker.cache_hit_rate
tokens_per_second = client.usage_tracker.tokens_per_second

puts "Cache hit rate: #{cache_hit_rate}%"
puts "Tokens per second: #{tokens_per_second}"

# Export usage data as CSV for analysis
csv_data = client.usage_tracker.export_csv
File.write("usage_report.csv", csv_data)
```

### Response Analytics

Every response includes comprehensive metadata for monitoring and optimization.

```ruby
response = client.complete(messages, model: "anthropic/claude-3-5-sonnet")

# Token metrics
puts "Input tokens: #{response.prompt_tokens}"
puts "Output tokens: #{response.completion_tokens}"
puts "Cached tokens: #{response.cached_tokens}"
puts "Total tokens: #{response.total_tokens}"

# Cost information (requires generation stats query)
puts "Total cost: $#{response.cost_estimate}"

# Model information
puts "Provider: #{response.provider}"
puts "Model: #{response.model}"
puts "System fingerprint: #{response.system_fingerprint}"
puts "Finish reason: #{response.finish_reason}"
```

### Callback System

The client provides an extensible callback system for monitoring requests, responses, and errors.

#### Basic Callbacks

```ruby
client = OpenRouter::Client.new

# Monitor all requests
client.on(:before_request) do |params|
  puts "Making request to #{params[:model]} with #{params[:messages].size} messages"
end

# Monitor all responses
client.on(:after_response) do |response|
  puts "Received response: #{response.total_tokens} tokens, $#{response.cost_estimate}"
end

# Monitor tool calls
client.on(:on_tool_call) do |tool_calls|
  tool_calls.each do |call|
    puts "Tool called: #{call.name} with args #{call.arguments}"
  end
end

# Monitor errors
client.on(:on_error) do |error|
  logger.error "API error: #{error.message}"
  # Send to monitoring service
  ErrorReporter.notify(error)
end
```

#### Advanced Callback Usage

```ruby
# Cost monitoring with alerts
client.on(:after_response) do |response|
  if response.cost_estimate > 0.10
    AlertService.send_alert(
      "High cost request: $#{response.cost_estimate} for #{response.total_tokens} tokens"
    )
  end
end

# Performance monitoring
client.on(:before_request) { |params| @start_time = Time.now }
client.on(:after_response) do |response|
  duration = Time.now - @start_time
  if duration > 10.0
    puts "Slow request detected: #{duration.round(2)}s"
  end
end

# Usage analytics
request_count = 0
total_cost = 0.0

client.on(:after_response) do |response|
  request_count += 1
  total_cost += response.cost_estimate || 0.0

  if request_count % 100 == 0
    puts "100 requests processed. Average cost: $#{(total_cost / request_count).round(4)}"
  end
end

# Chain callbacks for complex workflows
client
  .on(:before_request) { |params| log_request(params) }
  .on(:after_response) { |response| log_response(response) }
  .on(:on_tool_call) { |calls| execute_tools(calls) }
  .on(:on_error) { |error| handle_error(error) }
```

### Cost Management

Built-in cost estimation and usage tracking tools.

```ruby
# Pre-flight cost estimation
estimated_cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
  "anthropic/claude-3-5-sonnet",
  input_tokens: 1500,
  output_tokens: 800
)

puts "Estimated cost: $#{estimated_cost}"

# Use model selector to stay within budget
if estimated_cost > 0.01
  puts "Switching to cheaper model"
  model = OpenRouter::ModelSelector.new
                                   .within_budget(max_cost: 0.01)
                                   .require(:chat)
                                   .choose
end

# Track costs in real-time
client = OpenRouter::Client.new(track_usage: true)

client.on(:after_response) do |response|
  total_spent = client.usage_tracker.total_cost
  puts "Total spent this session: $#{total_spent.round(4)}"

  if total_spent > 5.00
    puts "⚠️  Session cost exceeds $5.00"
  end
end
```

## Advanced Features

### Model Fallbacks

Use multiple models with automatic failover for increased reliability.

```ruby
# Define fallback chain
response = client.complete(
  messages,
  model: ["openai/gpt-4o", "anthropic/claude-3-5-sonnet", "anthropic/claude-3-haiku"],
  tools: tools
)

# Or use ModelSelector for intelligent fallbacks
models = OpenRouter::ModelSelector.new
                                  .require(:function_calling)
                                  .choose_with_fallbacks(limit: 3)

response = client.complete(messages, model: models, tools: tools)
```

### Response Healing

Automatically heal malformed responses from models that don't natively support structured outputs.

```ruby
# Configure global healing
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2
end

# The gem automatically heals malformed JSON responses
response = client.complete(
  messages,
  model: "some/model-without-native-structured-outputs",
  response_format: schema  # Will be automatically healed if malformed
)
```

### Performance Optimization

Optimize performance for high-throughput applications.

#### Batching and Parallelization

```ruby
require 'concurrent-ruby'

# Process multiple requests in parallel
messages_batch = [
  [{ role: "user", content: "Summarize this: #{text1}" }],
  [{ role: "user", content: "Summarize this: #{text2}" }],
  [{ role: "user", content: "Summarize this: #{text3}" }]
]

# Create thread pool
thread_pool = Concurrent::FixedThreadPool.new(5)

# Process batch with shared model selection
model = OpenRouter::ModelSelector.new
                                 .optimize_for(:performance)
                                 .require(:chat)
                                 .choose

futures = messages_batch.map do |messages|
  Concurrent::Future.execute(executor: thread_pool) do
    client.complete(messages, model: model)
  end
end

# Collect results
results = futures.map(&:value)
thread_pool.shutdown
```

#### Caching and Optimization

```ruby
# Enable aggressive caching
OpenRouter.configure do |config|
  config.cache_ttl = 24 * 60 * 60  # 24 hours
  config.auto_heal_responses = true
  config.strict_mode = false  # Better performance
end

# Use cheaper models for development/testing
if Rails.env.development?
  client = OpenRouter::Client.new(
    default_model: "openai/gpt-4o-mini",  # Cheaper for development
    track_usage: true
  )
else
  client = OpenRouter::Client.new(
    default_model: "anthropic/claude-3-5-sonnet"  # Production quality
  )
end

# Pre-warm model registry cache
OpenRouter::ModelRegistry.refresh_cache!

# Optimize for specific workloads
fast_client = OpenRouter::Client.new(
  request_timeout: 30,  # Shorter timeout
  auto_heal_responses: false,  # Skip healing for speed
  strict_mode: false  # Skip capability validation
)
```

#### Memory Management

```ruby
# Reset usage tracking periodically for long-running apps
client.usage_tracker.reset! if client.usage_tracker.request_count > 1000

# Clear callback chains when not needed
client.clear_callbacks(:after_response) if Rails.env.production?

# Use streaming for large responses to reduce memory usage
streaming_client = OpenRouter::StreamingClient.new

streaming_client.stream_complete(
  [{ role: "user", content: "Write a detailed report on AI trends" }],
  model: "anthropic/claude-3-5-sonnet",
  accumulate_response: false  # Don't store full response
) do |chunk|
  # Process chunk immediately and discard
  process_chunk(chunk.content)
end
```

## Testing & Development

The gem includes comprehensive test coverage with VCR integration for real API testing.

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation

# Run specific test types
bundle exec rspec spec/unit/           # Unit tests only
bundle exec rspec spec/vcr/            # VCR integration tests (requires API key)
```

### VCR Testing

The project includes VCR tests that record real API interactions:

```bash
# Set API key for VCR tests
export OPENROUTER_API_KEY="your_api_key"

# Run VCR tests
bundle exec rspec spec/vcr/

# Re-record cassettes (deletes old recordings)
rm -rf spec/fixtures/vcr_cassettes/
bundle exec rspec spec/vcr/
```

### Examples

The project includes comprehensive examples for all features:

```bash
# Set your API key
export OPENROUTER_API_KEY="your_key_here"

# Run individual examples
ruby -I lib examples/basic_completion.rb
ruby -I lib examples/tool_calling_example.rb
ruby -I lib examples/structured_outputs_example.rb
ruby -I lib examples/model_selection_example.rb
ruby -I lib examples/prompt_template_example.rb
ruby -I lib examples/streaming_example.rb
ruby -I lib examples/observability_example.rb
ruby -I lib examples/smart_completion_example.rb

# Run all examples
find examples -name "*.rb" -exec ruby -I lib {} \;
```

### Model Exploration Rake Tasks

The gem includes convenient rake tasks for exploring and searching available models without writing code:

#### Model Summary

View an overview of all available models, including provider breakdown, capabilities, costs, and context lengths:

```bash
bundle exec rake models:summary
```

Output includes:
- Total model count and breakdown by provider
- Available capabilities across all models
- Cost analysis (min/max/median for input and output tokens)
- Context length statistics
- Performance tier distribution

#### Model Search

Search for models using various filters and optimization strategies:

```bash
# Basic search by provider
bundle exec rake models:search provider=anthropic

# Search by capabilities
bundle exec rake models:search capability=function_calling,vision

# Optimize for cost with capability requirements
bundle exec rake models:search capability=function_calling optimize=cost limit=10

# Filter by context length
bundle exec rake models:search min_context=200000

# Filter by cost
bundle exec rake models:search max_cost=0.01

# Filter by release date
bundle exec rake models:search newer_than=2024-01-01

# Combine multiple filters
bundle exec rake models:search provider=anthropic capability=function_calling min_context=100000 optimize=cost limit=5
```

Available search parameters:
- `provider=name` - Filter by provider (comma-separated for multiple)
- `capability=cap1,cap2` - Required capabilities (function_calling, vision, structured_outputs, etc.)
- `optimize=strategy` - Optimization strategy (cost, performance, latest, context)
- `min_context=tokens` - Minimum context length
- `max_cost=amount` - Maximum input cost per 1k tokens
- `max_output_cost=amount` - Maximum output cost per 1k tokens
- `newer_than=YYYY-MM-DD` - Filter models released after date
- `limit=N` - Maximum number of results to show (default: 20)
- `fallbacks=true` - Show models with fallback support

Examples:

```bash
# Find cheapest models with vision support
bundle exec rake models:search capability=vision optimize=cost limit=5

# Find latest Anthropic models with function calling
bundle exec rake models:search provider=anthropic optimize=latest capability=function_calling

# Find high-context models for long documents
bundle exec rake models:search min_context=500000 optimize=context
```

## Troubleshooting

### Common Issues and Solutions

#### Authentication Errors

```ruby
# Error: "OpenRouter access token missing!"
# Solution: Set your API key
export OPENROUTER_API_KEY="your_key_here"

# Or configure in code
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
end

# Error: "Invalid API key"
# Solution: Verify your key at https://openrouter.ai/keys
```

#### Model Selection Issues

```ruby
# Error: "Model not found or access denied"
# Solution: Check model availability and your account limits
begin
  client.complete(messages, model: "gpt-4")
rescue OpenRouter::ServerError => e
  if e.message.include?("not found")
    puts "Model not available, falling back to default"
    client.complete(messages, model: "openai/gpt-4o-mini")
  end
end

# Error: "Model doesn't support feature X"
# Solution: Use ModelSelector to find compatible models
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .choose
```

#### Rate Limiting and Costs

```ruby
# Error: "Rate limit exceeded"
# Solution: Implement exponential backoff
require 'retries'

with_retries(max_tries: 3, base_sleep_seconds: 1, max_sleep_seconds: 60) do |attempt|
  client.complete(messages, model: model)
end

# Error: "Request too expensive"
# Solution: Use cheaper models or budget constraints
client = OpenRouter::Client.new
model = OpenRouter::ModelSelector.new
                                 .within_budget(max_cost: 0.01)
                                 .choose
```

#### Structured Output Issues

```ruby
# Error: "Invalid JSON response"
# Solution: Enable response healing
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
end

# Error: "Schema validation failed"
# Solution: Check schema definitions and model capability
schema = OpenRouter::Schema.define("user") do
  string :name, required: true
  integer :age, minimum: 0  # Add constraints
end

# Use models that support structured outputs natively
model = OpenRouter::ModelSelector.new
                                 .require(:structured_outputs)
                                 .choose
```

#### Performance Issues

```ruby
# Issue: Slow responses
# Solution: Optimize client configuration
client = OpenRouter::Client.new(
  request_timeout: 30,  # Lower timeout
  strict_mode: false,   # Skip capability validation
  auto_heal_responses: false  # Skip healing for speed
)

# Issue: High memory usage
# Solution: Use streaming for large responses
streaming_client = OpenRouter::StreamingClient.new
streaming_client.stream_complete(messages, accumulate_response: false) do |chunk|
  process_chunk_immediately(chunk)
end

# Issue: Too many API calls
# Solution: Implement request batching
messages_batch = [...] # Multiple message sets
results = process_batch_concurrently(messages_batch, thread_pool_size: 5)
```

#### Tool Calling Issues

```ruby
# Error: "Tool not found"
# Solution: Verify tool definitions match exactly
tool = OpenRouter::Tool.define do
  name "get_weather"  # Must match exactly in model response
  description "Get current weather for a location"
  parameters do
    string :location, required: true
  end
end

# Error: "Invalid tool parameters"
# Solution: Add parameter validation
def handle_weather_tool(tool_call)
  location = tool_call.arguments["location"]
  raise ArgumentError, "Location required" if location.nil? || location.empty?

  get_weather_data(location)
end
```

### Debug Mode

Enable detailed logging for troubleshooting:

```ruby
require 'logger'

OpenRouter.configure do |config|
  config.log_errors = true
  config.faraday do |f|
    f.response :logger, Logger.new($stdout), { headers: true, bodies: true, errors: true }
  end
end

# Enable callback debugging
client = OpenRouter::Client.new
client.on(:before_request) { |params| puts "REQUEST: #{params.inspect}" }
client.on(:after_response) { |response| puts "RESPONSE: #{response.inspect}" }
client.on(:on_error) { |error| puts "ERROR: #{error.message}" }
```

### Performance Monitoring

```ruby
# Monitor request performance
client.on(:before_request) { @start_time = Time.now }
client.on(:after_response) do |response|
  duration = Time.now - @start_time
  if duration > 5.0
    puts "SLOW REQUEST: #{duration.round(2)}s for #{response.total_tokens} tokens"
  end
end

# Monitor costs
client.on(:after_response) do |response|
  if response.cost_estimate > 0.10
    puts "EXPENSIVE REQUEST: $#{response.cost_estimate}"
  end
end

# Export usage data as CSV for analysis
csv_data = client.usage_tracker.export_csv
File.write("debug_usage.csv", csv_data)
```

### Getting Help

1. **Check the documentation**: Each feature has detailed documentation in the `docs/` directory
2. **Review examples**: Look at working examples in the `examples/` directory
3. **Enable debug mode**: Turn on logging to see request/response details
4. **Check OpenRouter status**: Visit [OpenRouter Status](https://status.openrouter.ai)
5. **Open an issue**: Report bugs at [GitHub Issues](https://github.com/estiens/open_router_enhanced/issues)

## API Reference

### Client Classes

#### OpenRouter::Client

Main client for OpenRouter API interactions.

```ruby
client = OpenRouter::Client.new(
  access_token: "...",
  track_usage: false,
  request_timeout: 120
)

# Core methods
client.complete(messages, **options)  # Chat completions with full feature support
client.models                         # List available models
client.query_generation_stats(id)     # Query generation statistics

# Callback methods
client.on(event, &block)              # Register event callback
client.clear_callbacks(event)         # Clear callbacks for event
client.trigger_callbacks(event, data) # Manually trigger callbacks

# Usage tracking
client.usage_tracker                  # Access usage tracker instance
```

#### OpenRouter::StreamingClient

Enhanced streaming client with callback support.

```ruby
streaming_client = OpenRouter::StreamingClient.new

# Streaming methods
streaming_client.stream_complete(messages, **options)  # Stream with callbacks
streaming_client.on_stream(event, &block)              # Register streaming callbacks

# Available streaming events: :on_start, :on_chunk, :on_tool_call_chunk, :on_finish, :on_error
```

### Enhanced Classes

#### OpenRouter::Tool

Define and manage function calling tools.

```ruby
# DSL definition
tool = OpenRouter::Tool.define do
  name "function_name"
  description "Function description"
  parameters do
    string :param1, required: true, description: "Parameter description"
    integer :param2, minimum: 0, maximum: 100
    boolean :param3, default: false
  end
end

# Hash definition
tool = OpenRouter::Tool.from_hash({
  name: "function_name",
  description: "Function description",
  parameters: {
    type: "object",
    properties: { ... }
  }
})

# Methods
tool.name                    # Get tool name
tool.description             # Get tool description
tool.parameters              # Get parameters schema
tool.to_h                    # Convert to hash format
tool.validate_arguments(args) # Validate arguments against schema
```

#### OpenRouter::Schema

Define JSON schemas for structured outputs.

```ruby
# DSL definition
schema = OpenRouter::Schema.define("schema_name") do
  string :name, required: true, description: "User's name"
  integer :age, minimum: 0, maximum: 150
  boolean :active, default: true
  array :tags, items: { type: "string" }
  object :address do
    string :street, required: true
    string :city, required: true
    string :country, default: "US"
  end
end

# Hash definition
schema = OpenRouter::Schema.from_hash("schema_name", {
  type: "object",
  properties: { ... },
  required: [...]
})

# Methods
schema.name                   # Get schema name
schema.schema                 # Get JSON schema hash
schema.validate(data)         # Validate data against schema
schema.to_h                   # Convert to hash format
```

#### OpenRouter::PromptTemplate

Create reusable prompt templates with variable interpolation.

```ruby
# Basic template
template = OpenRouter::PromptTemplate.new(
  template: "Translate '{text}' from {source} to {target}",
  input_variables: [:text, :source, :target]
)

# Few-shot template
template = OpenRouter::PromptTemplate.new(
  prefix: "Classification examples:",
  suffix: "Classify: {input}",
  examples: [{ input: "...", output: "..." }],
  example_template: "Input: {input}\nOutput: {output}",
  input_variables: [:input]
)

# Methods
template.format(**variables)        # Format template with variables
template.to_messages(**variables)   # Convert to OpenRouter message format
template.input_variables           # Get required input variables
template.partial(**variables)       # Create partial template with some variables filled
```

#### OpenRouter::ModelSelector

Intelligent model selection with fluent DSL.

```ruby
selector = OpenRouter::ModelSelector.new

# Requirement methods
selector.require(*capabilities)             # Require specific capabilities
selector.within_budget(max_cost: 0.01)     # Set maximum cost constraint
selector.min_context(tokens)               # Minimum context length
selector.prefer_providers(*providers)      # Prefer specific providers
selector.avoid_providers(*providers)       # Avoid specific providers
selector.optimize_for(strategy)            # Optimization strategy (:cost, :performance, :balanced)

# Selection methods
selector.choose                            # Choose best single model
selector.choose_with_fallbacks(limit: 3)  # Choose multiple models for fallback
selector.candidates                        # Get all matching models
selector.explain_choice                    # Get explanation of selection

# Available capabilities: :chat, :function_calling, :structured_outputs, :vision, :code_generation
# Available strategies: :cost, :performance, :balanced
```

#### OpenRouter::ModelRegistry

Model information and capability detection.

```ruby
# Class methods
OpenRouter::ModelRegistry.all_models                          # Get all cached models
OpenRouter::ModelRegistry.get_model_info(model)              # Get specific model info
OpenRouter::ModelRegistry.models_meeting_requirements(...)    # Find models matching criteria
OpenRouter::ModelRegistry.calculate_estimated_cost(model, tokens) # Estimate cost
OpenRouter::ModelRegistry.refresh_cache!                     # Refresh model cache
OpenRouter::ModelRegistry.cache_status                       # Get cache status
```

#### OpenRouter::UsageTracker

Track token usage, costs, and performance metrics.

```ruby
tracker = client.usage_tracker

# Metrics
tracker.total_tokens              # Total tokens used
tracker.total_cost               # Total estimated cost
tracker.request_count            # Number of requests made
tracker.model_usage              # Per-model usage breakdown
tracker.session_duration         # Time since tracking started

# Analysis methods
tracker.cache_hit_rate          # Cache hit rate percentage
tracker.tokens_per_second       # Tokens processed per second
tracker.print_summary           # Print detailed usage report
tracker.export_csv              # Export usage data as CSV
tracker.summary                 # Get usage summary hash
tracker.reset!                  # Reset all counters
```

### Response Objects

#### OpenRouter::Response

Enhanced response wrapper with metadata and feature support.

```ruby
response = client.complete(messages)

# Content access
response.content                    # Response content
response.structured_output         # Parsed JSON for structured outputs

# Tool calling
response.has_tool_calls?          # Check if response has tool calls
response.tool_calls               # Array of ToolCall objects

# Token metrics
response.prompt_tokens            # Input tokens
response.completion_tokens        # Output tokens
response.cached_tokens           # Cached tokens
response.total_tokens            # Total tokens

# Cost information
response.input_cost              # Input cost
response.output_cost             # Output cost
response.cost_estimate           # Total estimated cost

# Performance metrics
response.response_time           # Response time in milliseconds
response.tokens_per_second       # Processing speed

# Model information
response.model                   # Model used
response.provider               # Provider name
response.system_fingerprint     # System fingerprint
response.finish_reason          # Why generation stopped

# Cache information
response.cache_hit?             # Whether response used cache
response.cache_efficiency       # Cache efficiency percentage

# Backward compatibility - delegates hash methods to raw response
response["key"]                 # Hash-style access
response.dig("path", "to", "value") # Deep hash access
```

#### OpenRouter::ToolCall

Individual tool call handling and execution.

```ruby
tool_call = response.tool_calls.first

# Properties
tool_call.id                    # Tool call ID
tool_call.name                  # Tool name
tool_call.arguments             # Tool arguments (Hash)

# Methods
tool_call.validate_arguments!   # Validate arguments against tool schema
tool_call.to_message           # Convert to continuation message format
tool_call.execute(&block)      # Execute tool with block
```

### Error Classes

```ruby
OpenRouter::Error                    # Base error class
OpenRouter::ConfigurationError       # Configuration issues
OpenRouter::CapabilityError         # Capability validation errors
OpenRouter::ServerError             # API server errors
OpenRouter::ToolCallError           # Tool execution errors
OpenRouter::SchemaValidationError   # Schema validation errors
OpenRouter::StructuredOutputError   # JSON parsing/healing errors
OpenRouter::ModelRegistryError      # Model registry errors
OpenRouter::ModelSelectionError     # Model selection errors
```

### Configuration Options

```ruby
OpenRouter.configure do |config|
  # Authentication
  config.access_token = "sk-..."
  config.site_name = "Your App Name"
  config.site_url = "https://yourapp.com"

  # Request settings
  config.request_timeout = 120
  config.api_version = "v1"
  config.uri_base = "https://openrouter.ai/api"
  config.extra_headers = {}

  # Response healing
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2

  # Capability validation
  config.strict_mode = true
  config.auto_force_on_unsupported_models = true

  # Structured outputs
  config.default_structured_output_mode = :strict

  # Caching
  config.cache_ttl = 7 * 24 * 60 * 60  # 7 days

  # Model registry
  config.model_registry_timeout = 30
  config.model_registry_retries = 3

  # Logging
  config.log_errors = false
  config.faraday do |f|
    f.response :logger
  end
end
```

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/estiens/open_router_enhanced>.

This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [Contributor Covenant](https://www.contributor-covenant.org/) code of conduct.

For detailed contribution guidelines, see [CONTRIBUTING.md](.github/CONTRIBUTING.md).

### Branch Strategy

We use a two-branch workflow:

- **`main`** - Stable releases only. Protected branch.
- **`dev`** - Active development. All PRs should target this branch.

**⚠️ Important:** Always target your PRs to the `dev` branch, not `main`. The `main` branch is reserved for stable releases.

### Development Setup

```bash
git clone https://github.com/estiens/open_router_enhanced.git
cd open_router_enhanced
bundle install
bundle exec rspec
```

### Running Examples

```bash
# Set your API key
export OPENROUTER_API_KEY="your_key_here"

# Run examples
ruby -I lib examples/tool_calling_example.rb
ruby -I lib examples/structured_outputs_example.rb
ruby -I lib examples/model_selection_example.rb
```

## Acknowledgments

This enhanced fork builds upon the excellent foundation laid by [Obie Fernandez](https://github.com/obie) and the original OpenRouter Ruby gem. The original library was bootstrapped from the [Anthropic gem](https://github.com/alexrudall/anthropic) by [Alex Rudall](https://github.com/alexrudall) and extracted from the codebase of [Olympia](https://olympia.chat), Obie's AI startup.

We extend our heartfelt gratitude to:

- **Obie Fernandez** - Original OpenRouter gem author and visionary
- **Alex Rudall** - Creator of the Anthropic gem that served as the foundation
- **The OpenRouter Team** - For creating an amazing unified AI API
- **The Ruby Community** - For continuous support and contributions

## Maintainer & Consulting

This enhanced fork is maintained by:

**Eric Stiens**
- Email: hello@ericstiens.dev
- Website: [ericstiens.dev](http://ericstiens.dev)
- GitHub: [@estiens](https://github.com/estiens)
- Blog: [Low Level Magic](https://lowlevelmagic.io)

### Need Help with AI Integration?

I'm available for consulting on Ruby AI applications, LLM integration, and building production-ready AI systems. My work extends beyond Ruby to include real-time AI orchestration, character-based AI systems, multi-agent architectures, and low-latency voice/streaming applications. Whether you need help with tool calling workflows, cost optimization, building AI characters with persistent memory, or orchestrating complex multi-model systems, I'd be happy to help.

**Get in touch:**
- Email: hello@lowlevelmagic.io
- Visit: [lowlevelmagic.io](https://lowlevelmagic.io)
- Read more: [Why I Built OpenRouter Enhanced](https://lowlevelmagic.io/writings/why-i-built-open-router-enhanced/)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

MIT License is chosen for maximum permissiveness and compatibility, allowing unrestricted use, modification, and distribution while maintaining attribution requirements.