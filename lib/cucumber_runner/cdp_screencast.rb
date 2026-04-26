# frozen_string_literal: true
require "base64"
require "thread"

module CucumberRunner
  class CdpScreencast
    # Maximum number of unsent frames buffered before we start dropping the
    # oldest. Higher = more frames preserved under back-pressure but more memory.
    QUEUE_CAPACITY = 4

    def initialize(socket_writer:, fps: 5, quality: 60)
      @socket_writer = socket_writer
      @fps = fps
      @quality = quality
      @cdp = nil
      @started = false
      # Queue + writer thread isolate the CDP/Playwright event-loop thread
      # from the socket I/O. Without this, a slow socket consumer
      # back-pressured all the way into Playwright and stalled navigation.
      @frame_queue = Queue.new
      @writer_thread = Thread.new { writer_loop }
      # Acks must NOT be sent synchronously from the screencast frame callback
      # — that callback runs on Playwright's dispatch thread, and the dispatch
      # thread is the only one that can deliver the ack response. Acking from
      # the callback deadlocked Page.goto on the very next CDP request. The
      # callback enqueues sessionIds here; this thread owns the actual sends.
      @ack_queue = Queue.new
      @ack_thread = Thread.new { ack_loop }
    end

    # Called from formatter on :test_step_started.
    # Idempotent — does nothing if already started or if browser not yet alive.
    def maybe_start
      return if @started
      page = playwright_page_or_nil
      if page.nil?
        dump_driver_state_once
        warn "[cucumber_runner] screencast: playwright_page not available yet (will retry on next step)"
        return
      end
      warn "[cucumber_runner] screencast: starting CDP session on Playwright page=#{page.class}"
      @page = page
      @cdp = page.context.new_cdp_session(page)
      warn "[cucumber_runner] screencast: CDP session created"

      frames_seen = 0
      callback = lambda do |params|
        frames_seen += 1
        if frames_seen <= 5 || frames_seen % 20 == 0
          url = current_page_url
          warn "[cucumber_runner] screencast: frame ##{frames_seen} (#{params['data'].to_s.bytesize} bytes) url=#{url.inspect}"
        end
        # Save to disk on Playwright's thread is fast (just a binwrite); cap to 30 frames.
        save_frame_to_disk(params["data"], "frame-#{frames_seen}") if frames_seen <= 30

        # Hand off to the writer thread. Drop the OLDEST queued frame if
        # we're already at capacity — preserve responsiveness over completeness.
        enqueue_frame(
          type: "frame",
          png_base64: params["data"],
          w: params.dig("metadata", "deviceWidth"),
          h: params.dig("metadata", "deviceHeight"),
          ts: params.dig("metadata", "timestamp")
        )

        # Hand the ack off to the dedicated ack thread. Acking inline blocks
        # Playwright's dispatch thread on a response only that thread can
        # deliver — the deadlock that froze Page.goto on the first navigation.
        @ack_queue << params["sessionId"]
      end
      @cdp.on("Page.screencastFrame", callback)
      warn "[cucumber_runner] screencast: listener registered"

      # everyNthFrame: 1 means "send every frame the renderer paints". With
      # higher values the renderer must paint N frames before we get one,
      # so static pages produce nothing. Keep it at 1 and let the screencast
      # rate be capped by how often the page actually rerenders.
      @cdp.send_message(
        "Page.startScreencast",
        params: {
          format: "png",
          quality: @quality,
          maxWidth: 1280,
          everyNthFrame: 1
        }
      )
      warn "[cucumber_runner] screencast: Page.startScreencast sent (everyNthFrame=1, quality=#{@quality})"
      @started = true
    rescue => e
      warn "[cucumber_runner] screencast failed to start: #{e.class}: #{e.message}"
      warn e.backtrace.first(5).join("\n")
    end

    def stop
      return unless @started
      @cdp&.send_message("Page.stopScreencast")
      @started = false
      # Tell helper threads to drain & exit. nil is the sentinel.
      @frame_queue << nil
      @ack_queue   << nil
      @writer_thread&.join(2)
      @ack_thread&.join(2)
    rescue
      # ignore
    end

    private

    # Push a frame payload onto the queue. If the queue is at capacity, drop
    # the oldest pending frame so the new one can land — Playwright must not
    # be back-pressured.
    def enqueue_frame(payload)
      while @frame_queue.size >= QUEUE_CAPACITY
        @frame_queue.pop(true) rescue break  # non-blocking pop
      end
      @frame_queue << payload
    end

    # Drain queued frames on a dedicated thread. Each socket write is
    # off the Playwright/CDP thread.
    def writer_loop
      loop do
        payload = @frame_queue.pop  # blocks
        break if payload.nil?       # sentinel
        begin
          @socket_writer.call(payload)
        rescue => e
          warn "[cucumber_runner] screencast: writer_loop socket write FAILED: #{e.class}: #{e.message}"
        end
      end
    end

    # Drain queued ack sessionIds and send them to CDP off Playwright's
    # dispatch thread. Sending acks from the dispatch thread itself blocks
    # waiting for a response that only the dispatch thread can deliver.
    def ack_loop
      loop do
        session_id = @ack_queue.pop  # blocks
        break if session_id.nil?     # sentinel
        begin
          @cdp&.send_message("Page.screencastFrameAck", params: { sessionId: session_id })
        rescue => e
          warn "[cucumber_runner] screencast: ack_loop send FAILED: #{e.class}: #{e.message}"
        end
      end
    end

    private

    def current_page_url
      @page&.url
    rescue
      nil
    end

    def current_page_title
      @page&.title
    rescue
      nil
    end

    def save_frame_to_disk(base64_data, label = nil)
      require "base64"
      require "tmpdir"
      require "fileutils"
      dir = File.join(Dir.tmpdir, "cucumber_runner", "frames")
      FileUtils.mkdir_p(dir)
      stamp = Time.now.strftime("%H%M%S-%6N")
      basename = label ? "#{stamp}-#{label}.png" : "#{stamp}.png"
      path = File.join(dir, basename)
      File.binwrite(path, Base64.decode64(base64_data.to_s))
    rescue => e
      warn "[cucumber_runner] screencast: save_frame_to_disk failed: #{e.class}: #{e.message}"
    end

    # Returns the Playwright Page if Capybara's playwright driver has spawned the browser,
    # else nil. Tries multiple known accessor paths so we keep working across
    # capybara-playwright-driver versions.
    def playwright_page_or_nil
      return nil unless defined?(Capybara) && Capybara.current_session
      driver = Capybara.current_session.driver

      # 1) Public API: capybara-playwright-driver has historically exposed
      #    with_playwright_page { |page| ... } once the browser is alive.
      if driver.respond_to?(:with_playwright_page)
        page = nil
        begin
          driver.with_playwright_page { |p| page = p }
        rescue
          page = nil
        end
        return page if page
      end

      # 2) Spike-confirmed introspection chain: driver → @browser → @playwright_page
      browser = driver.instance_variable_get(:@browser)
      return nil unless browser
      page = browser.instance_variable_get(:@playwright_page)
      return page if page

      # 3) Some versions store the page on the driver directly.
      page = driver.instance_variable_get(:@playwright_page)
      return page if page

      nil
    rescue
      nil
    end

    # Logs the driver/browser internal structure once so we can identify the
    # right accessor when the introspection paths above all return nil.
    # Subsequent calls are no-ops.
    def dump_driver_state_once
      return if @dumped
      @dumped = true
      return unless defined?(Capybara) && Capybara.current_session

      driver = Capybara.current_session.driver
      warn "[cucumber_runner] dump: driver=#{driver.class}"
      warn "[cucumber_runner] dump: driver methods: #{(driver.public_methods - Object.public_methods).sort.first(40).join(', ')}"
      warn "[cucumber_runner] dump: driver ivars: #{driver.instance_variables.inspect}"
      browser = driver.instance_variable_get(:@browser)
      warn "[cucumber_runner] dump: @browser=#{browser.inspect[0, 200]}"
      if browser
        warn "[cucumber_runner] dump: @browser.class=#{browser.class}"
        warn "[cucumber_runner] dump: @browser ivars: #{browser.instance_variables.inspect}"
      end
    rescue => e
      warn "[cucumber_runner] dump failed: #{e.class}: #{e.message}"
    end
  end
end
