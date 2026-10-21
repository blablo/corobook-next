import { Controller } from "@hotwired/stimulus"

// Live preview of the church's subdomain URL as the admin types it. Read-only convenience — the
// server still normalizes and validates on save. Mirrors the typed value into the preview code
// element, sanitized to the allowed label charset so the preview matches what will be stored.
export default class extends Controller {
  update() {
    const input = this.element.querySelector("[data-role=subdomain-input]")
    const out = this.element.querySelector("[data-role=subdomain-preview-url]")
    if (!input || !out) return
    const domain = out.textContent.split(".").slice(1).join(".").replace(/\/$/, "") ||
      window.location.hostname.split(".").slice(-2).join(".")
    const sub = input.value.trim().toLowerCase().replace(/[^a-z0-9-]/g, "")
    out.textContent = sub ? `https://${sub}.${domain}/` : "— not set —"
  }
}
