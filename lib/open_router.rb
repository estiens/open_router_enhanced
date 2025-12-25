# frozen_string_literal: true

require "faraday"
require "faraday/multipart"

begin
  require "faraday_middleware"
  module OpenRouter; HAS_JSON_MW = true; end
rescue LoadError
  module OpenRouter; HAS_JSON_MW = false; end
end

module OpenRouter
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class CapabilityError < Error; end
end

require_relative "open_router/http"
require_relative "open_router/tool"
require_relative "open_router/tool_call_base"
require_relative "open_router/tool_call"
require_relative "open_router/schema"
require_relative "open_router/json_healer"
require_relative "open_router/response"
require_relative "open_router/responses_response"
require_relative "open_router/responses_tool_call"
require_relative "open_router/model_registry"
require_relative "open_router/model_selector"
require_relative "open_router/prompt_template"
require_relative "open_router/usage_tracker"
require_relative "open_router/client"
require_relative "open_router/streaming_client"
require_relative "open_router/version"

module OpenRouter
  class Configuration
    attr_writer :access_token
    attr_accessor :api_version, :extra_headers, :faraday_config, :log_errors, :request_timeout, :uri_base

    # Healing configuration
    attr_accessor :auto_heal_responses, :healer_model, :max_heal_attempts

    # Native OpenRouter response healing (server-side)
    attr_accessor :auto_native_healing

    # Cache configuration
    attr_accessor :cache_ttl

    # Model registry configuration
    attr_accessor :model_registry_timeout, :model_registry_retries

    # Capability validation configuration
    attr_accessor :strict_mode

    # Automatic forcing configuration
    attr_accessor :auto_force_on_unsupported_models

    # Default structured output mode configuration
    attr_accessor :default_structured_output_mode

    DEFAULT_API_VERSION = "v1"
    DEFAULT_REQUEST_TIMEOUT = 120
    DEFAULT_URI_BASE = "https://openrouter.ai/api"
    DEFAULT_CACHE_TTL = 7 * 24 * 60 * 60 # 7 days in seconds
    DEFAULT_MODEL_REGISTRY_TIMEOUT = 30
    DEFAULT_MODEL_REGISTRY_RETRIES = 3

    def initialize
      self.access_token = nil
      self.api_version = DEFAULT_API_VERSION
      self.extra_headers = {}
      self.log_errors = false
      self.request_timeout = DEFAULT_REQUEST_TIMEOUT
      self.uri_base = DEFAULT_URI_BASE

      # Healing defaults
      self.auto_heal_responses = false
      self.healer_model = "openai/gpt-4o-mini"
      self.max_heal_attempts = 2

      # Native OpenRouter healing (enabled by default for non-streaming structured outputs)
      self.auto_native_healing = ENV.fetch("OPENROUTER_AUTO_NATIVE_HEALING", "true").downcase == "true"

      # Cache defaults
      self.cache_ttl = ENV.fetch("OPENROUTER_CACHE_TTL", DEFAULT_CACHE_TTL).to_i

      # Model registry defaults
      self.model_registry_timeout = ENV.fetch("OPENROUTER_REGISTRY_TIMEOUT", DEFAULT_MODEL_REGISTRY_TIMEOUT).to_i
      self.model_registry_retries = ENV.fetch("OPENROUTER_REGISTRY_RETRIES", DEFAULT_MODEL_REGISTRY_RETRIES).to_i

      # Capability validation defaults
      self.strict_mode = ENV.fetch("OPENROUTER_STRICT_MODE", "false").downcase == "true"

      # Auto forcing defaults
      self.auto_force_on_unsupported_models = ENV.fetch("OPENROUTER_AUTO_FORCE", "true").downcase == "true"

      # Default structured output mode
      self.default_structured_output_mode = ENV.fetch("OPENROUTER_DEFAULT_MODE", "strict").to_sym
    end

    def access_token
      return @access_token if @access_token

      raise ConfigurationError, "OpenRouter access token missing!"
    end

    def faraday(&block)
      self.faraday_config = block
    end

    def site_name=(value)
      @extra_headers["X-Title"] = value
    end

    def site_url=(value)
      @extra_headers["HTTP-Referer"] = value
    end
  end

  class << self
    attr_writer :configuration
  end

  def self.configuration
    @configuration ||= OpenRouter::Configuration.new
  end

  def self.configure
    yield(configuration)
  end
end
