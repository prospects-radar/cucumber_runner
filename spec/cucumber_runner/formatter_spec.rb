# frozen_string_literal: true
require "spec_helper"
require "cucumber_runner/formatter"
require "stringio"
require "json"

RSpec.describe CucumberRunner::Formatter do
  let(:fake_socket) { StringIO.new }

  before do
    CucumberRunner::Formatter.instance_variable_set(:@process_initialized, false)
    allow(TCPSocket).to receive(:new).and_return(fake_socket)
    ENV["CUCUMBER_RUNNER_PORT"] = "12345"
  end

  it "sends run-started on test_run_started" do
    config = double("config", on_event: nil)
    expect(config).to receive(:on_event).with(:test_run_started).and_yield(double(timestamp: nil))
    expect(config).to receive(:on_event).at_least(:once)
    described_class.new(config)
    fake_socket.rewind
    line = fake_socket.gets
    expect(JSON.parse(line)).to include("type" => "run-started")
  end

  it "skips initialization when a Formatter has already initialized in this process" do
    # First instantiation claims the process
    described_class.new(double("config", on_event: nil))
    # Second instantiation must NOT open another socket or register callbacks
    second_config = double("config")
    expect(second_config).not_to receive(:on_event)
    expect(TCPSocket).not_to receive(:new)
    described_class.new(second_config)
  end
end

RSpec.describe CucumberRunner::Formatter, "record-only mode (no socket)" do
  let(:fake_config) do
    Class.new do
      def initialize; @callbacks = {}; end
      def on_event(name, &block); @callbacks[name] = block; end
      def fire(name, event); @callbacks[name].call(event); end
    end.new
  end
  let(:recorder) { instance_double(CucumberRunner::HistoryRecorder, scenario_started: nil, step_finished: nil, scenario_finished: nil, flush_in_flight!: nil) }

  before do
    # Reset class-level state so instance_doubles don't leak between examples
    CucumberRunner::Formatter.instance_variable_set(:@recorders, [])
    CucumberRunner::Formatter.instance_variable_set(:@at_exit_installed, false)
    CucumberRunner::Formatter.instance_variable_set(:@process_initialized, false)
    ENV.delete("CUCUMBER_RUNNER_PORT")
    ENV["CUCUMBER_RUNNER_HISTORY_URL"]    = "https://history.example"
    ENV["CUCUMBER_RUNNER_PROJECT_ID"]     = "proj-a"
    ENV["CUCUMBER_RUNNER_API_TOKEN"]      = "tok"
    ENV["CUCUMBER_RUNNER_HISTORY"]        = "always"
    allow(CucumberRunner::HistoryRecorder).to receive(:new).and_return(recorder)
  end

  after do
    %w[CUCUMBER_RUNNER_HISTORY_URL CUCUMBER_RUNNER_PROJECT_ID CUCUMBER_RUNNER_API_TOKEN CUCUMBER_RUNNER_HISTORY].each { |k| ENV.delete(k) }
    CucumberRunner::Formatter.instance_variable_set(:@recorders, [])
    CucumberRunner::Formatter.instance_variable_set(:@at_exit_installed, false)
    CucumberRunner::Formatter.instance_variable_set(:@process_initialized, false)
  end

  it "constructs a recorder and skips the TCP socket" do
    expect(TCPSocket).not_to receive(:new)
    described_class.new(fake_config)
  end

  it "registers an at_exit hook that calls flush_in_flight! on the recorder" do
    described_class.new(fake_config)
    # Simulate at_exit by invoking the captured proc directly through the formatter API.
    # Implementation should expose this through a private method we invoke here.
    expect(recorder).to receive(:flush_in_flight!)
    CucumberRunner::Formatter.flush_recorders!
  end
end

RSpec.describe CucumberRunner::Formatter, "history-disabled" do
  let(:fake_config) { Class.new { def on_event(*); end }.new }

  before { CucumberRunner::Formatter.instance_variable_set(:@process_initialized, false) }

  it "is a no-op when CUCUMBER_RUNNER_HISTORY=never AND no port is set" do
    ENV.delete("CUCUMBER_RUNNER_PORT")
    ENV["CUCUMBER_RUNNER_HISTORY"] = "never"
    expect(TCPSocket).not_to receive(:new)
    expect(CucumberRunner::HistoryRecorder).not_to receive(:new)
    described_class.new(fake_config)
    ENV.delete("CUCUMBER_RUNNER_HISTORY")
  end

  it "registers no event callbacks when API keys are absent and no port is set" do
    %w[CUCUMBER_RUNNER_PORT CUCUMBER_RUNNER_HISTORY_URL CUCUMBER_RUNNER_PROJECT_ID CUCUMBER_RUNNER_API_TOKEN CUCUMBER_RUNNER_HISTORY].each { |k| ENV.delete(k) }
    config = double("config")
    expect(config).not_to receive(:on_event)
    described_class.new(config)
  end
end
