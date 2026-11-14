import { Controller } from "@hotwired/stimulus"
import "@hotwired/turbo-rails"
export default class extends Controller {
  go() { if (this.element.value) globalThis.Turbo.visit(`/journal/${encodeURIComponent(this.element.value)}`) }
}
