import { Controller } from "@hotwired/stimulus"

// Live preview of the church's subdomain URL as the admin types, plus a copy-to-clipboard button.
// Read-only convenience — the server still normalizes and validates on save. The preview mirrors
// the typed value sanitized to the allowed label charset, so it matches what will be stored.
export default class extends Controller {
  static targets = ["url", "copyBtn", "copyLabel"]

  update() {
    const input = this.element.querySelector("[data-role=subdomain-input]")
    if (!input || !this.hasUrlTarget) return
    const domain = this.domain()
    const sub = input.value.trim().toLowerCase().replace(/[^a-z0-9-]/g, "")
    this.urlTarget.textContent = sub ? `https://${sub}.${domain}/` : "— not set —"
    // Enable the copy button only when there is a real URL to copy.
    if (this.hasCopyBtnTarget) this.copyBtnTarget.classList.toggle("btn-disabled", !sub)
  }

  async copy() {
    if (!this.hasUrlTarget) return
    const url = this.urlTarget.textContent.trim()
    if (!url || url.startsWith("—")) return
    try {
      await navigator.clipboard.writeText(url)
    } catch (_) {
      // Fallback for browsers without the async clipboard API.
      const ta = document.createElement("textarea")
      ta.value = url; ta.style.position = "fixed"; ta.style.opacity = "0"
      document.body.appendChild(ta); ta.select()
      try { document.execCommand("copy") } catch (_) { /* give up silently */ }
      ta.remove()
    }
    this.flash("Copied!")
  }

  // Briefly show confirmation on the button label, then restore it.
  flash(text) {
    if (!this.hasCopyLabelTarget) return
    const prev = this.copyLabelTarget.textContent
    this.copyLabelTarget.textContent = text
    clearTimeout(this._t)
    this._t = setTimeout(() => { this.copyLabelTarget.textContent = prev }, 1500)
  }

  // The base domain from the current preview text, or derived from the page host.
  domain() {
    if (this.hasUrlTarget) {
      const parts = this.urlTarget.textContent.replace(/^https?:\/\//, "").replace(/\/$/, "").split(".")
      if (parts.length > 1) return parts.slice(1).join(".")
    }
    return window.location.hostname.split(".").slice(-2).join(".")
  }
}
