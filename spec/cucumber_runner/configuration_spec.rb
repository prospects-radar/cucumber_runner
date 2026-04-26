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

  it "defaults history settings to nil/sane values" do
    c = described_class.new
    expect(c.history_url).to be_nil
    expect(c.history_project_id).to be_nil
    expect(c.history_api_token).to be_nil
    expect(c.history_default_record_mode).to eq(:per_step)
  end

  it "allows overriding history settings" do
    c = described_class.new
    c.history_url = "https://example"
    c.history_project_id = "x"
    c.history_api_token = "tok"
    c.history_default_record_mode = :screencast
    expect(c.history_url).to eq("https://example")
    expect(c.history_project_id).to eq("x")
    expect(c.history_api_token).to eq("tok")
    expect(c.history_default_record_mode).to eq(:screencast)
  end
end
