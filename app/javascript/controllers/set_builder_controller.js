import { Controller } from "@hotwired/stimulus"

// Heroicons (outline) for the picker results. Program rows come from the server (_set_item_row).
const svg = (d, w = "1.8") => `<svg xmlns="http://www.w3.org/2000/svg" class="size-4" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="${w}" aria-hidden="true"><path stroke-linecap="round" stroke-linejoin="round" d="${d}"/></svg>`
const ICON = {
  song: svg("M9 9 19.5 6.75v8.25M9 9v8.25M9 9l-.75.161M9 17.25a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Zm10.5-2.25a2.25 2.25 0 1 1-4.5 0 2.25 2.25 0 0 1 4.5 0Z"),
  slide: svg("M3.75 3.75h16.5v12.75H3.75zM12 16.5v3.75m-3 0h6"),
}

// Set Builder: searchable library picker + optimistic, drag-and-drop program list over the
// existing JSON endpoints. Progressive enhancement — the server-rendered forms + button_to
// reorder/remove work with this controller absent (Req 7.3). Native Drag and Drop API, no deps.
//
// Templates add a Slots tab (song slots, and slide slots tied to a tag). In a service, an empty
// slot's Choose button opens the slot picker, which lists songs, or library slides with the
// slot's tag, and fills the slot in place.
export default class extends Controller {
  static targets = ["program", "query", "results", "announce", "tabs", "tab",
    "pickerPane", "fallback", "newSlideModal", "newSlideBody", "newSlideButton",
    "slotPane", "slotLabel", "slotNewTag", "slotTags",
    "slotModal", "slotTitle", "slotHint", "slotQuery", "slotResults", "slotNewSlide", "launchModal"]
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
    const slot = kind === "slot"
    if (this.hasPickerPaneTarget) this.pickerPaneTarget.classList.toggle("hidden", slot)
    if (this.hasSlotPaneTarget) this.slotPaneTarget.classList.toggle("hidden", !slot)
    if (this.hasNewSlideButtonTarget) this.newSlideButtonTarget.classList.toggle("hidden", kind !== "slide")
    if (slot) return
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
      rows = await this.fetchJson(url)
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

  // ---- template slots ----
  addSongSlot() { this.addSlot({ kind: "song_slot" }) }
  addSlideSlot(e) { this.addSlot({ kind: "slide_slot", slot_tag: e.currentTarget.dataset.tag }) }
  addNewTagSlot() {
    const tag = this.slotNewTagTarget.value.trim().toLowerCase()
    if (!tag) { this.slotNewTagTarget.focus(); return }
    this.addSlot({ kind: "slide_slot", slot_tag: tag })
    this.slotNewTagTarget.value = ""
    this.addTagChip(tag)
  }
  async addSlot(body) {
    const label = this.hasSlotLabelTarget ? this.slotLabelTarget.value.trim() : ""
    const item = await this.postAdd({ ...body, slot_label: label })
    if (!item) return
    this.appendRow(item)
    if (this.hasSlotLabelTarget) this.slotLabelTarget.value = ""
  }
  // A tag typed for a new slot becomes a chip, so the next slot with it is one click.
  addTagChip(tag) {
    if (!this.hasSlotTagsTarget) return
    if ([...this.slotTagsTarget.querySelectorAll("[data-tag]")].some(b => b.dataset.tag === tag)) return
    const b = document.createElement("button")
    b.type = "button"
    b.className = "badge badge-ghost cursor-pointer hover:bg-base-300"
    b.dataset.tag = tag
    b.dataset.action = "set-builder#addSlideSlot"
    b.textContent = tag
    this.slotTagsTarget.appendChild(b)
  }

  // ---- slot picker (a service's empty or filled slot) ----
  chooseSlot(e) {
    const b = e.currentTarget
    this.slot = { itemId: b.dataset.itemId, kind: b.dataset.slotKind, tag: b.dataset.slotTag || "" }
    this.slotTitleTarget.textContent = b.dataset.slotTitle || ""
    this.slotHintTarget.textContent = b.dataset.slotHint || ""
    this.slotHintTarget.classList.toggle("hidden", !b.dataset.slotHint)
    this.slotNewSlideTarget.textContent = b.dataset.slotNew || ""
    this.slotNewSlideTarget.classList.toggle("hidden", this.slot.kind !== "slide")
    this.slotQueryTarget.value = ""
    this.slotResultsTarget.innerHTML = ""
    this.slotModalTarget.showModal()
    this.slotQueryTarget.focus()
    this.runSlotSearch()
  }
  closeSlot() { if (this.hasSlotModalTarget) this.slotModalTarget.close() }
  slotSearch() {
    clearTimeout(this._st)
    this._st = setTimeout(() => this.runSlotSearch(), 200)
  }
  async runSlotSearch() {
    if (!this.slot) return
    const { kind, tag } = this.slot
    const q = this.slotQueryTarget.value
    const url = this.urlWith(this.libraryUrlValue, "", { kind, q, tag })
    const seq = (this._slotSeq = (this._slotSeq || 0) + 1)
    let rows
    try {
      rows = await this.fetchJson(url)
    } catch {
      if (seq === this._slotSeq) this.slotResultsTarget.innerHTML = `<li class="text-sm text-error px-1 py-3">Couldn't load. Try again.</li>`
      return
    }
    if (seq !== this._slotSeq) return
    this.renderSlotResults(rows, q, kind)
  }
  renderSlotResults(rows, q, kind) {
    const r = this.slotResultsTarget
    const m = this.slotModalTarget.dataset
    if (!rows.length) {
      const msg = !q && kind === "slide" ? m.noTagged : m.noMatches
      r.innerHTML = `<li class="text-sm text-base-content/60 px-1 py-3" data-role="slot-empty">${this.esc(msg)}</li>`
      return
    }
    r.innerHTML = rows.map(row => `
      <li class="list-row items-center px-1" data-role="slot-result">
        <div class="list-col-grow min-w-0">
          <div class="font-medium truncate">${this.esc(row.title)}</div>
          <div class="text-xs text-base-content/60 truncate">${this.esc(row.subtitle || "")}</div>
        </div>
        ${row.key ? `<span class="badge badge-ghost badge-sm font-mono">${this.esc(row.key)}</span>` : ""}
        <button type="button" class="btn btn-primary btn-xs" data-id="${row.id}">${this.esc(m.useLabel)}</button>
      </li>`).join("")
    r.querySelectorAll("button[data-id]").forEach(b => b.addEventListener("click", () => this.useForSlot(b.dataset.id)))
  }
  async useForSlot(id) {
    const body = this.slot.kind === "song" ? { song_id: id } : { text_slide_id: id }
    if (await this.fillSlot(this.slot.itemId, body)) this.closeSlot()
  }
  // "+ New slide (tagged scripture)": the full slide editor, tag already added; saving it fills
  // the slot instead of appending a row.
  newSlideForSlot() {
    this.slotFill = { ...this.slot }
    this.closeSlot()
    this.presetSlideTag(this.slot.tag)
    this.openNewSlide()
  }
  presetSlideTag(tag) {
    const input = this.hasNewSlideBodyTarget && this.newSlideBodyTarget.querySelector("[data-slide-editor-target=tagInput]")
    if (!input || !tag) return
    input.value = tag
    input.dispatchEvent(new KeyboardEvent("keydown", { key: "Enter", bubbles: true }))
  }
  async fillSlot(itemId, body) {
    const res = await fetch(this.urlWith(this.addUrlValue, `/${encodeURIComponent(itemId)}/fill`), {
      method: "PATCH", headers: this.headers(), body: JSON.stringify(body)
    })
    if (!res.ok) { this.flash("Could not fill the slot."); return false }
    const item = await res.json()
    const row = this.rows().find(r => r.dataset.itemId === String(itemId))
    const fresh = this.rowFromHtml(item.html)
    if (row && fresh) {
      row.replaceWith(fresh)
      this.wireRow(fresh)
      this.renumber()
      this.updateState()
    }
    return true
  }

  // ---- Go live with empty slots: ask first (they are skipped live) ----
  confirmLaunch(e) {
    if (!this.hasLaunchModalTarget || this.emptySlotCount() === 0) return
    e.preventDefault()
    this.updateState()
    this.launchModalTarget.showModal()
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
    // Closing the editor (saved, ✕, Esc or backdrop) ends any slot it was opened for.
    this.newSlideModalTarget.addEventListener("close", () => { this.slotFill = null })
    const form = this.newSlideBodyTarget.querySelector("form")
    if (!form) return
    form.addEventListener("submit", async (e) => {
      e.preventDefault()
      const fill = this.slotFill
      // The slide-editor controller serializes tags + pages into hidden fields on submit;
      // give it a tick to run its own submit handler before we read the form.
      await new Promise((r) => setTimeout(r, 0))
      const fd = new FormData(form)
      const res = await fetch(this.slideCreateUrlValue, {
        method: "POST", headers: { Accept: "application/json", "X-CSRF-Token": this.csrf() }, body: fd
      })
      if (!res.ok) { this.flash("Could not create the slide."); return }
      const slide = await res.json()
      if (fill) {
        await this.fillSlot(fill.itemId, { text_slide_id: slide.id })
      } else {
        const item = await this.postAdd({ kind: "text_slide", text_slide_id: slide.id })
        if (item) this.appendRow(item)
      }
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

  // The server renders the row (item.html) with the same partial as the page.
  appendRow(item) {
    const li = this.rowFromHtml(item.html)
    if (!li) return
    this.programTarget.appendChild(li)
    this.wireRow(li)
    this.hideEmpty()
    this.renumber()
    this.updateCount()
    this.updateState()
  }
  rowFromHtml(html) {
    const t = document.createElement("template")
    t.innerHTML = (html || "").trim()
    return t.content.firstElementChild
  }

  // ---- reorder (arrows + drag) ----
  wireRows() { this.rows().forEach(r => this.wireRow(r)) }
  wireRow(row) {
    // The arrows and ✕ are no-JS button_to forms; with JS on they act in place instead.
    const on = (sel, fn) => row.querySelector(sel)?.addEventListener("click", (e) => { e.preventDefault(); fn() })
    on(".arrange-up", () => this.move(row, -1))
    on(".arrange-down", () => this.move(row, +1))
    on(".arrange-del", () => this.remove(row))
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
    row.remove(); this.renumber(); this.updateCount(); this.updateState()
    const res = await fetch(this.urlWith(this.addUrlValue, `/${encodeURIComponent(id)}`), {
      method: "DELETE", headers: this.headers()
    })
    if (!res.ok && res.status !== 204) {
      next ? parent.insertBefore(row, next) : parent.appendChild(row)
      this.wireRow(row); this.renumber(); this.updateCount(); this.updateState()
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
  async fetchJson(url) {
    const res = await fetch(url, { headers: { Accept: "application/json" }, cache: "no-store" })
    if (!res.ok) throw new Error(`HTTP ${res.status}`)
    return res.json()
  }
  replaceProgram(items) {
    this.programTarget.innerHTML = ""
    items.forEach(i => this.appendRow(i))
    if (!items.length) this.showEmpty()
  }
  rows() { return Array.from(this.programTarget.querySelectorAll("[data-role=set-item]")) }
  // Number the rows and hide the ↑ on the first and the ↓ on the last.
  renumber() {
    const rows = this.rows()
    rows.forEach((r, i) => {
      const p = r.querySelector("[data-role=pos]")
      if (p) p.textContent = `${i + 1}.`
      r.querySelector(".arrange-up")?.closest("form")?.classList.toggle("invisible", i === 0)
      r.querySelector(".arrange-down")?.closest("form")?.classList.toggle("invisible", i === rows.length - 1)
    })
  }
  updateCount() {
    const el = document.querySelector("[data-role=item-count]")
    if (el) { const n = this.rows().length; el.textContent = `${n} item${n === 1 ? "" : "s"}` }
  }
  emptySlotCount() { return this.rows().filter(r => r.dataset.emptySlot === "true").length }
  // Recount "N slots to fill" (badge + Go live warnings) and enable Go live once something
  // can be shown.
  updateState() {
    const rows = this.rows()
    const empty = this.emptySlotCount()
    this.element.querySelectorAll("[data-slot-count-one]").forEach(el => {
      el.textContent = (empty === 1 ? el.dataset.slotCountOne : el.dataset.slotCountOther).replace("%{count}", empty)
      el.classList.toggle("hidden", empty === 0)
    })
    const launchable = rows.some(r => r.dataset.emptySlot !== "true" && r.dataset.missing !== "true") &&
      !rows.some(r => r.dataset.missing === "true")
    this.element.querySelectorAll("[data-role=launch], [data-role=launch-takeover]")
      .forEach(b => b.classList.toggle("btn-disabled", !launchable))
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
