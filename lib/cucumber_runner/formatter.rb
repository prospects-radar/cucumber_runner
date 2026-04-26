# frozen_string_literal: true
require "socket"
require "json"
require "cucumber_runner/cdp_screencast"

module CucumberRunner
  class Formatter
    def initialize(config)
      @port = ENV.fetch("CUCUMBER_RUNNER_PORT").to_i
      @sock = TCPSocket.new("127.0.0.1", @port)
      @sock.sync = true
      @writer_lock = Mutex.new
      @step_index = 0
      @screencast = CdpScreencast.new(
        socket_writer: ->(payload) { send_event_payload(payload) },
        fps: ENV.fetch("CUCUMBER_RUNNER_FPS", "5").to_i
      )

      config.on_event(:test_run_started) { |_| send_event("run-started") }
      config.on_event(:test_case_started) { |event| handle_test_case_started(event) }
      config.on_event(:test_step_started) do |event|
        @screencast.maybe_start  # always try; browser may come alive during a hook
        handle_step_started(event)
      end
      config.on_event(:test_step_finished) { |event| handle_step_finished(event) }
      config.on_event(:test_case_finished) { |_| @screencast.stop }
      config.on_event(:test_run_finished) { |event| handle_run_finished(event) }
    end

    private

    def handle_test_case_started(event)
      tc = event.test_case
      # Cucumber 10's test_steps mixes hook test steps and Gherkin step refs.
      # The UI only shows Gherkin steps, so the formatter MUST report indices
      # in the visible-step space. Track only non-hook steps.
      @visible_steps = tc.test_steps.reject { |s| hook_step?(s) }
      @step_index = -1  # incremented before each visible step
      @hook_count = 0
      send_event("test-case-started",
                 scenario_uri: tc.location.to_s,
                 scenario_name: tc.name,
                 steps: @visible_steps.map { |s| { text: step_text(s) } })
    end

    def handle_step_started(event)
      step = event.test_step
      if hook_step?(step)
        @hook_count += 1
        warn "[cucumber_runner] formatter: hook ##{@hook_count} (skipping UI emit)"
        send_event("setup-progress", count: @hook_count)
        return
      end
      @step_index += 1
      warn "[cucumber_runner] formatter: handle_step_started idx=#{@step_index} text=#{step_text(step)[0, 60].inspect}"
      send_event("step-about-to-start", step_index: @step_index, gherkin: step_text(step))
      warn "[cucumber_runner] formatter: idx=#{@step_index} sent step-about-to-start, awaiting command"
      cmd = await_command  # blocks
      warn "[cucumber_runner] formatter: idx=#{@step_index} got command #{cmd.inspect}"
      raise Interrupt, "abort" if cmd["type"] == "abort"
      send_event("step-started", step_index: @step_index)
      warn "[cucumber_runner] formatter: idx=#{@step_index} sent step-started, body executing"
    end

    def await_command
      loop do
        line = @sock.gets
        return JSON.parse(line) if line && !line.strip.empty?
        raise IOError, "engine disconnected" if line.nil?
      end
    end

    def handle_step_finished(event)
      step = event.test_step
      return if hook_step?(step)  # hooks don't appear in the UI
      result = event.result
      warn "[cucumber_runner] formatter: handle_step_finished idx=#{@step_index} status=#{result.to_sym}"
      send_event("step-finished",
                 step_index: @step_index,
                 status: result.to_sym,
                 duration_ms: ((result.duration&.nanoseconds || 0) / 1_000_000.0).round(1),
                 error: error_message(result))
    end

    # True for cucumber's @Before/@After hook test_steps. They appear in
    # tc.test_steps but shouldn't surface in the UI's step list. Detection
    # uses multiple strategies because cucumber's API has churned across
    # versions.
    HOOK_TEXT_PATTERN = /\A(Before|After|BeforeStep|AfterStep)( hook)?\z/i.freeze

    def hook_step?(step)
      return false unless step
      cname = step.class.name.to_s
      return true if cname.include?("HookStep") || cname.include?("HookTestStep")
      txt = step.respond_to?(:text) ? step.text.to_s.strip : ""
      return true if txt.empty?
      return true if HOOK_TEXT_PATTERN.match?(txt)
      # Gherkin steps live in .feature files; hook bodies live in .rb files.
      if step.respond_to?(:location) && step.location
        loc_file = step.location.respond_to?(:file) ? step.location.file.to_s : step.location.to_s
        return false if loc_file.end_with?(".feature")
        return true  if loc_file.end_with?(".rb")
      end
      false
    end

    def handle_run_finished(event)
      warn "[cucumber_runner] formatter: handle_run_finished success=#{event.success}"
      send_event("run-finished",
                 status: event.success ? :passed : :failed)
      @sock.close
    end

    def step_text(step)
      step.respond_to?(:text) ? step.text : step.to_s
    end

    def error_message(result)
      return nil unless result.respond_to?(:exception) && result.exception
      "#{result.exception.message} (#{result.exception.class})"
    end

    def send_event(type, **payload)
      @writer_lock.synchronize do
        @sock.puts({ type: type, **payload }.to_json)
      end
    rescue IOError, Errno::EPIPE
    end

    def send_event_payload(payload)
      json = payload.to_json
      @writer_lock.synchronize do
        @sock.puts(json)
      end
    rescue IOError, Errno::EPIPE => e
      warn "[cucumber_runner] formatter: send_event_payload failed (#{e.class}); dropping #{payload[:type]} #{json&.bytesize}B"
    end
  end
end
