/* ==========================================================================
 * HRMS Kuwait - Audit Report (db/60)
 * Filters (company, employee, transaction type, date range, search) reload
 * the server-rendered grid; Export takes the same filters. The filters are
 * kept in the address so a filtered report can be bookmarked or shared.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-aud-page]");
    if (!page) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function field(name) { return $('[data-aud-filter="' + name + '"]'); }
    function qs(params) {
        return Object.keys(params).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function iso(d) {
        return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2);
    }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments; clearTimeout(t); t = setTimeout(function () { fn.apply(null, a); }, wait); };
    };

    var slot = $("[data-aud-slot]"), counter = $("[data-aud-count]"), exportLink = $("[data-aud-export]");
    var state = { page: 1 };
    var defaults = {};
    ["company", "employee", "type", "from", "to", "search"].forEach(function (n) { var f = field(n); if (f) { defaults[n] = f.value; } });

    function values() {
        var v = { page: state.page };
        ["company", "employee", "type", "from", "to", "search"].forEach(function (n) {
            var f = field(n);
            if (f) { v[n] = n === "search" ? f.value.trim() : f.value; }
        });
        return v;
    }

    // an address like /audit?employee=12&type=g:calendar&from=2026-01-01 restores the filters
    (function restore() {
        var p = new URLSearchParams(window.location.search);
        ["company", "employee", "type", "from", "to", "search"].forEach(function (n) {
            var f = field(n);
            if (f && p.has(n)) {
                f.value = p.get(n);
                f.dispatchEvent(new Event("hrms:refresh"));
            }
        });
        if (p.has("page")) { state.page = parseInt(p.get("page"), 10) || 1; }
    })();

    function load() {
        var v = values();
        var query = qs(v);
        exportLink.href = page.getAttribute("data-urls-export") + "?" + qs(Object.assign({}, v, { page: "" }));
        if (window.history && window.history.replaceState) {
            window.history.replaceState(null, "", window.location.pathname + (query ? "?" + query : ""));
        }
        slot.setAttribute("aria-busy", "true");
        return HRMS.getHtml(page.getAttribute("data-urls-grid") + "?" + query).then(function (html) {
            slot.innerHTML = html;
            slot.removeAttribute("aria-busy");
            var holder = $("[data-count-text]", slot);
            counter.textContent = holder ? holder.getAttribute("data-count-text") : "";
        }, function (error) {
            slot.removeAttribute("aria-busy");
            slot.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' +
                HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div>";
            HRMS.toast((error && error.message) || HRMS.t("js.pr_failed", "The request could not be completed."), "error");
        });
    }
    function reload() { state.page = 1; load(); }

    ["company", "employee", "type", "from", "to"].forEach(function (n) {
        var f = field(n);
        if (f) { f.addEventListener("change", reload); }
    });
    field("search").addEventListener("input", debounce(reload, 300));

    // keep "from" before "to"
    field("from").addEventListener("change", function () { field("to").min = field("from").value || ""; });
    field("to").addEventListener("change", function () { field("from").max = field("to").value || ""; });

    $all("[data-aud-preset]").forEach(function (b) {
        b.addEventListener("click", function () {
            var days = parseInt(b.getAttribute("data-aud-preset"), 10) || 0;
            var to = new Date(), from = new Date();
            from.setDate(from.getDate() - days);
            field("from").value = iso(from);
            field("to").value = iso(to);
            field("from").max = field("to").value;
            field("to").min = field("from").value;
            $all("[data-aud-preset]").forEach(function (x) { x.classList.toggle("is-active", x === b); });
            reload();
        });
    });

    $("[data-aud-reset]").addEventListener("click", function () {
        Object.keys(defaults).forEach(function (n) {
            var f = field(n);
            f.value = n === "employee" ? "" : defaults[n];
            f.dispatchEvent(new Event("hrms:refresh"));
        });
        $all("[data-aud-preset]").forEach(function (x) { x.classList.remove("is-active"); });
        reload();
    });

    slot.addEventListener("click", function (ev) {
        var pg = ev.target.closest("[data-page]");
        if (pg && !pg.disabled) { state.page = parseInt(pg.getAttribute("data-page"), 10) || 1; load(); return; }
        // the filter icon next to a name: this employee only
        var only = ev.target.closest("[data-aud-only]");
        if (only) {
            var sel = field("employee");
            var id = only.getAttribute("data-aud-only");
            if (!sel.querySelector('option[value="' + id + '"]')) {
                var o = document.createElement("option");
                o.value = id; o.textContent = only.getAttribute("data-aud-only-name") || id;
                sel.appendChild(o);
            }
            sel.value = id;
            sel.dispatchEvent(new Event("hrms:refresh"));
            reload();
        }
    });

    load();
})();
