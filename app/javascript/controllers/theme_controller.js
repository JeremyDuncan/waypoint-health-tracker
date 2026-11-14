import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "menu", "choice", "current"]

  connect() {
    this.media = matchMedia("(prefers-color-scheme: dark)")
    this.refresh = () => window.WaypointTheme.apply()
    this.sync = () => {
      const preference = document.documentElement.dataset.themePreference
      const label = preference.charAt(0).toUpperCase() + preference.slice(1)
      this.buttonTarget.title = `Appearance: ${label}`
      this.currentTarget.textContent = `Current appearance: ${label}`
      this.choiceTargets.forEach(choice => choice.setAttribute("aria-checked", String(choice.dataset.themeChoice === preference)))
    }
    this.storageChanged = event => { if (["waypoint-health.theme", "hearth.theme"].includes(event.key) || event.key === null) this.refresh() }
    this.media.addEventListener("change", this.refresh)
    window.addEventListener("storage", this.storageChanged)
    window.addEventListener("waypoint-health:theme-change", this.sync)
    this.refresh()
  }

  disconnect() {
    this.media.removeEventListener("change", this.refresh)
    window.removeEventListener("storage", this.storageChanged)
    window.removeEventListener("waypoint-health:theme-change", this.sync)
  }

  toggle() {
    if (!this.menuTarget.hidden) return this.dismiss()
    this.menuTarget.hidden = false
    this.buttonTarget.setAttribute("aria-expanded", "true")
    this.choiceTargets.find(choice => choice.getAttribute("aria-checked") === "true")?.focus()
  }
  choose(event) {
    window.WaypointTheme.set(event.currentTarget.dataset.themeChoice)
    this.dismiss()
    this.buttonTarget.focus()
  }
  dismiss() {
    this.menuTarget.hidden = true
    this.buttonTarget.setAttribute("aria-expanded", "false")
  }
  outside(event) { if (!this.menuTarget.contains(event.target) && !this.buttonTarget.contains(event.target)) this.dismiss() }
  keydown(event) {
    if (this.menuTarget.hidden) return
    if (event.key === "Escape") { event.preventDefault(); this.dismiss(); this.buttonTarget.focus() }
    if (event.key === "Tab") this.dismiss()
    if (!["ArrowDown", "ArrowUp", "Home", "End"].includes(event.key)) return
    event.preventDefault()
    let index = this.choiceTargets.indexOf(document.activeElement)
    if (event.key === "Home") index = 0
    else if (event.key === "End") index = this.choiceTargets.length - 1
    else index = (index + (event.key === "ArrowDown" ? 1 : -1) + this.choiceTargets.length) % this.choiceTargets.length
    this.choiceTargets[index].focus()
  }
}
