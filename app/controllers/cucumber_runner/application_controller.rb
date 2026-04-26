# frozen_string_literal: true
module CucumberRunner
  class ApplicationController < ::ApplicationController
    layout "cucumber_runner/layouts/cucumber_runner"

    before_action :guard_environment

    private

    def guard_environment
      head :forbidden unless Rails.env.development?
    end

    def feature_index
      @feature_index ||= CucumberRunner::FeatureIndex.new(
        Dir.glob(CucumberRunner.configuration.feature_globs.flat_map { |g| Rails.root.join(g) })
      )
    end
  end
end
