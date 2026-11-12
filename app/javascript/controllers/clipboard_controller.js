import { Controller } from "@hotwired/stimulus"

// Copy a value to the clipboard and say so for a moment: the element carries data-copied and the
// copied classes, and a DaisyUI tooltip on it (data-tip) reads the done text meanwhile.
//   <div class="tooltip" data-tip="Copy link" data-controller="clipboard" data-clipboard-text-value="https://…"
//        data-clipboard-done-value="Copied" data-clipboard-copied-class="tooltip-open">
//     <button data-action="clipboard#copy">…</button></div>
export default class extends Controller {
  static values = { text: String, done: String }
  static classes = ["copied"]

  async copy() {
    if (!(await this.write(this.textValue))) return
    const el = this.element
    this.tip ??= el.dataset.tip
    el.dataset.copied = ""
    el.classList.add(...this.copiedClasses)
    if (this.tip != null) el.dataset.tip = this.doneValue
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      delete el.dataset.copied
      el.classList.remove(...this.copiedClasses)
      if (this.tip != null) el.dataset.tip = this.tip
    }, 1500)
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
