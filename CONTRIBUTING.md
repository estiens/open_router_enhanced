# Contributing to OpenRouter Ruby Gem

Thank you for your interest in contributing to the OpenRouter Ruby gem! This document provides guidelines for contributing to the project.

## Table of Contents

- [Getting Started](#getting-started)
- [Development Setup](#development-setup)
- [Contributing Process](#contributing-process)
- [Code Standards](#code-standards)
- [Testing Guidelines](#testing-guidelines)
- [Documentation](#documentation)
- [Submitting Changes](#submitting-changes)
- [Release Process](#release-process)

## Getting Started

### Prerequisites

- Ruby 3.2.2 or higher
- Bundler
- Git
- OpenRouter API key (for VCR tests)

### Development Setup

1. **Fork and Clone**
   ```bash
   git clone https://github.com/YOUR_USERNAME/open_router.git
   cd open_router
   ```

2. **Install Dependencies**
   ```bash
   bundle install
   ```

3. **Set Environment Variables**
   ```bash
   export OPENROUTER_API_KEY="your_api_key_here"
   ```

4. **Run Tests**
   ```bash
   bundle exec rspec
   ```

5. **Interactive Console**
   ```bash
   bundle exec pry -I lib -r open_router
   ```

## Contributing Process

### 1. Choose an Issue

- Look for issues labeled `good first issue` for newcomers
- Check existing issues or create a new one for discussion
- Comment on the issue to indicate you're working on it

### 2. Create a Feature Branch

```bash
git checkout -b feature/your-feature-name
# or
git checkout -b fix/your-bug-fix
```

### 3. Follow Development Workflow

1. **Write Tests First** (TDD approach)
   - Unit tests for new functionality
   - VCR integration tests for API interactions
   - Edge case and error handling tests

2. **Implement Feature**
   - Follow existing code patterns
   - Add comprehensive error handling
   - Include documentation comments

3. **Update Documentation**
   - Update relevant docs/ files
   - Add examples to README if needed
   - Update CHANGELOG.md

4. **Test Thoroughly**
   ```bash
   bundle exec rspec
   bundle exec rubocop
   ```

## Code Standards

### Ruby Style

Follow the existing codebase patterns and RuboCop configuration:

```bash
# Check style
bundle exec rubocop

# Auto-fix issues
bundle exec rubocop -a
```

### Design Patterns

#### DSL Design
- Use descriptive method names
- Chain methods fluently
- Provide sensible defaults
- Include parameter validation

```ruby
# Good
tool = OpenRouter::Tool.define do
  name "search_api"
  description "Search external API for information"
  
  parameters do
    string :query, required: true, description: "Search query"
    integer :limit, minimum: 1, maximum: 100, default: 10
  end
end

# Bad
tool = OpenRouter::Tool.new(name: "search", params: { q: { type: "string" } })
```

#### Error Handling
- Use specific error classes
- Provide helpful error messages
- Include context in errors

```ruby
# Good
raise OpenRouter::ToolCallError, 
      "Tool '#{tool_name}' validation failed: #{validation_errors.join(', ')}"

# Bad
raise StandardError, "Invalid tool"
```

#### Backward Compatibility
- Ensure all changes are backward compatible
- Use feature flags for experimental features
- Deprecate features gradually with warnings

### Documentation

#### Code Comments
- Document complex algorithms
- Explain non-obvious business logic
- Include examples for public methods

```ruby
# Calculates the estimated cost for a completion request.
# Takes into account both input and output token costs.
#
# @param model [String] The model identifier
# @param input_tokens [Integer] Number of input tokens
# @param output_tokens [Integer] Number of output tokens
# @return [Float] Estimated cost in USD
def calculate_estimated_cost(model, input_tokens:, output_tokens:)
  # Implementation...
end
```

#### Markdown Documentation
- Use clear headings and structure
- Include practical examples
- Provide troubleshooting sections
- Link between related documentation

## Testing Guidelines

### Test Organization

```
spec/
├── unit/                    # Fast unit tests
│   ├── tool_spec.rb
│   ├── schema_spec.rb
│   └── model_selector_spec.rb
├── integration/             # Cross-module integration tests
│   └── client_integration_spec.rb
├── vcr/                     # Real API interaction tests
│   ├── tool_calling_spec.rb
│   ├── structured_outputs_spec.rb
│   └── model_registry_spec.rb
└── support/
    └── vcr.rb              # VCR configuration
```

### Test Writing Guidelines

#### Unit Tests
```ruby
# Good: Clear, focused test
RSpec.describe OpenRouter::Tool do
  describe "#to_json_schema" do
    it "generates valid JSON schema for simple parameters" do
      tool = described_class.define do
        name "test_tool"
        parameters do
          string :query, required: true
        end
      end
      
      schema = tool.to_json_schema
      expect(schema[:parameters][:required]).to include("query")
    end
  end
end
```

#### VCR Tests
```ruby
# Good: Real API interaction test
RSpec.describe "Tool Calling", :vcr do
  it "handles real tool calling workflow" do
    response = client.complete(
      messages,
      model: "anthropic/claude-3.5-sonnet",
      tools: [tool],
      tool_choice: "auto"
    )
    
    expect(response.has_tool_calls?).to be true
    expect(response.tool_calls.first.name).to eq("test_tool")
  end
end
```

### VCR Best Practices

1. **Use Descriptive Cassette Names**
   ```ruby
   it "handles complex tool parameters", vcr: { cassette_name: "tool_complex_parameters" } do
   ```

2. **Filter Sensitive Data**
   - API keys are automatically filtered
   - Add custom filters for other sensitive data

3. **Keep Cassettes Fresh**
   ```bash
   # Re-record all cassettes
   rm -rf spec/fixtures/vcr_cassettes/
   bundle exec rspec spec/vcr/
   ```

## Documentation

### Types of Documentation

1. **API Documentation** - In-code documentation for public methods
2. **User Guides** - Step-by-step tutorials in docs/
3. **Examples** - Working examples in examples/
4. **README** - Overview and quick start guide
5. **CHANGELOG** - Version history and breaking changes

### Documentation Standards

- **Clear Examples**: Always include working code examples
- **Complete Coverage**: Document all public APIs
- **Troubleshooting**: Include common issues and solutions
- **Links**: Cross-reference related documentation

## Submitting Changes

### Pull Request Process

1. **Ensure Quality**
   ```bash
   bundle exec rspec      # All tests pass
   bundle exec rubocop    # Style checks pass
   ```

2. **Update Documentation**
   - Add examples for new features
   - Update relevant docs/ files
   - Update CHANGELOG.md

3. **Create Pull Request**
   - Use descriptive title and description
   - Reference related issues
   - Include testing notes

4. **Pull Request Template**
   ```markdown
   ## Description
   Brief description of changes

   ## Type of Change
   - [ ] Bug fix
   - [ ] New feature
   - [ ] Breaking change
   - [ ] Documentation update

   ## Testing
   - [ ] Unit tests added/updated
   - [ ] VCR tests added/updated
   - [ ] Manual testing completed

   ## Checklist
   - [ ] Code follows style guidelines
   - [ ] Self-review completed
   - [ ] Documentation updated
   - [ ] CHANGELOG.md updated
   ```

### Code Review Guidelines

#### For Authors
- Respond to feedback promptly
- Ask questions if feedback is unclear
- Make requested changes or explain reasoning

#### For Reviewers
- Be constructive and specific
- Focus on code quality and maintainability
- Test the changes locally when possible

## Release Process

### Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes (backward compatible)

### Release Checklist

1. **Update Version**
   ```ruby
   # lib/open_router/version.rb
   VERSION = "0.4.0"
   ```

2. **Update CHANGELOG.md**
   - Move items from [Unreleased] to new version
   - Add release date
   - Create new [Unreleased] section

3. **Run Full Test Suite**
   ```bash
   bundle exec rspec
   bundle exec rspec spec/vcr/  # With fresh recordings
   ```

4. **Update Documentation**
   - Ensure README is current
   - Verify all examples work
   - Check link validity

5. **Create Release**
   ```bash
   git tag v0.4.0
   git push origin v0.4.0
   gem build open_router.gemspec
   gem push open_router-0.4.0.gem
   ```

## Getting Help

- **Questions**: Open a discussion or issue
- **Bugs**: Create an issue with reproduction steps
- **Features**: Discuss in an issue before implementing

## Code of Conduct

This project follows our [Code of Conduct](CODE_OF_CONDUCT.md). Please read and follow it in all interactions.

## Recognition

Contributors are recognized in:
- CHANGELOG.md for significant contributions
- GitHub contributors page
- Special thanks in release notes

Thank you for contributing to OpenRouterEnhanced Ruby gem! 🚀