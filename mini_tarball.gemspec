# frozen_string_literal: true

require_relative "lib/mini_tarball/version"

Gem::Specification.new do |spec|
  spec.name          = "mini_tarball"
  spec.version       = MiniTarball::VERSION
  spec.authors       = ["Discourse"]

  spec.summary       = "A minimal implementation of the GNU Tar format."
  spec.homepage      = "https://github.com/discourse/mini_tarball"
  spec.license       = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 2.6.0")

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage

  spec.files = Dir["lib/**/*"] + %w(LICENSE.txt)
  spec.require_paths = ["lib"]

  spec.add_development_dependency "rake", "~> 13"
  spec.add_development_dependency "rspec"
  spec.add_development_dependency "rubocop-discourse"
  spec.add_development_dependency "rubocop-rake"
  spec.add_development_dependency "super_diff"
  spec.add_development_dependency "simplecov"
end
