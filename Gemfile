# frozen_string_literal: true

source "https://rubygems.org"

# Specify your gem's dependencies in bipolar_cache.gemspec
gemspec

gem "rake", "~> 13.0"

# minitest 6 needs Ruby >= 3.2; older Rubies resolve to the 5.x series
gem "minitest", ">= 5.16"

gem "rubocop", "~> 1.70"

gem "sequel", "~> 5.0"

# Allow the 1.x series for the Ruby 3.0 CI job.
gem "sqlite3", ">= 1.7", "< 3"
