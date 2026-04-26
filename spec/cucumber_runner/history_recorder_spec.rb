require "spec_helper"
require "json"
require "cucumber_runner/history_recorder"

RSpec.describe CucumberRunner::HistoryRecorder do
  let(:client) { instance_double(CucumberRunner::HistoryClient, post_run: { "run_id" => "x" }) }
  let(:metadata) do
    instance_double(CucumberRunner::RunMetadata,
                    source: "terminal", branch: "main", commit_sha: "abc",
                    pr_number: nil, ci_run_id: nil, host: "laptop",
                    actor: "bert", record_mode: :per_step,
                    history_mode: "auto", should_upload?: true)
  end
  let(:recorder) do
    described_class.new(
      project_id: "proj-a",
      client: client,
      metadata: metadata,
      session_provider: -> { nil }, # no Capybara session by default
    )
  end

  it "starts a scenario and assigns a UUIDv7-shaped run_id" do
    recorder.scenario_started(feature_path: "f.feature", line: 1, name: "x", tags: ["@a"])
    expect(recorder.current_run_id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/)
  end

  it "buffers step events and flushes on scenario_finished" do
    recorder.scenario_started(feature_path: "f.feature", line: 1, name: "x", tags: [])
    recorder.step_finished(index: 1, gherkin: "Given x", status: :passed, duration_ms: 10, error: nil)
    recorder.step_finished(index: 2, gherkin: "Then y", status: :passed, duration_ms: 20, error: nil)
    recorder.scenario_finished(status: :passed)

    expect(client).to have_received(:post_run) do |body, _ct|
      meta_match = body.match(/"events":(\[.*?\])/m)
      expect(meta_match).not_to be_nil
    end
  end

  it "skips upload when metadata.should_upload? is false" do
    allow(metadata).to receive(:should_upload?).and_return(false)
    recorder.scenario_started(feature_path: "f.feature", line: 1, name: "x", tags: [])
    recorder.scenario_finished(status: :passed)
    expect(client).not_to have_received(:post_run)
  end

  it "captures a per-step screenshot when a session is available" do
    fake_session = double("session")
    allow(CucumberRunner::ScreenshotCapture).to receive(:capture_per_step).with(fake_session).and_return("\x00\x01")
    rec = described_class.new(
      project_id: "proj-a", client: client, metadata: metadata,
      session_provider: -> { fake_session }
    )
    rec.scenario_started(feature_path: "f.feature", line: 1, name: "x", tags: [])
    rec.step_finished(index: 1, gherkin: "Given x", status: :passed, duration_ms: 5, error: nil)
    rec.scenario_finished(status: :passed)

    expect(client).to have_received(:post_run) do |body, _ct|
      expect(body).to include("artifact_1")
    end
  end

  it "flushes with status=aborted on at_exit if scenario was in progress" do
    recorder.scenario_started(feature_path: "f.feature", line: 1, name: "x", tags: [])
    recorder.step_finished(index: 1, gherkin: "Given x", status: :passed, duration_ms: 5, error: nil)
    recorder.flush_in_flight!
    expect(client).to have_received(:post_run) do |body, _ct|
      expect(body).to include('"status":"aborted"')
    end
  end
end
