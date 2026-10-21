/* ==========================================================================
 * HRMS Kuwait - Audit Report (db/60, db/62)
 * One grid, two places:
 *   - the Audit Report page ([data-aud-page]): company, employee, transaction
 *     type, date range and search; the filters are kept in the address
 *   - the employee profile's popup ([data-aud-panel]): that employee only,
 *     a search bar and the date range
 * Column headers sort the whole result on the server; Export takes the same
 * filters and sort.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var NAMES = ["company", "employee", "type", "from", "to", "search"];

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
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

    /**
     * Wires one audit grid. options.employee fixes the employee (the popup);
     * options.address keeps the filters in the page address (the report page).
     */
    function setup(root, options) {
        options = options || {};
        var field = function (name) { return $('[data-aud-filter="' + name + '"]', root); };
        var slot = $("[data-aud-slot]", root), counter = $("[data-aud-count]", root), exportLink = $("[data-aud-export]", root);
        var state = { page: 1, sort: "", dir: "" };
        var defaults = {};
        NAMES.forEach(function (n) { var f = field(n); if (f) { defaults[n] = f.value; } });

        var values = function () {
            var v = { page: state.page, sort: state.sort, dir: state.dir };
            NAMES.forEach(function (n) {
                var f = field(n);
                if (f) { v[n] = n === "search" ? f.value.trim() : f.value; }
            });
            if (options.employee) { v.employee = options.employee; v.mode = "employee"; }
            return v;
        };

        if (options.address) {
            // /audit?employee=12&type=g:calendar&from=2026-01-01&sort=Type&dir=ASC restores the report
            var p = new URLSearchParams(HRMS.pageUrl().search);
            NAMES.forEach(function (n) {
                var f = field(n);
                if (f && p.has(n)) { f.value = p.get(n); f.dispatchEvent(new Event("hrms:refresh")); }
            });
            if (p.has("page")) { state.page = parseInt(p.get("page"), 10) || 1; }
            if (p.has("sort")) { state.sort = p.get("sort"); state.dir = p.get("dir") || ""; }
        }

        var load = function () {
            var v = values();
            var query = qs(v);
            exportLink.href = root.getAttribute("data-urls-export") + "?" + qs(Object.assign({}, v, { page: "", mode: "" }));
            if (options.address && window.history && window.history.replaceState) {
                window.history.replaceState(null, "", window.location.pathname + (query ? "?" + query : ""));
            }
            slot.setAttribute("aria-busy", "true");
            return HRMS.getHtml(root.getAttribute("data-urls-grid") + "?" + query).then(function (html) {
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
        };
        var reload = function () { state.page = 1; load(); };
        var clearPresets = function () { $all("[data-aud-preset]", root).forEach(function (x) { x.classList.remove("is-active"); }); };

        ["company", "employee", "type"].forEach(function (n) { var f = field(n); if (f) { f.addEventListener("change", reload); } });
        ["from", "to"].forEach(function (n) {
            var f = field(n);
            if (f) { f.addEventListener("change", function () { clearPresets(); reload(); }); }
        });
        field("search").addEventListener("input", debounce(reload, 300));
        // keep "from" before "to"
        field("from").addEventListener("change", function () { field("to").min = field("from").value || ""; });
        field("to").addEventListener("change", function () { field("from").max = field("to").value || ""; });

        $all("[data-aud-preset]", root).forEach(function (b) {
            b.addEventListener("click", function () {
                var preset = b.getAttribute("data-aud-preset");
                var to = new Date(), from = new Date();
                from.setDate(from.getDate() - (parseInt(preset, 10) || 0));
                field("from").value = preset === "all" ? "" : iso(from);
                field("to").value = iso(to);
                field("from").max = field("to").value;
                field("to").min = field("from").value || "";
                $all("[data-aud-preset]", root).forEach(function (x) { x.classList.toggle("is-active", x === b); });
                reload();
            });
        });

        $("[data-aud-reset]", root).addEventListener("click", function () {
            Object.keys(defaults).forEach(function (n) {
                var f = field(n);
                f.value = n === "employee" ? "" : defaults[n];
                f.dispatchEvent(new Event("hrms:refresh"));
            });
            state.sort = ""; state.dir = "";
            $all("[data-aud-preset]", root).forEach(function (x) { x.classList.toggle("is-active", x.hasAttribute("data-aud-preset-default")); });
            reload();
        });

        slot.addEventListener("click", function (ev) {
            // a column header: sort the whole result
            var sort = ev.target.closest("[data-sort]");
            if (sort) {
                state.sort = sort.getAttribute("data-sort");
                state.dir = sort.getAttribute("data-direction");
                reload();
                return;
            }
            var pg = ev.target.closest("[data-page]");
            if (pg && !pg.disabled) { state.page = parseInt(pg.getAttribute("data-page"), 10) || 1; load(); return; }
            // the filter icon next to a name (report page): this employee only
            var only = ev.target.closest("[data-aud-only]");
            var sel = field("employee");
            if (only && sel) {
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
        return { reload: reload };
    }
    HRMS.auditSetup = setup;

    // ---- the Audit Report page
    var page = document.querySelector("[data-aud-page]");
    if (page) { setup(page, { address: true }); }

    // ---- the employee profile: "Audit history" opens this employee's audit in a popup
    var modalEl = document.getElementById("emp-audit-modal");
    if (modalEl) {
        var body = $("[data-aud-modal-body]", modalEl);
        var panel = null;
        modalEl.addEventListener("show.bs.modal", function () {
            if (panel) { panel.reload(); return; }
            HRMS.getHtml(modalEl.getAttribute("data-panel-url")).then(function (html) {
                body.innerHTML = html;
                var root = $("[data-aud-panel]", body);
                panel = setup(root, { employee: root.getAttribute("data-employee") });
            }, function () {
                body.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' +
                    HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div>";
            });
        });
    }
})();
