/* ============================================================================
   Employee Self Service (/ess) - db/146
   ----------------------------------------------------------------------------
   Tabs, the GPS punch, the attendance month, the annual leave request, the
   "Add to Home Screen" button and the service worker. No inline script (the
   site's CSP is script-src 'self'); the page's text comes from the JSON block
   #ess-text, its addresses from data-url-* on [data-ess-app].

   The distance shown on screen is only a guide: the server checks the
   distance and the GPS accuracy again on every punch (usp_EssSelfService).
   ============================================================================ */
(function () {
    "use strict";

    var body = document.body;
    var app = document.querySelector("[data-ess-app]");
    var text = {};
    try { text = JSON.parse((document.getElementById("ess-text") || {}).textContent || "{}"); } catch (e) { text = {}; }

    function t(key, a, b) {
        var s = text[key] || key;
        return s.replace("{0}", a == null ? "" : a).replace("{1}", b == null ? "" : b);
    }

    // ---------------------------------------------------------------- toast
    function toast(message, type) {
        var host = document.getElementById("ess-toasts");
        if (!host || !message) return;
        var el = document.createElement("div");
        el.className = "ess-toast" + (type ? " ess-toast--" + type : "");
        el.textContent = message;
        host.appendChild(el);
        setTimeout(function () { el.remove(); }, type === "error" ? 6000 : 3500);
    }

    // ------------------------------------------------------- service worker
    if ("serviceWorker" in navigator && body.dataset.essSw) {
        window.addEventListener("load", function () {
            navigator.serviceWorker.register(body.dataset.essSw, { scope: body.dataset.essScope }).catch(function () { /* optional */ });
        });
    }

    // ---------------------------------------------- Add to Home Screen (login)
    (function install() {
        var box = document.querySelector("[data-ess-install]");
        if (!box) return;
        var standalone = window.matchMedia("(display-mode: standalone)").matches || window.navigator.standalone === true;
        if (standalone) return;

        var ua = window.navigator.userAgent || "";
        var ios = /iphone|ipad|ipod/i.test(ua) || (/macintosh/i.test(ua) && navigator.maxTouchPoints > 1);
        if (ios) {
            box.hidden = false;
            box.querySelector("[data-ess-install-ios]").hidden = false;
            return;
        }

        var deferred = null;
        var btn = box.querySelector("[data-ess-install-btn]");
        window.addEventListener("beforeinstallprompt", function (e) {
            e.preventDefault();
            deferred = e;
            box.hidden = false;
            box.querySelector("[data-ess-install-android]").hidden = false;
            btn.hidden = false;
        });
        btn.addEventListener("click", function () {
            if (!deferred) return;
            deferred.prompt();
            deferred.userChoice.finally(function () { deferred = null; box.hidden = true; });
        });
        window.addEventListener("appinstalled", function () { box.hidden = true; });
    })();

    // the sign-in button: no double submit
    var loginForm = document.querySelector("[data-ess-login]");
    if (loginForm) {
        loginForm.addEventListener("submit", function () {
            var b = loginForm.querySelector("[data-ess-submit]");
            if (b) { setTimeout(function () { b.disabled = true; }, 0); }
        });
    }

    if (!app) return;

    var url = app.dataset;
    var tokenInput = app.querySelector("input[name='__RequestVerificationToken']");
    var token = tokenInput ? tokenInput.value : "";

    // ------------------------------------------------------------- requests
    function request(method, address, data) {
        var options = {
            method: method,
            credentials: "same-origin",
            headers: { "X-Requested-With": "XMLHttpRequest", "RequestVerificationToken": token }
        };
        if (data) {
            var form = new URLSearchParams();
            Object.keys(data).forEach(function (k) { if (data[k] != null && data[k] !== "") form.append(k, data[k]); });
            options.body = form;
        }
        return fetch(address, options).then(function (response) {
            if (response.status === 401) {
                window.location.href = url.urlLogin + "?reason=timeout&returnUrl=" + encodeURIComponent(window.location.pathname);
                throw new Error("signed out");
            }
            if (!response.ok) throw new Error("HTTP " + response.status);
            var type = response.headers.get("content-type") || "";
            return type.indexOf("json") >= 0 ? response.json() : response.text();
        });
    }

    // ----------------------------------------------------------------- tabs
    var tabs = Array.prototype.slice.call(app.querySelectorAll("[data-ess-tab]"));
    var panels = Array.prototype.slice.call(app.querySelectorAll("[data-ess-panel]"));

    function showTab(name, push) {
        if (!panels.some(function (p) { return p.dataset.essPanel === name; })) name = "punch";
        tabs.forEach(function (b) {
            var on = b.dataset.essTab === name;
            b.classList.toggle("is-active", on);
            b.setAttribute("aria-selected", on ? "true" : "false");
        });
        panels.forEach(function (p) { p.classList.toggle("is-active", p.dataset.essPanel === name); });
        if (push !== false) history.replaceState(null, "", name === "punch" ? window.location.pathname : "#" + name);
        window.scrollTo(0, 0);
        if (name === "punch") geo.start(); else geo.stop();
    }

    tabs.forEach(function (b) { b.addEventListener("click", function () { showTab(b.dataset.essTab); }); });
    app.addEventListener("click", function (e) {
        var go = e.target.closest("[data-ess-goto]");
        if (go) { e.preventDefault(); showTab(go.dataset.essGoto); }
    });

    // ---------------------------------------------------------------- clock
    function tick() {
        var el = app.querySelector("[data-ess-clock]");
        if (!el) return;
        var d = new Date();
        el.textContent = String(d.getHours()).padStart(2, "0") + ":" + String(d.getMinutes()).padStart(2, "0");
    }
    setInterval(tick, 10000);

    // ------------------------------------------------------------------ GPS
    function distance(lat1, lng1, lat2, lng2) {
        var r = Math.PI / 180;
        var a = Math.pow(Math.sin((lat2 - lat1) * r / 2), 2)
              + Math.cos(lat1 * r) * Math.cos(lat2 * r) * Math.pow(Math.sin((lng2 - lng1) * r / 2), 2);
        return 6371000 * 2 * Math.asin(Math.sqrt(a));
    }

    var geo = {
        watch: null,
        places: null,
        maxAccuracy: 50,
        fix: null,

        card: function () { return app.querySelector("[data-ess-punch]"); },

        start: function () {
            var card = this.card();
            if (!card || card.dataset.next === "DONE" || card.dataset.hasLocation !== "1" || this.watch !== null) return;
            if (!("geolocation" in navigator)) { this.show("off", t("gpsUnsupported"), ""); return; }
            if (!navigator.onLine) { this.show("off", t("offline"), ""); return; }

            var self = this;
            this.show("wait", t("locating"), t("hintLocating"));
            var load = this.places ? Promise.resolve() : request("GET", url.urlLocations).then(function (data) {
                self.places = data.locations || [];
                self.maxAccuracy = data.maxAccuracy || 50;
            });
            load.then(function () {
                if (self.watch !== null) return;
                self.watch = navigator.geolocation.watchPosition(
                    function (pos) { self.update(pos.coords); },
                    function (err) {
                        self.fix = null;
                        if (err.code === 1) self.show("out", t("gpsDenied"), "");
                        else self.show("wait", t("locating"), t("hintLocating"));
                    },
                    { enableHighAccuracy: true, maximumAge: 5000, timeout: 20000 });
            }).catch(function () { self.show("off", t("error"), ""); });
        },

        stop: function () {
            if (this.watch !== null) { navigator.geolocation.clearWatch(this.watch); this.watch = null; }
        },

        update: function (c) {
            this.fix = { lat: c.latitude, lng: c.longitude, accuracy: c.accuracy };
            var best = null;
            (this.places || []).forEach(function (p) {
                var d = distance(c.latitude, c.longitude, p.lat, p.lng);
                if (!best || d < best.d) best = { d: d, p: p };
            });
            if (!best) { this.show("off", t("noLocation"), ""); return; }

            var meters = Math.round(best.d);
            var accuracy = Math.round(c.accuracy);
            if (best.d <= best.p.radius && c.accuracy <= this.maxAccuracy) {
                this.show("in", t("inside", best.p.name, meters), t("hintInside"), true);
            } else if (best.d <= best.p.radius) {
                this.show("wait", t("inside", best.p.name, meters), t("hintWeak", accuracy));
            } else {
                this.show("out", t("outside", meters, best.p.name), t("hintOutside", best.p.radius));
            }
        },

        show: function (state, label, hint, enable) {
            var card = this.card();
            if (!card) return;
            var badge = card.querySelector("[data-ess-geo]");
            var btn = card.querySelector("[data-ess-punch-btn]");
            if (badge) {
                badge.className = "ess-geo ess-geo--" + state;
                var txt = badge.querySelector("[data-ess-geo-text]");
                if (txt) txt.textContent = label;
            }
            var h = card.querySelector("[data-ess-geo-hint]");
            if (h) h.textContent = hint || "";
            if (btn && !btn.classList.contains("is-busy")) btn.disabled = !enable;
        }
    };

    // ---------------------------------------------------------------- punch
    app.addEventListener("click", function (e) {
        var btn = e.target.closest("[data-ess-punch-btn]");
        if (!btn || btn.disabled || !geo.fix) return;
        if (!navigator.onLine) { toast(t("offline"), "error"); return; }

        btn.classList.add("is-busy");
        if (navigator.vibrate) navigator.vibrate(15);
        request("POST", url.urlPunch, {
            Type: btn.dataset.type,
            Lat: geo.fix.lat.toFixed(7),
            Lng: geo.fix.lng.toFixed(7),
            Accuracy: geo.fix.accuracy.toFixed(2)
        }).then(function (res) {
            if (res.ok) {
                toast(res.message, "success");
                if (navigator.vibrate) navigator.vibrate([20, 60, 20]);
                return reloadHome();
            }
            btn.classList.remove("is-busy");
            toast(res.message || t("error"), "error");
        }).catch(function () {
            btn.classList.remove("is-busy");
            toast(t("error"), "error");
        });
    });

    function reloadHome() {
        geo.stop();
        return request("GET", url.urlHome).then(function (html) {
            app.querySelector("[data-ess-home]").innerHTML = html;
            reloadAttendance();
            if (app.querySelector("[data-ess-panel='punch']").classList.contains("is-active")) geo.start();
        });
    }

    // ------------------------------------------------------- attendance month
    function reloadAttendance(month) {
        var holder = app.querySelector("[data-ess-attendance]");
        var select = holder.querySelector("[data-ess-month]");
        var m = month || (select ? select.value : "");
        return request("GET", url.urlAttendance + (m ? "?month=" + encodeURIComponent(m) : "")).then(function (html) {
            holder.innerHTML = html;
        });
    }

    app.addEventListener("change", function (e) {
        if (e.target.matches("[data-ess-month]")) {
            reloadAttendance(e.target.value).catch(function () { toast(t("error"), "error"); });
        }
    });

    // ------------------------------------------------------- annual leave
    var form = app.querySelector("[data-ess-leave-form]");
    var sheetEl = document.getElementById("ess-leave-sheet");
    var acceptUnpaid = false;

    function leaveData() {
        return {
            StartDate: form.elements.StartDate.value,
            EndDate: form.elements.EndDate.value,
            Reason: form.elements.Reason.value,
            AcceptUnpaid: acceptUnpaid ? "true" : "false"
        };
    }

    function preview() {
        var box = form.querySelector("[data-ess-leave-preview]");
        var from = form.elements.StartDate, to = form.elements.EndDate;
        if (from.value && (!to.value || to.value < from.value)) to.value = from.value;
        to.min = from.value || to.min;
        acceptUnpaid = false;
        form.querySelector("[data-ess-leave-unpaid]").hidden = true;
        if (!from.value || !to.value) { box.hidden = true; return; }

        request("POST", url.urlLeavePreview, leaveData()).then(function (res) {
            if (!res.ready) { box.hidden = true; return; }
            box.hidden = false;
            var info = box.querySelector(".ess-preview");
            info.innerHTML = "";
            if (res.days != null) {
                info.appendChild(pair(t("daysRequested"), res.days));
                if (res.after != null) info.appendChild(pair(t("balanceAfter"), res.after));
            }
            info.hidden = res.days == null;
            var list = box.querySelector(".ess-problems");
            list.innerHTML = "";
            (res.problems || []).forEach(function (p) {
                var li = document.createElement("li");
                li.textContent = p;
                list.appendChild(li);
            });
        }).catch(function () { box.hidden = true; });
    }

    function pair(label, value) {
        var span = document.createElement("span");
        span.append(label + ": ");
        var b = document.createElement("b");
        b.textContent = value;
        span.appendChild(b);
        return span;
    }

    if (form) {
        form.elements.StartDate.addEventListener("change", preview);
        form.elements.EndDate.addEventListener("change", preview);

        form.addEventListener("submit", function (e) {
            e.preventDefault();
            var submit = form.querySelector("[data-ess-leave-submit]");
            submit.disabled = true;
            request("POST", url.urlLeaveSubmit, leaveData()).then(function (res) {
                submit.disabled = false;
                if (res.success) {
                    toast(res.message, "success");
                    form.reset();
                    acceptUnpaid = false;
                    form.querySelector("[data-ess-leave-preview]").hidden = true;
                    form.querySelector("[data-ess-leave-unpaid]").hidden = true;
                    submit.textContent = submit.dataset.label || submit.textContent;
                    if (window.bootstrap) window.bootstrap.Offcanvas.getOrCreateInstance(sheetEl).hide();
                    reloadLeave();
                    return;
                }
                if (res.errorCode === "UNPAID_CONFIRM") {
                    // more days than the balance: the rest is unpaid - only with the employee's consent
                    acceptUnpaid = true;
                    var warn = form.querySelector("[data-ess-leave-unpaid]");
                    warn.querySelector("span").textContent = res.message;
                    warn.hidden = false;
                    submit.dataset.label = submit.dataset.label || submit.textContent;
                    submit.textContent = t("confirmUnpaid");
                    return;
                }
                var message = res.message;
                if (!message && res.errors) {
                    var first = Object.keys(res.errors)[0];
                    message = first ? res.errors[first][0] : "";
                }
                toast(message || t("error"), "error");
            }).catch(function () {
                submit.disabled = false;
                toast(t("error"), "error");
            });
        });
    }

    function reloadLeave() {
        return request("GET", url.urlLeave).then(function (html) {
            var holder = app.querySelector("[data-ess-leave]");
            holder.innerHTML = html;
            var free = holder.querySelector("[data-ess-leave-free-value]");
            var target = app.querySelector("[data-ess-leave-free]");
            if (free && target) target.textContent = free.dataset.essLeaveFreeValue;
            return reloadHome();
        });
    }

    // ------------------------------------------------------------ offline
    var offline = null;
    function connection() {
        if (navigator.onLine) {
            if (offline) { offline.remove(); offline = null; }
            if (app.querySelector("[data-ess-panel='punch']").classList.contains("is-active")) geo.start();
            return;
        }
        if (!offline) {
            offline = document.createElement("div");
            offline.className = "ess-offline";
            offline.textContent = t("offline");
            document.body.appendChild(offline);
        }
        geo.stop();
    }
    window.addEventListener("online", connection);
    window.addEventListener("offline", connection);

    // the GPS is only on while the Punch tab is on screen (battery)
    document.addEventListener("visibilitychange", function () {
        if (document.hidden) geo.stop();
        else if (app.querySelector("[data-ess-panel='punch']").classList.contains("is-active")) geo.start();
    });

    // start on the tab in the address (#attendance, #leave, #profile)
    showTab((window.location.hash || "#punch").slice(1), false);
    connection();
})();
