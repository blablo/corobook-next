import { Controller } from "@hotwired/stimulus"

// No-syntax ChordPro editor.
//
// Two modes over ONE canonical field (the hidden `source` textarea bound to
// song[chordpro_source]):
//   • Visual  — click-a-word WYSIWYG: sections are labelled blocks added via
//               buttons; clicking a word opens a key-aware chord picker that
//               places the chord above it. The user never types ChordPro.
//   • Advanced — a raw textarea on the same field for power users.
//
// The model is parsed from the field on connect, edited in memory, and
// serialized back to the field on every change — matching the Ruby
// Corobook::ChordPro::Serializer format ({sov/soc/sob}+{eov/eoc/eob},
// [Chord] prefix, {comment:}). The server parser stays the source of truth
// on save.
export default class extends Controller {
  static targets = ["source", "visual", "advanced", "visualBtn", "advancedBtn", "keyField"]

  connect() {
    this.model = this.parse(this.sourceTarget.value)
    this.openPicker = null
    this.renderVisual()
    this.showVisual()
    // keep palette in sync if the key field changes
    if (this.hasKeyFieldTarget) {
      this.keyField = this.keyFieldTarget
      this.keyFieldTarget.addEventListener("change", () => this.renderVisual())
    }
    // re-parse when the user edits raw text and returns to visual
    this.advancedTarget.addEventListener("input", () => { this.sourceTarget.value = this.advancedTarget.value })
  }

  // ---- mode toggle ----
  showVisual() {
    this.model = this.parse(this.sourceTarget.value) // re-sync from possibly-edited raw text
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
  // model = [{ kind, label, lines:[ {segments:[{chord,text}]} | {comment} ] }]
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
      if ((m = line.match(metaRe))) { continue }        // meta lives in form fields
      if ((m = line.match(openRe))) { current = { kind: kindOf(m[1]), label: m[2] ? m[2].trim() : null, lines: [] }; sections.push(current); continue }
      if (closeRe.test(line)) { current = null; continue }
      if ((m = line.match(commentRe))) { ensure(); current.lines.push({ comment: m[1] }); continue }
      if (line.trim() === "") { if (current && current.lines.length) current = null; continue }
      ensure(); current.lines.push({ segments: this.parseSegments(line) })
    }
    return sections
  }

  // "Se[G]ñor mi [C]Dios" -> [{chord:null,text:"Se"},{chord:"G",text:"ñor mi "},{chord:"C",text:"Dios"}]
  parseSegments(line) {
    const segs = []
    const re = /\[([^\]]*)\]/g
    let last = 0, m, pendingChord = null
    while ((m = re.exec(line)) !== null) {
      const text = line.slice(last, m.index)
      if (text.length || segs.length === 0) segs.push({ chord: pendingChord, text })
      else if (pendingChord !== null) segs.push({ chord: pendingChord, text: "" })
      pendingChord = m[1]
      last = re.lastIndex
    }
    segs.push({ chord: pendingChord, text: line.slice(last) })
    // merge a leading empty no-chord segment
    return segs.filter((s, i) => !(i === 0 && s.chord === null && s.text === "" && segs.length > 1) )
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
        out.push(ln.segments.map(seg => (seg.chord ? `[${seg.chord}]` : "") + seg.text).join(""))
      }
      out.push(`{${CLOSE[s.kind]}}`)
    }
    const text = out.join("\n")
    this.sourceTarget.value = text
    return text
  }

  // ======================= chord palette (key-aware) =======================
  paletteFor(key) {
    const MAJOR = ["C","G","D","A","E","F","Bb","Eb"]
    // diatonic-ish common chords per major key (I ii iii IV V vi V7)
    const TABLE = {
      C:["C","Dm","Em","F","G","Am","G7"], G:["G","Am","Bm","C","D","Em","D7"],
      D:["D","Em","F#m","G","A","Bm","A7"], A:["A","Bm","C#m","D","E","F#m","E7"],
      E:["E","F#m","G#m","A","B","C#m","B7"], F:["F","Gm","Am","Bb","C","Dm","C7"],
      Bb:["Bb","Cm","Dm","Eb","F","Gm","F7"], Eb:["Eb","Fm","Gm","Ab","Bb","Cm","Bb7"]
    }
    const norm = (key || "").trim().replace(/m$/,"")
    const common = TABLE[norm] || TABLE.G
    const extras = ["Am","Em","Dm","Bm","Cm","F#","B7","C7","D7","E7","A7","G7","Fm","Gm","sus4","add9"]
      .filter(c => !common.includes(c))
    return { common, extras }
  }

  // ======================= render visual editor =======================
  renderVisual() {
    const key = this.hasKeyFieldTarget ? this.keyFieldTarget.value : "G"
    const sec = (s, si) => {
      const label = s.label ? `${this.kindName(s.kind)} · ${this.esc(s.label)}` : this.kindName(s.kind)
      const lines = s.lines.map((ln, li) => this.renderLine(s, si, ln, li)).join("")
      return `
        <div class="rounded-lg ring-1 ring-base-200 bg-base-100 mb-3" data-si="${si}">
          <div class="flex items-center gap-2 px-3 py-2 border-b border-base-200">
            <span class="badge badge-neutral badge-sm">${label}</span>
            <div class="flex-1"></div>
            <button type="button" class="btn btn-ghost btn-xs" data-action="song-editor#addLine" data-si="${si}">+ line</button>
            <button type="button" class="btn btn-ghost btn-xs" data-action="song-editor#relabel" data-si="${si}">rename</button>
            <button type="button" class="btn btn-ghost btn-xs text-error" data-action="song-editor#removeSection" data-si="${si}">✕</button>
          </div>
          <div class="p-3 font-mono text-[15px] leading-[2.6]">${lines || '<span class="text-base-content/40 text-sm font-sans">Empty — click “+ line” to add lyrics.</span>'}</div>
        </div>`
    }
    this.visualTarget.querySelector("[data-role=sections]").innerHTML =
      this.model.length ? this.model.map(sec).join("") : `<p class="text-base-content/50 text-sm mb-3">No sections yet. Add a verse or chorus to begin.</p>`
    // stash palette for the picker
    this._palette = this.paletteFor(key)
  }

  renderLine(s, si, ln, li) {
    if ("comment" in ln) {
      return `<div class="text-base-content/60 italic text-sm font-sans mb-1" data-li="${li}">💬 ${this.esc(ln.comment)}
        <button type="button" class="link link-error text-xs ml-2 font-sans not-italic" data-action="song-editor#removeLine" data-si="${si}" data-li="${li}">remove</button></div>`
    }
    const words = ln.segments.map((seg, wi) => {
      const chord = seg.chord
        ? `<span class="chord absolute -top-[1.35em] left-0 text-[13px] font-bold text-primary cursor-pointer" data-action="song-editor#removeChord" data-si="${si}" data-li="${li}" data-wi="${wi}">${this.esc(seg.chord)}</span>`
        : ""
      // split text into clickable words preserving spaces
      return `<span class="relative inline-block whitespace-pre hover:bg-primary/10 rounded px-px cursor-pointer"
                data-action="song-editor#wordClick" data-si="${si}" data-li="${li}" data-wi="${wi}">${chord}${this.esc(seg.text) || "&nbsp;"}</span>`
    }).join("")
    return `<div class="mb-1" data-li="${li}">${words}</div>`
  }

  // ======================= interactions =======================
  wordClick(e) {
    e.stopPropagation()
    this.closePicker()
    const el = e.currentTarget
    const { si, li, wi } = el.dataset
    const pal = this._palette
    const chip = (c, rare) => `<span class="chip cursor-pointer text-[12px] font-semibold px-2 py-0.5 rounded border border-base-300 hover:border-primary hover:text-primary ${rare ? "opacity-60" : ""}" data-action="song-editor#pickChord" data-si="${si}" data-li="${li}" data-wi="${wi}" data-chord="${c}">${c}</span>`
    const pop = document.createElement("div")
    pop.className = "song-picker absolute z-20 bg-base-100 ring-1 ring-base-300 shadow-lg rounded-lg p-2 flex flex-wrap gap-1 w-56"
    pop.style.top = "-2.8em"; pop.style.left = "0"
    pop.innerHTML = pal.common.map(c => chip(c, false)).join("") + pal.extras.map(c => chip(c, true)).join("")
    el.appendChild(pop)
    this.openPicker = pop
  }
  pickChord(e) {
    e.stopPropagation()
    const { si, li, wi, chord } = e.currentTarget.dataset
    this.model[si].lines[li].segments[wi].chord = chord
    this.commit()
  }
  removeChord(e) {
    e.stopPropagation()
    const { si, li, wi } = e.currentTarget.dataset
    this.model[si].lines[li].segments[wi].chord = null
    this.commit()
  }
  addSection(e) {
    const kind = e.currentTarget.dataset.kind
    this.model.push({ kind, label: null, lines: [{ segments: [{ chord: null, text: "" }] }] })
    this.commit()
    // immediately prompt for first line text
    this.editLineText(this.model.length - 1, 0)
  }
  addLine(e) {
    const si = +e.currentTarget.dataset.si
    const text = window.prompt("Lyrics for this line:")
    if (text === null) return
    this.model[si].lines.push({ segments: this.parseSegments(text) })
    this.commit()
  }
  editLineText(si, li) {
    const text = window.prompt("Lyrics for this line:", "")
    if (text === null) return
    this.model[si].lines[li] = { segments: this.parseSegments(text || "") }
    this.commit()
  }
  removeLine(e) {
    const { si, li } = e.currentTarget.dataset
    this.model[si].lines.splice(+li, 1)
    this.commit()
  }
  removeSection(e) {
    const si = +e.currentTarget.dataset.si
    if (!window.confirm("Remove this whole section?")) return
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

  // ======================= helpers =======================
  kindName(k) { return { verse: "Verse", chorus: "Chorus", bridge: "Bridge" }[k] || "Verse" }
  esc(s) { return (s == null ? "" : String(s)).replace(/[&<>"]/g, c => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c])) }
}
