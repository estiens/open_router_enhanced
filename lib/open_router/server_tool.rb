# frozen_string_literal: true

module OpenRouter
  # A server-side tool executed by OpenRouter itself (rather than the client),
  # passed in the request `tools` array as `{ type: "openrouter:<name>", parameters: {...} }`.
  #
  # @example Web search
  #   client.complete(messages, model: "openai/gpt-5",
  #                   tools: [OpenRouter::ServerTool.web_search(max_results: 3)])
  #
  # @example Any server tool by name
  #   OpenRouter::ServerTool.new("datetime")
  class ServerTool
    NAMESPACE = "openrouter:"

    attr_reader :type, :parameters

    # @param name [String] short name ("web_search") or namespaced ("openrouter:web_search")
    # @param parameters [Hash] tool-specific configuration (sent under the "parameters" key)
    def initialize(name, parameters = {})
      raise ArgumentError, "Server tool name is required" if name.to_s.empty?

      @type = name.to_s.start_with?(NAMESPACE) ? name.to_s : "#{NAMESPACE}#{name}"
      @parameters = parameters || {}
    end

    # Real-time web search (openrouter:web_search). All keyword params are optional
    # and forwarded under "parameters" (engine, max_results, search_context_size,
    # allowed_domains, excluded_domains, user_location, ...).
    def self.web_search(**parameters)
      new("web_search", parameters)
    end

    # Fetch and extract content from URLs (openrouter:web_fetch).
    def self.web_fetch(**parameters)
      new("web_fetch", parameters)
    end

    def to_h
      hash = { type: @type }
      hash[:parameters] = @parameters unless @parameters.empty?
      hash
    end

    def to_json(*args)
      to_h.to_json(*args)
    end
  end
end
