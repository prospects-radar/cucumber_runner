require "spec_helper"
require "cucumber_runner/multipart_body"

RSpec.describe CucumberRunner::MultipartBody do
  it "builds a multipart body with text and binary parts" do
    mp = described_class.new
    mp.add_text("metadata", '{"hello":"world"}')
    mp.add_binary("artifact_1", "raw-bytes", filename: "0001.jpg", content_type: "image/jpeg")

    body, content_type = mp.finalize

    expect(content_type).to start_with("multipart/form-data; boundary=")
    expect(body).to include('Content-Disposition: form-data; name="metadata"')
    expect(body).to include('{"hello":"world"}')
    expect(body).to include('Content-Disposition: form-data; name="artifact_1"; filename="0001.jpg"')
    expect(body).to include("Content-Type: image/jpeg")
    expect(body).to include("raw-bytes")
    boundary = content_type.split("boundary=").last
    expect(body).to end_with("--#{boundary}--\r\n")
  end

  it "produces the body as binary-encoded String" do
    mp = described_class.new
    mp.add_binary("a", "\x99\xFF".b, filename: "x.bin", content_type: "application/octet-stream")
    body, _ = mp.finalize
    expect(body.encoding).to eq(Encoding::ASCII_8BIT)
    expect(body).to include("\x99\xFF".b)
  end
end
