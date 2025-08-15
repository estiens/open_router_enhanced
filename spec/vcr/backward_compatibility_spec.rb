# frozen_string_literal: true

require "spec_helper"

RSpec.describe "OpenRouter Backward Compatibility", :vcr do
  let(:client) do
    OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
  end

  describe "Core API Compatibility" do
    it "supports basic API calls with original method signature", vcr: { cassette_name: "compat_complete_method" } do
      messages = [
        { role: "user", content: "Original complete method test" }
      ]

      response = client.complete(
        messages,
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 50 }
      )

      expect(response).to respond_to(:dig)
      expect(response["choices"]).to be_an(Array)
      expect(response.dig("choices", 0, "message", "content")).to be_a(String)
    end

    it "maintains hash-like response access patterns", vcr: { cassette_name: "compat_hash_access" } do
      response = client.complete(
        [{ role: "user", content: "Hash access test" }],
        model: "openai/gpt-3.5-turbo",
        extras: { max_tokens: 30 }
      )

      expect(response["id"]).to be_a(String)
      expect(response["choices"]).to be_an(Array)
      expect(response["usage"]).to be_a(Hash)
      expect(response.dig("choices", 0, "message")).to be_a(Hash)
      expect(response.key?("choices")).to be true
      expect(response.keys).to include("choices")
    end

    it "supports original parameter passing with extras", vcr: { cassette_name: "compat_parameters" } do
      response = client.complete(
        [{ role: "user", content: "Parameter compatibility test" }],
        model: "openai/gpt-3.5-turbo",
        extras: {
          max_tokens: 40,
          temperature: 0.7,
          top_p: 0.9
        }
      )

      expect(response).to be_a(OpenRouter::Response)
      expect(response["choices"]).not_to be_empty
      expect(response["usage"]).to have_key("total_tokens")
    end
  end

  describe "Error Handling Compatibility" do
    it "maintains original error types for auth failures", vcr: { cassette_name: "compat_error_types" } do
      bad_client = OpenRouter::Client.new(access_token: "invalid_token")

      expect do
        bad_client.complete(
          [{ role: "user", content: "Error test" }],
          model: "openai/gpt-3.5-turbo"
        )
      end.to raise_error(Faraday::UnauthorizedError)
    end
  end

  describe "Module Structure Compatibility" do
    it "maintains version information and module structure", vcr: { cassette_name: "compat_version_info" } do
      expect(OpenRouter::VERSION).to be_a(String)
      expect(OpenRouter::VERSION).to match(/\d+\.\d+\.\d+/)
    end

    it "maintains core class accessibility", vcr: { cassette_name: "compat_module_structure" } do
      expect(OpenRouter::Client).to be_a(Class)
      expect(OpenRouter::Response).to be_a(Class)

      client = OpenRouter::Client.new(access_token: ENV["OPENROUTER_API_KEY"])
      expect(client).to be_a(OpenRouter::Client)
    end
  end
end
