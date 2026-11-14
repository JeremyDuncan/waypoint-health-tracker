import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["status", "preserved", "submit", "retry", "form"]
  static values = { state: Object, url: String }
  connect() { this.queue = Promise.resolve(); this.revision = 0 }

  save(event) {
    this.stateValue = { ...this.stateValue, ...event.detail }
    this.persist()
  }
  retry() { this.persist() }
  restoreFilters() {
    for (const input of this.formTarget.elements) {
      const key = input.name.match(/^preferences\[(\w+)\]$/)?.[1]
      if (!key) continue
      const value = this.stateValue[key]
      input.value = value === undefined ? input.defaultValue || "" : typeof value === "boolean" ? (value ? "1" : "0") : value
    }
  }

  persist() {
    const state = { ...this.stateValue }, revision = ++this.revision
    this.preservedTargets.forEach(input => { const value = state[input.dataset.key]; input.value = typeof value === "boolean" ? (value ? "1" : "0") : value })
    this.submitTargets.forEach(button => { button.disabled = true })
    this.statusTarget.textContent = "Saving selections…"
    this.retryTarget.hidden = true
    // Serialize writes so quick changes cannot finish in reverse order.
    this.queue = this.queue.catch(() => {}).then(async () => {
      try {
        const response = await fetch(this.urlValue, { method: "PATCH", credentials: "same-origin", headers: { "Content-Type": "application/json", "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }, body: JSON.stringify({ preferences: state }) })
        if (!response.ok || response.redirected) throw new Error("Save failed")
        await response.json()
        if (revision !== this.revision || !this.element.isConnected) return
        this.statusTarget.textContent = "Selections saved."
        // After an explicit save, a stale query string must not override it on reload.
        const url = new URL(location.href)
        Object.keys(state).forEach(key => url.searchParams.delete(key))
        url.searchParams.delete("from"); url.searchParams.delete("to"); url.searchParams.delete("edit_filters")
        history.replaceState(history.state, "", url)
      } catch (_) {
        if (revision === this.revision && this.element.isConnected) {
          this.statusTarget.textContent = "Could not save selections. Your current view is still shown."
          this.retryTarget.hidden = false
        }
      } finally {
        if (revision === this.revision && this.element.isConnected) this.submitTargets.forEach(button => { button.disabled = false })
      }
    })
  }
}
