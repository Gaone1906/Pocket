const CACHE = "momoflix-web-v2";
const SHELL = ["./", "index.html", "match.html", "profile.js", "momo.css", "manifest.webmanifest", "icon-192.png", "icon-512.png", "apple-touch-icon.png", "logo-96.png", "../fabula/style.css", "../fabula/app.js", "../fabula/match.js", "../fabula/store.js", "../fabula/films.js", "../fabula/drag.js", "../fabula/room.js", "../fabula/util.js", "../fabula/profile.js"];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(CACHE).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(
    caches
      .keys()
      .then((keys) => Promise.all(keys.filter((k) => k.startsWith("momoflix-web-") && k !== CACHE).map((k) => caches.delete(k))))
      .then(() => self.clients.claim())
  );
});

self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== self.location.origin) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        const copy = res.clone();
        caches.open(CACHE).then((c) => c.put(e.request, copy));
        return res;
      })
      .catch(() => caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || caches.match("index.html")))
  );
});
