import { Controller } from "@hotwired/stimulus"

// Copy a value to the clipboard and say so on the button for a moment.
//   <div data-controller="clipboard" data-clipboard-text-value="https://…" data-clipboard-done-value="Copied">
//     <button data-action="clipboard#copy" data-clipboard-target="label">Copy link</button>
export default class extends Controller {
  static targets = ["label"]
  static values = { text: String, done: String }

  async copy() {
    try {
      await navigator.clipboard.writeText(this.textValue)
    } catch {
      return // no clipboard access (e.g. not https): the link is on screen to copy by hand
    }
    if (!this.hasLabelTarget) return
    const label = this.labelTarget
    this.original ??= label.textContent
    label.textContent = this.doneValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { label.textContent = this.original }, 1500)
  }

  disconnect() { clearTimeout(this.timer) }
}
