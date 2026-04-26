require "spec_helper"
require "cucumber_runner/step_def_index"

RSpec.describe CucumberRunner::StepDefIndex do
  let(:fixture)  { File.expand_path("../fixtures/sample_steps.rb", __dir__) }
  let(:index)    { described_class.new([fixture]) }

  it "matches a regex step definition" do
    m = index.match("I am logged in")
    expect(m[:file]).to eq(fixture)
    expect(m[:line]).to eq(1)
    expect(m[:source]).to include("Given(/^I am logged in$/)")
  end

  it "matches a Cucumber expression with placeholders" do
    m = index.match("I visit the \"home\" page")
    expect(m[:file]).to eq(fixture)
    expect(m[:line]).to eq(5)
  end

  it "returns nil when no match" do
    expect(index.match("nothing matches this")).to be_nil
  end
end
