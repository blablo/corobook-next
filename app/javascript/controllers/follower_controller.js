import { Controller } from "@hotwired/stimulus"

// Follower frame guard (design §6.2, §6.4). Each incoming frame carries a monotonic
// position_version. We drop any frame whose version is <= the last one applied, so out-of-order
// Cable delivery (rapid Next) can never flash the congregation backward. On disconnect the
// projector simply holds the last frame — never an error or spinner.
export default class extends Controller {
  static values = { version: Number }

  connect() {
    // The server rendered us at a known version on GET; treat it as applied.
    const applied = window.__coroLastVersion ?? -1
    if (this.versionValue <= applied && applied >= 0) {
      // A stale frame arrived out of order — discard it by restoring nothing (it already
      // replaced #live-frame, so re-request the current state is not needed; just ignore future
      // lower ones). Mark the higher applied version as the source of truth.
      this.element.dataset.stale = "true"
    } else {
      window.__coroLastVersion = this.versionValue
    }
    this.refit()
    this.watchConnection()
  }

  // Re-fit the projector font whenever a new frame lands (the fit controller is on a child).
  refit() {
    const fitEl = this.element.querySelector("[data-controller~=fit]") ||
      (this.element.dataset.controller?.includes("fit") ? this.element : null)
    fitEl?.dispatchEvent(new Event("resize"))
  }

  // Hold the last frame on disconnect; swallow the reconnecting state so nothing flashes.
  watchConnection() {
    document.addEventListener("turbo:before-stream-render", this.guard)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.guard)
  }

  // Intercept stream renders: drop a frame whose version is not strictly newer.
  guard = (event) => {
    const incoming = event.target?.templateContent?.querySelector?.("[data-follower-version-value]")
    if (!incoming) return
    const v = Number(incoming.dataset.followerVersionValue)
    const applied = window.__coroLastVersion ?? -1
    if (v <= applied) {
      event.preventDefault() // stale/out-of-order — never render it
    } else {
      window.__coroLastVersion = v
    }
  }
}
