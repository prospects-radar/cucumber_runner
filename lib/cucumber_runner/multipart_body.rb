# frozen_string_literal: true
require "securerandom"

module CucumberRunner
  class MultipartBody
    def initialize
      @boundary = "cr-#{SecureRandom.hex(12)}"
      @parts = []
    end

    def add_text(name, value)
      @parts << build_part(name, value.to_s.b, nil, "text/plain; charset=utf-8")
      self
    end

    def add_binary(name, bytes, filename:, content_type:)
      @parts << build_part(name, bytes.to_s.b, filename, content_type)
      self
    end

    def finalize
      body = String.new(encoding: Encoding::ASCII_8BIT)
      @parts.each { |part| body << part }
      body << "--#{@boundary}--\r\n".b
      [body, "multipart/form-data; boundary=#{@boundary}"]
    end

    private

    def build_part(name, bytes, filename, content_type)
      header = String.new(encoding: Encoding::ASCII_8BIT)
      header << "--#{@boundary}\r\n".b
      if filename
        header << %(Content-Disposition: form-data; name="#{name}"; filename="#{filename}"\r\n).b
      else
        header << %(Content-Disposition: form-data; name="#{name}"\r\n).b
      end
      header << "Content-Type: #{content_type}\r\n\r\n".b
      header << bytes
      header << "\r\n".b
      header
    end
  end
end
