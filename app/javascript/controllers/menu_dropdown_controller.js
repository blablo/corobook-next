import { Controller } from "@hotwired/stimulus"

// Toggles a DaisyUI collapsible menu submenu (menu-dropdown). Adds/removes `menu-dropdown-show`
// on both the toggle and its dropdown list, per the daisyUI JS-controlled dropdown pattern.
export default class extends Controller {
  static targets = ["toggle", "menu"]
  static values = { open: Boolean }

  connect() {
    this.apply()
  }

  toggle(event) {
    event.preventDefault()
    this.openValue = !this.openValue
    this.apply()
  }

  apply() {
    this.toggleTarget.classList.toggle("menu-dropdown-show", this.openValue)
    this.menuTarget.classList.toggle("menu-dropdown-show", this.openValue)
  }
}
