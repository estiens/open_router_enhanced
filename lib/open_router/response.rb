# frozen_string_literal: true

require "json"
require "active_support/core_ext/hash/indifferent_access"

module OpenRouter
  class StructuredOutputError < Error; end

  class Response
    attr_reader :raw_response, :response_format, :forced_extraction
    attr_accessor :client

    def initialize(raw_response, response_format: nil, forced_extraction: false)
      @raw_response = raw_response.is_a?(Hash) ? raw_response.with_indifferent_access : {}
      @response_format = response_format
      @forced_extraction = forced_extraction
      @client = nil
    end

    # Delegate common hash methods to raw_response for backward compatibility
    def [](key)
      @raw_response[key]
    end

    def dig(*keys)
      @raw_response.dig(*keys)
    end

    def fetch(key, default = nil)
      @raw_response.fetch(key, default)
    end

    def key?(key)
      @raw_response.key?(key)
    end

    def keys
      @raw_response.keys
    end

    def has_key?(key)
      @raw_response.key?(key)
    end

    def to_h
      @raw_response.to_h
    end

    def to_json(*args)
      @raw_response.to_json(*args)
    end

    # Tool calling methods
    def tool_calls
      @tool_calls ||= parse_tool_calls
    end

    def has_tool_calls?
      !tool_calls.empty?
    end

    # Convert response to message format for conversation continuation
    def to_message
      if has_tool_calls?
        {
          role: "assistant",
          content: content,
          tool_calls: raw_tool_calls
        }
      else
        {
          role: "assistant",
          content: content
        }
      end
    end

    # Structured output methods
    def structured_output(mode: nil, auto_heal: nil)
      # Use global default mode if not specified
      if mode.nil?
        mode = if @client&.configuration.respond_to?(:default_structured_output_mode)
                 @client.configuration.default_structured_output_mode || :strict
               else
                 :strict
               end
      end
      # Validate mode parameter
      raise ArgumentError, "Invalid mode: #{mode}. Must be :strict or :gentle." unless %i[strict gentle].include?(mode)

      return nil unless structured_output_expected? && has_content?

      case mode
      when :strict
        # The existing logic for strict parsing and healing
        should_heal = if auto_heal.nil?
                        @client&.configuration&.auto_heal_responses
                      else
                        auto_heal
                      end

        result = parse_and_heal_structured_output(auto_heal: should_heal)

        # Only validate after parsing if healing is disabled (healing handles its own validation)
        if result && !should_heal
          schema_obj = extract_schema_from_response_format
          if schema_obj && !schema_obj.validate(result)
            validation_errors = schema_obj.validation_errors(result)
            raise StructuredOutputError, "Schema validation failed: #{validation_errors.join(", ")}"
          end
        end

        @structured_output ||= result
      when :gentle
        # New gentle mode: best-effort parsing, no healing, no validation
        content_to_parse = @forced_extraction ? extract_json_from_text(content) : content
        return nil if content_to_parse.nil?

        begin
          JSON.parse(content_to_parse)
        rescue JSON::ParserError
          nil # Return nil on failure instead of raising an error
        end
      end
    end

    def valid_structured_output?
      return true unless structured_output_expected?

      schema_obj = extract_schema_from_response_format
      return true unless schema_obj

      begin
        parsed_output = structured_output
        return false unless parsed_output

        schema_obj.validate(parsed_output)
      rescue StructuredOutputError
        false
      end
    end

    def validation_errors
      return [] unless structured_output_expected?

      schema_obj = extract_schema_from_response_format
      return [] unless schema_obj

      begin
        parsed_output = structured_output
        return [] unless parsed_output

        schema_obj.validation_errors(parsed_output)
      rescue StructuredOutputError
        ["Failed to parse structured output"]
      end
    end

    # Content accessors
    def content
      choices.first&.dig("message", "content")
    end

    def choices
      @raw_response["choices"] || []
    end

    def usage
      @raw_response["usage"]
    end

    def id
      @raw_response["id"]
    end

    def model
      @raw_response["model"]
    end

    def created
      @raw_response["created"]
    end

    def object
      @raw_response["object"]
    end

    # Provider information
    def provider
      @raw_response["provider"]
    end

    # System fingerprint (model version identifier)
    def system_fingerprint
      @raw_response["system_fingerprint"]
    end

    # Native finish reason from the provider
    def native_finish_reason
      choices.first&.dig("native_finish_reason")
    end

    # Finish reason (standard OpenRouter format)
    def finish_reason
      choices.first&.dig("finish_reason")
    end

    # Cached tokens (tokens served from cache)
    def cached_tokens
      usage&.dig("prompt_tokens_details", "cached_tokens") || 0
    end

    # Total prompt tokens
    def prompt_tokens
      usage&.dig("prompt_tokens") || 0
    end

    # Total completion tokens
    def completion_tokens
      usage&.dig("completion_tokens") || 0
    end

    # Total tokens (prompt + completion)
    def total_tokens
      usage&.dig("total_tokens") || 0
    end

    # Get estimated cost for this response
    # Note: This requires an additional API call to /generation endpoint
    def cost_estimate
      return nil unless id && client

      @cost_estimate ||= client.query_generation_stats(id)&.dig("cost")
    rescue StandardError
      nil
    end

    # Convenience method to check if response has content
    def has_content?
      !content.nil? && !content.empty?
    end

    # Convenience method to check if response indicates an error
    def error?
      @raw_response.key?("error")
    end

    def error_message
      @raw_response.dig("error", "message")
    end

    private

    def parse_tool_calls
      tool_calls_data = choices.first&.dig("message", "tool_calls")
      return [] unless tool_calls_data.is_a?(Array)

      tool_calls_data.map { |tc| ToolCall.new(tc) }
    rescue StandardError => e
      raise ToolCallError, "Failed to parse tool calls: #{e.message}"
    end

    def raw_tool_calls
      choices.first&.dig("message", "tool_calls") || []
    end

    def parse_and_heal_structured_output(auto_heal: false)
      return nil unless structured_output_expected?
      return nil unless has_content?

      content_to_parse = @forced_extraction ? extract_json_from_text(content) : content

      if auto_heal && @client
        # For forced extraction: always send full content to provide context for healing
        # For normal responses: send the content as-is
        healing_content = if @forced_extraction
                            content # Always send full response for better healing context
                          else
                            content_to_parse || content
                          end
        heal_structured_response(healing_content, extract_schema_from_response_format)
      else
        return nil if content_to_parse.nil? # No JSON found in forced extraction

        begin
          JSON.parse(content_to_parse)
        rescue JSON::ParserError => e
          # For forced extraction, be more lenient and return nil on parse failures
          # For regular structured outputs, return nil if content looks like it contains markdown
          # (indicates it's not actually structured JSON output)
          if @forced_extraction
            nil
          elsif content_to_parse&.include?("```")
            # Content contains markdown blocks - this is not structured output
            nil
          else
            raise StructuredOutputError, "Failed to parse structured output: #{e.message}"
          end
        end
      end
    end

    # Extract JSON from text content (for forced structured output)
    def extract_json_from_text(text)
      return nil if text.nil? || text.empty?

      # First try to find JSON in code blocks
      if text.include?("```")
        # Look for ```json or ``` blocks
        json_match = text.match(/```(?:json)?\s*\n?(.*?)\n?```/m)
        if json_match
          candidate = json_match[1].strip
          return candidate unless candidate.empty?
        end
      end

      # Try to parse the entire text as JSON
      begin
        JSON.parse(text)
        return text
      rescue JSON::ParserError
        # Look for JSON-like content (starts with { or [)
        json_match = text.match(/(\{.*\}|\[.*\])/m)
        return json_match[1] if json_match
      end

      # No JSON found
      nil
    end

    def structured_output_expected?
      return false unless @response_format

      if @response_format.is_a?(Schema)
        true
      elsif @response_format.is_a?(Hash) && @response_format[:type] == "json_schema"
        true
      else
        false
      end
    end

    def extract_schema_from_response_format
      case @response_format
      when Schema
        @response_format
      when Hash
        schema_def = @response_format[:json_schema]
        if schema_def.is_a?(Schema)
          schema_def
        elsif schema_def.is_a?(Hash) && schema_def[:schema]
          # Create a temporary schema object for validation
          Schema.new(
            schema_def[:name] || "response",
            schema_def[:schema],
            strict: schema_def.key?(:strict) ? schema_def[:strict] : true
          )
        end
      end
    end

    # Backward compatibility method that delegates to JsonHealer
    def heal_structured_response(content, schema)
      return JSON.parse(content) unless schema

      healer = JsonHealer.new(@client)
      context = @forced_extraction ? :forced_extraction : :generic
      healer.heal(content, schema, context: context)
    end
  end
end
