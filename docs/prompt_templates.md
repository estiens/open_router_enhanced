# Prompt Templates

The OpenRouter gem provides a flexible prompt template system inspired by LangChain, allowing you to create reusable, parameterized prompts with support for few-shot learning, chat formatting, and variable interpolation.

## Quick Start

```ruby
# Basic template
template = OpenRouter::PromptTemplate.new(
  template: "Translate '{text}' from {source} to {target}",
  input_variables: [:text, :source, :target]
)

prompt = template.format(
  text: "Hello world",
  source: "English",
  target: "French"
)
# => "Translate 'Hello world' from English to French"

# Use with OpenRouter client
client = OpenRouter::Client.new
response = client.complete(
  template.to_messages(text: "Hello", source: "English", target: "Spanish"),
  model: "openai/gpt-4o-mini"
)
```

## Core Features

### 1. Variable Interpolation

Templates support `{variable}` placeholders that get replaced with provided values:

```ruby
template = OpenRouter::PromptTemplate.new(
  template: "Hello {name}, welcome to {place}!",
  input_variables: [:name, :place]
)

template.format(name: "Alice", place: "Wonderland")
# => "Hello Alice, welcome to Wonderland!"
```

### 2. Few-Shot Learning

Create templates with examples for consistent output formatting:

```ruby
few_shot = OpenRouter::PromptTemplate.new(
  prefix: "Classify sentiment as positive, negative, or neutral:",
  examples: [
    { text: "I love this!", sentiment: "positive" },
    { text: "This is terrible", sentiment: "negative" },
    { text: "It's okay", sentiment: "neutral" }
  ],
  example_template: "Text: {text}\nSentiment: {sentiment}",
  suffix: "Text: {input}\nSentiment:",
  input_variables: [:input]
)

prompt = few_shot.format(input: "This product is amazing!")
```

Output:
```
Classify sentiment as positive, negative, or neutral:

Text: I love this!
Sentiment: positive

Text: This is terrible
Sentiment: negative

Text: It's okay
Sentiment: neutral

Text: This product is amazing!
Sentiment:
```

### 3. Partial Templates

Pre-fill some variables for reuse:

```ruby
base_template = OpenRouter::PromptTemplate.new(
  template: "As a {role} expert, answer this {difficulty} question: {question}",
  input_variables: [:role, :difficulty, :question]
)

# Create a partial with role pre-filled
python_expert = base_template.partial(role: "Python", difficulty: "beginner")

# Now only need to provide the question
python_expert.format(question: "What is a list comprehension?")
# => "As a Python expert, answer this beginner question: What is a list comprehension?"
```

### 4. Chat Message Formatting

Convert templates directly to OpenRouter message format:

```ruby
chat_template = OpenRouter::PromptTemplate.new(
  template: "System: You are a {role}.\nUser: {user_message}",
  input_variables: [:role, :user_message]
)

messages = chat_template.to_messages(
  role: "helpful assistant",
  user_message: "Explain quantum computing"
)
# => [
#      { role: "system", content: "You are a helpful assistant." },
#      { role: "user", content: "Explain quantum computing" }
#    ]

# Use directly with client
response = client.complete(messages, model: "anthropic/claude-3-haiku")
```

### 5. DSL for Template Creation

Use the builder DSL for more readable template definitions:

```ruby
template = OpenRouter::PromptTemplate.build do
  prefix "You are an expert code reviewer."

  examples [
    { code: "def add(a,b); a+b end", review: "Missing spaces after commas" },
    { code: "def foo; 42; end", review: "Method name not descriptive" }
  ]

  example_template "Code: {code}\nReview: {review}"

  suffix "Code: {input_code}\nReview:"

  variables :input_code
end
```

## Factory Methods

The gem provides convenient factory methods for common patterns:

```ruby
# Simple template
template = OpenRouter::Prompt.template(
  "Summarize in {count} words: {text}",
  variables: [:count, :text]
)

# Few-shot template
sentiment = OpenRouter::Prompt.few_shot(
  prefix: "Classify sentiment:",
  examples: [...],
  example_template: "{text} -> {label}",
  suffix: "{input} ->",
  variables: [:input]
)

# Chat template with DSL
chat = OpenRouter::Prompt.chat do
  template "System: {system}\nUser: {user}"
  variables :system, :user
end
```

## Advanced Usage

### Combining with Tools and Structured Outputs

Prompt templates work seamlessly with other OpenRouter features:

```ruby
# Define a tool
weather_tool = OpenRouter::Tool.define do
  name "get_weather"
  parameters do
    string :location, required: true
  end
end

# Define output schema
response_schema = OpenRouter::Schema.define("analysis") do
  string :summary, required: true
  array :key_points, items: { type: "string" }
end

# Create template
analysis_template = OpenRouter::PromptTemplate.new(
  template: "Analyze the weather data for {city} and provide insights",
  input_variables: [:city]
)

# Use together
response = client.complete(
  analysis_template.to_messages(city: "Tokyo"),
  model: "openai/gpt-4o",
  tools: [weather_tool],
  response_format: response_schema
)
```

### Multi-Stage Prompting

Chain templates for complex workflows:

```ruby
# Stage 1: Research
research_template = OpenRouter::PromptTemplate.new(
  template: "Research {topic} and list 5 key facts",
  input_variables: [:topic]
)

# Stage 2: Analysis
analysis_template = OpenRouter::PromptTemplate.new(
  template: "Given these facts:\n{facts}\n\nProvide analysis on {aspect}",
  input_variables: [:facts, :aspect]
)

# Stage 3: Summary
summary_template = OpenRouter::PromptTemplate.new(
  template: "Summarize this analysis for a {audience} audience:\n{analysis}",
  input_variables: [:analysis, :audience]
)

# Execute workflow
topic = "renewable energy"
facts_response = client.complete(
  research_template.to_messages(topic: topic),
  model: "openai/gpt-4o-mini"
)

analysis_response = client.complete(
  analysis_template.to_messages(
    facts: facts_response.content,
    aspect: "economic impact"
  ),
  model: "openai/gpt-4o-mini"
)

summary_response = client.complete(
  summary_template.to_messages(
    analysis: analysis_response.content,
    audience: "general public"
  ),
  model: "openai/gpt-4o-mini"
)
```

## Template Best Practices

### 1. Clear Variable Names
Use descriptive variable names that indicate expected content:
```ruby
# Good
template = "Translate {source_text} from {source_language} to {target_language}"

# Less clear
template = "Translate {text} from {lang1} to {lang2}"
```

### 2. Consistent Example Formatting
Keep examples consistent in structure and style:
```ruby
examples = [
  { input: "cat", output: "cats" },    # Consistent
  { input: "dog", output: "dogs" },    # structure
  { input: "fish", output: "fish" }    # throughout
]
```

### 3. Validate Required Variables
Always specify `input_variables` to catch missing values early:
```ruby
template = OpenRouter::PromptTemplate.new(
  template: "Hello {name}",
  input_variables: [:name]  # Enforces name is provided
)
```

### 4. Use Partials for Reusability
Create base templates and specialize them:
```ruby
base = OpenRouter::PromptTemplate.new(
  template: "As a {expertise} expert in {domain}, {task}",
  input_variables: [:expertise, :domain, :task]
)

ruby_expert = base.partial(expertise: "Ruby", domain: "web development")
python_expert = base.partial(expertise: "Python", domain: "data science")
```

### 5. Role Markers for Chat
Use clear role markers for multi-turn conversations:
```ruby
template = <<~TEMPLATE
  System: You are a {character} with {trait}.

  User: {user_question}

  Assistant: I'll respond as a {character} would.
TEMPLATE
```

## Migration from LangChain

If you're familiar with LangChain's prompt templates, here's a comparison:

### LangChain (Python/Ruby)
```ruby
# LangChain style
template = Langchain::Prompt::FewShotPromptTemplate.new(
  prefix: "Translate words:",
  suffix: "Input: {word}\nOutput:",
  example_prompt: Langchain::Prompt::PromptTemplate.new(
    input_variables: ["input", "output"],
    template: "Input: {input}\nOutput: {output}"
  ),
  examples: [
    { "input" => "happy", "output" => "glad" }
  ],
  input_variables: ["word"]
)
```

### OpenRouter Enhanced
```ruby
# OpenRouter style (simpler, more Ruby-idiomatic)
template = OpenRouter::PromptTemplate.new(
  prefix: "Translate words:",
  suffix: "Input: {word}\nOutput:",
  example_template: "Input: {input}\nOutput: {output}",
  examples: [
    { input: "happy", output: "glad" }
  ],
  input_variables: [:word]
)
```

Key differences:
- Simpler API with fewer nested objects
- Symbol keys instead of strings
- Built-in chat message formatting
- Direct integration with OpenRouter client
- No separate prompt classes for different patterns

## API Reference

### Class: `OpenRouter::PromptTemplate`

#### Constructor Options
- `template`: Main template string with `{variable}` placeholders
- `input_variables`: Array of required variable symbols
- `prefix`: Optional prefix text (for few-shot)
- `suffix`: Optional suffix text (for few-shot)
- `examples`: Array of example hashes
- `example_template`: Template string or PromptTemplate for formatting examples
- `partial_variables`: Hash of pre-filled variables

#### Methods
- `format(variables)`: Format template with variables
- `to_messages(variables)`: Convert to OpenRouter messages array
- `partial(variables)`: Create new template with partial variables
- `few_shot_template?`: Check if template uses examples

### Module: `OpenRouter::Prompt`

Factory methods for template creation:
- `template(text, variables:)`: Create simple template
- `few_shot(prefix:, suffix:, examples:, example_template:, variables:)`: Create few-shot template
- `chat(&block)`: Create template using DSL

## Complete Example

```ruby
require "open_router"

# Configure client
client = OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])

# Create a sophisticated prompt template
code_review_template = OpenRouter::PromptTemplate.new(
  prefix: "You are an expert code reviewer. Review code for quality, bugs, and improvements.",
  examples: [
    {
      code: "def calculate_sum(arr)\n  total = 0\n  arr.each { |n| total += n }\n  total\nend",
      review: "Consider using arr.sum for better readability and performance."
    },
    {
      code: "def get_user_name(id)\n  User.find(id).name\nend",
      review: "Add error handling for when user is not found. Consider: User.find(id)&.name"
    }
  ],
  example_template: "Code:\n```ruby\n{code}\n```\nReview: {review}",
  suffix: "Code:\n```ruby\n{input_code}\n```\nReview:",
  input_variables: [:input_code]
)

# Format the prompt
code_to_review = <<~CODE
  def process_payment(amount, card)
    charge = card.charge(amount)
    charge.success
  end
CODE

prompt = code_review_template.format(input_code: code_to_review)

# Send to OpenRouter
response = client.complete(
  [{ role: "user", content: prompt }],
  model: "anthropic/claude-3.5-sonnet"
)

puts response.content
```

This prompt template system provides a powerful, flexible way to manage prompts in your OpenRouter applications while maintaining consistency and reusability.