# frozen_string_literal: true

require "spec_helper"

RSpec.describe CucumberRunner::Configuration do
  it "exposes documented defaults" do
    c = described_class.new
    expect(c.feature_globs).to eq(["features/**/*.feature"])
    expect(c.cucumber_command).to eq(["bundle", "exec", "cucumber"])
    expect(c.cucumber_env).to eq("RAILS_ENV" => "test")
    expect(c.screencast_fps).to eq(5)
    expect(c.screencast_quality).to eq(60)
    expect(c.tags_to_show).to be_nil
    expect(c.step_defs_globs).to eq(["features/step_definitions/**/*.rb"])
    expect(c.host_javascript_entry).to eq("application")
  end

  it "yields itself from CucumberRunner.configure" do
    CucumberRunner.configure { |c| c.screencast_fps = 10 }
    expect(CucumberRunner.configuration.screencast_fps).to eq(10)
  ensure
    CucumberRunner.instance_variable_set(:@configuration, nil)
  end
end
