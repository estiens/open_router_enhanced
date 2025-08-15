#!/usr/bin/env ruby
# frozen_string_literal: true

# Example demonstrating the PromptTemplate system
# Run this with: ruby -I lib examples/prompt_template_example.rb

require "open_router"

puts "🎯 Prompt Template Examples"
puts "=" * 60

# Create a client
client = OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])

# Example 1: Simple template
puts "\n1. Simple Template:"
puts "-" * 40

translation_template = OpenRouter::PromptTemplate.new(
  template: "Translate the following {language_from} text to {language_to}:\n\n'{text}'",
  input_variables: %i[language_from language_to text]
)

prompt = translation_template.format(
  language_from: "English",
  language_to: "French",
  text: "Hello, how are you today?"
)

puts prompt
puts "\nFormatted prompt ready for OpenRouter API!"

# Example 2: Few-shot template for consistent formatting
puts "\n2. Few-Shot Template (Learning from Examples):"
puts "-" * 40

sentiment_template = OpenRouter::PromptTemplate.new(
  prefix: "Classify the sentiment of these messages as 'positive', 'negative', or 'neutral'.",
  examples: [
    { text: "I love this product! It's amazing!", sentiment: "positive" },
    { text: "This is terrible, waste of money.", sentiment: "negative" },
    { text: "It works as expected.", sentiment: "neutral" }
  ],
  example_template: "Text: {text}\nSentiment: {sentiment}",
  suffix: "Text: {input}\nSentiment:",
  input_variables: [:input]
)

prompt = sentiment_template.format(input: "The service was okay, nothing special.")
puts prompt

# Example 3: Chat-style template with role markers
puts "\n3. Chat-Style Template (Multi-role conversation):"
puts "-" * 40

chat_template = OpenRouter::PromptTemplate.new(
  template: <<~TEMPLATE,
    System: You are a helpful coding assistant specializing in {language}.
    Always provide clear explanations and working code examples.

    User: {question}
  TEMPLATE
  input_variables: %i[language question]
)

# Convert to messages array for OpenRouter API
messages = chat_template.to_messages(
  language: "Ruby",
  question: "How do I read a JSON file and parse it?"
)

puts "Messages array for API:"
puts messages.inspect

# Example 4: Using DSL for template creation
puts "\n4. DSL-Style Template Creation:"
puts "-" * 40

code_review_template = OpenRouter::PromptTemplate.build do
  template <<~PROMPT
    Review this {language} code for:
    - Code quality and best practices
    - Potential bugs or issues
    - Performance considerations
    - Suggestions for improvement

    Code to review:
    ```{language}
    {code}
    ```

    Provide your review in a structured format.
  PROMPT
  variables :language, :code
end

review_prompt = code_review_template.format(
  language: "ruby",
  code: "def add(a, b)\n  return a + b\nend"
)

puts review_prompt

# Example 5: Partial templates (pre-filling some variables)
puts "\n5. Partial Templates (Pre-filled Variables):"
puts "-" * 40

qa_template = OpenRouter::PromptTemplate.new(
  template: "Context: {context}\n\nQuestion: {question}\n\nAnswer:",
  input_variables: %i[context question]
)

# Create a partial with context pre-filled
science_qa = qa_template.partial(
  context: "Water boils at 100°C (212°F) at sea level atmospheric pressure."
)

# Now only need to provide the question
prompt1 = science_qa.format(question: "What is the boiling point of water in Celsius?")
prompt2 = science_qa.format(question: "How does altitude affect boiling point?")

puts "First question:\n#{prompt1}\n"
puts "Second question:\n#{prompt2}"

# Example 6: Factory methods for common patterns
puts "\n6. Factory Methods (Convenient Creation):"
puts "-" * 40

# Simple template
simple = OpenRouter::Prompt.template(
  "Summarize this text in {word_count} words:\n\n{text}",
  variables: %i[word_count text]
)

# Few-shot template
translation = OpenRouter::Prompt.few_shot(
  prefix: "Translate from English to Spanish:",
  examples: [
    { english: "Hello", spanish: "Hola" },
    { english: "Goodbye", spanish: "Adiós" }
  ],
  example_template: "{english} → {spanish}",
  suffix: "{input} →",
  variables: [:input]
)

puts simple.format(word_count: 50, text: "Long text here...")
puts "\n"
puts translation.format(input: "Thank you")

# Example 7: Integration with OpenRouter Client (if API key is set)
puts "\n7. Using with OpenRouter Client:"
puts "-" * 40

if ENV["OPENROUTER_API_KEY"]
  story_template = OpenRouter::PromptTemplate.new(
    template: "Write a short story about {character} who {plot}. Make it {tone}.",
    input_variables: %i[character plot tone]
  )

  messages = story_template.to_messages(
    character: "a robot",
    plot: "discovers emotions",
    tone: "heartwarming"
  )

  begin
    response = client.complete(messages, model: "openai/gpt-4o-mini")
    puts "AI Response:\n#{response.content}"
  rescue StandardError
    puts "API call would be made with messages: #{messages.inspect}"
    puts "(Set OPENROUTER_API_KEY to test real API calls)"
  end
else
  puts "Set OPENROUTER_API_KEY environment variable to test with real API"
end

puts "\n✅ Prompt template examples completed!"
puts "\n💡 Key Benefits:"
puts "   - Consistent prompt formatting"
puts "   - Variable validation"
puts "   - Few-shot learning support"
puts "   - Easy chat message formatting"
puts "   - Reusable templates with partials"
