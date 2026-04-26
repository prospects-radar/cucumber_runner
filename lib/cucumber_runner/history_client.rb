# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module CucumberRunner
  class HistoryClient
    def initialize(url:, token:, timeout_seconds: 10)
      @uri = URI.parse(url.to_s.sub(%r{/+\z}, "") + "/v1/runs")
      @token = token
      @timeout = timeout_seconds
    end

    def post_run(body, content_type)
      http = Net::HTTP.new(@uri.host, @uri.port)
      http.use_ssl = (@uri.scheme == "https")
      http.read_timeout = @timeout
      http.open_timeout = @timeout

      req = Net::HTTP::Post.new(@uri.request_uri)
      req["Authorization"] = "Bearer #{@token}"
      req["Content-Type"] = content_type
      req.body = body

      res = http.request(req)
      if res.code.to_i.between?(200, 299)
        JSON.parse(res.body)
      else
        warn "[cucumber_runner] history upload failed: #{res.code} #{res.body[0, 200]}"
        nil
      end
    rescue StandardError => e
      warn "[cucumber_runner] history upload error: #{e.class}: #{e.message}"
      nil
    end
  end
end
