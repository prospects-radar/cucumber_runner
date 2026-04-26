# frozen_string_literal: true
module CucumberRunner
  class BrowseController < ApplicationController
    def index
      @features = feature_index.all
      @all_tags = @features.flat_map { |f| f[:scenarios].flat_map { |s| s[:tags] } }.uniq.sort
    end
  end
end
