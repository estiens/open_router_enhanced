## [Unreleased]

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
