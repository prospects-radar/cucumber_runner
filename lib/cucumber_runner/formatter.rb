# frozen_string_literal: true
require "socket"
require "json"
require "cucumber_runner/cdp_screencast"
require "cucumber_runner/history_recorder"
require "cucumber_runner/history_client"
require "cucumber_runner/run_metadata"

module CucumberRunner
  class Formatter
    @recorders = []
    @at_exit_installed = false

    class << self
      def register_recorder(rec)
        @recorders << rec
        unless @at_exit_installed
          at_exit { Formatter.flush_recorders! }
          @at_exit_installed = true
        end
      end

      def flush_recorders!
        @recorders.each(&:flush_in_flight!)
        @recorders.clear
      end
    end

    def initialize(config)
      @history_mode  = (ENV["CUCUMBER_RUNNER_HISTORY"] || "auto").downcase
      @port          = ENV["CUCUMBER_RUNNER_PORT"]&.to_i
      @writer_lock   = Mutex.new
      @step_index    = 0
      @recorder      = nil

      install_history_recorder unless @history_mode == "never" && @port.nil?
      install_socket_bridge(config) if @port

      config.on_event(:test_run_started)   { |_| send_event("run-started") if @sock }
      config.on_event(:test_case_started)  { |event| handle_test_case_started(event) }
      config.on_event(:test_step_started)  do |event|
        @screencast&.maybe_start
        handle_step_started(event)
      end
      config.on_event(:test_step_finished) { |event| handle_step_finished(event) }
      config.on_event(:test_case_finished) { |event| handle_test_case_finished(event) }
      config.on_event(:test_run_finished)  { |event| handle_run_finished(event) }
    end

    private

    def install_history_recorder
      url   = ENV["CUCUMBER_RUNNER_HISTORY_URL"]
      proj  = ENV["CUCUMBER_RUNNER_PROJECT_ID"]
      token = ENV["CUCUMBER_RUNNER_API_TOKEN"]
      return if url.nil? || proj.nil? || token.nil?

      client   = HistoryClient.new(url: url, token: token)
      metadata = RunMetadata.new
      session_provider = -> { defined?(Capybara) && Capybara.respond_to?(:current_session) ? Capybara.current_session : nil }

      @recorder = HistoryRecorder.new(
        project_id: proj, client: client, metadata: metadata,
        session_provider: session_provider
      )
      Formatter.register_recorder(@recorder)
    end

    def install_socket_bridge(config)
      @sock = TCPSocket.new("127.0.0.1", @port)
      @sock.sync = true
      @screencast = CdpScreencast.new(
        socket_writer: ->(payload) { send_event_payload(payload) },
        fps: ENV.fetch("CUCUMBER_RUNNER_FPS", "5").to_i
      )
    end

    def handle_test_case_started(event)
      tc = event.test_case
      @visible_steps = tc.test_steps.reject { |s| hook_step?(s) }
      @step_index = -1
      @hook_count = 0
      @recorder&.scenario_started(
        feature_path: tc.location.file.to_s,
        line: tc.location.line,
        name: tc.name,
        tags: tc.tags.map(&:name)
      )
      send_event("test-case-started",
                 scenario_uri: tc.location.to_s,
                 scenario_name: tc.name,
                 steps: @visible_steps.map { |s| { text: step_text(s) } }) if @sock
    end

    def handle_step_started(event)
      step = event.test_step
      if hook_step?(step)
        @hook_count += 1
        send_event("setup-progress", count: @hook_count) if @sock
        return
      end
      @step_index += 1
      if @sock
        send_event("step-about-to-start", step_index: @step_index, gherkin: step_text(step))
        cmd = await_command
        raise Interrupt, "abort" if cmd["type"] == "abort"
        send_event("step-started", step_index: @step_index)
      end
    end

    def handle_step_finished(event)
      step = event.test_step
      return if hook_step?(step)
      result   = event.result
      duration = ((result.duration&.nanoseconds || 0) / 1_000_000.0).round(1)
      err      = error_message(result)

      send_event("step-finished",
                 step_index: @step_index, status: result.to_sym,
                 duration_ms: duration, error: err) if @sock

      @recorder&.step_finished(
        index: @step_index, gherkin: step_text(step),
        status: result.to_sym, duration_ms: duration, error: err
      )
    end

    def handle_test_case_finished(event)
      @screencast&.stop
      status = event.result.passed? ? :passed : :failed
      @recorder&.scenario_finished(status: status)
    end

    def handle_run_finished(event)
      send_event("run-finished", status: event.success ? :passed : :failed) if @sock
      @sock&.close
    end

    def await_command
      loop do
        line = @sock.gets
        return JSON.parse(line) if line && !line.strip.empty?
        raise IOError, "engine disconnected" if line.nil?
      end
    end

    HOOK_TEXT_PATTERN = /\A(Before|After|BeforeStep|AfterStep)( hook)?\z/i.freeze

    def hook_step?(step)
      return false unless step
      cname = step.class.name.to_s
      return true if cname.include?("HookStep") || cname.include?("HookTestStep")
      txt = step.respond_to?(:text) ? step.text.to_s.strip : ""
      return true if txt.empty?
      return true if HOOK_TEXT_PATTERN.match?(txt)
      if step.respond_to?(:location) && step.location
        loc_file = step.location.respond_to?(:file) ? step.location.file.to_s : step.location.to_s
        return false if loc_file.end_with?(".feature")
        return true  if loc_file.end_with?(".rb")
      end
      false
    end

    def step_text(step)
      step.respond_to?(:text) ? step.text : step.to_s
    end

    def error_message(result)
      return nil unless result.respond_to?(:exception) && result.exception
      "#{result.exception.message} (#{result.exception.class})"
    end

    def send_event(type, **payload)
      @writer_lock.synchronize { @sock.puts({ type: type, **payload }.to_json) }
    rescue IOError, Errno::EPIPE
    end

    def send_event_payload(payload)
      json = payload.to_json
      @writer_lock.synchronize { @sock.puts(json) }
    rescue IOError, Errno::EPIPE
    end
  end
end
