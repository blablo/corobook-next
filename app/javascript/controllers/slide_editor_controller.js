import { Controller } from "@hotwired/stimulus"

// WYSIWYG slide body. The author types into a contenteditable surface and formats with a toolbar;
// no markdown is ever shown. On every edit the HTML is serialized to Markdown into the canonical
// hidden `body_markdown` field (what the projector renders via commonmarker), and a live preview
// renders that same markdown server-side so what-you-see matches the screen. An Advanced toggle
// exposes the raw markdown for power users (the escape hatch).
export default class extends Controller {
  static targets = ["rich", "source", "subtype", "preview", "advancedBtn", "toolbar"]
  static values = { url: String }

  connect() {
    // Seed the WYSIWYG surface from the stored markdown.
    this.richTarget.innerHTML = this.mdToHtml(this.sourceTarget.value || "")
    this.advancedOpen = false
    this.render()
  }

  // ---- toolbar ----
  bold(e) { e.preventDefault(); this.exec("bold") }
  italic(e) { e.preventDefault(); this.exec("italic") }
  heading(e) { e.preventDefault(); this.exec("formatBlock", "H2") }
  bullet(e) { e.preventDefault(); this.exec("insertUnorderedList") }
  clearFormat(e) { e.preventDefault(); this.exec("removeFormat"); this.exec("formatBlock", "P") }
  exec(cmd, val = null) {
    this.richTarget.focus()
    document.execCommand(cmd, false, val)
    this.syncFromRich()
  }
  onKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "b") { e.preventDefault(); this.bold(e) }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "i") { e.preventDefault(); this.italic(e) }
  }

  // ---- sync ----
  onRichInput() { this.syncFromRich() }
  syncFromRich() {
    this.sourceTarget.value = this.htmlToMd(this.richTarget)
    this.schedule()
  }
  onSourceInput() {               // editing raw markdown in Advanced mode
    this.richTarget.innerHTML = this.mdToHtml(this.sourceTarget.value)
    this.schedule()
  }

  toggleAdvanced(e) {
    e.preventDefault()
    this.advancedOpen = !this.advancedOpen
    this.sourceTarget.classList.toggle("hidden", !this.advancedOpen)
    this.toolbarTarget.classList.toggle("hidden", this.advancedOpen)
    this.richTarget.classList.toggle("hidden", this.advancedOpen)
    this.advancedBtnTarget.classList.toggle("btn-active", this.advancedOpen)
  }

  // ---- live preview (server-rendered, matches the projector) ----
  schedule() { clearTimeout(this._t); this._t = setTimeout(() => this.render(), 200) }
  render() { if (this.hasSubtypeTarget) this.renderNow() }
  async renderNow() {
    try {
      const res = await fetch(this.urlValue, {
        method: "POST", headers: this.headers(),
        body: JSON.stringify({ body_markdown: this.sourceTarget.value, subtype: this.subtypeTarget.value })
      })
      if (!res.ok) return
      const { html, subtype_class } = await res.json()
      this.previewTarget.className = `slide-preview prose prose-invert max-w-none ${subtype_class}`
      this.previewTarget.innerHTML = html || `<p class="opacity-40">Nothing to preview yet.</p>`
    } catch { /* keep last good preview */ }
  }

  // ======================= HTML <-> Markdown (supported subset) =======================
  // Supported: H1/H2 headings, bold, italic, bulleted lists, paragraphs/line breaks.
  htmlToMd(root) {
    const lines = []
    root.childNodes.forEach(node => this.blockToMd(node, lines))
    return lines.join("\n").replace(/\n{3,}/g, "\n\n").trim()
  }
  blockToMd(node, lines) {
    if (node.nodeType === Node.TEXT_NODE) {
      const t = node.textContent.trim()
      if (t) lines.push(t)
      return
    }
    if (node.nodeType !== Node.ELEMENT_NODE) return
    const tag = node.tagName
    if (tag === "H1") { lines.push(`# ${this.inline(node)}`, "") }
    else if (tag === "H2") { lines.push(`## ${this.inline(node)}`, "") }
    else if (tag === "UL") {
      node.querySelectorAll(":scope > li").forEach(li => lines.push(`- ${this.inline(li)}`))
      lines.push("")
    } else if (tag === "OL") {
      let i = 1
      node.querySelectorAll(":scope > li").forEach(li => lines.push(`${i++}. ${this.inline(li)}`))
      lines.push("")
    } else if (tag === "BR") {
      lines.push("")
    } else { // P, DIV, or anything else → paragraph
      const md = this.inline(node)
      if (md.trim()) lines.push(md, "")
    }
  }
  inline(node) {
    let out = ""
    node.childNodes.forEach(child => {
      if (child.nodeType === Node.TEXT_NODE) { out += child.textContent }
      else if (child.nodeType === Node.ELEMENT_NODE) {
        const t = child.tagName
        if (t === "B" || t === "STRONG") out += `**${this.inline(child)}**`
        else if (t === "I" || t === "EM") out += `_${this.inline(child)}_`
        else if (t === "BR") out += "\n"
        else out += this.inline(child)
      }
    })
    return out.trim()
  }
  mdToHtml(md) {
    const lines = (md || "").split("\n")
    const html = []
    let inList = false
    const closeList = () => { if (inList) { html.push("</ul>"); inList = false } }
    for (const raw of lines) {
      const line = raw.trimEnd()
      if (/^#\s+/.test(line)) { closeList(); html.push(`<h1>${this.inlineMd(line.replace(/^#\s+/, ""))}</h1>`) }
      else if (/^##\s+/.test(line)) { closeList(); html.push(`<h2>${this.inlineMd(line.replace(/^##\s+/, ""))}</h2>`) }
      else if (/^[-*]\s+/.test(line)) { if (!inList) { html.push("<ul>"); inList = true } html.push(`<li>${this.inlineMd(line.replace(/^[-*]\s+/, ""))}</li>`) }
      else if (line.trim() === "") { closeList() }
      else { closeList(); html.push(`<p>${this.inlineMd(line)}</p>`) }
    }
    closeList()
    return html.join("") || "<p><br></p>"
  }
  inlineMd(s) {
    return this.esc(s)
      .replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>")
      .replace(/_([^_]+)_/g, "<em>$1</em>")
  }

  headers() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
  }
  esc(s) { const d = document.createElement("div"); d.textContent = s == null ? "" : String(s); return d.innerHTML }
}
