# frozen_string_literal: true

require "json"

module OpenRouter
  class ToolCallError < Error; end

  # Shared behavior for tool call parsing across different API formats.
  # Include this module and define `name` and `arguments_string` accessors.
  module ToolCallBase
    # Parse the arguments JSON string into a Ruby hash
    def arguments
      @arguments ||= begin
        JSON.parse(arguments_string)
      rescue JSON::ParserError => e
        raise ToolCallError, "Failed to parse tool call arguments: #{e.message}"
      end
    end

    # Execute the tool call with a provided block
    # The block receives (name, arguments) and should return the result
    #
    # @yield [name, arguments] Block to execute the tool
    # @return [ToolResultBase] The result of execution
    def execute(&block)
      raise ArgumentError, "Block required for tool execution" unless block_given?

      begin
        result = block.call(name, arguments)
        build_result(result)
      rescue StandardError => e
        build_result(nil, e.message)
      end
    end

    # Subclasses must implement this to return the appropriate result type
    def build_result(_result, _error = nil)
      raise NotImplementedError, "Subclasses must implement build_result"
    end
  end

  # Shared behavior for tool execution results.
  # Include this module and define `tool_call`, `result`, and `error` accessors.
  module ToolResultBase
    def success?
      error.nil?
    end

    def failure?
      !success?
    end

    module ClassMethods
      # Create a failed result
      def failure(tool_call, error)
        new(tool_call, nil, error)
      end

      # Create a successful result
      def success(tool_call, result)
        new(tool_call, result, nil)
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end
  end
end
