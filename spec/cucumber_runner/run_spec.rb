require "spec_helper"
require "cucumber_runner/run"

RSpec.describe CucumberRunner::Run do
  it "starts in :starting status" do
    run = described_class.new(run_id: "r1", scenario_id: "s1")
    expect(run.status).to eq(:starting)
    expect(run.run_id).to eq("r1")
  end

  it "tracks breakpoints by step index" do
    run = described_class.new(run_id: "r1", scenario_id: "s1")
    run.toggle_breakpoint(2)
    expect(run.breakpoint?(2)).to be true
    run.toggle_breakpoint(2)
    expect(run.breakpoint?(2)).to be false
  end

  it "marks paused/running" do
    run = described_class.new(run_id: "r1", scenario_id: "s1")
    run.status = :paused
    expect(run.paused?).to be true
  end
end
