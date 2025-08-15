# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Simple Healing Test", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV.fetch("OPENROUTER_API_KEY")) do |config|
      config.auto_heal_responses = true
      config.healer_model = "openai/gpt-4o-mini"
      config.max_heal_attempts = 2
    end
  end

  let(:basic_schema) do
    OpenRouter::Schema.define("person") do
      string :name, required: true
      integer :age, required: true
    end
  end

  describe "basic structured output", vcr: { cassette_name: "simple_structured_output" } do
    it "generates clean structured output" do
      messages = [
        {
          role: "user",
          content: "Create JSON for a person named Alice who is 25 years old. Use proper JSON format."
        }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-2024-08-06", # Model that supports structured outputs
        response_format: basic_schema,
        extras: { max_tokens: 200, temperature: 0.3 }
      )

      structured = response.structured_output(auto_heal: true)

      expect(structured).to be_a(Hash)
      expect(structured["name"]).to eq("Alice")
      expect(structured["age"]).to eq(25)

      puts "Content: #{response.content}"
      puts "Parsed: #{structured.inspect}"
    end
  end

  describe "basic completion without structured output", vcr: { cassette_name: "simple_basic_completion" } do
    it "works with basic completion" do
      messages = [
        {
          role: "user",
          content: "Say hello"
        }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-4o-mini",
        extras: { max_tokens: 50 }
      )

      expect(response.content).to be_a(String)
      expect(response.content).not_to be_empty

      puts "Basic completion: #{response.content}"
    end
  end
end
