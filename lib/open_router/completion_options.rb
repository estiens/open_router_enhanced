# frozen_string_literal: true

module OpenRouter
  # CompletionOptions provides a structured way to configure API requests.
  #
  # Supports all OpenRouter API parameters plus client-side options.
  # Can be used with complete(), stream_complete(), and responses() methods.
  #
  # @example Simple usage with kwargs (unchanged)
  #   client.complete(messages, model: "gpt-4")
  #
  # @example Using CompletionOptions for complex requests
  #   options = OpenRouter::CompletionOptions.new(
  #     model: "anthropic/claude-3.5-sonnet",
  #     temperature: 0.7,
  #     tools: [weather_tool],
  #     providers: ["anthropic"]
  #   )
  #   client.complete(messages, options)
  #
  # @example Merging options with overrides
  #   base_opts = CompletionOptions.new(model: "gpt-4", temperature: 0.5)
  #   client.complete(messages, base_opts, temperature: 0.9)  # overrides temperature
  #
  class CompletionOptions
    # ═══════════════════════════════════════════════════════════════════════════
    # Common params (used by both Complete and Responses APIs)
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [String, Array<String>] Model ID or array for fallback routing
    attr_accessor :model

    # @return [Array<Tool, Hash>] Tool/function definitions for function calling
    attr_accessor :tools

    # @return [String, Hash, nil] Tool selection: "auto", "none", "required", or specific
    attr_accessor :tool_choice

    # @return [Hash] Pass-through for any additional/future API params
    attr_accessor :extras

    # ═══════════════════════════════════════════════════════════════════════════
    # Sampling parameters (OpenRouter passes these to underlying models)
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [Float, nil] Sampling temperature (0.0-2.0, default 1.0)
    attr_accessor :temperature

    # @return [Float, nil] Nucleus sampling (0.0-1.0)
    attr_accessor :top_p

    # @return [Integer, nil] Limits token selection to top K options
    attr_accessor :top_k

    # @return [Float, nil] Frequency penalty (-2.0 to 2.0)
    attr_accessor :frequency_penalty

    # @return [Float, nil] Presence penalty (-2.0 to 2.0)
    attr_accessor :presence_penalty

    # @return [Float, nil] Repetition penalty (0.0-2.0)
    attr_accessor :repetition_penalty

    # @return [Float, nil] Minimum probability threshold (0.0-1.0)
    attr_accessor :min_p

    # @return [Float, nil] Dynamic filtering based on confidence (0.0-1.0)
    attr_accessor :top_a

    # @return [Integer, nil] Random seed for reproducibility
    attr_accessor :seed

    # ═══════════════════════════════════════════════════════════════════════════
    # Output control
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [Integer, nil] Legacy max tokens limit
    attr_accessor :max_tokens

    # @return [Integer, nil] Preferred max completion tokens limit
    attr_accessor :max_completion_tokens

    # @return [String, Array<String>, nil] Stop sequences
    attr_accessor :stop

    # @return [Boolean, nil] Return log probabilities of output tokens
    attr_accessor :logprobs

    # @return [Integer, nil] Number of top logprobs to return (0-20)
    attr_accessor :top_logprobs

    # @return [Hash, nil] Token ID to bias mapping (-100 to 100)
    attr_accessor :logit_bias

    # @return [Hash, Schema, nil] Structured output schema/format
    attr_accessor :response_format

    # @return [Boolean, nil] Allow parallel tool calls
    attr_accessor :parallel_tool_calls

    # @return [Symbol, String, nil] Output verbosity (:low, :medium, :high)
    attr_accessor :verbosity

    # ═══════════════════════════════════════════════════════════════════════════
    # OpenRouter-specific routing & features
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [Array<String>] Simple provider ordering (becomes provider.order)
    attr_accessor :providers

    # @return [Hash, nil] Full provider config (overrides :providers if set)
    #   Supports: order, only, ignore, allow_fallbacks, require_parameters,
    #   data_collection, zdr, quantizations, sort, max_price, etc.
    attr_accessor :provider

    # @return [Array<String>] Transform identifiers (e.g., ["middle-out"])
    attr_accessor :transforms

    # @return [Array<Hash>] Plugin configurations
    attr_accessor :plugins

    # @return [Hash, nil] Predicted output for latency reduction
    #   Format: { type: "content", content: "predicted text" }
    attr_accessor :prediction

    # @return [String, nil] Routing strategy: "fallback" or "sort"
    attr_accessor :route

    # @return [Hash, nil] Custom key-value metadata
    attr_accessor :metadata

    # @return [String, nil] End-user identifier for tracking
    attr_accessor :user

    # @return [String, nil] Session grouping identifier (max 128 chars)
    attr_accessor :session_id

    # ═══════════════════════════════════════════════════════════════════════════
    # Responses API specific
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [Hash, nil] Reasoning configuration for Responses API
    #   Format: { effort: "minimal"|"low"|"medium"|"high" }
    attr_accessor :reasoning

    # ═══════════════════════════════════════════════════════════════════════════
    # Client-side options (not sent to API)
    # ═══════════════════════════════════════════════════════════════════════════

    # @return [Boolean, nil] Override forced extraction mode for structured outputs
    #   true: Force extraction via system message injection
    #   false: Use native structured output
    #   nil: Auto-determine based on model capability
    attr_accessor :force_structured_output

    # All supported parameters with their defaults
    DEFAULTS = {
      # Common
      model: "openrouter/auto",
      tools: [],
      tool_choice: nil,
      extras: {},
      # Sampling
      temperature: nil,
      top_p: nil,
      top_k: nil,
      frequency_penalty: nil,
      presence_penalty: nil,
      repetition_penalty: nil,
      min_p: nil,
      top_a: nil,
      seed: nil,
      # Output
      max_tokens: nil,
      max_completion_tokens: nil,
      stop: nil,
      logprobs: nil,
      top_logprobs: nil,
      logit_bias: nil,
      response_format: nil,
      parallel_tool_calls: nil,
      verbosity: nil,
      # OpenRouter routing
      providers: [],
      provider: nil,
      transforms: [],
      plugins: [],
      prediction: nil,
      route: nil,
      metadata: nil,
      user: nil,
      session_id: nil,
      # Responses API
      reasoning: nil,
      # Client-side
      force_structured_output: nil
    }.freeze

    # Parameters that are client-side only (not sent to API)
    CLIENT_SIDE_PARAMS = %i[force_structured_output extras].freeze

    # Initialize with keyword arguments
    #
    # @param attrs [Hash] Parameter values (see DEFAULTS for available keys)
    def initialize(**attrs)
      DEFAULTS.each do |key, default|
        value = attrs.key?(key) ? attrs[key] : default
        # Deep dup arrays/hashes to prevent mutation of shared defaults
        value = value.dup if value.is_a?(Array) || value.is_a?(Hash)
        instance_variable_set(:"@#{key}", value)
      end
    end

    # Convert to hash, excluding nil values and empty collections
    #
    # @return [Hash] Non-empty parameter values
    def to_h
      DEFAULTS.keys.each_with_object({}) do |key, hash|
        value = instance_variable_get(:"@#{key}")
        next if value.nil?
        next if value.respond_to?(:empty?) && value.empty?

        hash[key] = value
      end
    end

    # Create a new CompletionOptions with merged overrides
    #
    # @param overrides [Hash] Values to override
    # @return [CompletionOptions] New instance with merged values
    def merge(**overrides)
      self.class.new(**to_h.merge(overrides))
    end

    # Build API request parameters hash
    # Excludes client-side-only options and merges extras
    #
    # @return [Hash] Parameters ready for API request
    def to_api_params
      api_params = to_h.reject { |key, _| CLIENT_SIDE_PARAMS.include?(key) }
      api_params.merge(extras || {})
    end

    # Check if this options object has any tools defined
    #
    # @return [Boolean]
    def has_tools?
      tools.is_a?(Array) && !tools.empty?
    end

    # Check if response format is configured
    #
    # @return [Boolean]
    def has_response_format?
      !response_format.nil?
    end

    # Check if using model fallback (array of models)
    #
    # @return [Boolean]
    def fallback_models?
      model.is_a?(Array)
    end
  end
end
