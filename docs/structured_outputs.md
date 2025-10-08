# Structured Outputs

The OpenRouter gem provides comprehensive support for structured outputs using JSON Schema validation. This feature ensures that AI model responses conform to specific formats, making them easy to parse and integrate into your applications.

**Important**: Add `faraday_middleware` to your Gemfile for proper JSON response parsing:

```ruby
# Gemfile
gem "faraday_middleware"
```

## Quick Start

```ruby
# Define a schema
user_schema = OpenRouter::Schema.define("user") do
  string :name, required: true, description: "User's full name", minLength: 2, maxLength: 100
  integer :age, required: true, description: "User's age", minimum: 0, maximum: 150
  string :email, required: true, description: "Valid email address"
  boolean :premium, description: "Premium account status"
  no_additional_properties
end

# Use with completion
response = client.complete(
  [{ role: "user", content: "Create a user profile for John Doe, age 30, john@example.com" }],
  model: "openai/gpt-4o",
  response_format: user_schema
)

# Access structured data
user = response.structured_output  # Validated Hash or raises StructuredOutputError
puts user["name"]    # => "John Doe"
puts user["age"]     # => 30
puts user["email"]   # => "john@example.com"
```

## Key Concepts: JSON Content vs Structured Outputs

**Important: These are fundamentally different features.**

### Regular JSON in Response Content

When you ask a model to "return JSON", you might get JSON in `response.content`, but this is just **text that happens to be formatted as JSON**:

```ruby
response = client.complete([
  { role: "user", content: "Return JSON with a name field" }
])

# response.content might be: '{"name": "John"}'
# This is just a string - NO schema validation, NO guarantees, NO auto-healing
json_text = response.content
data = JSON.parse(json_text)  # You must parse it yourself
```

**Characteristics:**
- No schema validation
- No automatic healing if malformed
- You must parse JSON manually
- Model might return text, markdown, or mixed content
- No guarantees about structure or fields

### Structured Outputs with Schema Validation

When you use `response_format: schema`, the gem ensures the response conforms to your schema:

```ruby
schema = OpenRouter::Schema.define("user") do
  string :name, required: true
  integer :age, required: true
end

response = client.complete(
  messages,
  response_format: schema  # This enables structured output mode
)

# response.structured_output => { "name" => "John", "age" => 30 }
# This is VALIDATED against your schema, with optional auto-healing
```

**Characteristics:**
- Schema-driven validation
- Automatic healing (if enabled)
- Parsed and validated automatically
- Guaranteed structure matching your schema
- Support for models without native structured output capability

**Key Difference**: `response.content` is raw text; `response.structured_output` is validated, parsed data conforming to your schema.

## Schema Definition DSL

The gem provides a fluent DSL for defining JSON schemas with validation rules. Use JSON Schema keywords in camelCase (`minLength`, `maxLength`, `minItems`, etc.):

### Basic Types

```ruby
schema = OpenRouter::Schema.define("example") do
  # String properties
  string :name, required: true, description: "Name field"
  string :category, enum: ["A", "B", "C"], description: "Category selection"
  string :content, minLength: 10, maxLength: 1000

  # Numeric properties
  integer :count, minimum: 0, maximum: 100
  number :price, minimum: 0.01, description: "Price in USD"

  # Boolean properties
  boolean :active, description: "Active status"

  # Strict schema - no extra fields allowed
  no_additional_properties
end
```

### Complex Objects and Arrays

```ruby
order_schema = OpenRouter::Schema.define("order") do
  string :id, required: true, description: "Order ID"

  # Nested object
  object :customer, required: true do
    string :name, required: true
    string :email, required: true
    object :address, required: true do
      string :street, required: true
      string :city, required: true
      string :zip_code, required: true
    end
    no_additional_properties
  end

  # Array of objects - use explicit items hash for complex objects
  array :items, required: true, description: "Order items", items: {
    type: "object",
    properties: {
      product_id: { type: "string" },
      quantity: { type: "integer", minimum: 1 },
      unit_price: { type: "number", minimum: 0 }
    },
    required: ["product_id", "quantity", "unit_price"],
    additionalProperties: false
  }

  # Simple array
  array :tags, description: "Order tags", items: { type: "string" }

  number :total, required: true, minimum: 0
  no_additional_properties
end
```

### Advanced Features

```ruby
advanced_schema = OpenRouter::Schema.define("advanced") do
  # Enum constraints
  string :type, required: true, enum: ["personal", "business"]

  # Pattern matching for strings
  string :phone, pattern: "^\\+?[1-9]\\d{1,14}$", description: "Phone number"

  # Length constraints
  string :description, minLength: 50, maxLength: 1000,
         description: "Detailed description (minimum 50 characters)"

  # Rich descriptions for better model understanding
  string :priority, enum: ["low", "medium", "high"],
         description: "Priority level - use 'high' for urgent items"
end
```

### Schema from Hash

For complex schemas or when migrating from existing JSON schemas:

```ruby
api_response_schema = OpenRouter::Schema.from_hash("api_response", {
  type: "object",
  properties: {
    success: { type: "boolean" },
    data: {
      type: "object",
      properties: {
        users: {
          type: "array",
          items: {
            type: "object",
            properties: {
              id: { type: "integer" },
              username: { type: "string", minLength: 3 }
            },
            required: ["id", "username"]
          }
        }
      }
    }
  },
  required: ["success", "data"]
})
```

## JSON Auto-Healing

The gem can automatically repair malformed JSON responses or fix schema validation failures.

### When Auto-Healing Triggers

Auto-healing activates when **both** conditions are met:
1. `config.auto_heal_responses = true` (configuration)
2. One of these failures occurs:
   - The model returns invalid JSON syntax (parse error)
   - Valid JSON fails schema validation (missing required fields, wrong types, etc.)

### How Auto-Healing Works

When healing is triggered:
1. The gem detects the JSON problem (parse error or validation failure)
2. Sends a **secondary API request** to the healer model
3. Passes the malformed JSON and your schema to the healer
4. The healer model fixes the JSON to match your schema
5. Returns the corrected, validated response

**Important**: Healing uses additional API calls, which incurs extra cost.

### Configuration

```ruby
OpenRouter.configure do |config|
  # Enable automatic healing (default: false)
  config.auto_heal_responses = true

  # Model to use for healing (should be reliable and cheap)
  config.healer_model = "openai/gpt-4o-mini"

  # Maximum healing attempts (default: 2)
  config.max_heal_attempts = 2
end
```

### How to Know if Healing Occurred

Use the callback system to track healing:

```ruby
client = OpenRouter::Client.new

client.on(:on_heal) do |healing_data|
  if healing_data[:healed]
    puts "Healing succeeded after #{healing_data[:attempts]} attempt(s)"
    puts "Original: #{healing_data[:original_content]}"
    puts "Healed: #{healing_data[:healed_content]}"
  else
    puts "Healing failed after #{healing_data[:attempts]} attempt(s)"
  end
end
```

### When Healing Fails

If healing fails after `max_heal_attempts`:
- In **strict mode**: raises `StructuredOutputError`
- In **gentle mode**: `response.structured_output(mode: :gentle)` returns `nil`

### Cost Considerations

Each healing attempt makes an additional API call:
- Original request: Uses your specified model
- Healing request: Uses the `healer_model` (typically cheaper)
- With `max_heal_attempts = 2`: Up to 3 total API calls (1 original + 2 healing)

**Best Practice**: Use a cheap, reliable model for healing (e.g., `openai/gpt-4o-mini`).

## Native vs Forced Structured Outputs

The gem works with all models, but handles them differently based on their capabilities.

### Native Structured Outputs

Models like GPT-4, Claude 3.5, and Gemini support structured outputs natively:

```ruby
response = client.complete(
  messages,
  model: "openai/gpt-4o",
  response_format: user_schema
)

# What happens:
# 1. Your schema is sent directly to the OpenRouter API
# 2. The model guarantees valid JSON conforming to your schema
# 3. No format instructions needed, no extraction required
# 4. Most reliable approach
```

**Advantages:**
- Highest reliability
- Guaranteed valid JSON structure
- No additional prompting overhead
- Faster processing

### Forced Structured Outputs (Automatic Fallback)

For models **without** native structured output support, the gem automatically "forces" structured output:

```ruby
response = client.complete(
  messages,
  model: "some-model-without-native-support",
  response_format: user_schema
)

# What happens automatically:
# 1. Gem detects model lacks native structured output capability
# 2. Injects format instructions into your messages
# 3. Adds system message: "Respond with valid JSON matching this schema: [schema]"
# 4. Model receives the injected instructions
# 5. Gem extracts and parses JSON from response text
# 6. If enabled, attempts auto-healing for invalid JSON
```

**Characteristics:**
- Works with any model
- Less reliable than native support
- May require healing for malformed responses
- Adds prompting overhead

### Configuration Options

```ruby
OpenRouter.configure do |config|
  # Option 1: Auto-force (default) - works with all models
  config.auto_force_on_unsupported_models = true

  # Option 2: Strict - only allow native support
  config.auto_force_on_unsupported_models = false
  config.strict_mode = true  # raises CapabilityError for unsupported models

  # Option 3: Warn but allow
  config.auto_force_on_unsupported_models = false
  config.strict_mode = false  # warns but continues with forcing
end
```

### How to Ensure Native Support

Use `ModelSelector` to find models with native structured output capability:

```ruby
model = OpenRouter::ModelSelector.new
  .require(:structured_outputs)
  .optimize_for(:cost)
  .choose

# This guarantees a model with native support
response = client.complete(messages, model: model, response_format: schema)
```

### Previewing Format Instructions

You can see the instructions injected when forcing:

```ruby
schema = OpenRouter::Schema.define("example") do
  string :title, required: true
end

# See what gets injected for unsupported models
puts schema.get_format_instructions(forced: true)
```

## Response Handling

### Accessing Structured Data

```ruby
response = client.complete(messages, response_format: schema)

# Strict mode (default) - validates and may raise StructuredOutputError
data = response.structured_output

# Gentle mode - best-effort parse, returns nil on failure, no validation
data = response.structured_output(mode: :gentle)  # => Hash or nil
```

### Checking Validity

```ruby
# Check if output is valid (may trigger healing if auto_heal_responses is true)
if response.valid_structured_output?
  puts "Valid structured output"
  data = response.structured_output
else
  puts "Errors: #{response.validation_errors.join(", ")}"
  # Handle validation failure
end
```

**Note**: There is no `response.has_structured_output?` helper. To check presence:
- Use `response.structured_output(mode: :gentle)` and test for `nil`, or
- Check that you provided `response_format` and response has content

### Error Handling

```ruby
begin
  response = client.complete(messages, response_format: schema)
  data = response.structured_output
rescue OpenRouter::StructuredOutputError => e
  puts "Failed to parse structured output: #{e.message}"
  # Healing failed or disabled - fall back to regular content
  content = response.content
rescue OpenRouter::SchemaValidationError => e
  puts "Schema validation failed: #{e.message}"
  # Data might still be accessible in gentle mode
  data = response.structured_output(mode: :gentle)
end
```

## Best Practices

### Schema Design

1. **Be Specific**: Provide clear descriptions for better model understanding
2. **Use Constraints**: Set appropriate min/max values, string lengths, and enums
3. **Required Fields**: Mark essential fields as required
4. **No Extra Properties**: Use `no_additional_properties` for strict schemas

```ruby
# Good: Clear, constrained schema
product_schema = OpenRouter::Schema.define("product") do
  string :name, required: true, description: "Product name (2-100 characters)",
         minLength: 2, maxLength: 100
  string :category, required: true, enum: ["electronics", "clothing", "books"],
         description: "Product category"
  number :price, required: true, minimum: 0.01, maximum: 999999.99,
         description: "Price in USD"
  integer :stock, required: true, minimum: 0,
          description: "Current stock quantity"
  no_additional_properties
end
```

### Model Selection

Use `ModelSelector` to find models with appropriate capabilities:

```ruby
# Select a model that supports structured outputs natively
model = OpenRouter::ModelSelector.new
  .require(:structured_outputs)
  .optimize_for(:cost)
  .choose

response = client.complete(messages, model: model, response_format: schema)
```

### Fallback Strategies

```ruby
def safe_structured_completion(messages, schema, client)
  begin
    response = client.complete(messages, response_format: schema)
    return { data: response.structured_output, type: :structured }
  rescue OpenRouter::StructuredOutputError
    # Healing failed - fall back to manual parsing
    fallback_messages = messages + [{
      role: "system",
      content: "Please respond with valid JSON matching this schema: #{schema.to_h[:schema]}"
    }]

    response = client.complete(fallback_messages)
    begin
      data = JSON.parse(response.content)
      return { data: data, type: :parsed }
    rescue JSON::ParserError
      return { data: response.content, type: :text }
    end
  end
end
```

### Debugging

```ruby
# View the schema sent to OpenRouter API
puts JSON.pretty_generate(user_schema.to_h)

# View the raw JSON Schema for local validation
puts JSON.pretty_generate(user_schema.pure_schema)

# Inspect response
response = client.complete(messages, response_format: user_schema)
puts response.content
puts response.structured_output.inspect
```

**Key Distinction**:
- `Schema#to_h` - OpenRouter API payload (all properties marked required for API compatibility)
- `Schema#pure_schema` - Raw JSON Schema respecting your DSL `required` flags

### Optional Validation

If you have the `json-schema` gem installed, you can validate data locally:

```ruby
if schema.validation_available?
  ok = schema.validate(data)                # => true/false
  errors = schema.validation_errors(data)   # => Array<String>
end
```

## Common Patterns

### API Response Wrapper

```ruby
api_wrapper_schema = OpenRouter::Schema.define("api_wrapper") do
  boolean :success, required: true, description: "Whether the operation succeeded"
  string :message, description: "Human-readable message"
  object :data, description: "Response payload"
  array :errors, description: "List of error messages", items: { type: "string" }
end
```

### Data Extraction

```ruby
extraction_schema = OpenRouter::Schema.define("extraction") do
  array :entities, required: true, description: "Extracted entities" do
    items do
      object do
        string :type, required: true, enum: ["person", "organization", "location"]
        string :name, required: true, description: "Entity name"
        number :confidence, required: true, minimum: 0, maximum: 1
        integer :start_pos, description: "Start position in text"
        integer :end_pos, description: "End position in text"
      end
    end
  end

  object :summary, required: true do
    string :main_topic, required: true
    array :key_points, required: true, items: { type: "string" }
    string :sentiment, enum: ["positive", "negative", "neutral"]
  end
end
```

### Configuration Objects

```ruby
config_schema = OpenRouter::Schema.define("config") do
  object :database, required: true do
    string :host, required: true
    integer :port, required: true, minimum: 1, maximum: 65535
    string :name, required: true
    boolean :ssl, default: true
  end

  object :cache do
    string :type, enum: ["redis", "memcached", "memory"], default: "memory"
    integer :ttl, minimum: 1, default: 3600
  end

  array :features, items: { type: "string" }
  no_additional_properties
end
```

## Troubleshooting

### Common Questions

**Q: Why is my JSON still invalid after healing?**

Healing can fail if:
- The original response is too corrupted to repair
- The healer model misunderstands your schema
- `max_heal_attempts` is too low

Solutions:
- Increase `max_heal_attempts` to 3-5
- Use a more capable healer model (e.g., `openai/gpt-4o`)
- Simplify your schema
- Check healing callbacks to see failure details

**Q: How do I know if forcing is being used vs native support?**

Check the model's capabilities:

```ruby
model_info = OpenRouter::ModelRegistry.get_model_info("model-name")
if model_info[:capabilities].include?(:structured_outputs)
  puts "Native support"
else
  puts "Will use forcing (if auto_force_on_unsupported_models is true)"
end
```

Or use callbacks:

```ruby
client.on(:before_request) do |params|
  if params[:messages].any? { |m| m[:content]&.include?("valid JSON") }
    puts "Forcing detected - format instructions injected"
  end
end
```

**Q: What's the cost impact of healing?**

Each healing attempt is a separate API call:
- Original request: Your specified model (e.g., `gpt-4o`: $0.0025/1k input tokens)
- Healing request: Healer model (e.g., `gpt-4o-mini`: $0.00015/1k input tokens)

With `max_heal_attempts = 2` and both attempts failing, you pay for 3 API calls total.

**Best Practice**: Use a cheap healer model and monitor healing frequency with callbacks.

**Q: How do I disable healing for specific requests?**

Healing is global configuration. To disable for specific requests:

```ruby
# Option 1: Use gentle mode (no validation, no healing)
data = response.structured_output(mode: :gentle)

# Option 2: Temporarily disable healing
original_heal_setting = OpenRouter.configuration.auto_heal_responses
OpenRouter.configuration.auto_heal_responses = false
response = client.complete(messages, response_format: schema)
OpenRouter.configuration.auto_heal_responses = original_heal_setting
```

### Common Issues

**1. Schema Too Complex**

Large, deeply nested schemas may cause model confusion.

Solution: Flatten structures where possible:

```ruby
# Instead of deep nesting:
# user -> profile -> settings -> notifications -> email -> frequency

# Use flatter structure:
simple_schema = OpenRouter::Schema.define("simple") do
  string :user_name, required: true
  string :notification_email_frequency, enum: ["daily", "weekly", "never"]
end
```

**2. Conflicting Constraints**

Ensure min/max values and enums are logically consistent:

```ruby
# Bad: impossible constraints
string :code, minLength: 10, maxLength: 5  # impossible!

# Good: logical constraints
string :code, minLength: 5, maxLength: 10
```

**3. Model Limitations**

Not all models support structured outputs equally well.

Solution: Use `ModelSelector` to find capable models:

```ruby
model = OpenRouter::ModelSelector.new
  .require(:structured_outputs)
  .optimize_for(:performance)
  .choose
```

**4. JSON Parsing Errors**

Models may return malformed JSON despite constraints.

Solutions:
- Enable auto-healing: `config.auto_heal_responses = true`
- Use models with native structured output support
- Implement retry logic:

```ruby
def robust_structured_completion(messages, schema, max_retries: 3)
  retries = 0

  begin
    response = client.complete(messages, response_format: schema)
    response.structured_output
  rescue OpenRouter::StructuredOutputError => e
    retries += 1
    if retries <= max_retries
      sleep(retries * 0.5)  # Exponential backoff
      retry
    else
      raise e
    end
  end
end
```

### Getting Help

For additional assistance:
- Check the [examples directory](../examples/) for working code samples
- Review the [observability documentation](observability.md) for callback debugging
- Open an issue on [GitHub](https://github.com/estiens/open_router_enhanced/issues) with:
  - Your schema definition
  - The model used
  - Error messages and stack traces
  - Whether healing is enabled
