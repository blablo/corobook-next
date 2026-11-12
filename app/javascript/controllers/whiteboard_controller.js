import { Controller } from "@hotwired/stimulus"
import { cable } from "@hotwired/turbo-rails"

// The speaker's whiteboard (Corobook::Whiteboard, WhiteboardChannel).
//
// On the speaker view (speaker value set) it draws: pointer strokes are sent as live points while
// the pen moves and as one stored stroke when it lifts. Everywhere else (projector, the
// operator's Now preview; viewer value set) it only shows the strokes.
//
// mode: null (off), "board" (a whiteboard covers the screen) or "slide" (a clear layer over the
// current slide). Points are 0..1 of the screen; line widths follow the screen height.
const MAX_POINTS = 1500
const MIN_STEP = 0.0015
const FLUSH_MS = 40
const BOARD_BG = { light: "#ffffff", dark: "#0f172a" }

export default class extends Controller {
  static targets = ["layer", "canvas", "surface", "start", "tools", "stop", "status", "darkToggle",
    "color", "tool", "banner", "bannerText", "hint"]
  static values = { speaker: String, viewer: String, labels: Object }

  connect() {
    this.isDisconnected = false
    this.src = Math.random().toString(36).slice(2)
    this.seq = 0
    this.mode = null
    this.dark = false
    this.blanked = false
    this.ended = false
    this.online = false   // subscribed; until then the speaker's buttons can't do anything
    this.refused = false  // the server turned the subscription down
    this.stopKey = ""
    this.board = []
    this.slide = []
    this.live = new Map()
    this.tool = "pen"
    this.color = this.colorTargets.find(b => b.getAttribute("aria-pressed") === "true")?.dataset.color || "#2563eb"

    this.observer = new ResizeObserver(() => this.fit())
    this.observer.observe(this.canvasTarget)
    if (this.speakerValue) this.wirePointer()

    const channel = this.speakerValue
      ? { channel: "WhiteboardChannel", speaker: this.speakerValue }
      : { channel: "WhiteboardChannel", viewer: this.viewerValue }
    cable.subscribeTo(channel, {
      received: (message) => this.receive(message),
      connected: () => { this.online = true; this.render() },
      disconnected: () => { this.online = false; this.render() },
      rejected: () => { this.refused = true; this.render() },
    }).then((sub) => {
      if (this.isDisconnected) sub.unsubscribe()
      else this.sub = sub
    })
    this.render()
  }

  disconnect() {
    this.isDisconnected = true
    this.sub?.unsubscribe()
    this.observer?.disconnect()
    clearInterval(this.flushTimer)
  }

  // ---- messages from the server ----
  receive(m) {
    switch (m.type) {
      case "state":
        Object.assign(this, { mode: m.mode, dark: m.dark, blanked: m.blanked, stopKey: m.stop, board: m.board || [], slide: m.slide || [] })
        this.live.clear()
        this.render()
        break
      case "stroke":
        if (m.src === this.src) return // drawn here already
        this.live.delete(m.id)
        this.layer(m.layer)?.push(m.stroke)
        this.draw()
        break
      case "live": {
        if (m.src === this.src) return
        const s = this.live.get(m.id)
        if (s) s.p.push(...m.p)
        else this.live.set(m.id, { t: m.t, c: m.c, p: [...m.p] })
        this.draw()
        break
      }
      case "position":
        if (m.stop !== this.stopKey) { this.stopKey = m.stop; this.slide = [] }
        this.blanked = m.blanked
        this.render()
        break
      case "ended":
        this.ended = true
        this.mode = null
        this.current = null
        clearInterval(this.flushTimer)
        this.render()
        break
    }
  }

  layer(name) { return name === "board" ? this.board : name === "slide" ? this.slide : null }

  // ---- speaker actions ----
  start(e) { this.perform("start", { mode: e.params.mode }) }
  stopDrawing() { this.perform("stop") }
  undo() { this.perform("undo") }
  clear() { if (window.confirm(this.labelsValue.clear_confirm)) this.perform("clear") }
  toggleDark() { this.perform("dark", { dark: !this.dark }) }

  pickColor(e) {
    this.color = e.currentTarget.dataset.color
    if (this.tool === "erase") this.setTool("pen")
    this.colorTargets.forEach(b => b.setAttribute("aria-pressed", String(b === e.currentTarget)))
  }
  pickTool(e) { this.setTool(e.params.tool) }
  setTool(tool) {
    this.tool = tool
    this.toolTargets.forEach(b => {
      const on = b.dataset.whiteboardToolParam === tool
      b.setAttribute("aria-pressed", String(on))
      b.classList.toggle("btn-active", on)
    })
  }

  perform(action, data = {}) { this.sub?.perform(action, data) }

  // ---- drawing (speaker) ----
  // One pointer draws at a time: a palm or second finger on the tablet is ignored until the
  // pen lifts, so it can't cut the stroke short.
  wirePointer() {
    const c = this.canvasTarget
    c.addEventListener("pointerdown", (e) => {
      if (!this.mode || this.ended || this.current) return
      e.preventDefault()
      this.pointerId = e.pointerId
      try { c.setPointerCapture(e.pointerId) } catch { /* a pen that already lifted */ }
      this.begin(this.point(e))
    })
    c.addEventListener("pointermove", (e) => {
      if (!this.current || e.pointerId !== this.pointerId) return
      const events = e.getCoalescedEvents ? e.getCoalescedEvents() : [ e ]
      events.forEach(ev => this.extend(this.point(ev)))
      this.draw()
    })
    const end = (e) => { if (e.pointerId === this.pointerId) this.finish() }
    c.addEventListener("pointerup", end)
    c.addEventListener("pointercancel", end)
  }
  begin(pt) {
    this.current = { id: `${this.src}-${++this.seq}`, t: this.tool, c: this.color, p: [ pt ] }
    this.pending = [ pt ]
    clearInterval(this.flushTimer)
    this.flushTimer = setInterval(() => this.flushLive(), FLUSH_MS)
    this.draw()
  }
  extend(pt) {
    const s = this.current
    const last = s.p[s.p.length - 1]
    if (Math.hypot(pt[0] - last[0], pt[1] - last[1]) < MIN_STEP) return
    s.p.push(pt)
    this.pending.push(pt)
    // A very long stroke is stored in pieces, so none is over the server's limit.
    if (s.p.length >= MAX_POINTS) { this.finish(); this.begin(pt) }
  }
  finish() {
    if (!this.current) return
    clearInterval(this.flushTimer)
    this.flushLive()
    const s = this.current
    this.current = null
    this.layer(this.mode)?.push({ t: s.t, c: s.c, p: s.p })
    this.perform("stroke", { src: this.src, id: s.id, stroke: { t: s.t, c: s.c, p: s.p } })
    this.draw()
  }
  flushLive() {
    if (!this.current || !this.pending.length) return
    const s = this.current
    this.perform("draw", { src: this.src, id: s.id, stroke: { t: s.t, c: s.c, p: this.pending } })
    this.pending = []
  }
  point(e) {
    const r = this.canvasTarget.getBoundingClientRect()
    const clamp = (v) => Math.round(Math.min(1, Math.max(0, v)) * 10000) / 10000
    return [ clamp((e.clientX - r.left) / r.width), clamp((e.clientY - r.top) / r.height) ]
  }

  // ---- render ----
  render() {
    const on = !!this.mode && !this.ended
    const speaker = !!this.speakerValue
    // A blanked screen stays black on the projector; the speaker still sees his drawing.
    const shown = on && (speaker || !this.blanked)
    this.layerTarget.hidden = !shown
    if (this.hasSurfaceTarget) {
      this.surfaceTarget.style.background = this.mode === "board" ? (this.dark ? BOARD_BG.dark : BOARD_BG.light) : "transparent"
    }
    const L = this.labelsValue
    if (this.hasStatusTarget) {
      this.statusTarget.textContent = this.ended ? L.ended : this.refused ? L.unavailable : !this.online ? L.connecting
        : on ? (this.blanked ? L.blanked : L[this.mode]) : L.idle
      this.statusTarget.classList.toggle("badge-error", on || this.refused)
      this.statusTarget.classList.toggle("badge-ghost", !on && !this.refused)
    }
    if (this.hasStartTarget) {
      this.startTarget.hidden = on || this.ended
      this.startTarget.querySelectorAll("button").forEach(b => { b.disabled = !this.online })
    }
    if (this.hasToolsTarget) this.toolsTarget.hidden = !on
    if (this.hasStopTarget) {
      this.stopTarget.hidden = !on
      this.stopTarget.textContent = this.mode === "slide" ? L.stop_slide : L.stop_board
    }
    if (this.hasDarkToggleTarget) this.darkToggleTarget.hidden = this.mode !== "board"
    if (this.hasHintTarget) this.hintTarget.textContent = this.mode === "slide" ? L.hint_slide : this.mode === "board" ? L.hint_board : L.hint_idle
    if (this.hasBannerTarget) {
      this.bannerTarget.hidden = !on
      if (this.hasBannerTextTarget && on) this.bannerTextTarget.textContent = L[`banner_${this.mode}`]
    }
    this.fit()
  }

  fit() {
    const c = this.canvasTarget
    const dpr = window.devicePixelRatio || 1
    const w = Math.round(c.clientWidth * dpr), h = Math.round(c.clientHeight * dpr)
    if (w && h && (c.width !== w || c.height !== h)) { c.width = w; c.height = h }
    this.draw()
  }

  draw() {
    const c = this.canvasTarget
    const ctx = c.getContext("2d")
    ctx.clearRect(0, 0, c.width, c.height)
    if (!this.mode || !c.width) return
    this.layer(this.mode).forEach(s => this.paint(ctx, s))
    this.live.forEach(s => this.paint(ctx, s))
    if (this.current) this.paint(ctx, this.current)
  }

  paint(ctx, s) {
    const { width: w, height: h } = ctx.canvas
    if (!s.p?.length) return
    ctx.save()
    ctx.lineCap = "round"
    ctx.lineJoin = "round"
    if (s.t === "erase") {
      ctx.globalCompositeOperation = "destination-out"
      ctx.lineWidth = h * 0.05
    } else {
      ctx.strokeStyle = s.c
      ctx.globalAlpha = s.t === "hl" ? 0.35 : 1
      ctx.lineWidth = h * (s.t === "hl" ? 0.035 : 0.008)
    }
    ctx.beginPath()
    s.p.forEach(([x, y], i) => (i ? ctx.lineTo(x * w, y * h) : ctx.moveTo(x * w, y * h)))
    if (s.p.length === 1) ctx.lineTo(s.p[0][0] * w + 0.1, s.p[0][1] * h) // a tap leaves a dot
    ctx.stroke()
    ctx.restore()
  }
}
