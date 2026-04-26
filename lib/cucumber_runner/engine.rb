# frozen_string_literal: true

module CucumberRunner
  class Engine < ::Rails::Engine
    engine_name "cucumber_runner"
    isolate_namespace CucumberRunner

    initializer "cucumber_runner.assets" do |app|
      next unless app.config.respond_to?(:assets)

      app.config.assets.precompile += %w[
        controllers/cucumber_runner_browse_controller.js
        controllers/cucumber_runner_runtime_controller.js
        cucumber_runner.css
      ]
    end

    initializer "cucumber_runner.importmap", before: "importmap" do |app|
      next unless app.config.respond_to?(:importmap)

      app.config.importmap.paths << Engine.root.join("config/importmap.rb")
      app.config.importmap.cache_sweepers << Engine.root.join("app/assets/javascripts")
    end

    initializer "cucumber_runner.i18n" do
      config.i18n.load_path += Dir[Engine.root.join("config/locales/**/*.yml")]
    end
  end
end
