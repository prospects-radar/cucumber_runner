# frozen_string_literal: true
require "spec_helper"
require "cucumber_runner/run_orchestrator"

RSpec.describe CucumberRunner::RunOrchestrator do
  let(:fake_socket) { instance_double(CucumberRunner::SocketServer, start: 12345, on_event: nil, send_command: nil, close: nil) }

  # Spawn a real long-sleeping child so process_alive?(pid) returns true.
  # Caller is responsible for killing + waiting it.
  def spawn_long_lived_child
    Process.spawn("sleep 30", out: File::NULL, err: File::NULL)
  end

  let(:long_pid) { @long_pid ||= spawn_long_lived_child }
  let(:orchestrator) { described_class.new(socket_factory: -> { fake_socket }, spawner: ->(*_) { long_pid }) }

  after do
    if @long_pid
      Process.kill("KILL", @long_pid) rescue nil
      Process.wait(@long_pid) rescue nil
    end
  end

  it "creates a run and stores it as active" do
    run_id = orchestrator.start(scenario: { id: "s1", path: "f.feature", line: 5, steps: [] }, breakpoints: [])
    expect(run_id).to be_a(String)
    expect(orchestrator.active_run.run_id).to eq(run_id)
    expect(orchestrator.active_run.pid).to eq(long_pid)
  end

  it "rejects a second concurrent run while the first is still alive" do
    orchestrator.start(scenario: { id: "s1", path: "f.feature", line: 5, steps: [] }, breakpoints: [])
    expect {
      orchestrator.start(scenario: { id: "s2", path: "g.feature", line: 5, steps: [] }, breakpoints: [])
    }.to raise_error(CucumberRunner::RunOrchestrator::AlreadyRunning)
  end

  it "auto-cleans a stuck active_run when its child has exited, so a new run can start" do
    # Spawn a child that exits immediately. It becomes a zombie (not yet
    # reaped) — exactly the state that fooled the old Process.kill(0, pid)
    # check on macOS. process_alive? must return false for it.
    dead_pid = Process.spawn("true", out: File::NULL, err: File::NULL)
    sleep 0.05  # give it time to exit
    dead_orch = described_class.new(socket_factory: -> { fake_socket }, spawner: ->(*_) { dead_pid })
    dead_orch.start(scenario: { id: "s1", path: "f.feature", line: 5, steps: [] }, breakpoints: [])
    expect {
      dead_orch.start(scenario: { id: "s2", path: "g.feature", line: 5, steps: [] }, breakpoints: [])
    }.not_to raise_error
  end
end

RSpec.describe CucumberRunner::RunOrchestrator, "breakpoints" do
  it "withholds proceed at a breakpointed step until commanded" do
    socket = instance_double(CucumberRunner::SocketServer, start: 12345, on_event: nil, send_command: nil, close: nil)
    orch = described_class.new(
      socket_factory: -> { socket },
      spawner: ->(*_) { 99 }
    )
    captured = nil
    allow(socket).to receive(:send_command) { |cmd| captured = cmd }

    run_id = orch.start(
      scenario: { id: "s", path: "f.feature", line: 5, steps: [{ keyword: "Given", text: "x" }, { keyword: "When", text: "y" }] },
      breakpoints: [1]
    )

    orch.send(:handle_event, orch.active_run, "type" => "step-about-to-start", "step_index" => 0)
    expect(captured).to eq(type: "proceed")

    captured = nil
    orch.send(:handle_event, orch.active_run, "type" => "step-about-to-start", "step_index" => 1)
    expect(captured).to be_nil
    expect(orch.active_run.status).to eq(:paused)

    orch.command(run_id, "continue")
    expect(captured).to eq(type: "continue")
  end
end
