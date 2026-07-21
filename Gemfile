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

  # Database integration testing (optional).
  # Users add `sequel` to their own Gemfile; `pg` >= 1.3 is fiber-scheduler-aware.
  gem "base64"
  gem "sequel", "~> 5.0"
  gem "pg", "~> 1.3"
  gem "testcontainers-postgres", "~> 0.1"
end
