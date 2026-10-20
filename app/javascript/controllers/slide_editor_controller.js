import { Controller } from "@hotwired/stimulus"

// Live slide preview: debounced POST to /text_slides/preview renders the SAME safe HTML the
// projector uses (commonmarker server-side), so the preview never drifts from the real output.
export default class extends Controller {
  static targets = ["body", "subtype", "preview"]
  static values = { url: String }

  connect() { this.render() }

  schedule() {
    clearTimeout(this._t)
    this._t = setTimeout(() => this.render(), 200)
  }

  async render() {
    const body = this.hasBodyTarget ? this.bodyTarget.value : ""
    const subtype = this.hasSubtypeTarget ? this.subtypeTarget.value : "statement"
    try {
      const res = await fetch(this.urlValue, {
        method: "POST", headers: this.headers(),
        body: JSON.stringify({ body_markdown: body, subtype })
      })
      if (!res.ok) return
      const { html, subtype_class } = await res.json()
      this.previewTarget.className = `slide-preview ${subtype_class}`
      this.previewTarget.innerHTML = html || `<p class="opacity-40">Nothing to preview yet.</p>`
    } catch { /* leave the last good preview on a transient error */ }
  }

  headers() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
  }
}
