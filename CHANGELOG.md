## [Unreleased]

## [1.2.0] - 2025-12-24

### Added
- **Responses API**: Full support for OpenRouter's Responses API Beta (`/api/v1/responses`)
  - Simple string or structured array input
  - Reasoning with configurable effort levels (`minimal`, `low`, `medium`, `high`)
  - `ResponsesResponse` wrapper with convenient accessors
- **Responses API Tool Calling**: Complete function calling support for Responses API
  - `ResponsesToolCall` and `ResponsesToolResult` classes
  - `execute_tool_calls` for easy tool execution with blocks
  - `build_follow_up_input` for multi-turn tool conversations
  - `tool_choice` parameter (`auto`, `required`, `none`)
  - Automatic format conversion from Chat Completions tool format
- **Shared Tool Call Infrastructure**: Extracted `ToolCallBase` and `ToolResultBase` modules
  - DRY shared behavior for argument parsing and execution
  - Consistent interface across Chat Completions and Responses APIs

### Documentation
- New `docs/responses_api.md` with comprehensive Responses API guide
- Tool calling examples with Tool DSL and hash formats

## [1.1.0] - 2025-12-24

### Added
- **Native Response Healing Plugin**: Automatic server-side JSON healing for structured outputs via OpenRouter's `response-healing` plugin (free, <1ms latency)
- **Plugins Parameter**: Support for OpenRouter plugins (`web-search`, `pdf-inputs`, `response-healing`) via new `plugins:` parameter
- **Prediction Parameter**: Latency optimization via `prediction:` parameter for predictable outputs
- **Auto Native Healing**: Automatically enables `response-healing` plugin when using structured outputs (configurable via `auto_native_healing` setting)

### Changed
- Enhanced structured output workflow: native healing catches syntax errors server-side, client-side healing handles schema validation

### Configuration
- New `auto_native_healing` config option (default: `true`)
- Environment variable: `OPENROUTER_AUTO_NATIVE_HEALING`

## [1.0.0] - 2025-10-07

### Major Features
- **Tool Calling**: Complete function calling support with DSL-based tool definitions and automatic validation
- **Structured Outputs**: Native and forced JSON schema support with automatic response healing
- **Model Selection**: Intelligent model selection with fluent DSL, capability detection, and cost optimization
- **Model Fallbacks**: Automatic failover routing with model arrays for reliability
- **Response Healing**: Self-correcting malformed JSON outputs from non-native structured output models
- **Streaming Client**: Real-time streaming with comprehensive callback system
- **Usage Tracking**: Token usage and cost analytics with detailed metrics
- **Prompt Templates**: Reusable templates with variable interpolation

### Enhanced
- **Model Registry**: Local caching with automatic capability detection and cost calculation
- **Response Object**: Rich metadata including tokens, costs, cache hits, and performance analytics
- **Error Handling**: Comprehensive error hierarchy with specific error types for better debugging
- **VCR Testing**: Complete real API integration testing coverage
- **Documentation**: Extensive guides, examples, and API reference

### Compatibility
- Full backward compatibility with original OpenRouter gem
- Ruby 3.0+ support
- Optional dependencies for enhanced features (json-schema for validation)

## [0.3.0] - 2024-05-03

### Changed
- Uses Faraday's built-in JSON mode
- Added support for configuring Faraday and its middleware
- Spec creates a STDOUT logger by default (headers, bodies, errors)  
- Spec filters Bearer token from logs by default

## [0.1.0] - 2024-03-19

### Added
- Initial release of OpenRouter Ruby gem
- Basic chat completion support
- Model selection and routing
- OpenRouter API integration
