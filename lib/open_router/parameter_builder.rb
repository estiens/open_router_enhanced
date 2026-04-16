# frozen_string_literal: true

module OpenRouter
  # Mixin providing request parameter construction for Client.
  module ParameterBuilder
    private

    # Prepare the base parameters for the API request
    def prepare_base_parameters(messages, opts, stream)
      parameters = { messages: messages.dup }

      configure_model_parameter!(parameters, opts.model)
      configure_provider_parameter!(parameters, opts)
      configure_transforms_parameter!(parameters, opts.transforms)
      configure_plugins_parameter!(parameters, opts.plugins)
      configure_prediction_parameter!(parameters, opts.prediction)
      configure_stream_parameter!(parameters, stream)
      configure_sampling_parameters!(parameters, opts)
      configure_output_parameters!(parameters, opts)
      configure_routing_parameters!(parameters, opts)

      parameters.merge!(opts.extras || {})
      parameters
    end

    def configure_model_parameter!(parameters, model)
      if model.is_a?(String)
        parameters[:model] = model
      elsif model.is_a?(Array)
        parameters[:models] = model
        parameters[:route] = "fallback"
      end
    end

    def configure_provider_parameter!(parameters, opts)
      if opts.provider && !opts.provider.empty?
        parameters[:provider] = opts.provider
      elsif opts.providers.any?
        parameters[:provider] = { order: opts.providers }
      end

      parameters[:route] = opts.route if opts.route
    end

    def configure_sampling_parameters!(parameters, opts)
      parameters[:temperature] = opts.temperature if opts.temperature
      parameters[:top_p] = opts.top_p if opts.top_p
      parameters[:top_k] = opts.top_k if opts.top_k
      parameters[:frequency_penalty] = opts.frequency_penalty if opts.frequency_penalty
      parameters[:presence_penalty] = opts.presence_penalty if opts.presence_penalty
      parameters[:repetition_penalty] = opts.repetition_penalty if opts.repetition_penalty
      parameters[:min_p] = opts.min_p if opts.min_p
      parameters[:top_a] = opts.top_a if opts.top_a
      parameters[:seed] = opts.seed if opts.seed
    end

    def configure_output_parameters!(parameters, opts)
      if opts.max_completion_tokens
        parameters[:max_completion_tokens] = opts.max_completion_tokens
      elsif opts.max_tokens
        parameters[:max_tokens] = opts.max_tokens
      end

      parameters[:stop] = opts.stop if opts.stop
      parameters[:logprobs] = opts.logprobs unless opts.logprobs.nil?
      parameters[:top_logprobs] = opts.top_logprobs if opts.top_logprobs
      parameters[:logit_bias] = opts.logit_bias if opts.logit_bias && !opts.logit_bias.empty?
      parameters[:parallel_tool_calls] = opts.parallel_tool_calls unless opts.parallel_tool_calls.nil?
      parameters[:verbosity] = opts.verbosity if opts.verbosity
    end

    def configure_routing_parameters!(parameters, opts)
      parameters[:metadata] = opts.metadata if opts.metadata && !opts.metadata.empty?
      parameters[:user] = opts.user if opts.user
      parameters[:session_id] = opts.session_id if opts.session_id
    end

    def configure_transforms_parameter!(parameters, transforms)
      parameters[:transforms] = transforms if transforms.any?
    end

    def configure_plugins_parameter!(parameters, plugins)
      parameters[:plugins] = plugins.dup if plugins.any?
    end

    def configure_prediction_parameter!(parameters, prediction)
      parameters[:prediction] = prediction if prediction
    end

    def configure_stream_parameter!(parameters, stream)
      parameters[:stream] = stream if stream
    end

    # Auto-add response-healing plugin when using structured outputs (non-streaming only)
    def configure_plugins!(parameters, response_format, stream)
      return unless should_auto_add_healing?(response_format, stream)

      parameters[:plugins] ||= []
      return if parameters[:plugins].any? { |p| p[:id] == "response-healing" || p["id"] == "response-healing" }

      parameters[:plugins] << { id: "response-healing" }
    end

    def should_auto_add_healing?(response_format, stream)
      return false unless configuration.auto_native_healing
      return false if stream
      return false unless response_format

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
  end
end
