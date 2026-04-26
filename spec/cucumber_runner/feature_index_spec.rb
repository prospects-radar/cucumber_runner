require "spec_helper"
require "cucumber_runner/feature_index"

RSpec.describe CucumberRunner::FeatureIndex do
  let(:fixture)  { File.expand_path("../fixtures/sample.feature", __dir__) }
  let(:index)   { described_class.new([fixture]) }

  it "parses feature name, tags, and scenarios" do
    features = index.all
    expect(features.size).to eq(1)
    f = features.first
    expect(f[:name]).to eq("Sample CRM")
    expect(f[:tags]).to include("@javascript", "@settings")
    expect(f[:path]).to eq(fixture)
    expect(f[:scenarios].size).to eq(2)
  end

  it "captures each scenario's name, tags, line, and steps" do
    s = index.all.first[:scenarios].first
    expect(s[:name]).to eq("Visit index")
    expect(s[:tags]).to include("@smoke", "@happy-path", "@javascript", "@settings")
    expect(s[:line]).to be_a(Integer)
    expect(s[:steps].first[:keyword].strip).to eq("Given")
    expect(s[:steps].first[:text]).to eq("I am logged in")
  end

  it "merges Background steps into each scenario" do
    s = index.all.first[:scenarios].first
    expect(s[:steps].map { |st| st[:text] }).to include("I am logged in")
  end

  it "produces a stable scenario id (digest of path:line)" do
    s = index.all.first[:scenarios].first
    expect(s[:id]).to match(/\A[a-f0-9]+\z/)
  end

  it "looks up by id" do
    s = index.all.first[:scenarios].first
    expect(index.find(s[:id])[:name]).to eq("Visit index")
  end

  it "exposes background_steps and scenario_steps separately" do
    s = index.all.first[:scenarios].first
    expect(s[:background_steps].map { |st| st[:text] }).to eq(["I am logged in"])
    expect(s[:scenario_steps].map { |st| st[:text] }).to eq(["I visit the page", "I should see \"Hello\""])
  end

  it "carries the feature name and description down to each scenario" do
    s = index.all.first[:scenarios].first
    expect(s[:feature_name]).to eq("Sample CRM")
    expect(s[:feature_description]).to include("As a user")
  end
end
