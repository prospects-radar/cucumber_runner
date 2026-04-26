# frozen_string_literal: true

module CucumberRunner
  class RunsController < ApplicationController
    def create
      scenario = feature_index.find(params[:scenario_id])
      head :not_found and return unless scenario

      breakpoints = Array(params[:breakpoints]).map(&:to_i)
      step_delay_ms = (params[:step_delay_ms].presence || 1000).to_i
      run_id = CucumberRunner::RunOrchestrator.instance.start(
        scenario: scenario,
        breakpoints: breakpoints,
        owner_user_id: current_user&.id,
        step_delay_ms: step_delay_ms
      )
      redirect_to run_path(run_id)
    rescue CucumberRunner::RunOrchestrator::AlreadyRunning
      redirect_to root_path, alert: "Another run is already in progress."
    end

    def show
      @run_id = params[:id]
      run = CucumberRunner::RunOrchestrator.instance.active_run
      head :not_found and return unless run && run.run_id == @run_id
      @scenario = feature_index.find(run.scenario_id)
      @run = run
    end

    def destroy
      CucumberRunner::RunOrchestrator.instance.stop(params[:id])
      head :no_content
    end
  end
end
