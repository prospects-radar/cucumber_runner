# frozen_string_literal: true
require "socket"

module CucumberRunner
  class RunMetadata
    DEFAULT_GIT = ->(*args) {
      result = `git #{args.join(" ")} 2>/dev/null`.strip
      result.empty? ? nil : result
    }

    def initialize(env: ENV, git: DEFAULT_GIT)
      @env = env
      @git = git
    end

    def source
      return "interactive"     if @env["CUCUMBER_RUNNER_PORT"]
      return "github-actions"  if @env["GITHUB_ACTIONS"] == "true"
      return "local-ci"        if @env["CI"] == "true"
      "terminal"
    end

    def branch
      @env["GITHUB_REF_NAME"] || @git.call("rev-parse", "--abbrev-ref", "HEAD")
    end

    def commit_sha
      @env["GITHUB_SHA"] || @git.call("rev-parse", "HEAD")
    end

    def pr_number
      ref = @env["GITHUB_REF"]
      return nil unless ref&.start_with?("refs/pull/")
      ref.split("/")[2]&.to_i
    end

    def ci_run_id
      @env["GITHUB_RUN_ID"]
    end

    def host
      @env["RUNNER_NAME"] || Socket.gethostname
    end

    def actor
      @env["GITHUB_ACTOR"] || @env["USER"] || "unknown"
    end

    def history_mode
      (@env["CUCUMBER_RUNNER_HISTORY"] || "auto").downcase
    end

    def record_mode
      (@env["CUCUMBER_RUNNER_RECORD"] || "per_step").downcase.to_sym
    end

    def should_upload?(scenario_status)
      return false if history_mode == "never"
      return true  if history_mode == "always"
      # auto: always for non-GHA; GHA only on failure
      return true unless source == "github-actions"
      scenario_status != :passed
    end
  end
end
