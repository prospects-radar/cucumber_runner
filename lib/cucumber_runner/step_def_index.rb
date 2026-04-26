# frozen_string_literal: true

module CucumberRunner
  class StepDefIndex
    PLACEHOLDER_TO_REGEX = {
      "{string}"  => "\"([^\"]*)\"|'([^']*)'",
      "{int}"     => "(-?\\d+)",
      "{float}"   => "(-?\\d+\\.\\d+)",
      "{word}"    => "(\\S+)"
    }.freeze

    Definition = Struct.new(:file, :line, :regex, :source)

    def initialize(paths)
      @paths = paths
    end

    def match(text)
      definitions.find { |d| d.regex.match?(text) }&.then do |d|
        { file: d.file, line: d.line, source: d.source }
      end
    end

    private

    def definitions
      @definitions ||= @paths.flat_map { |path| parse_file(path) }
    end

    def parse_file(path)
      content = File.read(path)
      defs = []
      content.each_line.with_index(1) do |line, lineno|
        if (m = line.match(/^\s*(Given|When|Then|And|But)(?:\(|\s+)(.+)/))
          regex = extract_regex_or_expression(m[2], content, lineno)
          next unless regex
          defs << Definition.new(path, lineno, regex, line.rstrip)
        end
      end
      defs
    end

    def extract_regex_or_expression(rest, _full, _lineno)
      if (m = rest.match(/\A\/(.*?)\/[mixn]*\)?\s*do\b/))
        return Regexp.new(m[1])
      end
      if (m = rest.match(/\A"(.*?)"\s*\)?\s*do\b/))
        return cucumber_expression_to_regex(m[1])
      end
      nil
    end

    def cucumber_expression_to_regex(expr)
      escaped = Regexp.escape(expr)
      PLACEHOLDER_TO_REGEX.each do |placeholder, replacement|
        escaped = escaped.gsub(Regexp.escape(placeholder), replacement)
      end
      Regexp.new("\\A#{escaped}\\z")
    end
  end
end
