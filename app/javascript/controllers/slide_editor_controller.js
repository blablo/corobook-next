import { Controller } from "@hotwired/stimulus"

// WYSIWYG slide editor with free-form TAGS and multi-PAGE support.
//  - Tags: chips + autocomplete; serialized to hidden tags[] inputs.
//  - Pages: an ordered array of markdown bodies; the contenteditable edits the ACTIVE page;
//    serialized to hidden pages[][body_markdown] inputs. A slide with one page is the common case.
// The body stays WYSIWYG — HTML is converted to Markdown behind the scenes (projector renders via
// commonmarker). An Advanced toggle exposes the raw markdown of the active page.
export default class extends Controller {
  static targets = ["rich", "source", "preview", "previewLabel", "advancedBtn", "toolbar",
    "tagChips", "tagInput", "tagFields", "pageFields", "pageLabel", "seed"]
  static values = { url: String }

  connect() {
    const seed = this.readSeed()
    this.tags = seed.tags || []
    this.pages = (seed.pages && seed.pages.length) ? seed.pages.slice() : [ "" ]
    this.active = 0
    this.advancedOpen = false
    this.renderTags()
    this.loadPage()
    this.renderPageFields()
  }

  readSeed() {
    try { return JSON.parse(this.seedTarget.textContent || "{}") } catch { return {} }
  }

  // ======================= TAGS =======================
  onTagKey(e) {
    if (e.key === "Enter" || e.key === ",") { e.preventDefault(); this.addTag(this.tagInputTarget.value) }
    else if (e.key === "Backspace" && this.tagInputTarget.value === "" && this.tags.length) { this.removeTag(this.tags.length - 1) }
  }
  focusTag() { this.tagInputTarget.focus() }
  addTag(raw) {
    const t = (raw || "").trim().toLowerCase()
    this.tagInputTarget.value = ""
    if (!t || this.tags.includes(t)) return
    this.tags.push(t)
    this.renderTags()
  }
  removeTag(i) { this.tags.splice(i, 1); this.renderTags() }
  renderTags() {
    this.tagChipsTarget.innerHTML = this.tags.length
      ? this.tags.map((t, i) => `
          <span class="badge badge-neutral gap-1">${this.esc(t)}
            <button type="button" class="tag-x" data-i="${i}" aria-label="Remove ${this.esc(t)}">✕</button>
          </span>`).join("")
      : `<span class="text-sm text-base-content/40">No tags yet</span>`
    this.tagChipsTarget.querySelectorAll(".tag-x").forEach(b =>
      b.addEventListener("click", (e) => { e.stopPropagation(); this.removeTag(+b.dataset.i) }))
    this.tagFieldsTarget.innerHTML = this.tags.map(t =>
      `<input type="hidden" name="text_slide[tags][]" value="${this.esc(t)}">`).join("")
  }

  // ======================= PAGES =======================
  loadPage() {
    this.richTarget.innerHTML = this.mdToHtml(this.pages[this.active] || "")
    this.sourceTarget.value = this.pages[this.active] || ""
    this.updatePageLabel()
    this.renderPreview()
  }
  saveActiveFromRich() { this.pages[this.active] = this.htmlToMd(this.richTarget); this.renderPageFields() }
  updatePageLabel() {
    const label = `Page ${this.active + 1} of ${this.pages.length}`
    if (this.hasPageLabelTarget) this.pageLabelTarget.textContent = label
    if (this.hasPreviewLabelTarget) this.previewLabelTarget.textContent = this.pages.length > 1 ? `(page ${this.active + 1})` : ""
  }
  prevPage(e) { e.preventDefault(); if (this.active > 0) { this.active--; this.loadPage() } }
  nextPage(e) { e.preventDefault(); if (this.active < this.pages.length - 1) { this.active++; this.loadPage() } }
  addPage(e) {
    e.preventDefault()
    this.pages.splice(this.active + 1, 0, "")
    this.active++
    this.renderPageFields(); this.loadPage()
  }
  removePage(e) {
    e.preventDefault()
    if (this.pages.length === 1) { this.pages[0] = ""; this.active = 0 }
    else { this.pages.splice(this.active, 1); this.active = Math.max(0, this.active - 1) }
    this.renderPageFields(); this.loadPage()
  }
  renderPageFields() {
    this.pageFieldsTarget.innerHTML = this.pages.map(p =>
      `<textarea class="hidden" name="text_slide[pages][][body_markdown]">${this.esc(p)}</textarea>`).join("")
  }

  // ======================= BODY (WYSIWYG) =======================
  bold(e) { e.preventDefault(); this.exec("bold") }
  italic(e) { e.preventDefault(); this.exec("italic") }
  heading(e) { e.preventDefault(); this.exec("formatBlock", "H2") }
  bullet(e) { e.preventDefault(); this.exec("insertUnorderedList") }
  clearFormat(e) { e.preventDefault(); this.exec("removeFormat"); this.exec("formatBlock", "P") }
  exec(cmd, val = null) { this.richTarget.focus(); document.execCommand(cmd, false, val); this.syncFromRich() }
  onKeydown(e) {
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "b") { e.preventDefault(); this.bold(e) }
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "i") { e.preventDefault(); this.italic(e) }
  }
  onRichInput() { this.syncFromRich() }
  syncFromRich() {
    this.pages[this.active] = this.htmlToMd(this.richTarget)
    this.sourceTarget.value = this.pages[this.active]
    this.renderPageFields()
    this.schedulePreview()
  }
  onSourceInput() {
    this.pages[this.active] = this.sourceTarget.value
    this.richTarget.innerHTML = this.mdToHtml(this.sourceTarget.value)
    this.renderPageFields()
    this.schedulePreview()
  }
  toggleAdvanced(e) {
    e.preventDefault()
    this.advancedOpen = !this.advancedOpen
    this.sourceTarget.classList.toggle("hidden", !this.advancedOpen)
    this.toolbarTarget.classList.toggle("hidden", this.advancedOpen)
    this.richTarget.classList.toggle("hidden", this.advancedOpen)
    this.advancedBtnTarget.classList.toggle("btn-active", this.advancedOpen)
  }

  // ======================= PREVIEW =======================
  schedulePreview() { clearTimeout(this._t); this._t = setTimeout(() => this.renderPreview(), 200) }
  async renderPreview() {
    try {
      const res = await fetch(this.urlValue, {
        method: "POST", headers: this.headers(),
        body: JSON.stringify({ body_markdown: this.pages[this.active] || "" })
      })
      if (!res.ok) return
      const { html } = await res.json()
      this.previewTarget.innerHTML = html || `<p class="opacity-40">Nothing to preview yet.</p>`
    } catch { /* keep last good preview */ }
  }

  // ======================= HTML <-> Markdown (supported subset) =======================
  htmlToMd(root) {
    const lines = []
    root.childNodes.forEach(n => this.blockToMd(n, lines))
    return lines.join("\n").replace(/\n{3,}/g, "\n\n").trim()
  }
  blockToMd(node, lines) {
    if (node.nodeType === Node.TEXT_NODE) { const t = node.textContent.trim(); if (t) lines.push(t); return }
    if (node.nodeType !== Node.ELEMENT_NODE) return
    const tag = node.tagName
    if (tag === "H1") lines.push(`# ${this.inline(node)}`, "")
    else if (tag === "H2") lines.push(`## ${this.inline(node)}`, "")
    else if (tag === "UL") { node.querySelectorAll(":scope > li").forEach(li => lines.push(`- ${this.inline(li)}`)); lines.push("") }
    else if (tag === "OL") { let i = 1; node.querySelectorAll(":scope > li").forEach(li => lines.push(`${i++}. ${this.inline(li)}`)); lines.push("") }
    else if (tag === "BR") lines.push("")
    else { const md = this.inline(node); if (md.trim()) lines.push(md, "") }
  }
  inline(node) {
    let out = ""
    node.childNodes.forEach(c => {
      if (c.nodeType === Node.TEXT_NODE) out += c.textContent
      else if (c.nodeType === Node.ELEMENT_NODE) {
        const t = c.tagName
        if (t === "B" || t === "STRONG") out += `**${this.inline(c)}**`
        else if (t === "I" || t === "EM") out += `_${this.inline(c)}_`
        else if (t === "BR") out += "\n"
        else out += this.inline(c)
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
    return this.esc(s).replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>").replace(/_([^_]+)_/g, "<em>$1</em>")
  }

  headers() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
  }
  esc(s) { const d = document.createElement("div"); d.textContent = s == null ? "" : String(s); return d.innerHTML }
}
