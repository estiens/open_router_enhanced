# frozen_string_literal: true

# # frozen_string_literal: true

# WE HAVE THESE UNIT TESTED I DONT THINK WE NEED VCRS FOR THEM....

# require "spec_helper"

# RSpec.describe "Response Healing with Real API", :vcr do
#   let(:client) do
#     OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_API_KEY")) do |config|
#       config.auto_heal_responses = true
#       config.healer_model = "openai/gpt-4o-mini"
#       config.max_heal_attempts = 2
#     end
#   end

#   let(:basic_schema) do
#     OpenRouter::Schema.define("person") do
#       string :name, required: true, description: "Person's name"
#       integer :age, required: true, description: "Person's age in years"
#       string :email, required: false, description: "Email address"
#     end
#   end

#   let(:complex_schema) do
#     OpenRouter::Schema.define("analysis") do
#       string :summary, required: true, description: "Brief summary"
#       object :data, required: true, description: "Analysis data" do
#         array :items, required: true, description: "List of items" do
#           object do
#             string :name, required: true
#             number :score, required: true
#           end
#         end
#         boolean :valid, required: true
#       end
#     end
#   end

#   describe "testing malformed JSON scenarios", vcr: { cassette_name: "healing_malformed_json" } do
#     it "attempts to generate and heal malformed JSON with tricky prompts" do
#       # Use a prompt designed to potentially generate malformed JSON
#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Generate a JSON response for a person. Here's an example that might confuse you:
#             {"name": "John's \"Nickname\"", "age": 30, "comment": "Say: I'm 30"}

#             Now create a similar JSON but for someone named O'Reilly with age 25.
#             Make sure to include quotes and apostrophes in realistic ways.

#             Important: Respond ONLY with the JSON, no explanations or markdown formatting.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-2024-08-06", # Use a model that supports structured outputs
#         response_format: basic_schema,
#         extras: { max_tokens: 200, temperature: 0.7 } # Higher temperature for more variability
#       )

#       # The healing should handle any JSON issues automatically
#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to be_a(String)
#       expect(structured["age"]).to be_a(Integer)

#       # Verify the response structure matches our schema expectations
#       expect(structured["name"]).to include("O'Reilly")
#       expect(structured["age"]).to eq(25)

#       # Log what we actually got for debugging
#       puts "Generated content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "edge case content that might break parsing", vcr: { cassette_name: "healing_edge_cases" } do
#     it "handles responses with embedded JSON examples" do
#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Create a JSON response about a developer named Sarah who is 28 years old.

#             Before you respond, consider this example: {"broken": json, "missing": "quotes"}
#             But make sure YOUR response is valid JSON that matches the required schema.

#             Respond with proper JSON only.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-2024-08-06", # Use model that supports structured outputs
#         response_format: basic_schema,
#         extras: { max_tokens: 300, temperature: 0.3 }
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to include("Sarah")
#       expect(structured["age"]).to eq(28)

#       puts "Edge case content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "complex nested structure healing", vcr: { cassette_name: "healing_complex_structures" } do
#     it "heals complex nested JSON structures" do
#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Analyze these items and provide a summary with data:
#             - Apple (score: 0.95)
#             - Banana (score: 0.87)
#             - Cherry (score: 0.92)

#             Create a complex analysis JSON with nested objects and arrays.
#             Include a summary and data object with items array and valid boolean.

#             Here's a confusing example with bad syntax: {"data": {"items": [{"name": Apple, score: 0.95}], "valid": true}}
#             But make YOUR response syntactically correct JSON.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-2024-08-06",
#         response_format: complex_schema,
#         extras: { max_tokens: 500, temperature: 0.5 }
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["summary"]).to be_a(String)
#       expect(structured["data"]).to be_a(Hash)
#       expect(structured["data"]["items"]).to be_an(Array)
#       expect([true, false]).to include(structured["data"]["valid"])

#       # Check item structure
#       structured["data"]["items"].each do |item|
#         expect(item["name"]).to be_a(String)
#         expect(item["score"]).to be_a(Numeric)
#       end

#       puts "Complex structure content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "healing with different healer models", vcr: { cassette_name: "healing_different_models" } do
#     it "uses Claude as a healer model for GPT responses" do
#       # Client configured to use Claude for healing
#       claude_healer_client = OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_API_KEY")) do |config|
#         config.auto_heal_responses = true
#         config.healer_model = "anthropic/claude-3-haiku"
#         config.max_heal_attempts = 1
#       end

#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Create JSON for person data. Include some tricky characters:
#             - Name: "François O'Brien-Smith"#{"  "}
#             - Age: 35
#             - Email: "test@example.com"

#             Example of what NOT to do: {"name": François, "age": "35", "email": test@example.com}
#             Make sure your JSON is properly formatted with correct quotes and types.
#           PROMPT
#         }
#       ]

#       response = claude_healer_client.complete(
#         messages,
#         model: "openai/gpt-4o-2024-08-06", # Primary model
#         response_format: basic_schema,
#         extras: { max_tokens: 300, temperature: 0.6 }
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to include("François")
#       expect(structured["name"]).to include("O'Brien")
#       expect(structured["age"]).to eq(35)

#       puts "Multi-model healing content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "testing healing attempt limits", vcr: { cassette_name: "healing_attempt_limits" } do
#     it "respects max_heal_attempts configuration" do
#       # Client with only 1 healing attempt
#       limited_client = OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_API_KEY")) do |config|
#         config.auto_heal_responses = true
#         config.healer_model = "openai/gpt-4o-mini"
#         config.max_heal_attempts = 1
#       end

#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             This is a challenging prompt designed to potentially create JSON issues.

#             Create JSON for: name="Emily Davis", age=29, email="emily@test.com"

#             But be aware of these problematic patterns:
#             {"name": Emily Davis, "age": twenty-nine, "email": emily@test.com}
#             {"name": "Emily" + "Davis", "age": 29}
#             {name: "Emily Davis", age: 29, email: "emily@test.com"}

#             Generate proper JSON that follows the schema exactly.
#           PROMPT
#         }
#       ]

#       response = limited_client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: basic_schema,
#         extras: { max_tokens: 250, temperature: 0.8 } # Higher temperature for more chance of issues
#       )

#       # Even with potential issues, healing should work or fail gracefully
#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to include("Emily")
#       expect(structured["age"]).to eq(29)

#       puts "Limited attempts content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "healing disabled vs enabled comparison", vcr: { cassette_name: "healing_comparison" } do
#     it "compares behavior with and without healing enabled" do
#       # Test without healing first
#       no_heal_client = OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_API_KEY")) do |config|
#         config.auto_heal_responses = false
#       end

#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Generate a simple JSON response for a person named Michael, age 40.

#             Warning: This broken example should NOT be copied: {"name": Michael, "age": "40"}
#             Instead, create proper JSON with correct syntax and types.
#           PROMPT
#         }
#       ]

#       # First try without healing
#       no_heal_response = no_heal_client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: basic_schema,
#         extras: { max_tokens: 200, temperature: 0.4 }
#       )

#       # Then try with healing enabled
#       heal_response = client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: basic_schema,
#         extras: { max_tokens: 200, temperature: 0.4 }
#       )

#       # Both should work in ideal cases, but healing provides a safety net
#       no_heal_structured = no_heal_response.structured_output(auto_heal: false)
#       heal_structured = heal_response.structured_output(auto_heal: true)

#       expect(no_heal_structured).to be_a(Hash)
#       expect(heal_structured).to be_a(Hash)

#       expect(no_heal_structured["name"]).to include("Michael")
#       expect(heal_structured["name"]).to include("Michael")
#       expect(no_heal_structured["age"]).to eq(40)
#       expect(heal_structured["age"]).to eq(40)

#       puts "No heal content: #{no_heal_response.content}"
#       puts "With heal content: #{heal_response.content}"
#       puts "No heal parsed: #{no_heal_structured.inspect}"
#       puts "With heal parsed: #{heal_structured.inspect}"
#     end
#   end

#   describe "real-world malformation scenarios", vcr: { cassette_name: "healing_real_world" } do
#     it "handles common JSON malformation patterns from LLM responses" do
#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             You need to create a JSON response for contact information.

#             Create JSON for:
#             - Name: Dr. Jane Smith-Johnson
#             - Age: 42
#             - Email: jane.smith+work@company-name.co.uk

#             Common mistakes to avoid:
#             1. Missing quotes around strings
#             2. Using single quotes instead of double
#             3. Trailing commas
#             4. Unescaped quotes in values

#             Return ONLY valid JSON matching the required schema.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: basic_schema,
#         extras: { max_tokens: 300, temperature: 0.7 }
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to include("Jane")
#       expect(structured["name"]).to include("Smith")
#       expect(structured["age"]).to eq(42)

#       if structured["email"]
#         expect(structured["email"]).to include("jane.smith")
#         expect(structured["email"]).to include("@")
#       end

#       puts "Real-world scenario content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end

#   describe "healing validation with json-schema", vcr: { cassette_name: "healing_schema_validation" } do
#     it "heals responses that fail schema validation" do
#       # Skip if json-schema gem not available
#       skip "json-schema gem not available" unless defined?(JSON::Validator)

#       # Create a schema that's likely to catch type errors
#       strict_schema = OpenRouter::Schema.define("strict_person") do
#         string :name, required: true
#         integer :age, required: true # Must be integer, not string
#         string :status, required: true # Must be present
#       end

#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Create JSON for a person with:
#             - name: "Alice Cooper"
#             - age: 35 (make sure this is a number, not a string!)
#             - status: "active"

#             Common error would be: {"name": "Alice Cooper", "age": "35", "status": "active"}
#             But age should be numeric, not string.

#             Provide correct JSON with proper types.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: strict_schema,
#         extras: { max_tokens: 200, temperature: 0.5 }
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to eq("Alice Cooper")
#       expect(structured["age"]).to be_a(Integer)
#       expect(structured["age"]).to eq(35)
#       expect(structured["status"]).to eq("active")

#       # Test validation
#       expect(response.valid_structured_output?).to be true
#       expect(response.validation_errors).to be_empty

#       puts "Schema validation content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#       puts "Validation status: #{response.valid_structured_output?}"
#     end
#   end

#   describe "healing with different temperature settings", vcr: { cassette_name: "healing_temperature_test" } do
#     it "tests healing with high temperature responses" do
#       messages = [
#         {
#           role: "user",
#           content: <<~PROMPT
#             Generate creative JSON for a fictional character:
#             - name: Something creative with special characters
#             - age: Random age between 20-60

#             Be creative but ensure valid JSON syntax.
#             Special characters in names are okay if properly escaped.
#           PROMPT
#         }
#       ]

#       response = client.complete(
#         messages,
#         model: "openai/gpt-4o-mini",
#         response_format: basic_schema,
#         extras: { max_tokens: 300, temperature: 1.0 } # Maximum creativity
#       )

#       structured = response.structured_output(auto_heal: true)

#       expect(structured).to be_a(Hash)
#       expect(structured["name"]).to be_a(String)
#       expect(structured["name"]).not_to be_empty
#       expect(structured["age"]).to be_a(Integer)
#       expect(structured["age"]).to be_between(20, 60)

#       puts "High temperature content: #{response.content}"
#       puts "Parsed structure: #{structured.inspect}"
#     end
#   end
# end
