import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["dialog"]
  static values = { open: Boolean }
  connect() { if (this.openValue) this.open() }
  disconnect() { document.body.classList.remove("modal-open") }
  open(event) {
    this.opener = event?.currentTarget || this.opener
    if (!this.dialogTarget.open) this.dialogTarget.showModal()
    document.body.classList.add("modal-open")
  }
  close() { this.dialogTarget.close() }
  closed() {
    document.body.classList.remove("modal-open")
    this.opener?.focus()
    this.dispatch("closed")
  }
  backdrop(event) { if (event.target === this.dialogTarget) {
    const box = this.dialogTarget.getBoundingClientRect()
    if (event.clientX < box.left || event.clientX > box.right || event.clientY < box.top || event.clientY > box.bottom) this.close()
  } }
}
