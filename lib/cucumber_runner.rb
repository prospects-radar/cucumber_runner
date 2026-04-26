# frozen_string_literal: true

require "cucumber_runner/version"
require "cucumber_runner/configuration"
require "cucumber_runner/feature_index"
require "cucumber_runner/step_def_index"
require "cucumber_runner/run_orchestrator"
require "cucumber_runner/engine" if defined?(Rails)

module CucumberRunner
  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield configuration
    end

    def reset_configuration!
      @configuration = nil
    end
  end
end
