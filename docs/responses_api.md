# Responses API (Beta)

The Responses API is an OpenAI-compatible stateless endpoint that provides access to multiple AI models with advanced reasoning capabilities.

> **Beta**: This API may have breaking changes. Use with caution in production.

## Basic Usage

```ruby
client = OpenRouter::Client.new

response = client.responses(
  "What is the capital of France?",
  model: "openai/gpt-4o-mini"
)

puts response.content  # => "Paris"
```

## With Reasoning

The Responses API supports reasoning with configurable effort levels:

```ruby
response = client.responses(
  "What is 15% of 80? Show your work.",
  model: "openai/o4-mini",
  reasoning: { effort: "high" },
  max_output_tokens: 500
)

# Access reasoning steps
if response.has_reasoning?
  puts "Reasoning steps:"
  response.reasoning_summary.each { |step| puts "  - #{step}" }
end

puts "Answer: #{response.content}"
puts "Reasoning tokens used: #{response.reasoning_tokens}"
```

### Effort Levels

| Level | Description |
|-------|-------------|
| `minimal` | Basic reasoning with minimal computational effort |
| `low` | Light reasoning for simple problems |
| `medium` | Balanced reasoning for moderate complexity |
| `high` | Deep reasoning for complex problems |

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `input` | String or Array | The input text or structured message array (required) |
| `model` | String | Model identifier, e.g. `"openai/o4-mini"` (required) |
| `reasoning` | Hash | Reasoning config with `effort` key |
| `tools` | Array | Tool definitions for function calling |
| `tool_choice` | String/Hash | `"auto"`, `"none"`, `"required"`, or specific tool |
| `max_output_tokens` | Integer | Maximum tokens to generate |
| `temperature` | Float | Sampling temperature (0-2) |
| `top_p` | Float | Nucleus sampling parameter (0-1) |
| `extras` | Hash | Additional API parameters |

## Structured Input

You can also use structured message arrays:

```ruby
response = client.responses(
  [
    {
      "type" => "message",
      "role" => "user",
      "content" => [
        { "type" => "input_text", "text" => "Hello, world!" }
      ]
    }
  ],
  model: "openai/gpt-4o-mini"
)
```

## Response Object

The `ResponsesResponse` class provides convenient accessors:

```ruby
response.id              # Response ID
response.status          # "completed", "failed", etc.
response.model           # Model used
response.content         # Assistant's text response
response.output          # Raw output array

# Reasoning
response.has_reasoning?     # Boolean
response.reasoning_summary  # Array of reasoning steps

# Tool calls
response.has_tool_calls?  # Boolean
response.tool_calls       # Array of ResponsesToolCall objects
response.tool_calls_raw   # Array of raw hash data

# Token usage
response.input_tokens     # Input token count
response.output_tokens    # Output token count
response.total_tokens     # Total token count
response.reasoning_tokens # Tokens used for reasoning
```

## Tool/Function Calling

The Responses API supports function calling with a simplified format. Tool calls are wrapped in `ResponsesToolCall` objects for easy execution.

### Defining Tools

You can use the same tool format as Chat Completions - the gem automatically converts it:

```ruby
tools = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get current weather for a location",
      parameters: {
        type: "object",
        properties: {
          location: { type: "string", description: "City name" },
          units: { type: "string", enum: ["celsius", "fahrenheit"] }
        },
        required: ["location"]
      }
    }
  }
]

response = client.responses(
  "What's the weather in San Francisco?",
  model: "openai/gpt-4o-mini",
  tools: tools
)
```

You can also use the `Tool` DSL:

```ruby
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"
  parameters do
    string :location, required: true, description: "City name"
    string :units, enum: %w[celsius fahrenheit]
  end
end

response = client.responses(
  "What's the weather in Tokyo?",
  model: "openai/gpt-4o-mini",
  tools: [weather_tool]
)
```

### Tool Choice

Control when the model uses tools with `tool_choice`:

```ruby
# Let model decide (default)
response = client.responses(input, model: model, tools: tools, tool_choice: "auto")

# Force tool use
response = client.responses(input, model: model, tools: tools, tool_choice: "required")

# Prevent tool use
response = client.responses(input, model: model, tools: tools, tool_choice: "none")
```

### Executing Tool Calls

```ruby
if response.has_tool_calls?
  # Execute each tool call with a block
  results = response.execute_tool_calls do |name, arguments|
    case name
    when "get_weather"
      fetch_weather(arguments["location"], arguments["units"])
    when "search_web"
      search(arguments["query"])
    else
      { error: "Unknown function: #{name}" }
    end
  end

  # Results are ResponsesToolResult objects
  results.each do |result|
    if result.success?
      puts "#{result.tool_call.name}: #{result.result}"
    else
      puts "Error: #{result.error}"
    end
  end
end
```

### Multi-turn Tool Conversations

Use `build_follow_up_input` to continue conversations after tool execution:

```ruby
# First call - model requests tool use
original_input = "What's the weather in NYC and Paris?"
response = client.responses(original_input, model: "openai/gpt-4o-mini", tools: tools)

# Execute the tool calls
results = response.execute_tool_calls do |name, args|
  fetch_weather(args["location"])
end

# Build follow-up input with tool results
next_input = response.build_follow_up_input(
  original_input: original_input,
  tool_results: results
)

# Continue the conversation - model will use the tool results
final_response = client.responses(next_input, model: "openai/gpt-4o-mini")
puts final_response.content
# => "In NYC it's 72°F and sunny. In Paris it's 18°C and cloudy."
```

### Adding Follow-up Messages

You can include a follow-up question when building the input:

```ruby
next_input = response.build_follow_up_input(
  original_input: original_input,
  tool_results: results,
  follow_up_message: "Which city has better weather for a picnic?"
)
```

### Tool Call Objects

`ResponsesToolCall` provides:

```ruby
tool_call.id              # Tool call ID
tool_call.call_id         # Call ID for result matching
tool_call.name            # Function name
tool_call.function_name   # Alias for name
tool_call.arguments       # Parsed arguments hash
tool_call.arguments_string # Raw JSON string
tool_call.to_input_item   # Convert to input format
```

`ResponsesToolResult` provides:

```ruby
result.tool_call  # Reference to the tool call
result.result     # Execution result (if successful)
result.error      # Error message (if failed)
result.success?   # Boolean
result.failure?   # Boolean
result.to_input_item  # Convert to function_call_output format
```

## Comparison with Chat Completions

| Aspect | `complete()` | `responses()` |
|--------|--------------|---------------|
| Endpoint | `/chat/completions` | `/responses` |
| Input | `messages` array | `input` string or array |
| Output | `choices[].message` | `output[]` typed items |
| Reasoning | Not supported | `reasoning` parameter |
| Tool calling | Supported | Supported |
| Token limit | `max_tokens` | `max_output_tokens` |
| Streaming | Supported | Not yet supported |

## When to Use

Use the Responses API when you need:
- Built-in reasoning with effort control
- OpenAI Responses API compatibility
- Simpler input format (string instead of messages)

Use Chat Completions when you need:
- Streaming responses
- Full callback system integration
- Usage tracking integration
- Response healing features

## Future Enhancements

The following features are planned but not yet implemented:
- Streaming support
- Callbacks integration
