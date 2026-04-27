require "spec_helper"
require "cucumber_runner/screenshot_capture"

RSpec.describe CucumberRunner::ScreenshotCapture do
  describe ".capture_per_step" do
    let(:content_bytes) { "x" * 50_000 } # above BLANK_BYTE_THRESHOLD

    it "calls save_screenshot on the current Capybara session and returns the bytes" do
      png_path = nil
      session = double("Capybara::Session")
      allow(session).to receive(:save_screenshot) do |path, **|
        png_path = path
        File.binwrite(path, content_bytes)
        path
      end

      bytes = described_class.capture_per_step(session)
      expect(bytes).to eq(content_bytes)
      expect(File.exist?(png_path)).to be(false) # tempfile cleaned up
    end

    it "returns nil and swallows errors when there's no active session" do
      session = double("Capybara::Session")
      allow(session).to receive(:save_screenshot).and_raise(StandardError, "no driver")
      expect(described_class.capture_per_step(session)).to be_nil
    end

    it "returns nil for a blank screenshot below the size threshold" do
      session = double("Capybara::Session")
      allow(session).to receive(:save_screenshot) do |path, **|
        File.binwrite(path, "x" * 16_000) # smaller than BLANK_BYTE_THRESHOLD
        path
      end
      expect(described_class.capture_per_step(session)).to be_nil
    end
  end

  describe ".blank?" do
    it "returns true for bytes shorter than BLANK_BYTE_THRESHOLD" do
      expect(described_class.blank?("x" * (described_class::BLANK_BYTE_THRESHOLD - 1))).to be(true)
    end

    it "returns false for bytes at or above BLANK_BYTE_THRESHOLD" do
      expect(described_class.blank?("x" * described_class::BLANK_BYTE_THRESHOLD)).to be(false)
    end

    it "returns false for non-string input" do
      expect(described_class.blank?(nil)).to be(false)
    end
  end
end
