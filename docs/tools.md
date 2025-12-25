# Tool Calling

The OpenRouter gem provides comprehensive support for OpenRouter's function calling API with an intuitive Ruby DSL for defining and managing tools. This enables AI models to interact with external functions and APIs in a structured, type-safe manner.

## Quick Start

```ruby
# Define a tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  description "Get current weather for a location"
  
  parameters do
    string :location, required: true, description: "City name or coordinates"
    string :units, enum: ["celsius", "fahrenheit"], description: "Temperature units"
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
    result = fetch_weather(tool_call.arguments["location"])
    puts result
  end
end
```

## Tool Definition DSL

The gem provides a fluent DSL for defining tools with comprehensive parameter validation:

### Basic Tool Structure

```ruby
tool = OpenRouter::Tool.define do
  name "tool_name"
  description "Clear description of what this tool does"
  
  parameters do
    # Parameter definitions go here
  end
end
```

### Parameter Types

```ruby
comprehensive_tool = OpenRouter::Tool.define do
  name "comprehensive_example"
  description "Example showing all parameter types"
  
  parameters do
    # String parameters
    string :name, required: true, description: "Required string parameter"
    string :category, enum: ["A", "B", "C"], description: "String with allowed values"
    string :content, minLength: 10, maxLength: 1000, description: "String with length constraints"
    string :pattern_field, pattern: "^[A-Z]{2,3}$", description: "String with regex pattern"
    
    # Numeric parameters
    integer :count, required: true, minimum: 1, maximum: 100, description: "Integer with range"
    number :price, minimum: 0.01, description: "Floating point number"
    
    # Boolean parameters
    boolean :enabled, description: "Boolean flag"
    
    # Array parameters
    array :tags, description: "Array of strings", items: { type: "string" }
    array :numbers, description: "Array of numbers", items: { type: "number", minimum: 0 }
    
    # Object parameters (nested)
    object :metadata do
      string :key, required: true
      string :value, required: true
      integer :priority, minimum: 1, maximum: 10
    end
  end
end
```

### Complex Nested Objects

```ruby
order_processing_tool = OpenRouter::Tool.define do
  name "process_order"
  description "Process a customer order"
  
  parameters do
    string :order_id, required: true, description: "Unique order identifier"
    
    # Customer object
    object :customer, required: true do
      string :name, required: true, description: "Customer full name"
      string :email, required: true, description: "Customer email address"
      
      # Nested address object
      object :address, required: true do
        string :street, required: true
        string :city, required: true
        string :state, required: true
        string :zip_code, required: true, pattern: "^\\d{5}(-\\d{4})?$"
        string :country, default: "US", enum: ["US", "CA", "MX"]
      end
    end
    
    # Array of order items
    array :items, required: true, description: "Order items" do
      items do
        object do
          string :product_id, required: true
          string :product_name, required: true
          integer :quantity, required: true, minimum: 1
          number :unit_price, required: true, minimum: 0.01
          array :options, description: "Product options", items: { type: "string" }
        end
      end
    end
    
    # Payment information
    object :payment do
      string :method, required: true, enum: ["credit_card", "debit_card", "paypal", "bank_transfer"]
      number :amount, required: true, minimum: 0.01
      string :currency, default: "USD", enum: ["USD", "EUR", "GBP", "CAD"]
    end
    
    # Optional metadata
    object :metadata do
      string :source, enum: ["web", "mobile", "api"]
      string :campaign_id
      boolean :gift_order, default: false
      string :special_instructions
    end
  end
end
```

### Array Parameters with Complex Items

```ruby
data_analysis_tool = OpenRouter::Tool.define do
  name "analyze_data"
  description "Analyze datasets with various configurations"
  
  parameters do
    # Array of simple values
    array :column_names, required: true, description: "Data column names", items: { type: "string" }
    
    # Array of numbers with constraints
    array :thresholds, description: "Analysis thresholds", items: { 
      type: "number", 
      minimum: 0, 
      maximum: 100 
    }
    
    # Array of objects - use explicit items hash for complex objects
    array :filters, description: "Data filters", items: {
      type: "object",
      properties: {
        column: { type: "string", description: "Column to filter" },
        operator: { type: "string", enum: ["eq", "ne", "gt", "lt", "in", "not_in"] },
        value_type: { type: "string", enum: ["string", "number", "array"] },
        value: { type: "string", description: "Filter value (format depends on value_type)" }
      },
      required: ["column", "operator", "value_type"],
      additionalProperties: false
    }
    
    # Array with min/max items
    array :metrics, required: true, description: "Metrics to calculate", 
          minItems: 1, maxItems: 10, items: { 
            type: "string", 
            enum: ["mean", "median", "mode", "std", "var", "min", "max"] 
          }
  end
end
```

## Tool Definition from Hash

For complex tools or when migrating from existing OpenAPI/JSON schemas:

```ruby
# Define from hash (useful for complex tools or API imports)
api_tool = OpenRouter::Tool.from_hash({
  name: "api_request",
  description: "Make HTTP requests to external APIs",
  parameters: {
    type: "object",
    properties: {
      url: {
        type: "string",
        format: "uri",
        description: "Target URL for the request"
      },
      method: {
        type: "string",
        enum: ["GET", "POST", "PUT", "DELETE", "PATCH"],
        default: "GET"
      },
      headers: {
        type: "object",
        patternProperties: {
          "^[A-Za-z-]+$": { type: "string" }
        },
        description: "HTTP headers as key-value pairs"
      },
      body: {
        type: "string",
        description: "Request body (JSON string for POST/PUT)"
      },
      timeout: {
        type: "integer",
        minimum: 1,
        maximum: 300,
        default: 30,
        description: "Request timeout in seconds"
      }
    },
    required: ["url"]
  }
})

# Convert from OpenAPI 3.0 spec
def tool_from_openapi_operation(operation_spec)
  OpenRouter::Tool.from_hash({
    name: operation_spec[:operationId],
    description: operation_spec[:summary] || operation_spec[:description],
    parameters: operation_spec.dig(:requestBody, :content, :"application/json", :schema) || {
      type: "object",
      properties: {},
      required: []
    }
  })
end
```

## Using Tools in Completions

### Basic Usage

```ruby
tools = [weather_tool, calculator_tool, search_tool]

response = client.complete(
  [{ role: "user", content: "What's the weather in Tokyo and what's 15 * 23?" }],
  model: "anthropic/claude-3.5-sonnet",
  tools: tools,
  tool_choice: "auto"  # Let the model decide which tools to use
)
```

### Tool Choice Options

```ruby
# Auto - let model decide when to use tools
response = client.complete(messages, tools: tools, tool_choice: "auto")

# Required - force model to use a tool
response = client.complete(messages, tools: tools, tool_choice: "required")

# None - disable tool usage for this request
response = client.complete(messages, tools: tools, tool_choice: "none")

# Specific tool - force use of a particular tool
response = client.complete(messages, tools: tools, tool_choice: "get_weather")
```

### Handling Tool Calls

```ruby
def handle_completion_with_tools(messages, tools)
  response = client.complete(messages, tools: tools, tool_choice: "auto")
  
  unless response.has_tool_calls?
    return response.content  # Regular text response
  end
  
  # Process each tool call
  conversation = messages.dup
  conversation << response.to_message
  
  response.tool_calls.each do |tool_call|
    puts "Executing tool: #{tool_call.name}"
    puts "Arguments: #{tool_call.arguments.inspect}"
    
    # Execute the tool
    result = execute_tool(tool_call)
    
    # Add result to conversation
    conversation << tool_call.to_result_message(result)
  end
  
  # Get final response
  final_response = client.complete(conversation, tools: tools)
  final_response.content
end

def execute_tool(tool_call)
  case tool_call.name
  when "get_weather"
    fetch_weather(tool_call.arguments["location"], tool_call.arguments["units"])
  when "calculate"
    perform_calculation(tool_call.arguments["expression"])
  when "search_web"
    search_web(tool_call.arguments["query"], tool_call.arguments["max_results"])
  else
    { error: "Unknown tool: #{tool_call.name}" }
  end
rescue => e
  { error: "Tool execution failed: #{e.message}" }
end
```

## ToolCall Objects

When a model uses tools, you receive `ToolCall` objects with helpful methods:

### ToolCall Object

Properties and helpers you can rely on:

- `id`: String
- `type`: String (e.g., "function")
- `name`: tool function name
- `arguments_string`: raw JSON string
- `arguments`: parsed Hash (raises `ToolCallError` on invalid JSON)
- `to_message`: assistant message with the original `tool_calls` field
- `to_result_message(result)`: tool message payload with `tool_call_id` and JSON content
- `execute { |name, arguments| ... }`: returns an `OpenRouter::ToolResult` (success/failure), where:
  - `success?`: boolean
  - `to_message`: a tool message suitable for conversation continuation

Example:

```ruby
response.tool_calls.each do |tool_call|
  tool_result = tool_call.execute do |name, args|
    case name
    when "get_weather" then fetch_weather(args["location"], args["units"])
    else { error: "unknown tool: #{name}" }
    end
  end

  conversation << tool_result.to_message
end
```

## Advanced Usage Patterns

### Tool Validation and Error Handling

```ruby
def safe_tool_execution(tool_call, tools)
  # Validate arguments against tool schema
  unless tool_call.valid?(tools: tools)
    return {
      error: "Invalid arguments",
      details: tool_call.validation_errors(tools: tools)
    }
  end
  
  begin
    # Execute with timeout
    Timeout::timeout(30) do
      execute_tool_safely(tool_call)
    end
  rescue Timeout::Error
    { error: "Tool execution timed out" }
  rescue => e
    { error: "Tool execution failed: #{e.message}" }
  end
end

def execute_tool_safely(tool_call)
  case tool_call.name
  when "file_operation"
    # Validate file paths for security
    path = tool_call.arguments["path"]
    raise "Invalid path" unless safe_path?(path)
    
    File.read(path)
  when "api_request"
    # Validate URLs for security
    url = tool_call.arguments["url"]
    raise "Invalid URL" unless safe_url?(url)
    
    Net::HTTP.get(URI(url))
  end
end

def safe_path?(path)
  # Prevent directory traversal
  !path.include?("..") && path.start_with?("/safe/directory/")
end

def safe_url?(url)
  # Only allow specific domains
  uri = URI.parse(url)
  ["api.example.com", "safe-api.com"].include?(uri.host)
end
```

### Streaming Tool Results

```ruby
def streaming_tool_execution(tool_call)
  case tool_call.name
  when "large_data_processing"
    # Stream results for long-running operations
    results = []
    
    process_large_dataset(tool_call.arguments) do |chunk|
      results << chunk
      yield({ status: "processing", progress: results.size, partial_data: chunk })
    end
    
    { status: "complete", data: results }
  end
end

# Usage with streaming
handle_tool_call_with_streaming(tool_call) do |partial_result|
  puts "Progress: #{partial_result[:progress]} items processed"
end
```

### Tool Composition and Chaining

```ruby
class ToolChain
  def initialize(client, tools)
    @client = client
    @tools = tools
    @conversation = []
  end
  
  def execute(initial_message, max_iterations: 10)
    @conversation = [{ role: "user", content: initial_message }]
    iterations = 0
    
    while iterations < max_iterations
      response = @client.complete(@conversation, tools: @tools, tool_choice: "auto")
      @conversation << response.to_message
      
      if response.has_tool_calls?
        # Execute all tool calls
        response.tool_calls.each do |tool_call|
          result = execute_tool(tool_call)
          @conversation << tool_call.to_result_message(result)
        end
        iterations += 1
      else
        # Final response without tool calls
        return response.content
      end
    end
    
    "Maximum iterations reached"
  end
  
  private
  
  def execute_tool(tool_call)
    # Tool execution logic here
  end
end

# Usage
chain = ToolChain.new(client, [search_tool, calculator_tool, weather_tool])
result = chain.execute("Plan a trip to Tokyo: check weather, calculate budget for 5 days, and find flights")
```

### Tool Result Caching

```ruby
class CachedToolExecutor
  def initialize(cache_ttl: 3600)  # 1 hour cache
    @cache = {}
    @cache_ttl = cache_ttl
  end
  
  def execute(tool_call)
    cache_key = generate_cache_key(tool_call)
    cached_result = @cache[cache_key]
    
    if cached_result && Time.now - cached_result[:timestamp] < @cache_ttl
      return cached_result[:result]
    end
    
    result = perform_tool_execution(tool_call)
    @cache[cache_key] = { result: result, timestamp: Time.now }
    result
  end
  
  private
  
  def generate_cache_key(tool_call)
    "#{tool_call.name}:#{tool_call.arguments.to_json}"
  end
  
  def perform_tool_execution(tool_call)
    # Actual tool execution
  end
end
```

## Tool Organization and Management

### Tool Registry

```ruby
class ToolRegistry
  def initialize
    @tools = {}
  end
  
  def register(tool)
    @tools[tool.name] = tool
  end
  
  def get(name)
    @tools[name]
  end
  
  def all
    @tools.values
  end
  
  def for_capabilities(*capabilities)
    # Return tools that provide specific capabilities
    @tools.values.select do |tool|
      capabilities.all? { |cap| tool_provides_capability?(tool, cap) }
    end
  end
  
  private
  
  def tool_provides_capability?(tool, capability)
    # Define your capability mapping logic
    case capability
    when :web_search
      ["search_web", "google_search"].include?(tool.name)
    when :calculations
      ["calculator", "math_eval"].include?(tool.name)
    when :data_analysis
      ["analyze_data", "statistics"].include?(tool.name)
    else
      false
    end
  end
end

# Usage
registry = ToolRegistry.new
registry.register(search_tool)
registry.register(calculator_tool)
registry.register(weather_tool)

# Get tools for specific capabilities
analysis_tools = registry.for_capabilities(:calculations, :data_analysis)
```

### Tool Categories

```ruby
module Tools
  module Web
    SEARCH = OpenRouter::Tool.define do
      name "web_search"
      description "Search the web for information"
      parameters do
        string :query, required: true
        integer :max_results, minimum: 1, maximum: 20, default: 10
      end
    end
    
    SCRAPE = OpenRouter::Tool.define do
      name "web_scrape"
      description "Extract content from a web page"
      parameters do
        string :url, required: true
        array :selectors, items: { type: "string" }
      end
    end
  end
  
  module Math
    CALCULATOR = OpenRouter::Tool.define do
      name "calculator"
      description "Perform mathematical calculations"
      parameters do
        string :expression, required: true
      end
    end
    
    STATISTICS = OpenRouter::Tool.define do
      name "statistics"
      description "Calculate statistical measures"
      parameters do
        array :data, required: true, items: { type: "number" }
        array :measures, items: { 
          type: "string", 
          enum: ["mean", "median", "std", "var"] 
        }
      end
    end
  end
  
  module Data
    FILE_READ = OpenRouter::Tool.define do
      name "file_read"
      description "Read file contents"
      parameters do
        string :path, required: true
        string :encoding, default: "utf-8"
      end
    end
    
    DATABASE_QUERY = OpenRouter::Tool.define do
      name "database_query"
      description "Query database"
      parameters do
        string :query, required: true
        array :parameters, items: { type: "string" }
      end
    end
  end
end

# Usage
web_tools = [Tools::Web::SEARCH, Tools::Web::SCRAPE]
math_tools = [Tools::Math::CALCULATOR, Tools::Math::STATISTICS]
all_tools = web_tools + math_tools + [Tools::Data::FILE_READ]
```

## Model Selection for Tool Calling

```ruby
# Select models that support function calling
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

# Use with tools
response = client.complete(
  messages,
  model: model,
  tools: tools,
  tool_choice: "auto"
)
```

## Testing Tools

### Unit Testing Tool Definitions

```ruby
# spec/tools/weather_tool_spec.rb
RSpec.describe "Weather Tool" do
  let(:tool) { Tools::Weather::CURRENT }
  
  it "has correct name and description" do
    expect(tool.name).to eq("get_current_weather")
    expect(tool.description).to include("current weather")
  end
  
  it "defines required parameters" do
    schema = tool.to_json_schema
    expect(schema[:parameters][:required]).to include("location")
  end
  
  it "validates parameter constraints" do
    schema = tool.to_json_schema
    units_prop = schema[:parameters][:properties][:units]
    expect(units_prop[:enum]).to include("celsius", "fahrenheit")
  end
end
```

### Integration Testing

```ruby
# spec/integration/tool_calling_spec.rb
RSpec.describe "Tool Calling Integration" do
  let(:client) { OpenRouter::Client.new }
  let(:tools) { [weather_tool, calculator_tool] }
  
  it "handles tool calls correctly", :vcr do
    response = client.complete(
      [{ role: "user", content: "What's 2+2 and weather in Paris?" }],
      model: "anthropic/claude-3.5-sonnet",
      tools: tools,
      tool_choice: "auto"
    )
    
    expect(response.has_tool_calls?).to be true
    expect(response.tool_calls.map(&:name)).to include("calculator")
  end
  
  it "validates tool call arguments" do
    # Mock response with invalid arguments
    mock_response = build_mock_response_with_invalid_tool_call

    tool_call = mock_response.tool_calls.first
    expect(tool_call.valid?(tools: tools)).to be false
    expect(tool_call.validation_errors(tools: tools)).to include(/required.*missing/)
  end
end
```

### Mock Tool Execution

```ruby
class MockToolExecutor
  def initialize(responses = {})
    @responses = responses
  end
  
  def execute(tool_call)
    key = "#{tool_call.name}:#{tool_call.arguments.to_json}"
    @responses[key] || @responses[tool_call.name] || { error: "No mock response defined" }
  end
end

# Usage in tests
mock_executor = MockToolExecutor.new({
  "get_weather" => { temperature: 22, condition: "sunny" },
  "calculator" => { result: 42 }
})

result = mock_executor.execute(tool_call)
expect(result[:temperature]).to eq(22)
```

## Security Considerations

### Input Validation

```ruby
def validate_tool_arguments(tool_call)
  case tool_call.name
  when "file_operation"
    path = tool_call.arguments["path"]
    
    # Prevent directory traversal
    raise "Invalid path" if path.include?("..")
    
    # Restrict to allowed directories
    allowed_dirs = ["/app/data", "/tmp/uploads"]
    raise "Forbidden path" unless allowed_dirs.any? { |dir| path.start_with?(dir) }
    
  when "api_request"
    url = tool_call.arguments["url"]
    uri = URI.parse(url)
    
    # Whitelist allowed domains
    allowed_hosts = ["api.example.com", "trusted-service.com"]
    raise "Forbidden host" unless allowed_hosts.include?(uri.host)
    
    # Prevent internal network access
    raise "Internal network access forbidden" if internal_ip?(uri.host)
  end
end

def internal_ip?(hostname)
  ip = Resolv.getaddress(hostname)
  IPAddr.new("10.0.0.0/8").include?(ip) ||
  IPAddr.new("172.16.0.0/12").include?(ip) ||
  IPAddr.new("192.168.0.0/16").include?(ip) ||
  IPAddr.new("127.0.0.0/8").include?(ip)
rescue Resolv::ResolvError
  false
end
```

### Rate Limiting

```ruby
class RateLimitedToolExecutor
  def initialize(limit: 10, period: 60)  # 10 calls per minute
    @limit = limit
    @period = period
    @call_times = []
  end
  
  def execute(tool_call)
    now = Time.now
    
    # Remove old calls outside the time window
    @call_times.reject! { |time| now - time > @period }
    
    # Check rate limit
    if @call_times.size >= @limit
      raise "Rate limit exceeded: #{@limit} calls per #{@period} seconds"
    end
    
    @call_times << now
    perform_tool_execution(tool_call)
  end
end
```

### Sandboxing

```ruby
require 'timeout'

def execute_tool_in_sandbox(tool_call)
  # Set resource limits
  original_rlimits = set_resource_limits
  
  begin
    # Execute with timeout
    Timeout::timeout(30) do
      case tool_call.name
      when "code_execution"
        execute_code_safely(tool_call.arguments["code"])
      when "file_processing"
        process_file_safely(tool_call.arguments["file_path"])
      else
        execute_tool_normally(tool_call)
      end
    end
  ensure
    # Restore original limits
    restore_resource_limits(original_rlimits)
  end
end

def set_resource_limits
  original = {}
  
  # Limit memory usage (100MB)
  original[:memory] = Process.getrlimit(:AS)
  Process.setrlimit(:AS, 100 * 1024 * 1024)
  
  # Limit CPU time (10 seconds)
  original[:cpu] = Process.getrlimit(:CPU)
  Process.setrlimit(:CPU, 10)
  
  original
end
```

## Best Practices

### 1. Clear Tool Descriptions

```ruby
# Good: Clear, specific description
search_tool = OpenRouter::Tool.define do
  name "web_search"
  description "Search the internet for current information about any topic. Returns relevant web pages with titles, URLs, and snippets. Use this when you need up-to-date information not in your training data."
  
  parameters do
    string :query, required: true, 
           description: "Search query - be specific and include relevant keywords. Example: 'weather forecast London UK' or 'latest iPhone 15 reviews'"
    integer :max_results, 
            minimum: 1, maximum: 10, default: 5,
            description: "Number of search results to return (1-10)"
  end
end

# Bad: Vague description
bad_tool = OpenRouter::Tool.define do
  name "search"
  description "Search for stuff"
  parameters do
    string :q, required: true
  end
end
```

### 2. Parameter Validation

```ruby
# Use comprehensive validation
robust_tool = OpenRouter::Tool.define do
  name "user_management"
  description "Manage user accounts"
  
  parameters do
    string :action, required: true, enum: ["create", "update", "delete", "get"]
    string :user_id, pattern: "^[a-zA-Z0-9_-]{1,50}$", 
           description: "Alphanumeric user ID (1-50 characters)"
    string :email, pattern: "^[^@]+@[^@]+\\.[^@]+$",
           description: "Valid email address"
    integer :age, minimum: 13, maximum: 120,
            description: "User age (13-120)"
  end
end
```

### 3. Error Handling

```ruby
def robust_tool_execution(tool_call, tools)
  # Validate first
  unless tool_call.valid?(tools: tools)
    return {
      success: false,
      error: "Invalid arguments",
      details: tool_call.validation_errors(tools: tools)
    }
  end
  
  begin
    result = execute_tool(tool_call)
    { success: true, data: result }
  rescue => e
    {
      success: false,
      error: "Execution failed: #{e.message}",
      tool_name: tool_call.name,
      timestamp: Time.now.iso8601
    }
  end
end
```

### 4. Tool Documentation

```ruby
# Document your tools
module ToolDocumentation
  WEATHER = {
    name: "get_weather",
    description: "Retrieves current weather information",
    usage_examples: [
      "Get weather for a city: { location: 'London' }",
      "Get weather with units: { location: 'Tokyo', units: 'celsius' }"
    ],
    return_format: {
      temperature: "number",
      condition: "string",
      humidity: "number (0-100)",
      wind_speed: "number (km/h)"
    },
    error_cases: [
      "Location not found: returns { error: 'Location not found' }",
      "API unavailable: returns { error: 'Weather service unavailable' }"
    ]
  }
end
```

## Common Tool Patterns

### Database Tools

```ruby
database_tool = OpenRouter::Tool.define do
  name "database_query"
  description "Execute read-only database queries"
  
  parameters do
    string :query, required: true, 
           description: "SQL SELECT query (read-only)"
    array :parameters, 
          items: { type: "string" },
          description: "Query parameters for prepared statements"
    integer :limit, minimum: 1, maximum: 1000, default: 100,
            description: "Maximum number of rows to return"
  end
end
```

### File System Tools

```ruby
file_tool = OpenRouter::Tool.define do
  name "file_operations"
  description "Perform file system operations"
  
  parameters do
    string :operation, required: true, 
           enum: ["read", "write", "list", "exists", "size"]
    string :path, required: true,
           description: "File or directory path"
    string :content, 
           description: "Content to write (required for write operation)"
    string :encoding, default: "utf-8",
           enum: ["utf-8", "ascii", "binary"]
  end
end
```

### API Integration Tools

```ruby
api_tool = OpenRouter::Tool.define do
  name "external_api"
  description "Call external REST APIs"

  parameters do
    string :endpoint, required: true,
           description: "API endpoint URL"
    string :method, default: "GET",
           enum: ["GET", "POST", "PUT", "DELETE"]
    object :headers,
           description: "HTTP headers"
    object :body,
           description: "Request body for POST/PUT"
    integer :timeout, minimum: 1, maximum: 300, default: 30,
            description: "Request timeout in seconds"
  end
end
```

### Model Delegation Tool (AI-as-a-Tool)

A powerful pattern where one model can delegate tasks to a different, specialized model and incorporate the results. This enables "multi-agent" workflows where you route specific subtasks to the best model for the job.

```ruby
# Define a tool that calls a different model
specialist_tool = OpenRouter::Tool.define do
  name "consult_specialist"
  description "Consult a specialist AI model for specific tasks like code review, math, or creative writing. Use this when a task would benefit from a specialized model's expertise."

  parameters do
    string :task_type, required: true,
           enum: ["code_review", "math_reasoning", "creative_writing", "analysis"],
           description: "Type of task to delegate"
    string :prompt, required: true,
           description: "The specific question or task for the specialist"
    string :context,
           description: "Additional context to provide to the specialist"
  end
end

# Tool executor that routes to different models
class ModelDelegationExecutor
  MODEL_ROUTING = {
    "code_review" => "anthropic/claude-sonnet-4",
    "math_reasoning" => "deepseek/deepseek-r1",
    "creative_writing" => "anthropic/claude-sonnet-4",
    "analysis" => "openai/gpt-4o"
  }.freeze

  def initialize(client)
    @client = client
  end

  def execute(tool_call)
    args = tool_call.arguments
    task_type = args["task_type"]
    prompt = args["prompt"]
    context = args["context"]

    # Select the appropriate specialist model
    specialist_model = MODEL_ROUTING[task_type]

    # Build the specialist prompt
    specialist_messages = [
      {
        role: "system",
        content: system_prompt_for(task_type)
      },
      {
        role: "user",
        content: context ? "Context: #{context}\n\nTask: #{prompt}" : prompt
      }
    ]

    # Call the specialist model
    specialist_response = @client.complete(
      specialist_messages,
      model: specialist_model
    )

    {
      specialist_model: specialist_model,
      task_type: task_type,
      response: specialist_response.content
    }
  end

  private

  def system_prompt_for(task_type)
    case task_type
    when "code_review"
      "You are an expert code reviewer. Analyze the code for bugs, security issues, and improvements."
    when "math_reasoning"
      "You are a mathematics expert. Solve problems step by step with clear explanations."
    when "creative_writing"
      "You are a creative writing expert. Help with storytelling, prose, and narrative."
    when "analysis"
      "You are an analytical expert. Provide thorough, well-reasoned analysis."
    end
  end
end

# Usage in a tool loop
client = OpenRouter::Client.new
executor = ModelDelegationExecutor.new(client)

messages = [
  { role: "user", content: "Review this Ruby code and also help me solve: what's the integral of x^2?" }
]

# Primary model (orchestrator)
response = client.complete(
  messages,
  model: "openai/gpt-4o-mini",  # Fast, cheap orchestrator
  tools: [specialist_tool],
  tool_choice: "auto"
)

if response.has_tool_calls?
  messages << response.to_message

  response.tool_calls.each do |tool_call|
    puts "Delegating #{tool_call.arguments['task_type']} to specialist..."

    result = executor.execute(tool_call)
    puts "Specialist (#{result[:specialist_model]}) responded"

    messages << tool_call.to_result_message(result)
  end

  # Get final synthesized response from orchestrator
  final_response = client.complete(
    messages,
    model: "openai/gpt-4o-mini",
    tools: [specialist_tool]
  )

  puts final_response.content
end
```

#### Advanced: Multi-Model Reasoning Pipeline

```ruby
# Chain multiple specialist consultations for complex tasks
class ReasoningPipeline
  def initialize(client)
    @client = client
  end

  def solve_complex_problem(problem)
    # Step 1: Break down the problem with a reasoning model
    breakdown = consult_model(
      model: "deepseek/deepseek-r1",
      system: "Break this problem into smaller, solvable steps.",
      prompt: problem
    )

    # Step 2: Solve each step with appropriate specialists
    solutions = breakdown[:steps].map do |step|
      model = select_model_for_step(step)
      consult_model(
        model: model,
        system: "Solve this specific step thoroughly.",
        prompt: step
      )
    end

    # Step 3: Synthesize with a capable general model
    consult_model(
      model: "anthropic/claude-sonnet-4",
      system: "Synthesize these solutions into a coherent final answer.",
      prompt: "Problem: #{problem}\n\nStep solutions:\n#{solutions.join("\n\n")}"
    )
  end

  private

  def consult_model(model:, system:, prompt:)
    response = @client.complete(
      [
        { role: "system", content: system },
        { role: "user", content: prompt }
      ],
      model: model
    )
    response.content
  end

  def select_model_for_step(step)
    # Route based on step content
    case step
    when /code|programming|function/i
      "anthropic/claude-sonnet-4"
    when /math|calculate|equation/i
      "deepseek/deepseek-r1"
    when /research|analyze|compare/i
      "openai/gpt-4o"
    else
      "openai/gpt-4o-mini"
    end
  end
end
```

#### Cost-Aware Model Routing

```ruby
# Route based on task complexity to optimize cost
class CostAwareRouter
  MODELS_BY_TIER = {
    cheap: "openai/gpt-4o-mini",
    standard: "openai/gpt-4o",
    premium: "anthropic/claude-sonnet-4",
    reasoning: "deepseek/deepseek-r1"
  }.freeze

  def initialize(client)
    @client = client
  end

  def route_task(task, complexity: :auto)
    tier = complexity == :auto ? estimate_complexity(task) : complexity
    model = MODELS_BY_TIER[tier]

    @client.complete(
      [{ role: "user", content: task }],
      model: model
    )
  end

  private

  def estimate_complexity(task)
    # Quick heuristics for complexity
    word_count = task.split.size

    case
    when task.match?(/prove|derive|analyze deeply|comprehensive/i)
      :reasoning
    when task.match?(/code|debug|security|architecture/i)
      :premium
    when word_count > 200 || task.match?(/compare|evaluate|synthesize/i)
      :standard
    else
      :cheap
    end
  end
end
```