# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::Response do
  describe "#selected_model" do
    it "returns the model the router actually resolved" do
      response_hash = {
        "model" => "anthropic/claude-3.5-sonnet",
        "choices" => [{ "message" => { "role" => "assistant", "content" => "hi" } }]
      }
      response = described_class.new(response_hash)
      expect(response.selected_model).to eq("anthropic/claude-3.5-sonnet")
    end

    it "returns nil when the response has no model field" do
      response_hash = { "choices" => [] }
      response = described_class.new(response_hash)
      expect(response.selected_model).to be_nil
    end
  end
end
