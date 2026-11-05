import { Controller } from "@hotwired/stimulus"

// Keeps the operator's live indicators in step with the slide in its preview: the auto-advance
// "Page N of M" label (auto-pages:change), the page time-left bar (auto-pages:progress) and the
// countdown badge (countdown:tick). template uses %{n} and %{count}.
export default class extends Controller {
  static targets = ["text", "progress", "countdown"]
  static values = { template: String }

  update({ detail: { page, count } }) {
    const label = this.templateValue.replace("%{n}", page + 1).replace("%{count}", count)
    this.textTargets.forEach(el => { el.textContent = label })
  }

  progress({ detail: { fraction } }) {
    this.progressTargets.forEach(el => { el.value = Math.round(fraction * 100) })
  }

  countdown({ detail: { text, done } }) {
    this.countdownTargets.forEach(el => {
      el.textContent = done ? el.dataset.done : el.dataset.left.replace("%{t}", text)
    })
  }
}
