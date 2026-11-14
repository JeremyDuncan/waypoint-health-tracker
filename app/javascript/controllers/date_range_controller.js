import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["range"]
  customDates() { this.rangeTarget.value = "custom" }
}
