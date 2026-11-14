import { Controller } from "@hotwired/stimulus"

// Collapses the main navigation into a menu button on narrow screens.
// The menu is only hidden once this controller connects, so the links stay
// reachable if JavaScript fails to load.
export default class extends Controller {
  static targets = ["button", "panel"]

  connect() {
    this.media = matchMedia("(max-width: 1100px)")
    this.mediaChanged = () => { if (!this.media.matches) this.close() }
    this.media.addEventListener("change", this.mediaChanged)
    this.element.toggleAttribute("data-nav-ready", true)
  }

  disconnect() {
    this.media.removeEventListener("change", this.mediaChanged)
    this.close()
    this.element.removeAttribute("data-nav-ready")
  }

  get isOpen() { return this.element.classList.contains("nav-open") }

  toggle() { this.isOpen ? this.close({ focusButton: true }) : this.open() }

  open() {
    if (!this.hasButtonTarget) return
    this.element.classList.add("nav-open")
    document.documentElement.classList.add("nav-locked")
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.buttonTarget.setAttribute("aria-label", "Close menu")
    this.panelTarget.querySelector("a, button")?.focus({ preventScroll: true })
  }

  close({ focusButton = false } = {}) {
    if (!this.isOpen) return
    this.element.classList.remove("nav-open")
    document.documentElement.classList.remove("nav-locked")
    if (!this.hasButtonTarget) return
    this.buttonTarget.setAttribute("aria-expanded", "false")
    this.buttonTarget.setAttribute("aria-label", "Menu")
    if (focusButton) this.buttonTarget.focus()
  }

  keydown(event) {
    if (this.isOpen && event.key === "Escape") { event.preventDefault(); this.close({ focusButton: true }) }
  }

  outside(event) {
    if (!this.isOpen) return
    if (!this.panelTarget.contains(event.target) && !this.buttonTarget.contains(event.target)) this.close()
  }

  focusout(event) {
    if (!this.isOpen || !event.relatedTarget) return
    if (!this.panelTarget.contains(event.relatedTarget) && !this.buttonTarget.contains(event.relatedTarget)) this.close()
  }
}
