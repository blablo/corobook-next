import { Controller } from "@hotwired/stimulus"

// Lets a presentation clicker (and the keyboard) drive the live service from the operator page.
// Clickers emit ordinary key events: most send Page Down / Right Arrow to advance and
// Page Up / Left Arrow to go back; some send Space (forward) and Backspace (back), and a few
// send "b"/"." to blank. We map those to the existing Back / Next / Blank forms so the server
// actions, optimistic lock and follower polling are all reused unchanged.
export default class extends Controller {
  static targets = ["next", "back", "blank"]

  connect() {
    this.onKey = this.handleKey.bind(this)
    document.addEventListener("keydown", this.onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this.onKey)
  }

  handleKey(e) {
    // Never hijack keys while the user is typing into a field (jump-to search, etc.).
    const t = e.target
    if (t && (t.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(t.tagName))) return
    if (e.metaKey || e.ctrlKey || e.altKey) return

    const key = e.key
    if (key === "PageDown" || key === "ArrowRight" || key === "ArrowDown" || key === " " || key === "Spacebar") {
      this.submit(this.nextTarget, e)
    } else if (key === "PageUp" || key === "ArrowLeft" || key === "ArrowUp" || key === "Backspace") {
      this.submit(this.backTarget, e)
    } else if ((key === "b" || key === "B" || key === ".") && this.hasBlankTarget) {
      this.submit(this.blankTarget, e)
    }
  }

  submit(form, e) {
    if (!form) return
    e.preventDefault()
    if (typeof form.requestSubmit === "function") form.requestSubmit()
    else form.submit()
  }
}
