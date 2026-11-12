import { Controller } from "@hotwired/stimulus"

// Keeps the full-set chart in sync with the projector. The live "Now" frame is replaced by the
// operator broadcast (Turbo Stream on #live-frame); each replacement carries the new
// position_version. On a newer version we mark the matching row in the full set as current and
// scroll it to just below the sticky Now band, so a musician reading ahead is snapped back to
// where the service is.
//
// The current row is identified server-side on GET (data-current="true"); live advances happen
// client-side here by reading the item/section the new live frame reports.
const GAP = 12 // px between the bottom of the sticky header and the current row

export default class extends Controller {
  connect() {
    this.onStream = this.onStream.bind(this)
    document.addEventListener("turbo:before-stream-render", this.onStream)
    // Snap to the server-rendered current row on first paint.
    const row = this.element.querySelector('[data-role=set-row][data-current="true"]')
    if (row) this.scrollToRow(row, false)
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.onStream)
  }

  onStream(event) {
    const frame = event.target?.templateContent?.querySelector?.("[data-role=musician-frame]")
    if (!frame) return
    const { itemId, sectionIndex } = frame.dataset
    if (itemId == null || sectionIndex == null) return

    // Turbo renders the stream one repaint after this event. Follow only once the new Now band
    // is in place: its height is final, and swapping it in can no longer cancel the scroll. A
    // stale frame the follower guard drops is never rendered, so it never moves the chart.
    const render = event.detail.render
    event.detail.render = async (stream) => {
      await render(stream)
      this.markCurrent(itemId, sectionIndex)
    }
  }

  markCurrent(itemId, sectionIndex) {
    this.element.querySelectorAll("[data-role=set-row].is-current").forEach((el) => {
      el.classList.remove("is-current")
      el.removeAttribute("data-current")
    })
    const row = this.element.querySelector(`#${CSS.escape(`row-${itemId}-${sectionIndex}`)}`)
    if (!row) return
    row.classList.add("is-current")
    row.setAttribute("data-current", "true")
    this.scrollToRow(row, true)
  }

  // Put the row just below the sticky header. The top bar hides while scrolling down
  // (topbar_reveal_controller) and returns when scrolling up, so it only counts going up.
  scrollToRow(row, smooth) {
    const band = this.element.querySelector("[data-role=now-bar]")
    const bar = this.element.querySelector(".musician-topbar")
    const rowTop = row.getBoundingClientRect().top + window.scrollY
    let top = rowTop - (band?.offsetHeight || 0) - GAP
    if (top < window.scrollY) top -= bar?.offsetHeight || 0

    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches
    window.scrollTo({ top: Math.max(0, top), behavior: smooth && !reduce ? "smooth" : "auto" })
  }
}
