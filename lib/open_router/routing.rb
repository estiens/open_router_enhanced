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

    private

    def validate_min_coding_score!(score)
      return if score.nil?

      unless score.is_a?(Numeric) && score >= 0.0 && score <= 1.0
        raise ArgumentError, "min_coding_score must be a number between 0.0 and 1.0 (got #{score.inspect})"
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
