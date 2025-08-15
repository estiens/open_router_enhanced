# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Callback System", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:messages) do
    [{ role: "user", content: "Hello, world!" }]
  end

  describe "request callbacks" do
    it "executes before_request callbacks", vcr: { cassette_name: "callbacks_before_request" } do
      callback_data = nil

      client.on :before_request do |params|
        callback_data = params
      end

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(callback_data).to be_a(Hash)
      expect(callback_data).to include(:messages, :model)
      expect(callback_data[:messages]).to eq(messages)
      expect(callback_data[:model]).to eq("openai/gpt-3.5-turbo")
      expect(response).to be_a(OpenRouter::Response)
    end

    it "executes after_response callbacks", vcr: { cassette_name: "callbacks_after_response" } do
      callback_data = nil

      client.on :after_response do |response|
        callback_data = response
      end

      result = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(callback_data).to be_a(OpenRouter::Response)
      expect(callback_data).to eq(result)
      expect(callback_data.content).to be_a(String)
    end
  end

  describe "tool call callbacks" do
    let(:calculator_tool) do
      OpenRouter::Tool.define do
        name "add_numbers"
        description "Add two numbers together"
        parameters do
          number "a", required: true, description: "First number"
          number "b", required: true, description: "Second number"
        end
      end
    end

    it "executes on_tool_call callbacks", vcr: { cassette_name: "callbacks_tool_calls" } do
      callback_data = nil

      client.on :on_tool_call do |tool_calls|
        callback_data = tool_calls
      end

      response = client.complete(
        [{ role: "user", content: "What is 5 + 3?" }],
        model: "openai/gpt-4o-mini",
        tools: [calculator_tool],
        extras: { max_tokens: 200 }
      )

      if response.has_tool_calls?
        expect(callback_data).to be_an(Array)
        expect(callback_data.first).to be_a(OpenRouter::ToolCall)
        expect(callback_data.first.name).to eq("add_numbers")
      end
    end
  end

  describe "error callbacks" do
    it "executes on_error callbacks", vcr: { cassette_name: "callbacks_on_error" } do
      callback_data = nil
      bad_client = OpenRouter::Client.new(access_token: "invalid_token")

      bad_client.on :on_error do |error|
        callback_data = error
      end

      expect do
        bad_client.complete(messages, model: "openai/gpt-3.5-turbo")
      end.to raise_error(Faraday::Error)

      expect(callback_data).to be_a(Exception)
    end
  end

  describe "multiple callbacks" do
    it "executes all callbacks for the same event", vcr: { cassette_name: "callbacks_multiple" } do
      callback_results = []

      client.on :before_request do |params|
        callback_results << params[:model]
      end

      client.on :before_request do |params|
        callback_results << "second_#{params[:model]}"
      end

      client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(callback_results).to eq([
                                       "openai/gpt-3.5-turbo",
                                       "second_openai/gpt-3.5-turbo"
                                     ])
    end

    it "executes callbacks in the order they were added", vcr: { cassette_name: "callbacks_order" } do
      execution_order = []

      client.on :before_request do |_params|
        execution_order << :first
      end

      client.on :before_request do |_params|
        execution_order << :second
      end

      client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(execution_order).to eq(%i[first second])
    end
  end

  describe "callback data integrity" do
    it "provides complete request data in before_request", vcr: { cassette_name: "callbacks_request_data" } do
      callback_data = nil

      client.on :before_request do |params|
        callback_data = params
      end

      client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: {
          max_tokens: 30,
          temperature: 0.5
        }
      )

      expect(callback_data).to include(
        messages: messages,
        model: "openai/gpt-3.5-turbo",
        max_tokens: 30,
        temperature: 0.5
      )
    end

    it "provides response object in after_response", vcr: { cassette_name: "callbacks_response_data" } do
      callback_data = nil

      client.on :after_response do |response|
        callback_data = response
      end

      client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(callback_data).to be_a(OpenRouter::Response)
      expect(callback_data.content).to be_a(String)
      expect(callback_data.total_tokens).to be > 0
    end
  end

  describe "callback clearing" do
    it "can clear all callbacks for an event", vcr: { cassette_name: "callbacks_clear" } do
      callback_data = {}

      client.on :before_request do |_params|
        callback_data[:should_not_execute1] = true
      end

      client.on :before_request do |_params|
        callback_data[:should_not_execute2] = true
      end

      client.clear_callbacks :before_request

      client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 20 }
      )

      expect(callback_data).to be_empty
    end
  end

  describe "callback system with structured outputs" do
    let(:schema) do
      OpenRouter::Schema.define("test_response") do
        string :message, required: true
        integer :confidence, required: true
      end
    end

    let(:response_format) do
      {
        type: "json_schema",
        json_schema: schema.to_h
      }
    end

    it "includes structured output data in callbacks", vcr: { cassette_name: "callbacks_structured_output" } do
      skip "VCR cassette mismatch - needs re-recording with current API"

      callback_data = nil

      client.on :after_response do |response|
        callback_data = response
      end

      response = client.complete(
        [{ role: "user", content: "Generate a test message with confidence score" }],
        model: "openai/gpt-4o-mini",
        response_format: response_format,
        extras: { max_tokens: 100 }
      )

      expect(callback_data).to be_a(OpenRouter::Response)
      expect(callback_data).to eq(response)

      structured = response.structured_output
      expect(structured).to be_a(Hash)
    end
  end
end
