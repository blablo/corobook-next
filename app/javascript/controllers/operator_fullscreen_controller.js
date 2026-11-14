import { Controller } from "@hotwired/stimulus"

// Full screen on the operator page, for a computer with only one screen: the screen becomes the
// projector view (the same /p/:token page the projection screen opens), and the clicker or the
// arrow keys keep driving the service from it. Esc leaves full screen and returns to the operator
// view, reloaded so it shows where the service is now.
//
// The projector page runs inside an iframe that is the full-screen element. The operator page's
// own forms reload the page on every move, which would drop out of full screen; the projector
// page instead moves with fetch + the follower stream, so it stays in full screen.
export default class extends Controller {
  static values = { url: String }

  connect() {
    this.onChange = this.handleChange.bind(this)
    document.addEventListener("fullscreenchange", this.onChange)
  }

  disconnect() {
    document.removeEventListener("fullscreenchange", this.onChange)
    this.box?.remove()
  }

  start(e) {
    e.preventDefault()
    // No element full screen (e.g. Safari on iPhone): open the projector view in a new tab.
    if (!document.fullscreenEnabled || !this.element.requestFullscreen) { window.open(this.urlValue, "_blank"); return }

    const box = document.createElement("div")
    box.className = "operator-fullscreen"
    box.dataset.role = "operator-fullscreen"
    const frame = document.createElement("iframe")
    frame.src = this.urlValue
    frame.title = this.element.dataset.fullscreenTitle || ""
    frame.addEventListener("load", () => this.focusFrame(frame))
    box.appendChild(frame)
    document.body.appendChild(box)
    this.box = box
    this.frame = frame

    box.requestFullscreen()
      .then(() => this.focusFrame(frame))
      .catch(() => { this.close(); window.open(this.urlValue, "_blank") })
  }

  // Keys must reach the projector page (its clicker handler), not this page.
  focusFrame(frame) {
    frame.focus()
    try { frame.contentWindow.focus() } catch (_) { /* same origin; ignore if not ready */ }
  }

  handleChange() {
    if (document.fullscreenElement || !this.box) return
    this.close()
    // The operator page doesn't follow moves made from the projector page: show the current state.
    window.location.reload()
  }

  close() {
    this.box?.remove()
    this.box = null
    this.frame = null
  }
}
