import { Controller } from "@hotwired/stimulus"

// Enables a destructive submit only after its phrase is typed. The server checks it again.
export default class extends Controller {
  static targets = ["input", "submit"]
  static values = { phrase: String }
  connect() { this.reset() }
  check() { this.submitTarget.disabled = this.inputTarget.value.trim() !== this.phraseValue }
  reset() {
    this.inputTarget.value = ""
    this.check()
  }
}
