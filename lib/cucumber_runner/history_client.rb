# frozen_string_literal: true
require "net/http"
require "uri"
require "json"

module CucumberRunner
  class HistoryClient
    def initialize(url:, token:, timeout_seconds: 10)
      @base = url.to_s.sub(%r{/+\z}, "")
      @token = token
      @timeout = timeout_seconds
    end

    # POST a multipart body to /v1/runs. Used by the recorder.
    def post_run(body, content_type)
      uri = URI.parse(@base + "/v1/runs")
      do_request(Net::HTTP::Post.new(uri.request_uri).tap { |r|
        r["Content-Type"] = content_type
        r.body = body
      }, uri)
    end

    # GET /v1/runs?project_id=…&namespace=cucumber&… — returns the parsed
    # JSON envelope { runs: [...], next_cursor: ... } or nil on any failure.
    def list_runs(project_id:, branch: nil, status: nil, since: nil, limit: 50)
      query = { project_id: project_id, namespace: "cucumber", limit: limit }
      query[:branch] = branch if branch
      query[:status] = status if status
      query[:since]  = since  if since
      uri = URI.parse(@base + "/v1/runs?" + URI.encode_www_form(query))
      do_request(Net::HTTP::Get.new(uri.request_uri), uri)
    end

    # GET /v1/runs/:id — returns { run: {...}, events: [...] } or nil.
    def get_run(id:)
      uri = URI.parse(@base + "/v1/runs/" + URI.encode_www_form_component(id))
      do_request(Net::HTTP::Get.new(uri.request_uri), uri)
    end

    # GET /v1/artifacts/:key — returns [bytes, content_type] or nil. Used by
    # the host's artifact-proxy endpoint so the browser doesn't need to send
    # the bearer token directly.
    def fetch_artifact(key:)
      uri = URI.parse(@base + "/v1/artifacts/" + URI.encode_www_form_component(key))
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = @timeout
      http.open_timeout = @timeout
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@token}"
      res = http.request(req)
      return nil unless res.code.to_i.between?(200, 299)
      [res.body, res["content-type"] || "application/octet-stream"]
    rescue StandardError => e
      warn "[cucumber_runner] history fetch_artifact error: #{e.class}: #{e.message}"
      nil
    end

    private

    def do_request(req, uri)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.read_timeout = @timeout
      http.open_timeout = @timeout
      req["Authorization"] = "Bearer #{@token}"

      res = http.request(req)
      if res.code.to_i.between?(200, 299)
        body = res.body.to_s
        body.empty? ? {} : JSON.parse(body)
      else
        warn "[cucumber_runner] history #{req.method} #{uri.path} failed: #{res.code} #{res.body[0, 200]}"
        nil
      end
    rescue StandardError => e
      warn "[cucumber_runner] history #{req.method} #{uri.path} error: #{e.class}: #{e.message}"
      nil
    end
  end
end
