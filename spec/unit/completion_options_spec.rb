# frozen_string_literal: true

require "spec_helper"

RSpec.describe OpenRouter::CompletionOptions do
  describe ".new" do
    it "sets default values" do
      options = described_class.new

      expect(options.model).to eq("openrouter/auto")
      expect(options.tools).to eq([])
      expect(options.tool_choice).to be_nil
      expect(options.extras).to eq({})
      expect(options.providers).to eq([])
      expect(options.transforms).to eq([])
      expect(options.plugins).to eq([])
      expect(options.temperature).to be_nil
      expect(options.top_p).to be_nil
    end

    it "accepts keyword arguments" do
      options = described_class.new(
        model: "gpt-4",
        temperature: 0.7,
        max_tokens: 1000
      )

      expect(options.model).to eq("gpt-4")
      expect(options.temperature).to eq(0.7)
      expect(options.max_tokens).to eq(1000)
    end

    it "deep dups arrays to prevent mutation" do
      tools = [{ name: "test" }]
      options = described_class.new(tools: tools)

      options.tools << { name: "another" }

      expect(tools.length).to eq(1)
      expect(options.tools.length).to eq(2)
    end

    it "deep dups hashes to prevent mutation" do
      extras = { foo: "bar" }
      options = described_class.new(extras: extras)

      options.extras[:baz] = "qux"

      expect(extras.keys).to eq([:foo])
      expect(options.extras.keys).to contain_exactly(:foo, :baz)
    end
  end

  describe "#to_h" do
    it "returns only non-nil, non-empty values" do
      options = described_class.new(
        model: "gpt-4",
        temperature: 0.5,
        tools: [] # empty, should be excluded
      )

      hash = options.to_h

      expect(hash).to eq({ model: "gpt-4", temperature: 0.5 })
      expect(hash).not_to have_key(:tools)
      expect(hash).not_to have_key(:top_p)
    end

    it "includes all set sampling parameters" do
      options = described_class.new(
        model: "gpt-4",
        temperature: 0.7,
        top_p: 0.9,
        top_k: 50,
        frequency_penalty: 0.5,
        presence_penalty: 0.3,
        repetition_penalty: 1.1,
        min_p: 0.05,
        top_a: 0.1,
        seed: 42
      )

      hash = options.to_h

      expect(hash[:temperature]).to eq(0.7)
      expect(hash[:top_p]).to eq(0.9)
      expect(hash[:top_k]).to eq(50)
      expect(hash[:frequency_penalty]).to eq(0.5)
      expect(hash[:presence_penalty]).to eq(0.3)
      expect(hash[:repetition_penalty]).to eq(1.1)
      expect(hash[:min_p]).to eq(0.05)
      expect(hash[:top_a]).to eq(0.1)
      expect(hash[:seed]).to eq(42)
    end

    it "includes output control parameters" do
      options = described_class.new(
        max_tokens: 500,
        max_completion_tokens: 600,
        stop: %W[\n END],
        logprobs: true,
        top_logprobs: 5,
        logit_bias: { "123" => 10 },
        parallel_tool_calls: false,
        verbosity: :high
      )

      hash = options.to_h

      expect(hash[:max_tokens]).to eq(500)
      expect(hash[:max_completion_tokens]).to eq(600)
      expect(hash[:stop]).to eq(%W[\n END])
      expect(hash[:logprobs]).to eq(true)
      expect(hash[:top_logprobs]).to eq(5)
      expect(hash[:logit_bias]).to eq({ "123" => 10 })
      expect(hash[:parallel_tool_calls]).to eq(false)
      expect(hash[:verbosity]).to eq(:high)
    end

    it "includes OpenRouter routing parameters" do
      options = described_class.new(
        providers: %w[anthropic openai],
        provider: { order: ["anthropic"], quantizations: ["fp16"] },
        transforms: ["middle-out"],
        plugins: [{ id: "web-search" }],
        prediction: { type: "content", content: "Hello" },
        route: "fallback",
        metadata: { request_id: "abc123" },
        user: "user_123",
        session_id: "session_456"
      )

      hash = options.to_h

      expect(hash[:providers]).to eq(%w[anthropic openai])
      expect(hash[:provider]).to eq({ order: ["anthropic"], quantizations: ["fp16"] })
      expect(hash[:transforms]).to eq(["middle-out"])
      expect(hash[:plugins]).to eq([{ id: "web-search" }])
      expect(hash[:prediction]).to eq({ type: "content", content: "Hello" })
      expect(hash[:route]).to eq("fallback")
      expect(hash[:metadata]).to eq({ request_id: "abc123" })
      expect(hash[:user]).to eq("user_123")
      expect(hash[:session_id]).to eq("session_456")
    end

    it "includes Responses API parameters" do
      options = described_class.new(
        model: "openai/o4-mini",
        reasoning: { effort: "high" }
      )

      hash = options.to_h

      expect(hash[:reasoning]).to eq({ effort: "high" })
    end
  end

  describe "#merge" do
    it "creates a new options with overrides" do
      original = described_class.new(model: "gpt-4", temperature: 0.5)
      merged = original.merge(temperature: 0.9, max_tokens: 100)

      expect(merged.model).to eq("gpt-4")
      expect(merged.temperature).to eq(0.9)
      expect(merged.max_tokens).to eq(100)

      # Original unchanged
      expect(original.temperature).to eq(0.5)
      expect(original.max_tokens).to be_nil
    end

    it "returns a new instance" do
      original = described_class.new(model: "gpt-4")
      merged = original.merge(temperature: 0.5)

      expect(merged).not_to be(original)
      expect(merged).to be_a(described_class)
    end
  end

  describe "#to_api_params" do
    it "excludes client-side-only parameters" do
      options = described_class.new(
        model: "gpt-4",
        temperature: 0.7,
        force_structured_output: true,
        extras: { custom_param: "value" }
      )

      api_params = options.to_api_params

      expect(api_params).to have_key(:model)
      expect(api_params).to have_key(:temperature)
      expect(api_params).not_to have_key(:force_structured_output)
      expect(api_params).not_to have_key(:extras)
    end

    it "merges extras into the api params" do
      options = described_class.new(
        model: "gpt-4",
        extras: { safe_prompt: true, custom_field: "value" }
      )

      api_params = options.to_api_params

      expect(api_params[:model]).to eq("gpt-4")
      expect(api_params[:safe_prompt]).to eq(true)
      expect(api_params[:custom_field]).to eq("value")
    end

    it "handles nil extras gracefully" do
      options = described_class.new(model: "gpt-4")
      options.extras = nil

      expect { options.to_api_params }.not_to raise_error
    end
  end

  describe "#tools?" do
    it "returns true when tools are defined" do
      options = described_class.new(tools: [{ name: "test" }])
      expect(options.tools?).to be true
    end

    it "returns false when tools are empty" do
      options = described_class.new(tools: [])
      expect(options.tools?).to be false
    end

    it "returns false when tools are nil" do
      options = described_class.new
      options.tools = nil
      expect(options.tools?).to be false
    end
  end

  describe "#response_format?" do
    it "returns true when response_format is set" do
      options = described_class.new(response_format: { type: "json_object" })
      expect(options.response_format?).to be true
    end

    it "returns false when response_format is nil" do
      options = described_class.new
      expect(options.response_format?).to be false
    end
  end

  describe "#fallback_models?" do
    it "returns true when model is an array" do
      options = described_class.new(model: ["gpt-4", "gpt-3.5-turbo"])
      expect(options.fallback_models?).to be true
    end

    it "returns false when model is a string" do
      options = described_class.new(model: "gpt-4")
      expect(options.fallback_models?).to be false
    end
  end

  describe "DEFAULTS" do
    it "includes all expected parameter keys" do
      expected_keys = %i[
        model tools tool_choice extras
        temperature top_p top_k frequency_penalty presence_penalty
        repetition_penalty min_p top_a seed
        max_tokens max_completion_tokens stop logprobs top_logprobs
        logit_bias response_format parallel_tool_calls verbosity
        providers provider transforms plugins prediction route
        metadata user session_id
        reasoning
        force_structured_output
      ]

      expect(described_class::DEFAULTS.keys).to contain_exactly(*expected_keys)
    end

    it "is frozen" do
      expect(described_class::DEFAULTS).to be_frozen
    end
  end

  describe "attr_accessors" do
    it "allows reading and writing all parameters" do
      options = described_class.new

      # Test a sampling param
      options.temperature = 0.8
      expect(options.temperature).to eq(0.8)

      # Test a routing param
      options.providers = ["openai"]
      expect(options.providers).to eq(["openai"])

      # Test a client-side param
      options.force_structured_output = true
      expect(options.force_structured_output).to eq(true)
    end
  end

  describe "integration scenarios" do
    it "works for a simple completion request" do
      options = described_class.new(model: "gpt-4", temperature: 0.7)

      expect(options.to_api_params).to eq({
                                            model: "gpt-4",
                                            temperature: 0.7
                                          })
    end

    it "works for a complex completion with tools and structured output" do
      tool = { type: "function", function: { name: "get_weather" } }
      schema = { type: "json_schema", json_schema: { name: "response" } }

      options = described_class.new(
        model: "anthropic/claude-3.5-sonnet",
        tools: [tool],
        tool_choice: "auto",
        response_format: schema,
        temperature: 0.5,
        max_tokens: 1000,
        providers: ["anthropic"],
        force_structured_output: false
      )

      api_params = options.to_api_params

      expect(api_params[:model]).to eq("anthropic/claude-3.5-sonnet")
      expect(api_params[:tools]).to eq([tool])
      expect(api_params[:tool_choice]).to eq("auto")
      expect(api_params[:response_format]).to eq(schema)
      expect(api_params[:temperature]).to eq(0.5)
      expect(api_params[:max_tokens]).to eq(1000)
      expect(api_params[:providers]).to eq(["anthropic"])
      expect(api_params).not_to have_key(:force_structured_output)
    end

    it "works for Responses API with reasoning" do
      options = described_class.new(
        model: "openai/o4-mini",
        reasoning: { effort: "high" },
        temperature: 0.3
      )

      api_params = options.to_api_params

      expect(api_params[:model]).to eq("openai/o4-mini")
      expect(api_params[:reasoning]).to eq({ effort: "high" })
      expect(api_params[:temperature]).to eq(0.3)
    end

    it "works with fallback models" do
      options = described_class.new(
        model: ["gpt-4", "gpt-3.5-turbo", "claude-3-sonnet"],
        route: "fallback",
        temperature: 0.7
      )

      expect(options.fallback_models?).to be true
      expect(options.to_api_params[:model]).to eq(["gpt-4", "gpt-3.5-turbo", "claude-3-sonnet"])
      expect(options.to_api_params[:route]).to eq("fallback")
    end

    it "works with full provider configuration" do
      options = described_class.new(
        model: "gpt-4",
        provider: {
          order: %w[openai azure],
          allow_fallbacks: true,
          require_parameters: true,
          quantizations: %w[fp16 bf16],
          max_price: { prompt: 0.01, completion: 0.03 }
        }
      )

      provider_config = options.to_api_params[:provider]

      expect(provider_config[:order]).to eq(%w[openai azure])
      expect(provider_config[:allow_fallbacks]).to eq(true)
      expect(provider_config[:quantizations]).to eq(%w[fp16 bf16])
    end
  end
end
