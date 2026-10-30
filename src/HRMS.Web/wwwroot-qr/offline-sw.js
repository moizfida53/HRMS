/*=============================================================================
  QR Menu - Offline Mode service worker            (served from the site root)

  Registered ONLY while the customer has switched the menu to "Offline" (see
  MainJs/ItemsViewNew/OfflineMode.js, cookie QRMenuOfflineMode=1). Switching
  back to "Online" deletes every cache below and unregisters this worker, so a
  device that never opts in behaves exactly as before.

  What it serves (only for the customer landing page - see isMenuPageUrl):
    - the landing page HTML itself                       (navigation requests)
    - every css / js / font / image / video it loads     (same + cross origin)
    - the read-only menu endpoints listed in API_READ    (jQuery POSTs)

  Two modes, decided per request from the persisted state:
    normal   CACHE FIRST  - the saved copy wins even when a network exists, so
                            the menu is stable and instant; misses fall through
                            to the network and are added to the cache.
    syncing  NETWORK FIRST - started by the Sync icon. Every response is written
                            to a brand new cache; anything the network cannot
                            supply is copied over from the current one. On
                            SYNC_COMMIT the new cache replaces the old one in a
                            single step, on SYNC_ABORT it is thrown away - a
                            sync that dies halfway never leaves a half-empty
                            menu behind.

  POST bodies cannot be Cache API keys, so API responses are stored under a
  synthetic GET url: path + sorted query + SHA-256 of the canonical JSON body
  (keys sorted, numbers stringified, jQuery's "_" cache-buster dropped). That
  makes {BrandId:"5"} and {BrandId:5} the same entry, so the warm-up crawler
  in OfflineMode.js hits exactly the entries the menu code later asks for.

  Video: <video> asks for byte ranges. Ranges are never stored (a 206 is a
  fragment); the crawler downloads each video whole and ranges are then cut
  out of that full copy here (Safari will not play without proper 206s).
=============================================================================*/
'use strict';

var SW_VERSION   = '1.0.0';
var PREFIX       = 'qrmenu-offline-';
var META_CACHE   = PREFIX + 'meta';
var STATE_URL    = self.location.origin + '/__qrmenu_offline__/state';
var API_KEY_ROOT = self.location.origin + '/__qrmenu_offline__/api';
var DEFAULT_STATE = {
    current: PREFIX + 'data-initial',
    syncing: false,
    syncCache: null,
    syncStarted: 0,
    lastPage: null,
    lastSync: 0
};

// Read-only endpoints the landing page calls. Anything that changes data
// (SubmitOrder, payment, PostFeedback, SetIpAddress, TrackOrder, ...) is NOT
// listed and is never intercepted - it simply fails without a network.
var API_READ = [
    '/itemsview/getlanglabels',
    '/itemsview/getcategorylist',
    '/itemsview/getitemlist',
    '/itemsview/getbranchandsectionlist',
    '/itemsview/binditemextraitemsandcomments',
    '/itemsview/getcartviewitems',
    '/itemsview/getarealist',
    '/itemsviewnew/getitemimages',
    '/itemsviewnew/getfeedbackformquestion'
];

// RouteConfig maps every single-segment path to ItemsViewNew/brand ("{name}")
// except these explicit routes.
var NON_MENU_SINGLE = ['login', 'category', 'branchreservation', 'favicon.ico'];

/* ---------------------------------------------------------------- state -- */

var stateMemo = null;

function loadState() {
    if (stateMemo) { return Promise.resolve(stateMemo); }
    return caches.open(META_CACHE)
        .then(function (c) { return c.match(STATE_URL); })
        .then(function (r) { return r ? r.json() : null; })
        .catch(function () { return null; })
        .then(function (s) {
            stateMemo = Object.assign({}, DEFAULT_STATE, s || {});
            return stateMemo;
        });
}

function saveState(s) {
    stateMemo = s;
    return caches.open(META_CACHE).then(function (c) {
        return c.put(STATE_URL, new Response(JSON.stringify(s), {
            headers: { 'Content-Type': 'application/json' }
        }));
    });
}

/* -------------------------------------------------------------- routing -- */

function isMenuPageUrl(u) {
    if (!u) { return false; }
    var url;
    try { url = new URL(u); } catch (e) { return false; }
    if (url.origin !== self.location.origin) { return false; }
    var segs = url.pathname.split('/').filter(Boolean).map(function (s) {
        try { return decodeURIComponent(s).toLowerCase(); } catch (e) { return s.toLowerCase(); }
    });
    if (segs.length === 0) { return true; }
    if (segs[0] === 'itemsviewnew') {
        return segs.length === 1 || segs[1] === 'index' || segs[1] === 'brand';
    }
    if (segs.length === 1) {
        return segs[0].indexOf('.') === -1 && NON_MENU_SINGLE.indexOf(segs[0]) === -1;
    }
    return false;
}

// Fonts and background images are requested by the STYLESHEET, so their
// referrer is the .css file, not the page.
function isFromMenu(referrer) {
    if (isMenuPageUrl(referrer)) { return true; }
    return /\.css(\?|#|$)/i.test(referrer || '');
}

self.addEventListener('fetch', function (event) {
    var req = event.request;
    if (!/^https?:/i.test(req.url)) { return; }
    if (req.url.indexOf('/__qrmenu_offline__/') !== -1) { return; }

    if (req.method === 'GET') {
        if (req.mode === 'navigate') {
            if (isMenuPageUrl(req.url)) { event.respondWith(handle(req, 'page')); }
            return;
        }
        if (isFromMenu(req.referrer)) { event.respondWith(handle(req, 'asset')); }
        return;
    }

    if (req.method === 'POST' && isMenuPageUrl(req.referrer)) {
        var url = new URL(req.url);
        if (url.origin === self.location.origin &&
            API_READ.indexOf(url.pathname.toLowerCase()) !== -1) {
            event.respondWith(handle(req, 'api'));
        }
    }
});

/* ---------------------------------------------------------- strategies -- */

function handle(req, kind) {
    var keyPromise = kind === 'api' ? apiKey(req) : Promise.resolve(assetKey(req));
    return Promise.all([loadState(), keyPromise]).then(function (r) {
        var state = r[0], key = r[1];
        return (state.syncing && state.syncCache)
            ? networkFirst(req, key, kind, state)
            : cacheFirst(req, key, kind, state);
    }).catch(function () {
        return fetch(req);
    });
}

function cacheFirst(req, key, kind, state) {
    return matchFrom(state.current, key, kind).then(function (hit) {
        if (hit) { return withRange(req, hit); }
        return fetch(req).then(function (res) {
            if (!req.headers.has('range')) {
                return store(state.current, key, res, kind).then(function () { return res; });
            }
            return res;
        }).catch(function () {
            return offlineFallback(req, kind, state);
        });
    });
}

function networkFirst(req, key, kind, state) {
    var isRange = req.headers.has('range');
    return fetchFresh(req, kind).then(function (res) {
        if (isRange) { return res; }
        return store(state.syncCache, key, res, kind).then(function (ok) {
            if (ok && kind === 'page') { rememberPage(req.url); }
            return res;
        });
    }).catch(function () {
        return matchFrom(state.current, key, kind).then(function (hit) {
            if (!hit) { return offlineFallback(req, kind, state); }
            if (!isRange) {
                // Carry the old copy into the new cache so the commit keeps it.
                return caches.open(state.syncCache)
                    .then(function (c) { return c.put(key, hit.clone()); })
                    .catch(function () { })
                    .then(function () { return hit; });
            }
            return withRange(req, hit);
        });
    });
}

// During a sync we want the server's copy, not the browser's HTTP cache.
function fetchFresh(req, kind) {
    if (kind === 'page') {
        return fetch(req.url, { cache: 'no-store', credentials: 'include' }).then(cleanRedirect);
    }
    if (kind === 'api') { return fetch(req); }
    try {
        return fetch(new Request(req, { cache: 'no-cache' }));
    } catch (e) {
        return fetch(req);
    }
}

// A navigation cannot be answered with a response flagged "redirected".
function cleanRedirect(res) {
    if (!res.redirected) { return res; }
    return res.blob().then(function (body) {
        return new Response(body, { status: res.status, statusText: res.statusText, headers: res.headers });
    });
}

function matchFrom(cacheName, key, kind) {
    return caches.open(cacheName).then(function (cache) {
        return cache.match(key, { ignoreVary: true }).then(function (hit) {
            if (hit || kind === 'api') { return hit; }
            // ?v= stamps (Asset.V) or ?fit=crop style suffixes - an older copy
            // of the same file is better than nothing when offline.
            return cache.match(key, { ignoreVary: true, ignoreSearch: true });
        });
    });
}

// Resolves true when stored. Only complete, successful responses are kept; for
// API calls the JSON must also say Message == "Success" so a server-side error
// is never frozen into the offline menu.
function store(cacheName, key, res, kind) {
    if (!res || res.status === 206 || !(res.ok || res.type === 'opaque')) {
        return Promise.resolve(false);
    }
    var copy = res.clone();
    var check = kind === 'api'
        ? copy.clone().text().then(function (txt) {
            try {
                var j = JSON.parse(txt);
                return !(j && typeof j === 'object' && 'Message' in j && j.Message !== 'Success');
            } catch (e) { return false; }
        })
        : Promise.resolve(true);
    return check.then(function (ok) {
        if (!ok) { return false; }
        return caches.open(cacheName)
            .then(function (c) { return c.put(key, copy); })
            .then(function () { return true; });
    }).catch(function () { return false; });
}

function rememberPage(url) {
    loadState().then(function (s) {
        if (s.lastPage === url) { return; }
        s.lastPage = url;
        return saveState(s);
    }).catch(function () { });
}

function offlineFallback(req, kind, state) {
    if (kind === 'api') {
        // 200 + Message "Offline": the menu's success handlers just skip it,
        // instead of its error handlers popping "Service Not Connected".
        return new Response(JSON.stringify({ Message: 'Offline', IsOffline: true }), {
            status: 200, headers: { 'Content-Type': 'application/json; charset=utf-8' }
        });
    }
    if (kind === 'page' && state.lastPage) {
        return caches.open(state.current).then(function (c) {
            return c.match(state.lastPage, { ignoreVary: true });
        }).then(function (hit) {
            return hit || offlinePage();
        });
    }
    if (kind === 'page') { return offlinePage(); }
    return new Response('', { status: 504, statusText: 'Offline' });
}

function offlinePage() {
    var html = '<!DOCTYPE html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">' +
        '<title>Offline</title><style>body{font-family:system-ui,sans-serif;display:flex;align-items:center;justify-content:center;' +
        'min-height:100vh;margin:0;background:#f5f6f8;color:#333;text-align:center;padding:16px}</style></head><body><div>' +
        '<h2>Menu not available offline</h2><p>This page was not saved for offline use. Connect to the internet and try again.</p>' +
        '<button onclick="location.reload()">Retry</button></div></body></html>';
    return new Response(html, { status: 503, headers: { 'Content-Type': 'text/html; charset=utf-8' } });
}

/* ------------------------------------------------------------ keys ------- */

function assetKey(req) {
    // Range requests are looked up against the full copy.
    return req.headers.has('range') ? req.url : req;
}

function apiKey(req) {
    var url = new URL(req.url);
    var params = [];
    url.searchParams.forEach(function (v, k) {
        if (k !== '_') { params.push([k.toLowerCase(), v]); }
    });
    params.sort(function (a, b) { return a[0] < b[0] ? -1 : a[0] > b[0] ? 1 : 0; });
    var query = params.map(function (p) {
        return encodeURIComponent(p[0]) + '=' + encodeURIComponent(p[1]);
    }).join('&');

    return req.clone().text().then(function (body) {
        return sha256(canonicalBody(body));
    }).then(function (hash) {
        return API_KEY_ROOT + url.pathname.toLowerCase() + '?' + query + '&__b=' + hash;
    });
}

function canonicalBody(body) {
    if (!body) { return ''; }
    try { return JSON.stringify(canonical(JSON.parse(body))); } catch (e) { return body; }
}

function canonical(v) {
    if (Array.isArray(v)) { return v.map(canonical); }
    if (v && typeof v === 'object') {
        var out = {};
        Object.keys(v).sort().forEach(function (k) {
            if (v[k] !== undefined) { out[k.toLowerCase()] = canonical(v[k]); }
        });
        return out;
    }
    if (typeof v === 'number' || typeof v === 'boolean') { return String(v); }
    return v;
}

function sha256(text) {
    return crypto.subtle.digest('SHA-256', new TextEncoder().encode(text)).then(function (buf) {
        return Array.prototype.map.call(new Uint8Array(buf), function (b) {
            return ('0' + b.toString(16)).slice(-2);
        }).join('');
    });
}

/* ----------------------------------------------------------- ranges ------ */

function withRange(req, res) {
    var range = req.headers.get('range');
    if (!range || res.status !== 200 || res.type === 'opaque') { return res; }
    var m = /bytes=(\d*)-(\d*)/i.exec(range);
    if (!m) { return res; }
    return res.blob().then(function (blob) {
        var size = blob.size;
        var start, end;
        if (m[1] === '') {                       // bytes=-500 (last 500 bytes)
            start = Math.max(size - parseInt(m[2], 10), 0);
            end = size - 1;
        } else {
            start = parseInt(m[1], 10);
            end = m[2] === '' ? size - 1 : Math.min(parseInt(m[2], 10), size - 1);
        }
        if (start >= size || start > end) {
            return new Response('', { status: 416, headers: { 'Content-Range': 'bytes */' + size } });
        }
        var part = blob.slice(start, end + 1);
        return new Response(part, {
            status: 206,
            statusText: 'Partial Content',
            headers: {
                'Content-Type': res.headers.get('Content-Type') || blob.type || 'application/octet-stream',
                'Content-Range': 'bytes ' + start + '-' + end + '/' + size,
                'Content-Length': String(part.size),
                'Accept-Ranges': 'bytes'
            }
        });
    });
}

/* --------------------------------------------------------- messages ------ */

self.addEventListener('message', function (event) {
    var data = event.data || {};
    var port = event.ports && event.ports[0];
    var job;
    switch (data.type) {
        case 'GET_STATE':   job = getStateInfo(); break;
        case 'SYNC_BEGIN':  job = syncBegin(); break;
        case 'SYNC_COMMIT': job = syncCommit(); break;
        case 'SYNC_ABORT':  job = syncAbort(); break;
        case 'CLEAR_ALL':   job = clearAll(); break;
        default: return;
    }
    event.waitUntil(job.then(function (result) {
        if (port) { port.postMessage({ ok: true, result: result }); }
    }, function (err) {
        if (port) { port.postMessage({ ok: false, error: String(err && err.message || err) }); }
    }));
});

function countEntries(name) {
    return caches.open(name).then(function (c) { return c.keys(); })
        .then(function (k) { return k.length; }).catch(function () { return 0; });
}

function getStateInfo() {
    return loadState().then(function (s) {
        return countEntries(s.current).then(function (n) {
            return { version: SW_VERSION, state: s, entries: n };
        });
    });
}

function syncBegin() {
    return loadState().then(function (s) {
        var drop = (s.syncing && s.syncCache) ? caches.delete(s.syncCache) : Promise.resolve();
        return drop.then(function () {
            var next = Object.assign({}, s, {
                syncing: true,
                syncCache: PREFIX + 'data-' + Date.now(),
                syncStarted: Date.now()
            });
            return saveState(next).then(function () { return { syncCache: next.syncCache }; });
        });
    });
}

function syncCommit() {
    return loadState().then(function (s) {
        if (!s.syncing || !s.syncCache) { return { committed: false }; }
        var next = Object.assign({}, s, {
            current: s.syncCache, syncing: false, syncCache: null, syncStarted: 0, lastSync: Date.now()
        });
        return saveState(next).then(function () {
            return caches.keys();
        }).then(function (keys) {
            return Promise.all(keys.filter(function (k) {
                return k.indexOf(PREFIX + 'data-') === 0 && k !== next.current;
            }).map(function (k) { return caches.delete(k); }));
        }).then(function () {
            return countEntries(next.current);
        }).then(function (n) {
            return { committed: true, entries: n, lastSync: next.lastSync };
        });
    });
}

function syncAbort() {
    return loadState().then(function (s) {
        var drop = s.syncCache ? caches.delete(s.syncCache) : Promise.resolve();
        return drop.then(function () {
            return saveState(Object.assign({}, s, { syncing: false, syncCache: null, syncStarted: 0 }));
        }).then(function () { return { aborted: true }; });
    });
}

function clearAll() {
    stateMemo = null;
    return caches.keys().then(function (keys) {
        return Promise.all(keys.filter(function (k) { return k.indexOf(PREFIX) === 0; })
            .map(function (k) { return caches.delete(k); }));
    }).then(function () { return { cleared: true }; });
}

/* -------------------------------------------------------- lifecycle ------ */

self.addEventListener('install', function () { self.skipWaiting(); });

self.addEventListener('activate', function (event) {
    event.waitUntil(self.clients.claim());
});
