# frozen_string_literal: true

module OpenRouter
  # Mixin providing ergonomic access to OpenRouter router/meta-model features
  # (Fusion, Pareto Code Router). Builds the right model alias + plugin config
  # and delegates to Client#complete.
  module Routing
    FUSION_MODEL = "openrouter/fusion"
    PARETO_CODE_MODEL = "openrouter/pareto-code"

    # Route to the cheapest code-capable model meeting a quality bar.
    #
    # @param min_coding_score [Float, nil] 0.0–1.0 (1.0 = best). Optional.
    def pareto_complete(messages, min_coding_score: nil, **opts)
      validate_min_coding_score!(min_coding_score)

      plugin = { id: "pareto-router" }
      plugin[:min_coding_score] = min_coding_score unless min_coding_score.nil?

      kwargs = merge_plugin(opts, plugin)
      complete(messages, model: PARETO_CODE_MODEL, **kwargs)
    end

    # Fan a prompt out to a panel of models and synthesize one answer.
    # NOTE: Fusion costs ~4–5x a single completion (panel calls + judge).
    #
    # @param analysis_models [Array<String>, nil] 1–8 panel model ids.
    # @param judge [String, nil] synthesis model id (defaults to the fusion model server-side).
    # @param preset [String, Symbol, nil] curated panel slug (e.g. "general-budget").
    # @param max_tool_calls [Integer, nil] 1–16.
    def fuse(messages, analysis_models: nil, judge: nil, preset: nil, max_tool_calls: nil, **opts)
      validate_analysis_models!(analysis_models)
      validate_max_tool_calls!(max_tool_calls)

      plugin = {
        id: "fusion",
        analysis_models: analysis_models,
        model: judge,
        preset: preset&.to_s,
        max_tool_calls: max_tool_calls
      }.compact

      kwargs = merge_plugin(opts, plugin)
      complete(messages, model: FUSION_MODEL, **kwargs)
    end

    private

    def validate_min_coding_score!(score)
      return if score.nil?

      unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
        raise ArgumentError, "min_coding_score must be a number between 0.0 and 1.0 (got #{score.inspect})"
      end
    end

    def validate_analysis_models!(models)
      return if models.nil?

      unless models.is_a?(Array) && (1..8).cover?(models.size) && models.all? { |m| m.is_a?(String) && !m.strip.empty? }
        raise ArgumentError, "analysis_models must be an array of 1–8 model id strings (got #{models.inspect})"
      end
    end

    def validate_max_tool_calls!(value)
      return if value.nil?

      unless value.is_a?(Integer) && (1..16).cover?(value)
        raise ArgumentError, "max_tool_calls must be an integer between 1 and 16 (got #{value.inspect})"
      end
    end

    # Merge a router plugin into any caller-supplied plugins, de-duped by :id.
    def merge_plugin(opts, plugin)
      existing = Array(opts[:plugins]).map { |p| p.transform_keys(&:to_sym) }
      existing = existing.reject { |p| p[:id].to_s == plugin[:id].to_s }
      opts.merge(plugins: existing + [plugin])
    end
  end
end
