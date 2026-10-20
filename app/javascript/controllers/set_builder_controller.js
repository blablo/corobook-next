import { Controller } from "@hotwired/stimulus"

// Set Builder: searchable library picker + optimistic, drag-and-drop program list over the
// existing JSON endpoints. Progressive enhancement — the server-rendered forms + button_to
// reorder/remove work with this controller absent (Req 7.3). Native Drag and Drop API, no deps.
export default class extends Controller {
  static targets = ["program", "query", "results", "announce", "tabs", "tab",
    "pickerPane", "fallback", "newSlideModal", "newSlideBody"]
  static values = { reorderUrl: String, addUrl: String, libraryUrl: String, slideCreateUrl: String, canEdit: Boolean }

  connect() {
    if (!this.canEditValue) return
    this.kind = "song"
    if (this.hasFallbackTarget) this.fallbackTarget.classList.add("hidden") // JS on → hide no-JS forms
    this.wireRows()
    this.wireNewSlideModal()
    this.search()
  }

  // ---- tabs ----
  switchTab(e) {
    this.kind = e.currentTarget.dataset.kind
    this.tabTargets.forEach(t => t.classList.toggle("tab-active", t === e.currentTarget))
    this.search()
  }

  // ---- search (songs/slides) ----
  search() {
    clearTimeout(this._t)
    this._t = setTimeout(() => this.runSearch(), 200)
  }
  async runSearch() {
    const q = this.hasQueryTarget ? this.queryTarget.value : ""
    const url = `${this.libraryUrlValue}?kind=${this.kind}&q=${encodeURIComponent(q)}`
    let rows = []
    try { rows = await (await fetch(url, { headers: { Accept: "application/json" } })).json() }
    catch { return }
    this.renderResults(rows, q)
  }
  renderResults(rows, q) {
    const r = this.resultsTarget
    if (!rows.length) {
      r.innerHTML = `<p class="text-sm text-base-content/40 px-1 py-2">${q ? "No matches." : "Start typing to search."}</p>`
      return
    }
    r.innerHTML = rows.map(row => `
      <button type="button" class="flex items-center gap-2 text-left rounded px-2 py-1.5 hover:bg-base-200 result"
              data-kind="${row.kind}" data-id="${row.id}">
        <span class="text-base-content/40">${row.kind === "song" ? "♪" : "▤"}</span>
        <span class="flex-1 truncate">${this.esc(row.title)}</span>
        ${row.key ? `<span class="badge badge-ghost badge-sm">${this.esc(row.key)}</span>` : ""}
      </button>`).join("") +
      (rows.length >= 20 ? `<p class="text-xs text-base-content/40 px-1 py-1">Refine your search to see more.</p>` : "")
    r.querySelectorAll(".result").forEach(b =>
      b.addEventListener("click", () => this.addFromResult(b.dataset.kind, b.dataset.id)))
  }

  // ---- add ----
  async addFromResult(kind, id) {
    const body = kind === "song" ? { kind: "song", song_id: id } : { kind: "text_slide", text_slide_id: id }
    const item = await this.postAdd(body)
    if (item) this.appendRow(item)
  }
  // ---- New slide modal (same editor as /text_slides/new) ----
  openNewSlide() {
    if (this.hasNewSlideModalTarget) this.newSlideModalTarget.showModal()
  }
  closeNewSlide() {
    if (this.hasNewSlideModalTarget) this.newSlideModalTarget.close()
  }
  wireNewSlideModal() {
    if (!this.hasNewSlideBodyTarget) return
    const form = this.newSlideBodyTarget.querySelector("form")
    if (!form) return
    form.addEventListener("submit", async (e) => {
      e.preventDefault()
      // The slide-editor controller serializes tags + pages into hidden fields on submit;
      // give it a tick to run its own submit handler before we read the form.
      await new Promise((r) => setTimeout(r, 0))
      const fd = new FormData(form)
      const res = await fetch(this.slideCreateUrlValue, {
        method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": this.csrf() }, body: fd
      })
      if (!res.ok) { this.flash("Could not create the slide."); return }
      const slide = await res.json()
      const item = await this.postAdd({ kind: "text_slide", text_slide_id: slide.id })
      if (item) this.appendRow(item)
      this.closeNewSlide()
    })
  }
  csrf() {
    return document.querySelector("meta[name=csrf-token]")?.content || ""
  }
  async postAdd(body) {
    const res = await this.postAddRaw(body)
    if (res.ok) return res.json()
    this.flash("Could not add item.")
    return null
  }
  postAddRaw(body) {
    return fetch(this.addUrlValue, {
      method: "POST", headers: this.headers(), body: JSON.stringify(body)
    })
  }

  appendRow(item) {
    const count = this.rows().length + 1
    const li = document.createElement("li")
    li.className = "flex items-center gap-2 rounded-lg bg-base-100 ring-1 ring-base-200 px-3 py-2"
    li.setAttribute("data-role", "set-item")
    li.setAttribute("data-item-id", item.id)
    li.setAttribute("data-missing", "false")
    li.setAttribute("draggable", "true")
    li.innerHTML = `
      <span class="cursor-grab select-none text-base-content/30 shrink-0" data-drag-handle title="Drag to reorder">⠿</span>
      <span class="text-xs text-base-content/40 w-6 text-right shrink-0" data-role="pos">${count}.</span>
      <span class="shrink-0 text-base-content/40">${item.kind === "song" ? "♪" : "▤"}</span>
      <span class="flex-1 min-w-0 truncate">${this.esc(item.title || "")}</span>
      ${item.key ? `<span class="badge badge-ghost badge-sm shrink-0">${this.esc(item.key)}</span>` : ""}
      <span class="flex items-center gap-0.5 shrink-0">
        <button type="button" class="btn btn-ghost btn-xs px-1 arrange-up" aria-label="Move up">↑</button>
        <button type="button" class="btn btn-ghost btn-xs px-1 arrange-down" aria-label="Move down">↓</button>
        <button type="button" class="btn btn-ghost btn-xs px-1 text-error arrange-del" aria-label="Remove">✕</button>
      </span>`
    this.programTarget.appendChild(li)
    this.wireRow(li)
    this.hideEmpty()
    this.renumber()
    this.updateCount()
  }

  // ---- reorder (arrows + drag) ----
  wireRows() { this.rows().forEach(r => this.wireRow(r)) }
  wireRow(row) {
    row.querySelector(".arrange-up")?.addEventListener("click", () => this.move(row, -1))
    row.querySelector(".arrange-down")?.addEventListener("click", () => this.move(row, +1))
    row.querySelector(".arrange-del")?.addEventListener("click", () => this.remove(row))
    row.addEventListener("dragstart", (e) => { this._drag = row; e.dataTransfer.effectAllowed = "move"; row.classList.add("opacity-50") })
    row.addEventListener("dragend", () => row.classList.remove("opacity-50"))
    row.addEventListener("dragover", (e) => e.preventDefault())
    row.addEventListener("drop", (e) => { e.preventDefault(); this.drop(row) })
  }
  move(row, delta) {
    const rows = this.rows()
    const i = rows.indexOf(row)
    const j = i + delta
    if (j < 0 || j >= rows.length) return
    delta < 0 ? this.programTarget.insertBefore(row, rows[j]) : this.programTarget.insertBefore(rows[j], row)
    row.querySelector(".arrange-up")?.focus()
    this.announce(`Moved to position ${this.rows().indexOf(row) + 1} of ${this.rows().length}`)
    this.renumber()
    this.persistOrder()
  }
  drop(target) {
    if (!this._drag || this._drag === target) return
    const rows = this.rows()
    if (rows.indexOf(this._drag) < rows.indexOf(target)) target.after(this._drag)
    else target.before(this._drag)
    this._drag = null
    this.renumber()
    this.persistOrder()
  }
  async persistOrder() {
    const ids = this.rows().map(r => r.dataset.itemId)
    const res = await fetch(this.reorderUrlValue, {
      method: "PATCH", headers: this.headers(), body: JSON.stringify({ ordered_ids: ids })
    })
    if (res.status === 409) {
      const { items } = await res.json()
      this.replaceProgram(items)
      this.flash("The set changed — reloaded.")
    } else if (!res.ok) {
      this.flash("Could not save order.")
    }
  }

  // ---- remove ----
  async remove(row) {
    const id = row.dataset.itemId
    const next = row.nextElementSibling, parent = row.parentNode
    row.remove(); this.renumber(); this.updateCount()
    const res = await fetch(`${this.addUrlValue.replace(/\/items$/, "")}/items/${id}`, {
      method: "DELETE", headers: this.headers()
    })
    if (!res.ok && res.status !== 204) {
      next ? parent.insertBefore(row, next) : parent.appendChild(row)
      this.wireRow(row); this.renumber(); this.updateCount()
      this.flash("Could not remove item.")
    }
  }

  // ---- helpers ----
  replaceProgram(items) {
    this.programTarget.innerHTML = ""
    items.forEach(i => this.appendRow(i))
    if (!items.length) this.showEmpty()
  }
  rows() { return Array.from(this.programTarget.querySelectorAll("[data-role=set-item]")) }
  renumber() { this.rows().forEach((r, i) => { const p = r.querySelector("[data-role=pos]"); if (p) p.textContent = `${i + 1}.` }) }
  updateCount() {
    const el = document.querySelector("[data-role=item-count]")
    if (el) { const n = this.rows().length; el.textContent = `${n} item${n === 1 ? "" : "s"}` }
  }
  hideEmpty() { document.querySelector("[data-role=empty]")?.classList.add("hidden") }
  showEmpty() { document.querySelector("[data-role=empty]")?.classList.remove("hidden") }
  announce(msg) { if (this.hasAnnounceTarget) this.announceTarget.textContent = msg }
  flash(msg) { this.announce(msg); console.warn(msg) }
  headers() {
    const token = document.querySelector("meta[name=csrf-token]")?.content
    return { "Content-Type": "application/json", Accept: "application/json", "X-CSRF-Token": token }
  }
  esc(s) { const d = document.createElement("div"); d.textContent = s == null ? "" : String(s); return d.innerHTML }
}
