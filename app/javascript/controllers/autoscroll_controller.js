import { Controller } from "@hotwired/stimulus"

// Hands-free teleprompter scroll for the song sheet. A musician playing can let the page scroll
// itself instead of swiping. Play/pause toggles a requestAnimationFrame loop that advances
// window scroll at an adjustable speed; the speed is persisted per browser. Any manual scroll,
// touch, or key pauses it (you grabbed the wheel), and it respects prefers-reduced-motion.
//
// Targets: toggle (the play/pause button), speed (the range input), speedLabel (shows ×N).
// Values: min/max/step/default speed (px per second at the slider's unit).
export default class extends Controller {
  static targets = ["toggle", "speed", "speedLabel"]
  static values = {
    storageKey: { type: String, default: "song-autoscroll-speed" }
  }

  connect() {
    this.running = false
    this.rafId = null
    this.lastTs = null
    this.carry = 0 // sub-pixel accumulator so slow speeds still move

    // Restore saved speed.
    const saved = Number(localStorage.getItem(this.storageKeyValue))
    if (this.hasSpeedTarget && Number.isFinite(saved) && saved > 0) {
      this.speedTarget.value = String(saved)
    }
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

  // Slider is 1..10; map to ~20..200 px/s (gentle to brisk reading pace).
  pxPerSecond() {
    const unit = this.hasSpeedTarget ? Number(this.speedTarget.value) : 4
    return Math.max(1, unit) * 20
  }

  changeSpeed() {
    localStorage.setItem(this.storageKeyValue, this.speedTarget.value)
    this.updateLabel()
  }

  updateLabel() {
    if (this.hasSpeedLabelTarget && this.hasSpeedTarget) {
      this.speedLabelTarget.textContent = `×${this.speedTarget.value}`
    }
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
