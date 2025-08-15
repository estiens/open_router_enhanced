# Model Selection

The OpenRouter gem includes sophisticated model selection capabilities that help you automatically choose the best AI model based on your specific requirements. The system combines intelligent model registry caching with a fluent DSL for expressing selection criteria.

## Quick Start

```ruby
# Find the cheapest model that supports function calling
model = OpenRouter::ModelSelector.new
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose

# Use the selected model
response = client.complete(messages, model: model, tools: tools)
```

## ModelSelector API

The `ModelSelector` class provides a fluent interface for building complex model selection criteria.

### Basic Usage

```ruby
selector = OpenRouter::ModelSelector.new

# Method chaining for requirements
model = selector.require(:function_calling, :vision)
              .within_budget(max_cost: 0.01)
              .prefer_providers("anthropic", "openai")
              .optimize_for(:performance)
              .choose

puts model  # => "anthropic/claude-3.5-sonnet"
```

### Optimization Strategies

```ruby
# Optimize for cost - choose cheapest input token cost
model = selector.optimize_for(:cost).choose

# Optimize for performance - prefer premium tier, then by cost
model = selector.optimize_for(:performance).choose

# Optimize for latest - prefer most recent model
model = selector.optimize_for(:latest).choose

# Optimize for context - prefer largest context window
model = selector.optimize_for(:context).choose
```

**Note**: Sorting is nil-safe for `created_at` and `context_length`.

### Capability Requirements

```ruby
# Require specific capabilities
selector.require(:function_calling)                    # Single capability
selector.require(:function_calling, :vision)           # Multiple capabilities
selector.require(:structured_outputs, :long_context)   # Mix and match

# Available capabilities:
# :function_calling   - Tool/function calling support
# :structured_outputs - JSON schema response formatting
# :vision            - Image input processing
# :long_context      - Large context windows (100k+ tokens)
# :chat              - Basic chat completion (all models have this)
```

### Budget Constraints

```ruby
# Set maximum costs per 1k tokens
selector.within_budget(max_cost: 0.01)                    # Input tokens only
selector.within_budget(max_cost: 0.01, max_output_cost: 0.02)  # Both input and output

# Example: Find cheapest model under $0.005 per 1k input tokens
model = OpenRouter::ModelSelector.new
                                 .within_budget(max_cost: 0.005)
                                 .require(:function_calling)
                                 .choose
```

### Context Length Requirements

```ruby
# Require minimum context length
selector.min_context(50_000)   # 50k tokens minimum
selector.min_context(200_000)  # 200k tokens minimum

# Find model with large context for document processing
model = OpenRouter::ModelSelector.new
                                 .min_context(100_000)
                                 .optimize_for(:cost)
                                 .choose
```

### Provider Preferences and Filtering

```ruby
# Soft preference - records preference but doesn't currently affect ordering
selector.prefer_providers("anthropic", "openai")

# Hard requirement - only these providers
selector.require_providers("anthropic")

# Avoid specific providers
selector.avoid_providers("google", "meta")

# Avoid model patterns (glob syntax)
selector.avoid_patterns("*-free", "*-preview", "*-alpha")
```

**Note**: `prefer_providers` is available to record preferences but does not currently affect ordering. Filtering is enforced via `require_providers`/`avoid_providers`/`avoid_patterns`.

### Release Date Filtering

```ruby
# Only models released after a specific date
selector.newer_than(Date.new(2024, 1, 1))
selector.newer_than(Time.now - 30.days)
selector.newer_than(1704067200)  # Unix timestamp

# Find latest models from this year
model = OpenRouter::ModelSelector.new
                                 .newer_than(Date.new(2024, 1, 1))
                                 .optimize_for(:latest)
                                 .choose
```

## Selection Methods

### Single Model Selection

```ruby
# Get just the model ID
model = selector.choose
# => "anthropic/claude-3.5-sonnet"

# Get model ID with detailed specs
model, specs = selector.choose(return_specs: true)
# => ["anthropic/claude-3.5-sonnet", { capabilities: [...], cost_per_1k_tokens: {...}, ... }]
```

### Multiple Models with Fallbacks

```ruby
# Get multiple models in order of preference
models = selector.choose_with_fallbacks(limit: 3)
# => ["anthropic/claude-3.5-sonnet", "openai/gpt-4o", "anthropic/claude-3-haiku"]

# Use first model, fall back to others if needed
models.each do |model|
  begin
    response = client.complete(messages, model: model)
    break
  rescue OpenRouter::ServerError => e
    puts "Model #{model} failed: #{e.message}"
    next
  end
end
```

### Graceful Degradation

```ruby
# choose_with_fallback drops least important requirements progressively if no match
model = selector.require(:function_calling, :vision)
              .within_budget(max_cost: 0.001)  # Very strict budget
              .choose_with_fallback
```

**Drop order**:
1. `released_after_date`
2. `performance_tier`
3. `max_output_cost`
4. `min_context_length`
5. `max_input_cost`
6. Keep only capability requirements
7. Otherwise choose the cheapest available model

## ModelRegistry

The underlying model registry provides direct access to model data and capabilities.

### Model Information

```ruby
# Get all available models
all_models = OpenRouter::ModelRegistry.all_models
# => { "anthropic/claude-3.5-sonnet" => { capabilities: [...], cost_per_1k_tokens: {...}, ...}, ... }

# Get specific model information
model_info = OpenRouter::ModelRegistry.get_model_info("anthropic/claude-3.5-sonnet")
puts model_info[:capabilities]        # => [:chat, :function_calling, :structured_outputs, :vision]
puts model_info[:cost_per_1k_tokens]  # => { input: 0.003, output: 0.015 }
puts model_info[:context_length]      # => 200000
puts model_info[:performance_tier]    # => :premium

# Check if model exists
if OpenRouter::ModelRegistry.model_exists?("anthropic/claude-3.5-sonnet")
  puts "Model is available"
end
```

### Cost Estimation

```ruby
# Estimate costs for specific token usage
cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
  "anthropic/claude-3.5-sonnet",
  input_tokens: 1000,
  output_tokens: 500
)
puts "Estimated cost: $#{cost.round(4)}"  # => "Estimated cost: $0.0105"
```

### Filtering Models

```ruby
# Find models matching specific requirements
candidates = OpenRouter::ModelRegistry.models_meeting_requirements(
  capabilities: [:function_calling, :vision],
  max_input_cost: 0.01,
  min_context_length: 50_000
)

candidates.each do |model_id, specs|
  puts "#{model_id}: $#{specs[:cost_per_1k_tokens][:input]} per 1k tokens"
end
```

### Cache Management

```ruby
# Refresh model data from API (clears cache)
OpenRouter::ModelRegistry.refresh!

# Clear cache manually
OpenRouter::ModelRegistry.clear_cache!

# Check cache status
cached_data = OpenRouter::ModelRegistry.load_cached_models
puts cached_data ? "Cache loaded" : "No cache available"
```

## Advanced Usage Patterns

### Cost-Aware Model Selection

```ruby
def select_model_by_budget(requirements, max_monthly_cost:, estimated_monthly_tokens:)
  max_cost_per_1k = (max_monthly_cost / estimated_monthly_tokens) * 1000
  
  OpenRouter::ModelSelector.new
                           .require(*requirements)
                           .within_budget(max_cost: max_cost_per_1k)
                           .optimize_for(:cost)
                           .choose
end

# Usage
model = select_model_by_budget(
  [:function_calling],
  max_monthly_cost: 100.0,      # $100 monthly budget
  estimated_monthly_tokens: 1_000_000  # 1M tokens per month
)
```

### Capability-First Selection

```ruby
def select_best_model_for_task(task_type)
  requirements = case task_type
  when :data_extraction
    [:structured_outputs]
  when :function_calling
    [:function_calling]
  when :document_analysis
    [:vision, :long_context]
  when :code_generation
    [:function_calling, :long_context]
  else
    []
  end
  
  OpenRouter::ModelSelector.new
                           .require(*requirements)
                           .optimize_for(:performance)
                           .choose_with_fallback
end
```

### Provider Rotation

```ruby
class ModelRotator
  def initialize(providers:, requirements: [])
    @providers = providers
    @requirements = requirements
    @current_index = 0
  end
  
  def next_model
    provider = @providers[@current_index % @providers.length]
    @current_index += 1
    
    OpenRouter::ModelSelector.new
                             .require(*@requirements)
                             .require_providers(provider)
                             .optimize_for(:cost)
                             .choose
  end
end

# Usage
rotator = ModelRotator.new(
  providers: ["anthropic", "openai", "google"],
  requirements: [:function_calling]
)

3.times do
  model = rotator.next_model
  puts "Using model: #{model}"
end
```

### Performance Monitoring

```ruby
class ModelPerformanceTracker
  def initialize
    @performance_data = {}
  end
  
  def track_completion(model, input_tokens:, output_tokens:, duration:, success:)
    @performance_data[model] ||= { 
      calls: 0, 
      successes: 0, 
      total_duration: 0, 
      total_cost: 0 
    }
    
    data = @performance_data[model]
    data[:calls] += 1
    data[:successes] += 1 if success
    data[:total_duration] += duration
    
    cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
      model, 
      input_tokens: input_tokens, 
      output_tokens: output_tokens
    )
    data[:total_cost] += cost
  end
  
  def best_performing_model(min_calls: 5)
    eligible_models = @performance_data.select { |_, data| data[:calls] >= min_calls }
    return nil if eligible_models.empty?
    
    eligible_models.max_by do |_, data|
      success_rate = data[:successes].to_f / data[:calls]
      avg_duration = data[:total_duration] / data[:calls]
      
      # Score based on success rate and speed (higher is better)
      success_rate * 100 - avg_duration
    end&.first
  end
end
```

## Integration with Client

### Automatic Model Selection

```ruby
class SmartOpenRouterClient < OpenRouter::Client
  def initialize(*args, **kwargs)
    super
    @model_selector = OpenRouter::ModelSelector.new
  end
  
  def smart_complete(messages, requirements: [], **options)
    unless options[:model]
      options[:model] = @model_selector
                          .require(*requirements)
                          .optimize_for(:cost)
                          .choose_with_fallback
    end
    
    complete(messages, **options)
  end
end

# Usage
client = SmartOpenRouterClient.new
response = client.smart_complete(
  messages, 
  requirements: [:function_calling],
  tools: tools
)
```

### Fallback Chains

```ruby
def complete_with_fallbacks(messages, **options)
  models = OpenRouter::ModelSelector.new
                                    .require(:function_calling)
                                    .optimize_for(:cost)
                                    .choose_with_fallbacks(limit: 3)
  
  last_error = nil
  
  models.each do |model|
    begin
      return client.complete(messages, model: model, **options)
    rescue OpenRouter::ServerError => e
      last_error = e
      puts "Model #{model} failed: #{e.message}, trying next..."
      next
    end
  end
  
  raise last_error if last_error
  raise OpenRouter::Error, "No models available"
end
```

## Configuration and Customization

### Custom Selection Criteria

```ruby
class CustomModelSelector < OpenRouter::ModelSelector
  def require_custom_capability(capability_name)
    # Add custom logic for proprietary capability detection
    new_requirements = @requirements.dup
    new_requirements[:custom_capabilities] ||= []
    new_requirements[:custom_capabilities] << capability_name
    
    self.class.new(
      requirements: new_requirements,
      strategy: @strategy,
      provider_preferences: @provider_preferences,
      fallback_options: @fallback_options
    )
  end
  
  private
  
  def meets_requirements?(specs, requirements)
    # Call parent implementation first
    return false unless super
    
    # Add custom requirement checking
    if requirements[:custom_capabilities]
      # Your custom logic here
    end
    
    true
  end
end
```

### Environment-Specific Defaults

```ruby
# config/initializers/openrouter.rb
class OpenRouter::ModelSelector
  class << self
    def production_defaults
      new.avoid_patterns("*-preview", "*-alpha", "*-beta")
         .require_providers("anthropic", "openai")  # Trusted providers only
         .optimize_for(:performance)
    end
    
    def development_defaults
      new.optimize_for(:cost)
         .within_budget(max_cost: 0.001)  # Keep costs low in dev
    end
    
    def for_environment
      Rails.env.production? ? production_defaults : development_defaults
    end
  end
end

# Usage in your app
model = OpenRouter::ModelSelector.for_environment
                                 .require(:function_calling)
                                 .choose
```

## Best Practices

### 1. Cache Selection Results

```ruby
class CachedModelSelector
  def initialize(ttl: 3600)  # 1 hour cache
    @cache = {}
    @ttl = ttl
  end
  
  def select(requirements_hash)
    cache_key = requirements_hash.hash
    cached_result = @cache[cache_key]
    
    if cached_result && Time.now - cached_result[:timestamp] < @ttl
      return cached_result[:model]
    end
    
    model = build_selector_from_hash(requirements_hash).choose
    @cache[cache_key] = { model: model, timestamp: Time.now }
    model
  end
  
  private
  
  def build_selector_from_hash(hash)
    selector = OpenRouter::ModelSelector.new
    
    selector = selector.require(*hash[:capabilities]) if hash[:capabilities]
    selector = selector.within_budget(max_cost: hash[:max_cost]) if hash[:max_cost]
    selector = selector.optimize_for(hash[:strategy]) if hash[:strategy]
    
    selector
  end
end
```

### 2. Monitor Model Availability

```ruby
def check_model_health(models)
  results = {}
  
  models.each do |model|
    begin
      # Quick test completion
      response = client.complete(
        [{ role: "user", content: "Say 'OK'" }],
        model: model,
        max_tokens: 5
      )
      results[model] = response.content.include?("OK") ? :healthy : :unhealthy
    rescue => e
      results[model] = :error
    end
  end
  
  results
end
```

### 3. Cost Tracking

```ruby
def track_model_costs
  @daily_costs ||= Hash.new(0)
  
  before_action do
    @request_start_time = Time.now
  end
  
  after_action do
    if @selected_model && @input_tokens && @output_tokens
      cost = OpenRouter::ModelRegistry.calculate_estimated_cost(
        @selected_model,
        input_tokens: @input_tokens,
        output_tokens: @output_tokens
      )
      
      date_key = Date.current.to_s
      @daily_costs[date_key] += cost
      
      Rails.logger.info "Model cost: #{@selected_model} $#{cost.round(6)}"
    end
  end
end
```

## Troubleshooting

### Common Issues

1. **No Models Found**: Your requirements may be too restrictive
2. **Cache Stale**: Model data might be outdated
3. **Network Errors**: API connection issues when fetching model data
4. **Performance**: Selection taking too long with many models

### Solutions

```ruby
# 1. Debug selection criteria
selector = OpenRouter::ModelSelector.new
           .require(:function_calling)
           .within_budget(max_cost: 0.0001)  # Very restrictive

puts "Selection criteria:"
puts selector.selection_criteria.inspect

# See what models meet each requirement step by step
all_models = OpenRouter::ModelRegistry.all_models
puts "Total models: #{all_models.size}"

with_capability = OpenRouter::ModelRegistry.models_meeting_requirements(
  capabilities: [:function_calling]
)
puts "With function calling: #{with_capability.size}"

within_budget = with_capability.select do |_, specs|
  specs[:cost_per_1k_tokens][:input] <= 0.0001
end
puts "Within budget: #{within_budget.size}"

# 2. Force cache refresh
OpenRouter::ModelRegistry.refresh!

# 3. Handle network errors gracefully
begin
  models = OpenRouter::ModelRegistry.all_models
rescue OpenRouter::ModelRegistryError => e
  puts "Using fallback model due to registry error: #{e.message}"
  model = "anthropic/claude-3-haiku"  # Known reliable fallback
end

# 4. Optimize for performance
# Use more specific requirements to reduce search space
model = OpenRouter::ModelSelector.new
                                 .require_providers("anthropic")  # Limit search space
                                 .require(:function_calling)
                                 .optimize_for(:cost)
                                 .choose
```