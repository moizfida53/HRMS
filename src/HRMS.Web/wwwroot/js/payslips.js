/* ==========================================================================
 * HRMS Kuwait - Payslips (db/42-43)
 * Generate / Employee Payslips / Email Payslips, the printable payslip and
 * My Payslips. Panels are server-rendered; this file only wires them up.
 * Every POST carries the anti-forgery token (HRMS.post); every text shown
 * comes from the server (already translated) or from HRMS.t("js.ps_*").
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-ps-page]");
    var FLASH = "hrms-ps-flash";

    /* ------------------------------------------------------------- helpers */

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function qs(params) {
        return Object.keys(params).filter(function (k) {
            return params[k] !== null && params[k] !== undefined && params[k] !== "";
        }).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function withQs(url, params) { var q = qs(params); return q ? url + (url.indexOf("?") >= 0 ? "&" : "?") + q : url; }
    function busy(button, on) {
        if (!button) { return; }
        button.disabled = !!on;
        button.classList.toggle("is-busy", !!on);
    }
    function failed() { return HRMS.t("js.ps_failed", "The request could not be completed."); }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments, self = this; clearTimeout(t); t = setTimeout(function () { fn.apply(self, a); }, wait); };
    };

    /** POST a FormData; on success reload with the message shown once, on failure toast it. */
    function post(url, body, button) {
        busy(button, true);
        return HRMS.post(url, body).then(function (res) {
            if (res && res.success) {
                try { if (res.message) { window.sessionStorage.setItem(FLASH, res.message); } } catch (e) { /* private mode */ }
                window.location.reload();
            } else {
                busy(button, false);
                HRMS.toast((res && res.message) || failed(), "error");
            }
        }, function (error) {
            busy(button, false);
            HRMS.toast((error && error.message) || failed(), "error");
        });
    }
    (function showFlash() {
        try {
            var msg = window.sessionStorage.getItem(FLASH);
            if (msg) { window.sessionStorage.removeItem(FLASH); HRMS.toast(msg, "success"); }
        } catch (e) { /* private mode */ }
    })();

    /* ====================================================== print / save */

    (function wirePrint() {
        var button = $("[data-ps-print]");
        if (button) { button.addEventListener("click", function () { window.print(); }); }
        // ?print=1 (the printer icon of a list) opens the print dialog straight away.
        if ($("[data-ps-doc]") && /[?&]print=1(&|$)/.test(window.location.search)) {
            window.setTimeout(function () { window.print(); }, 300);
        }
    })();

    /* A payslip that is not generated yet (or outdated) - generate this one only. */
    (function wireGenerateOne() {
        var button = $("[data-ps-generate-one]");
        if (!button) { return; }
        button.addEventListener("click", function () {
            var fd = new FormData();
            fd.append("run", button.getAttribute("data-ps-run-id"));
            fd.append("employeeIds", button.getAttribute("data-ps-generate-one"));
            post(button.getAttribute("data-url"), fd, button);
        });
    })();

    /* ======================================================== My Payslips */

    if (page && page.getAttribute("data-ps-page") === "my") {
        page.addEventListener("click", function (e) {
            var btn = e.target.closest("[data-page]");
            if (!btn || btn.disabled) { return; }
            window.location.href = withQs(window.location.pathname, { page: btn.getAttribute("data-page") });
        });
        return;
    }

    if (!page) { return; }

    var mode = page.getAttribute("data-ps-page");
    var runId = page.getAttribute("data-run") || "";

    /* ================================================== payroll picker */

    var runSelect = $("[data-ps-run]", page);
    var yearSelect = $("[data-ps-year]", page);
    var monthSelect = $("[data-ps-month]", page);
    var pageYear = page.getAttribute("data-year") || "";
    var pageMonth = page.getAttribute("data-month") || "";

    /** Period options follow the year; payroll options follow the year and period. */
    function narrow() {
        var y = yearSelect ? yearSelect.value : "";
        if (monthSelect) {
            HRMS.filterOptions(monthSelect, function (o) { return !o.value || !y || o.getAttribute("data-year") === y; });
        }
        var m = monthSelect ? monthSelect.value : "";
        if (runSelect && (yearSelect || monthSelect)) {
            HRMS.filterOptions(runSelect, function (o) {
                return !o.value || ((!y || o.getAttribute("data-year") === y) && (!m || o.getAttribute("data-month") === m));
            });
        }
    }
    if (yearSelect || monthSelect) { narrow(); }

    /** Opens the page again for the chosen payroll / year / period, keeping the list filters. */
    function go(params) {
        var status = $("[data-ps-status]", page), dept = $("[data-ps-dept]", page), q = $("[data-ps-search]", page);
        params.status = status && status.value !== "ALL" ? status.value : "";
        params.dept = dept ? dept.value : "";
        params.q = q ? q.value.trim() : "";
        window.location.href = withQs(page.getAttribute("data-urls-page"), params);
    }
    function periodChanged() {
        narrow();
        // Employee Payslips keeps the payroll when it still matches (else "All payrolls");
        // Email Payslips opens the latest payroll of the chosen year / period.
        go({
            year: yearSelect ? yearSelect.value : "",
            month: monthSelect ? monthSelect.value : "",
            run: mode === "employees" && runSelect ? runSelect.value : ""
        });
    }
    if (yearSelect) { yearSelect.addEventListener("change", periodChanged); }
    if (monthSelect) { monthSelect.addEventListener("change", periodChanged); }
    if (runSelect) {
        runSelect.addEventListener("change", function () {
            if (mode === "generate") {
                window.location.href = withQs(page.getAttribute("data-urls-page"), { run: runSelect.value });
                return;
            }
            go({
                run: runSelect.value,
                year: runSelect.value ? "" : (yearSelect ? yearSelect.value : ""),
                month: runSelect.value ? "" : (monthSelect ? monthSelect.value : "")
            });
        });
    }

    /* ======================================================== generate */

    var genForm = $("[data-ps-generate-form]", page);
    if (genForm) {
        // radio cards: keep the selected look in step with the radio
        $all("[data-ps-choice]", genForm).forEach(function (group) {
            group.addEventListener("change", function () {
                $all("label", group).forEach(function (label) {
                    var input = $("input", label);
                    label.classList.toggle("is-selected", !!(input && input.checked));
                });
            });
        });

        var deptWrap = $("[data-ps-dept-wrap]", genForm);
        $all("input[name=scope]", genForm).forEach(function (radio) {
            radio.addEventListener("change", function () {
                if (deptWrap) { deptWrap.hidden = !(radio.checked && radio.value === "dept"); }
            });
        });

        var genButton = $("[data-ps-generate]", page);
        if (genButton) {
            genButton.addEventListener("click", function () {
                var scope = $("input[name=scope]:checked", genForm);
                var template = $("input[name=template]:checked", genForm);
                var fd = new FormData();
                fd.append("run", runId);
                fd.append("template", template ? template.value : "BILINGUAL");
                if (scope && scope.value === "dept") {
                    var dept = $("[name=dept]", genForm);
                    if (!dept || !dept.value) {
                        HRMS.toast(HRMS.t("js.ps_choose_department", "Choose the department."), "error");
                        return;
                    }
                    fd.append("dept", dept.value);
                }
                post(page.getAttribute("data-urls-generate"), fd, genButton);
            });
        }
        return;
    }

    /* ============================================== employees / email list */

    var list = $("[data-ps-list]", page);
    if (!list) { return; }

    var slot = $("[data-ps-slot]", list);
    var countEl = $("[data-ps-count]", list);
    var search = $("[data-ps-search]", list);
    var status = $("[data-ps-status]", list);
    var dept = $("[data-ps-dept]", list);
    var currentPage = 1;
    var seq = 0;

    function load() {
        var mine = ++seq;
        slot.setAttribute("aria-busy", "true");
        var url = withQs(page.getAttribute("data-urls-grid"), {
            mode: mode,
            run: runId,
            year: runId ? "" : pageYear,
            month: runId ? "" : pageMonth,
            dept: dept ? dept.value : "",
            status: status ? status.value : "",
            search: search ? search.value.trim() : "",
            page: currentPage
        });
        HRMS.getHtml(url).then(function (html) {
            if (mine !== seq) { return; }
            slot.innerHTML = html;
            slot.removeAttribute("aria-busy");
            var holder = $("[data-total]", slot);
            if (countEl) { countEl.textContent = holder ? holder.getAttribute("data-count-text") : ""; }
            remember();
        }, function (error) {
            if (mine !== seq) { return; }
            slot.removeAttribute("aria-busy");
            slot.innerHTML = "";
            HRMS.toast((error && error.message) || failed(), "error");
        });
    }

    /** Keeps the filters in the address bar, so a refresh or a shared link shows the same list. */
    function remember() {
        if (!window.history || !window.history.replaceState) { return; }
        var url = withQs(window.location.pathname, {
            run: runId,
            year: runId ? "" : pageYear,
            month: runId ? "" : pageMonth,
            dept: dept ? dept.value : "",
            status: status && status.value !== "ALL" ? status.value : "",
            q: search ? search.value.trim() : ""
        });
        window.history.replaceState(null, "", url);
    }

    function reset() { currentPage = 1; load(); }

    if (search) { search.addEventListener("input", debounce(reset, 300)); }
    if (status) { status.addEventListener("change", reset); }
    if (dept) { dept.addEventListener("change", reset); }

    list.addEventListener("click", function (e) {
        var pageBtn = e.target.closest("[data-page]");
        if (pageBtn && !pageBtn.disabled) {
            currentPage = parseInt(pageBtn.getAttribute("data-page"), 10) || 1;
            load();
            list.scrollIntoView({ block: "start", behavior: "smooth" });
            return;
        }

        var send = e.target.closest("[data-ps-send]");
        if (send) {
            var fd = new FormData();
            fd.append("run", runId);
            fd.append("employeeIds", send.getAttribute("data-ps-send"));
            fd.append("resend", send.getAttribute("data-ps-resend") === "true" ? "true" : "false");
            post(page.getAttribute("data-urls-email"), fd, send);
        }
    });

    /* "Send to all not yet sent" (top bar) */
    var sendAll = $("[data-ps-send-all]");
    if (sendAll) {
        sendAll.addEventListener("click", function () {
            var fd = new FormData();
            fd.append("run", runId);
            post(page.getAttribute("data-urls-email"), fd, sendAll);
        });
    }

    load();
})();
