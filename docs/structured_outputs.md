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
  # Use JSON Schema keywords (camelCase): minLength, maxLength, etc.
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
user = response.structured_output  # Hash or raises StructuredOutputError in strict mode
puts user["name"]    # => "John Doe"
puts user["age"]     # => 30
puts user["email"]   # => "john@example.com"
puts user["premium"] # => false
```

## Schema Definition DSL

The gem provides a fluent DSL for defining JSON schemas with validation rules:

### Basic Types

```ruby
schema = OpenRouter::Schema.define("example") do
  # String properties - use JSON Schema keywords (camelCase)
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

**Note**: Use JSON Schema keywords (camelCase): `minLength`, `maxLength`, `minItems`, `maxItems`, `patternProperties`, etc.

### Advanced Features

```ruby
advanced_schema = OpenRouter::Schema.define("advanced") do
  # Enum constraints
  string :type, required: true, enum: ["personal", "business"]
  
  # Pattern matching for strings
  string :phone, pattern: "^\\+?[1-9]\\d{1,14}$", description: "Phone number"
  
  # Length constraints
  string :description, 
         description: "Detailed description (minimum 50 characters for quality)", 
         minLength: 50, maxLength: 1000
  
  # Rich descriptions for better model understanding
  string :priority, enum: ["low", "medium", "high"], 
         description: "Priority level - use 'high' for urgent items"
end
```

## Schema from Hash

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
              username: { type: "string", minLength: 3 },
              profile: {
                type: "object",
                properties: {
                  bio: { type: "string" },
                  avatar_url: { type: "string", format: "uri" }
                }
              }
            },
            required: ["id", "username"]
          }
        }
      }
    },
    pagination: {
      type: "object",
      properties: {
        page: { type: "integer", minimum: 1 },
        total: { type: "integer", minimum: 0 },
        has_more: { type: "boolean" }
      },
      required: ["page", "total", "has_more"]
    }
  },
  required: ["success", "data"]
})
```

## Response Handling

### Strict vs Gentle Modes

```ruby
response = client.complete(messages, response_format: schema)

# Strict mode (default) – parses JSON and validates; may raise StructuredOutputError
data = response.structured_output

# Gentle mode – best-effort JSON parse; returns nil on failure, no validation
data = response.structured_output(mode: :gentle)  # => Hash or nil

# Check validity (may trigger healing if auto_heal_responses is true)
if response.valid_structured_output?
  puts "Valid structured output"
else
  puts "Errors: #{response.validation_errors.join(", ")}"
end
```

**Tip**: There is no `response.has_structured_output?` helper. To check "presence," either:
- Call `response.structured_output(mode: :gentle)` and test for `nil`, or
- Check that you provided `response_format` and response has content

### Native vs Forced Structured Outputs

If the model supports structured outputs natively, the gem sends your schema to the API directly. If not:

```ruby
# Configuration for unsupported models
OpenRouter.configure do |config|
  config.auto_force_on_unsupported_models = true # default - inject format instructions
  config.strict_mode = false                     # warn instead of raise on missing capability
  config.default_structured_output_mode = :strict
end
```

When `auto_force_on_unsupported_models` is `true`, the gem:
1. Injects format instructions into messages (forced extraction)
2. Parses/extracts JSON from text, optionally healing it if enabled

If `false`, using structured outputs on unsupported models raises a `CapabilityError` in strict mode.

### Error Handling

```ruby
begin
  response = client.complete(messages, response_format: schema)
  data = response.structured_output
rescue OpenRouter::StructuredOutputError => e
  puts "Failed to parse structured output: #{e.message}"
  # Fall back to regular content
  content = response.content
rescue OpenRouter::SchemaValidationError => e
  puts "Schema validation failed: #{e.message}"
  # Data might still be accessible but invalid
  data = response.structured_output
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

Different models have varying support for structured outputs:

```ruby
# Select a model that supports structured outputs
model = OpenRouter::ModelSelector.new
                                 .require(:structured_outputs)
                                 .optimize_for(:cost)
                                 .choose

response = client.complete(messages, model: model, response_format: schema)
```

### Fallback Strategies

```ruby
def safe_structured_completion(messages, schema, client)
  # Try with structured output first
  begin
    response = client.complete(messages, response_format: schema)
    return { data: response.structured_output, type: :structured }
  rescue OpenRouter::StructuredOutputError
    # Fall back to regular completion with instructions
    fallback_messages = messages + [{
      role: "system", 
      content: "Please respond with valid JSON matching this schema: #{schema.to_json_schema}"
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
# API schema sent to OpenRouter (all properties appear required)
puts JSON.pretty_generate(user_schema.to_h)

# Raw JSON Schema for local validation
puts JSON.pretty_generate(user_schema.pure_schema)

response = client.complete(messages, response_format: user_schema)
puts response.content
puts response.structured_output.inspect
```

**Key Distinction**:
- `Schema#to_h` returns the OpenRouter payload respecting your DSL required flags
- `Schema#pure_schema` returns the raw JSON Schema for local validation (when using the json-schema gem)

### Validation (Optional)

If you have the `json-schema` gem installed:

```ruby
# schema.pure_schema is the raw JSON Schema (respects your required fields)
if schema.validation_available?
  ok = schema.validate(data)                # => true/false
  errors = schema.validation_errors(data)   # => Array<String>
end
```

### Response Healing

The gem includes automatic healing for malformed JSON responses:

```ruby
# Configure healing globally
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2
end
```

**Notes**:
- In strict mode, `response.structured_output` may invoke the healer if JSON is invalid or schema validation fails and `auto_heal_responses` is `true`
- Healing sends a secondary request with instructions to fix JSON according to your schema

### Format Instructions

You can preview the system instructions the model receives when forcing:

```ruby
schema = OpenRouter::Schema.define("example") { string :title, required: true }
puts schema.get_format_instructions  # or get_format_instructions(forced: true)
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

### Common Issues

1. **Schema Too Complex**: Large, deeply nested schemas may cause model confusion
2. **Conflicting Constraints**: Ensure min/max values and enums are logically consistent
3. **Model Limitations**: Not all models support structured outputs equally well
4. **JSON Parsing Errors**: Models may return malformed JSON despite schema constraints

### Solutions

```ruby
# 1. Simplify complex schemas
simple_schema = OpenRouter::Schema.define("simple") do
  # Flatten nested structures where possible
  string :user_name, required: true
  string :user_email, required: true
  string :order_id, required: true
  number :order_total, required: true
end

# 2. Add extra validation in your code
def validate_response_data(data, custom_rules = {})
  errors = []
  
  # Custom business logic validation
  errors << "Invalid email format" unless data["email"]&.include?("@")
  errors << "Price too low" if data["price"].to_f < 0.01
  
  errors
end

# 3. Use model selection
best_model = OpenRouter::ModelSelector.new
                                      .require(:structured_outputs)
                                      .optimize_for(:performance)
                                      .choose

# 4. Implement retry logic with fallbacks
def robust_structured_completion(messages, schema, max_retries: 3)
  retries = 0
  
  begin
    response = client.complete(messages, response_format: schema)
    response.structured_output
  rescue OpenRouter::StructuredOutputError => e
    retries += 1
    if retries <= max_retries
      sleep(retries * 0.5)  # Back off
      retry
    else
      raise e
    end
  end
end
```