# frozen_string_literal: true
module CucumberRunner
  class RunChannel < ::ApplicationCable::Channel
    def subscribed
      @run_id = params[:run_id]
      active = orchestrator.active_run
      reason = subscribe_rejection_reason(active)
      if reason
        Rails.logger.warn("[cucumber_runner] RunChannel REJECT run_id=#{@run_id.inspect} reason=#{reason}")
        reject
        return
      end
      Rails.logger.info("[cucumber_runner] RunChannel subscribed run_id=#{@run_id} status=#{active.status}")
      orchestrator.subscribe(@run_id) do |payload|
        type = payload.is_a?(Hash) ? (payload[:type] || payload["type"]) : "?"
        Rails.logger.info("[cucumber_runner] RunChannel TRANSMIT type=#{type} run_id=#{@run_id}")
        transmit(payload)
      end
      # NOTE: braces are mandatory. ActionCable::Channel::Base#transmit's
      # signature is transmit(data, via: nil) — without an explicit hash
      # literal Ruby 4+ parses these key:val pairs as keyword arguments,
      # finds none of them match `via:`, and raises
      # `ArgumentError - wrong number of arguments (given 0, expected 1)`.
      transmit({ type: "started", steps: active.steps, current_index: active.current_index, status: active.status })
    end

    private

    def subscribe_rejection_reason(active)
      return "no current_user (ApplicationCable::Connection didn't authenticate)" unless current_user
      return "orchestrator has no active_run" unless active
      return "active_run.run_id=#{active.run_id} does not match params run_id=#{@run_id}" unless active.run_id == @run_id
      owner = active.instance_variable_get(:@owner_user_id)
      return "active_run.@owner_user_id=#{owner.inspect} does not match current_user.id=#{current_user.id.inspect}" unless current_user.id == owner
      nil
    end

    public

    # Each method below is an ActionCable channel "action" — the JS side
    # invokes them via subscription.perform("<action>", data).
    # ActionCable routes by data["action"] matching a public method name on
    # the channel; if the action key has no matching method, ActionCable
    # logs "Unable to process X#Y" and does NOT fall back to #receive.
    # That's why a single #receive(data) dispatching on data["action"]
    # silently swallowed every command.

    def continue_run(_data = {})
      orchestrator.command(@run_id, "continue")
    end

    def step_run(_data = {})
      orchestrator.command(@run_id, "step")
    end

    def stop_run(_data = {})
      orchestrator.command(@run_id, "stop")
    end

    def pause_at_next(_data = {})
      orchestrator.command(@run_id, "pause_at_next")
    end

    def toggle_breakpoint(data)
      orchestrator.toggle_breakpoint(@run_id, data["step_index"].to_i)
    end

    def set_step_delay(data)
      orchestrator.set_step_delay(@run_id, data["step_delay_ms"].to_i)
    end

    private

    def orchestrator
      CucumberRunner::RunOrchestrator.instance
    end
  end
end
