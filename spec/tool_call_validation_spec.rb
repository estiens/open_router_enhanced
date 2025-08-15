# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::ToolCall do
  describe "argument validation" do
    let(:search_tool) do
      OpenRouter::Tool.define do
        name "search_books"
        description "Search for books"

        parameters do
          string :query, required: true, description: "Search query"
          integer :limit, description: "Max results", minimum: 1, maximum: 100
          boolean :include_reviews, description: "Include reviews"
        end
      end
    end

    let(:valid_tool_call) do
      OpenRouter::ToolCall.new({
                                 "id" => "call_123",
                                 "type" => "function",
                                 "function" => {
                                   "name" => "search_books",
                                   "arguments" => '{"query": "Ruby programming", "limit": 10, "include_reviews": true}'
                                 }
                               })
    end

    let(:invalid_tool_call_missing_required) do
      OpenRouter::ToolCall.new({
                                 "id" => "call_456",
                                 "type" => "function",
                                 "function" => {
                                   "name" => "search_books",
                                   "arguments" => '{"limit": 5}' # Missing required "query"
                                 }
                               })
    end

    let(:invalid_tool_call_wrong_types) do
      OpenRouter::ToolCall.new({
                                 "id" => "call_789",
                                 "type" => "function",
                                 "function" => {
                                   "name" => "search_books",
                                   "arguments" => '{"query": 123, "limit": "not_a_number", "include_reviews": "not_boolean"}'
                                 }
                               })
    end

    describe "#valid?" do
      it "returns true for valid arguments" do
        expect(valid_tool_call.valid?(tools: [search_tool])).to be true
      end

      it "returns false for missing required fields" do
        expect(invalid_tool_call_missing_required.valid?(tools: [search_tool])).to be false
      end

      if defined?(JSON::Validator)
        it "returns false for wrong argument types" do
          expect(invalid_tool_call_wrong_types.valid?(tools: [search_tool])).to be false
        end
      end

      it "returns true when no matching tool is found (graceful fallback)" do
        # When tool definition isn't found, validation is skipped
        expect(valid_tool_call.valid?(tools: [])).to be true
      end

      it "raises error if tools parameter is not provided" do
        expect do
          valid_tool_call.valid?
        end.to raise_error(ArgumentError, /tools/)
      end
    end

    describe "#validation_errors" do
      it "returns empty array for valid arguments" do
        errors = valid_tool_call.validation_errors(tools: [search_tool])
        expect(errors).to be_empty
      end

      it "returns errors for missing required fields" do
        errors = invalid_tool_call_missing_required.validation_errors(tools: [search_tool])
        expect(errors).not_to be_empty
        expect(errors.join(" ")).to include("query")
      end

      if defined?(JSON::Validator)
        it "returns detailed validation errors for wrong types" do
          errors = invalid_tool_call_wrong_types.validation_errors(tools: [search_tool])
          expect(errors).not_to be_empty
          # Should report type errors
          error_text = errors.join(" ").downcase
          expect(error_text).to match(/(type|invalid|expected)/i)
        end
      end

      it "returns empty array when no matching tool is found" do
        errors = valid_tool_call.validation_errors(tools: [])
        expect(errors).to be_empty
      end

      it "raises error if tools parameter is not provided" do
        expect do
          valid_tool_call.validation_errors
        end.to raise_error(ArgumentError, /tools/)
      end
    end

    describe "graceful degradation without json-schema gem" do
      before do
        # Simulate json-schema gem not being available
        allow_any_instance_of(OpenRouter::ToolCall).to receive(:validation_available?).and_return(false)
      end

      it "falls back to basic required field checking for valid?" do
        expect(valid_tool_call.valid?(tools: [search_tool])).to be true
        expect(invalid_tool_call_missing_required.valid?(tools: [search_tool])).to be false
      end

      it "falls back to basic required field checking for validation_errors" do
        errors = invalid_tool_call_missing_required.validation_errors(tools: [search_tool])
        expect(errors).not_to be_empty
        expect(errors.first).to include("Missing required")
      end
    end
  end
end
