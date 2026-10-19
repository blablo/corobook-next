import { Controller } from "@hotwired/stimulus"

// Follower frame guard. Full monotonic version-drop + freeze-on-disconnect logic lands in 7.4;
// for now it just records the applied version.
export default class extends Controller {
  static values = { version: Number }

  connect() {
    this.lastVersion = this.versionValue
  }
}
