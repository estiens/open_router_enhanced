# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/hash/indifferent_access"

require_relative "http"
require "pry"

module OpenRouter
  class ServerError < StandardError; end

  class Client
    include OpenRouter::HTTP

    attr_reader :callbacks, :usage_tracker

    # Initializes the client with optional configurations.
    def initialize(access_token: nil, request_timeout: nil, uri_base: nil, extra_headers: {}, track_usage: true)
      OpenRouter.configuration.access_token = access_token if access_token
      OpenRouter.configuration.request_timeout = request_timeout if request_timeout
      OpenRouter.configuration.uri_base = uri_base if uri_base
      OpenRouter.configuration.extra_headers = extra_headers if extra_headers.any?
      yield(OpenRouter.configuration) if block_given?

      # Instance-level tracking of capability warnings to avoid memory leaks
      @capability_warnings_shown = Set.new

      # Initialize callback system
      @callbacks = {
        before_request: [],
        after_response: [],
        on_tool_call: [],
        on_error: [],
        on_stream_chunk: [],
        on_healing: []
      }

      # Initialize usage tracking
      @track_usage = track_usage
      @usage_tracker = UsageTracker.new if @track_usage
    end

    def configuration
      OpenRouter.configuration
    end

    # Register a callback for a specific event
    #
    # @param event [Symbol] The event to register for (:before_request, :after_response, :on_tool_call, :on_error, :on_stream_chunk, :on_healing)
    # @param block [Proc] The callback to execute
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.on(:after_response) do |response|
    #     puts "Used #{response.total_tokens} tokens"
    #   end
    def on(event, &block)
      unless @callbacks.key?(event)
        raise ArgumentError, "Invalid event: #{event}. Valid events are: #{@callbacks.keys.join(", ")}"
      end

      @callbacks[event] << block
      self
    end

    # Remove all callbacks for a specific event
    #
    # @param event [Symbol] The event to clear callbacks for
    # @return [self] Returns self for method chaining
    def clear_callbacks(event = nil)
      if event
        @callbacks[event] = [] if @callbacks.key?(event)
      else
        @callbacks.each_key { |key| @callbacks[key] = [] }
      end
      self
    end

    # Trigger callbacks for a specific event
    #
    # @param event [Symbol] The event to trigger
    # @param data [Object] Data to pass to the callbacks
    def trigger_callbacks(event, data = nil)
      return unless @callbacks[event]

      @callbacks[event].each do |callback|
        callback.call(data)
      rescue StandardError => e
        warn "[OpenRouter] Callback error for #{event}: #{e.message}"
      end
    end

    # Performs a chat completion request to the OpenRouter API.
    # @param messages [Array<Hash>] Array of message hashes with role and content, like [{role: "user", content: "What is the meaning of life?"}]
    # @param model [String|Array] Model identifier, or array of model identifiers if you want to fallback to the next model in case of failure
    # @param providers [Array<String>] Optional array of provider identifiers, ordered by priority
    # @param transforms [Array<String>] Optional array of strings that tell OpenRouter to apply a series of transformations to the prompt before sending it to the model. Transformations are applied in-order
    # @param plugins [Array<Hash>] Optional array of plugin hashes like [{id: "response-healing"}]. Available plugins: response-healing, web-search, pdf-inputs
    # @param tools [Array<Tool>] Optional array of Tool objects or tool definition hashes for function calling
    # @param tool_choice [String|Hash] Optional tool choice: "auto", "none", "required", or specific tool selection
    # @param response_format [Hash] Optional response format for structured outputs
    # @param prediction [Hash] Optional predicted output for latency reduction, e.g. {type: "content", content: "predicted text"}
    # @param extras [Hash] Optional hash of model-specific parameters to send to the OpenRouter API
    # @param stream [Proc, nil] Optional callable object for streaming
    # @return [Response] The completion response wrapped in a Response object.
    def complete(messages, model: "openrouter/auto", providers: [], transforms: [], plugins: [], tools: [], tool_choice: nil,
                 response_format: nil, force_structured_output: nil, prediction: nil, extras: {}, stream: nil)
      parameters = prepare_base_parameters(messages, model, providers, transforms, plugins, prediction, stream, extras)
      forced_extraction = configure_tools_and_structured_outputs!(parameters, model, tools, tool_choice,
                                                                  response_format, force_structured_output)
      configure_plugins!(parameters, response_format, stream)
      validate_vision_support(model, messages)

      # Trigger before_request callbacks
      trigger_callbacks(:before_request, parameters)

      raw_response = execute_request(parameters)
      validate_response!(raw_response, stream)

      response = build_response(raw_response, response_format, forced_extraction)

      # Track usage if enabled
      @usage_tracker&.track(response, model: model.is_a?(String) ? model : model.first)

      # Trigger after_response callbacks
      trigger_callbacks(:after_response, response)

      # Trigger on_tool_call callbacks if tool calls are present
      trigger_callbacks(:on_tool_call, response.tool_calls) if response.has_tool_calls?

      response
    end

    # Fetches the list of available models from the OpenRouter API.
    # @return [Array<Hash>] The list of models.
    def models
      get(path: "/models")["data"]
    end

    # Queries the generation stats for a given id.
    # @param generation_id [String] The generation id returned from a previous request.
    # @return [Hash] The stats including token counts and cost.
    def query_generation_stats(generation_id)
      response = get(path: "/generation?id=#{generation_id}")
      response["data"]
    end

    # Performs a request to the Responses API Beta (/api/v1/responses)
    # This is an OpenAI-compatible stateless API with support for reasoning.
    #
    # @param input [String, Array] The input text or structured message array
    # @param model [String] Model identifier (e.g., "openai/o4-mini")
    # @param reasoning [Hash, nil] Optional reasoning config, e.g. {effort: "high"}
    #   Effort levels: "minimal", "low", "medium", "high"
    # @param tools [Array<Tool, Hash>] Optional array of tool definitions
    # @param tool_choice [String, Hash, nil] Optional: "auto", "none", "required", or specific tool
    # @param max_output_tokens [Integer, nil] Maximum tokens to generate
    # @param temperature [Float, nil] Sampling temperature (0-2)
    # @param top_p [Float, nil] Nucleus sampling parameter (0-1)
    # @param extras [Hash] Additional parameters to pass to the API
    # @return [ResponsesResponse] The response wrapped in a ResponsesResponse object
    #
    # @example Basic usage
    #   response = client.responses("What is 2+2?", model: "openai/o4-mini")
    #   puts response.content
    #
    # @example With reasoning
    #   response = client.responses(
    #     "Solve this step by step: What is 15% of 80?",
    #     model: "openai/o4-mini",
    #     reasoning: { effort: "high" }
    #   )
    #   puts response.reasoning_summary
    #   puts response.content
    def responses(input, model:, reasoning: nil, tools: [], tool_choice: nil,
                  max_output_tokens: nil, temperature: nil, top_p: nil, extras: {})
      parameters = { model: model, input: input }
      parameters[:reasoning] = reasoning if reasoning
      parameters[:tools] = serialize_tools_for_responses(tools) if tools.any?
      parameters[:tool_choice] = tool_choice if tool_choice
      parameters[:max_output_tokens] = max_output_tokens if max_output_tokens
      parameters[:temperature] = temperature if temperature
      parameters[:top_p] = top_p if top_p
      parameters.merge!(extras)

      raw = post(path: "/responses", parameters: parameters)
      ResponsesResponse.new(raw)
    end

    # Create a new ModelSelector for intelligent model selection
    #
    # @return [ModelSelector] A new ModelSelector instance
    # @example
    #   client = OpenRouter::Client.new
    #   model = client.select_model.optimize_for(:cost).require(:function_calling).choose
    def select_model
      ModelSelector.new
    end

    # Smart completion that automatically selects the best model based on requirements
    #
    # @param messages [Array<Hash>] Array of message hashes
    # @param requirements [Hash] Model selection requirements
    # @param optimization [Symbol] Optimization strategy (:cost, :performance, :latest, :context)
    # @param extras [Hash] Additional parameters for the completion request
    # @return [Response] The completion response
    # @raise [ModelSelectionError] If no suitable model is found
    #
    # @example
    #   response = client.smart_complete(
    #     messages: [{ role: "user", content: "Analyze this data" }],
    #     requirements: { capabilities: [:function_calling], max_input_cost: 0.01 },
    #     optimization: :cost
    #   )
    def smart_complete(messages, requirements: {}, optimization: :cost, **extras)
      selector = ModelSelector.new.optimize_for(optimization)

      # Apply requirements using fluent interface
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
          if requirements[:providers][:require]
            selector = selector.require_providers(*requirements[:providers][:require])
          end
          selector = selector.avoid_providers(*requirements[:providers][:avoid]) if requirements[:providers][:avoid]
        when Array
          selector = selector.prefer_providers(*requirements[:providers])
        end
      end

      # Select the best model
      model = selector.choose
      raise ModelSelectionError, "No model found matching requirements: #{requirements}" unless model

      # Perform the completion with the selected model
      complete(messages, model:, **extras)
    end

    # Smart completion with automatic fallback to alternative models
    #
    # @param messages [Array<Hash>] Array of message hashes
    # @param requirements [Hash] Model selection requirements
    # @param optimization [Symbol] Optimization strategy
    # @param max_retries [Integer] Maximum number of fallback attempts
    # @param extras [Hash] Additional parameters for the completion request
    # @return [Response] The completion response
    # @raise [ModelSelectionError] If all fallback attempts fail
    #
    # @example
    #   response = client.smart_complete_with_fallback(
    #     messages: [{ role: "user", content: "Hello" }],
    #     requirements: { capabilities: [:function_calling] },
    #     max_retries: 3
    #   )
    def smart_complete_with_fallback(messages, requirements: {}, optimization: :cost, max_retries: 3, **extras)
      selector = ModelSelector.new.optimize_for(optimization)

      # Apply requirements (same logic as smart_complete)
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
          if requirements[:providers][:require]
            selector = selector.require_providers(*requirements[:providers][:require])
          end
          selector = selector.avoid_providers(*requirements[:providers][:avoid]) if requirements[:providers][:avoid]
        when Array
          selector = selector.prefer_providers(*requirements[:providers])
        end
      end

      # Get fallback models
      fallback_models = selector.choose_with_fallbacks(limit: max_retries + 1)
      raise ModelSelectionError, "No models found matching requirements: #{requirements}" if fallback_models.empty?

      last_error = nil

      fallback_models.each do |model|
        return complete(messages, model:, **extras)
      rescue StandardError => e
        last_error = e
        # Continue to next model in fallback list
      end

      # If we get here, all models failed
      raise ModelSelectionError, "All fallback models failed. Last error: #{last_error&.message}"
    end

    private

    # Prepare the base parameters for the API request
    def prepare_base_parameters(messages, model, providers, transforms, plugins, prediction, stream, extras)
      parameters = { messages: messages.dup }

      configure_model_parameter!(parameters, model)
      configure_provider_parameter!(parameters, providers)
      configure_transforms_parameter!(parameters, transforms)
      configure_plugins_parameter!(parameters, plugins)
      configure_prediction_parameter!(parameters, prediction)
      configure_stream_parameter!(parameters, stream)

      parameters.merge!(extras)
      parameters
    end

    # Configure the model parameter (single model or fallback array)
    def configure_model_parameter!(parameters, model)
      if model.is_a?(String)
        parameters[:model] = model
      elsif model.is_a?(Array)
        parameters[:models] = model
        parameters[:route] = "fallback"
      end
    end

    # Configure the provider parameter if providers are specified
    def configure_provider_parameter!(parameters, providers)
      parameters[:provider] = { order: providers } if providers.any?
    end

    # Configure the transforms parameter if transforms are specified
    def configure_transforms_parameter!(parameters, transforms)
      parameters[:transforms] = transforms if transforms.any?
    end

    # Configure the plugins parameter if plugins are specified
    def configure_plugins_parameter!(parameters, plugins)
      parameters[:plugins] = plugins.dup if plugins.any?
    end

    # Configure the prediction parameter for latency optimization
    def configure_prediction_parameter!(parameters, prediction)
      parameters[:prediction] = prediction if prediction
    end

    # Configure the stream parameter if streaming is enabled
    def configure_stream_parameter!(parameters, stream)
      parameters[:stream] = stream if stream
    end

    # Auto-add response-healing plugin when using structured outputs (non-streaming only)
    # This leverages OpenRouter's native JSON healing for better reliability
    def configure_plugins!(parameters, response_format, stream)
      return unless should_auto_add_healing?(response_format, stream)

      parameters[:plugins] ||= []

      # Don't duplicate if user already specified response-healing
      return if parameters[:plugins].any? { |p| p[:id] == "response-healing" || p["id"] == "response-healing" }

      parameters[:plugins] << { id: "response-healing" }
    end

    # Determine if we should auto-add the response-healing plugin
    def should_auto_add_healing?(response_format, stream)
      return false unless configuration.auto_native_healing
      return false if stream # Response healing doesn't work with streaming
      return false unless response_format

      # Check if response_format is a structured output type
      case response_format
      when OpenRouter::Schema
        true
      when Hash
        type = response_format[:type] || response_format["type"]
        %w[json_schema json_object].include?(type.to_s)
      else
        false
      end
    end

    # Configure tools and structured outputs, returning forced_extraction flag
    def configure_tools_and_structured_outputs!(parameters, model, tools, tool_choice, response_format,
                                                force_structured_output)
      configure_tool_calling!(parameters, model, tools, tool_choice)
      configure_structured_outputs!(parameters, model, response_format, force_structured_output)
    end

    # Configure tool calling support
    def configure_tool_calling!(parameters, model, tools, tool_choice)
      return unless tools.any?

      warn_if_unsupported(model, :function_calling, "tool calling")
      parameters[:tools] = serialize_tools(tools)
      parameters[:tool_choice] = tool_choice if tool_choice
    end

    # Configure structured output support and return forced_extraction flag
    def configure_structured_outputs!(parameters, model, response_format, force_structured_output)
      return false unless response_format

      force_structured_output = determine_forced_extraction_mode(model, force_structured_output)

      if force_structured_output
        handle_forced_structured_output!(parameters, model, response_format)
        true
      else
        handle_native_structured_output!(parameters, model, response_format)
        false
      end
    end

    # Determine whether to use forced extraction mode
    def determine_forced_extraction_mode(model, force_structured_output)
      return force_structured_output unless force_structured_output.nil?

      if model.is_a?(String) &&
         model != "openrouter/auto" &&
         !ModelRegistry.has_capability?(model, :structured_outputs) &&
         configuration.auto_force_on_unsupported_models
        warn "[OpenRouter] Model '#{model}' doesn't support native structured outputs. Automatically using forced extraction mode."
        true
      else
        false
      end
    end

    # Handle forced structured output mode
    def handle_forced_structured_output!(parameters, model, response_format)
      # In strict mode, still validate to ensure user is aware of capability limits
      warn_if_unsupported(model, :structured_outputs, "structured outputs") if configuration.strict_mode
      inject_schema_instructions!(parameters[:messages], response_format)
    end

    # Handle native structured output mode
    def handle_native_structured_output!(parameters, model, response_format)
      warn_if_unsupported(model, :structured_outputs, "structured outputs")
      parameters[:response_format] = serialize_response_format(response_format)
    end

    # Validate vision support if messages contain images
    def validate_vision_support(model, messages)
      warn_if_unsupported(model, :vision, "vision/image processing") if messages_contain_images?(messages)
    end

    # Execute the HTTP request with comprehensive error handling
    def execute_request(parameters)
      post(path: "/chat/completions", parameters: parameters)
    rescue ConfigurationError => e
      trigger_callbacks(:on_error, e)
      raise ServerError, e.message
    rescue Faraday::Error => e
      trigger_callbacks(:on_error, e)
      handle_faraday_error(e)
    end

    # Handle Faraday errors with specific error message extraction
    def handle_faraday_error(error)
      case error
      when Faraday::UnauthorizedError
        raise error
      when Faraday::BadRequestError
        error_message = extract_error_message(error)
        raise ServerError, "Bad Request: #{error_message}"
      when Faraday::ServerError
        raise ServerError, "Server Error: #{error.message}"
      else
        raise ServerError, "Network Error: #{error.message}"
      end
    end

    # Extract error message from Faraday error response
    def extract_error_message(error)
      return error.message unless error.response&.dig(:body)

      body = error.response[:body]

      if body.is_a?(Hash)
        body.dig("error", "message") || error.message
      elsif body.is_a?(String)
        extract_error_from_json_string(body) || error.message
      else
        error.message
      end
    end

    # Extract error message from JSON string response
    def extract_error_from_json_string(json_string)
      parsed_body = JSON.parse(json_string)
      parsed_body.dig("error", "message")
    rescue JSON::ParserError
      nil
    end

    # Validate the API response for errors
    def validate_response!(raw_response, stream)
      raise ServerError, raw_response.dig("error", "message") if raw_response.presence&.dig("error", "message").present?

      return unless stream.blank? && raw_response.blank?

      raise ServerError, "Empty response from OpenRouter. Might be worth retrying once or twice."
    end

    # Build and configure the Response object
    def build_response(raw_response, response_format, forced_extraction)
      response = Response.new(raw_response, response_format: response_format, forced_extraction: forced_extraction)
      response.client = self
      response
    end

    # Warn if a model is being used with an unsupported capability
    def warn_if_unsupported(model, capability, feature_name)
      # Skip warnings for array models (fallbacks) or auto-selection
      return if model.is_a?(Array) || model == "openrouter/auto"

      return if ModelRegistry.has_capability?(model, capability)

      if configuration.strict_mode
        raise CapabilityError,
              "Model '#{model}' does not support #{feature_name} (missing :#{capability} capability). Enable non-strict mode to allow this request."
      end

      warning_key = "#{model}:#{capability}"
      return if @capability_warnings_shown.include?(warning_key)

      warn "[OpenRouter Warning] Model '#{model}' may not support #{feature_name} (missing :#{capability} capability). The request will still be attempted."
      @capability_warnings_shown << warning_key
    end

    # Check if messages contain image content
    def messages_contain_images?(messages)
      messages.any? do |msg|
        content = msg[:content] || msg["content"]
        if content.is_a?(Array)
          content.any? { |part| part.is_a?(Hash) && (part[:type] == "image_url" || part["type"] == "image_url") }
        else
          false
        end
      end
    end

    # Serialize tools to the format expected by OpenRouter Chat Completions API
    # Format: { type: "function", function: { name: ..., parameters: ... } }
    def serialize_tools(tools)
      tools.map do |tool|
        case tool
        when Tool
          tool.to_h
        when Hash
          tool
        else
          raise ArgumentError, "Tools must be Tool objects or hashes"
        end
      end
    end

    # Serialize tools to the flat format expected by Responses API
    # Format: { type: "function", name: ..., parameters: ... }
    def serialize_tools_for_responses(tools)
      tools.map do |tool|
        tool_hash = case tool
                    when Tool
                      tool.to_h
                    when Hash
                      tool.transform_keys(&:to_sym)
                    else
                      raise ArgumentError, "Tools must be Tool objects or hashes"
                    end

        # Flatten the nested function structure if present
        if tool_hash[:function]
          {
            type: "function",
            name: tool_hash[:function][:name],
            description: tool_hash[:function][:description],
            parameters: tool_hash[:function][:parameters]
          }.compact
        else
          # Already in flat format
          tool_hash
        end
      end
    end

    # Serialize response format to the format expected by OpenRouter API
    def serialize_response_format(response_format)
      case response_format
      when Hash
        if response_format[:json_schema].is_a?(Schema)
          response_format.merge(json_schema: response_format[:json_schema].to_h)
        else
          response_format
        end
      when Schema
        {
          type: "json_schema",
          json_schema: response_format.to_h
        }
      else
        response_format
      end
    end

    # Inject schema instructions into messages for forced structured output
    def inject_schema_instructions!(messages, response_format)
      schema = extract_schema(response_format)
      return unless schema

      instruction_content = if schema.respond_to?(:get_format_instructions)
                              schema.get_format_instructions
                            else
                              build_schema_instruction(schema)
                            end

      # Add as system message
      messages << { role: "system", content: instruction_content }
    end

    # Extract schema from response_format
    def extract_schema(response_format)
      case response_format
      when Schema
        response_format
      when Hash
        # Handle both Schema objects and raw hash schemas
        if response_format[:json_schema].is_a?(Schema)
          response_format[:json_schema]
        elsif response_format[:json_schema].is_a?(Hash)
          response_format[:json_schema]
        else
          response_format
        end
      end
    end

    # Build schema instruction when schema doesn't have get_format_instructions
    def build_schema_instruction(schema)
      schema_json = schema.respond_to?(:to_h) ? schema.to_h.to_json : schema.to_json

      <<~INSTRUCTION
        You must respond with valid JSON matching this exact schema:

        ```json
        #{schema_json}
        ```

        Rules:
        - Return ONLY the JSON object, no other text
        - Ensure all required fields are present
        - Match the exact data types specified
        - Follow any format constraints (email, date, etc.)
        - Do not include trailing commas or comments
      INSTRUCTION
    end
  end
end
