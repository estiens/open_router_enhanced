# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"

require_relative "http"
require_relative "callbacks"
require_relative "parameter_builder"
require_relative "tool_serializer"
require_relative "request_handler"

module OpenRouter
  class ServerError < StandardError; end

  class Client
    include OpenRouter::HTTP
    include OpenRouter::Callbacks
    include OpenRouter::ParameterBuilder
    include OpenRouter::ToolSerializer
    include OpenRouter::RequestHandler

    attr_reader :callbacks, :usage_tracker, :configuration

    def initialize(access_token: nil, request_timeout: nil, uri_base: nil, extra_headers: {}, track_usage: true)
      # Build a per-instance configuration to avoid mutating the global singleton,
      # which would cause credential leakage across Client instances in concurrent use.
      @configuration = OpenRouter.configuration.dup
      @configuration.extra_headers = OpenRouter.configuration.extra_headers.dup
      @configuration.access_token = access_token if access_token
      @configuration.request_timeout = request_timeout if request_timeout
      @configuration.uri_base = uri_base if uri_base
      @configuration.extra_headers = @configuration.extra_headers.merge(extra_headers) if extra_headers.any?
      yield(@configuration) if block_given?

      @capability_warnings_shown = Set.new

      @callbacks = {
        before_request: [],
        after_response: [],
        on_tool_call: [],
        on_error: [],
        on_stream_chunk: [],
        on_healing: []
      }

      @track_usage = track_usage
      @usage_tracker = UsageTracker.new if @track_usage
    end

    # Performs a chat completion request to the OpenRouter API.
    #
    # @param messages [Array<Hash>] Array of message hashes with role and content
    # @param options [CompletionOptions, Hash, nil] Options object or hash with configuration
    # @param stream [Proc, nil] Optional callable object for streaming
    # @param kwargs [Hash] Additional options (merged with options parameter)
    # @return [Response] The completion response wrapped in a Response object
    def complete(messages, options = nil, stream: nil, **kwargs)
      opts = normalize_options(options, kwargs)
      parameters = prepare_base_parameters(messages, opts, stream)
      forced_extraction = configure_tools_and_structured_outputs!(parameters, opts)
      configure_plugins!(parameters, opts.response_format, stream)
      validate_vision_support(opts.model, messages)

      trigger_callbacks(:before_request, parameters)

      raw_response = execute_request(parameters)
      validate_response!(raw_response, stream)

      response = build_response(raw_response, opts.response_format, forced_extraction)

      model_for_tracking = opts.model.is_a?(String) ? opts.model : opts.model.first
      @usage_tracker&.track(response, model: model_for_tracking)

      trigger_callbacks(:after_response, response)
      trigger_callbacks(:on_tool_call, response.tool_calls) if response.has_tool_calls?

      response
    end

    # Fetches the list of available models from the OpenRouter API.
    def models
      get(path: "/models")["data"]
    end

    # Queries the generation stats for a given id.
    def query_generation_stats(generation_id)
      response = get(path: "/generation?id=#{generation_id}")
      response["data"]
    end

    # Performs a request to the Responses API Beta (/api/v1/responses)
    #
    # @param input [String, Array] The input text or structured message array
    # @param options [CompletionOptions, Hash, nil] Options object or hash with configuration
    # @param kwargs [Hash] Additional options (merged with options parameter)
    # @return [ResponsesResponse] The response wrapped in a ResponsesResponse object
    def responses(input, options = nil, **kwargs)
      opts = normalize_options(options, kwargs)

      if opts.model == "openrouter/auto"
        raise ArgumentError, "model is required for responses API (cannot use default 'openrouter/auto')"
      end

      parameters = { model: opts.model, input: input }
      parameters[:reasoning] = opts.reasoning if opts.reasoning
      parameters[:tools] = serialize_tools_for_responses(opts.tools) if opts.tools?
      parameters[:tool_choice] = opts.tool_choice if opts.tool_choice
      parameters[:max_output_tokens] = opts.max_completion_tokens || opts.max_tokens if opts.max_completion_tokens || opts.max_tokens
      parameters[:temperature] = opts.temperature if opts.temperature
      parameters[:top_p] = opts.top_p if opts.top_p
      parameters.merge!(opts.extras || {})

      raw = post(path: "/responses", parameters: parameters)
      ResponsesResponse.new(raw)
    end

    # Create a new ModelSelector for intelligent model selection
    def select_model
      ModelSelector.new
    end

    # Smart completion that automatically selects the best model based on requirements
    def smart_complete(messages, requirements: {}, optimization: :cost, **extras)
      selector = ModelSelector.new.optimize_for(optimization)

      selector = selector.require(*requirements[:capabilities]) if requirements[:capabilities]

      if requirements[:max_cost] || requirements[:max_input_cost]
        cost_opts = {}
        cost_opts[:max_cost] = requirements[:max_cost] || requirements[:max_input_cost]
        cost_opts[:max_output_cost] = requirements[:max_output_cost] if requirements[:max_output_cost]
        selector = selector.within_budget(**cost_opts)
      end

      selector = selector.min_context(requirements[:min_context_length]) if requirements[:min_context_length]

      if requirements[:providers]
        case requirements[:providers]
        when Hash
          selector = selector.prefer_providers(*requirements[:providers][:prefer]) if requirements[:providers][:prefer]
          selector = selector.require_providers(*requirements[:providers][:require]) if requirements[:providers][:require]
          selector = selector.avoid_providers(*requirements[:providers][:avoid]) if requirements[:providers][:avoid]
        when Array
          selector = selector.prefer_providers(*requirements[:providers])
        end
      end

      model = selector.choose
      raise ModelSelectionError, "No model found matching requirements: #{requirements}" unless model

      complete(messages, model:, **extras)
    end

    # Smart completion with automatic fallback to alternative models
    def smart_complete_with_fallback(messages, requirements: {}, optimization: :cost, max_retries: 3, **extras)
      selector = ModelSelector.new.optimize_for(optimization)

      selector = selector.require(*requirements[:capabilities]) if requirements[:capabilities]

      if requirements[:max_cost] || requirements[:max_input_cost]
        cost_opts = {}
        cost_opts[:max_cost] = requirements[:max_cost] || requirements[:max_input_cost]
        cost_opts[:max_output_cost] = requirements[:max_output_cost] if requirements[:max_output_cost]
        selector = selector.within_budget(**cost_opts)
      end

      selector = selector.min_context(requirements[:min_context_length]) if requirements[:min_context_length]

      if requirements[:providers]
        case requirements[:providers]
        when Hash
          selector = selector.prefer_providers(*requirements[:providers][:prefer]) if requirements[:providers][:prefer]
          selector = selector.require_providers(*requirements[:providers][:require]) if requirements[:providers][:require]
          selector = selector.avoid_providers(*requirements[:providers][:avoid]) if requirements[:providers][:avoid]
        when Array
          selector = selector.prefer_providers(*requirements[:providers])
        end
      end

      fallback_models = selector.choose_with_fallbacks(limit: max_retries + 1)
      raise ModelSelectionError, "No models found matching requirements: #{requirements}" if fallback_models.empty?

      last_error = nil

      fallback_models.each do |model|
        return complete(messages, model:, **extras)
      rescue StandardError => e
        last_error = e
      end

      raise ModelSelectionError, "All fallback models failed. Last error: #{last_error&.message}"
    end

    private

    def normalize_options(options, kwargs)
      case options
      when CompletionOptions
        kwargs.empty? ? options : options.merge(**kwargs)
      when Hash
        symbolized = options.transform_keys(&:to_sym)
        CompletionOptions.new(**symbolized.merge(kwargs))
      when nil
        CompletionOptions.new(**kwargs)
      else
        raise ArgumentError, "options must be CompletionOptions, Hash, or nil"
      end
    end
  end
end
