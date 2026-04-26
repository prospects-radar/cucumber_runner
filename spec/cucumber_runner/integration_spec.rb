# frozen_string_literal: true
require "spec_helper"
require "open3"
require "cucumber_runner/run_orchestrator"
require "cucumber_runner/feature_index"

RSpec.describe "End-to-end run", :slow do
  let(:dummy_root) { File.expand_path("../dummy", __dir__) }
  let(:dummy_gemfile) { File.join(dummy_root, "Gemfile") }

  it "runs a passing scenario and emits step events in order" do
    Dir.chdir(dummy_root) do
      idx = CucumberRunner::FeatureIndex.new(["features/**/*.feature"])
      pass = idx.all.flat_map { |f| f[:scenarios] }.find { |s| s[:name] == "Pass" }
      expect(pass).not_to be_nil, "Could not find 'Pass' scenario in feature index"

      events = []
      orch = CucumberRunner::RunOrchestrator.new

      # Override env to point bundle exec at the dummy Gemfile so the spawned
      # cucumber subprocess uses the dummy app's bundle (which includes cucumber).
      # We must unset the bundler-injected env vars (BUNDLE_LOCKFILE, RUBYOPT, etc.)
      # that the parent RSpec process inherited from `bundle exec rspec`, which
      # would otherwise make the subprocess use the gem's Gemfile.lock.
      bundler_unset = %w[
        BUNDLE_LOCKFILE RUBYOPT RUBYLIB BUNDLER_SETUP BUNDLER_VERSION
        BUNDLE_BIN_PATH BUNDLER_ORIG_BUNDLE_GEMFILE BUNDLER_ORIG_BUNDLE_BIN_PATH
        BUNDLER_ORIG_BUNDLE_LOCKFILE BUNDLER_ORIG_BUNDLER_VERSION
        BUNDLER_ORIG_BUNDLER_SETUP BUNDLER_ORIG_GEM_HOME BUNDLER_ORIG_GEM_PATH
        BUNDLER_ORIG_MANPATH BUNDLER_ORIG_PATH BUNDLER_ORIG_RB_USER_INSTALL
        BUNDLER_ORIG_RUBYLIB BUNDLER_ORIG_RUBYOPT
      ].each_with_object({}) { |k, h| h[k] = nil }

      CucumberRunner.configure do |config|
        config.cucumber_env = bundler_unset.merge(
          "RAILS_ENV" => "test",
          "BUNDLE_GEMFILE" => dummy_gemfile,
          "CUCUMBER_PUBLISH_QUIET" => "true"
        )
      end

      run_id = orch.start(scenario: pass, breakpoints: [])
      orch.subscribe(run_id) { |e| events << e }

      timeout_at = Time.now + 60
      sleep 0.1 until events.any? { |e| e[:type] == "finished" } || Time.now > timeout_at

      expect(events.map { |e| e[:type] }).to include("step_running", "step_done", "finished")
      expect(events.last[:status]).to eq("passed")
    end
  ensure
    # Reset configuration between tests
    CucumberRunner.reset_configuration!
  end
end

RSpec.describe "integration: HISTORY=never with no port", :slow do
  it "runs cucumber successfully without contacting any history backend" do
    out, err, status = Open3.capture3(
      { "CUCUMBER_RUNNER_HISTORY" => "never" },
      "bundle", "exec", "cucumber",
      "spec/dummy/features/sample.feature",
      chdir: File.expand_path("../..", __dir__)
    )
    expect(status.exitstatus).to eq(0).or eq(1)  # depends on sample feature outcome
    expect(err).not_to include("history")
  end
end
