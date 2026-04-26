require "spec_helper"

RSpec.describe CucumberRunner::VERSION do
  it "is a semver string" do
    expect(CucumberRunner::VERSION).to match(/\A\d+\.\d+\.\d+\z/)
  end
end
