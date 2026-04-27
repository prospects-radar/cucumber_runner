# frozen_string_literal: true
module CucumberRunner
  module ScenarioNavHelper
    PREV_LABEL = "← Previous scenario"
    NEXT_LABEL = "Next scenario →"

    def prev_next_link(direction, scenario)
      label = direction == :prev ? PREV_LABEL : NEXT_LABEL
      if scenario
        button_to label, runs_path(scenario_id: scenario[:id]),
                  method: :post, class: "cr-link",
                  form: { class: "cr-link-form" }
      else
        content_tag(:span, label,
                    class: "cr-link cr-link--disabled",
                    "aria-disabled": "true")
      end
    end
  end
end
