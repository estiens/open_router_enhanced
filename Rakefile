# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

# Unit tests only (excludes VCR integration tests)
RSpec::Core::RakeTask.new(:spec) do |t|
  t.exclude_pattern = "spec/vcr/**/*_spec.rb"
end

# VCR integration tests
RSpec::Core::RakeTask.new(:spec_vcr) do |t|
  t.pattern = "spec/vcr/**/*_spec.rb"
end

# All tests (unit + VCR)
RSpec::Core::RakeTask.new(:spec_all) do |t|
  # Run all specs
end

require "rubocop/rake_task"

RuboCop::RakeTask.new

# Default task runs unit tests + rubocop (fast feedback)
task default: %i[spec rubocop]

# Full CI task runs everything
task ci: %i[spec_all rubocop]

# Model exploration tasks
namespace :models do
  desc "Display summary of available models"
  task :summary do
    require_relative "lib/open_router"

    puts "\n🤖 OpenRouter Model Registry Summary"
    puts "=" * 80

    models = OpenRouter::ModelRegistry.all_models

    # Overall stats
    puts "\n📊 Overall Statistics:"
    puts "  Total models: #{models.size}"

    # Provider breakdown
    providers = models.keys.group_by { |id| id.split("/").first }
    puts "\n🏢 Models by Provider:"
    providers.sort_by { |_, models| -models.size }.each do |provider, provider_models|
      puts "  #{provider.ljust(20)} #{provider_models.size} models"
    end

    # Capabilities breakdown
    all_capabilities = models.values.flat_map { |spec| spec[:capabilities] }.uniq.sort
    puts "\n⚡ Available Capabilities:"
    all_capabilities.each do |cap|
      count = models.values.count { |spec| spec[:capabilities].include?(cap) }
      puts "  #{cap.to_s.ljust(25)} #{count} models"
    end

    # Cost analysis
    input_costs = models.values.map { |spec| spec[:cost_per_1k_tokens][:input] }.compact.sort
    output_costs = models.values.map { |spec| spec[:cost_per_1k_tokens][:output] }.compact.sort

    puts "\n💰 Cost Analysis (per 1k tokens):"
    puts "  Input tokens:"
    puts "    Min:    $#{format("%.6f", input_costs.min)}"
    puts "    Max:    $#{format("%.6f", input_costs.max)}"
    puts "    Median: $#{format("%.6f", input_costs[input_costs.size / 2])}"
    puts "  Output tokens:"
    puts "    Min:    $#{format("%.6f", output_costs.min)}"
    puts "    Max:    $#{format("%.6f", output_costs.max)}"
    puts "    Median: $#{format("%.6f", output_costs[output_costs.size / 2])}"

    # Context length analysis
    context_lengths = models.values.map { |spec| spec[:context_length] }.compact.sort
    puts "\n📏 Context Length Analysis:"
    puts "  Min:    #{format_number_with_commas(context_lengths.min)} tokens"
    puts "  Max:    #{format_number_with_commas(context_lengths.max)} tokens"
    puts "  Median: #{format_number_with_commas(context_lengths[context_lengths.size / 2])} tokens"

    # Performance tier breakdown
    tiers = models.values.group_by { |spec| spec[:performance_tier] }
    puts "\n🎯 Performance Tiers:"
    tiers.each do |tier, tier_models|
      puts "  #{tier.to_s.capitalize.ljust(10)} #{tier_models.size} models"
    end

    puts "\n#{"=" * 80}"
    puts "💡 Use 'rake models:search' to find specific models"
    puts "   Example: rake models:search provider=anthropic capability=function_calling"
    puts
  end

  desc "Search for models by criteria (provider, capability, cost, context, etc.)"
  task :search do
    require_relative "lib/open_router"
    require "date"

    args = parse_search_arguments
    puts "\n🔍 Searching OpenRouter Models"
    puts "=" * 80

    selector = build_model_selector(args)
    limit = args[:limit]&.to_i || 20

    puts "\n#{"=" * 80}"
    puts "Results (showing up to #{limit}):\n\n"

    results = fetch_matching_models(selector, args, limit)
    display_search_results(results)

    puts

    # Prevent rake from treating arguments as tasks
    ARGV.drop(1).each { |arg| task(arg.to_sym) { nil } }
  end

  # Parse command-line arguments into a hash
  def self.parse_search_arguments
    ARGV.drop(1).each_with_object({}) do |arg, hash|
      key, value = arg.split("=", 2)
      hash[key.to_sym] = value if key && value
    end
  end

  # Build a ModelSelector from parsed arguments
  def self.build_model_selector(args)
    selector = OpenRouter::ModelSelector.new

    selector = apply_optimization_strategy(selector, args)
    selector = apply_provider_filters(selector, args)
    selector = apply_capability_filters(selector, args)
    selector = apply_cost_filters(selector, args)
    selector = apply_context_filter(selector, args)
    apply_date_filter(selector, args)
  end

  # Apply optimization strategy to selector
  def self.apply_optimization_strategy(selector, args)
    return selector unless args[:optimize]

    strategy = args[:optimize].to_sym
    selector = selector.optimize_for(strategy)
    puts "📈 Optimizing for: #{strategy}"
    selector
  end

  # Apply provider filters to selector
  def self.apply_provider_filters(selector, args)
    return selector unless args[:provider]

    providers = args[:provider].split(",").map(&:strip)
    selector = selector.require_providers(*providers)
    puts "🏢 Provider: #{providers.join(", ")}"
    selector
  end

  # Apply capability filters to selector
  def self.apply_capability_filters(selector, args)
    capability_arg = args[:capability] || args[:capabilities]
    return selector unless capability_arg

    caps = capability_arg.split(",").map { |c| c.strip.to_sym }
    selector = selector.require(*caps)
    puts "⚡ Required capabilities: #{caps.join(", ")}"
    selector
  end

  # Apply cost filters to selector
  def self.apply_cost_filters(selector, args)
    selector = apply_input_cost_filter(selector, args)
    apply_output_cost_filter(selector, args)
  end

  # Apply input cost filter
  def self.apply_input_cost_filter(selector, args)
    return selector unless args[:max_cost]

    max_cost = args[:max_cost].to_f
    selector = selector.within_budget(max_cost:)
    puts "💰 Max cost (input): $#{format("%.6f", max_cost)}/1k tokens"
    selector
  end

  # Apply output cost filter
  def self.apply_output_cost_filter(selector, args)
    return selector unless args[:max_output_cost]

    max_output_cost = args[:max_output_cost].to_f
    selector = selector.within_budget(max_output_cost:)
    puts "💰 Max cost (output): $#{format("%.6f", max_output_cost)}/1k tokens"
    selector
  end

  # Apply context length filter to selector
  def self.apply_context_filter(selector, args)
    return selector unless args[:min_context]

    min_context = args[:min_context].to_i
    selector = selector.min_context(min_context)
    puts "📏 Min context: #{format_number_with_commas(min_context)} tokens"
    selector
  end

  # Apply date filter to selector
  def self.apply_date_filter(selector, args)
    if args[:newer_than]
      date = Date.parse(args[:newer_than])
      selector = selector.newer_than(date)
      puts "📅 Released after: #{date}"
    end

    puts "🎯 Performance tier: #{args[:tier]}" if args[:tier]
    selector
  end

  # Fetch matching models based on selector and arguments
  def self.fetch_matching_models(selector, args, limit)
    if args[:fallbacks]
      selector.choose_with_fallbacks(limit:)
    else
      fetch_sorted_candidates(selector, limit)
    end
  end

  # Fetch and sort all matching candidates
  def self.fetch_sorted_candidates(selector, limit)
    requirements = selector.instance_variable_get(:@requirements)
    provider_preferences = selector.instance_variable_get(:@provider_preferences)
    strategy = selector.instance_variable_get(:@strategy)

    candidates = OpenRouter::ModelRegistry.models_meeting_requirements(requirements)
    candidates = filter_by_provider_preferences(candidates, provider_preferences)
    sorted = sort_by_strategy(candidates, strategy)

    sorted.first(limit)
  end

  # Display search results
  def self.display_search_results(results)
    if results.empty?
      display_no_results
    else
      display_model_results(results)
    end
  end

  # Display message when no results found
  def self.display_no_results
    puts "❌ No models found matching your criteria"
    puts "\n💡 Try relaxing your requirements or use different filters"
  end

  # Display list of model results
  def self.display_model_results(results)
    results.each_with_index do |(model_id, specs), index|
      next unless specs

      specs = OpenRouter::ModelRegistry.get_model_info(model_id) if model_id.is_a?(String) && !specs
      display_model_info(model_id, specs, index)
    end

    puts "=" * 80
    puts "Found #{results.size} matching model#{"s" if results.size != 1}"
  end

  # Display information for a single model
  def self.display_model_info(model_id, specs, index)
    puts "#{(index + 1).to_s.rjust(3)}. #{model_id}"
    puts "     Name: #{specs[:name]}" if specs[:name]
    puts "     Cost: $#{format("%.6f", specs[:cost_per_1k_tokens][:input])}/1k input, " \
         "$#{format("%.6f", specs[:cost_per_1k_tokens][:output])}/1k output"
    puts "     Context: #{format_number_with_commas(specs[:context_length])} tokens"
    puts "     Capabilities: #{specs[:capabilities].join(", ")}"
    puts "     Tier: #{specs[:performance_tier]}"

    display_release_date(specs[:created_at]) if specs[:created_at]
    puts
  end

  # Display release date for a model
  def self.display_release_date(created_at)
    created = Time.at(created_at).strftime("%Y-%m-%d")
    puts "     Released: #{created}"
  end

  # Format number with comma separators
  def self.format_number_with_commas(number)
    number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
  end

  # Helper methods for search task
  def self.filter_by_provider_preferences(candidates, preferences)
    return candidates if preferences.empty?

    filtered = candidates.dup

    if preferences[:required]
      required_providers = preferences[:required]
      filtered = filtered.select do |model_id, _|
        provider = model_id.split("/").first
        required_providers.include?(provider)
      end
    end

    if preferences[:avoided]
      avoided_providers = preferences[:avoided]
      filtered = filtered.reject do |model_id, _|
        provider = model_id.split("/").first
        avoided_providers.include?(provider)
      end
    end

    filtered
  end

  def self.sort_by_strategy(candidates, strategy)
    case strategy
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
