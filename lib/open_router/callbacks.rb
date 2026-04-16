# frozen_string_literal: true

module OpenRouter
  # Mixin providing event callback registration and dispatch for Client.
  module Callbacks
    # Register a callback for a specific event
    #
    # @param event [Symbol] The event to register for (:before_request, :after_response, :on_tool_call, :on_error, :on_stream_chunk, :on_healing)
    # @param block [Proc] The callback to execute
    # @return [self] Returns self for method chaining
    #
    # @example
    #   client.on(:after_response) do |response|
    #     puts "Used #{response.total_tokens} tokens"
    #   end
    def on(event, &block)
      raise ArgumentError, "Invalid event: #{event}. Valid events are: #{@callbacks.keys.join(", ")}" unless @callbacks.key?(event)

      @callbacks[event] << block
      self
    end

    # Remove all callbacks for a specific event
    #
    # @param event [Symbol] The event to clear callbacks for
    # @return [self] Returns self for method chaining
    def clear_callbacks(event = nil)
      if event
        @callbacks[event] = [] if @callbacks.key?(event)
      else
        @callbacks.each_key { |key| @callbacks[key] = [] }
      end
      self
    end

    # Trigger callbacks for a specific event
    #
    # @param event [Symbol] The event to trigger
    # @param data [Object] Data to pass to the callbacks
    def trigger_callbacks(event, data = nil)
      return unless @callbacks[event]

      @callbacks[event].each do |callback|
        callback.call(data)
      rescue StandardError => e
        warn "[OpenRouter] Callback error for #{event}: #{e.message}"
      end
    end
  end
end
