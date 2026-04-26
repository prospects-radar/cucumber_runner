# frozen_string_literal: true
require "spec_helper"
require "cucumber_runner/formatter"
require "stringio"
require "json"

RSpec.describe CucumberRunner::Formatter do
  let(:fake_socket) { StringIO.new }

  before do
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
end
