# frozen_string_literal: true

require "spec_helper"
require "open_router"

RSpec.describe "Debug Healing" do
  let(:client) do
    OpenRouter::Client.new(access_token: "test-key") do |config|
      config.auto_heal_responses = true
      config.healer_model = "openai/gpt-4o-mini"
      config.max_heal_attempts = 2
    end
  end

  let(:malformed_json) { '{"name": "John", age: 30}' }
  let(:valid_json) { '{"name": "John", "age": 30}' }
  let(:basic_schema) { { type: "json_schema", json_schema: { schema: { type: "object" } } } }

  it "debugs the healing flow" do
    # Create response with malformed JSON
    response = OpenRouter::Response.new(
      { "choices" => [{ "message" => { "content" => malformed_json } }] },
      response_format: basic_schema
    )
    response.client = client

    # Check if structured output is expected
    puts "Structured output expected: #{response.send(:structured_output_expected?)}"
    puts "Has content: #{response.has_content?}"
    puts "Content: #{response.content}"
    puts "Client present: #{!response.client.nil?}"
    puts "Auto heal enabled: #{response.client.configuration.auto_heal_responses}"

    # Mock the healing response
    healed_response = double("Response", content: valid_json)
    expect(client).to receive(:complete).and_return(healed_response)

    begin
      result = response.structured_output(auto_heal: true)
      puts "Result: #{result.inspect}"
      expect(result).to eq({ "name" => "John", "age" => 30 })
    rescue StandardError => e
      puts "Error: #{e.class} - #{e.message}"
      puts "Backtrace: #{e.backtrace.first(5).join("\n")}"
      raise e
    end
  end
end
