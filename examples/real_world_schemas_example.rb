#!/usr/bin/env ruby
# frozen_string_literal: true

# Real-World Structured Outputs Example
# =====================================
# This example demonstrates practical uses of schemas for extracting
# structured data from unstructured text, with validation and error handling.
#
# Run with: ruby -I lib examples/real_world_schemas_example.rb

require "open_router"
require "json"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV.fetch("OPENROUTER_API_KEY") do
    abort "Please set OPENROUTER_API_KEY environment variable"
  end
  config.site_name = "Schema Examples"
end

client = OpenRouter::Client.new

# Use a model with native structured output support
MODEL = "openai/gpt-4o-mini"

puts "=" * 60
puts "REAL-WORLD STRUCTURED OUTPUTS EXAMPLES"
puts "=" * 60

# -----------------------------------------------------------------------------
# Example 1: Extract Job Posting Details
# -----------------------------------------------------------------------------
puts "\n1. EXTRACTING JOB POSTING DETAILS"
puts "-" * 40

job_posting_schema = OpenRouter::Schema.define("job_posting") do
  string :title, required: true, description: "Job title"
  string :company, required: true, description: "Company name"
  string :location, required: true, description: "Job location (city, state or 'Remote')"
  boolean :remote_friendly, description: "Whether remote work is allowed"
  integer :salary_min, description: "Minimum salary in USD"
  integer :salary_max, description: "Maximum salary in USD"
  array :required_skills, required: true do
    string
  end
  array :nice_to_have_skills do
    string
  end
  string :experience_level, enum: %w[junior mid senior lead principal]
end

job_text = <<~TEXT
  Senior Ruby Engineer at TechCorp

  We're looking for an experienced Ruby developer to join our platform team
  in San Francisco (hybrid - 2 days in office). Salary range: $180,000-$220,000.

  Requirements:
  - 5+ years Ruby experience
  - Strong Rails knowledge
  - PostgreSQL expertise
  - Experience with background job processing

  Nice to have:
  - Kubernetes experience
  - GraphQL
  - Previous startup experience
TEXT

response = client.complete(
  [{ role: "user", content: "Extract the job details from this posting:\n\n#{job_text}" }],
  model: MODEL,
  response_format: job_posting_schema
)

job = response.structured_output
puts "Title: #{job["title"]}"
puts "Company: #{job["company"]}"
puts "Location: #{job["location"]}"
puts "Remote: #{job["remote_friendly"]}"
puts "Salary: $#{job["salary_min"]&.to_s || "?"} - $#{job["salary_max"]&.to_s || "?"}"
puts "Skills: #{job["required_skills"]&.join(", ")}"
puts "Level: #{job["experience_level"]}"

# -----------------------------------------------------------------------------
# Example 2: Nested Schema - Order with Line Items
# -----------------------------------------------------------------------------
puts "\n\n2. NESTED SCHEMA: ORDER WITH LINE ITEMS"
puts "-" * 40

order_schema = OpenRouter::Schema.define("order") do
  string :order_id, required: true
  string :customer_name, required: true
  string :customer_email, required: true

  object :shipping_address, required: true do
    string :street, required: true
    string :city, required: true
    string :state, required: true
    string :zip_code, required: true
    string :country, required: true
  end

  array :line_items, required: true do
    object do
      string :product_name, required: true
      integer :quantity, required: true
      number :unit_price, required: true
      number :total, required: true
    end
  end

  number :subtotal, required: true
  number :tax, required: true
  number :total, required: true
  string :status, enum: %w[pending confirmed shipped delivered]
end

order_email = <<~TEXT
  Order Confirmation #ORD-2024-5847

  Dear John Smith (john.smith@email.com),

  Thank you for your order! Here are the details:

  Ship to:
  123 Main Street
  Austin, TX 78701
  United States

  Items:
  - Mechanical Keyboard (x1) - $149.99 each = $149.99
  - USB-C Hub (x2) - $39.99 each = $79.98
  - Mouse Pad XL (x1) - $24.99 each = $24.99

  Subtotal: $254.96
  Tax (8.25%): $21.03
  Total: $275.99

  Your order has been confirmed and will ship soon!
TEXT

response = client.complete(
  [{ role: "user", content: "Parse this order confirmation email into structured data:\n\n#{order_email}" }],
  model: MODEL,
  response_format: order_schema
)

order = response.structured_output
puts "Order: #{order["order_id"]}"
puts "Customer: #{order["customer_name"]} (#{order["customer_email"]})"
puts "Ship to: #{order.dig("shipping_address", "city")}, #{order.dig("shipping_address", "state")}"
puts "\nLine Items:"
order["line_items"]&.each do |item|
  puts "  - #{item["product_name"]} x#{item["quantity"]} = $#{"%.2f" % item["total"]}"
end
puts "\nTotal: $#{"%.2f" % order["total"]} (including $#{"%.2f" % order["tax"]} tax)"

# -----------------------------------------------------------------------------
# Example 3: Schema Validation
# -----------------------------------------------------------------------------
puts "\n\n3. SCHEMA VALIDATION"
puts "-" * 40

# Create a simple schema
validation_schema = OpenRouter::Schema.define("contact") do
  string :name, required: true
  string :email, required: true
  integer :age
end

# Valid data
valid_data = { "name" => "Alice", "email" => "alice@example.com", "age" => 30 }
puts "Valid data: #{validation_schema.validate(valid_data)}"

# Invalid data (missing required field)
invalid_data = { "name" => "Bob" }
puts "Invalid data (missing email): #{validation_schema.validate(invalid_data)}"

# Get detailed errors
errors = validation_schema.validation_errors(invalid_data)
puts "Validation errors: #{errors.inspect}" if errors.any?

# -----------------------------------------------------------------------------
# Example 4: Sentiment Analysis with Confidence
# -----------------------------------------------------------------------------
puts "\n\n4. SENTIMENT ANALYSIS WITH CONFIDENCE"
puts "-" * 40

sentiment_schema = OpenRouter::Schema.define("sentiment_analysis") do
  string :sentiment, required: true, enum: %w[positive negative neutral mixed]
  number :confidence, required: true, description: "Confidence score from 0.0 to 1.0"
  array :key_phrases, required: true do
    string
  end
  string :summary, required: true, description: "Brief explanation of the sentiment"
end

reviews = [
  "This product exceeded my expectations! Fast shipping, great quality, will buy again.",
  "Terrible experience. Arrived broken and customer service was unhelpful.",
  "It's okay. Does what it says but nothing special. Fair price I guess."
]

reviews.each_with_index do |review, i|
  response = client.complete(
    [{ role: "user", content: "Analyze the sentiment of this review:\n\n#{review}" }],
    model: MODEL,
    response_format: sentiment_schema
  )

  result = response.structured_output
  puts "\nReview #{i + 1}: \"#{review[0..50]}...\""
  puts "  Sentiment: #{result["sentiment"]} (#{(result["confidence"] * 100).round}% confident)"
  puts "  Key phrases: #{result["key_phrases"]&.join(", ")}"
end

# -----------------------------------------------------------------------------
# Example 5: Using Auto-Healing for Non-Native Models
# -----------------------------------------------------------------------------
puts "\n\n5. AUTO-HEALING FOR MALFORMED RESPONSES"
puts "-" * 40

# Enable auto-healing in configuration
OpenRouter.configure do |config|
  config.auto_heal_responses = true
  config.healer_model = "openai/gpt-4o-mini"
  config.max_heal_attempts = 2
end

simple_schema = OpenRouter::Schema.define("extraction") do
  string :name, required: true
  integer :count, required: true
end

# The response will attempt to heal if the model returns malformed JSON
response = client.complete(
  [{ role: "user", content: "Extract: There are 42 widgets made by Acme Corp" }],
  model: MODEL,
  response_format: simple_schema
)

if response.valid_structured_output?
  puts "Extraction successful: #{response.structured_output}"
else
  puts "Validation failed: #{response.validation_errors}"
end

# Show response metadata
puts "\nResponse metadata:"
puts "  Model: #{response.model}"
puts "  Tokens: #{response.usage["total_tokens"]} total"
puts "  Was healed: #{begin
  response.healed?
rescue StandardError
  "N/A"
end}"

puts "\n#{"=" * 60}"
puts "Examples complete!"
puts "=" * 60
