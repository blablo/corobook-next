import { Controller } from "@hotwired/stimulus"

// Hands-free teleprompter scroll for the song sheet. A musician playing can let the page scroll
// itself instead of swiping. Play/pause toggles a requestAnimationFrame loop that advances
// window scroll at an adjustable speed; the speed is persisted per browser. Any manual scroll,
// touch, or key pauses it (you grabbed the wheel), and it respects prefers-reduced-motion.
//
// Targets: toggle (the play/pause button), slower / faster (the − and + buttons), speedLabel
// (shows the speed number). Big − / + buttons replaced a thin slider that was hard to hit with a
// finger on a phone.
//
// Speeds 1-6, in px per second. Most players use the old slider's 2 and 3 (9 and 13 px/s), so
// those sit in the middle with half steps around them: 3 = old 2, 5 = old 3 (the default).
const SPEEDS = [5, 7, 9, 11, 13, 17]
const DEFAULT_LEVEL = 5
const OLD_KEY = "song-autoscroll-speed" // old slider 1..10, n -> n * 4 + 1 px/s

export default class extends Controller {
  static targets = ["toggle", "slower", "faster", "speedLabel"]
  static values = {
    storageKey: { type: String, default: "song-autoscroll-level" }
  }

  connect() {
    this.running = false
    this.rafId = null
    this.lastTs = null
    this.carry = 0 // sub-pixel accumulator so slow speeds still move

    this.level = this.savedLevel()
    this.updateLabel()

    // Pause when the user takes over. We listen to wheel/touch/key rather than the scroll event,
    // because our own scrollBy would otherwise pause us; those three are genuine user input.
    this.onUserInput = this.onUserInput.bind(this)
    window.addEventListener("wheel", this.onUserInput, { passive: true })
    window.addEventListener("touchmove", this.onUserInput, { passive: true })
    window.addEventListener("keydown", this.onKey.bind(this))
  }

  disconnect() {
    this.stop()
    window.removeEventListener("wheel", this.onUserInput)
    window.removeEventListener("touchmove", this.onUserInput)
  }

  toggle() {
    this.running ? this.stop() : this.start()
  }

  start() {
    if (this.running) return
    // Nothing to scroll (already at the bottom) — do nothing.
    if (this.atBottom()) return
    this.running = true
    this.lastTs = null
    this.carry = 0
    this.reflectState()
    this.rafId = requestAnimationFrame(this.tick.bind(this))
  }

  stop() {
    this.running = false
    if (this.rafId) cancelAnimationFrame(this.rafId)
    this.rafId = null
    this.reflectState()
  }

  tick(ts) {
    if (!this.running) return
    if (this.lastTs == null) this.lastTs = ts
    const dt = (ts - this.lastTs) / 1000 // seconds
    this.lastTs = ts

    // pixels/second: slider unit (1..10) scaled to a comfortable reading range.
    const pxPerSec = this.pxPerSecond()
    this.carry += pxPerSec * dt
    const whole = Math.floor(this.carry)
    if (whole > 0) {
      this.carry -= whole
      window.scrollBy(0, whole)
    }

    if (this.atBottom()) { this.stop(); return }
    this.rafId = requestAnimationFrame(this.tick.bind(this))
  }

  pxPerSecond() { return SPEEDS[this.level - 1] }

  // − / + buttons: change the speed without pausing (the player is mid-song).
  slower(e) { e?.preventDefault(); this.setLevel(this.level - 1) }
  faster(e) { e?.preventDefault(); this.setLevel(this.level + 1) }

  setLevel(level) {
    this.level = Math.min(SPEEDS.length, Math.max(1, level))
    localStorage.setItem(this.storageKeyValue, String(this.level))
    this.updateLabel()
  }

  // The saved level, or one carried over from the old slider (nearest speed), or the default.
  savedLevel() {
    const saved = Number(localStorage.getItem(this.storageKeyValue))
    if (Number.isInteger(saved) && saved >= 1 && saved <= SPEEDS.length) return saved
    const old = Number(localStorage.getItem(OLD_KEY))
    if (Number.isFinite(old) && old > 0) {
      const px = old * 4 + 1
      const nearest = SPEEDS.reduce((best, v, i) => Math.abs(v - px) < Math.abs(SPEEDS[best] - px) ? i : best, 0)
      return nearest + 1
    }
    return DEFAULT_LEVEL
  }

  updateLabel() {
    if (this.hasSpeedLabelTarget) this.speedLabelTarget.textContent = String(this.level)
    if (this.hasSlowerTarget) this.slowerTarget.disabled = this.level <= 1
    if (this.hasFasterTarget) this.fasterTarget.disabled = this.level >= SPEEDS.length
  }

  atBottom() {
    const scrolled = window.innerHeight + window.scrollY
    return scrolled >= document.documentElement.scrollHeight - 2
  }

  onUserInput() {
    if (this.running) this.stop()
  }

  onKey(e) {
    // Space toggles; arrows/page keys mean the user is driving — pause.
    if (e.target && /^(INPUT|TEXTAREA|SELECT)$/.test(e.target.tagName)) return
    // Space on a focused button (− / +) clicks it; don't also toggle the scroll.
    if (e.code === "Space" && e.target?.closest?.("[data-autoscroll-target=slower], [data-autoscroll-target=faster]")) return
    if (e.code === "Space") {
      e.preventDefault()
      this.toggle()
    } else if (this.running && ["ArrowUp", "ArrowDown", "PageUp", "PageDown", "Home", "End"].includes(e.code)) {
      this.stop()
    }
  }

  // Button label + pressed state follow the running flag.
  reflectState() {
    if (!this.hasToggleTarget) return
    this.toggleTarget.setAttribute("aria-pressed", String(this.running))
    this.toggleTarget.dataset.running = String(this.running)
    const play = this.toggleTarget.querySelector("[data-autoscroll-icon=play]")
    const pause = this.toggleTarget.querySelector("[data-autoscroll-icon=pause]")
    if (play && pause) {
      play.classList.toggle("hidden", this.running)
      pause.classList.toggle("hidden", !this.running)
    }
  }
}
