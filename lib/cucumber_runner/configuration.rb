# frozen_string_literal: true

module CucumberRunner
  class Configuration
    attr_accessor :feature_globs, :cucumber_command, :cucumber_env,
                  :screencast_fps, :screencast_quality, :tags_to_show,
                  :step_defs_globs, :host_javascript_entry,
                  :history_url, :history_project_id, :history_api_token,
                  :history_default_record_mode

    def initialize
      @feature_globs         = ["features/**/*.feature"]
      @cucumber_command      = ["bundle", "exec", "cucumber"]
      @cucumber_env          = { "RAILS_ENV" => "test" }
      @screencast_fps        = 5
      @screencast_quality    = 60
      @tags_to_show          = nil
      @step_defs_globs       = ["features/step_definitions/**/*.rb"]
      # The host app's importmap entry to load via javascript_importmap_tags.
      # Most Rails apps use "application"; some use a custom name. Override
      # in an initializer if your host's main JS entry isn't "application".
      @host_javascript_entry = "application"

      @history_url                 = nil
      @history_project_id          = nil
      @history_api_token           = nil
      @history_default_record_mode = :per_step
    end
  end
end
