import { Controller } from "@hotwired/stimulus"

// Remembers that a <details> was closed, in a cookie the server reads to render it the same way
// on the next page load (each Next reloads the operator page). The cookie holds the key of what
// was closed, so a new key (the next live service) starts open again.
//   <details open data-controller="remember-open" data-action="toggle->remember-open#save"
//            data-remember-open-cookie-value="join_links_closed" data-remember-open-key-value="12">
export default class extends Controller {
  static values = { cookie: String, key: String }

  save() {
    const value = this.element.open ? "" : this.keyValue
    document.cookie = `${this.cookieValue}=${encodeURIComponent(value)}; path=/; max-age=86400; samesite=lax`
  }
}
