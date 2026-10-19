import { Controller } from "@hotwired/stimulus"

// No-syntax ChordPro editor.
//
// Two modes over ONE canonical field (the hidden `source` input bound to
// song[chordpro_source]):
//   • Visual   — WYSIWYG. Sections are labelled blocks added via buttons.
//                Each lyric line is directly CONTENTEDITABLE (type in place);
//                clicking a character opens a key-aware chord picker that
//                anchors a chord above that offset. The user never types ChordPro.
//   • Advanced — a raw textarea on the same field for power users.
//
// Line model: { text: "plain lyrics", chords: [{ at: <charOffset>, chord: "G" }] }
// or { comment: "..." }. Chords render in a monospace row above the lyric row,
// positioned by character column (1ch per char), so inline editing keeps a
// stable caret. Serialized back to the canonical field to match the Ruby
// Serializer ({sov/soc/sob}+{eov/eoc/eob}, [Chord] prefix, {comment:}).
export default class extends Controller {
  static targets = ["source", "visual", "advanced", "visualBtn", "advancedBtn", "keyField"]

  connect() {
    this.model = this.parse(this.sourceTarget.value)
    this.openPicker = null
    this.renderVisual()
    this.showVisual()
    if (this.hasKeyFieldTarget) {
      this.keyFieldTarget.addEventListener("change", () => this.renderVisual())
    }
    this.advancedTarget.addEventListener("input", () => { this.sourceTarget.value = this.advancedTarget.value })
    this._closeOnOutside = (e) => { if (!e.target.closest(".song-picker") && !e.target.closest("[data-chordstop]")) this.closePicker() }
    document.addEventListener("click", this._closeOnOutside)
  }
  disconnect() { document.removeEventListener("click", this._closeOnOutside) }

  // ---- mode toggle ----
  showVisual() {
    this.model = this.parse(this.sourceTarget.value)
    this.renderVisual()
    this.visualTarget.classList.remove("hidden")
    this.advancedTarget.classList.add("hidden")
    this.visualBtnTarget.classList.add("btn-active")
    this.advancedBtnTarget.classList.remove("btn-active")
  }
  showAdvanced() {
    this.advancedTarget.value = this.sourceTarget.value
    this.advancedTarget.classList.remove("hidden")
    this.visualTarget.classList.add("hidden")
    this.advancedBtnTarget.classList.add("btn-active")
    this.visualBtnTarget.classList.remove("btn-active")
  }

  // ======================= PARSE (ChordPro -> model) =======================
  parse(src) {
    const sections = []
    let current = null
    const openRe = /^\{(sov|soc|sob|start_of_verse|start_of_chorus|start_of_bridge)(?::\s*(.*?))?\}\s*$/i
    const closeRe = /^\{(eov|eoc|eob|end_of_verse|end_of_chorus|end_of_bridge)\}\s*$/i
    const commentRe = /^\{(?:comment|c):\s*(.*?)\}\s*$/i
    const metaRe = /^\{(title|subtitle|key|capo|transpose)\s*:.*\}\s*$/i
    const kindOf = (d) => d.toLowerCase().includes("chorus") ? "chorus" : d.toLowerCase().includes("bridge") ? "bridge" : "verse"
    const ensure = () => { if (!current) { current = { kind: "verse", label: null, lines: [] }; sections.push(current) } }

    for (const raw of (src || "").split("\n")) {
      const line = raw.replace(/\s+$/, "")
      let m
      if (line.match(metaRe)) { continue }
      if ((m = line.match(openRe))) { current = { kind: kindOf(m[1]), label: m[2] ? m[2].trim() : null, lines: [] }; sections.push(current); continue }
      if (closeRe.test(line)) { current = null; continue }
      if ((m = line.match(commentRe))) { ensure(); current.lines.push({ comment: m[1] }); continue }
      if (line.trim() === "") { if (current && current.lines.length) current = null; continue }
      ensure(); current.lines.push(this.parseLine(line))
    }
    return sections
  }

  // "Se[G]ñor [C]Dios" -> { text:"Señor Dios", chords:[{at:2,chord:"G"},{at:6,chord:"C"}] }
  parseLine(line) {
    const chords = []
    let text = "", i = 0
    const re = /\[([^\]]*)\]/g
    let last = 0, m
    while ((m = re.exec(line)) !== null) {
      text += line.slice(last, m.index)
      chords.push({ at: text.length, chord: m[1] })
      last = re.lastIndex
    }
    text += line.slice(last)
    return { text, chords }
  }

  // ======================= SERIALIZE (model -> ChordPro) =======================
  serialize() {
    const OPEN = { verse: "sov", chorus: "soc", bridge: "sob" }
    const CLOSE = { verse: "eov", chorus: "eoc", bridge: "eob" }
    const out = []
    for (const s of this.model) {
      out.push(s.label ? `{${OPEN[s.kind]}: ${s.label}}` : `{${OPEN[s.kind]}}`)
      for (const ln of s.lines) {
        if ("comment" in ln) { out.push(`{comment: ${ln.comment}}`); continue }
        out.push(this.lineToChordPro(ln))
      }
      out.push(`{${CLOSE[s.kind]}}`)
    }
    const text = out.join("\n")
    this.sourceTarget.value = text
    return text
  }
  lineToChordPro(ln) {
    const chords = [...(ln.chords || [])].sort((a, b) => a.at - b.at)
    let res = "", cursor = 0
    for (const c of chords) {
      const at = Math.max(0, Math.min(c.at, ln.text.length))
      res += ln.text.slice(cursor, at) + `[${c.chord}]`
      cursor = at
    }
    res += ln.text.slice(cursor)
    return res
  }

  // ======================= chord palette (key-aware) =======================
  paletteFor(key) {
    const TABLE = {
      C:["C","Dm","Em","F","G","Am","G7"], G:["G","Am","Bm","C","D","Em","D7"],
      D:["D","Em","F#m","G","A","Bm","A7"], A:["A","Bm","C#m","D","E","F#m","E7"],
      E:["E","F#m","G#m","A","B","C#m","B7"], F:["F","Gm","Am","Bb","C","Dm","C7"],
      Bb:["Bb","Cm","Dm","Eb","F","Gm","F7"], Eb:["Eb","Fm","Gm","Ab","Bb","Cm","Bb7"]
    }
    const norm = (key || "").trim().replace(/m$/, "")
    const common = TABLE[norm] || TABLE.G
    const extras = ["Am","Em","Dm","Bm","Cm","F#","B7","C7","D7","E7","A7","G7","Fm","Gm","sus4","add9"].filter(c => !common.includes(c))
    return { common, extras }
  }

  // ======================= render visual editor =======================
  renderVisual() {
    const key = this.hasKeyFieldTarget ? this.keyFieldTarget.value : "G"
    this._palette = this.paletteFor(key)
    const sec = (s, si) => {
      const label = s.label ? `${this.kindName(s.kind)} · ${this.esc(s.label)}` : this.kindName(s.kind)
      const lines = s.lines.map((ln, li) => this.renderLine(si, ln, li)).join("")
      return `
        <div class="rounded-lg ring-1 ring-base-200 bg-base-100 mb-3" data-si="${si}">
          <div class="flex items-center gap-2 px-3 py-2 border-b border-base-200">
            <span class="badge badge-neutral badge-sm">${label}</span>
            <div class="flex-1"></div>
            <button type="button" class="btn btn-ghost btn-xs" data-action="song-editor#addLine" data-si="${si}">+ line</button>
            <button type="button" class="btn btn-ghost btn-xs" data-action="song-editor#addComment" data-si="${si}">+ note</button>
            <button type="button" class="btn btn-ghost btn-xs" data-action="song-editor#relabel" data-si="${si}">rename</button>
            <button type="button" class="btn btn-ghost btn-xs text-error" data-action="song-editor#removeSection" data-si="${si}">✕</button>
          </div>
          <div class="p-3">${lines || '<span class="text-base-content/40 text-sm">Empty — click “+ line” to add lyrics.</span>'}</div>
        </div>`
    }
    this.visualTarget.querySelector("[data-role=sections]").innerHTML =
      this.model.length ? this.model.map(sec).join("") : `<p class="text-base-content/50 text-sm mb-3">No sections yet. Add a verse or chorus to begin.</p>`
  }

  renderLine(si, ln, li) {
    if ("comment" in ln) {
      return `<div class="flex items-center gap-2 mb-2" data-li="${li}">
        <span>💬</span>
        <span contenteditable="true" class="comment-edit flex-1 italic text-base-content/70 text-sm outline-none focus:bg-primary/5 rounded px-1"
              data-action="input->song-editor#commentInput" data-si="${si}" data-li="${li}">${this.esc(ln.comment)}</span>
        <button type="button" class="link link-error text-xs" data-action="song-editor#removeLine" data-si="${si}" data-li="${li}">remove</button>
      </div>`
    }
    // chord row (monospace, 1ch per column) above an editable monospace lyric row
    const chords = [...(ln.chords || [])].sort((a, b) => a.at - b.at)
    let chordRow = "", col = 0
    for (const c of chords) {
      const at = Math.max(0, Math.min(c.at, ln.text.length))
      if (at > col) chordRow += " ".repeat(at - col)
      chordRow += `<span class="chord inline-block text-primary font-bold cursor-pointer align-bottom" style="width:0;white-space:nowrap"
                      data-action="song-editor#removeChord" data-si="${si}" data-li="${li}" data-at="${c.at}" title="Remove ${this.esc(c.chord)}">${this.esc(c.chord)}</span>`
      col = at
    }
    return `
      <div class="mb-2 group" data-li="${li}">
        <div class="chordrow font-mono text-[13px] leading-[1.1] h-[1.25em] whitespace-pre text-primary select-none">${chordRow}</div>
        <div class="flex items-center gap-2">
          <div contenteditable="true" spellcheck="false"
               class="lyric-edit font-mono text-[15px] leading-tight whitespace-pre-wrap outline-none focus:bg-primary/5 rounded px-1 flex-1 min-h-[1.5em]"
               data-chordstop data-action="input->song-editor#lyricInput click->song-editor#lyricClick"
               data-si="${si}" data-li="${li}">${this.esc(ln.text)}</div>
          <button type="button" class="link link-error text-xs opacity-0 group-hover:opacity-100 transition-opacity shrink-0"
                  data-action="song-editor#removeLine" data-si="${si}" data-li="${li}">remove</button>
        </div>
      </div>`
  }

  // ======================= inline editing =======================
  lyricInput(e) {
    const { si, li } = e.currentTarget.dataset
    const old = this.model[si].lines[li]
    const newText = e.currentTarget.textContent
    // shift chord offsets by the edit delta at the caret (best-effort: clamp to new length)
    const delta = newText.length - old.text.length
    const caret = this.caretOffset(e.currentTarget)
    old.chords = (old.chords || []).map(c => {
      let at = c.at
      if (delta !== 0 && at >= caret - Math.max(delta, 0)) at += delta
      return { ...c, at: Math.max(0, Math.min(at, newText.length)) }
    })
    old.text = newText
    this.serialize() // no re-render: preserve caret
  }
  commentInput(e) {
    const { si, li } = e.currentTarget.dataset
    this.model[si].lines[li].comment = e.currentTarget.textContent
    this.serialize()
  }
  lyricClick(e) {
    // place a chord at the clicked character offset
    e.stopPropagation()
    this.closePicker()
    const el = e.currentTarget
    const { si, li } = el.dataset
    const at = this.caretOffset(el)
    this.openChordPicker(el, si, li, at)
  }

  openChordPicker(anchorEl, si, li, at) {
    const pal = this._palette
    const chip = (c, rare) => `<span class="chip cursor-pointer text-[12px] font-semibold px-2 py-0.5 rounded border border-base-300 hover:border-primary hover:text-primary ${rare ? "opacity-60" : ""}" data-chord="${c}">${c}</span>`
    const pop = document.createElement("div")
    pop.className = "song-picker absolute z-30 bg-base-100 ring-1 ring-base-300 shadow-lg rounded-lg p-2 flex flex-wrap gap-1 w-60 mt-1"
    pop.innerHTML =
      `<div class="w-full text-[11px] text-base-content/50 mb-1 px-0.5">Chord at this position</div>` +
      pal.common.map(c => chip(c, false)).join("") + pal.extras.map(c => chip(c, true)).join("")
    // Direct listeners — dynamically-injected nodes are not reliably bound by Stimulus
    // actions in time, so wire the clicks ourselves.
    pop.querySelectorAll(".chip").forEach(ch => {
      ch.addEventListener("mousedown", (ev) => {
        ev.preventDefault(); ev.stopPropagation()
        this.placeChord(si, li, at, ch.dataset.chord)
      })
    })
    anchorEl.parentElement.style.position = "relative"
    anchorEl.parentElement.appendChild(pop)
    this.openPicker = pop
  }
  placeChord(si, li, at, chord) {
    const ln = this.model[si].lines[li]
    const offset = +at
    const existing = (ln.chords || []).find(c => c.at === offset)
    if (existing) existing.chord = chord
    else (ln.chords = ln.chords || []).push({ at: offset, chord })
    this.closePicker()
    this.commit()
  }
  removeChord(e) {
    e.stopPropagation()
    const { si, li, at } = e.currentTarget.dataset
    const ln = this.model[si].lines[li]
    ln.chords = (ln.chords || []).filter(c => c.at !== +at)
    this.commit()
  }

  // caret char offset within a contenteditable (text-only)
  caretOffset(el) {
    const sel = window.getSelection()
    if (!sel || sel.rangeCount === 0) return el.textContent.length
    const range = sel.getRangeAt(0).cloneRange()
    range.selectNodeContents(el)
    range.setEnd(sel.getRangeAt(0).endContainer, sel.getRangeAt(0).endOffset)
    return range.toString().length
  }

  // ======================= structure actions =======================
  addSection(e) {
    const kind = e.currentTarget.dataset.kind
    this.model.push({ kind, label: null, lines: [{ text: "", chords: [] }] })
    this.commit()
    this.focusLine(this.model.length - 1, 0)
  }
  addLine(e) {
    const si = +e.currentTarget.dataset.si
    this.model[si].lines.push({ text: "", chords: [] })
    this.commit()
    this.focusLine(si, this.model[si].lines.length - 1)
  }
  addComment(e) {
    const si = +e.currentTarget.dataset.si
    this.model[si].lines.push({ comment: "" })
    this.commit()
    this.focusLine(si, this.model[si].lines.length - 1, ".comment-edit")
  }
  removeLine(e) {
    const { si, li } = e.currentTarget.dataset
    this.model[si].lines.splice(+li, 1)
    this.commit()
  }
  removeSection(e) {
    const si = +e.currentTarget.dataset.si
    this.model.splice(si, 1)
    this.commit()
  }
  relabel(e) {
    const si = +e.currentTarget.dataset.si
    const label = window.prompt("Section label (optional, e.g. “Verse 2”):", this.model[si].label || "")
    if (label === null) return
    this.model[si].label = label.trim() || null
    this.commit()
  }

  commit() { this.serialize(); this.renderVisual() }
  closePicker() { if (this.openPicker) { this.openPicker.remove(); this.openPicker = null } }

  focusLine(si, li, sel = ".lyric-edit") {
    requestAnimationFrame(() => {
      const el = this.visualTarget.querySelector(`[data-si="${si}"] [data-li="${li}"] ${sel}`)
      if (el) { el.focus(); this.placeCaretEnd(el) }
    })
  }
  placeCaretEnd(el) {
    const range = document.createRange(); range.selectNodeContents(el); range.collapse(false)
    const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range)
  }

  // ======================= helpers =======================
  kindName(k) { return { verse: "Verse", chorus: "Chorus", bridge: "Bridge" }[k] || "Verse" }
  esc(s) { return (s == null ? "" : String(s)).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])) }
}
