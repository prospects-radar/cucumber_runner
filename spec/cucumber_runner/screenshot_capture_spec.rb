require "spec_helper"
require "cucumber_runner/screenshot_capture"

RSpec.describe CucumberRunner::ScreenshotCapture do
  describe ".capture_per_step" do
    it "calls save_screenshot on the current Capybara session and returns JPEG bytes" do
      png_path = nil
      session = double("Capybara::Session")
      allow(session).to receive(:save_screenshot) do |path, **|
        png_path = path
        File.binwrite(path, "fake-png-bytes")
        path
      end

      bytes = described_class.capture_per_step(session)
      expect(bytes).not_to be_nil
      expect(File.exist?(png_path)).to be(false) # tempfile cleaned up
    end

    it "returns nil and swallows errors when there's no active session" do
      session = double("Capybara::Session")
      allow(session).to receive(:save_screenshot).and_raise(StandardError, "no driver")
      expect(described_class.capture_per_step(session)).to be_nil
    end
  end
end
