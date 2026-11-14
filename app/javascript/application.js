import "@hotwired/turbo-rails"
import "controllers"
if ("serviceWorker" in navigator && window.isSecureContext) {
  navigator.serviceWorker.register("/service-worker").catch(() => {})
}
