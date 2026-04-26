// app/assets/javascripts/controllers/cucumber_runner_browse_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["search", "list", "tagChips", "data"]

  connect() {
    this.activeTags = new Set()
    this.scenarios = JSON.parse(this.dataTarget.textContent)
  }

  filter() {
    this.applyFilter()
  }

  toggleTag(event) {
    const tag = event.currentTarget.dataset.tag
    if (this.activeTags.has(tag)) {
      this.activeTags.delete(tag)
      event.currentTarget.dataset.active = "false"
    } else {
      this.activeTags.add(tag)
      event.currentTarget.dataset.active = "true"
    }
    this.applyFilter()
  }

  applyFilter() {
    const term = (this.searchTarget.value || "").toLowerCase()
    const required = Array.from(this.activeTags)

    this.listTarget.querySelectorAll(".cr-scenario").forEach((li) => {
      const text = li.textContent.toLowerCase()
      const tags = (li.dataset.tags || "").split(/\s+/).filter(Boolean)

      const matchesSearch = term === "" || text.includes(term)
      const matchesTags = required.every((t) => tags.includes(t))

      li.classList.toggle("is-hidden", !(matchesSearch && matchesTags))
    })
  }
}
