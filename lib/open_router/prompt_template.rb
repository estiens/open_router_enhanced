# frozen_string_literal: true

module OpenRouter
  # Main prompt template class that handles variable interpolation,
  # few-shot examples, and chat message formatting
  class PromptTemplate
    attr_reader :template, :input_variables, :prefix, :suffix, :examples, :example_template

    # Initialize a new PromptTemplate
    #
    # @param template [String, nil] Main template string with {variable} placeholders
    # @param input_variables [Array<Symbol>] List of required input variables
    # @param prefix [String, nil] Optional prefix text (for few-shot templates)
    # @param suffix [String, nil] Optional suffix text (for few-shot templates)
    # @param examples [Array<Hash>, nil] Optional examples for few-shot learning
    # @param example_template [String, PromptTemplate, nil] Template for formatting examples
    # @param partial_variables [Hash] Pre-filled variable values
    #
    # @example Basic template
    #   template = PromptTemplate.new(
    #     template: "Translate '{text}' to {language}",
    #     input_variables: [:text, :language]
    #   )
    #
    # @example Few-shot template
    #   template = PromptTemplate.new(
    #     prefix: "You are a translator. Here are some examples:",
    #     suffix: "Now translate: {input}",
    #     examples: [
    #       { input: "Hello", output: "Bonjour" },
    #       { input: "Goodbye", output: "Au revoir" }
    #     ],
    #     example_template: "Input: {input}\nOutput: {output}",
    #     input_variables: [:input]
    #   )
    def initialize(template: nil, input_variables: [], prefix: nil, suffix: nil,
                   examples: nil, example_template: nil, partial_variables: {})
      @template = template
      @input_variables = Array(input_variables).map(&:to_sym)
      @prefix = prefix
      @suffix = suffix
      @examples = examples
      @example_template = build_example_template(example_template)
      @partial_variables = partial_variables.transform_keys(&:to_sym)

      validate_configuration!
    end

    # Format the template with provided variables
    #
    # @param variables [Hash] Variable values to interpolate
    # @return [String] Formatted prompt text
    # @raise [ArgumentError] If required variables are missing
    def format(variables = {})
      variables = @partial_variables.merge(variables.transform_keys(&:to_sym))
      validate_variables!(variables)

      if few_shot_template?
        format_few_shot(variables)
      else
        format_simple(variables)
      end
    end

    # Format as chat messages for OpenRouter API
    #
    # @param variables [Hash] Variable values to interpolate
    # @param role [String] Role for the message (user, system, assistant)
    # @return [Array<Hash>] Messages array for OpenRouter API
    def to_messages(variables = {})
      formatted = format(variables)

      # Split by role markers if present (e.g., "System: ... User: ...")
      if formatted.include?("System:") || formatted.include?("Assistant:") || formatted.include?("User:")
        parse_chat_format(formatted)
      else
        # Default to single user message
        [{ role: "user", content: formatted }]
      end
    end

    # Create a partial template with some variables pre-filled
    #
    # @param partial_variables [Hash] Variables to pre-fill
    # @return [PromptTemplate] New template with partial variables
    def partial(partial_variables = {})
      self.class.new(
        template: @template,
        input_variables: @input_variables - partial_variables.keys.map(&:to_sym),
        prefix: @prefix,
        suffix: @suffix,
        examples: @examples,
        example_template: @example_template,
        partial_variables: @partial_variables.merge(partial_variables.transform_keys(&:to_sym))
      )
    end

    # Check if this is a few-shot template
    #
    # @return [Boolean]
    def few_shot_template?
      !@examples.nil? && !@examples.empty?
    end

    # Class method for convenient DSL-style creation
    #
    # @example DSL usage
    #   template = PromptTemplate.build do
    #     template "Translate '{text}' to {language}"
    #     variables :text, :language
    #   end
    def self.build(&block)
      builder = Builder.new
      builder.instance_eval(&block)
      builder.build
    end

    private

    def validate_configuration!
      raise ArgumentError, "Either template or suffix must be provided" if @template.nil? && @suffix.nil?

      return unless few_shot_template? && @example_template.nil?

      raise ArgumentError, "example_template is required when examples are provided"
    end

    def validate_variables!(variables)
      missing = @input_variables - variables.keys
      return if missing.empty?

      raise ArgumentError, "Missing required variables: #{missing.join(", ")}"
    end

    def format_simple(variables)
      interpolate(@template, variables)
    end

    def format_few_shot(variables)
      parts = []
      parts << interpolate(@prefix, variables) if @prefix

      if @examples && @example_template
        formatted_examples = @examples.map do |example|
          # Use only the example data for formatting, not user-provided variables
          @example_template.format(example)
        end
        parts.concat(formatted_examples)
      end

      parts << interpolate(@suffix, variables) if @suffix
      parts.join("\n\n")
    end

    def interpolate(text, variables)
      return "" if text.nil?

      result = text.dup
      variables.each do |key, value|
        # Support both {var} and {var:format} syntax
        result.gsub!(/\{#{Regexp.escape(key.to_s)}(?::[^}]+)?\}/, value.to_s)
      end
      result
    end

    def build_example_template(template)
      case template
      when PromptTemplate
        template
      when String
        PromptTemplate.new(
          template: template,
          input_variables: extract_variables(template)
        )
      when nil
        nil
      else
        raise ArgumentError, "example_template must be a String or PromptTemplate"
      end
    end

    def extract_variables(text)
      return [] if text.nil?

      # Extract {variable} or {variable:format} patterns
      text.scan(/\{(\w+)(?::[^}]+)?\}/).flatten.map(&:to_sym).uniq
    end

    def parse_chat_format(text)
      messages = []
      current_role = "user"
      current_content = []

      text.lines.each do |line|
        if line.start_with?("System:")
          unless current_content.empty?
            messages << { role: current_role, content: current_content.join.strip }
            current_content = []
          end
          current_role = "system"
          current_content << line.sub("System:", "").strip
        elsif line.start_with?("Assistant:")
          unless current_content.empty?
            messages << { role: current_role, content: current_content.join.strip }
            current_content = []
          end
          current_role = "assistant"
          current_content << line.sub("Assistant:", "").strip
        elsif line.start_with?("User:")
          unless current_content.empty?
            messages << { role: current_role, content: current_content.join.strip }
            current_content = []
          end
          current_role = "user"
          current_content << line.sub("User:", "").strip
        else
          current_content << "\n" unless current_content.empty?
          current_content << line
        end
      end

      messages << { role: current_role, content: current_content.join.strip } unless current_content.empty?

      messages
    end

    # Builder class for DSL-style template creation
    class Builder
      def initialize
        @config = {}
      end

      def template(text)
        @config[:template] = text
      end

      def variables(*vars)
        @config[:input_variables] = vars
      end

      def prefix(text)
        @config[:prefix] = text
      end

      def suffix(text)
        @config[:suffix] = text
      end

      def examples(examples_array)
        @config[:examples] = examples_array
      end

      def example_template(template)
        @config[:example_template] = template
      end

      def partial_variables(vars)
        @config[:partial_variables] = vars
      end

      def build
        PromptTemplate.new(**@config)
      end
    end
  end

  # Convenient factory methods
  module Prompt
    # Create a simple prompt template
    def self.template(template, variables: [])
      PromptTemplate.new(template: template, input_variables: variables)
    end

    # Create a few-shot prompt template
    def self.few_shot(prefix:, suffix:, examples:, example_template:, variables:)
      PromptTemplate.new(
        prefix: prefix,
        suffix: suffix,
        examples: examples,
        example_template: example_template,
        input_variables: variables
      )
    end

    # Create a chat-style template
    def self.chat(&block)
      PromptTemplate.build(&block)
    end
  end
end
