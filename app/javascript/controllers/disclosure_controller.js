import { Controller } from "@hotwired/stimulus"

// Show and hide a panel, keeping aria-expanded (and an optional active class) on the button
// targets in step. The server renders whether the panel starts open.
//   <div data-controller="disclosure" data-disclosure-active-class="btn-active">
//     <button data-action="disclosure#toggle" data-disclosure-target="button" aria-expanded="false">Show</button>
//     <section data-disclosure-target="panel" hidden>…</section>
export default class extends Controller {
  static targets = ["panel", "button"]
  static classes = ["active"]

  toggle() {
    const open = this.panelTarget.hidden
    this.panelTarget.hidden = !open
    this.buttonTargets.forEach((button) => {
      button.setAttribute("aria-expanded", open)
      this.activeClasses.forEach((name) => button.classList.toggle(name, open))
    })
  }
}
