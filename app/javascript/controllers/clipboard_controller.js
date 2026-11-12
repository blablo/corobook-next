import { Controller } from "@hotwired/stimulus"

// Copy a value to the clipboard and say so on the button for a moment.
//   <div data-controller="clipboard" data-clipboard-text-value="https://…" data-clipboard-done-value="Copied">
//     <button data-action="clipboard#copy" data-clipboard-target="label">Copy link</button>
export default class extends Controller {
  static targets = ["label"]
  static values = { text: String, done: String }

  async copy() {
    if (!(await this.write(this.textValue))) return
    if (!this.hasLabelTarget) return
    const label = this.labelTarget
    this.original ??= label.textContent
    label.textContent = this.doneValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => { label.textContent = this.original }, 1500)
  }

  // The async clipboard API needs a secure page (https or localhost). Elsewhere, e.g. the dev
  // server opened by its LAN address, fall back to the old select-and-copy.
  async write(text) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch {
      const area = document.createElement("textarea")
      area.value = text
      area.style.position = "fixed"
      area.style.opacity = "0"
      document.body.appendChild(area)
      area.select()
      let ok = false
      try { ok = document.execCommand("copy") } catch { ok = false }
      area.remove()
      return ok
    }
  }

  disconnect() { clearTimeout(this.timer) }
}
