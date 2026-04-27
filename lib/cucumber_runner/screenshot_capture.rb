# frozen_string_literal: true
require "tempfile"

module CucumberRunner
  module ScreenshotCapture
    # Screenshots smaller than this are treated as blank (about:blank,
    # unrendered page). PNG compresses solid-colour images to a few KB
    # while real UI content lands at 50 KB+. Empirically blank frames
    # cluster at ~16 KB; real content starts at ~90 KB. 25 KB sits
    # safely in the gap.
    BLANK_BYTE_THRESHOLD = 25_000

    module_function

    # Capture a single screenshot and return its bytes, or nil on any failure.
    # Returns nil for visually-blank screenshots so the recorder doesn't
    # bother uploading them to R2 — this saves ~16 KB per skipped step
    # of bandwidth and storage.
    # We deliberately rescue everything — history capture must never crash a test.
    def capture_per_step(session)
      tmp = Tempfile.new(["cucumber-runner-shot", ".png"])
      tmp.close
      session.save_screenshot(tmp.path, full: false)
      bytes = File.binread(tmp.path)
      return nil if blank?(bytes)
      bytes
    rescue StandardError => e
      warn "[cucumber_runner] screenshot capture failed: #{e.class}: #{e.message}"
      nil
    ensure
      tmp&.unlink
    end

    # True when the captured PNG is small enough that it is almost
    # certainly a blank page. Cheap (no decoding), but the threshold
    # means a hypothetical legitimate page that compresses below 25 KB
    # would also be skipped — acceptable trade-off.
    def blank?(bytes)
      bytes.is_a?(String) && bytes.bytesize < BLANK_BYTE_THRESHOLD
    end
  end
end
