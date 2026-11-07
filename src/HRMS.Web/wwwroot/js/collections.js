/* ==========================================================================
 * HRMS Kuwait - Payroll Components > Collection (db/115)
 * --------------------------------------------------------------------------
 * Work Permit Collection receivables: pick the company and the payroll month,
 * see Total / Pending / Collected, mark what was received (one row or the
 * ticked rows) and set a mistake back to pending. Every change is audited
 * (history dialog).
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-col-page]");
    if (!page) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function url(name) { return page.getAttribute("data-url-" + name); }
    function qs(base, params) {
        var parts = Object.keys(params).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); });
        return base + (base.indexOf("?") >= 0 ? "&" : "?") + parts.join("&");
    }
    function modal(el) { return window.bootstrap.Modal.getOrCreateInstance(el); }
    function busy(button, on) {
        if (!button) { return; }
        button.disabled = on;
        button.classList.toggle("is-busy", on);
    }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments; clearTimeout(t); t = setTimeout(function () { fn.apply(null, a); }, wait); };
    };
    function failed(text) {
        return '<div class="hrms-card"><div class="hrms-empty"><p class="hrms-empty__title">' +
            HRMS.escape(text || HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div></div>";
    }

    var companySel = $("[data-col-company]"), monthSel = $("[data-col-month]"), statusSel = $("[data-col-status]");
    var searchIn = $("[data-col-search]"), slot = $("[data-col-slot]");
    // db/123: on a payroll's workspace tab the month is the payroll's own
    var state = { month: page.getAttribute("data-col-fixed-month") || null };

    /* ---- the payroll months of the company ---- */
    function loadMonths() {
        var company = companySel.value;
        monthSel.disabled = true;
        monthSel.innerHTML = '<option value="">' + HRMS.escape(HRMS.t("js.col_loading_months", "Loading months…")) + "</option>";
        if (!company) { slot.innerHTML = ""; return Promise.resolve(); }
        return HRMS.getJson(qs(url("months"), { companyId: company })).then(function (months) {
            monthSel.innerHTML = "";
            if (!months || !months.length) {
                monthSel.innerHTML = '<option value="">' + HRMS.escape(HRMS.t("js.col_no_months", "No payroll yet")) + "</option>";
                state.month = null;
                return loadGrid();
            }
            months.forEach(function (m) {
                var o = document.createElement("option");
                o.value = m.value;
                // the months with something still to collect say so
                o.textContent = m.pending > 0
                    ? HRMS.t("js.col_month_pending", "{0} · {1} pending", m.text, Number(m.pending).toFixed(3))
                    : m.text;
                monthSel.appendChild(o);
            });
            // keep the month picked before (another company), else the newest
            if (state.month && months.some(function (m) { return m.value === state.month; })) { monthSel.value = state.month; }
            state.month = monthSel.value;
            monthSel.disabled = false;
            return loadGrid();
        }, function () {
            monthSel.innerHTML = '<option value="">—</option>';
            slot.innerHTML = failed();
        });
    }

    /* ---- the summary and the list ---- */
    function loadGrid() {
        slot.setAttribute("aria-busy", "true");
        var params = { companyId: companySel.value, month: monthSel.disabled ? "" : monthSel.value, status: statusSel.value, search: searchIn.value.trim() };
        return HRMS.getHtml(qs(url("grid"), params)).then(function (html) {
            slot.innerHTML = html;
            slot.removeAttribute("aria-busy");
            syncPicks();
        }, function () {
            slot.removeAttribute("aria-busy");
            slot.innerHTML = failed();
        });
    }

    companySel.addEventListener("change", loadMonths);
    monthSel.addEventListener("change", function () { state.month = monthSel.value; loadGrid(); });
    statusSel.addEventListener("change", loadGrid);
    searchIn.addEventListener("input", debounce(loadGrid, 300));

    /* ---- ticked rows ---- */
    function picked() { return $all("[data-col-pick]:checked", slot).map(function (c) { return c.value; }); }
    function syncPicks() {
        var bar = $("[data-col-bulk]", slot);
        var all = $("[data-col-all]", slot);
        var boxes = $all("[data-col-pick]", slot);
        var ids = picked();
        if (bar) {
            bar.hidden = ids.length === 0;
            var t = $("[data-col-bulk-text]", bar);
            if (t) { t.textContent = ids.length === 1 ? t.getAttribute("data-one") : t.getAttribute("data-many").replace("{0}", ids.length); }
        }
        if (all) {
            all.checked = boxes.length > 0 && ids.length === boxes.length;
            all.indeterminate = ids.length > 0 && ids.length < boxes.length;
        }
        boxes.forEach(function (b) { var tr = b.closest("tr"); if (tr) { tr.classList.toggle("is-picked", b.checked); } });
    }
    slot.addEventListener("change", function (ev) {
        if (ev.target.matches("[data-col-all]")) {
            $all("[data-col-pick]", slot).forEach(function (b) { b.checked = ev.target.checked; });
        }
        if (ev.target.matches("[data-col-all], [data-col-pick]")) { syncPicks(); }
    });

    /* ---- mark as received ---- */
    var collectModal = $("#col-collect-modal"), collectForm = $("[data-col-collect-form]");
    var collectIds = [];
    function openCollect(ids, what) {
        collectIds = ids;
        $("[data-col-collect-what]").textContent = what;
        collectForm.reset();
        $("#col-date").value = $("#col-date").getAttribute("value");
        $all(".is-invalid", collectForm).forEach(function (f) { f.classList.remove("is-invalid"); });
        modal(collectModal).show();
    }
    collectForm.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var date = $("#col-date");
        if (!date.value) {
            date.classList.add("is-invalid"); date.focus();
            HRMS.toast(HRMS.t("js.col_enter_date", "Enter the date it was received."), "error");
            return;
        }
        var fd = new FormData(collectForm);
        fd.set("ids", collectIds.join(","));
        var button = $("[data-col-collect-save]");
        busy(button, true);
        HRMS.post(url("collect"), fd).then(function (res) {
            busy(button, false);
            HRMS.toast(res.message, res.success ? "success" : "error");
            if (res.success) { modal(collectModal).hide(); }
            if (res.success || res.errorCode === "NOT_FOUND" || res.errorCode === "ALREADY") { loadMonths(); }
        }, function (error) { busy(button, false); HRMS.toast(error.message, "error"); });
    });

    /* ---- set back to pending ---- */
    var reopenModal = $("#col-reopen-modal"), reopenForm = $("[data-col-reopen-form]"), reopenId = null;
    reopenForm.addEventListener("submit", function (ev) {
        ev.preventDefault();
        var comment = $("#col-reopen-comment");
        if (!comment.value.trim()) {
            comment.classList.add("is-invalid"); comment.focus();
            HRMS.toast(HRMS.t("js.col_enter_reason", "Enter why it is set back to pending."), "error");
            return;
        }
        var fd = new FormData();
        fd.set("id", reopenId);
        fd.set("comment", comment.value.trim());
        var button = $("[data-col-reopen-save]");
        busy(button, true);
        HRMS.post(url("reopen"), fd).then(function (res) {
            busy(button, false);
            HRMS.toast(res.message, res.success ? "success" : "error");
            if (res.success) { modal(reopenModal).hide(); loadMonths(); }
        }, function (error) { busy(button, false); HRMS.toast(error.message, "error"); });
    });

    /* ---- row buttons ---- */
    slot.addEventListener("click", function (ev) {
        var btn = ev.target.closest("[data-col-collect], [data-col-reopen], [data-col-history], [data-col-collect-selected]");
        if (!btn) { return; }
        var tr = btn.closest("tr");
        var name = tr ? tr.getAttribute("data-name") : "";
        var amount = tr ? tr.getAttribute("data-amount") : "";
        if (btn.matches("[data-col-collect-selected]")) {
            var ids = picked();
            if (!ids.length) { return; }
            var total = $all("[data-col-pick]:checked", slot).reduce(function (sum, b) {
                var row = b.closest("tr");
                return sum + parseFloat(String(row.getAttribute("data-amount") || "0").replace(/,/g, ""));
            }, 0);
            openCollect(ids, HRMS.t("js.col_collect_many", "{0} collections · KWD {1}", ids.length, total.toFixed(3)));
        } else if (btn.matches("[data-col-collect]")) {
            openCollect([btn.getAttribute("data-col-collect")], HRMS.t("js.col_collect_one", "{0} · KWD {1}", name, amount));
        } else if (btn.matches("[data-col-reopen]")) {
            reopenId = btn.getAttribute("data-col-reopen");
            $("[data-col-reopen-what]").textContent = HRMS.t("js.col_collect_one", "{0} · KWD {1}", name, amount);
            $("#col-reopen-comment").value = "";
            $("#col-reopen-comment").classList.remove("is-invalid");
            modal(reopenModal).show();
        } else if (btn.matches("[data-col-history]")) {
            var body = $("[data-col-history-body]");
            $("[data-col-history-name]").textContent = name ? "· " + name : "";
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            modal($("#col-history-modal")).show();
            HRMS.getHtml(qs(url("history"), { id: btn.getAttribute("data-col-history") })).then(function (html) {
                body.innerHTML = html;
            }, function () { body.innerHTML = '<p class="hrms-muted">' + HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p>"; });
        }
    });

    loadMonths();
})();
