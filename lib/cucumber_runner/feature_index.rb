# frozen_string_literal: true
require "digest/sha1"
require "gherkin"

module CucumberRunner
  class FeatureIndex
    def initialize(paths)
      @paths = paths
    end

    def all
      @all ||= @paths.flat_map { |p| Dir.glob(p) }.flat_map { |p| parse_file(p) }
    end

    def find(scenario_id)
      all.flat_map { |f| f[:scenarios] }.find { |s| s[:id] == scenario_id }
    end

    private

    def parse_file(path)
      messages = ::Gherkin.from_paths(
        [path],
        include_source: false,
        include_gherkin_document: true,
        include_pickles: false
      )
      doc = messages.find { |m| m.gherkin_document }&.gherkin_document
      return [] unless doc&.feature

      feature = doc.feature
      feature_tags = feature.tags.map(&:name)
      background_steps = []
      scenarios = []

      feature.children.each do |child|
        if child.background
          background_steps = child.background.steps.map { |s| step_hash(s) }
        elsif child.scenario
          sc = child.scenario
          scenario_steps = sc.steps.map { |s| step_hash(s) }
          steps = background_steps + scenario_steps
          tags = (feature_tags + sc.tags.map(&:name)).uniq
          scenarios << {
            id: digest(path, sc.location.line),
            name: sc.name,
            line: sc.location.line,
            tags: tags,
            steps: steps,                       # combined; index space the formatter uses
            background_steps: background_steps, # for separated rendering
            scenario_steps: scenario_steps,     # for separated rendering
            feature_name: feature.name,
            feature_description: feature.description.to_s.strip,
            path: path
          }
        end
      end

      [{
        path: path,
        breadcrumb: breadcrumb_for(path),
        name: feature.name,
        description: feature.description.to_s.strip,
        tags: feature_tags,
        scenarios: scenarios
      }]
    end

    def step_hash(step)
      { keyword: step.keyword, text: step.text, line: step.location.line }
    end

    def digest(path, line)
      Digest::SHA1.hexdigest("#{path}:#{line}")[0, 16]
    end

    def breadcrumb_for(path)
      rel = path.sub(%r{.*?/features/}, "")
      return "General" if rel == path # no /features/ segment found
      segments = rel.split("/")[0..-2]
      return "General" if segments.nil? || segments.empty?
      segments.map { |s| humanise_segment(s) }.join(" › ")
    end

    def humanise_segment(segment)
      segment.tr("_-", "  ").split.map(&:capitalize).join(" ")
    end
  end
end
