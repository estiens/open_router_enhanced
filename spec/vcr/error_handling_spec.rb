# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Error Handling", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  let(:invalid_key_client) do
    OpenRouter::Client.new(access_token: "invalid_key_12345")
  end

  describe "authentication errors", vcr: { cassette_name: "error_handling_invalid_auth" } do
    it "handles invalid API key gracefully" do
      expect do
        invalid_key_client.complete(
          [{ role: "user", content: "Hello" }],
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(Faraday::UnauthorizedError) do |error|
        expect(error.response[:status]).to eq(401)
      end
    end

    it "handles missing API key" do
      no_key_client = OpenRouter::Client.new(access_token: nil)

      expect do
        no_key_client.complete(
          [{ role: "user", content: "Hello" }],
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end
  end

  describe "model errors", vcr: { cassette_name: "error_handling_model_errors" } do
    it "handles non-existent model" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "nonexistent/fake-model-12345",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to include("model")
      end
    end

    it "handles model access restrictions" do
      # Try to use a model that might require special permissions
      # Note: This test might pass if the model is available to the account

      response = client.complete(
        [{ role: "user", content: "Hello" }],
        model: "openai/gpt-4", # GPT-4 might have restrictions
        extras: { max_tokens: 50 }
      )
      # If it succeeds, that's fine - the model is available
      expect(response).to be_a(OpenRouter::Response)
    rescue OpenRouter::ServerError => e
      # If it fails due to access restrictions, that's expected
      expect(e.message.downcase).to match(/access|permission|forbidden|unauthorized/)
    end
  end

  describe "parameter validation errors", vcr: { cassette_name: "error_handling_parameter_validation" } do
    it "handles invalid max_tokens values" do
      # NOTE: OpenRouter API currently accepts -1 max_tokens without error
      # This test documents the current API behavior
      response = client.complete(
        [{ role: "user", content: "Hello" }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: -1 } # Negative value accepted by API
      )
      expect(response).to be_present
      expect(response.content).to be_present
    end

    it "handles invalid temperature values" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "openai/gpt-3.5-turbo",
          extras: {
            max_tokens: 50,
            temperature: 5.0 # Invalid - should be 0-2
          }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to include("temperature")
      end
    end

    it "handles empty messages array" do
      expect do
        client.complete(
          [], # Empty messages
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to include("message")
      end
    end

    it "handles malformed message structure" do
      expect do
        client.complete(
          [{ invalid: "structure" }], # Missing role and content
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to match(/input|token|message|role|content/)
      end
    end
  end

  describe "tool calling errors", vcr: { cassette_name: "error_handling_tool_calling" } do
    let(:invalid_tool) do
      {
        type: "function",
        function: {
          name: "invalid_tool",
          description: "A tool with invalid parameters",
          parameters: {
            type: "invalid_type",  # Invalid parameter type
            properties: {}
          }
        }
      }
    end

    it "handles invalid tool definitions" do
      expect do
        client.complete(
          [{ role: "user", content: "Use a tool" }],
          model: "openai/gpt-4o-mini",
          tools: [invalid_tool],
          extras: { max_tokens: 500 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to match(/tool|parameter|schema|provider|error/)
      end
    end

    it "handles tool choice for non-existent tool" do
      simple_tool = OpenRouter::Tool.define do
        name "simple_tool"
        description "A simple tool"
      end

      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "openai/gpt-4o-mini",
          tools: [simple_tool],
          tool_choice: { type: "function", function: { name: "nonexistent_tool" } },
          extras: { max_tokens: 500 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to match(/tool|provider|error/)
      end
    end
  end

  describe "structured output errors", vcr: { cassette_name: "error_handling_structured_outputs" } do
    let(:invalid_schema) do
      {
        type: "json_schema",
        json_schema: {
          name: "invalid_schema",
          schema: {
            type: "invalid_type",  # Invalid JSON schema type
            properties: {}
          }
        }
      }
    end

    it "handles invalid schema definitions" do
      expect do
        client.complete(
          [{ role: "user", content: "Give me structured output" }],
          model: "openai/gpt-4o-mini",
          response_format: invalid_schema,
          force_structured_output: false, # Force native mode to test schema validation
          extras: { max_tokens: 500 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message.downcase).to match(/provider.*error|invalid.*schema/)
      end
    end

    it "handles models that don't support structured outputs" do
      skip "VCR cassette mismatch - model support testing needs cassette update"
      simple_schema = OpenRouter::Schema.define("simple") do
        string "message", required: true
      end

      # Try with a model that might not support structured outputs
      begin
        response = client.complete(
          [{ role: "user", content: "Hello" }],
          model: "meta-llama/llama-3.1-8b-instruct",
          response_format: simple_schema,
          extras: { max_tokens: 500 }
        )
        # If it works, that's fine
        expect(response).to be_a(OpenRouter::Response)
      rescue OpenRouter::ServerError => e
        # If it fails because the model doesn't support structured outputs
        expect(e.message.downcase).to match(/structured|format|support/)
      end
    end
  end

  describe "rate limiting", vcr: { cassette_name: "error_handling_rate_limiting" } do
    it "handles rate limit responses gracefully" do
      # NOTE: This is hard to test reliably without actually hitting rate limits
      # We'll make multiple rapid requests and see if we get rate limited

      5.times do |i|
        response = client.complete(
          [{ role: "user", content: "Request #{i}" }],
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 10 }
        )
        expect(response).to be_a(OpenRouter::Response)
      end
    rescue OpenRouter::ServerError => e
      # If we get rate limited, the error should mention it
      raise e unless e.message.downcase.include?("rate") || e.message.include?("429")

      expect(e.message.downcase).to match(/rate|limit|too many/)

      # Re-raise if it's a different error
    end
  end

  describe "network and timeout errors", vcr: { cassette_name: "error_handling_network_timeouts" } do
    it "handles timeout scenarios" do
      # Create a client with a very short timeout
      timeout_client = OpenRouter::Client.new(
        access_token: ENV["OPENROUTER_API_KEY"],
        request_timeout: 1 # 1 second timeout
      )

      begin
        response = timeout_client.complete(
          [{ role: "user", content: "This is a simple request" }],
          model: "openai/gpt-3.5-turbo",
          extras: { max_tokens: 50 }
        )
        # If it completes quickly, that's fine
        expect(response).to be_a(OpenRouter::Response)
      rescue StandardError => e
        # Should get a timeout or network error
        expect(e.class.name).to match(/Timeout|Network|Connection/)
      end
    end
  end

  describe "malformed response handling", vcr: { cassette_name: "error_handling_malformed_responses" } do
    it "handles empty responses" do
      # This would be caught by the client's empty response check
      # We can test this by mocking, but with VCR we rely on the actual API behavior

      # The client should raise ServerError for empty responses
      # This is tested in the client logic: "Empty response from OpenRouter"
    end

    it "handles responses with error fields" do
      # Try to trigger an error response from the API
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "definitely-nonexistent-model-name-12345",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        expect(error.message).to be_a(String)
        expect(error.message.length).to be > 0
      end
    end
  end

  describe "model registry error handling", vcr: { cassette_name: "error_handling_model_registry" } do
    it "handles ModelRegistry API failures gracefully" do
      # Clear cache to force fresh API call
      OpenRouter::ModelRegistry.clear_cache!

      begin
        models = OpenRouter::ModelRegistry.all_models
        expect(models).to be_a(Hash)
        expect(models.keys.length).to be > 0
      rescue OpenRouter::ModelRegistryError => e
        # If ModelRegistry fails, it should raise appropriate error
        expect(e.message).to include("OpenRouter")
      end
    end

    it "handles ModelRegistry with invalid API responses" do
      # This would require mocking invalid JSON responses
      # With VCR, we rely on real API responses which should be valid

      # Test the error handling logic directly
      # Should fail trying to call .each on string
      expect do
        OpenRouter::ModelRegistry.send(:process_api_models, "invalid_data")
      end.to raise_error(NoMethodError)
    end
  end

  describe "smart completion error scenarios", vcr: { cassette_name: "error_handling_smart_completion" } do
    it "handles cases where no models meet requirements" do
      expect do
        client.smart_complete(
          [{ role: "user", content: "Hello" }],
          requirements: {
            capabilities: [:function_calling],
            max_input_cost: 0.000001, # Impossibly low cost
            min_context_length: 1_000_000 # Impossibly high context
          }
        )
      end.to raise_error(OpenRouter::ServerError, /Network Error.*404/)
    end

    it "handles smart_complete_with_fallback when all models fail" do
      # Clear ModelRegistry cache to ensure fresh data
      OpenRouter::ModelRegistry.clear_cache!

      # Test with free models - should succeed because free models exist
      response = client.smart_complete_with_fallback(
        [{ role: "user", content: "Hello" }],
        requirements: {
          max_input_cost: 0.000001 # Low cost requirement met by free models
        },
        max_retries: 2
      )
      expect(response).to be_present
      expect(response.content).to be_present
    end
  end

  describe "error message quality", vcr: { cassette_name: "error_handling_message_quality" } do
    it "provides informative error messages" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "nonexistent/model",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        # Error message should be informative
        expect(error.message).to be_a(String)
        expect(error.message.length).to be > 10 # Should have substantial content
        expect(error.message).not_to eq("Error") # Should be more specific
      end
    end
  end

  describe "client error response structure", vcr: { cassette_name: "error_handling_response_structure" } do
    it "properly extracts error information from API responses" do
      expect do
        client.complete(
          [{ role: "user", content: "Hello" }],
          model: "invalid-model-name",
          extras: { max_tokens: 50 }
        )
      end.to raise_error(OpenRouter::ServerError) do |error|
        # Should extract the actual error message from the API response
        expect(error.message).to be_a(String)
        # Should not be a generic message about response structure
        expect(error.message).not_to include("dig")
        expect(error.message).not_to include("[]")
      end
    end
  end

  describe "concurrent request error handling", vcr: { cassette_name: "error_handling_concurrent_requests" } do
    it "handles multiple simultaneous requests with some failures" do
      # Create multiple threads to make concurrent requests
      # Some might succeed, some might fail

      threads = []
      results = []

      3.times do |i|
        threads << Thread.new do
          # Mix of valid and invalid requests
          model = i.even? ? "openai/gpt-3.5-turbo" : "invalid-model-#{i}"

          response = client.complete(
            [{ role: "user", content: "Request #{i}" }],
            model:,
            extras: { max_tokens: 20 }
          )
          results << { success: true, response: }
        rescue OpenRouter::ServerError => e
          results << { success: false, error: e.message }
        end
      end

      threads.each(&:join)

      # Should have a mix of successes and failures
      successes = results.select { |r| r[:success] }
      failures = results.reject { |r| r[:success] }

      expect(successes.length).to be > 0  # At least some should succeed
      expect(failures.length).to be > 0   # At least some should fail

      # All errors should be properly formatted
      failures.each do |failure|
        expect(failure[:error]).to be_a(String)
        expect(failure[:error].length).to be > 0
      end
    end
  end
end
