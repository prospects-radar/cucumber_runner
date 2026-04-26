# frozen_string_literal: true
module CucumberRunner
  class ScenariosController < ApplicationController
    def show
      @scenario = feature_index.find(params[:id])
      head :not_found and return unless @scenario

      neighbors = feature_index.neighbors(@scenario[:id])
      @prev_scenario = neighbors[:prev]
      @next_scenario = neighbors[:next]
    end
  end
end
