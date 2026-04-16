# frozen_string_literal: true

module OpenRouter
  # Mixin providing HTTP execution, error handling, and capability validation for Client.
  module RequestHandler
    private

    def execute_request(parameters)
      post(path: "/chat/completions", parameters: parameters)
    rescue ConfigurationError => e
      trigger_callbacks(:on_error, e)
      raise ServerError, e.message
    rescue Faraday::Error => e
      trigger_callbacks(:on_error, e)
      handle_faraday_error(e)
    end

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

    def extract_error_from_json_string(json_string)
      parsed_body = JSON.parse(json_string)
      parsed_body.dig("error", "message")
    rescue JSON::ParserError
      nil
    end

    def validate_response!(raw_response, stream)
      raise ServerError, raw_response.dig("error", "message") if raw_response.presence&.dig("error", "message").present?

      return unless stream.blank? && raw_response.blank?

      raise ServerError, "Empty response from OpenRouter. Might be worth retrying once or twice."
    end

    def build_response(raw_response, response_format, forced_extraction)
      response = Response.new(raw_response, response_format: response_format, forced_extraction: forced_extraction)
      response.client = self
      response
    end

    def validate_vision_support(model, messages)
      warn_if_unsupported(model, :vision, "vision/image processing") if messages_contain_images?(messages)
    end

    def warn_if_unsupported(model, capability, feature_name)
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
  end
end
