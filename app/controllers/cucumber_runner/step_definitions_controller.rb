# frozen_string_literal: true
module CucumberRunner
  class StepDefinitionsController < ApplicationController
    def lookup
      paths = CucumberRunner.configuration.step_defs_globs.flat_map { |g| Dir[Rails.root.join(g)] }
      index = CucumberRunner::StepDefIndex.new(paths)
      @match = index.match(params[:gherkin].to_s)
      @text  = params[:gherkin].to_s
    end
  end
end
