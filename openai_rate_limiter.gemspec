# frozen_string_literal: true

require_relative "lib/openai_rate_limiter/version"

Gem::Specification.new do |spec|
  spec.name = "openai_rate_limiter"
  spec.version = OpenAIRateLimiter::VERSION
  spec.authors = ["Garen J. Torikian"]
  spec.email = ["gjtorikian@users.noreply.github.com"]

  spec.summary = "Automatically rate limits requests to the OpenAI API"
  spec.description = "This gem provides a simple way to rate limit requests to the OpenAI API, ensuring that you stay within your usage limits. It monitors token usage and request counts via the headers returned by the OpenAI API."
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3.0"

  github_root_uri = "https://github.com/gjtorikian/openai_rate_limiter"
  spec.homepage = "#{github_root_uri}/tree/v#{spec.version}"
  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{github_root_uri}/blob/v#{spec.version}/CHANGELOG.md",
    "bug_tracker_uri" => "#{github_root_uri}/issues",
    "documentation_uri" => "https://rubydoc.info/gems/#{spec.name}/#{spec.version}",
    "funding_uri" => "https://github.com/sponsors/gjtorikian",
    "rubygems_mfa_required" => "true",
  }

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(["git", "ls-files", "-z"], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?("bin/", "test/", "spec/", "features/", ".git", ".github", "appveyor", "Gemfile")
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
  spec.add_dependency("async", "~> 2.27")
  spec.add_dependency("zeitwerk", "~> 2")
end
