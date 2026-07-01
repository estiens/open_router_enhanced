#!/usr/bin/env ruby
# frozen_string_literal: true

require "bundler/setup"
require "open_router"

# Configure the client
OpenRouter.configure do |config|
  config.access_token = ENV["OPENROUTER_API_KEY"]
  config.site_name = "OpenRouter Ruby Gem Example"
  config.site_url = "https://github.com/OlympiaAI/open_router"
end

OpenRouter::Client.new

# Example 1: Simple structured output
puts "=== Example 1: Simple Weather Schema ==="

weather_schema = OpenRouter::Schema.define("weather") do
  strict true

  string :location, required: true, description: "City or location name"
  number :temperature, required: true, description: "Temperature in Celsius"
  string :conditions, required: true, description: "Weather conditions"
  string :humidity, description: "Humidity percentage"

  no_additional_properties
end

puts "Schema definition:"
puts weather_schema.to_json

# Example 2: Complex nested schema
puts "\n=== Example 2: Complex User Profile Schema ==="

user_schema = OpenRouter::Schema.define("user_profile") do
  string :name, required: true, description: "Full name"
  integer :age, required: true, minimum: 0, maximum: 150
  string :email, required: true, description: "Email address"

  object :address, required: true do
    string :street, required: true
    string :city, required: true
    string :state, required: true
    string :zip_code, required: true
  end

  array :hobbies do
    string description: "A hobby or interest"
  end

  object :preferences do
    boolean :newsletter, description: "Wants to receive newsletter"
    string :theme, description: "UI theme preference"
  end
end

puts "User schema:"
puts JSON.pretty_generate(user_schema.to_h)

# Example 3: Using schemas with API calls
puts "\n=== Example 3: Structured Output API Call ==="

# Simulate a structured response
mock_weather_response = {
  "id" => "chatcmpl-123",
  "choices" => [
    {
      "message" => {
        "role" => "assistant",
        "content" => '{"location": "San Francisco", "temperature": 22, "conditions": "Partly cloudy", "humidity": "65%"}'
      }
    }
  ]
}

response = OpenRouter::Response.new(mock_weather_response, response_format: weather_schema)
puts "Parsed structured output:"
puts response.structured_output.inspect

# Check if output is valid
if response.valid_structured_output?
  puts "✅ Output is valid according to schema"
else
  puts "❌ Output validation failed:"
  puts response.validation_errors
end

# Example 4: Working with different response formats
puts "\n=== Example 4: Different Response Format Styles ==="

# Style 1: Schema object directly
format1 = weather_schema

# Style 2: Hash with schema object
format2 = {
  type: "json_schema",
  json_schema: weather_schema
}

# Style 3: Raw hash format
format3 = {
  type: "json_schema",
  json_schema: {
    name: "simple_weather",
    strict: true,
    schema: {
      type: "object",
      properties: {
        temp: { type: "number" },
        desc: { type: "string" }
      },
      required: %w[temp desc],
      additionalProperties: false
    }
  }
}

puts "All three formats are supported:"
puts "1. Direct schema object: #{format1.class}"
puts "2. Hash with schema object: #{format2[:json_schema].class}"
puts "3. Raw hash format: #{format3[:json_schema].class}"

# Example 5: Real API call example (commented out)
puts "\n=== Example 5: Real API Usage ==="

# # Uncomment to make a real API call
# begin
#   response = client.complete(
#     [{ role: "user", content: "What's the weather like in Tokyo right now?" }],
#     model: "openai/gpt-4o",
#     response_format: weather_schema
#   )
#
#   if response.structured_output
#     weather = response.structured_output
#     puts "Location: #{weather['location']}"
#     puts "Temperature: #{weather['temperature']}°C"
#     puts "Conditions: #{weather['conditions']}"
#     puts "Humidity: #{weather['humidity']}" if weather['humidity']
#
#     if response.valid_structured_output?
#       puts "✅ Response validates against schema"
#     else
#       puts "❌ Validation errors:"
#       response.validation_errors.each { |error| puts "  - #{error}" }
#     end
#   end
#
# rescue OpenRouter::ServerError => e
#   puts "API Error: #{e.message}"
# rescue OpenRouter::StructuredOutputError => e
#   puts "Structured Output Error: #{e.message}"
# rescue => e
#   puts "Unexpected error: #{e.message}"
# end

puts "\n(Structured outputs example complete - uncomment the API call section to test with real API)"

# Example 6: Schema validation demonstration
puts "\n=== Example 6: Schema Validation Demo ==="

if weather_schema.validation_available?
  puts "JSON Schema validation is available"

  # Valid data
  valid_data = {
    "location" => "London",
    "temperature" => 18,
    "conditions" => "Rainy"
  }

  # Invalid data
  invalid_data = {
    "location" => "London",
    "temperature" => "eighteen", # Should be number
    "conditions" => "Rainy"
  }

  puts "Valid data validation: #{weather_schema.validate(valid_data)}"
  puts "Invalid data validation: #{weather_schema.validate(invalid_data)}"

  unless weather_schema.validate(invalid_data)
    puts "Validation errors for invalid data:"
    weather_schema.validation_errors(invalid_data).each do |error|
      puts "  - #{error}"
    end
  end
else
  puts "JSON Schema validation not available (install json-schema gem for validation)"
end
