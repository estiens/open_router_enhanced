## [Unreleased]

## [2.0.0] - 2025-12-28

### Overview

Version 2.0.0 introduces the `CompletionOptions` class - a structured, self-documenting way to configure API requests. This replaces the previous pattern of 11+ keyword arguments with a clean, reusable options object.

**This is a semver major release, but existing code will continue to work without modification.** The new patterns are opt-in and recommended for new code.

---

### Breaking Changes

Method signatures now accept an optional `CompletionOptions` object as the second parameter:

| Method | Old Signature | New Signature |
|--------|---------------|---------------|
| `complete` | `(messages, model:, tools:, ...)` | `(messages, options = nil, stream:, **kwargs)` |
| `stream_complete` | `(messages, model:, ...)` | `(messages, options = nil, accumulate_response:, **kwargs, &block)` |
| `stream` | `(messages, model:, ...)` | `(messages, options = nil, **kwargs, &block)` |
| `responses` | `(input, model:, ...)` | `(input, options = nil, **kwargs)` |

**Important**: The `options` parameter accepts `CompletionOptions`, `Hash`, or `nil`. All existing keyword argument patterns continue to work.

---

### Migration Guide

#### No Changes Required (Backward Compatible)

All existing code continues to work:

```ruby
# ✅ These all work exactly as before:
client.complete(messages, model: "openai/gpt-4o")
client.complete(messages, model: "openai/gpt-4o", temperature: 0.7)
client.stream(messages, model: "openai/gpt-4o") { |chunk| print chunk }
client.responses("Hello", model: "openai/gpt-4o", reasoning: { effort: "high" })
```

#### Recommended: Use CompletionOptions for New Code

For new code, we recommend using `CompletionOptions` for better IDE support, documentation, and reusability:

```ruby
# Create reusable configuration
opts = OpenRouter::CompletionOptions.new(
  model: "openai/gpt-4o",
  temperature: 0.7,
  max_tokens: 1000
)

# Use across multiple calls
response1 = client.complete(messages1, opts)
response2 = client.complete(messages2, opts)

# Override specific values without mutating original
creative_opts = opts.merge(temperature: 1.2)
response3 = client.complete(messages3, creative_opts)
```

#### Migrating Complex Configurations

**Before (v1.x)**:
```ruby
client.complete(
  messages,
  model: "openai/gpt-4o",
  tools: my_tools,
  tool_choice: "auto",
  temperature: 0.7,
  max_tokens: 2000,
  providers: ["openai", "azure"],
  response_format: { type: "json_object" },
  extras: { custom_param: "value" }
)
```

**After (v2.0 - recommended)**:
```ruby
opts = OpenRouter::CompletionOptions.new(
  model: "openai/gpt-4o",
  tools: my_tools,
  tool_choice: "auto",
  temperature: 0.7,
  max_tokens: 2000,
  providers: ["openai", "azure"],
  response_format: { type: "json_object" },
  extras: { custom_param: "value" }
)

client.complete(messages, opts)
```

#### Migrating Streaming Code

**Before (v1.x)**:
```ruby
client.stream_complete(
  messages,
  model: "openai/gpt-4o",
  accumulate_response: true
) do |chunk|
  print chunk.dig("choices", 0, "delta", "content")
end
```

**After (v2.0 - recommended)**:
```ruby
opts = OpenRouter::CompletionOptions.new(model: "openai/gpt-4o")

client.stream_complete(messages, opts, accumulate_response: true) do |chunk|
  print chunk.dig("choices", 0, "delta", "content")
end

# Or use the simpler stream method:
client.stream(messages, opts) { |content| print content }
```

#### Pattern: Base Options with Per-Request Overrides

```ruby
# Define base configuration once
BASE_OPTS = OpenRouter::CompletionOptions.new(
  model: "openai/gpt-4o",
  max_tokens: 1000,
  providers: ["openai"]
)

# Override for specific use cases
def generate_creative_content(prompt)
  messages = [{ role: "user", content: prompt }]
  client.complete(messages, BASE_OPTS, temperature: 1.2)
end

def generate_factual_content(prompt)
  messages = [{ role: "user", content: prompt }]
  client.complete(messages, BASE_OPTS, temperature: 0.1)
end
```

---

### Added

#### `OpenRouter::CompletionOptions` Class

A structured configuration object supporting **30+ parameters** organized by category:

**Core Parameters**:
- `model` - Model ID string or array for fallback routing
- `tools` - Tool/function definitions
- `tool_choice` - `"auto"`, `"none"`, `"required"`, or specific tool
- `extras` - Hash for pass-through of any additional/future parameters

**Sampling Parameters** (control response randomness):
- `temperature` - 0.0-2.0, controls randomness (default varies by model)
- `top_p` - 0.0-1.0, nucleus sampling threshold
- `top_k` - Integer, limits token selection to top K
- `frequency_penalty` - -2.0 to 2.0, penalize frequent tokens
- `presence_penalty` - -2.0 to 2.0, penalize tokens already present
- `repetition_penalty` - 0.0-2.0, general repetition penalty
- `min_p` - 0.0-1.0, minimum probability threshold
- `top_a` - 0.0-1.0, dynamic token filtering
- `seed` - Integer for reproducible outputs

**Output Control**:
- `max_tokens` - Maximum tokens to generate (legacy)
- `max_completion_tokens` - Maximum tokens (preferred, newer API)
- `stop` - String or array of stop sequences
- `logprobs` - Boolean, return log probabilities
- `top_logprobs` - 0-20, number of top logprobs per token
- `logit_bias` - Hash mapping token IDs to bias values (-100 to 100)
- `response_format` - Structured output schema configuration
- `parallel_tool_calls` - Boolean, allow parallel function calls
- `verbosity` - `:low`, `:medium`, `:high`

**OpenRouter Routing**:
- `providers` - Array of provider names (becomes `provider.order`)
- `provider` - Full provider config hash (overrides `providers`)
- `transforms` - Array of transform identifiers
- `plugins` - Array of plugin configs (`web-search`, `response-healing`, etc.)
- `prediction` - Predicted output for latency optimization
- `route` - `"fallback"` or `"sort"`
- `metadata` - Custom key-value metadata
- `user` - End-user identifier for tracking
- `session_id` - Session grouping identifier (max 128 chars)

**Responses API**:
- `reasoning` - Hash with `effort:` key (`"minimal"`, `"low"`, `"medium"`, `"high"`)

**Client-Side Options** (not sent to API):
- `force_structured_output` - Override forced extraction mode behavior

#### Helper Methods

```ruby
opts = CompletionOptions.new(model: "gpt-4", tools: [...])

opts.has_tools?           # => true if tools are defined
opts.has_response_format? # => true if response_format is set
opts.fallback_models?     # => true if model is an array

opts.to_h                 # => Hash of all non-nil, non-empty values
opts.to_api_params        # => Hash for API request (excludes client-side params)
opts.merge(temp: 0.5)     # => New CompletionOptions with override
```

---

### Backward Compatibility

**All existing patterns continue to work**:

```ruby
# Direct kwargs (unchanged from v1.x)
client.complete(messages, model: "gpt-4")

# Hash as second argument
client.complete(messages, { model: "gpt-4", temperature: 0.7 })

# CompletionOptions object (new in v2.0)
opts = CompletionOptions.new(model: "gpt-4")
client.complete(messages, opts)

# Options with kwargs overrides (new in v2.0)
client.complete(messages, opts, temperature: 0.9)
```

The `normalize_options` helper transparently handles all input styles.

---

### Internal Improvements

- New `normalize_options` private helper for flexible input handling
- Refactored `prepare_base_parameters` to accept `CompletionOptions`
- Refactored `configure_tools_and_structured_outputs!` to use `CompletionOptions`
- Added focused parameter helpers:
  - `configure_sampling_parameters!`
  - `configure_output_parameters!`
  - `configure_routing_parameters!`
- Improved separation of concerns in request building

---

### Bug Fixes

- Fixed issue where `extras` hash contents were nested incorrectly in API requests. Parameters like `max_tokens` passed via `extras` now correctly appear at the top level of the request body.

## [1.2.2] - 2025-12-25

### Fixed
- Fixed SSL certificate verification error in `ModelRegistry` by switching from `Net::HTTP` to `Faraday` for consistent HTTP handling across the gem

### Added
- New examples in `examples/` directory:
  - `real_world_schemas_example.rb` - Practical structured data extraction scenarios
  - `tool_loop_example.rb` - Complete Chat Completions API tool calling workflow
  - `responses_api_example.rb` - Responses API with multi-turn tool loops
  - `dynamic_model_switching_example.rb` - Runtime model selection and capability detection

## [1.2.1] - 2025-12-24

### Fixed
- Memoized `output_id` in `ResponsesToolResult` to ensure consistent IDs across multiple calls
- Memoized `message_output` and `reasoning_output` finders in `ResponsesResponse` for performance

## [1.2.0] - 2025-12-24

### Added
- **Responses API**: Full support for OpenRouter's Responses API Beta (`/api/v1/responses`)
  - Simple string or structured array input
  - Reasoning with configurable effort levels (`minimal`, `low`, `medium`, `high`)
  - `ResponsesResponse` wrapper with convenient accessors
- **Responses API Tool Calling**: Complete function calling support for Responses API
  - `ResponsesToolCall` and `ResponsesToolResult` classes
  - `execute_tool_calls` for easy tool execution with blocks
  - `build_follow_up_input` for multi-turn tool conversations
  - `tool_choice` parameter (`auto`, `required`, `none`)
  - Automatic format conversion from Chat Completions tool format
- **Shared Tool Call Infrastructure**: Extracted `ToolCallBase` and `ToolResultBase` modules
  - DRY shared behavior for argument parsing and execution
  - Consistent interface across Chat Completions and Responses APIs

### Documentation
- New `docs/responses_api.md` with comprehensive Responses API guide
- Tool calling examples with Tool DSL and hash formats

## [1.1.0] - 2025-12-24

### Added
- **Native Response Healing Plugin**: Automatic server-side JSON healing for structured outputs via OpenRouter's `response-healing` plugin (free, <1ms latency)
- **Plugins Parameter**: Support for OpenRouter plugins (`web-search`, `pdf-inputs`, `response-healing`) via new `plugins:` parameter
- **Prediction Parameter**: Latency optimization via `prediction:` parameter for predictable outputs
- **Auto Native Healing**: Automatically enables `response-healing` plugin when using structured outputs (configurable via `auto_native_healing` setting)

### Changed
- Enhanced structured output workflow: native healing catches syntax errors server-side, client-side healing handles schema validation

### Configuration
- New `auto_native_healing` config option (default: `true`)
- Environment variable: `OPENROUTER_AUTO_NATIVE_HEALING`

## [1.0.0] - 2025-10-07

### Major Features
- **Tool Calling**: Complete function calling support with DSL-based tool definitions and automatic validation
- **Structured Outputs**: Native and forced JSON schema support with automatic response healing
- **Model Selection**: Intelligent model selection with fluent DSL, capability detection, and cost optimization
- **Model Fallbacks**: Automatic failover routing with model arrays for reliability
- **Response Healing**: Self-correcting malformed JSON outputs from non-native structured output models
- **Streaming Client**: Real-time streaming with comprehensive callback system
- **Usage Tracking**: Token usage and cost analytics with detailed metrics
- **Prompt Templates**: Reusable templates with variable interpolation

### Enhanced
- **Model Registry**: Local caching with automatic capability detection and cost calculation
- **Response Object**: Rich metadata including tokens, costs, cache hits, and performance analytics
- **Error Handling**: Comprehensive error hierarchy with specific error types for better debugging
- **VCR Testing**: Complete real API integration testing coverage
- **Documentation**: Extensive guides, examples, and API reference

### Compatibility
- Full backward compatibility with original OpenRouter gem
- Ruby 3.0+ support
- Optional dependencies for enhanced features (json-schema for validation)

## [0.3.0] - 2024-05-03

### Changed
- Uses Faraday's built-in JSON mode
- Added support for configuring Faraday and its middleware
- Spec creates a STDOUT logger by default (headers, bodies, errors)  
- Spec filters Bearer token from logs by default

## [0.1.0] - 2024-03-19

### Added
- Initial release of OpenRouter Ruby gem
- Basic chat completion support
- Model selection and routing
- OpenRouter API integration
