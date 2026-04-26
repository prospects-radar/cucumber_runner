require_relative "lib/cucumber_runner/version"

Gem::Specification.new do |spec|
  spec.name    = "cucumber_runner"
  spec.version = CucumberRunner::VERSION
  spec.authors = ["Bert Hajee"]
  spec.email   = ["bert.hajee@enterprisemodules.com"]

  spec.summary     = "Interactive web UI to browse and execute cucumber scenarios with breakpoints and a live CDP screencast."
  spec.description = "A Rails engine providing a developer-only UI at /cucumber-runner for browsing scenarios, running them with breakpoints, and watching the test browser live."
  spec.license     = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir.glob("{app,config,lib}/**/*", File::FNM_DOTMATCH)
                  .reject { |path| File.directory?(path) }
                  .concat(%w[README.md cucumber_runner.gemspec])
                  .uniq
  spec.require_paths = ["lib"]

  spec.add_dependency "rails", ">= 7.1", "< 9.0"
  spec.add_dependency "cucumber", ">= 10", "< 12"
  spec.add_dependency "cucumber-messages", ">= 32", "< 34"

  spec.add_development_dependency "bundler", ">= 2.4", "< 5.0"
  spec.add_development_dependency "rake", ">= 13.0"
  spec.add_development_dependency "rspec", "~> 3.13"
end
