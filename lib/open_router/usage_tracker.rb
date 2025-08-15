# frozen_string_literal: true

module OpenRouter
  # Tracks token usage and costs across API calls
  class UsageTracker
    attr_reader :total_prompt_tokens, :total_completion_tokens, :total_cached_tokens,
                :total_cost, :request_count, :model_usage, :session_start

    def initialize
      reset!
    end

    # Reset all tracking counters
    def reset!
      @total_prompt_tokens = 0
      @total_completion_tokens = 0
      @total_cached_tokens = 0
      @total_cost = 0.0
      @request_count = 0
      @model_usage = Hash.new { |h, k| h[k] = create_model_stats }
      @session_start = Time.now
      @request_history = []
    end

    # Track usage from a response
    #
    # @param response [Response] The response object to track
    # @param model [String] The model used (optional, will try to get from response)
    def track(response, model: nil)
      return unless response

      model ||= response.model
      prompt_tokens = response.prompt_tokens
      completion_tokens = response.completion_tokens
      cached_tokens = response.cached_tokens
      cost = response.cost_estimate || estimate_cost(model, prompt_tokens, completion_tokens)

      # Update totals
      @total_prompt_tokens += prompt_tokens
      @total_completion_tokens += completion_tokens
      @total_cached_tokens += cached_tokens
      @total_cost += cost if cost
      @request_count += 1

      # Update per-model stats
      if model
        @model_usage[model][:prompt_tokens] += prompt_tokens
        @model_usage[model][:completion_tokens] += completion_tokens
        @model_usage[model][:cached_tokens] += cached_tokens
        @model_usage[model][:cost] += cost if cost
        @model_usage[model][:requests] += 1
      end

      # Store in history
      @request_history << {
        timestamp: Time.now,
        model: model,
        prompt_tokens: prompt_tokens,
        completion_tokens: completion_tokens,
        cached_tokens: cached_tokens,
        cost: cost,
        response_id: response.id
      }

      self
    end

    # Get total tokens used
    def total_tokens
      @total_prompt_tokens + @total_completion_tokens
    end

    # Get average tokens per request
    def average_tokens_per_request
      return 0 if @request_count.zero?

      total_tokens.to_f / @request_count
    end

    # Get average cost per request
    def average_cost_per_request
      return 0 if @request_count.zero?

      @total_cost / @request_count
    end

    # Get session duration in seconds
    def session_duration
      Time.now - @session_start
    end

    # Get tokens per second
    def tokens_per_second
      duration = session_duration
      return 0 if duration.zero?

      total_tokens.to_f / duration
    end

    # Get most used model
    def most_used_model
      return nil if @model_usage.empty?

      @model_usage.max_by { |_, stats| stats[:requests] }&.first
    end

    # Get most expensive model
    def most_expensive_model
      return nil if @model_usage.empty?

      @model_usage.max_by { |_, stats| stats[:cost] }&.first
    end

    # Get cache hit rate
    def cache_hit_rate
      return 0 if @total_prompt_tokens.zero?

      (@total_cached_tokens.to_f / @total_prompt_tokens) * 100
    end

    # Get usage summary
    def summary
      {
        session: {
          start: @session_start,
          duration_seconds: session_duration,
          requests: @request_count
        },
        tokens: {
          total: total_tokens,
          prompt: @total_prompt_tokens,
          completion: @total_completion_tokens,
          cached: @total_cached_tokens,
          cache_hit_rate: "#{cache_hit_rate.round(2)}%"
        },
        cost: {
          total: @total_cost.round(4),
          average_per_request: average_cost_per_request.round(4)
        },
        performance: {
          tokens_per_second: tokens_per_second.round(2),
          average_tokens_per_request: average_tokens_per_request.round(0)
        },
        models: {
          most_used: most_used_model,
          most_expensive: most_expensive_model,
          breakdown: model_breakdown
        }
      }
    end

    # Get model usage breakdown
    def model_breakdown
      @model_usage.transform_values do |stats|
        {
          requests: stats[:requests],
          tokens: stats[:prompt_tokens] + stats[:completion_tokens],
          cost: stats[:cost].round(4),
          cached_tokens: stats[:cached_tokens]
        }
      end
    end

    # Export usage history as CSV
    def export_csv
      require "csv"

      CSV.generate do |csv|
        csv << ["Timestamp", "Model", "Prompt Tokens", "Completion Tokens", "Cached Tokens", "Cost", "Response ID"]
        @request_history.each do |entry|
          csv << [
            entry[:timestamp].iso8601,
            entry[:model],
            entry[:prompt_tokens],
            entry[:completion_tokens],
            entry[:cached_tokens],
            entry[:cost]&.round(4),
            entry[:response_id]
          ]
        end
      end
    end

    # Get request history
    def history(limit: nil)
      limit ? @request_history.last(limit) : @request_history
    end

    # Pretty print summary to console
    def print_summary
      summary_data = summary

      puts "\n#{"=" * 60}"
      puts " OpenRouter Usage Summary"
      puts "=" * 60

      puts "\n📊 Session"
      puts "  Started: #{summary_data[:session][:start].strftime("%Y-%m-%d %H:%M:%S")}"
      puts "  Duration: #{format_duration(summary_data[:session][:duration_seconds])}"
      puts "  Requests: #{summary_data[:session][:requests]}"

      puts "\n🔤 Tokens"
      puts "  Total: #{format_number(summary_data[:tokens][:total])}"
      puts "  Prompt: #{format_number(summary_data[:tokens][:prompt])}"
      puts "  Completion: #{format_number(summary_data[:tokens][:completion])}"
      puts "  Cached: #{format_number(summary_data[:tokens][:cached])} (#{summary_data[:tokens][:cache_hit_rate]})"

      puts "\n💰 Cost"
      puts "  Total: $#{summary_data[:cost][:total]}"
      puts "  Average/Request: $#{summary_data[:cost][:average_per_request]}"

      puts "\n⚡ Performance"
      puts "  Tokens/Second: #{summary_data[:performance][:tokens_per_second]}"
      puts "  Average Tokens/Request: #{summary_data[:performance][:average_tokens_per_request]}"

      if summary_data[:models][:breakdown].any?
        puts "\n🤖 Models Used"
        summary_data[:models][:breakdown].each do |model, stats|
          puts "  #{model}:"
          puts "    Requests: #{stats[:requests]}"
          puts "    Tokens: #{format_number(stats[:tokens])}"
          puts "    Cost: $#{stats[:cost]}"
        end
      end

      puts "\n#{"=" * 60}"
    end

    private

    def create_model_stats
      {
        prompt_tokens: 0,
        completion_tokens: 0,
        cached_tokens: 0,
        cost: 0.0,
        requests: 0
      }
    end

    # Estimate cost if not available from response
    def estimate_cost(model, prompt_tokens, completion_tokens)
      return 0 unless model

      # Try to get pricing from model registry
      model_data = ModelRegistry.get_model(model)
      return 0 unless model_data

      pricing = model_data["pricing"]
      return 0 unless pricing

      prompt_cost = (prompt_tokens / 1_000_000.0) * pricing["prompt"].to_f
      completion_cost = (completion_tokens / 1_000_000.0) * pricing["completion"].to_f

      prompt_cost + completion_cost
    rescue StandardError
      0
    end

    def format_number(num)
      num.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
    end

    def format_duration(seconds)
      hours = seconds / 3600
      minutes = (seconds % 3600) / 60
      seconds %= 60

      parts = []
      parts << "#{hours.to_i}h" if hours >= 1
      parts << "#{minutes.to_i}m" if minutes >= 1
      parts << "#{seconds.to_i}s"

      parts.join(" ")
    end
  end
end
