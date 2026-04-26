# cucumber_runner

Mountable Rails engine for browsing, running, and watching Cucumber scenarios with breakpoints and a live test-browser screencast.

## Mount

```ruby
# Gemfile
cucumber_runner_local_path = "vendor/local_gems/cucumber_runner"
if File.directory?(cucumber_runner_local_path)
  gem "cucumber_runner", path: cucumber_runner_local_path, group: :development
else
  gem "cucumber_runner", github: "prospects-radar/cucumber_runner", branch: "main", group: :development
end
```

```ruby
# config/routes.rb
if Rails.env.development? && defined?(CucumberRunner::Engine)
  authenticate :user do
    mount CucumberRunner::Engine, at: "/cucumber-runner"
  end
end
```

## Configuration

```ruby
# config/initializers/cucumber_runner.rb (optional)
CucumberRunner.configure do |c|
  c.feature_globs    = ["features/**/*.feature"]
  c.cucumber_command = ["bundle", "exec", "cucumber"]
  c.cucumber_env     = { "RAILS_ENV" => "test" }
  c.screencast_fps   = 5
end
```

## Requirements

- Rails 7.1+ (8.x supported)
- Cucumber 10+ with messages-protocol formatter API
- `capybara-playwright-driver` and `playwright-ruby-client` for the screencast
- ActionCable configured (Async adapter is enough in dev)

## Architecture

See `docs/superpowers/specs/2026-04-26-cucumber-runner-engine-design.md` in the host repo.
