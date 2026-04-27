# frozen_string_literal: true
CucumberRunner::Engine.routes.draw do
  root to: "browse#index"
  resources :runs, only: [:show, :create, :destroy]
  get "step_definitions/lookup", to: "step_definitions#lookup"
end
