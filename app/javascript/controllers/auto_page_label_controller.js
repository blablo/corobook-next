import { Controller } from "@hotwired/stimulus"

// Keeps the operator's "Page N of M · auto" label in step with an auto-advancing slide: listens
// for the auto-pages:change event its preview dispatches. template uses %{n} and %{count}.
export default class extends Controller {
  static targets = ["text"]
  static values = { template: String }

  update({ detail: { page, count } }) {
    const label = this.templateValue.replace("%{n}", page + 1).replace("%{count}", count)
    this.textTargets.forEach(el => { el.textContent = label })
  }
}
