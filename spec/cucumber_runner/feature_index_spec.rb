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

  describe "#breadcrumb_for" do
    let(:nested) { File.expand_path("../fixtures/features/admin/users/permissions.feature", __dir__) }
    let(:single) { File.expand_path("../fixtures/features/onboarding/sign_up.feature", __dir__) }
    let(:root)   { File.expand_path("../fixtures/features/root_only.feature", __dir__) }

    it "joins humanised path segments with ' › ' for nested directories" do
      idx = described_class.new([nested])
      expect(idx.all.first[:breadcrumb]).to eq("Admin › Users")
    end

    it "uses a single humanised segment for one-level subdirectories" do
      idx = described_class.new([single])
      expect(idx.all.first[:breadcrumb]).to eq("Onboarding")
    end

    it "returns 'General' for files directly under features/" do
      idx = described_class.new([root])
      expect(idx.all.first[:breadcrumb]).to eq("General")
    end

    it "returns 'General' when path has no features/ segment" do
      legacy = File.expand_path("../fixtures/sample.feature", __dir__)
      idx = described_class.new([legacy])
      expect(idx.all.first[:breadcrumb]).to eq("General")
    end
  end

  describe "#neighbors" do
    let(:multi)  { File.expand_path("../fixtures/features/multi_scenario.feature", __dir__) }
    let(:index)  { described_class.new([multi]) }
    let(:scenarios) { index.all.first[:scenarios] }

    it "returns nil prev for the first scenario in a file" do
      n = index.neighbors(scenarios.first[:id])
      expect(n[:prev]).to be_nil
      expect(n[:next][:name]).to eq("Bravo")
    end

    it "returns both neighbors for a middle scenario" do
      n = index.neighbors(scenarios[1][:id])
      expect(n[:prev][:name]).to eq("Alpha")
      expect(n[:next][:name]).to eq("Charlie")
    end

    it "returns nil next for the last scenario in a file" do
      n = index.neighbors(scenarios.last[:id])
      expect(n[:prev][:name]).to eq("Bravo")
      expect(n[:next]).to be_nil
    end

    it "crosses feature-file boundaries alphabetically by path" do
      single = File.expand_path("../fixtures/features/onboarding/sign_up.feature", __dir__)
      # Pass paths in non-alphabetical order — neighbors should still order them by path.
      idx = described_class.new([single, multi])

      # Sorted path order: multi_scenario.feature (m) < onboarding/sign_up.feature (o)
      # Flat scenario order: Alpha, Bravo, Charlie (from multi), then Happy path (from single).
      multi_scenarios  = idx.all.find { |f| f[:path] == multi }[:scenarios]
      single_scenarios = idx.all.find { |f| f[:path] == single }[:scenarios]
      alpha = multi_scenarios.first
      charlie = multi_scenarios.last
      happy = single_scenarios.first

      # Last scenario of one feature → first scenario of the next feature
      expect(idx.neighbors(charlie[:id])[:next][:name]).to eq("Happy path")

      # First scenario of a later feature → last scenario of the prior feature
      expect(idx.neighbors(happy[:id])[:prev][:name]).to eq("Charlie")

      # Globally first scenario has no prev; globally last has no next
      expect(idx.neighbors(alpha[:id])[:prev]).to be_nil
      expect(idx.neighbors(happy[:id])[:next]).to be_nil
    end

    it "returns {prev: nil, next: nil} for an unknown id" do
      expect(index.neighbors("nonexistent")).to eq(prev: nil, next: nil)
    end
  end
end
