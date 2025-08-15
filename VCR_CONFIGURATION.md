# VCR Configuration

This document explains the VCR (Video Cassette Recorder) configuration for testing external API interactions.

## Configuration Overview

The VCR setup is configured in `spec/support/vcr.rb` with the following key features:

### Environment-Based Recording Modes

- **CI Environment** (`CI=true`, `GITHUB_ACTIONS=true`, or `CONTINUOUS_INTEGRATION=true`):
  - Recording mode: `:none` (never record, use existing cassettes only)
  - HTTP connections: Disabled (WebMock blocks all external requests)
  - API Key: Uses dummy key from environment variable

- **Development Environment**:
  - Recording mode: `:once` (record if cassette doesn't exist, otherwise use existing)
  - HTTP connections: Allowed when no cassette exists (enables recording)
  - API Key: Uses real API key from environment variable

### Override Options

- `VCR_RECORD_ALL=true`: Re-record all cassettes (development only)
- `VCR_RECORD_NEW=true`: Record new episodes only (development only)

### API Key Handling

- In CI: Uses dummy key `"dummy-api-key-for-testing-do-not-use"` set in GitHub Actions
- In development: Uses real API key from `OPENROUTER_API_KEY` environment variable
- All API keys are filtered from recordings for security

### Cassette Storage

Cassettes are stored in `spec/fixtures/vcr_cassettes/` and contain recorded HTTP interactions.

## Usage

### Running Tests with Different Modes

```bash
# Use existing cassettes (CI mode)
CI=true bundle exec rspec spec/vcr/

# Record new cassettes (development)
OPENROUTER_API_KEY=your-real-key bundle exec rspec spec/vcr/

# Re-record all cassettes
VCR_RECORD_ALL=true OPENROUTER_API_KEY=your-real-key bundle exec rspec spec/vcr/
```

### Test Tagging

Tests use `:vcr` metadata tag to enable VCR recording:

```ruby
RSpec.describe "API Tests", :vcr do
  it "makes API call", vcr: { cassette_name: "custom_name" } do
    # Test code that makes HTTP requests
  end
end
```

## Security

- All API keys are automatically filtered from cassette recordings
- Real API keys are never committed to the repository
- CI uses dummy keys that cannot access real services

## WebMock Integration

VCR hooks into WebMock to:
- Block external HTTP requests by default
- Allow requests only when VCR cassettes are recording
- Ensure tests are deterministic and don't depend on external services

This configuration ensures that:
1. Tests are fast and reliable (no external dependencies)
2. CI environments never make real API calls
3. Development can record new interactions when needed
4. Security is maintained through API key filtering