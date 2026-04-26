# frozen_string_literal: true
require "socket"
require "json"

module CucumberRunner
  class SocketServer
    def initialize
      @server = nil
      @client = nil
      @on_event = nil
      @reader = nil
      @writer_lock = Mutex.new
    end

    def start
      @server = TCPServer.new("127.0.0.1", 0)
      port = @server.addr[1]
      Thread.new { accept_loop }
      port
    end

    def on_event(&block)
      @on_event = block
    end

    def send_command(payload)
      @writer_lock.synchronize do
        @client&.puts(payload.to_json)
      rescue IOError, Errno::EPIPE
        # client gone; ignore
      end
    end

    def close
      @reader&.kill
      @client&.close
      @server&.close
    rescue IOError
      # nothing
    end

    private

    def accept_loop
      @client = @server.accept
      @reader = Thread.new { read_loop(@client) }
    rescue IOError
      # server closed before connect — ignore
    end

    def read_loop(io)
      io.each_line do |line|
        line = line.strip
        next if line.empty?
        @on_event&.call(JSON.parse(line))
      end
    rescue IOError, Errno::ECONNRESET, JSON::ParserError
      # client closed or bad data
    end
  end
end
