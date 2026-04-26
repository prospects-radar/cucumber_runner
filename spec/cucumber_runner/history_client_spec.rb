require "spec_helper"
require "cucumber_runner/history_client"
require "cucumber_runner/multipart_body"

RSpec.describe CucumberRunner::HistoryClient do
  let(:url)   { "https://history.example" }
  let(:token) { "cr_test_token" }
  let(:client) { described_class.new(url: url, token: token) }

  it "POSTs multipart body with bearer auth and returns parsed response on 201" do
    mp = CucumberRunner::MultipartBody.new
    mp.add_text("metadata", '{"a":1}')
    body, ct = mp.finalize

    stub = stub_request(:post, "#{url}/v1/runs")
      .with(headers: { "Authorization" => "Bearer #{token}", "Content-Type" => ct })
      .to_return(status: 201, body: '{"run_id":"abc","view_url":"/v1/runs/abc"}', headers: { "Content-Type" => "application/json" })

    result = client.post_run(body, ct)
    expect(stub).to have_been_requested
    expect(result).to eq("run_id" => "abc", "view_url" => "/v1/runs/abc")
  end

  it "returns nil and logs on network failure" do
    stub_request(:post, "#{url}/v1/runs").to_raise(SocketError.new("nope"))
    expect { client.post_run("x", "text/plain") }.not_to raise_error
    expect(client.post_run("x", "text/plain")).to be_nil
  end

  it "returns nil and logs on 4xx/5xx" do
    stub_request(:post, "#{url}/v1/runs").to_return(status: 401, body: '{"error":"invalid_token"}')
    expect(client.post_run("x", "text/plain")).to be_nil
  end
end
