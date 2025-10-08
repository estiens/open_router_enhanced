# OpenRouter Enhanced - Ruby Gem

The future will bring us hundreds of language models and dozens of providers for each. How will you choose the best?

The [OpenRouter API](https://openrouter.ai/docs) is a single unified interface for all LLMs, accessible through an idiomatic Ruby interface.

**OpenRouter Enhanced** is an advanced fork of the [original OpenRouter Ruby gem](https://github.com/OlympiaAI/open_router) by [Obie Fernandez](https://github.com/obie) that adds comprehensive AI application development features including tool calling, structured outputs, intelligent model selection, prompt templates, observability, and automatic response healing—all while maintaining full backward compatibility.

**[Read the story behind OpenRouter Enhanced](https://lowlevelmagic.io/writings/why-i-built-open-router-enhanced/)** - Learn why this gem was built and the philosophy behind its design.

## Enhanced Features

### Core AI Features
- **[Tool Calling](docs/tools.md)**: Full support for OpenRouter's function calling API with Ruby-idiomatic DSL
- **[Structured Outputs](docs/structured_outputs.md)**: JSON Schema validation with automatic healing for non-native models
- **[Smart Model Selection](docs/model_selection.md)**: Intelligent model selection with cost optimization and capability matching
- **[Prompt Templates](docs/prompt_templates.md)**: Reusable prompt templates with variable interpolation and few-shot learning

### Performance & Reliability
- **Model Registry**: Local caching and querying of OpenRouter model data with capability detection
- **Enhanced Response Handling**: Rich Response objects with automatic parsing for tool calls and structured outputs
- **Automatic Healing**: Self-healing responses for malformed JSON from models without native structured output support
- **Model Fallbacks**: Automatic failover between models with graceful degradation
- **Streaming Support**: Enhanced streaming client with callback system and response reconstruction

### Observability & Analytics
- **Usage Tracking**: Comprehensive token usage and cost tracking across all API calls
- **Response Analytics**: Detailed metadata including tokens, costs, cache hits, and performance metrics
- **Callback System**: Extensible event system for monitoring requests, responses, and errors
- **Cost Management**: Built-in cost estimation and budget constraints

### Core OpenRouter Benefits
- **Prioritize price or performance**: OpenRouter scouts for the lowest prices and best latencies/throughputs across dozens of providers
- **Standardized API**: No need to change your code when switching between models or providers
- **Easy integration**: Simple and intuitive Ruby interface for AI capabilities

## Table of Contents

- [Installation](#installation)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Features](#features)
  - [Tool Calling](#tool-calling)
  - [Structured Outputs](#structured-outputs)
  - [Smart Model Selection](#smart-model-selection)
  - [Prompt Templates](#prompt-templates)
  - [Streaming](#streaming)
  - [Usage Tracking](#usage-tracking)
- [Model Exploration](#model-exploration)
- [Testing](#testing)
- [Troubleshooting](#troubleshooting)
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

## Quick Start

### 1. Get Your API Key
- Sign up at [OpenRouter](https://openrouter.ai)
- Get your API key from [https://openrouter.ai/keys](https://openrouter.ai/keys)

### 2. Basic Setup

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

### 3. Enhanced Features Example

```ruby
# Smart model selection with capabilities
model = OpenRouter::ModelSelector.new
  .require(:function_calling)
  .optimize_for(:cost)
  .choose

# Define a tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather"
  parameters do
    string :location, required: true
  end
end

# Define a schema for structured output
weather_schema = OpenRouter::Schema.define("weather") do
  string :location, required: true
  number :temperature, required: true
  string :conditions, required: true
end

# Use everything together
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

Configure the gem globally (e.g., in an initializer):

```ruby
OpenRouter.configure do |config|
  # Required
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "Your App Name"
  config.site_url = "https://yourapp.com"

  # Optional: Response healing for non-native structured output models
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2

  # Optional: Strict mode for capability validation
  config.strict_mode = true

  # Optional: Request timeout (default: 120 seconds)
  config.request_timeout = 120
end
```

### Per-Client Configuration

```ruby
client = OpenRouter::Client.new(
  access_token: ENV["OPENROUTER_API_KEY"],
  request_timeout: 240
)
```

### Faraday Configuration

Configure Faraday middleware for retries, logging, etc:

```ruby
require 'faraday/retry'

OpenRouter::Client.new(access_token: ENV["ACCESS_TOKEN"]) do |config|
  config.faraday do |f|
    f.request :retry, max: 2, interval: 0.05
    f.response :logger, ::Logger.new($stdout), { headers: true, bodies: true }
  end
end
```

**[Full configuration documentation](docs/configuration.md)**

## Features

### Tool Calling

Enable AI models to call functions and interact with external APIs.

```ruby
# Define a tool with the DSL
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
  tools: [weather_tool]
)

# Handle tool calls
if response.has_tool_calls?
  response.tool_calls.each do |tool_call|
    result = fetch_weather(tool_call.arguments["location"])
    puts "Weather: #{result}"
  end
end
```

**[Complete Tool Calling Documentation](docs/tools.md)**

### Structured Outputs

Get JSON responses that conform to specific schemas with automatic validation and healing.

```ruby
# Define a schema
user_schema = OpenRouter::Schema.define("user") do
  string :name, required: true, description: "Full name"
  integer :age, required: true, minimum: 0, maximum: 150
  string :email, required: true
  boolean :premium, description: "Premium account status"
end

# Get structured response
response = client.complete(
  [{ role: "user", content: "Create a user: John Doe, 30, john@example.com" }],
  model: "openai/gpt-4o",
  response_format: user_schema
)

# Access parsed JSON
user = response.structured_output
puts "#{user['name']} (#{user['age']}) - #{user['email']}"
```

**Key Features:**
- Ruby DSL for JSON schemas
- Automatic healing for models without native support
- Validation with detailed error reporting
- Support for nested objects and arrays

**[Complete Structured Outputs Documentation](docs/structured_outputs.md)**

### Smart Model Selection

Automatically choose the best model based on requirements.

```ruby
# Find cheapest model with function calling
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

# Get multiple options for fallbacks
models = OpenRouter::ModelSelector.new
  .require(:structured_outputs)
  .choose_with_fallbacks(limit: 3)
# => ["openai/gpt-4o-mini", "anthropic/claude-3-haiku", "google/gemini-flash"]
```

**Available capabilities:** `:chat`, `:function_calling`, `:structured_outputs`, `:vision`, `:code_generation`

**Optimization strategies:** `:cost`, `:performance`, `:latest`, `:context`

**[Complete Model Selection Documentation](docs/model_selection.md)**

### Prompt Templates

Create reusable, parameterized prompts with variable interpolation.

```ruby
# Basic template
translation_template = OpenRouter::PromptTemplate.new(
  template: "Translate '{text}' from {source_lang} to {target_lang}",
  input_variables: [:text, :source_lang, :target_lang]
)

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
  prefix: "Classify the sentiment:",
  suffix: "Now classify: {text}",
  examples: [
    { text: "I love this!", sentiment: "positive" },
    { text: "This is terrible.", sentiment: "negative" }
  ],
  example_template: "Text: {text}\nSentiment: {sentiment}",
  input_variables: [:text]
)
```

**[Complete Prompt Templates Documentation](docs/prompt_templates.md)**

### Streaming

Stream responses in real-time with callbacks and automatic response reconstruction.

```ruby
streaming_client = OpenRouter::StreamingClient.new

# Set up callbacks
streaming_client
  .on_stream(:on_start) { |data| puts "Starting..." }
  .on_stream(:on_chunk) { |chunk| print chunk.content }
  .on_stream(:on_finish) { |response| puts "\nDone! Tokens: #{response.total_tokens}" }
  .on_stream(:on_error) { |error| puts "Error: #{error.message}" }

# Stream with automatic response accumulation
response = streaming_client.stream_complete(
  [{ role: "user", content: "Write a story about a robot" }],
  model: "openai/gpt-4o-mini",
  accumulate_response: true
)

puts "Final response: #{response.content}"
```

**[Complete Streaming Documentation](docs/streaming.md)**

### Usage Tracking

Track token usage, costs, and performance metrics.

```ruby
# Enable tracking
client = OpenRouter::Client.new(track_usage: true)

# Make requests
3.times do
  response = client.complete(
    [{ role: "user", content: "Tell me a fact" }],
    model: "openai/gpt-4o-mini"
  )
end

# View statistics
tracker = client.usage_tracker
puts "Total requests: #{tracker.request_count}"
puts "Total tokens: #{tracker.total_tokens}"
puts "Total cost: $#{tracker.total_cost.round(4)}"

# Per-model breakdown
tracker.model_usage.each do |model, stats|
  puts "#{model}: #{stats[:total_tokens]} tokens, $#{stats[:cost].round(4)}"
end

# Print detailed report
tracker.print_summary
```

**[Complete Usage Tracking Documentation](docs/usage_tracking.md)**

## Model Exploration

The gem includes rake tasks for exploring available models:

```bash
# View model summary with statistics
bundle exec rake models:summary

# Search by provider
bundle exec rake models:search provider=anthropic

# Search by capabilities and optimize for cost
bundle exec rake models:search capability=function_calling optimize=cost limit=10

# Advanced filtering
bundle exec rake models:search provider=anthropic capability=function_calling min_context=100000 max_cost=0.01
```

Available search parameters:
- `provider=name` - Filter by provider
- `capability=cap1,cap2` - Required capabilities
- `optimize=strategy` - Optimization (cost, performance, latest, context)
- `min_context=tokens` - Minimum context length
- `max_cost=amount` - Maximum cost per 1k tokens
- `newer_than=YYYY-MM-DD` - Filter by release date
- `limit=N` - Maximum results (default: 20)

## Testing

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
# Set API key
export OPENROUTER_API_KEY="your_api_key"

# Run VCR tests
bundle exec rspec spec/vcr/

# Re-record cassettes
rm -rf spec/fixtures/vcr_cassettes/
bundle exec rspec spec/vcr/
```

### Examples

Comprehensive examples for all features are available in the `examples/` directory:

```bash
# Set your API key
export OPENROUTER_API_KEY="your_key_here"

# Run examples
ruby -I lib examples/basic_completion.rb
ruby -I lib examples/tool_calling_example.rb
ruby -I lib examples/structured_outputs_example.rb
ruby -I lib examples/model_selection_example.rb
ruby -I lib examples/streaming_example.rb
```

## Troubleshooting

### Common Issues

**Authentication Errors**
```ruby
# Set your API key
export OPENROUTER_API_KEY="your_key_here"

# Or in code
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
end
```

**Model Selection Issues**
```ruby
# Use ModelSelector to find compatible models
model = OpenRouter::ModelSelector.new
  .require(:function_calling)
  .choose
```

**Structured Output Issues**
```ruby
# Enable automatic healing
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
end
```

**Performance Issues**
```ruby
# Optimize configuration
client = OpenRouter::Client.new(
  request_timeout: 30,
  strict_mode: false,
  auto_heal_responses: false
)
```

### Debug Mode

Enable detailed logging:

```ruby
require 'logger'

OpenRouter.configure do |config|
  config.log_errors = true
  config.faraday do |f|
    f.response :logger, Logger.new($stdout), { headers: true, bodies: true, errors: true }
  end
end
```

### Getting Help

1. **Check the documentation**: Detailed docs in the `docs/` directory
2. **Review examples**: Working examples in `examples/`
3. **Enable debug mode**: Turn on logging to see details
4. **Check OpenRouter status**: [OpenRouter Status](https://status.openrouter.ai)
5. **Open an issue**: [GitHub Issues](https://github.com/estiens/open_router_enhanced/issues)

**[Complete Troubleshooting Guide](docs/troubleshooting.md)**

## Contributing

Bug reports and pull requests are welcome on GitHub at <https://github.com/estiens/open_router_enhanced>.

### Branch Strategy

We use a two-branch workflow:
- **`main`** - Stable releases only. Protected branch.
- **`dev`** - Active development. **All PRs should target this branch.**

**Important:** Always target your PRs to the `dev` branch, not `main`.

### Development Setup

```bash
git clone https://github.com/estiens/open_router_enhanced.git
cd open_router_enhanced
bundle install
bundle exec rspec
```

For detailed contribution guidelines, see [CONTRIBUTING.md](.github/CONTRIBUTING.md).

## Acknowledgments

This enhanced fork builds upon the excellent foundation laid by [Obie Fernandez](https://github.com/obie) and the original OpenRouter Ruby gem. The original library was bootstrapped from the [Anthropic gem](https://github.com/alexrudall/anthropic) by [Alex Rudall](https://github.com/alexrudall).

We extend our heartfelt gratitude to:
- **Obie Fernandez** - Original OpenRouter gem author
- **Alex Rudall** - Creator of the Anthropic gem foundation
- **The OpenRouter Team** - For creating an amazing unified AI API
- **The Ruby Community** - For continuous support and contributions

## Consulting

I'm available for consulting on Ruby AI applications, LLM integration, and building production-ready AI systems. My work extends beyond Ruby to include real-time AI orchestration, character-based AI systems, multi-agent architectures, and low-latency voice/streaming applications.

**Get in touch:**
- Email: hello@lowlevelmagic.io
- Visit: [lowlevelmagic.io](https://lowlevelmagic.io)
- Read more: [Why I Built OpenRouter Enhanced](https://lowlevelmagic.io/writings/why-i-built-open-router-enhanced/)

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
