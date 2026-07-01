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

    # Configure the structured-output request.
    #
    # Default (native: false): ask the provider for a plain JSON object — the most
    # widely supported response_format across models/providers — and describe the
    # schema in the prompt. The model's capability registry never gates the request.
    #
    # Opt-in (native: true): send response_format: { type: "json_schema", ... } for
    # grammar-constrained decoding. Only some models/providers support this; it can
    # 400 on the rest, which is why it is explicit rather than auto-detected.
    #
    # Returns the lenient-extraction flag (true when the schema was injected into the
    # prompt, so the response may need JSON extracted from surrounding text).
    def configure_structured_outputs!(parameters, opts)
      return false unless opts.response_format?

      schema = extract_schema(opts.response_format)

      if opts.native && schema
        warn_if_unsupported(opts.model, :structured_outputs, "structured outputs")
        parameters[:response_format] = serialize_response_format(opts.response_format)
        return false
      end

      # Default json_object path.
      parameters[:response_format] = { type: "json_object" }
      return false unless schema

      inject_schema_instructions!(parameters[:messages], schema)
      true
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

    def inject_schema_instructions!(messages, schema)
      return unless schema

      instruction_content = if schema.respond_to?(:get_format_instructions)
                              schema.get_format_instructions
                            else
                              build_schema_instruction(schema)
                            end

      messages << { role: "system", content: instruction_content }
    end

    # Pull the schema out of a response_format. Returns nil for a plain
    # { type: "json_object" } directive (no schema to describe or validate).
    def extract_schema(response_format)
      case response_format
      when Schema
        response_format
      when Hash
        json_schema = response_format[:json_schema] || response_format["json_schema"]
        json_schema if json_schema.is_a?(Schema) || json_schema.is_a?(Hash)
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
