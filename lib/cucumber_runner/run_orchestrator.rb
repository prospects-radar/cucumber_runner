# frozen_string_literal: true
require "securerandom"
require "tmpdir"
require "fileutils"
require "cucumber_runner/run"
require "cucumber_runner/socket_server"

module CucumberRunner
  class RunOrchestrator
    class AlreadyRunning < StandardError; end

    def self.instance
      @instance ||= new
    end

    def initialize(socket_factory: -> { SocketServer.new }, spawner: nil)
      @socket_factory = socket_factory
      @spawner = spawner || method(:spawn_cucumber)
      @subscribers = {}
      @lock = Mutex.new
    end

    attr_reader :active_run

    def start(scenario:, breakpoints:, owner_user_id: nil, step_delay_ms: 1000)
      @lock.synchronize do
        cleanup_dead_active_run!
        raise AlreadyRunning if @active_run
        run_id = SecureRandom.hex(8)
        run = Run.new(run_id: run_id, scenario_id: scenario[:id])
        run.instance_variable_set(:@owner_user_id, owner_user_id)
        run.steps = scenario[:steps]
        run.step_delay_ms = step_delay_ms.to_i.clamp(0, 10_000)
        breakpoints.each { |i| run.toggle_breakpoint(i.to_i) }

        socket = @socket_factory.call
        socket.on_event { |evt| handle_event(run, evt) }
        port = socket.start

        pid = @spawner.call(scenario, port)
        run.pid = pid
        @active_run = run
        @socket = socket

        pid_dir = File.join(Dir.tmpdir, "cucumber_runner")
        FileUtils.mkdir_p(pid_dir)
        File.write(File.join(pid_dir, "#{run_id}.pid"), pid.to_s)

        run_id
      end
    end

    def stop(run_id)
      @lock.synchronize do
        return unless @active_run && @active_run.run_id == run_id
        @socket.send_command(type: "abort")
        Process.kill("TERM", @active_run.pid) rescue nil
        @socket.close
        @active_run.status = :aborted
        broadcast(@active_run, type: "finished", status: "aborted")
        @active_run = nil
        delete_pid_file(run_id)
      end
    end

    def stop_all_silently
      Dir.glob(File.join(Dir.tmpdir, "cucumber_runner", "*.pid")).each do |path|
        pid = File.read(path).to_i
        Process.kill("KILL", pid) rescue nil
        File.delete(path) rescue nil
      end
    end

    def subscribe(run_id, &block)
      (@subscribers[run_id] ||= []) << block
    end

    def command(run_id, action)
      @lock.synchronize do
        return unless @active_run && @active_run.run_id == run_id
        case action
        when "continue", "step", "stop", "pause_at_next"
          @active_run.pause_at_next = true if action == "pause_at_next"
          payload = case action
                    when "stop" then { type: "abort" }
                    else { type: action }
                    end
          @socket.send_command(payload) unless action == "pause_at_next"
          @active_run.status = :running unless action == "stop"
          broadcast(@active_run, type: "resumed") if %w[continue step].include?(action)
        when "toggle_breakpoint"
          # handled separately via toggle_breakpoint method below
        end
      end
    end

    def toggle_breakpoint(run_id, idx)
      @lock.synchronize do
        return unless @active_run && @active_run.run_id == run_id
        @active_run.toggle_breakpoint(idx)
      end
    end

    def set_step_delay(run_id, ms)
      @lock.synchronize do
        return unless @active_run && @active_run.run_id == run_id
        @active_run.step_delay_ms = ms.to_i.clamp(0, 10_000)
      end
    end

    private

    def handle_event(run, evt)
      type = evt["type"]
      summary = type == "frame" ? "frame(#{evt["png_base64"].to_s.bytesize}B)" : evt.inspect[0, 200]
      Rails.logger.info("[cucumber_runner] orch RECV #{summary}") if defined?(Rails)
      @lock.synchronize do
        case type
        when "step-about-to-start" then handle_step_about_to_start(run, evt)
        when "step-started"        then run.current_index = evt["step_index"]; run.status = :running; broadcast(run, type: "step_running", index: evt["step_index"])
        when "step-finished"       then broadcast(run, type: "step_done", index: evt["step_index"], status: evt["status"], error: evt["error"])
        when "setup-progress"      then broadcast(run, type: "setup_progress", count: evt["count"])
        when "frame"               then run.last_frame = evt["png_base64"]; broadcast(run, type: "frame", png_base64: evt["png_base64"], w: evt["w"], h: evt["h"], ts: evt["ts"])
        when "run-finished"        then run.status = evt["status"].to_sym; broadcast(run, type: "finished", status: evt["status"]); @active_run = nil; @socket.close; delete_pid_file(run.run_id)
        end
      end
    rescue => e
      Rails.logger.error("[cucumber_runner] orch handle_event ERROR: #{e.class}: #{e.message}\n#{e.backtrace.first(8).join("\n")}") if defined?(Rails)
      raise
    end

    def handle_step_about_to_start(run, evt)
      idx = evt["step_index"]
      if run.breakpoint?(idx) || run.pause_at_next
        run.pause_at_next = false
        run.status = :paused
        Rails.logger.info("[cucumber_runner] orch idx=#{idx} PAUSED") if defined?(Rails)
        broadcast(run, type: "paused", reason: run.breakpoint?(idx) ? "breakpoint" : "pause_now", at_index: idx)
        # do not send proceed; wait for command
      else
        delay_ms = idx.to_i.zero? ? 0 : run.step_delay_ms.to_i
        if delay_ms > 0
          Rails.logger.info("[cucumber_runner] orch idx=#{idx} scheduling proceed after #{delay_ms}ms") if defined?(Rails)
          Thread.new do
            begin
              sleep(delay_ms / 1000.0)
              if @socket
                Rails.logger.info("[cucumber_runner] orch idx=#{idx} sending proceed (after delay)") if defined?(Rails)
                @socket.send_command(type: "proceed")
              else
                Rails.logger.warn("[cucumber_runner] orch idx=#{idx} no socket when sending proceed") if defined?(Rails)
              end
            rescue => e
              Rails.logger.error("[cucumber_runner] orch proceed-scheduler FAIL idx=#{idx}: #{e.class}: #{e.message}") if defined?(Rails)
            end
          end
        else
          Rails.logger.info("[cucumber_runner] orch idx=#{idx} sending proceed (no delay)") if defined?(Rails)
          @socket.send_command(type: "proceed")
        end
      end
    end

    def delete_pid_file(run_id)
      path = File.join(Dir.tmpdir, "cucumber_runner", "#{run_id}.pid")
      File.delete(path) if File.exist?(path)
    rescue
      nil
    end

    # If the previous active run's subprocess has died (crashed or exited
    # without sending run-finished), clear our state so a new run can start.
    # Uses Process.waitpid2(WNOHANG) so zombies are reaped and reported
    # as exited (Process.kill(0, pid) reports zombies as alive on macOS).
    # Caller must hold @lock.
    def cleanup_dead_active_run!
      return unless @active_run
      pid = @active_run.pid
      return if pid && process_alive?(pid)
      Rails.logger.info("[cucumber_runner] cleaning up dead active_run pid=#{pid.inspect}") if defined?(Rails)
      @socket&.close rescue nil
      delete_pid_file(@active_run.run_id)
      @active_run = nil
    end

    # True if pid refers to a still-running, not-yet-reaped child process we own.
    # Also reaps the child if it has exited (so zombies don't accumulate).
    def process_alive?(pid)
      return false unless pid
      result = Process.waitpid2(pid, Process::WNOHANG)
      result.nil?  # nil => still running. [pid, status] => exited and just reaped.
    rescue Errno::ECHILD
      # Not our child, or already reaped, or never our child to begin with.
      false
    rescue Errno::ESRCH
      false
    end

    def broadcast(run, payload)
      (@subscribers[run.run_id] || []).each { |s| s.call(payload) }
    end

    def spawn_cucumber(scenario, port)
      formatter_path = File.expand_path("formatter.rb", __dir__)
      env = CucumberRunner.configuration.cucumber_env.merge("CUCUMBER_RUNNER_PORT" => port.to_s)
      cmd = CucumberRunner.configuration.cucumber_command + [
        "#{scenario[:path]}:#{scenario[:line]}",
        "-r", formatter_path,
        "-r", "features",
        "--format", "CucumberRunner::Formatter"
      ]

      # Redirect the subprocess's stdout+stderr to a known log file so the
      # diagnostic warnings emitted by Formatter and CdpScreencast survive
      # the bin/dev / Procfile multiplexing.
      log_dir = File.join(Dir.tmpdir, "cucumber_runner")
      FileUtils.mkdir_p(log_dir)
      log_path = File.join(log_dir, "last-run.log")
      Rails.logger.info("[cucumber_runner] spawning cucumber; output → #{log_path}") if defined?(Rails)
      Process.spawn(env, *cmd, pgroup: true, [:out, :err] => [log_path, "w"])
    end
  end
end
