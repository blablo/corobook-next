import { Controller } from "@hotwired/stimulus"

// Live preview of the church's projector look on the Settings page. Reads the projection form
// controls and paints a 16:9 sample slide, so an admin sees the result before saving. Mirrors the
// server-side ProjectorSettings mapping (fonts, line-heights, valign, casing, by-lines chunking).
export default class extends Controller {
  static targets = ["stage", "frame", "title", "lyrics"]

  static FONTS = {
    sans: '-apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif',
    serif: 'Georgia, "Times New Roman", Times, serif',
    condensed: '"Arial Narrow", "Roboto Condensed", "Helvetica Neue", sans-serif',
    mono: 'ui-monospace, "SF Mono", "Cascadia Code", Menlo, Consolas, monospace',
  }
  static LINE_HEIGHTS = { tight: "1.0", normal: "1.15", relaxed: "1.4" }
  static VALIGN = { top: "flex-start", center: "center", bottom: "flex-end" }
  static CASE = { none: "none", upper: "uppercase", title: "capitalize" }

  // A short, section-structured sample so both pagination modes read correctly.
  static SAMPLE = [
    "Amazing grace how sweet the sound",
    "That saved a wretch like me",
    "I once was lost but now am found",
    "Was blind but now I see",
    "'Twas grace that taught my heart to fear",
    "And grace my fears relieved",
  ]

  connect() { this.update() }

  val(role) {
    const el = this.element.querySelector(`[data-role="${role}"]`)
    if (!el) return null
    return el.type === "checkbox" ? el.checked : el.value
  }

  update() {
    const bgType = this.val("pp-bg-type")
    const bg1 = this.val("pp-bg") || "#000000"
    const bg2 = this.val("pp-bg2") || "#1a1a2e"
    const angle = parseInt(this.val("pp-bg-angle"), 10)
    const background = bgType === "gradient"
      ? `linear-gradient(${isNaN(angle) ? 160 : angle}deg, ${bg1}, ${bg2})`
      : bg1
    const text = this.val("pp-text") || "#ffffff"
    const font = this.constructor.FONTS[this.val("pp-font")] || this.constructor.FONTS.sans
    const lh = this.constructor.LINE_HEIGHTS[this.val("pp-lh")] || "1.15"
    const valign = this.constructor.VALIGN[this.val("pp-valign")] || "center"
    const lyricCase = this.constructor.CASE[this.val("pp-lyric-case")] || "none"
    const titleCase = this.constructor.CASE[this.val("pp-title-case")] || "none"
    const bold = this.val("pp-bold")
    const pagination = this.val("pp-pagination")
    const perSlide = Math.max(1, Math.min(20, parseInt(this.val("pp-lines"), 10) || 4))

    // Stage background (solid or gradient).
    this.stageTarget.style.background = background

    const frame = this.frameTarget
    frame.style.background = background
    frame.style.color = text
    frame.style.fontFamily = font
    frame.style.justifyContent = valign

    this.titleTarget.style.textTransform = titleCase

    // Show only the first slide's worth of lines: section mode = whole sample; by_lines = first N.
    const lines = pagination === "by_lines" ? this.constructor.SAMPLE.slice(0, perSlide) : this.constructor.SAMPLE
    this.lyricsTarget.innerHTML = ""
    lines.forEach((line) => {
      const div = document.createElement("div")
      div.textContent = line
      div.style.fontWeight = bold ? "700" : "400"
      div.style.lineHeight = lh
      div.style.textTransform = lyricCase
      div.style.fontSize = "clamp(0.85rem, 2.6vw, 1.5rem)"
      div.style.marginTop = "0.3em"
      this.lyricsTarget.appendChild(div)
    })

    // Lines-per-slide only matters in by_lines mode.
    const linesField = this.element.querySelector('[data-role="pp-lines-field"]')
    if (linesField) linesField.style.display = pagination === "by_lines" ? "" : "none"

    // Gradient colour + angle only matter in gradient mode.
    const isGradient = bgType === "gradient"
    const color2Field = this.element.querySelector('[data-role="pp-bg-color2-field"]')
    const angleField = this.element.querySelector('[data-role="pp-bg-angle-field"]')
    if (color2Field) color2Field.style.display = isGradient ? "" : "none"
    if (angleField) angleField.style.display = isGradient ? "" : "none"
    const angleLabel = this.element.querySelector('[data-role="pp-bg-angle-label"]')
    if (angleLabel && !isNaN(angle)) angleLabel.textContent = `${angle}°`
  }
}
