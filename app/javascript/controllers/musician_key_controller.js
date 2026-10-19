import { Controller } from "@hotwired/stimulus"

// A musician's chosen key/capo is theirs alone, persisted in localStorage and sent as query
// params so the server renders this follower's frame at their key (§6.3). Independent of the
// operator and other musicians.
export default class extends Controller {
  static values = { token: String }

  connect() {
    const saved = this.load()
    const input = this.element.querySelector("[data-role=key-input]")
    const capo = this.element.querySelector("[data-role=capo-input]")
    // Apply a saved preference on first load if the URL does not already carry one.
    const params = new URLSearchParams(window.location.search)
    if (!params.has("key") && (saved.key || saved.capo)) {
      this.navigate(saved.key, saved.capo)
    } else {
      if (input && params.get("key")) input.value = params.get("key")
      if (capo && params.get("capo")) capo.value = params.get("capo")
    }
  }

  choose(event) {
    event.preventDefault()
    const key = this.element.querySelector("[data-role=key-input]").value
    const capo = this.element.querySelector("[data-role=capo-input]").value
    this.save(key, capo)
    this.navigate(key, capo)
  }

  navigate(key, capo) {
    const params = new URLSearchParams()
    if (key) params.set("key", key)
    if (capo) params.set("capo", capo)
    window.location.search = params.toString()
  }

  storageKey() {
    return `musician-key:${this.tokenValue}`
  }

  save(key, capo) {
    localStorage.setItem(this.storageKey(), JSON.stringify({ key, capo }))
  }

  load() {
    try {
      return JSON.parse(localStorage.getItem(this.storageKey())) || {}
    } catch {
      return {}
    }
  }
}
