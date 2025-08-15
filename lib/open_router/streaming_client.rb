# frozen_string_literal: true

module OpenRouter
  # Enhanced streaming client with better event handling and response reconstruction
  class StreamingClient < Client
    # Initialize streaming client with additional streaming-specific options
    def initialize(*args, **kwargs, &block)
      super(*args, **kwargs, &block)
      @streaming_callbacks = {
        on_chunk: [],
        on_start: [],
        on_finish: [],
        on_tool_call_chunk: [],
        on_error: []
      }
    end

    # Register streaming-specific callbacks
    #
    # @param event [Symbol] The streaming event to register for
    # @param block [Proc] The callback to execute
    # @return [self] Returns self for method chaining
    def on_stream(event, &block)
      unless @streaming_callbacks.key?(event)
        valid_events = @streaming_callbacks.keys.join(", ")
        raise ArgumentError, "Invalid streaming event: #{event}. Valid events are: #{valid_events}"
      end

      @streaming_callbacks[event] << block
      self
    end

    # Enhanced streaming completion with better event handling and response reconstruction
    #
    # @param messages [Array<Hash>] Array of message hashes
    # @param model [String|Array] Model identifier or array of models for fallback
    # @param accumulate_response [Boolean] Whether to accumulate and return complete response
    # @param extras [Hash] Additional parameters for the completion request
    # @return [Response, nil] Complete response if accumulate_response is true, nil otherwise
    def stream_complete(messages, model: "openrouter/auto", accumulate_response: true, **extras)
      response_accumulator = ResponseAccumulator.new if accumulate_response

      # Set up streaming handler
      stream_handler = build_stream_handler(response_accumulator)

      # Trigger start callback
      trigger_streaming_callbacks(:on_start, { model: model, messages: messages })

      begin
        # Execute the streaming request
        complete(messages, model: model, stream: stream_handler, **extras)

        # Return accumulated response if requested
        if accumulate_response && response_accumulator
          final_response = response_accumulator.build_response
          trigger_streaming_callbacks(:on_finish, final_response)
          final_response
        else
          trigger_streaming_callbacks(:on_finish, nil)
          nil
        end
      rescue StandardError => e
        trigger_streaming_callbacks(:on_error, e)
        raise
      end
    end

    # Stream with a simple block interface
    #
    # @param messages [Array<Hash>] Array of message hashes
    # @param model [String|Array] Model identifier
    # @param block [Proc] Block to call for each content chunk
    # @param extras [Hash] Additional parameters
    #
    # @example
    #   client.stream(messages, model: "openai/gpt-4o-mini") do |chunk|
    #     print chunk
    #   end
    def stream(messages, model: "openrouter/auto", **extras, &block)
      raise ArgumentError, "Block required for streaming" unless block_given?

      stream_complete(
        messages,
        model: model,
        accumulate_response: false,
        **extras
      ) do |chunk|
        content = extract_content_from_chunk(chunk)
        block.call(content) if content
      end
    end

    private

    def build_stream_handler(accumulator)
      proc do |chunk|
        # Trigger chunk callback
        trigger_streaming_callbacks(:on_chunk, chunk)

        # Accumulate if needed
        accumulator&.add_chunk(chunk)

        # Handle tool call chunks
        trigger_streaming_callbacks(:on_tool_call_chunk, chunk) if chunk.dig("choices", 0, "delta", "tool_calls")

        # Also trigger general stream callbacks for backward compatibility
        trigger_callbacks(:on_stream_chunk, chunk)
      rescue StandardError => e
        trigger_streaming_callbacks(:on_error, e)
      end
    end

    def trigger_streaming_callbacks(event, data)
      return unless @streaming_callbacks[event]

      @streaming_callbacks[event].each do |callback|
        callback.call(data)
      rescue StandardError => e
        warn "[OpenRouter] Streaming callback error for #{event}: #{e.message}"
      end
    end

    def extract_content_from_chunk(chunk)
      chunk.dig("choices", 0, "delta", "content")
    end
  end

  # Accumulates streaming chunks to reconstruct a complete response
  class ResponseAccumulator
    def initialize
      @chunks = []
      @content_parts = []
      @tool_calls = {}
      @first_chunk = nil
      @last_chunk = nil
    end

    # Add a streaming chunk
    def add_chunk(chunk)
      @chunks << chunk
      @first_chunk ||= chunk
      @last_chunk = chunk

      process_chunk(chunk)
    end

    # Build final response object
    def build_response
      return nil if @chunks.empty?

      # Build the complete response structure
      response_data = build_response_structure

      Response.new(response_data)
    end

    private

    def process_chunk(chunk)
      delta = chunk.dig("choices", 0, "delta")
      return unless delta

      # Accumulate content
      if (content = delta["content"])
        @content_parts << content
      end

      # Accumulate tool calls
      if (tool_calls = delta["tool_calls"])
        tool_calls.each do |tc|
          index = tc["index"]
          @tool_calls[index] ||= {
            "id" => tc["id"],
            "type" => tc["type"],
            "function" => { "name" => "", "arguments" => "" }
          }

          @tool_calls[index]["function"]["name"] = tc["function"]["name"] if tc.dig("function", "name")

          @tool_calls[index]["function"]["arguments"] += tc["function"]["arguments"] if tc.dig("function", "arguments")
        end
      end
    end

    def build_response_structure
      choice = {
        "index" => 0,
        "message" => {
          "role" => "assistant",
          "content" => @content_parts.join
        },
        "finish_reason" => @last_chunk.dig("choices", 0, "finish_reason")
      }

      # Add tool calls if present
      choice["message"]["tool_calls"] = @tool_calls.values unless @tool_calls.empty?

      {
        "id" => @first_chunk["id"],
        "object" => @first_chunk["object"],
        "created" => @first_chunk["created"],
        "model" => @first_chunk["model"],
        "choices" => [choice],
        "usage" => @last_chunk["usage"],
        "provider" => @first_chunk["provider"],
        "system_fingerprint" => @first_chunk["system_fingerprint"]
      }.compact
    end
  end
end
