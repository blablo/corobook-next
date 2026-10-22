import { Controller } from "@hotwired/stimulus"

// WYSIWYG slide editor with free-form TAGS and multi-PAGE support.
//  - Tags: chips + autocomplete; serialized to hidden tags[] inputs.
//  - Pages: an ordered array of markdown bodies; the contenteditable edits the ACTIVE page;
//    serialized to hidden pages[][body_markdown] inputs. A slide with one page is the common case.
// The body stays WYSIWYG — HTML is converted to Markdown behind the scenes (projector renders via
// commonmarker). An Advanced toggle exposes the raw markdown of the active page.
export default class extends Controller {
  static targets = ["rich", "source", "preview", "previewLabel", "advancedBtn", "toolbar",
    "tagChips", "tagInput", "tagFields", "pageFields", "pageStrip", "seed"]
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
    this.renderStrip()
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
    this.tagChipsTarget.innerHTML = this.tags.map((t, i) => `
          <span class="badge badge-neutral gap-1">${this.esc(t)}
            <button type="button" class="tag-x" data-i="${i}" aria-label="Remove ${this.esc(t)}">✕</button>
          </span>`).join("")
    this.tagChipsTarget.querySelectorAll(".tag-x").forEach(b =>
      b.addEventListener("click", (e) => { e.stopPropagation(); this.removeTag(+b.dataset.i) }))
    this.tagFieldsTarget.innerHTML = this.tags.map(t =>
      `<input type="hidden" name="text_slide[tags][]" value="${this.esc(t)}">`).join("")
  }

  // ======================= PAGES =======================
  loadPage() {
    this.richTarget.innerHTML = this.mdToHtml(this.pages[this.active] || "")
    this.sourceTarget.value = this.pages[this.active] || ""
    if (this.hasPreviewLabelTarget) this.previewLabelTarget.textContent = this.pages.length > 1 ? `(page ${this.active + 1})` : ""
    this.renderPreview()
  }

  renderStrip() {
    if (!this.hasPageStripTarget) return
    const cards = this.pages.map((md, i) => {
      const snippet = this.esc((this.plain(md) || "Empty").slice(0, 48))
      const activeCls = i === this.active ? "border-primary border-2" : "border-base-300 border"
      return `
        <div class="pg-card group shrink-0 w-28 h-20 box-border rounded-lg overflow-hidden ${activeCls} bg-base-100 p-2 text-left relative cursor-pointer select-none"
             draggable="true" data-i="${i}" title="Page ${i + 1}">
          <div class="text-[10px] font-semibold text-base-content/40">Page ${i + 1}</div>
          <div class="text-[11px] leading-tight text-base-content/70 line-clamp-3 mt-0.5 pr-4">${snippet}</div>
          <button type="button" class="pg-del absolute top-0.5 right-0.5 text-error opacity-0 group-hover:opacity-100 text-xs leading-none px-1"
                  data-i="${i}" aria-label="Remove page ${i + 1}">✕</button>
        </div>`
    }).join("")
    const addCard = `
      <button type="button" class="pg-add shrink-0 w-28 h-20 box-border rounded-lg border-2 border-dashed border-base-300 text-base-content/40 hover:text-primary hover:border-primary flex items-center justify-center text-sm"
              aria-label="Add a page">+ Add page</button>`
    this.pageStripTarget.innerHTML = cards + addCard
    this.wireStrip()
  }
  wireStrip() {
    this.pageStripTarget.querySelectorAll(".pg-card").forEach(card => {
      const i = +card.dataset.i
      card.addEventListener("click", (e) => { if (!e.target.closest(".pg-del")) this.switchTo(i) })
      card.querySelector(".pg-del").addEventListener("click", (e) => { e.stopPropagation(); this.removePageAt(i) })
      card.addEventListener("dragstart", (e) => { this._drag = i; e.dataTransfer.effectAllowed = "move"; card.classList.add("opacity-50") })
      card.addEventListener("dragend", () => card.classList.remove("opacity-50"))
      card.addEventListener("dragover", (e) => e.preventDefault())
      card.addEventListener("drop", (e) => { e.preventDefault(); this.dropPage(i) })
    })
    this.pageStripTarget.querySelector(".pg-add").addEventListener("click", () => this.addPage())
  }
  switchTo(i) {
    this.pages[this.active] = this.htmlToMd(this.richTarget) // save current before leaving
    this.active = i
    this.loadPage(); this.renderStrip()
  }
  addPage() {
    this.pages[this.active] = this.htmlToMd(this.richTarget)
    this.pages.splice(this.active + 1, 0, "")
    this.active++
    this.renderPageFields(); this.loadPage(); this.renderStrip()
  }
  removePageAt(i) {
    if (this.pages.length === 1) { this.pages[0] = "" }
    else { this.pages.splice(i, 1); if (this.active >= this.pages.length) this.active = this.pages.length - 1; else if (i < this.active) this.active-- }
    this.renderPageFields(); this.loadPage(); this.renderStrip()
  }
  dropPage(to) {
    const from = this._drag
    if (from == null || from === to) return
    const activeMd = this.active
    const [moved] = this.pages.splice(from, 1)
    this.pages.splice(to, 0, moved)
    // keep editing the same page content the user was on
    this.active = this.pages.indexOf(moved) === to ? to : activeMd
    this._drag = null
    this.renderPageFields(); this.loadPage(); this.renderStrip()
  }
  renderPageFields() {
    this.pageFieldsTarget.innerHTML = this.pages.map(p =>
      `<textarea class="hidden" name="text_slide[pages][][body_markdown]">${this.esc(p)}</textarea>`).join("")
  }
  // Plain-text snippet of a page's markdown for the thumbnail.
  plain(md) { return (md || "").replace(/[#*_>-]/g, "").replace(/\s+/g, " ").trim() }

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
    this.updateActiveThumb()
    this.schedulePreview()
  }
  updateActiveThumb() {
    const card = this.pageStripTarget?.querySelector(`.pg-card[data-i="${this.active}"] .line-clamp-3`)
    if (card) card.textContent = (this.plain(this.pages[this.active]) || "Empty").slice(0, 48)
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
      // The preview now lives inside the projector mini-stage; tell its fit controller to resize
      // (a content swap is invisible to the ResizeObserver).
      const fitEl = this.previewTarget.closest('[data-controller~="fit"]')
      if (fitEl) fitEl.dispatchEvent(new CustomEvent("fit:refit"))
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
