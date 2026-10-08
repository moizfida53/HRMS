/* ==========================================================================
 * HRMS Kuwait - Payslips (db/42-43)
 * Generate / Employee Payslips / Email Payslips, the printable payslip and
 * My Payslips. Panels are server-rendered; this file only wires them up.
 * Every POST carries the anti-forgery token (HRMS.post / HRMS.postHtml); every
 * text shown comes from the server (already translated) or from HRMS.t("js.ps_*").
 * No database id is sent or put in an address: payrolls and payslips are named
 * by the opaque references the server renders (data-ref, data-ps-view, ...).
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
            fd.append("slip", button.getAttribute("data-ps-generate-one"));
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

    /* ================================================ an employee list
     * Loads the employees of a payroll (or of every payroll) into [data-ps-slot]
     * by POST - the payroll's reference travels in the body - with search,
     * department and status filters and paging. Used on Employee / Email
     * Payslips and in the View Payslips popup. */
    function wireList(list, opts) {
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
            var fd = new FormData();
            fd.append("mode", opts.mode);
            if (opts.ref) { fd.append("ref", opts.ref); }
            if (!opts.ref && opts.year) { fd.append("year", opts.year); }
            if (!opts.ref && opts.month) { fd.append("month", opts.month); }
            if (dept && dept.value) { fd.append("dept", dept.value); }
            if (status && status.value) { fd.append("status", status.value); }
            if (search && search.value.trim()) { fd.append("search", search.value.trim()); }
            fd.append("page", String(currentPage));
            HRMS.postHtml(opts.gridUrl, fd).then(function (html) {
                if (mine !== seq) { return; }
                slot.innerHTML = html;
                slot.removeAttribute("aria-busy");
                var holder = $("[data-total]", slot);
                if (countEl) { HRMS.setCountText(countEl, holder ? holder.getAttribute("data-count-text") : ""); }
                if (opts.onLoad) { opts.onLoad({ dept: dept, status: status, search: search }); }
            }, function (error) {
                if (mine !== seq) { return; }
                slot.removeAttribute("aria-busy");
                slot.innerHTML = "";
                HRMS.toast((error && error.message) || failed(), "error");
            });
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
            if (send && opts.emailUrl) {
                var fd = new FormData();
                fd.append("slip", send.getAttribute("data-ps-send"));
                fd.append("resend", send.getAttribute("data-ps-resend") === "true" ? "true" : "false");
                post(opts.emailUrl, fd, send);
            }
        });

        load();
    }

    /** Radio cards keep the selected look; "One department" shows the department list. */
    function wireGenerateForm(form) {
        $all("[data-ps-choice]", form).forEach(function (group) {
            group.addEventListener("change", function () {
                $all("label", group).forEach(function (label) {
                    var input = $("input", label);
                    label.classList.toggle("is-selected", !!(input && input.checked));
                });
            });
        });
        var deptWrap = $("[data-ps-dept-wrap]", form);
        $all("input[name=scope]", form).forEach(function (radio) {
            radio.addEventListener("change", function () {
                if (deptWrap) { deptWrap.hidden = !(radio.checked && radio.value === "dept"); }
            });
        });
    }

    /** The generate form's fields (the payroll reference, template, department). */
    function generateBody(form) {
        var scope = $("input[name=scope]:checked", form);
        var template = $("input[name=template]:checked", form);
        var fd = new FormData();
        fd.append("ref", $("[name=ref]", form).value);
        fd.append("template", template ? template.value : "BILINGUAL");
        if (scope && scope.value === "dept") {
            var dept = $("[name=dept]", form);
            if (!dept || !dept.value) {
                HRMS.toast(HRMS.t("js.ps_choose_department", "Choose the department."), "error");
                return null;
            }
            fd.append("dept", dept.value);
        }
        return fd;
    }

    /* ================================================= Generate Payslips
     * The payrolls list (filters in the address: year / period / show / search -
     * no ids). View opens the payroll's figures and the generate form in a popup;
     * View Payslips opens its employees' payslips in a popup. */
    if (mode === "generate-list") {
        var filters = $("[data-ps-filters]", page);
        if (filters) {
            var yearSel = $("[name=year]", filters), monthSel = $("[name=month]", filters);
            var narrowMonths = function () {
                var y = yearSel ? yearSel.value : "";
                if (monthSel) { HRMS.filterOptions(monthSel, function (o) { return !o.value || !y || o.getAttribute("data-year") === y; }); }
            };
            narrowMonths();
            $all("[data-ps-filter]", filters).forEach(function (el) {
                el.addEventListener("change", function () {
                    if (el === yearSel) { narrowMonths(); }
                    filters.submit();
                });
            });
            var q = $("[data-ps-filter-search]", filters);
            if (q) { q.addEventListener("input", debounce(function () { filters.submit(); }, 600)); }
        }

        var openPanel = function (modalId, url, ref, title, ready) {
            var modalEl = document.getElementById(modalId);
            if (!modalEl || !window.bootstrap) { return; }
            var body = $("[data-ps-modal-body]", modalEl);
            var actions = $("[data-ps-modal-actions]", modalEl);
            if (actions) { actions.innerHTML = ""; }
            $("[data-ps-modal-title]", modalEl).textContent = title || "";
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
            var fd = new FormData();
            fd.append("ref", ref);
            HRMS.postHtml(url, fd).then(function (html) {
                body.innerHTML = html;
                var t = $("[data-ps-panel-title]", body);
                if (t) { $("[data-ps-modal-title]", modalEl).textContent = t.textContent.trim(); }
                // the panel's header buttons (Generate Payslips) go to the popup header, right-aligned
                var head = $("[data-ps-header-actions]", body);
                if (head && actions) {
                    while (head.firstChild) { actions.appendChild(head.firstChild); }
                    head.remove();
                }
                ready(body, modalEl);
            }, function (error) {
                body.innerHTML = "";
                HRMS.toast((error && error.message) || failed(), "error");
            });
        };

        /** The Generate Payslips popup of a payroll (its reference): the form, the button in the header. */
        var openGenerate = function (ref, title) {
            openPanel("ps-run-modal", page.getAttribute("data-urls-panel"), ref, title, function (body, modalEl) {
                var form = $("[data-ps-generate-form]", body);
                if (!form) { return; }
                wireGenerateForm(form);
                var button = $("[data-ps-generate]", modalEl);
                if (button) {
                    button.addEventListener("click", function () {
                        var fd = generateBody(form);
                        if (fd) { post(page.getAttribute("data-urls-generate"), fd, button); }
                    });
                }
            });
        };

        page.addEventListener("click", function (e) {
            var view = e.target.closest("[data-ps-view]");
            if (view) {
                openGenerate(view.getAttribute("data-ps-view"), view.getAttribute("data-ps-title"));
                return;
            }
            var slips = e.target.closest("[data-ps-slips]");
            if (slips) {
                openPanel("ps-slips-modal", page.getAttribute("data-urls-slips"), slips.getAttribute("data-ps-slips"), slips.getAttribute("data-ps-title"), function (body) {
                    var panel = $("[data-ps-slips-panel]", body);
                    var list = panel && $("[data-ps-list]", panel);
                    if (list) { wireList(list, { mode: "employees", ref: panel.getAttribute("data-ref"), gridUrl: page.getAttribute("data-urls-grid") }); }
                });
            }
        });

        // "Goto PaySlips" on Payrolls: open that payroll's popup straight away, then drop the reference from the address
        var openRef = page.getAttribute("data-open");
        if (openRef) {
            openGenerate(openRef, page.getAttribute("data-open-title"));
            if (window.history && window.history.replaceState) {
                var u = new URL(window.location.href);
                u.searchParams.delete("open");
                window.history.replaceState(null, "", u.pathname + u.search);
            }
        }
        return;
    }

    /* ========================================= Employee / Email Payslips */

    var runRef = page.getAttribute("data-ref") || "";
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

    /** Opens the page again for the chosen payroll (its reference) / year / period, keeping the list filters. */
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
            ref: mode === "employees" && runSelect ? runSelect.value : ""
        });
    }
    if (yearSelect) { yearSelect.addEventListener("change", periodChanged); }
    if (monthSelect) { monthSelect.addEventListener("change", periodChanged); }
    if (runSelect) {
        runSelect.addEventListener("change", function () {
            go({
                ref: runSelect.value,
                year: runSelect.value ? "" : (yearSelect ? yearSelect.value : ""),
                month: runSelect.value ? "" : (monthSelect ? monthSelect.value : "")
            });
        });
    }

    var list = $("[data-ps-list]", page);
    if (list) {
        wireList(list, {
            mode: mode,
            ref: runRef,
            year: pageYear,
            month: pageMonth,
            gridUrl: page.getAttribute("data-urls-grid"),
            emailUrl: page.getAttribute("data-urls-email"),
            /* keeps the filters in the address bar, so a refresh shows the same list */
            onLoad: function (f) {
                if (!window.history || !window.history.replaceState) { return; }
                window.history.replaceState(null, "", withQs(window.location.pathname, {
                    ref: runRef,
                    year: runRef ? "" : pageYear,
                    month: runRef ? "" : pageMonth,
                    dept: f.dept ? f.dept.value : "",
                    status: f.status && f.status.value !== "ALL" ? f.status.value : "",
                    q: f.search ? f.search.value.trim() : ""
                }));
            }
        });
    }

    /* "Send to all not yet sent" (top bar) */
    var sendAll = $("[data-ps-send-all]");
    if (sendAll) {
        sendAll.addEventListener("click", function () {
            var fd = new FormData();
            fd.append("ref", runRef);
            post(page.getAttribute("data-urls-email"), fd, sendAll);
        });
    }
})();
