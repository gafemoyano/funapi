# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development do
  gem "irb"
  gem "rake", "~> 13.0"
  gem "standard", "~> 1.3"
end

group :test do
  gem "minitest", "~> 5.16"

  # Database integration testing (optional)
  gem "base64"
  gem "db", "~> 0.14"
  gem "db-postgres", "~> 0.9"
  gem "testcontainers-postgres", "~> 0.1"
end
