# frozen_string_literal: true
require "tempfile"

module CucumberRunner
  module ScreenshotCapture
    module_function

    # Capture a single screenshot and return its bytes, or nil on any failure.
    # We deliberately rescue everything — history capture must never crash a test.
    def capture_per_step(session)
      tmp = Tempfile.new(["cucumber-runner-shot", ".png"])
      tmp.close
      session.save_screenshot(tmp.path, full: false)
      bytes = File.binread(tmp.path)
      bytes
    rescue StandardError => e
      warn "[cucumber_runner] screenshot capture failed: #{e.class}: #{e.message}"
      nil
    ensure
      tmp&.unlink
    end
  end
end
