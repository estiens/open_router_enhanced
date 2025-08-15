# frozen_string_literal: true

require_relative "lib/open_router/version"

Gem::Specification.new do |spec|
  spec.name = "open_router_enhanced"
  spec.version = OpenRouter::VERSION
  spec.authors = ["Eric Stiens"]
  spec.email = ["opensource@ericstiens.dev"]

  spec.summary = "Enhanced Ruby library for OpenRouter API with tool calling, structured outputs, and intelligent model selection. Based on the original work by Obie Fernandez."
  spec.homepage = "https://github.com/estiens/open_router"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/estiens/open_router"
  spec.metadata["changelog_uri"] = "https://github.com/estiens/open_router/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z`.split("\x0").reject do |f|
      (File.expand_path(f) == __FILE__) || f.end_with?(".gem",
                                                       ".gemspec") || f.start_with?(*%w[bin/ test/ spec/ features/ .git
                                                                                        .circleci appveyor])
    end
  end

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 6.0"
  spec.add_dependency "dotenv", ">= 2"
  spec.add_dependency "faraday", ">= 1"
  spec.add_dependency "faraday-multipart", ">= 1"
  spec.add_dependency "json-schema", "~> 4.0"
end
