import { Controller } from "@hotwired/stimulus"

// Heroicons (outline), shared by the program rows and picker results. Must match _set_item_row.
const svg = (d, w = "1.8") => `<svg xmlns="http://www.w3.org/2000/svg" class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="${w}" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="${d}"/></svg>`
const ICON = {
  song: svg("M9 9 19.5 6.75v8.25M9 9v8.25M9 9l-.75.161M9 17.25a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm10.5-2.25a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"),
  slide: svg("M3.75 3.75h16.5v12.75H3.75zM12 16.5v3.75m-3 0h6"),
  up: svg("m4.5 15.75 7.5-7.5 7.5 7.5", "2"),
  down: svg("m19.5 8.25-7.5 7.5-7.5-7.5", "2"),
  remove: svg("M6 18 18 6M6 6l12 12", "2"),
  grip: `<svg xmlns="http://www.w3.org/2000/svg" class="size-4" viewBox="0 0 24 24" fill="currentColor" aria-hidden="true"><circle cx="9" cy="6" r="1.5"/><circle cx="15" cy="6" r="1.5"/><circle cx="9" cy="12" r="1.5"/><circle cx="15" cy="12" r="1.5"/><circle cx="9" cy="18" r="1.5"/><circle cx="15" cy="18" r="1.5"/></svg>`,
}

// Set Builder: searchable library picker + optimistic, drag-and-drop program list over the
// existing JSON endpoints. Progressive enhancement — the server-rendered forms + button_to
// reorder/remove work with this controller absent (Req 7.3). Native Drag and Drop API, no deps.
export default class extends Controller {
  static targets = ["program", "query", "results", "announce", "tabs", "tab",
    "pickerPane", "fallback", "newSlideModal", "newSlideBody", "newSlideButton"]
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
    const kind = e.currentTarget.dataset.kind
    if (!kind) return
    this.kind = kind
    this.tabTargets.forEach(t => {
      const active = t === e.currentTarget
      t.classList.toggle("tab-active", active)
      t.setAttribute("aria-selected", active ? "true" : "false")
    })
    if (this.hasNewSlideButtonTarget) this.newSlideButtonTarget.classList.toggle("hidden", kind !== "slide")
    // Clear stale results immediately so the previous tab's list can never linger
    // if the new fetch is slow or fails.
    if (this.hasResultsTarget) this.resultsTarget.innerHTML = ""
    this.search()
  }

  // ---- search (songs/slides) ----
  search() {
    clearTimeout(this._t)
    this._t = setTimeout(() => this.runSearch(), 200)
  }
  async runSearch() {
    const q = this.hasQueryTarget ? this.queryTarget.value : ""
    const kind = this.kind
    // Merge into the existing query string: the URL helper may already carry ?locale=es,
    // and appending a second "?" made Rails read kind as part of the locale value.
    const url = this.urlWith(this.libraryUrlValue, "", { kind, q })
    // Tag this request so a slow earlier response can't overwrite a newer one.
    const seq = (this._seq = (this._seq || 0) + 1)
    let rows
    try {
      const res = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store" })
      if (!res.ok) throw new Error(`HTTP ${res.status}`)
      rows = await res.json()
    } catch {
      if (seq === this._seq && kind === this.kind) {
        this.resultsTarget.innerHTML =
          `<p class="text-sm text-error px-1 py-2">Couldn't load ${kind === "slide" ? "slides" : "songs"}. Try again.</p>`
      }
      return
    }
    // Ignore a response that lost the race to a newer request/tab switch.
    if (seq !== this._seq || kind !== this.kind) return
    this.renderResults(rows, q)
  }
  renderResults(rows, q) {
    const r = this.resultsTarget
    if (!rows.length) {
      r.innerHTML = `<p class="text-sm text-base-content/40 px-1 py-2">${q ? "No matches." : "Start typing to search."}</p>`
      return
    }
    r.innerHTML = rows.map(row => `
      <button type="button" class="flex items-center gap-3 text-left rounded-box px-2 py-2 hover:bg-base-200 result"
              data-kind="${row.kind}" data-id="${row.id}">
        <span class="inline-grid place-items-center size-8 rounded-box bg-base-200 text-primary shrink-0">${row.kind === "song" ? ICON.song : ICON.slide}</span>
        <span class="flex-1 truncate">${this.esc(row.title)}</span>
        ${row.key ? `<span class="badge badge-ghost badge-sm font-mono">${this.esc(row.key)}</span>` : ""}
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
    li.className = "list-row items-center hover:bg-base-200"
    li.setAttribute("data-role", "set-item")
    li.setAttribute("data-item-id", item.id)
    li.setAttribute("data-missing", "false")
    li.setAttribute("draggable", "true")
    li.innerHTML = `
      <span class="cursor-grab select-none text-base-content/40" data-drag-handle title="Drag to reorder">${ICON.grip}</span>
      <span class="w-6 text-right text-sm tabular-nums text-base-content/60" data-role="pos">${count}.</span>
      <span class="inline-grid place-items-center size-9 rounded-box bg-base-200 text-primary">${item.kind === "song" ? ICON.song : ICON.slide}</span>
      <div class="list-col-grow min-w-0">
        <span class="block font-medium truncate">${this.esc(item.title || "")}</span>
        <span class="block text-xs text-base-content/60 truncate">${this.esc(item.subtitle || "")}</span>
      </div>
      ${item.key ? `<span class="badge badge-ghost badge-sm font-mono">${this.esc(item.key)}</span>` : ""}
      <span class="flex items-center">
        <button type="button" class="btn btn-ghost btn-sm btn-square arrange-up" title="Move up" aria-label="Move up">${ICON.up}</button>
        <button type="button" class="btn btn-ghost btn-sm btn-square arrange-down" title="Move down" aria-label="Move down">${ICON.down}</button>
        <button type="button" class="btn btn-ghost btn-sm btn-square text-error arrange-del" title="Remove" aria-label="Remove">${ICON.remove}</button>
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
    const res = await fetch(this.urlWith(this.addUrlValue, `/${encodeURIComponent(id)}`), {
      method: "DELETE", headers: this.headers()
    })
    if (!res.ok && res.status !== 204) {
      next ? parent.insertBefore(row, next) : parent.appendChild(row)
      this.wireRow(row); this.renumber(); this.updateCount()
      this.flash("Could not remove item.")
    }
  }

  // ---- helpers ----
  // Append a path suffix and query params to a server-generated URL, keeping any query
  // it already has (e.g. ?locale=es).
  urlWith(base, pathSuffix = "", params = {}) {
    const u = new URL(base, window.location.origin)
    if (pathSuffix) u.pathname = u.pathname.replace(/\/$/, "") + pathSuffix
    Object.entries(params).forEach(([k, v]) => u.searchParams.set(k, v ?? ""))
    return u.pathname + u.search
  }
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
