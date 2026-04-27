# frozen_string_literal: true
CucumberRunner::Engine.routes.draw do
  root to: "browse#index"
  resources :runs, only: [:show, :create, :destroy]
  get "history/:id", to: "history#show", as: :history
  get "history/:id/artifact", to: "history#artifact", as: :history_artifact
  get "step_definitions/lookup", to: "step_definitions#lookup"
end
