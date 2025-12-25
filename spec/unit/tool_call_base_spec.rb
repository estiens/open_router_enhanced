# frozen_string_literal: true

require "spec_helper"

# Simple result class for testing
class TestToolResult
  attr_reader :result, :error

  def initialize(result, error)
    @result = result
    @error = error
  end

  def success?
    @error.nil?
  end
end

RSpec.describe OpenRouter::ToolCallBase do
  # Test class that includes the module
  let(:test_class) do
    Class.new do
      include OpenRouter::ToolCallBase

      attr_reader :name, :arguments_string

      def initialize(name, arguments_string)
        @name = name
        @arguments_string = arguments_string
      end

      def build_result(result, error = nil)
        TestToolResult.new(result, error)
      end
    end
  end

  describe "#arguments" do
    it "parses valid JSON" do
      tc = test_class.new("test", '{"key": "value"}')
      expect(tc.arguments).to eq({ "key" => "value" })
    end

    it "memoizes the result" do
      tc = test_class.new("test", '{"key": "value"}')
      first = tc.arguments
      second = tc.arguments
      expect(first).to equal(second)
    end

    it "raises ToolCallError for invalid JSON" do
      tc = test_class.new("test", "not json")
      expect { tc.arguments }.to raise_error(OpenRouter::ToolCallError)
    end
  end

  describe "#execute" do
    it "requires a block" do
      tc = test_class.new("test", "{}")
      expect { tc.execute }.to raise_error(ArgumentError, /Block required/)
    end

    it "passes name and arguments to block" do
      tc = test_class.new("my_func", '{"x": 1}')

      received = nil
      tc.execute do |name, args|
        received = [name, args]
        "ok"
      end

      expect(received).to eq(["my_func", { "x" => 1 }])
    end

    it "returns result from build_result on success" do
      tc = test_class.new("test", "{}")
      result = tc.execute { "success" }

      expect(result.result).to eq("success")
      expect(result.success?).to be true
    end

    it "captures errors and passes to build_result" do
      tc = test_class.new("test", "{}")
      result = tc.execute { raise "boom" }

      expect(result.error).to eq("boom")
      expect(result.success?).to be false
    end
  end
end

RSpec.describe OpenRouter::ToolResultBase do
  let(:test_class) do
    Class.new do
      include OpenRouter::ToolResultBase

      attr_reader :tool_call, :result, :error

      def initialize(tool_call, result, error)
        @tool_call = tool_call
        @result = result
        @error = error
      end
    end
  end

  describe "#success?" do
    it "returns true when error is nil" do
      result = test_class.new(nil, "ok", nil)
      expect(result.success?).to be true
    end

    it "returns false when error is present" do
      result = test_class.new(nil, nil, "failed")
      expect(result.success?).to be false
    end
  end

  describe "#failure?" do
    it "returns false when error is nil" do
      result = test_class.new(nil, "ok", nil)
      expect(result.failure?).to be false
    end

    it "returns true when error is present" do
      result = test_class.new(nil, nil, "failed")
      expect(result.failure?).to be true
    end
  end

  describe ".success" do
    it "creates a successful result" do
      result = test_class.success(:tc, "data")
      expect(result.result).to eq("data")
      expect(result.error).to be_nil
    end
  end

  describe ".failure" do
    it "creates a failed result" do
      result = test_class.failure(:tc, "error msg")
      expect(result.error).to eq("error msg")
      expect(result.result).to be_nil
    end
  end
end
