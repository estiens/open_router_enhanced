# frozen_string_literal: true

require "json"

module OpenRouter
  # A dedicated class for extracting, cleaning, and healing malformed JSON
  # responses from language models.
  class JsonHealer
    # Regex to find a JSON object or array within a markdown code block.
    # It handles optional "json" language identifier. Non-greedy `.*?` is key.
    CODE_BLOCK_JSON_REGEX = /```(?:json)?\s*\n?(.*?)\n?```/m

    # Regex to find JSON that isn't in a code block. Looks for the first
    # `{` or `[` and captures until the matching last `}` or `]`. This is
    # a heuristic and might not be perfect for all cases.
    LOOSE_JSON_REGEX = /(\{.*\}|\[.*\])/m

    def initialize(client)
      @client = client
      @configuration = client.configuration
    end

    # Enhanced heal method that supports different healing contexts
    def heal(raw_text, schema, context: :generic)
      candidate_json = extract_json_candidate(raw_text)
      raise StructuredOutputError, "No JSON-like content found in the response." if candidate_json.nil?

      attempts = 0
      max_attempts = @configuration.max_heal_attempts
      original_content = raw_text # Keep track of original for forced extraction context
      all_errors = [] # Track all errors encountered during healing

      loop do
        # Attempt to parse after simple cleanup
        parsed_json = JSON.parse(cleanup_syntax(candidate_json))

        # If parsing succeeds, validate against the schema
        if schema.validation_available? && !schema.validate(parsed_json)
          errors = schema.validation_errors(parsed_json)
          raise SchemaValidationError, "Schema validation failed: #{errors.join(", ")}"
        end

        return parsed_json # Success!
      rescue JSON::ParserError, SchemaValidationError => e
        attempts += 1
        all_errors << e.message

        if attempts > max_attempts
          final_error_message = build_final_error_message(e, schema, candidate_json, max_attempts)
          raise StructuredOutputError, final_error_message
        end

        # Escalate to LLM-based healing with proper context
        candidate_json = fix_with_healer_model(candidate_json, schema, e.message, e.class, original_content, context)
      end
    end

    private

    # Stage 1: Intelligently extract the JSON string from raw text.
    def extract_json_candidate(text)
      # 1. Prioritize markdown code blocks, as they are the most explicit.
      match = text.match(CODE_BLOCK_JSON_REGEX)
      return match[1].strip if match

      # 2. If no code block, look for the text after a "JSON:" label.
      # This handles "Here is the JSON: {...}"
      text_after_colon = text.split(/json:/i).last
      return text_after_colon.strip if text_after_colon && text_after_colon.length < text.length

      # 3. As a fallback, try to find the first balanced JSON-like structure.
      match = text.match(LOOSE_JSON_REGEX)
      return match[1].strip if match

      # 4. If nothing else works, check if the whole text looks like JSON before using it.
      trimmed = text.strip
      return trimmed if trimmed.start_with?("{", "[")

      # 5. No JSON-like content found
      nil
    end

    # Stage 2: Perform simple, deterministic syntax cleanup.
    def cleanup_syntax(json_string)
      # Remove trailing commas from objects and arrays, a very common LLM error.
      json_string
        .gsub(/,\s*(\}|\])/, '\1') # Remove trailing commas: ",}" -> "}" and ",]" -> "]"
    end

    # Stage 4: Use an LLM to fix the broken JSON.
    def fix_with_healer_model(broken_json, schema, error_reason, error_class, original_content, context)
      healer_model = @configuration.healer_model
      prompt = build_healing_prompt(broken_json, schema, error_reason, error_class, original_content, context)

      # Trigger on_healing callback with healing context
      if @client.respond_to?(:trigger_callbacks)
        @client.trigger_callbacks(:on_healing, {
                                    broken_json: broken_json,
                                    error: error_reason,
                                    schema: schema,
                                    healer_model: healer_model,
                                    context: context
                                  })
      end

      healing_response = @client.complete(
        [{ role: "user", content: prompt }],
        model: healer_model,
        extras: { temperature: 0.0, max_tokens: 4000 }
      )

      # The healer's response is now our new best candidate.
      # We extract it again in case the healer also added fluff.
      healed_json = extract_json_candidate(healing_response.content)

      # Trigger callback with healing result
      if @client.respond_to?(:trigger_callbacks)
        @client.trigger_callbacks(:on_healing, {
                                    healed: true,
                                    original: broken_json,
                                    result: healed_json
                                  })
      end

      healed_json
    rescue StandardError => e
      # If the healing call itself fails, we can't proceed.
      # Return the original broken content to let the loop fail naturally.
      warn "[OpenRouter Warning] JSON healing request failed: #{e.message}"

      # Trigger callback for failed healing
      if @client.respond_to?(:trigger_callbacks)
        @client.trigger_callbacks(:on_healing, {
                                    healed: false,
                                    error: e.message,
                                    original: broken_json
                                  })
      end

      broken_json
    end

    def build_healing_prompt(content, schema, error_reason, error_class, original_content, context)
      # Use schema.to_h instead of pure_schema for consistency with existing tests
      schema_json = schema.respond_to?(:to_h) ? schema.to_h.to_json : schema.to_json

      case error_class.name
      when "JSON::ParserError"
        build_json_parsing_prompt(content, error_reason)
      when "OpenRouter::SchemaValidationError"
        if forced_extraction_context?(context, original_content, content)
          build_forced_extraction_prompt(original_content, schema_json, error_reason)
        else
          build_schema_validation_prompt(content, schema_json, error_reason)
        end
      else
        build_generic_prompt(content, schema_json, error_reason)
      end
    end

    def build_json_parsing_prompt(content, error_reason)
      <<~PROMPT
        Invalid JSON: #{error_reason}

        Content to fix:
        #{content}

        Please fix this content to be valid JSON. Return ONLY the fixed JSON, no explanations or additional text.
      PROMPT
    end

    def build_schema_validation_prompt(content, schema_json, error_reason)
      <<~PROMPT
        The following JSON content is invalid because it failed to validate against the provided JSON Schema.

        Validation Errors:
        #{error_reason}

        Original Content to Fix:
        ```json
        #{content}
        ```

        Required JSON Schema:
        ```json
        #{schema_json}
        ```

        Please correct the content to produce a valid JSON object that strictly conforms to the schema.
        Return ONLY the fixed, raw JSON object, without any surrounding text or explanations.
      PROMPT
    end

    def build_forced_extraction_prompt(original_content, schema_json, error_reason)
      <<~PROMPT
        The following response contains explanatory text and JSON that needs to be extracted and fixed to conform to the provided schema.

        Validation Errors:
        #{error_reason}

        Original Response Content:
        #{original_content}

        Required JSON Schema:
        ```json
        #{schema_json}
        ```

        Please extract and correct the JSON from the response above to produce a valid JSON object that strictly conforms to the schema.
        Return ONLY the fixed, raw JSON object, without any surrounding text or explanations.
      PROMPT
    end

    def build_generic_prompt(content, schema_json, error_reason)
      <<~PROMPT
        You are an expert JSON fixing bot. Your task is to correct a malformed JSON string so that it becomes syntactically valid AND conforms to a given JSON Schema.

        The user's JSON is invalid for the following reason:
        #{error_reason}

        Here is the malformed JSON content to fix:
        ```
        #{content}
        ```

        It MUST be corrected to strictly conform to the following JSON Schema:
        ```json
        #{schema_json}
        ```

        CRITICAL INSTRUCTIONS:
        1.  Analyze the error, the broken JSON, and the schema.
        2.  Correct the JSON so it is syntactically perfect and valid against the schema.
        3.  Return ONLY the raw, corrected JSON object. Do not include any text, explanations, or markdown fences.
      PROMPT
    end

    def forced_extraction_context?(context, original_content, content)
      context == :forced_extraction ||
        (original_content != content && (original_content.include?("```") || original_content.length > 200 || original_content.include?("\n")))
    end

    def build_final_error_message(error, schema, candidate_json, max_attempts)
      base_message = "Failed to heal JSON after #{max_attempts} healing attempts. Last error: #{error.message}"

      return base_message unless error.is_a?(SchemaValidationError) && schema.validation_available?

      # For schema validation errors, include specific validation details
      parsed_json_for_errors = safely_parse_json(candidate_json)
      return base_message unless parsed_json_for_errors

      validation_errors = schema.validation_errors(parsed_json_for_errors)
      error_details = validation_errors.any? ? ". Last errors: #{validation_errors.join(", ")}" : ""
      "#{base_message}#{error_details}"
    end

    def safely_parse_json(candidate_json)
      JSON.parse(cleanup_syntax(candidate_json))
    rescue StandardError
      nil
    end
  end
end
