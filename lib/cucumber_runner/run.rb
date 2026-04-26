# frozen_string_literal: true
module CucumberRunner
  class Run
    STATUSES = %i[starting running paused passed failed aborted].freeze

    attr_accessor :run_id, :scenario_id, :status, :pid, :steps,
                  :current_index, :last_frame, :pause_at_next, :error,
                  :step_delay_ms

    def initialize(run_id:, scenario_id:)
      @run_id = run_id
      @scenario_id = scenario_id
      @status = :starting
      @breakpoints = {}
      @steps = []
      @pause_at_next = false
      @step_delay_ms = 1000
    end

    def toggle_breakpoint(index)
      @breakpoints[index] = !@breakpoints[index]
    end

    def breakpoint?(index)
      !!@breakpoints[index]
    end

    def paused?
      @status == :paused
    end
  end
end
