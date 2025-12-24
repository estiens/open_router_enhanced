# OpenRouter Plugins

OpenRouter provides plugins that extend model capabilities. The gem supports all OpenRouter plugins and automatically enables response healing for structured outputs.

## Available Plugins

| Plugin | ID | Description |
|--------|-----|-------------|
| Response Healing | `response-healing` | Fixes malformed JSON responses |
| Web Search | `web-search` | Augments responses with real-time web search |
| PDF Inputs | `pdf-inputs` | Parses and extracts content from PDF files |

## Basic Usage

```ruby
# Specify plugins in your request
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  plugins: [{ id: "web-search" }]
)

# Multiple plugins
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  plugins: [
    { id: "web-search" },
    { id: "pdf-inputs" }
  ]
)
```

## Response Healing Plugin

The response-healing plugin fixes common JSON formatting issues server-side:

- Missing brackets, commas, and quotes
- Trailing commas
- Markdown-wrapped JSON
- Text mixed with JSON
- Unquoted object keys

### Automatic Activation

The gem **automatically adds** the response-healing plugin when:
1. Using structured outputs (`response_format` is set)
2. Not streaming
3. `auto_native_healing` is enabled (default: true)

```ruby
# Response-healing is automatically added here
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  response_format: schema
)
```

### Disable Automatic Healing

```ruby
# Via configuration
OpenRouter.configure do |config|
  config.auto_native_healing = false
end

# Via environment variable
# OPENROUTER_AUTO_NATIVE_HEALING=false
```

### Manual Control

```ruby
# Explicitly add response-healing
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  plugins: [{ id: "response-healing" }],
  response_format: { type: "json_object" }
)

# Disable for a specific request (when auto is enabled)
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",
  plugins: [{ id: "response-healing", enabled: false }],
  response_format: schema
)
```

### Limitations

- **Non-streaming only**: Does not work with `stream: proc`
- **Syntax only**: Fixes JSON syntax, not schema conformance
- **Truncation issues**: May fail if response was cut off by `max_tokens`

For schema validation failures, use the gem's [client-side auto-healing](structured_outputs.md#json-auto-healing-client-side).

## Web Search Plugin

Augments model responses with real-time web search results.

```ruby
response = client.complete(
  [{ role: "user", content: "What are the latest AI developments?" }],
  model: "openai/gpt-4o-mini",
  plugins: [{ id: "web-search" }]
)
```

**Shortcut**: Append `:online` to model ID:

```ruby
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini:online"  # Enables web-search
)
```

## PDF Inputs Plugin

Enables models to process PDF file content.

```ruby
response = client.complete(
  [{ role: "user", content: "Summarize this PDF: [pdf content]" }],
  model: "openai/gpt-4o-mini",
  plugins: [{ id: "pdf-inputs" }]
)
```

## Plugin Configuration Options

Plugins can accept additional configuration:

```ruby
# Enable/disable a plugin explicitly
plugins: [{ id: "response-healing", enabled: true }]

# Disable a default plugin for one request
plugins: [{ id: "response-healing", enabled: false }]
```

## Prediction Parameter (Latency Optimization)

The `prediction` parameter reduces latency by providing the model with an expected output:

```ruby
response = client.complete(
  [{ role: "user", content: "What is the capital of France?" }],
  model: "openai/gpt-4o",
  prediction: { type: "content", content: "The capital of France is Paris." }
)
```

**When to use**:
- Code completion with predictable boilerplate
- Template filling where most content is known
- Minor corrections/refinements to existing text

**How it works**: Instead of generating from scratch, the model confirms/refines your prediction, which is faster when accurate.

## Best Practices

1. **Use native healing for structured outputs**: It's free and adds <1ms latency
2. **Don't combine response-healing with streaming**: It won't work
3. **Check model compatibility**: Not all models support all plugins
4. **Monitor costs**: Web search may add to response latency

## Comparison: Native vs Client-Side Healing

| Aspect | Native (Plugin) | Client-Side (Gem) |
|--------|-----------------|-------------------|
| Location | Server-side | Client-side |
| Cost | Free | API call per attempt |
| Latency | <1ms | Full LLM call |
| Fixes syntax | Yes | Yes |
| Fixes schema | No | Yes |
| Streaming | No | Yes |
| Auto-enabled | For structured outputs | When `auto_heal_responses = true` |

**Recommendation**: Use both! Native healing catches 80%+ of issues for free. Client-side healing handles the rest and validates against your schema.
