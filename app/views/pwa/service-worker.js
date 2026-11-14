// Deliberately no fetch handler or caches: health pages stay on the server.
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", event => event.waitUntil(self.clients.claim()));
