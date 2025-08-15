# frozen_string_literal: true

require "vcr"
require "webmock/rspec"

# Detect CI environment
def ci_environment?
  ENV["CI"] == "true" || ENV["GITHUB_ACTIONS"] == "true" || ENV["CONTINUOUS_INTEGRATION"] == "true"
end

VCR.configure do |config|
  config.cassette_library_dir = "spec/fixtures/vcr_cassettes"
  config.hook_into :webmock

  # Filter sensitive data
  config.filter_sensitive_data("<OPENROUTER_API_KEY>") { ENV["OPENROUTER_API_KEY"] }
  config.filter_sensitive_data("<OPEN_ROUTER_API_KEY>") { ENV["OPEN_ROUTER_API_KEY"] }
  config.filter_sensitive_data("<ACCESS_TOKEN>") { ENV["ACCESS_TOKEN"] }

  # Determine the recording mode based on environment variables and CI
  record_mode = if ENV["CI"]
                  :none # Never record in CI, use existing cassettes only
                elsif ENV["VCR_RECORD_ALL"] == "true"
                  :all # Re-record everything when explicitly requested
                elsif ENV["VCR_RECORD_NEW"] == "true"
                  :new_episodes # Record new interactions
                else
                  :once # Record if cassette doesn't exist, otherwise use existing
                end

  # Default cassette options
  config.default_cassette_options = {
    record: record_mode,
    match_requests_on: %i[method uri body],
    allow_playback_repeats: true
  }

  # Key setting: Allow HTTP connections only when no cassette exists
  # In CI: false (use cassettes only), In development: true (allow recording)
  config.allow_http_connections_when_no_cassette = !ci_environment?

  # Configure request matching
  config.configure_rspec_metadata!
end

# Configure WebMock to work with VCR
# VCR will handle enabling/disabling connections based on cassette presence
WebMock.disable_net_connect!(allow_localhost: true)

# Helper method for VCR tests
def with_vcr(cassette_name, **options, &block)
  VCR.use_cassette(cassette_name, options, &block)
end
