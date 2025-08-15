# frozen_string_literal: true

require "date"

module OpenRouter
  class ModelSelectionError < Error; end

  # ModelSelector provides a fluent DSL interface for selecting the best AI model
  # based on specific requirements. It wraps the ModelRegistry functionality
  # with an intuitive, chainable API.
  #
  # @example Basic usage
  #   selector = OpenRouter::ModelSelector.new
  #   model = selector.optimize_for(:cost)
  #                   .require(:function_calling, :vision)
  #                   .within_budget(max_cost: 0.01)
  #                   .choose
  #
  # @example With provider preferences
  #   model = OpenRouter::ModelSelector.new
  #                                   .prefer_providers("anthropic", "openai")
  #                                   .require(:function_calling)
  #                                   .choose
  #
  # @example With fallback selection
  #   models = OpenRouter::ModelSelector.new
  #                                     .optimize_for(:performance)
  #                                     .choose_with_fallbacks(limit: 3)
  class ModelSelector
    # Available optimization strategies
    STRATEGIES = {
      cost: { sort_by: :cost, pick_newer: false },
      performance: { sort_by: :performance, pick_newer: false },
      latest: { sort_by: :date, pick_newer: true },
      context: { sort_by: :context_length, pick_newer: false }
    }.freeze

    def initialize(requirements: {}, strategy: :cost, provider_preferences: {}, fallback_options: {})
      @requirements = requirements.dup
      @strategy = strategy
      @provider_preferences = provider_preferences.dup
      @fallback_options = fallback_options.dup
    end

    # Set the optimization strategy for model selection
    #
    # @param strategy [Symbol] The optimization strategy (:cost, :performance, :latest, :context)
    # @return [ModelSelector] Returns self for method chaining
    # @raise [ArgumentError] If strategy is not supported
    #
    # @example
    #   selector.optimize_for(:cost)      # Choose cheapest model
    #   selector.optimize_for(:performance) # Choose highest performance tier
    #   selector.optimize_for(:latest)    # Choose newest model
    #   selector.optimize_for(:context)   # Choose model with largest context window
    def optimize_for(strategy)
      unless STRATEGIES.key?(strategy)
        raise ArgumentError,
              "Unknown strategy: #{strategy}. Available: #{STRATEGIES.keys.join(", ")}"
      end

      new_requirements = @requirements.dup

      # Apply strategy-specific requirements
      case strategy
      when :performance
        new_requirements[:performance_tier] = :premium
      when :latest
        new_requirements[:pick_newer] = true
      end

      self.class.new(
        requirements: new_requirements,
        strategy:,
        provider_preferences: @provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Require specific capabilities from the selected model
    #
    # @param capabilities [Array<Symbol>] Required capabilities
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.require(:function_calling)
    #   selector.require(:function_calling, :vision, :structured_outputs)
    def require(*capabilities)
      new_requirements = @requirements.dup
      new_requirements[:capabilities] = Array(new_requirements[:capabilities]) + capabilities
      new_requirements[:capabilities].uniq!

      self.class.new(
        requirements: new_requirements,
        strategy: @strategy,
        provider_preferences: @provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Set budget constraints for model selection
    #
    # @param max_cost [Float] Maximum cost per 1k input tokens
    # @param max_output_cost [Float] Maximum cost per 1k output tokens (optional)
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.within_budget(max_cost: 0.01)
    #   selector.within_budget(max_cost: 0.01, max_output_cost: 0.02)
    def within_budget(max_cost: nil, max_output_cost: nil)
      new_requirements = @requirements.dup
      new_requirements[:max_input_cost] = max_cost if max_cost
      new_requirements[:max_output_cost] = max_output_cost if max_output_cost

      self.class.new(
        requirements: new_requirements,
        strategy: @strategy,
        provider_preferences: @provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Set minimum context length requirement
    #
    # @param tokens [Integer] Minimum context length in tokens
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.min_context(100_000)  # Require at least 100k context
    def min_context(tokens)
      new_requirements = @requirements.dup
      new_requirements[:min_context_length] = tokens

      self.class.new(
        requirements: new_requirements,
        strategy: @strategy,
        provider_preferences: @provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Require models released after a specific date
    #
    # @param date [Date, Time, Integer] Cutoff date (Date/Time object or Unix timestamp)
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.newer_than(Date.new(2024, 1, 1))
    #   selector.newer_than(Time.now - 30.days)
    def newer_than(date)
      new_requirements = @requirements.dup
      new_requirements[:released_after_date] = date

      self.class.new(
        requirements: new_requirements,
        strategy: @strategy,
        provider_preferences: @provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Set provider preferences (soft preference - won't exclude other providers)
    #
    # @param providers [Array<String>] Preferred provider names in order of preference
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.prefer_providers("anthropic", "openai")
    def prefer_providers(*providers)
      new_provider_preferences = @provider_preferences.dup
      new_provider_preferences[:preferred] = providers.flatten

      self.class.new(
        requirements: @requirements,
        strategy: @strategy,
        provider_preferences: new_provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Require specific providers (hard filter - only these providers)
    #
    # @param providers [Array<String>] Required provider names
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.require_providers("anthropic")
    def require_providers(*providers)
      new_provider_preferences = @provider_preferences.dup
      new_provider_preferences[:required] = providers.flatten

      self.class.new(
        requirements: @requirements,
        strategy: @strategy,
        provider_preferences: new_provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Avoid specific providers (blacklist)
    #
    # @param providers [Array<String>] Provider names to avoid
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.avoid_providers("google")
    def avoid_providers(*providers)
      new_provider_preferences = @provider_preferences.dup
      new_provider_preferences[:avoided] = providers.flatten

      self.class.new(
        requirements: @requirements,
        strategy: @strategy,
        provider_preferences: new_provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Avoid models matching specific patterns
    #
    # @param patterns [Array<String>] Glob patterns to avoid
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.avoid_patterns("*-free", "*-preview")
    def avoid_patterns(*patterns)
      new_provider_preferences = @provider_preferences.dup
      new_provider_preferences[:avoided_patterns] = patterns.flatten

      self.class.new(
        requirements: @requirements,
        strategy: @strategy,
        provider_preferences: new_provider_preferences,
        fallback_options: @fallback_options
      )
    end

    # Configure fallback behavior
    #
    # @param max_fallbacks [Integer] Maximum number of fallback models to include
    # @param strategy [Symbol] Fallback strategy (:similar, :cheaper, :different_provider)
    # @return [ModelSelector] Returns self for method chaining
    #
    # @example
    #   selector.with_fallbacks(max: 3, strategy: :similar)
    def with_fallbacks(max: 3, strategy: :similar)
      new_fallback_options = { max_fallbacks: max, strategy: }

      self.class.new(
        requirements: @requirements,
        strategy: @strategy,
        provider_preferences: @provider_preferences,
        fallback_options: new_fallback_options
      )
    end

    # Select the best model based on configured requirements
    #
    # @param return_specs [Boolean] Whether to return model specs along with model ID
    # @return [String, Array] Model ID or [model_id, specs] tuple if return_specs is true
    # @return [nil] If no models match requirements
    #
    # @example
    #   model = selector.choose
    #   model, specs = selector.choose(return_specs: true)
    def choose(return_specs: false)
      # Get all models that meet basic requirements
      candidates = filter_by_providers(ModelRegistry.models_meeting_requirements(@requirements))

      return nil if candidates.empty?

      # Apply strategy-specific sorting
      best_match = apply_strategy_sorting(candidates)

      return nil unless best_match

      return_specs ? best_match : best_match.first
    end

    # Select the best model with fallback options
    #
    # @param limit [Integer] Maximum number of models to return (including primary choice)
    # @return [Array<String>] Array of model IDs in order of preference
    # @return [Array] Empty array if no models match requirements
    #
    # @example
    #   models = selector.choose_with_fallbacks(limit: 3)
    #   # => ["gpt-4", "claude-3-opus", "gpt-3.5-turbo"]
    def choose_with_fallbacks(limit: 3)
      candidates = filter_by_providers(ModelRegistry.models_meeting_requirements(@requirements))

      return [] if candidates.empty?

      # Apply strategy-specific sorting to get ordered list
      sorted_candidates = apply_strategy_sorting_all(candidates)

      # Return up to `limit` models
      sorted_candidates.first(limit).map(&:first)
    end

    # Choose with graceful degradation if no models meet all requirements
    #
    # @return [String, nil] Model ID or nil if no models available at all
    #
    # @example
    #   model = selector.choose_with_fallback
    def choose_with_fallback
      # Try with all requirements first
      result = choose
      return result if result

      # Try dropping least important requirements progressively
      fallback_requirements = @requirements.dup

      # Drop requirements in order of importance (least to most important)
      %i[
        released_after_date
        performance_tier
        max_output_cost
        min_context_length
        max_input_cost
      ].each do |requirement|
        next unless fallback_requirements.key?(requirement)

        fallback_requirements.delete(requirement)
        candidates = filter_by_providers(ModelRegistry.models_meeting_requirements(fallback_requirements))

        unless candidates.empty?
          result = apply_strategy_sorting(candidates)
          return result&.first
        end
      end

      # Last resort: just pick any model that meets capability requirements
      if fallback_requirements[:capabilities]
        basic_requirements = { capabilities: fallback_requirements[:capabilities] }
        candidates = filter_by_providers(ModelRegistry.models_meeting_requirements(basic_requirements))
        result = apply_strategy_sorting(candidates) unless candidates.empty?
        return result&.first if result
      end

      # Final fallback: cheapest available model
      all_candidates = filter_by_providers(ModelRegistry.all_models)
      return nil if all_candidates.empty?

      all_candidates.min_by { |_, specs| specs[:cost_per_1k_tokens][:input] }&.first
    end

    # Get detailed information about the current selection criteria
    #
    # @return [Hash] Hash containing requirements, strategy, and provider preferences
    def selection_criteria
      {
        requirements: deep_dup(@requirements),
        strategy: @strategy,
        provider_preferences: deep_dup(@provider_preferences),
        fallback_options: deep_dup(@fallback_options)
      }
    end

    # Estimate cost for a given model with expected token usage
    #
    # @param model [String] Model ID
    # @param input_tokens [Integer] Expected input tokens
    # @param output_tokens [Integer] Expected output tokens
    # @return [Float] Estimated cost in dollars
    def estimate_cost(model, input_tokens: 1000, output_tokens: 1000)
      ModelRegistry.calculate_estimated_cost(model, input_tokens:, output_tokens:)
    end

    private

    # Deep duplicate a hash or array to avoid shared references
    def deep_dup(obj)
      case obj
      when Hash
        obj.transform_values { |v| deep_dup(v) }
      when Array
        obj.map { |item| deep_dup(item) }
      else
        obj
      end
    end

    # Filter candidates by provider preferences
    def filter_by_providers(candidates)
      return candidates if @provider_preferences.empty?

      filtered = candidates.dup

      # Apply required providers filter (hard requirement)
      if @provider_preferences[:required]
        required_providers = @provider_preferences[:required]
        filtered = filtered.select do |model_id, _|
          provider = extract_provider_from_model_id(model_id)
          required_providers.include?(provider)
        end
      end

      # Apply avoided providers filter
      if @provider_preferences[:avoided]
        avoided_providers = @provider_preferences[:avoided]
        filtered = filtered.reject do |model_id, _|
          provider = extract_provider_from_model_id(model_id)
          avoided_providers.include?(provider)
        end
      end

      # Apply avoided patterns filter
      if @provider_preferences[:avoided_patterns]
        patterns = @provider_preferences[:avoided_patterns]
        filtered = filtered.reject do |model_id, _|
          patterns.any? { |pattern| File.fnmatch(pattern, model_id) }
        end
      end

      filtered
    end

    # Extract provider name from model ID (e.g., "anthropic/claude-3" -> "anthropic")
    def extract_provider_from_model_id(model_id)
      model_id.split("/").first
    end

    # Apply strategy-specific sorting and return best match
    def apply_strategy_sorting(candidates)
      case @strategy
      when :cost
        candidates.min_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
      when :performance
        # Prefer premium tier, then by cost within tier
        candidates.min_by do |_, specs|
          [specs[:performance_tier] == :premium ? 0 : 1, specs[:cost_per_1k_tokens][:input]]
        end
      when :latest
        candidates.max_by { |_, specs| (specs[:created_at] || 0).to_i }
      when :context
        candidates.max_by { |_, specs| (specs[:context_length] || 0).to_i }
      else
        candidates.min_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
      end
    end

    # Apply strategy-specific sorting and return all sorted candidates
    def apply_strategy_sorting_all(candidates)
      case @strategy
      when :cost
        candidates.sort_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
      when :performance
        candidates.sort_by do |_, specs|
          [specs[:performance_tier] == :premium ? 0 : 1, specs[:cost_per_1k_tokens][:input]]
        end
      when :latest
        candidates.sort_by { |_, specs| -(specs[:created_at] || 0).to_i }
      when :context
        candidates.sort_by { |_, specs| -(specs[:context_length] || 0).to_i }
      else
        candidates.sort_by { |_, specs| specs[:cost_per_1k_tokens][:input] }
      end
    end
  end
end
