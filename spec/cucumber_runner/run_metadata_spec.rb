require "spec_helper"
require "cucumber_runner/run_metadata"

RSpec.describe CucumberRunner::RunMetadata do
  before do
    stub_const("ENV", env_stub)
  end

  def with_env(overrides)
    described_class.new(env: env_stub.merge(overrides))
  end

  let(:env_stub) { {} }

  it "detects 'github-actions' when GITHUB_ACTIONS is set" do
    expect(with_env("GITHUB_ACTIONS" => "true").source).to eq("github-actions")
  end

  it "detects 'interactive' when CUCUMBER_RUNNER_PORT is set" do
    expect(with_env("CUCUMBER_RUNNER_PORT" => "12345").source).to eq("interactive")
  end

  it "detects 'local-ci' when CI=true and not on GitHub Actions" do
    expect(with_env("CI" => "true").source).to eq("local-ci")
  end

  it "falls back to 'terminal'" do
    expect(with_env({}).source).to eq("terminal")
  end

  it "returns the GitHub branch from GITHUB_REF_NAME" do
    expect(with_env("GITHUB_ACTIONS" => "true", "GITHUB_REF_NAME" => "feat/x").branch).to eq("feat/x")
  end

  it "shells out to git for branch when not in GHA" do
    md = described_class.new(env: {}, git: ->(*args) { "main" if args == ["rev-parse", "--abbrev-ref", "HEAD"] })
    expect(md.branch).to eq("main")
  end

  it "exposes commit_sha, pr_number, ci_run_id, host, actor" do
    md = with_env(
      "GITHUB_ACTIONS" => "true",
      "GITHUB_SHA" => "abcdef",
      "GITHUB_REF_NAME" => "main",
      "GITHUB_RUN_ID" => "777",
      "GITHUB_ACTOR" => "octocat",
      "RUNNER_NAME" => "ubuntu-latest"
    )
    expect(md.commit_sha).to eq("abcdef")
    expect(md.ci_run_id).to eq("777")
    expect(md.host).to eq("ubuntu-latest")
    expect(md.actor).to eq("octocat")
  end

  it "extracts pr_number from GITHUB_REF when present" do
    expect(with_env("GITHUB_ACTIONS" => "true", "GITHUB_REF" => "refs/pull/1234/merge").pr_number).to eq(1234)
  end
end
