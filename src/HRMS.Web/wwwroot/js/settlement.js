/* ==========================================================================
 * HRMS Kuwait - Final Settlement (db/39-40)
 * Settlements list, the settlement form (exit and leave encashment), the
 * settlement page (lines, approval, payment) and the printable statement.
 * Panels are server-rendered; this file only wires them up. Every POST
 * carries the anti-forgery token (HRMS.post); every text shown comes from the
 * server (already translated) or from HRMS.t("js.fs_*").
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-fs-page]");
    var FLASH = "hrms-fs-flash";

    /* ------------------------------------------------------------- helpers */

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function qs(params) {
        return Object.keys(params).filter(function (k) {
            return params[k] !== null && params[k] !== undefined && params[k] !== "";
        }).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function withQs(url, params) { var q = qs(params); return q ? url + (url.indexOf("?") >= 0 ? "&" : "?") + q : url; }
    function data(params) {
        var fd = new FormData();
        Object.keys(params).forEach(function (k) { if (params[k] !== null && params[k] !== undefined) { fd.append(k, params[k]); } });
        return fd;
    }
    function modal(el) { return el && window.bootstrap ? window.bootstrap.Modal.getOrCreateInstance(el) : null; }
    function busy(button, on) {
        if (!button) { return; }
        button.disabled = !!on;
        button.classList.toggle("is-busy", !!on);
    }
    function failed() { return HRMS.t("js.fs_failed", "The request could not be completed."); }

    /** POST; on success keep the message for the next page (or toast it), on failure toast it. */
    function post(url, body, button, onOk) {
        busy(button, true);
        return HRMS.post(url, body instanceof FormData ? body : data(body)).then(function (res) {
            if (res && res.success) {
                if (onOk) { onOk(res); } else { busy(button, false); if (res.message) { HRMS.toast(res.message, "success"); } }
            } else {
                busy(button, false);
                HRMS.toast((res && res.message) || failed(), "error");
            }
            return res;
        }, function (error) {
            busy(button, false);
            HRMS.toast((error && error.message) || failed(), "error");
        });
    }
    /** Reloads (or opens url) and shows the message once the page is back. */
    function flashAndGo(message, url) {
        try { if (message) { window.sessionStorage.setItem(FLASH, message); } } catch (e) { /* private mode */ }
        if (url) { window.location.href = url; } else { window.location.reload(); }
    }
    (function showFlash() {
        try {
            var msg = window.sessionStorage.getItem(FLASH);
            if (msg) { window.sessionStorage.removeItem(FLASH); HRMS.toast(msg, "success"); }
        } catch (e) { /* private mode */ }
    })();

    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments, self = this; clearTimeout(t); t = setTimeout(function () { fn.apply(self, a); }, wait); };
    };
    var nf = new Intl.NumberFormat("en-US", { minimumFractionDigits: 3, maximumFractionDigits: 3 });
    function money(v) { return v === null || v === undefined ? "—" : "KWD " + nf.format(v); }
    function dateText(iso) {
        if (!iso) { return "—"; }
        var p = iso.split("-");
        return p.length === 3 ? p[2] + "/" + p[1] + "/" + p[0] : iso;
    }
    function detailsUrl(id) {
        var base = page && page.getAttribute("data-urls-details");
        return base ? base.replace(/\/0$/, "/" + id) : "/payroll/settlement/" + id;
    }
    /** Years / months / days between two ISO dates (inclusive), like the server. */
    function serviceText(fromIso, toIso) {
        if (!fromIso || !toIso || fromIso > toIso) { return "—"; }
        var from = new Date(fromIso + "T00:00:00"), end = new Date(toIso + "T00:00:00");
        end.setDate(end.getDate() + 1);
        var y = end.getFullYear() - from.getFullYear();
        var a = new Date(from); a.setFullYear(from.getFullYear() + y);
        if (a > end) { y--; a = new Date(from); a.setFullYear(from.getFullYear() + y); }
        var m = 0, b = new Date(a); b.setMonth(b.getMonth() + 1);
        while (b <= end) { m++; b = new Date(a); b.setMonth(a.getMonth() + m + 1); }
        var c = new Date(a); c.setMonth(a.getMonth() + m);
        var d = Math.round((end - c) / 86400000);
        return HRMS.t("js.fs_service", "{0} years {1} months {2} days").replace("{0}", y).replace("{1}", m).replace("{2}", d);
    }

    /* =============================================================== form */

    function wireForm(form) {
        var emp = $("[data-fs-emp]", form);
        var lwd = $("[data-fs-lwd]", form);
        var from = $("[data-fs-from]", form);
        var fromHint = $("[data-fs-from-hint]", form);
        var balance = $("[data-fs-balance]", form);
        var encash = $("[data-fs-encash]", form);
        var info = $("[data-fs-info]", form);
        var exit = form.getAttribute("data-mode") === "exit";
        var isNew = ($("[name=FinalSettlementId]", form) || {}).value === "0";
        var userSetFrom = !isNew;
        var userSetEncash = !isNew;
        var seq = 0;

        if (from) { from.addEventListener("input", function () { userSetFrom = true; }); }
        if (encash) { encash.addEventListener("input", function () { userSetEncash = true; }); }
        if (balance && encash && exit) {
            balance.addEventListener("input", function () { if (!userSetEncash) { encash.value = balance.value; } });
        }

        function set(key, text) { var el = $('[data-fs-v="' + key + '"]', info); if (el) { el.textContent = text; } }

        function refresh() {
            if (!info || !emp || !emp.value) { if (info) { info.hidden = true; } return; }
            var mine = ++seq;
            var url = withQs(form.getAttribute("data-defaults-url"), { emp: emp.value, lwd: lwd ? lwd.value : "" });
            HRMS.getJson(url).then(function (d) {
                if (mine !== seq || !d) { return; }
                info.hidden = false;
                var open = $("[data-fs-open]", info);
                if (open) {
                    var showOpen = exit && isNew && !!d.openNo;
                    open.hidden = !showOpen;
                    if (showOpen) { var a = $("[data-fs-open-link]", open); a.textContent = d.openNo; a.href = d.openUrl || "#"; }
                }
                set("hire", dateText(d.hireDate));
                set("service", lwd && lwd.value ? serviceText(d.hireDate, lwd.value) : "—");
                set("salary", money(d.monthlySalary));
                set("indemnity", money(d.indemnityBase));
                set("leave", money(d.leaveBase));
                set("paid", d.paidThrough ? dateText(d.paidThrough) + " · " + (d.paidByRun || "") : HRMS.t("js.fs_no_payroll_yet", "No closed payroll yet"));
                set("rules", d.ruleSet ? d.ruleSet + (d.ruleSetVerified ? "" : " · " + HRMS.t("js.fs_not_verified", "not verified")) : HRMS.t("js.fs_no_rules", "None in force"));
                if (from && !userSetFrom && d.salaryFrom && lwd && lwd.value) { from.value = d.salaryFrom; }
                if (fromHint) {
                    fromHint.textContent = d.paidThrough
                        ? HRMS.t("js.fs_from_hint", "Paid up to {0} by payroll {1}.").replace("{0}", dateText(d.paidThrough)).replace("{1}", d.paidByRun || "")
                        : HRMS.t("js.fs_from_hint_none", "No closed payroll has paid this employee - check the date.");
                }
            }, function () { /* the panel is a convenience; the save validates */ });
        }

        if (emp) { emp.addEventListener("change", function () { userSetFrom = !isNew ? userSetFrom : false; refresh(); }); }
        if (lwd) { lwd.addEventListener("change", function () { if (isNew) { userSetFrom = false; } refresh(); }); }
        refresh();

        form.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var missing = $all("[required]", form).filter(function (el) { return !el.value; });
            $all(".is-invalid", form).forEach(function (el) { el.classList.remove("is-invalid"); });
            if (missing.length) {
                missing.forEach(function (el) { el.classList.add("is-invalid"); });
                missing[0].focus();
                HRMS.toast(HRMS.t("js.fs_fill_required", "Fill in the fields marked *."), "error");
                return;
            }
            var url = (page && page.getAttribute("data-urls-save")) || "/payroll/settlement/save";
            post(url, new FormData(form), $("[data-fs-save]", form), function (res) {
                flashAndGo(res.message, detailsUrl(res.id));
            });
        });

        var cancel = $("[data-fs-form-cancel]", form);
        if (cancel) {
            cancel.addEventListener("click", function () {
                form.reset();
                var toggle = $("[data-fs-edit-toggle]");
                if (toggle) { toggle.click(); }
            });
        }
    }
    $all("[data-fs-form]").forEach(wireForm);

    if (!page) { return; }
    var PAGE = page.getAttribute("data-fs-page");

    /* =============================================================== list */

    if (PAGE === "list") {
        var slot = $("[data-fs-slot]", page);
        var counter = $("[data-fs-count]", page);
        var search = $("[data-fs-search]", page);
        var typeSel = $("[data-fs-type-filter]", page);
        var statusSel = $("[data-fs-status]", page);
        var fixedType = page.getAttribute("data-fixed-type") || "";
        var state = { page: 1 };

        var loadGrid = function () {
            slot.setAttribute("aria-busy", "true");
            var url = withQs(page.getAttribute("data-urls-grid"), {
                search: search ? search.value.trim() : "",
                type: fixedType || (typeSel ? typeSel.value : ""),
                status: statusSel ? statusSel.value : "",
                page: state.page
            });
            HRMS.getHtml(url).then(function (html) {
                slot.innerHTML = html;
                slot.removeAttribute("aria-busy");
                var holder = slot.querySelector("[data-count-text]");
                if (counter) { HRMS.setCountText(counter, holder ? holder.getAttribute("data-count-text") : ""); }
            }, function (error) {
                slot.removeAttribute("aria-busy");
                slot.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' +
                    HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div>";
                HRMS.toast((error && error.message) || failed(), "error");
            });
        };
        var kpis = $("[data-fs-kpis]", page);
        if (kpis && page.getAttribute("data-urls-kpis")) {
            HRMS.getHtml(page.getAttribute("data-urls-kpis")).then(function (html) { kpis.innerHTML = html; }, function () { kpis.innerHTML = ""; });
        }
        if (search) { search.addEventListener("input", debounce(function () { state.page = 1; loadGrid(); }, 300)); }
        [typeSel, statusSel].forEach(function (sel) { if (sel) { sel.addEventListener("change", function () { state.page = 1; loadGrid(); }); } });
        slot.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (b && !b.disabled) { state.page = parseInt(b.getAttribute("data-page"), 10) || 1; loadGrid(); }
        });
        loadGrid();
        return;
    }

    /* ============================================================ details */

    if (PAGE === "details") {
        var base = page.getAttribute("data-urls-base");
        var act = function (verb) { return base + "/" + verb; };

        /* change the details (draft) */
        var toggle = $("[data-fs-edit-toggle]", page);
        var body = $("[data-fs-edit-body]", page);
        if (toggle && body) {
            toggle.addEventListener("click", function () {
                var open = body.hidden;
                body.hidden = !open;
                toggle.setAttribute("aria-expanded", open ? "true" : "false");
                if (open) { var first = $("input:not([type=hidden]):not([readonly]), select", body); if (first) { first.focus(); } }
            });
        }

        /* recalculate */
        $all('[data-fs-act="recalc"]', page).forEach(function (b) {
            b.addEventListener("click", function () { post(act("recalc"), {}, b, function (res) { flashAndGo(res.message); }); });
        });

        /* submit for approval */
        var submit = $("[data-fs-submit]", page);
        if (submit) {
            submit.addEventListener("click", function () {
                var ack = $("[data-fs-ack]", page);
                if (submit.getAttribute("data-needs-ack") === "true" && ack && !ack.checked) {
                    ack.focus();
                    ack.closest(".fs-ack").classList.add("is-invalid");
                    HRMS.toast(HRMS.t("js.fs_tick_ack", "Tick the box to confirm you have checked the indemnity."), "error");
                    return;
                }
                post(act("submit"), { ack: ack && ack.checked ? "true" : "false" }, submit, function (res) { flashAndGo(res.message); });
            });
        }

        /* lines: waive / include again, remove */
        page.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-fs-line]");
            if (!b) { return; }
            var li = b.closest("[data-line]");
            var verb = b.getAttribute("data-fs-line") === "remove" ? "remove-line" : "toggle-line";
            post(act(verb), { lineId: li.getAttribute("data-line") }, b, function (res) { flashAndGo(res.message); });
        });

        /* add a line by hand */
        $all("[data-fs-add]", page).forEach(function (f) {
            f.addEventListener("submit", function (ev) {
                ev.preventDefault();
                var desc = f.elements.description, amt = f.elements.amount;
                desc.classList.toggle("is-invalid", !desc.value.trim());
                amt.classList.toggle("is-invalid", !(parseFloat(amt.value) > 0));
                if (!desc.value.trim() || !(parseFloat(amt.value) > 0)) { return; }
                post(act("add-line"), { section: f.getAttribute("data-section"), description: desc.value.trim(), amount: amt.value },
                    $("button[type=submit]", f), function (res) { flashAndGo(res.message); });
            });
        });

        /* approve / return / reject / cancel: one comment dialog */
        var reasonModal = $("#fs-reason-modal");
        var current = null;
        $all("[data-fs-reason]", page).forEach(function (b) {
            b.addEventListener("click", function () {
                current = b;
                var optional = b.getAttribute("data-optional") === "true";
                $("[data-fs-reason-title]", reasonModal).textContent = b.getAttribute("data-title") || "";
                $("[data-fs-reason-text]", reasonModal).textContent = b.getAttribute("data-text") || "";
                $("[data-fs-reason-button]", reasonModal).textContent = b.getAttribute("data-button") || "";
                $("[data-fs-reason-req]", reasonModal).hidden = optional;
                var input = $("[data-fs-reason-input]", reasonModal);
                input.value = "";
                input.classList.remove("is-invalid");
                $("[data-fs-reason-error]", reasonModal).hidden = true;
                var go = $("[data-fs-reason-submit]", reasonModal);
                go.classList.toggle("btn-danger", b.getAttribute("data-danger") === "true");
                go.classList.toggle("btn-primary", b.getAttribute("data-danger") !== "true");
                modal(reasonModal).show();
                window.setTimeout(function () { input.focus(); }, 250);
            });
        });
        if (reasonModal) {
            $("[data-fs-reason-form]", reasonModal).addEventListener("submit", function (ev) {
                ev.preventDefault();
                if (!current) { return; }
                var input = $("[data-fs-reason-input]", reasonModal);
                var value = input.value.trim();
                if (!value && current.getAttribute("data-optional") !== "true") {
                    input.classList.add("is-invalid");
                    $("[data-fs-reason-error]", reasonModal).hidden = false;
                    return;
                }
                var verb = current.getAttribute("data-fs-reason");
                post(act(verb), { comment: value }, $("[data-fs-reason-submit]", reasonModal), function (res) {
                    modal(reasonModal).hide();
                    flashAndGo(res.message);
                });
            });
        }

        /* record the payment */
        var payForm = $("[data-fs-pay-form]");
        if (payForm) {
            var method = payForm.elements.method, ref = payForm.elements.reference;
            var syncRef = function () { ref.required = method.value === "BANK" || method.value === "CHEQUE"; };
            method.addEventListener("change", syncRef);
            syncRef();
            payForm.addEventListener("submit", function (ev) {
                ev.preventDefault();
                ref.classList.toggle("is-invalid", ref.required && !ref.value.trim());
                payForm.elements.paidDate.classList.toggle("is-invalid", !payForm.elements.paidDate.value);
                if ((ref.required && !ref.value.trim()) || !payForm.elements.paidDate.value) { return; }
                post(act("pay"), new FormData(payForm), $("[data-fs-pay-submit]", payForm), function (res) {
                    modal($("#fs-pay-modal")).hide();
                    flashAndGo(res.message);
                });
            });
        }
    }
})();

/* the statement: print button (works without the page wiring above) */
(function () {
    "use strict";
    var b = document.querySelector("[data-fs-print]");
    if (b) { b.addEventListener("click", function () { window.print(); }); }
})();
