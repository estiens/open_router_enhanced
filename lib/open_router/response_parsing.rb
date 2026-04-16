# frozen_string_literal: true

module OpenRouter
  # Private parsing helpers for Response — structured output extraction and tool call parsing.
  module ResponseParsing
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
        healing_content = @forced_extraction ? content : (content_to_parse || content)
        heal_structured_response(healing_content, extract_schema_from_response_format)
      else
        return nil if content_to_parse.nil?

        begin
          JSON.parse(content_to_parse)
        rescue JSON::ParserError => e
          if @forced_extraction
            nil
          elsif content_to_parse&.include?("```")
            nil
          else
            raise StructuredOutputError, "Failed to parse structured output: #{e.message}"
          end
        end
      end
    end

    def extract_json_from_text(text)
      return nil if text.nil? || text.empty?

      if text.include?("```")
        json_match = text.match(/```(?:json)?\s*\n?(.*?)\n?```/m)
        if json_match
          candidate = json_match[1].strip
          return candidate unless candidate.empty?
        end
      end

      begin
        JSON.parse(text)
        return text
      rescue JSON::ParserError
        json_match = text.match(/(\{.*\}|\[.*\])/m)
        return json_match[1] if json_match
      end

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
          Schema.new(
            schema_def[:name] || "response",
            schema_def[:schema],
            strict: schema_def.key?(:strict) ? schema_def[:strict] : true
          )
        end
      end
    end

    def heal_structured_response(content, schema)
      return JSON.parse(content) unless schema

      healer = JsonHealer.new(@client)
      context = @forced_extraction ? :forced_extraction : :generic
      healer.heal(content, schema, context: context)
    end
  end
end
