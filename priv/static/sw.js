const STATIC_CACHE = "elilai-static-v1"
const STATIC_CACHE_PREFIX = "elilai-static-"
const ALLOWED_PREFIXES = ["/assets/", "/fonts/"]
const ALLOWED_EXACT_PATHS = [
  "/images/elilai-kafe/elilai-kafe-logo.jpg",
  "/images/elilai-kafe/app-icon-192.png",
  "/images/elilai-kafe/app-icon-512.png",
  "/images/elilai-kafe/apple-touch-icon.png"
]

self.addEventListener("install", event => {
  event.waitUntil(
    caches.open(STATIC_CACHE).then(cache => cache.addAll(ALLOWED_EXACT_PATHS))
  )
})

self.addEventListener("activate", event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(
        keys
          .filter(key => key.startsWith(STATIC_CACHE_PREFIX) && key !== STATIC_CACHE)
          .map(key => caches.delete(key))
      )
    )
  )
})

self.addEventListener("push", event => {
  let data = {}

  try {
    data = event.data ? event.data.json() : {}
  } catch (_error) {
    data = {}
  }

  const title = data.title || "CoffeeSpot"
  const body = data.body || ""
  const url = data.url || "/menu"
  const tag = data.tag || "coffeespot-order"

  event.waitUntil(
    self.registration.showNotification(title, {
      body,
      icon: "/images/elilai-kafe/app-icon-192.png",
      badge: "/images/elilai-kafe/app-icon-192.png",
      data: {url},
      tag,
      renotify: true
    })
  )
})

self.addEventListener("notificationclick", event => {
  event.notification.close()
  const url = event.notification.data?.url || "/menu"

  event.waitUntil(
    self.clients.matchAll({type: "window", includeUncontrolled: true}).then(clients => {
      for (const client of clients) {
        if ("focus" in client && client.url && client.url.includes(url)) {
          return client.focus()
        }
      }

      if (self.clients.openWindow) return self.clients.openWindow(url)
      return undefined
    })
  )
})

self.addEventListener("fetch", event => {
  if (!isCacheableRequest(event.request)) return

  event.respondWith(cacheFirst(event.request))
})

function isCacheableRequest(request) {
  if (request.method !== "GET") return false

  const url = new URL(request.url)

  if (url.origin !== self.location.origin) return false
  if (request.mode === "navigate") return false

  const path = url.pathname

  if (path === "/elilai-kafe.webmanifest") return false
  if (path.startsWith("/api/")) return false
  if (path === "/live" || path.startsWith("/live/")) return false
  if (path === "/socket" || path.startsWith("/socket/")) return false

  return (
    ALLOWED_PREFIXES.some(prefix => path.startsWith(prefix)) ||
    ALLOWED_EXACT_PATHS.includes(path)
  )
}

async function cacheFirst(request) {
  const cache = await caches.open(STATIC_CACHE)
  const cached = await cache.match(request)

  if (cached) return cached

  const response = await fetch(request)

  if (response.ok && response.type === "basic") {
    await cache.put(request, response.clone())
  }

  return response
}
