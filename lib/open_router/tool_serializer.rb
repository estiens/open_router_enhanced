# frozen_string_literal: true

module OpenRouter
  # Mixin providing tool calling and structured output configuration for Client.
  # rubocop:disable Metrics/ModuleLength
  module ToolSerializer
    private

    # Configure tools and structured outputs, returning forced_extraction flag
    def configure_tools_and_structured_outputs!(parameters, opts)
      configure_tool_calling!(parameters, opts)
      configure_structured_outputs!(parameters, opts)
    end

    def configure_tool_calling!(parameters, opts)
      return unless opts.tools?

      warn_if_unsupported(opts.model, :function_calling, "tool calling")
      parameters[:tools] = serialize_tools(opts.tools)
      parameters[:tool_choice] = opts.tool_choice if opts.tool_choice
    end

    # Returns forced_extraction boolean
    def configure_structured_outputs!(parameters, opts)
      return false unless opts.response_format?

      force_extraction = determine_forced_extraction_mode(opts.model, opts.force_structured_output)

      if force_extraction
        handle_forced_structured_output!(parameters, opts.model, opts.response_format)
        true
      else
        handle_native_structured_output!(parameters, opts.model, opts.response_format)
        false
      end
    end

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

    def handle_forced_structured_output!(parameters, model, response_format)
      warn_if_unsupported(model, :structured_outputs, "structured outputs") if configuration.strict_mode
      inject_schema_instructions!(parameters[:messages], response_format)
    end

    def handle_native_structured_output!(parameters, model, response_format)
      warn_if_unsupported(model, :structured_outputs, "structured outputs")
      parameters[:response_format] = serialize_response_format(response_format)
    end

    # Serialize tools to Chat Completions API format: { type: "function", function: { name:, parameters: } }
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

    # Serialize tools to Responses API flat format: { type: "function", name:, parameters: }
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

        if tool_hash[:function]
          {
            type: "function",
            name: tool_hash[:function][:name],
            description: tool_hash[:function][:description],
            parameters: tool_hash[:function][:parameters]
          }.compact
        else
          tool_hash
        end
      end
    end

    def serialize_response_format(response_format)
      case response_format
      when Hash
        if response_format[:json_schema].is_a?(Schema)
          response_format.merge(json_schema: response_format[:json_schema].to_h)
        else
          response_format
        end
      when Schema
        { type: "json_schema", json_schema: response_format.to_h }
      else
        response_format
      end
    end

    def inject_schema_instructions!(messages, response_format)
      schema = extract_schema(response_format)
      return unless schema

      instruction_content = if schema.respond_to?(:get_format_instructions)
                              schema.get_format_instructions
                            else
                              build_schema_instruction(schema)
                            end

      messages << { role: "system", content: instruction_content }
    end

    def extract_schema(response_format)
      case response_format
      when Schema
        response_format
      when Hash
        if response_format[:json_schema].is_a?(Schema)
          response_format[:json_schema]
        elsif response_format[:json_schema].is_a?(Hash)
          response_format[:json_schema]
        else
          response_format
        end
      end
    end

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
  # rubocop:enable Metrics/ModuleLength
end
