// app/assets/javascripts/controllers/cucumber_runner_runtime_controller.js
import { Controller } from "@hotwired/stimulus"
import { createConsumer } from "@rails/actioncable"

export default class extends Controller {
  static targets = ["stepList", "canvas", "status", "error", "footer", "speed"]
  static values  = { runId: String }

  connect() {
    console.log(`[cucumber_runner] runtime controller connect() run_id=${this.runIdValue}`)
    this.statusTarget.textContent = "connecting to cable…"
    this._eventsReceived = 0
    try {
      this.consumer = createConsumer()
      console.log(`[cucumber_runner] cable consumer created, url=${this.consumer?.url || "(unknown)"}`)
    } catch (e) {
      this.surfaceError(`createConsumer threw: ${e.message}`)
      return
    }
    try {
      this.subscription = this.consumer.subscriptions.create(
        { channel: "CucumberRunner::RunChannel", run_id: this.runIdValue },
        {
          received:     (msg) => this.dispatch(msg),
          initialized:  ()    => { console.log("[cucumber_runner] cable subscription initialized") },
          connected:    ()    => {
            console.log("[cucumber_runner] cable connected")
            // Only display 'connected, awaiting events…' if we haven't already
            // received any events. Otherwise leave the status alone — the
            // 'connected' callback can fire AFTER 'received' due to async
            // ordering, which would visually clobber an already-running state.
            if (this._eventsReceived === 0) {
              this.statusTarget.textContent = "connected, awaiting events…"
            }
          },
          disconnected: ()    => {
            console.warn("[cucumber_runner] cable disconnected")
            this.statusTarget.textContent = "disconnected — refresh the page"
          },
          rejected:     ()    => {
            this.surfaceError("Cable subscription was rejected. Check log/development.log for [cucumber_runner] RunChannel REJECT lines.")
            this.statusTarget.textContent = "subscription rejected — see Rails log"
          }
        }
      )
      console.log("[cucumber_runner] subscriptions.create returned", this.subscription)
    } catch (e) {
      this.surfaceError(`subscriptions.create threw: ${e.message}`)
      return
    }
    this.ctx = this.canvasTarget.getContext("2d")
  }

  surfaceError(message) {
    console.error(`[cucumber_runner] ${message}`)
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message
      this.errorTarget.hidden = false
    }
  }

  disconnect() {
    this.subscription?.unsubscribe()
    this.consumer?.disconnect()
  }

  dispatch(msg) {
    this._eventsReceived = (this._eventsReceived || 0) + 1
    const summary = msg.type === "frame"
      ? `frame(${msg.png_base64 ? msg.png_base64.length : 0}b64chars)`
      : JSON.stringify(msg).slice(0, 200)
    console.log("[cucumber_runner] received", summary)
    switch (msg.type) {
      case "started":        this.onStarted(msg); break
      case "setup_progress": this.onSetupProgress(msg); break
      case "step_running":   this.onStepRunning(msg); break
      case "step_done":      this.onStepDone(msg); break
      case "paused":         this.onPaused(msg); break
      case "resumed":        this.onResumed(msg); break
      case "frame":          this.onFrame(msg); break
      case "finished":       this.onFinished(msg); break
      case "engine_error":   this.onEngineError(msg); break
      default: console.warn("[cucumber_runner] unhandled message type:", msg.type)
    }
  }

  onSetupProgress(msg) {
    const n = msg.count || 0
    this.statusTarget.textContent = `setting up scenario (${n} hook${n === 1 ? "" : "s"} done)…`
  }

  onStarted(_msg) {
    this.statusTarget.textContent = "running"
    // Push the dropdown's current selection so engine and UI agree on speed.
    if (this.hasSpeedTarget) this._sendSpeed(this.speedTarget.value)
  }
  onStepRunning(msg) {
    this.stepListTarget.querySelectorAll(".cr-step").forEach((el) => el.classList.remove("is-current"))
    const target = this.stepListTarget.querySelector(`[data-step-index="${msg.index}"]`)
    if (!target) {
      console.warn(`[cucumber_runner] step_running idx=${msg.index} — no DOM row found`)
      return
    }
    target.classList.add("is-current")
  }
  onStepDone(msg) {
    const el = this.stepListTarget.querySelector(`[data-step-index="${msg.index}"]`)
    if (!el) {
      console.warn(`[cucumber_runner] step_done idx=${msg.index} status=${msg.status} — no DOM row found`)
      return
    }
    el.classList.remove("is-current")
    if (msg.status === "passed") {
      el.classList.add("is-passed")
      console.log(`[cucumber_runner] marked idx=${msg.index} as passed`)
    } else if (msg.status === "failed") {
      el.classList.add("is-failed")
      if (msg.error) {
        this.errorTarget.textContent = msg.error
        this.errorTarget.hidden = false
      }
    } else if (msg.status === "skipped") {
      el.classList.add("is-skipped")
    }
  }
  onPaused(msg)          { this.statusTarget.textContent = `paused (${msg.reason})` }
  onResumed(_msg)        { this.statusTarget.textContent = "running" }
  onFinished(msg) {
    this.statusTarget.textContent = `done: ${msg.status}`
    this.footerTarget.hidden = false
  }
  onEngineError(msg)     { this.errorTarget.textContent = msg.message; this.errorTarget.hidden = false }

  onFrame(msg) {
    const img = new Image()
    img.onload = () => this.ctx.drawImage(img, 0, 0, this.canvasTarget.width, this.canvasTarget.height)
    img.src = `data:image/png;base64,${msg.png_base64}`
  }

  // ActionCable routes incoming messages by data["action"] -> matching
  // public method on the channel. perform(name, data) sets data.action=name
  // server-side and dispatches to def name(data). The channel defines
  // continue_run/step_run/stop_run/pause_at_next/toggle_breakpoint/set_step_delay.
  continue() { this.subscription.perform("continue_run") }
  step()     { this.subscription.perform("step_run") }
  stop()     { this.subscription.perform("stop_run") }
  pauseNow() { this.subscription.perform("pause_at_next") }

  toggleBreakpoint(event) {
    const idx = parseInt(event.currentTarget.dataset.stepIndex, 10)
    event.currentTarget.classList.toggle("has-bp")
    this.subscription.perform("toggle_breakpoint", { step_index: idx })
  }

  setSpeed(event) {
    this._sendSpeed(event.target.value)
  }

  _sendSpeed(value) {
    const ms = parseInt(value, 10) || 0
    this.subscription.perform("set_step_delay", { step_delay_ms: ms })
  }
}
