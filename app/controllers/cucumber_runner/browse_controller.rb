# frozen_string_literal: true
require "cucumber_runner/history_client"

module CucumberRunner
  class BrowseController < ApplicationController
    def index
      @features = feature_index.all
      @all_tags = @features.flat_map { |f| f[:scenarios].flat_map { |s| s[:tags] } }.uniq.sort
      @runs_by_scenario = fetch_recent_runs_by_scenario
    end

    private

    # Returns a hash keyed by "<feature_path>:<line>" with each value an array
    # of run hashes (newest-first). Empty hash when history is not configured
    # or the worker is unreachable — the browse page works without history.
    def fetch_recent_runs_by_scenario
      config = CucumberRunner.configuration
      return {} unless config.history_url && config.history_api_token && config.history_project_id

      client = HistoryClient.new(url: config.history_url, token: config.history_api_token)
      result = client.list_runs(project_id: config.history_project_id, limit: 200)
      return {} unless result.is_a?(Hash) && result["runs"].is_a?(Array)

      result["runs"].each_with_object({}) do |run, hash|
        summary = parse_summary(run["summary_json"])
        feature_path = summary["feature_path"]
        line = summary["line"]
        next unless feature_path && line
        key = "#{feature_path}:#{line}"
        (hash[key] ||= []) << run
      end
    end

    def parse_summary(json)
      return {} unless json.is_a?(String)
      JSON.parse(json)
    rescue JSON::ParserError
      {}
    end
  end
end
