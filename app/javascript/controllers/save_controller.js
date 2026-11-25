import { Controller } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"

// Keep drafts only in the open DOM. Never put health data into browser storage.
export default class extends Controller {
  static targets = ["status", "button"]
  connect() {
    this.dirty = false
    this.offline = () => this.message("Offline. This entry has NOT been saved. Keep this page open and retry when connected.", true)
    this.unload = event => { if (this.dirty) { event.preventDefault(); event.returnValue = "" } }
    window.addEventListener("offline", this.offline)
    window.addEventListener("beforeunload", this.unload)
    if (!navigator.onLine) this.offline()
  }
  disconnect() { window.removeEventListener("offline", this.offline); window.removeEventListener("beforeunload", this.unload) }
  changed() { this.dirty = true; this.message("Not saved yet.") }
  message(text, error = false) {
    if (!this.element.isConnected) return this.announce("Your earlier entry was NOT saved. Please enter it again.", true)
    this.statusTarget.textContent = text; this.statusTarget.classList.toggle("errors", error)
  }
  // Reports on a form that is no longer on the page, above whatever replaced it.
  announce(text, error = false) {
    const notice = document.createElement("div")
    notice.className = `flash ${error ? "alert" : "notice"}`
    notice.setAttribute("role", error ? "alert" : "status")
    notice.textContent = text
    const host = document.querySelector("dialog[open]") || document.getElementById("main")
    host?.prepend(notice)
  }
  async submit(event) {
    event.preventDefault()
    if (this.saving) return
    this.saving = true; this.dirty = true; this.buttonTarget.disabled = true
    this.message("Saving…")
    const abort = new AbortController()
    const timeout = setTimeout(() => abort.abort(), 20000)
    try {
      const response = await fetch(this.element.action, {
        method: "POST", body: new FormData(this.element), credentials: "same-origin", redirect: "follow",
        headers: { "Accept": "application/json", "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content }, signal: abort.signal
      })
      if (response.headers.get("content-type")?.includes("application/json")) {
        const result = await response.json()
        if (response.ok && result.redirect_to) {
          this.dirty = false
          // Another form may have replaced this one; navigating would discard its draft.
          if (!this.element.isConnected) return this.announce("Your earlier entry was saved.")
          this.message("Saved.")
          globalThis.Turbo.visit(result.redirect_to)
        } else {
          this.message(`NOT saved. ${(result.errors || ["Please check your values and retry."]).join(" ")}`, true)
        }
      } else {
        this.message("NOT saved. Your session may have expired. Sign in again in another tab, then retry this form.", true)
      }
    } catch (_) {
      this.message("Server unreachable. This entry has NOT been saved. Your form is still here. Keep this page open and retry; a retry cannot create a duplicate.", true)
    } finally { clearTimeout(timeout); this.saving = false; this.buttonTarget.disabled = false }
  }
}
