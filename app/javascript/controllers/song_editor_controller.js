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
  static targets = ["source", "visual", "advanced", "visualBtn", "advancedBtn", "keyField", "importModal", "importText", "importReplace", "arrangeWrap", "arrangeAvail", "arrangeOrder", "arrangeField"]

  connect() {
    this.model = this.parse(this.sourceTarget.value)
    this.openPicker = null
    this.order = this.parseOrder(this.hasArrangeFieldTarget ? this.arrangeFieldTarget.value : "")
    this.renderVisual()
    this.renderArrange()
    this.showVisual()
    if (this.hasKeyFieldTarget) {
      this.keyFieldTarget.addEventListener("change", () => this.renderVisual())
    }
    this.advancedTarget.addEventListener("input", () => { this.sourceTarget.value = this.advancedTarget.value })
    this._closeOnOutside = (e) => { if (!e.target.closest(".song-picker") && !e.target.closest("[data-chordstop]") && !e.target.closest(".chordrow")) this.closePicker() }
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

  // ======================= IMPORT (chords-over-lyrics -> model) =======================
  openImport() {
    this.importModalTarget.classList.remove("hidden")
    this.importModalTarget.classList.add("flex")
    this.importTextTarget.focus()
  }
  closeImport() {
    this.importModalTarget.classList.add("hidden")
    this.importModalTarget.classList.remove("flex")
  }
  runImport() {
    const sections = this.parseChordsOverLyrics(this.importTextTarget.value)
    if (!sections.length) { this.closeImport(); return }
    if (this.hasImportReplaceTarget && this.importReplaceTarget.checked) this.model = sections
    else this.model = [...this.model, ...sections]
    this.importTextTarget.value = ""
    this.closeImport()
    // Serialize the imported model into the canonical field FIRST, then show visual mode
    // (showVisual re-parses the source field, so the field must already hold the import).
    this.serialize()
    this.visualTarget.classList.remove("hidden")
    this.advancedTarget.classList.add("hidden")
    this.visualBtnTarget.classList.add("btn-active")
    this.advancedBtnTarget.classList.remove("btn-active")
    this.renderVisual()
  }

  // Parse pasted "chords over lyrics" text into our section/line model.
  // Recognizes section headers (VERSE 1 / CHORUS / BRIDGE / ...), chord lines
  // (all tokens look like chords) paired with the following lyric line, and
  // chord-only lines (a chord line not followed by lyrics).
  parseChordsOverLyrics(text) {
    const rawLines = (text || "").replace(/\r/g, "").split("\n")
    const headerRe = /^\s*(verse|chorus|coro|estrofa|bridge|puente|pre[-\s]?chorus|intro|outro|interlude|instrumental|tag|ending|vamp|refrain|verso)\s*([0-9]+|[a-z])?\s*:?\s*$/i
    const kindOf = (h) => {
      const l = h.toLowerCase()
      if (l.includes("chorus") || l.includes("coro") || l.includes("refrain")) return "chorus"
      if (l.includes("bridge") || l.includes("puente")) return "bridge"
      return "verse"
    }
    const isChordToken = (t) => /^\(?[A-G][#b]?(?:maj|min|m|M|dim|aug|sus|add|º|°|\+)?[0-9]*(?:sus[0-9])?(?:add[0-9]+)?(?:\/[A-G][#b]?)?\)?$/.test(t)
    const isChordLine = (line) => {
      const toks = line.trim().split(/\s+/).filter(Boolean)
      return toks.length > 0 && toks.every(isChordToken)
    }
    const chordsFromLine = (chordLine, lyric) => {
      const chords = []
      const re = /\S+/g; let m
      while ((m = re.exec(chordLine)) !== null) {
        const at = Math.min(m.index, lyric.length)
        chords.push({ at, chord: m[0].replace(/[()]/g, "") })
      }
      return chords
    }

    const sections = []
    let current = null
    const ensure = () => { if (!current) { current = { kind: "verse", label: null, lines: [] }; sections.push(current) } }
    const lines = rawLines
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i]
      if (line.trim() === "") continue
      const hm = line.match(headerRe)
      if (hm) {
        const num = hm[2] ? ` ${hm[2]}` : ""
        current = { kind: kindOf(hm[1]), label: (hm[1][0].toUpperCase() + hm[1].slice(1).toLowerCase() + num).trim(), lines: [] }
        sections.push(current)
        continue
      }
      ensure()
      if (isChordLine(line)) {
        const next = lines[i + 1]
        if (next !== undefined && next.trim() !== "" && !isChordLine(next) && !next.match(headerRe)) {
          current.lines.push({ text: next, chords: chordsFromLine(line, next) })
          i++ // consume the lyric line
        } else {
          // chord-only line (e.g. a lone repeat): anchor chords on empty text
          current.lines.push({ text: "", chords: chordsFromLine(line, "") })
        }
      } else {
        current.lines.push({ text: line, chords: [] })
      }
    }
    this.numberSections(sections)
    return sections
  }

  // Ensure every section carries a unique numbered label per kind
  // ("Verse 1", "Verse 2", "Chorus 1"...) so the arrangement can reference it.
  // Preserves an existing valid number, renumbers conflicts/blanks in order.
  numberSections(sections) {
    // Only auto-number sections that have NO explicit label. A section that already carries
    // a label (Intro, Outro, Pre-chorus, Solo, Chorus 2, …) keeps it verbatim — the kind only
    // determines the ChordPro directive, not the display label.
    const used = {}
    const take = (kind, n) => { (used[kind] = used[kind] || new Set()).add(n) }
    const free = (kind) => { let n = 1; const s = used[kind] || new Set(); while (s.has(n)) n++; return n }
    // First pass: reserve numbers already claimed by explicit "<Kind> N" labels.
    for (const s of sections) {
      const prefix = this.kindName(s.kind)
      const m = s.label && s.label.match(new RegExp(`^${prefix}\\s+(\\d+)$`, "i"))
      if (m) take(s.kind, +m[1])
    }
    // Second pass: leave explicit labels alone; number only the unlabeled ones.
    for (const s of sections) {
      if (s.label && s.label.trim() !== "") continue
      const n = free(s.kind); s.label = `${this.kindName(s.kind)} ${n}`; take(s.kind, n)
    }
    return sections
  }

  // ======================= PARSE (ChordPro -> model) =======================
  parse(src) {
    const sections = []
    let current = null
    const openRe = /^\{(sov|soc|sob|start_of_verse|start_of_chorus|start_of_bridge)(?::\s*(.*?))?\}\s*$/i
    const closeRe = /^\{(eov|eoc|eob|end_of_verse|end_of_chorus|end_of_bridge)\}\s*$/i
    const commentRe = /^\{(?:comment|c):\s*(.*?)\}\s*$/i
    const metaRe = /^\{(title|subtitle|key|capo|transpose)\s*:.*\}\s*$/i
    // Any other bare {directive} / {directive: value} line (e.g. {x_corobook_mood: 30}) is
    // metadata, not lyric text — ignore it, matching the Ruby parser's unknown-directive rule.
    const directiveRe = /^\{\s*[a-zA-Z_]+\s*(?::.*)?\}\s*$/
    const kindOf = (d) => d.toLowerCase().includes("chorus") ? "chorus" : d.toLowerCase().includes("bridge") ? "bridge" : "verse"
    const ensure = () => { if (!current) { current = { kind: "verse", label: null, lines: [] }; sections.push(current) } }

    for (const raw of (src || "").split("\n")) {
      const line = raw.replace(/\s+$/, "")
      let m
      if (line.match(metaRe)) { continue }
      if ((m = line.match(openRe))) { current = { kind: kindOf(m[1]), label: m[2] ? m[2].trim() : null, lines: [] }; sections.push(current); continue }
      if (closeRe.test(line)) { current = null; continue }
      if ((m = line.match(commentRe))) { ensure(); current.lines.push({ comment: m[1] }); continue }
      if (directiveRe.test(line)) { continue }
      if (line.trim() === "") { if (current && current.lines.length) current = null; continue }
      ensure(); current.lines.push(this.parseLine(line))
    }
    this.numberSections(sections)
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
      const label = this.esc(s.label || this.kindName(s.kind))
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
    // Direct listeners for chord pills — dynamic nodes aren't reliably bound by Stimulus actions.
    this.visualTarget.querySelectorAll(".chord-pill").forEach(pill => {
      pill.addEventListener("mousedown", (ev) => {
        ev.preventDefault(); ev.stopPropagation()
        const { si, li, at } = pill.dataset
        this.removeChordAt(si, li, +at)
      })
    })
    // Clicking the chord row (not a pill) opens the picker at the clicked column.
    this.visualTarget.querySelectorAll(".chordrow").forEach(row => {
      row.addEventListener("mousedown", (ev) => {
        if (ev.target.closest(".chord-pill")) return // pill handles its own removal
        ev.preventDefault(); ev.stopPropagation()
        this.chordRowClickAt(row, ev.clientX)
      })
    })
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
    // chord row (monospace, 1ch per column) above an editable monospace lyric row.
    // Each chord is a clickable pill, absolutely positioned at its character column
    // (ch units) so it never disturbs lyric spacing but is a real click target.
    const chords = [...(ln.chords || [])].sort((a, b) => a.at - b.at)
    const chordPills = chords.map((c) => {
      const at = Math.max(0, Math.min(c.at, ln.text.length))
      return `<span class="chord-pill absolute top-0 inline-flex items-center gap-0.5 text-primary font-bold cursor-pointer leading-none hover:bg-primary/10 rounded px-0.5"
                 style="left:${at}ch" data-si="${si}" data-li="${li}" data-at="${c.at}" title="Click to remove ${this.esc(c.chord)}">${this.esc(c.chord)}<span class="text-error text-[10px] opacity-0 group-hover:opacity-70">✕</span></span>`
    }).join("")
    return `
      <div class="mb-2 group" data-li="${li}">
        <div class="chordrow relative font-mono text-[13px] leading-[1.35] h-[1.6em] whitespace-pre text-primary cursor-pointer rounded hover:bg-primary/5 select-none"
             data-si="${si}" data-li="${li}"
             title="Click here to add a chord above the lyrics">
          ${chordPills}
          ${chords.length === 0 ? '<span class="chord-hint absolute inset-0 flex items-center text-base-content/30 text-[11px] opacity-0 group-hover:opacity-100 transition-opacity pointer-events-none px-1">+ click to add a chord</span>' : ''}
        </div>
        <div class="flex items-center gap-2">
          <div contenteditable="true" spellcheck="false"
               class="lyric-edit font-mono text-[15px] leading-tight whitespace-pre-wrap outline-none focus:bg-primary/5 rounded px-1 flex-1 min-h-[1.5em]"
               data-chordstop data-action="input->song-editor#lyricInput keydown->song-editor#lyricKeydown"
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

  lyricKeydown(e) {
    const el = e.currentTarget
    const si = +el.dataset.si, li = +el.dataset.li
    if (e.key === "Enter" && !e.shiftKey && !e.isComposing) {
      e.preventDefault()
      // sync current DOM text into the model first (input may not have fired yet)
      const ln = this.model[si].lines[li]
      ln.text = el.textContent
      const caret = this.caretOffset(el)
      const before = ln.text.slice(0, caret)
      const after = ln.text.slice(caret)
      // chords before the caret stay; chords at/after move to the new line (offset rebased)
      const keep = (ln.chords || []).filter(c => c.at <= caret).map(c => ({ ...c }))
      const moved = (ln.chords || []).filter(c => c.at > caret).map(c => ({ chord: c.chord, at: c.at - caret }))
      ln.text = before; ln.chords = keep
      this.model[si].lines.splice(li + 1, 0, { text: after, chords: moved })
      this.commit()
      this.focusLineAt(si, li + 1, 0) // caret at start of the new line
      return
    }
    if (e.key === "Backspace" && this.caretOffset(el) === 0 && li > 0) {
      // merge this line up into the previous lyric line
      const prev = this.model[si].lines[li - 1]
      const cur = this.model[si].lines[li]
      if (!("comment" in prev) && !("comment" in cur)) {
        e.preventDefault()
        const joinAt = prev.text.length
        prev.text = prev.text + cur.text
        prev.chords = [...(prev.chords || []), ...(cur.chords || []).map(c => ({ chord: c.chord, at: c.at + joinAt }))]
        this.model[si].lines.splice(li, 1)
        this.commit()
        this.focusLineAt(si, li - 1, joinAt)
      }
    }
  }
  commentInput(e) {
    const { si, li } = e.currentTarget.dataset
    this.model[si].lines[li].comment = e.currentTarget.textContent
    this.serialize()
  }
  chordRowClickAt(row, clientX) {
    this.closePicker()
    const { si, li } = row.dataset
    const lyric = row.parentElement.querySelector(".lyric-edit")
    const text = (this.model[si].lines[li].text) || ""
    const chWidth = this.charWidth(lyric)
    const x = clientX - lyric.getBoundingClientRect().left
    let at = chWidth > 0 ? Math.round(x / chWidth) : 0
    at = Math.max(0, Math.min(at, text.length))
    this.openChordPicker(row, si, li, at)
  }
  charWidth(lyricEl) {
    const probe = document.createElement("span")
    probe.style.cssText = "position:absolute;visibility:hidden;white-space:pre;font-family:ui-monospace,Menlo,monospace;font-size:15px"
    probe.textContent = "0000000000"
    lyricEl.appendChild(probe)
    const w = probe.getBoundingClientRect().width / 10
    probe.remove()
    return w
  }

  openChordPicker(anchorEl, si, li, at) {
    const pal = this._palette
    const ln = this.model[si].lines[li]
    const existing = (ln.chords || []).find(c => c.at === +at)

    const ALL_ROOTS = ["C","C#","Db","D","D#","Eb","E","F","F#","Gb","G","G#","Ab","A","A#","Bb","B"]
    const SUFFIXES = ["", "m", "7", "maj7", "m7", "sus2", "sus4", "add9", "9", "6", "m6", "dim", "aug", "5"]

    const quick = (c) => `<span class="chip cursor-pointer text-[12px] font-semibold px-2 py-0.5 rounded border border-base-300 hover:border-primary hover:text-primary" data-pick="${c}">${c}</span>`
    const rootBtn = (r) => `<span class="rootbtn cursor-pointer text-[12px] font-semibold px-1.5 py-0.5 rounded border border-base-300 hover:border-primary hover:text-primary" data-root="${r}">${r}</span>`
    const sufBtn = (s) => `<span class="sufbtn cursor-pointer text-[12px] px-1.5 py-0.5 rounded border border-base-300 hover:border-primary hover:text-primary opacity-50" data-suf="${s}">${s === "" ? "maj" : s}</span>`

    const pop = document.createElement("div")
    pop.className = "song-picker absolute z-30 bg-base-100 ring-1 ring-base-300 shadow-lg rounded-lg p-2 w-72 mt-1"
    const header = existing
      ? `<div class="flex items-center gap-2 mb-1.5 px-0.5"><span class="text-[11px] text-base-content/50 flex-1">Change <b>${this.esc(existing.chord)}</b></span><span class="remove-chord cursor-pointer text-[12px] font-semibold text-error hover:underline">✕ Remove</span></div>`
      : `<div class="text-[11px] text-base-content/50 mb-1.5 px-0.5">Add a chord here</div>`

    pop.innerHTML = header +
      `<div class="text-[10px] uppercase tracking-wide text-base-content/40 mb-1">Key of ${this.esc((this.hasKeyFieldTarget ? this.keyFieldTarget.value : "G") || "G")}</div>
       <div class="flex flex-wrap gap-1 mb-2">${pal.common.map(quick).join("")}</div>
       <div class="text-[10px] uppercase tracking-wide text-base-content/40 mb-1">Build any chord</div>
       <div class="flex flex-wrap gap-1 mb-1.5" data-role="roots">${ALL_ROOTS.map(rootBtn).join("")}</div>
       <div class="flex flex-wrap gap-1 mb-2" data-role="sufs">${SUFFIXES.map(sufBtn).join("")}</div>
       <div class="flex items-center gap-1">
         <input type="text" class="chord-free input input-bordered input-xs flex-1 font-mono" placeholder="type any chord (e.g. F#m7/A)" value="${existing ? this.esc(existing.chord) : ""}">
         <button type="button" class="chord-free-add btn btn-primary btn-xs">Set</button>
       </div>`

    // key quick-chips: one-tap place
    pop.querySelectorAll(".chip[data-pick]").forEach(ch =>
      ch.addEventListener("mousedown", (ev) => { ev.preventDefault(); ev.stopPropagation(); this.placeChord(si, li, at, ch.dataset.pick) }))

    // builder: tap root → suffixes enable; tap suffix → place root+suffix; tap root alone places major triad on second tap
    let chosenRoot = null
    const sufEls = pop.querySelectorAll(".sufbtn")
    const setRoot = (r) => {
      chosenRoot = r
      pop.querySelectorAll(".rootbtn").forEach(b => b.classList.toggle("border-primary", b.dataset.root === r))
      pop.querySelectorAll(".rootbtn").forEach(b => b.classList.toggle("text-primary", b.dataset.root === r))
      sufEls.forEach(b => b.classList.remove("opacity-50"))
    }
    pop.querySelectorAll(".rootbtn").forEach(b =>
      b.addEventListener("mousedown", (ev) => {
        ev.preventDefault(); ev.stopPropagation()
        if (chosenRoot === b.dataset.root) { this.placeChord(si, li, at, chosenRoot) } // second tap = major triad
        else setRoot(b.dataset.root)
      }))
    sufEls.forEach(b =>
      b.addEventListener("mousedown", (ev) => {
        ev.preventDefault(); ev.stopPropagation()
        const root = chosenRoot || (this.hasKeyFieldTarget ? (this.keyFieldTarget.value || "G").replace(/m$/, "") : "G")
        this.placeChord(si, li, at, root + b.dataset.suf)
      }))

    // free text: the ultimate escape hatch — any chord string
    const free = pop.querySelector(".chord-free")
    const commitFree = () => { const v = free.value.trim(); if (v) this.placeChord(si, li, at, v) }
    pop.querySelector(".chord-free-add").addEventListener("mousedown", (ev) => { ev.preventDefault(); ev.stopPropagation(); commitFree() })
    free.addEventListener("keydown", (ev) => { if (ev.key === "Enter") { ev.preventDefault(); commitFree() } })
    free.addEventListener("mousedown", (ev) => ev.stopPropagation())
    free.addEventListener("click", (ev) => ev.stopPropagation())

    const rm = pop.querySelector(".remove-chord")
    if (rm) rm.addEventListener("mousedown", (ev) => { ev.preventDefault(); ev.stopPropagation(); this.removeChordAt(si, li, +at) })
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
  removeChordAt(si, li, at) {
    const ln = this.model[si].lines[li]
    ln.chords = (ln.chords || []).filter(c => c.at !== +at)
    this.closePicker()
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
    this.model.push({ kind, label: this.nextLabel(kind), lines: [{ text: "", chords: [] }] })
    this.commit()
    this.focusLine(this.model.length - 1, 0)
  }

  // Next unique numbered label for a kind, e.g. "Verse 1", "Verse 2".
  // Numbers the kind sequentially, skipping any numbers already in use so a
  // label is always unique and stable for arrangement ordering.
  nextLabel(kind) {
    const prefix = this.kindName(kind)
    const used = new Set()
    for (const s of this.model) {
      if (s.kind !== kind || !s.label) continue
      const m = s.label.match(new RegExp(`^${prefix}\\s+(\\d+)$`, "i"))
      if (m) used.add(+m[1])
    }
    let n = 1
    while (used.has(n)) n++
    return `${prefix} ${n}`
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

  commit() { this.serialize(); this.renderVisual(); this.renderArrange() }

  // ======================= ARRANGEMENT (play order) =======================
  // The order is a list of section labels (repeats allowed). It serializes to the
  // hidden arrangeField as newline-separated labels, which the server already parses.
  parseOrder(text) {
    return (text || "").split(/[\n,]/).map(s => s.trim()).filter(Boolean)
  }
  sectionLabels() {
    return this.model.map(s => s.label || this.kindName(s.kind))
  }
  renderArrange() {
    if (!this.hasArrangeAvailTarget) return
    const labels = this.sectionLabels()
    // Drop order entries whose section no longer exists (e.g. a deleted section).
    this.order = this.order.filter(l => labels.includes(l))

    this.arrangeAvailTarget.innerHTML = labels.length
      ? labels.map(l => `<button type="button" class="btn btn-sm btn-outline arrange-add" data-label="${this.esc(l)}">+ ${this.esc(l)}</button>`).join("")
      : `<span class="text-sm text-base-content/40">Add sections above first.</span>`
    this.arrangeAvailTarget.querySelectorAll(".arrange-add").forEach(b =>
      b.addEventListener("click", () => this.addToOrder(b.dataset.label)))

    this.arrangeOrderTarget.innerHTML = this.order.length
      ? this.order.map((l, i) => this.orderRow(l, i)).join("")
      : `<span class="text-sm text-base-content/40 px-1">Empty — plays in section order.</span>`
    this.wireOrderRows()
    this.syncOrderField()
  }
  orderRow(label, i) {
    return `
      <div class="flex items-center gap-2 rounded bg-base-100 ring-1 ring-base-200 px-2 py-1 arrange-row" draggable="true" data-i="${i}">
        <span class="cursor-grab select-none text-base-content/30" data-drag-handle>⠿</span>
        <span class="text-base-content/40 text-xs w-5 text-right">${i + 1}.</span>
        <span class="flex-1 text-sm">${this.esc(label)}</span>
        <button type="button" class="btn btn-ghost btn-xs px-1 arrange-up" title="Move up" data-i="${i}">↑</button>
        <button type="button" class="btn btn-ghost btn-xs px-1 arrange-down" title="Move down" data-i="${i}">↓</button>
        <button type="button" class="btn btn-ghost btn-xs px-1 text-error arrange-del" title="Remove" data-i="${i}">✕</button>
      </div>`
  }
  wireOrderRows() {
    const rows = this.arrangeOrderTarget.querySelectorAll(".arrange-row")
    rows.forEach(row => {
      const i = +row.dataset.i
      row.querySelector(".arrange-up").addEventListener("click", () => this.moveOrder(i, -1))
      row.querySelector(".arrange-down").addEventListener("click", () => this.moveOrder(i, +1))
      row.querySelector(".arrange-del").addEventListener("click", () => this.removeFromOrder(i))
      row.addEventListener("dragstart", (e) => { this._dragFrom = i; e.dataTransfer.effectAllowed = "move"; row.classList.add("opacity-50") })
      row.addEventListener("dragend", () => row.classList.remove("opacity-50"))
      row.addEventListener("dragover", (e) => { e.preventDefault(); e.dataTransfer.dropEffect = "move" })
      row.addEventListener("drop", (e) => { e.preventDefault(); this.dropOrder(i) })
    })
  }
  addToOrder(label) { this.order.push(label); this.renderArrange() }
  removeFromOrder(i) { this.order.splice(i, 1); this.renderArrange() }
  moveOrder(i, delta) {
    const j = i + delta
    if (j < 0 || j >= this.order.length) return
    const [item] = this.order.splice(i, 1)
    this.order.splice(j, 0, item)
    this.renderArrange()
  }
  dropOrder(to) {
    const from = this._dragFrom
    if (from == null || from === to) return
    const [item] = this.order.splice(from, 1)
    this.order.splice(to, 0, item)
    this._dragFrom = null
    this.renderArrange()
  }
  syncOrderField() {
    if (this.hasArrangeFieldTarget) this.arrangeFieldTarget.value = this.order.join("\n")
  }
  closePicker() { if (this.openPicker) { this.openPicker.remove(); this.openPicker = null } }

  focusLine(si, li, sel = ".lyric-edit") {
    requestAnimationFrame(() => {
      const el = this.visualTarget.querySelector(`[data-si="${si}"] [data-li="${li}"] ${sel}`)
      if (el) { el.focus(); this.placeCaretEnd(el) }
    })
  }
  focusLineAt(si, li, offset) {
    requestAnimationFrame(() => {
      const el = this.visualTarget.querySelector(`[data-si="${si}"] [data-li="${li}"] .lyric-edit`)
      if (!el) return
      el.focus()
      const node = el.firstChild || el
      const pos = Math.max(0, Math.min(offset, (node.textContent || "").length))
      const range = document.createRange()
      try { range.setStart(node.nodeType === 3 ? node : el, node.nodeType === 3 ? pos : 0) } catch (_) { range.selectNodeContents(el) }
      range.collapse(true)
      const sel = window.getSelection(); sel.removeAllRanges(); sel.addRange(range)
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
