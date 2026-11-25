import { Controller } from "@hotwired/stimulus"

// Loads one calendar day at a time. The previous day is removed as soon as another
// is requested, so its form can never be filled in or submitted for the wrong day.
export default class extends Controller {
  loading(event) {
    if (event.target !== this.element) return
    const focused = this.element.contains(document.activeElement)
    this.show("Loading…")
    if (focused) { this.element.tabIndex = -1; this.element.focus() }
  }

  failed(event) {
    if (event.target === this.element) this.show("Couldn’t load this. Check your connection, then close and try again.", "errors")
  }

  // Follows a response that has no matching frame, such as an expired session's sign-in page.
  visit(event) {
    event.preventDefault()
    event.detail.visit(event.detail.response)
  }

  show(text, className = "muted") {
    const status = document.createElement("p")
    status.className = className
    status.setAttribute("role", "status")
    status.textContent = text
    this.element.replaceChildren(status)
  }
}
