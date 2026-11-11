/* TMM Self Service (/ess) - service worker.
   Makes the app installable and keeps its look (styles, scripts, logo, fonts) on the
   phone so it opens fast. Pages and data are NEVER cached: attendance, leave and the
   profile are personal and always come fresh from the server; a punch needs the
   connection. With no connection the app shows the offline page. */
"use strict";

var CACHE = "tmm-ess-v1";
var SHELL = ["offline.html", "icons/icon-192.png", "../img/tmm-logo-dark.svg"];

self.addEventListener("install", function (event) {
    event.waitUntil(caches.open(CACHE).then(function (cache) { return cache.addAll(SHELL); }));
    self.skipWaiting();
});

self.addEventListener("activate", function (event) {
    event.waitUntil(caches.keys().then(function (keys) {
        return Promise.all(keys.filter(function (k) { return k.indexOf("tmm-ess-") === 0 && k !== CACHE; })
                               .map(function (k) { return caches.delete(k); }));
    }).then(function () { return self.clients.claim(); }));
});

function isStatic(url) {
    return /\.(css|js|svg|png|woff2?)$/i.test(url.pathname) || url.hostname === "fonts.gstatic.com" || url.hostname === "fonts.googleapis.com";
}

self.addEventListener("fetch", function (event) {
    var request = event.request;
    if (request.method !== "GET") return;
    var url = new URL(request.url);

    // pages: always the network; the offline page when there is none
    if (request.mode === "navigate") {
        event.respondWith(fetch(request).catch(function () {
            return caches.match(new URL("offline.html", self.registration.scope).href);
        }));
        return;
    }

    // styles, scripts, images, fonts: the network first (new versions), the copy when offline
    if (isStatic(url) && url.pathname.indexOf("/ess/sw.js") < 0) {
        event.respondWith(fetch(request).then(function (response) {
            if (response && (response.ok || response.type === "opaque")) {
                var copy = response.clone();
                caches.open(CACHE).then(function (cache) { cache.put(request, copy); });
            }
            return response;
        }).catch(function () { return caches.match(request); }));
    }
    // anything else (data, punches): straight to the network, never stored
});
