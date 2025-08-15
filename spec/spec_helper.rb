# frozen_string_literal: true

require "dotenv/load"
require "vcr"
require "webmock/rspec"
require "json-schema" # Enable schema validation in tests

# Load VCR configuration
require_relative "support/vcr"

require_relative "../lib/open_router"

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on Module and main
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end

  config.around(:each, &:run)

  # VCR is configured automatically via config.configure_rspec_metadata!
end
