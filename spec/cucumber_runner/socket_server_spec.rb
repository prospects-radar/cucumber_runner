# frozen_string_literal: true
require "spec_helper"
require "cucumber_runner/socket_server"
require "socket"
require "json"

RSpec.describe CucumberRunner::SocketServer do
  it "accepts a client and round-trips JSON lines" do
    server = described_class.new
    received = []
    server.on_event { |evt| received << evt }
    port = server.start

    client = TCPSocket.new("127.0.0.1", port)
    client.puts({ type: "hello", n: 1 }.to_json)
    sleep 0.05  # let event loop tick
    server.send_command({ type: "ack" })
    line = client.gets
    expect(JSON.parse(line)).to eq("type" => "ack")

    expect(received).to eq([{ "type" => "hello", "n" => 1 }])
  ensure
    client&.close
    server&.close
  end
end
