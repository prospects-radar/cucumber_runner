# frozen_string_literal: true
require "json"
require "securerandom"
require "cucumber_runner/history_client"
require "cucumber_runner/multipart_body"
require "cucumber_runner/run_metadata"
require "cucumber_runner/screenshot_capture"

module CucumberRunner
  class HistoryRecorder
    attr_reader :current_run_id

    def initialize(project_id:, client:, metadata:, session_provider:)
      @project_id        = project_id
      @client            = client
      @metadata          = metadata
      @session_provider  = session_provider
      @namespace         = "cucumber"
      @run_started_at    = nil
      @events            = []      # array of { sequence:, event_type:, ts_ms:, payload:, artifact_bytes: }
      @summary           = {}
      @current_run_id    = nil
      @scenario_name     = nil
    end

    def scenario_started(feature_path:, line:, name:, tags:)
      @current_run_id  = uuid7
      @run_started_at  = ms_now
      @scenario_name   = name
      @summary = {
        feature_path: feature_path,
        line: line,
        scenario_name: name,
        tags: tags,
        step_count: 0,
        screenshot_mode: @metadata.record_mode.to_s,
      }
      @events.clear
    end

    def step_finished(index:, gherkin:, status:, duration_ms:, error:)
      payload = { step_index: index, gherkin: gherkin, status: status.to_s, duration_ms: duration_ms }
      payload[:error] = error if error
      bytes = capture_screenshot
      @events << {
        sequence: index,
        event_type: "step_finished",
        ts_ms: ms_now,
        payload: payload,
        artifact_bytes: bytes,
      }
      @summary[:step_count] = [@summary[:step_count].to_i, index].max
    end

    def scenario_finished(status:)
      return unless @current_run_id
      flush(status: status.to_s)
    end

    # Called from at_exit / on hard abort
    def flush_in_flight!
      return unless @current_run_id
      flush(status: "aborted")
    end

    private

    def flush(status:)
      finished_at = ms_now
      duration = finished_at - @run_started_at
      run_row = {
        id: @current_run_id,
        project_id: @project_id,
        namespace: @namespace,
        source: @metadata.source,
        status: status,
        title: @scenario_name.to_s,
        summary_json: @summary.to_json,
        branch: @metadata.branch,
        commit_sha: @metadata.commit_sha,
        pr_number: @metadata.pr_number,
        ci_run_id: @metadata.ci_run_id,
        host: @metadata.host,
        actor: @metadata.actor,
        started_at: @run_started_at,
        finished_at: finished_at,
        duration_ms: duration,
      }

      events_payload = @events.map do |ev|
        item = {
          sequence: ev[:sequence],
          event_type: ev[:event_type],
          ts_ms: ev[:ts_ms],
          payload_json: ev[:payload].to_json,
        }
        if ev[:artifact_bytes]
          item[:artifact_filename] = "#{ev[:sequence].to_s.rjust(4, "0")}.jpg"
          item[:artifact_mime] = "image/jpeg"
        end
        item
      end

      reset_state = lambda do
        @current_run_id = nil
        @events.clear
        @run_started_at = nil
        @summary = {}
      end

      unless @metadata.should_upload?(status.to_sym)
        reset_state.call
        return
      end

      mp = MultipartBody.new
      mp.add_text("metadata", { run: run_row, events: events_payload }.to_json)
      @events.each do |ev|
        next unless ev[:artifact_bytes]
        mp.add_binary("artifact_#{ev[:sequence]}", ev[:artifact_bytes],
                      filename: "#{ev[:sequence].to_s.rjust(4, "0")}.jpg",
                      content_type: "image/jpeg")
      end
      body, content_type = mp.finalize

      @client.post_run(body, content_type)
      reset_state.call
    end

    def capture_screenshot
      session = @session_provider.call
      return nil unless session
      ScreenshotCapture.capture_per_step(session)
    end

    def ms_now
      (Time.now.to_f * 1000).to_i
    end

    # UUIDv7 — same algorithm as the Worker side, ensuring run_ids are
    # time-sortable and consistent in shape.
    def uuid7
      ms = Time.now.to_f * 1000
      bytes = Array.new(16) { rand(256) }
      bytes[0] = (ms.to_i >> 40) & 0xff
      bytes[1] = (ms.to_i >> 32) & 0xff
      bytes[2] = (ms.to_i >> 24) & 0xff
      bytes[3] = (ms.to_i >> 16) & 0xff
      bytes[4] = (ms.to_i >> 8)  & 0xff
      bytes[5] = ms.to_i         & 0xff
      bytes[6] = (bytes[6] & 0x0f) | 0x70
      bytes[8] = (bytes[8] & 0x3f) | 0x80
      hex = bytes.map { |b| b.to_s(16).rjust(2, "0") }.join
      "#{hex[0,8]}-#{hex[8,4]}-#{hex[12,4]}-#{hex[16,4]}-#{hex[20,12]}"
    end
  end
end
