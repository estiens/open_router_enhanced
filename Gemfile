# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in open_router.gemspec
gemspec

gem "activesupport", ">= 6.0"
gem "json-schema"

group :development, :test do
  gem "dotenv", ">= 2"
  gem "pry", ">= 0.14"
  gem "vcr", "~> 6.2"
  gem "webmock", "~> 3.19"
end

group :development do
  gem "rake", "~> 13.0"
  gem "rspec", "~> 3.0"
  gem "rubocop", require: false
end
