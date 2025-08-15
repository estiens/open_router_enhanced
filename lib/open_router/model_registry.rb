# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "tmpdir"
require "fileutils"
require "openssl"

module OpenRouter
  class ModelRegistryError < Error; end

  class ModelRegistry
    API_BASE = "https://openrouter.ai/api/v1"
    CACHE_DIR = File.join(Dir.tmpdir, "openrouter_cache")
    CACHE_DATA_FILE = File.join(CACHE_DIR, "models_data.json")
    CACHE_METADATA_FILE = File.join(CACHE_DIR, "cache_metadata.json")
    MAX_CACHE_SIZE_MB = 50 # Maximum cache size in megabytes

    class << self
      # Fetch models from OpenRouter API
      def fetch_models_from_api
        uri = URI("#{API_BASE}/models")

        # Use configurable timeout and SSL settings
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.verify_mode = OpenSSL::SSL::VERIFY_PEER
        http.read_timeout = OpenRouter.configuration.model_registry_timeout
        http.open_timeout = OpenRouter.configuration.model_registry_timeout

        request = Net::HTTP::Get.new(uri)
        response = http.request(request)

        unless response.code == "200"
          raise ModelRegistryError,
                "Failed to fetch models from OpenRouter API: #{response.message}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise ModelRegistryError, "Failed to parse OpenRouter API response: #{e.message}"
      rescue StandardError => e
        raise ModelRegistryError, "Network error fetching models: #{e.message}"
      end

      # Ensure cache directory exists and set up cleanup
      def ensure_cache_dir
        FileUtils.mkdir_p(CACHE_DIR) unless Dir.exist?(CACHE_DIR)
        setup_cleanup_hook
      end

      # Check if cache is stale based on TTL
      def cache_stale?
        return true unless File.exist?(CACHE_METADATA_FILE)

        begin
          metadata = JSON.parse(File.read(CACHE_METADATA_FILE))
          cache_time = metadata["cached_at"]
          ttl = OpenRouter.configuration.cache_ttl

          return true unless cache_time

          Time.now.to_i - cache_time.to_i > ttl
        rescue JSON::ParserError, StandardError
          true # If we can't read metadata, consider cache stale
        end
      end

      # Write cache with timestamp metadata
      def write_cache_with_timestamp(models_data)
        ensure_cache_dir

        # Write the actual models data
        File.write(CACHE_DATA_FILE, JSON.pretty_generate(models_data))

        # Write metadata with timestamp
        metadata = {
          "cached_at" => Time.now.to_i,
          "version" => "1.0",
          "source" => "openrouter_api"
        }
        File.write(CACHE_METADATA_FILE, JSON.pretty_generate(metadata))
      end

      # Read cache only if it's fresh
      def read_cache_if_fresh
        return nil if cache_stale?
        return nil unless File.exist?(CACHE_DATA_FILE)

        JSON.parse(File.read(CACHE_DATA_FILE))
      rescue JSON::ParserError
        nil
      end

      # Clear local cache (both files and memory)
      def clear_cache!
        FileUtils.rm_rf(CACHE_DIR) if Dir.exist?(CACHE_DIR)
        @processed_models = nil
        @all_models = nil
      end

      # Refresh models data from API
      def refresh!
        clear_cache!
        fetch_and_cache_models
      end

      # Get processed models (fetch if needed)
      def fetch_and_cache_models
        # Try cache first (only if fresh)
        cached_data = read_cache_if_fresh

        if cached_data
          api_data = cached_data
        else
          # Cache is stale or doesn't exist, fetch from API
          api_data = fetch_models_from_api
          write_cache_with_timestamp(api_data)
        end

        @processed_models = process_api_models(api_data["data"])
      end

      # Find original API model data by model ID
      def find_original_model_data(model_id)
        # Get raw models data (not processed)
        cached_data = read_cache_if_fresh

        if cached_data
          api_data = cached_data
        else
          api_data = fetch_models_from_api
          write_cache_with_timestamp(api_data)
        end

        raw_models = api_data["data"] || []
        raw_models.find { |model| model["id"] == model_id }
      end

      # Convert API model data to our internal format
      def process_api_models(api_models)
        models = {}

        api_models.each do |model_data|
          model_id = model_data["id"]

          models[model_id] = {
            name: model_data["name"],
            cost_per_1k_tokens: {
              input: model_data.dig("pricing", "prompt").to_f,
              output: model_data.dig("pricing", "completion").to_f
            },
            context_length: model_data["context_length"],
            capabilities: extract_capabilities(model_data),
            description: model_data["description"],
            supported_parameters: model_data["supported_parameters"] || [],
            architecture: model_data["architecture"],
            performance_tier: determine_performance_tier(model_data),
            fallbacks: determine_fallbacks(model_id, model_data),
            created_at: model_data["created"]
          }
        end

        models
      end

      # Extract capabilities from model data
      def extract_capabilities(model_data)
        capabilities = [:chat] # All models support basic chat

        # Check for function calling support
        supported_params = model_data["supported_parameters"] || []
        if supported_params.include?("tools") && supported_params.include?("tool_choice")
          capabilities << :function_calling
        end

        # Check for structured output support
        if supported_params.include?("structured_outputs") || supported_params.include?("response_format")
          capabilities << :structured_outputs
        end

        # Check for vision support
        architecture = model_data["architecture"] || {}
        input_modalities = architecture["input_modalities"] || []
        capabilities << :vision if input_modalities.include?("image")

        # Check for large context support
        context_length = model_data["context_length"] || 0
        capabilities << :long_context if context_length > 100_000

        capabilities
      end

      # Determine performance tier based on pricing and capabilities
      def determine_performance_tier(model_data)
        input_cost = model_data.dig("pricing", "prompt").to_f

        # Higher cost generally indicates premium models
        # Note: pricing is per token, not per 1k tokens
        if input_cost > 0.000001 # > $0.001 per 1k tokens (converted from per-token)
          :premium
        else
          :standard
        end
      end

      # Determine fallback models (simplified logic)
      def determine_fallbacks(_model_id, _model_data)
        # For now, return empty array - could be enhanced with smart fallback logic
        []
      end

      # Find the best model matching given requirements
      def find_best_model(requirements = {})
        candidates = models_meeting_requirements(requirements)
        return nil if candidates.empty?

        # If pick_newer is true, prefer newer models over cost
        if requirements[:pick_newer]
          candidates.max_by { |_, specs| specs[:created_at] }
        else
          # Sort by cost (cheapest first) as default strategy
          candidates.min_by { |_, specs| calculate_model_cost(specs, requirements) }
        end
      end

      # Get all models that meet requirements (without sorting)
      def models_meeting_requirements(requirements = {})
        all_models.select do |_model, specs|
          meets_requirements?(specs, requirements)
        end
      end

      # Get fallback models for a given model
      def get_fallbacks(model)
        model_info = get_model_info(model)
        model_info ? model_info[:fallbacks] || [] : []
      end

      # Check if a model exists in the registry
      def model_exists?(model)
        all_models.key?(model)
      end

      # Check if a model has a specific capability
      def has_capability?(model, capability)
        model_info = get_model_info(model)
        return false unless model_info

        model_info[:capabilities].include?(capability)
      end

      # Get detailed information about a model
      def get_model_info(model)
        all_models[model]
      end

      # Get all registered models (fetch from API if needed)
      def all_models
        @all_models ||= fetch_and_cache_models
      end

      # Calculate estimated cost for a request
      def calculate_estimated_cost(model, input_tokens: 0, output_tokens: 0)
        model_info = get_model_info(model)
        return 0 unless model_info

        input_cost = (input_tokens / 1000.0) * model_info[:cost_per_1k_tokens][:input]
        output_cost = (output_tokens / 1000.0) * model_info[:cost_per_1k_tokens][:output]

        input_cost + output_cost
      end

      private

      # Check if model specs meet the given requirements
      def meets_requirements?(specs, requirements)
        # Check capability requirements
        if requirements[:capabilities]
          required_caps = Array(requirements[:capabilities])
          return false unless required_caps.all? { |cap| specs[:capabilities].include?(cap) }
        end

        # Check cost requirements
        if requirements[:max_input_cost] && (specs[:cost_per_1k_tokens][:input] > requirements[:max_input_cost])
          return false
        end

        if requirements[:max_output_cost] && (specs[:cost_per_1k_tokens][:output] > requirements[:max_output_cost])
          return false
        end

        # Check context length requirements
        if requirements[:min_context_length] && (specs[:context_length] < requirements[:min_context_length])
          return false
        end

        # Check performance tier requirements
        if requirements[:performance_tier]
          required_tier = requirements[:performance_tier]
          model_tier = specs[:performance_tier]

          # Premium tier can satisfy premium or standard requirements
          # Standard tier can only satisfy standard requirements
          case required_tier
          when :premium
            return false unless model_tier == :premium
          when :standard
            return false unless %i[standard premium].include?(model_tier)
          end
        end

        # Check released after date requirement
        if requirements[:released_after_date]
          required_date = requirements[:released_after_date]
          model_timestamp = specs[:created_at]

          # Convert date to timestamp if needed
          required_timestamp = case required_date
                               when Date
                                 required_date.to_time.to_i
                               when Time
                                 required_date.to_i
                               when Integer
                                 required_date
                               else
                                 return false
                               end

          return false if model_timestamp < required_timestamp
        end

        true
      end

      # Calculate the cost metric for sorting models
      def calculate_model_cost(specs, _requirements)
        # Simple cost calculation for sorting - could be made more sophisticated
        # For now, just use input token cost as the primary metric
        specs[:cost_per_1k_tokens][:input]
      end

      # Set up cleanup hook to manage cache size
      def setup_cleanup_hook
        return if @cleanup_hook_set

        at_exit { cleanup_oversized_cache }
        @cleanup_hook_set = true
      end

      # Clean up cache if it exceeds size limits
      def cleanup_oversized_cache
        return unless Dir.exist?(CACHE_DIR)

        cache_size_mb = calculate_cache_size_mb
        return unless cache_size_mb > MAX_CACHE_SIZE_MB

        # Remove cache files if oversized
        FileUtils.rm_rf(CACHE_DIR)
      rescue StandardError
        # Silently ignore cleanup errors - don't break the application
      end

      # Calculate current cache size in megabytes
      def calculate_cache_size_mb
        total_size = Dir.glob(File.join(CACHE_DIR, "**/*"))
                        .select { |f| File.file?(f) }
                        .sum do |f|
          File.size(f)
        rescue StandardError
          0
        end
        total_size / (1024.0 * 1024.0)
      end
    end
  end
end
