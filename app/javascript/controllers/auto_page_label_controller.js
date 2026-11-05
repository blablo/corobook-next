import { Controller } from "@hotwired/stimulus"

// Keeps the operator's auto-advance indicators in step with an auto-advancing slide: the
// "Page N of M" label (auto-pages:change) and the time-left bar under Now (auto-pages:progress),
// both dispatched by the slide's preview. template uses %{n} and %{count}.
export default class extends Controller {
  static targets = ["text", "progress"]
  static values = { template: String }

  update({ detail: { page, count } }) {
    const label = this.templateValue.replace("%{n}", page + 1).replace("%{count}", count)
    this.textTargets.forEach(el => { el.textContent = label })
  }

  progress({ detail: { fraction } }) {
    this.progressTargets.forEach(el => { el.value = Math.round(fraction * 100) })
  }
}
