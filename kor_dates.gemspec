# frozen_string_literal: true

require_relative "lib/kor_dates/version"

Gem::Specification.new do |spec|
  spec.name = "kor_dates"
  spec.version = KorDates::VERSION
  spec.authors = ["Daniel Dailey"]
  spec.email = ["daniel@danieldailey.com"]

  spec.summary = "Natural-language dates and date ranges for search boxes and filters"
  spec.description = "KorDates turns what people type into date filters (\"last month\", \"mtd\", \"since jan\", " \
                     "\"mon-fri\", \"past 2 weeks\", \"1/2/99\") into Dates and [from, to] ranges, anchored to Time.zone."
  spec.homepage = "https://github.com/dandailey/kor_dates"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  spec.files = Dir["lib/**/*.rb", "README.md", "LICENSE", "CHANGELOG.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "activesupport", ">= 7.0"
  spec.add_dependency "chronic", "~> 0.10"
end
