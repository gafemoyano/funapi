# frozen_string_literal: true

require_relative "lib/funapi/version"

Gem::Specification.new do |spec|
  spec.name = "funapi"
  spec.version = FunApi::VERSION
  spec.authors = ["Felipe Moyano"]
  spec.email = ["gafemoyano@gmail.com"]

  spec.summary = "Minimal async web framework for ruby inspired by FastAPI"
  spec.description = "Get an API started quickly, with performance in mind and, of course, have some fun with Ruby."
  spec.homepage = "https://github.com/gafemoyano/funapi"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ Gemfile .gitignore test/ .github/ .standard.yml])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "async", ">= 2.8"
  spec.add_dependency "dry-container", ">= 0.11"
  spec.add_dependency "dry-schema", ">= 1.13"
  spec.add_dependency "falcon", ">= 0.44"
  spec.add_dependency "rack", ">= 3.0.0", "< 4"
  spec.add_dependency "rack-cors", ">= 2.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
