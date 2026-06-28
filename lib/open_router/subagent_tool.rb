# frozen_string_literal: true

require_relative "tool"

module OpenRouter
  # Represents the `openrouter:subagent` server tool, which lets an orchestrator
  # model delegate self-contained subtasks to a cheaper worker model mid-generation.
  #
  # Unlike a function Tool, it serializes to the server-tool shape:
  #   { type: "openrouter:subagent", parameters: { model:, instructions:, ... } }
  #
  # @example
  #   sub = OpenRouter::SubagentTool.new(model: "z-ai/glm-5.2", instructions: "Be concise.")
  #   client.complete(messages, model: "anthropic/claude-3.5-sonnet", tools: [sub])
  class SubagentTool < Tool
    SERVER_TOOL_TYPE = "openrouter:subagent"

    def initialize(model:, instructions: nil, max_completion_tokens: nil,
                   temperature: nil, reasoning: nil)
      raise ArgumentError, "model is required for SubagentTool" if model.nil? || model.to_s.strip.empty?

      @type = SERVER_TOOL_TYPE
      @parameters_config = {
        model: model,
        instructions: instructions,
        max_completion_tokens: max_completion_tokens,
        temperature: temperature,
        reasoning: reasoning
      }.compact
      # Intentionally skip Tool#validate_definition! (no function name/description).
    end

    def to_h
      { type: @type, parameters: @parameters_config }
    end

    def name
      @type
    end

    def description
      "OpenRouter subagent server tool (worker: #{@parameters_config[:model]})"
    end

    def parameters
      nil
    end
  end
end
