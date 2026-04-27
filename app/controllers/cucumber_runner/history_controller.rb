# frozen_string_literal: true
require "cucumber_runner/history_client"

module CucumberRunner
  class HistoryController < ApplicationController
    def show
      @run_id = params[:id]
      payload = history_client&.get_run(id: @run_id)
      head :not_found and return unless payload && payload["run"]

      @run = payload["run"]
      @events = payload["events"] || []
      @summary = parse_summary(@run["summary_json"])
    end

    def artifact
      key = params[:key]
      head :bad_request and return if key.blank?
      result = history_client&.fetch_artifact(key: key)
      head :not_found and return unless result
      bytes, content_type = result
      send_data bytes, type: content_type, disposition: "inline"
    end

    private

    def history_client
      config = CucumberRunner.configuration
      return nil unless config.history_url && config.history_api_token
      HistoryClient.new(url: config.history_url, token: config.history_api_token)
    end

    def parse_summary(json)
      return {} unless json.is_a?(String)
      JSON.parse(json)
    rescue JSON::ParserError
      {}
    end
  end
end
