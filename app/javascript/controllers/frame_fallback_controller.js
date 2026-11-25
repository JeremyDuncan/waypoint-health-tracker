import { Controller } from "@hotwired/stimulus"

// Follows a response that has no matching frame, such as an expired session's sign-in page.
export default class extends Controller {
  visit(event) {
    event.preventDefault()
    event.detail.visit(event.detail.response)
  }
}
