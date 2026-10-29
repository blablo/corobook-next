import { Controller } from "@hotwired/stimulus"

// Live preview of the church's projector look on the Settings page. Reads the projection form
// controls and paints a 16:9 sample slide, so an admin sees the result before saving. Mirrors the
// server-side ProjectorSettings mapping (fonts, line-heights, valign, casing, by-lines chunking).
export default class extends Controller {
  static targets = ["stage", "frame", "lyrics"]
  static values = { imageUrl: String }

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

  disconnect() {
    if (this.chosenObjectUrl) { URL.revokeObjectURL(this.chosenObjectUrl); this.chosenObjectUrl = null }
  }

  // Preview a just-picked image file without uploading: swap the stage to it via an object URL.
  previewImage(event) {
    const file = event.target.files && event.target.files[0]
    if (this.chosenObjectUrl) { URL.revokeObjectURL(this.chosenObjectUrl); this.chosenObjectUrl = null }
    if (file) {
      this.chosenObjectUrl = URL.createObjectURL(file)
    }
    this.update()
  }

  // The image to show in image mode: a freshly-picked file wins over the saved one.
  currentImageUrl() {
    return this.chosenObjectUrl || (this.hasImageUrlValue ? this.imageUrlValue : "")
  }

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
    const imageUrl = this.currentImageUrl()
    const useImage = bgType === "image" && imageUrl
    const background = bgType === "gradient"
      ? `linear-gradient(${isNaN(angle) ? 160 : angle}deg, ${bg1}, ${bg2})`
      : bg1
    const text = this.val("pp-text") || "#ffffff"
    const font = this.constructor.FONTS[this.val("pp-font")] || this.constructor.FONTS.sans
    const lh = this.constructor.LINE_HEIGHTS[this.val("pp-lh")] || "1.15"
    const valign = this.constructor.VALIGN[this.val("pp-valign")] || "center"
    const lyricCase = this.constructor.CASE[this.val("pp-lyric-case")] || "none"
    const bold = this.val("pp-bold")
    const pagination = this.val("pp-pagination")
    const perSlide = Math.max(1, Math.min(20, parseInt(this.val("pp-lines"), 10) || 4))
    // Fixed lyric size as % of screen height (cqh — the preview stage is a size container); 0 = auto.
    const fixedSize = parseInt(this.val("pp-font-size"), 10) || 0

    // Stage background (solid or gradient). Painted on the stage only — the frame sits inside the
    // stage padding, so a second copy of a gradient there would show a seam.
    if (useImage) {
      // Image mode: a dark scrim over the cover photo, so the sample lyrics stay legible — mirrors
      // the projector's .projector-slide-bg + scrim. Falls back to black behind a not-yet-loaded image.
      this.stageTarget.style.background =
        `linear-gradient(rgba(0,0,0,0.45), rgba(0,0,0,0.45)), url("${imageUrl}") center / cover no-repeat, #000`
    } else {
      this.stageTarget.style.background = background
    }

    const frame = this.frameTarget
    frame.style.color = text
    frame.style.fontFamily = font
    frame.style.justifyContent = valign

    // Show only the first slide's worth of lines: section mode = whole sample; by_lines = first N.
    // Font size is NOT set per line: the fit controller sizes the whole block, exactly as on the
    // real projector (auto-fit, or the fixed % of screen height).
    const lines = pagination === "by_lines" ? this.constructor.SAMPLE.slice(0, perSlide) : this.constructor.SAMPLE
    this.lyricsTarget.innerHTML = ""
    lines.forEach((line) => {
      const div = document.createElement("div")
      div.textContent = line
      div.style.fontWeight = bold ? "700" : "400"
      div.style.lineHeight = lh
      div.style.textTransform = lyricCase
      div.style.marginTop = "0.3em"
      div.style.textShadow = useImage ? "0 2px 12px rgba(0,0,0,0.65)" : "none"
      this.lyricsTarget.appendChild(div)
    })

    const fitEl = this.lyricsTarget.closest('[data-controller~="fit"]')
    if (fitEl) {
      fitEl.setAttribute("data-fit-fixed-value", String(fixedSize))
      fitEl.dispatchEvent(new CustomEvent("fit:refit"))
    }

    // Lines-per-slide only matters in by_lines mode.
    const linesField = this.element.querySelector('[data-role="pp-lines-field"]')
    if (linesField) linesField.style.display = pagination === "by_lines" ? "" : "none"

    // Gradient colour + angle only matter in gradient mode.
    const isGradient = bgType === "gradient"
    const isImage = bgType === "image"
    const color2Field = this.element.querySelector('[data-role="pp-bg-color2-field"]')
    const angleField = this.element.querySelector('[data-role="pp-bg-angle-field"]')
    if (color2Field) color2Field.style.display = isGradient ? "" : "none"
    if (angleField) angleField.style.display = isGradient ? "" : "none"
    // Solid background colour only applies in solid/gradient modes (it is the gradient's first stop).
    const bgColorField = this.element.querySelector('[data-role="pp-bg"]')?.closest("fieldset")
    if (bgColorField) bgColorField.style.display = isImage ? "none" : ""
    // The image upload field only applies in image mode.
    const imageField = this.element.querySelector('[data-role="pp-bg-image-field"]')
    if (imageField) imageField.style.display = isImage ? "" : "none"
    const angleLabel = this.element.querySelector('[data-role="pp-bg-angle-label"]')
    if (angleLabel && !isNaN(angle)) angleLabel.textContent = `${angle}°`
  }
}
