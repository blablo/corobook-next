import { Controller } from "@hotwired/stimulus"

// Keeps the full-set chart in sync with the projector. The live "Now" frame is replaced by the
// operator broadcast (Turbo Stream on #live-frame); each replacement carries the new
// position_version. On a newer version we mark the matching row in the full set as current and
// scroll it into view, so a musician reading ahead is snapped back to where the service is.
//
// The current row is identified server-side on GET (data-current="true"); live advances happen
// client-side here by reading the item/section the new live frame reports.
export default class extends Controller {
  connect() {
    this.onStream = this.onStream.bind(this)
    document.addEventListener("turbo:before-stream-render", this.onStream)
    // Snap to the server-rendered current row on first paint.
    this.scrollToCurrent()
  }

  disconnect() {
    document.removeEventListener("turbo:before-stream-render", this.onStream)
  }

  onStream(event) {
    const frame = event.target?.templateContent?.querySelector?.("[data-role=musician-frame]")
    if (!frame) return
    const itemId = frame.dataset.itemId
    const sectionIndex = frame.dataset.sectionIndex
    if (itemId == null || sectionIndex == null) return
    // Defer until the stream has applied so the DOM reflects the new frame.
    requestAnimationFrame(() => this.markCurrent(itemId, sectionIndex))
  }

  markCurrent(itemId, sectionIndex) {
    this.element.querySelectorAll("[data-role=set-row].is-current").forEach((el) => {
      el.classList.remove("is-current")
      el.removeAttribute("data-current")
    })
    const id = `row-${itemId}-${sectionIndex}`
    const row = this.element.querySelector(`#${CSS.escape(id)}`)
    if (!row) return
    row.classList.add("is-current")
    row.setAttribute("data-current", "true")
    row.scrollIntoView({ behavior: "smooth", block: "start" })
  }

  scrollToCurrent() {
    const row = this.element.querySelector('[data-role=set-row][data-current="true"]')
    row?.scrollIntoView({ block: "start" })
  }
}
