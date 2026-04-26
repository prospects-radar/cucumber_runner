# frozen_string_literal: true
require "spec_helper"
require "cucumber_runner/cdp_screencast"

RSpec.describe CucumberRunner::CdpScreencast do
  # Regression for the deadlock that hung `When I visit "..."` indefinitely.
  #
  # The original implementation spawned `Thread.new { @cdp.send_message(...) }`
  # in two places: a forced-screenshot inside `maybe_start`, and a per-step
  # `capture_now` invoked from the formatter. While `Page.startScreencast`
  # was active those threads piled up against playwright-ruby-client's
  # CDPSession lock — the same lock the dispatch thread needs to deliver
  # responses — so the next CDP-issuing call (Capybara's first real `visit`)
  # blocked forever on `Mutex#synchronize` -> `ConditionVariable#wait`.
  describe "thread-safety with active screencast" do
    it "does not expose capture_now (it was the deadlock source)" do
      expect(described_class.instance_methods(false)).not_to include(:capture_now)
    end

    it "does not call CDP send_message synchronously inside the screencast frame callback" do
      # The Page.screencastFrame callback runs on Playwright's dispatch
      # thread. That thread is the *only* thread that delivers responses
      # to CDP requests, so any synchronous send_message inside the
      # callback waits forever — and freezes every later CDP call (e.g.
      # Page.goto on the first `visit`).
      source = File.read(
        File.expand_path("../../lib/cucumber_runner/cdp_screencast.rb", __dir__),
        encoding: "UTF-8"
      )
      callback = source[/callback\s*=\s*lambda do \|params\|(.*?)^      end$/m, 1]
      expect(callback).not_to be_nil, "could not locate the screencast frame callback in source"
      expect(callback).not_to include("send_message"),
        "screencast frame callback must not call CDP send_message — it deadlocks Playwright's dispatch thread:\n#{callback}"
    end
  end
end
