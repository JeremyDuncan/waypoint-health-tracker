import { Controller } from "@hotwired/stimulus"
export default class extends Controller {
  static targets = ["mode", "targetFields", "maintenanceFields"]
  connect() { this.render() }
  render() {
    const maintenance = this.modeTarget.value === "maintenance"
    this.targetFieldsTarget.hidden = maintenance
    this.maintenanceFieldsTarget.hidden = !maintenance
  }
}
