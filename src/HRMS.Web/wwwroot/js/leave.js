/* ==========================================================================
 * HRMS Kuwait - Leave (db/68, db/69)
 * One script for the Leave pages ([data-lv-page]):
 *   - requests  HR's list: KPI tiles, filters, export, approve / reject
 *   - my        My Leave: balance cards, own requests, the team waiting for the user
 *   - balances  balances of every employee, ledger + adjustments
 *   - settings  leave types, public holidays, weekend days + approval route
 * and the employee profile's Leave tab ([data-lv-employee], balance cards).
 * Records open in popups - no record reference ever reaches the address bar.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function qs(params) {
        return Object.keys(params).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function withQuery(url, params) { var q = qs(params); return q ? url + (url.indexOf("?") < 0 ? "?" : "&") + q : url; }
    function body(params) {
        var fd = new FormData();
        Object.keys(params).forEach(function (k) { if (params[k] !== null && params[k] !== undefined) { fd.append(k, params[k]); } });
        return fd;
    }
    function modal(id) {
        var el = document.getElementById(id);
        return el && window.bootstrap ? window.bootstrap.Modal.getOrCreateInstance(el) : null;
    }
    function loading() { return '<div class="pr-loading"><div class="hrms-spinner"></div></div>'; }
    function failed(slot, error) {
        slot.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title"></p></div>';
        slot.querySelector("p").textContent = (error && error.message) || HRMS.t("js.could_not_load_data", "Could not load data.");
    }
    function busy(button, on) {
        if (!button) { return; }
        button.disabled = on;
        button.classList.toggle("is-busy", on);
    }
    /** Shows the server's answer; resolves to the response when it succeeded. */
    function answer(res) {
        if (res && res.success) {
            if (res.message) { HRMS.toast(res.message, "success"); }
            return res;
        }
        var msg = (res && res.message) || HRMS.t("js.something_went_wrong", "Something went wrong. Please try again.");
        if (res && res.errors) {
            var first = Object.keys(res.errors)[0];
            if (first && res.errors[first] && res.errors[first][0]) { msg = res.errors[first][0]; }
        }
        HRMS.toast(msg, "error");
        return null;
    }
    function oops(error) { HRMS.toast((error && error.message) || HRMS.t("js.something_went_wrong", "Something went wrong. Please try again."), "error"); }

    var page = $("[data-lv-page]");
    var kind = page ? page.getAttribute("data-lv-page") : null;
    var shared = $(".lv-modals");
    var sharedUrl = function (name) { return shared ? shared.getAttribute("data-urls-" + name) : null; };
    var sharedText = function (name) { return shared ? shared.getAttribute("data-text-" + name) || "" : ""; };

    /* ------------------------------------------------------------ grids -- */

    /**
     * A server-rendered list: its filters ([data-lv-f]) go in the query; pagination
     * buttons ([data-page]) ask for another page. options.slot / count / url / extra.
     */
    function grid(options) {
        var state = { page: 1 };
        var slot = options.slot, count = options.count;
        var token = 0;

        function values() {
            var v = { page: state.page };
            (options.filters || []).forEach(function (f) {
                var name = f.getAttribute("data-lv-f");
                v[name] = f.type === "search" ? f.value.trim() : f.value;
            });
            if (options.extra) { Object.assign(v, options.extra()); }
            return v;
        }
        function load() {
            var mine = ++token;
            if (!slot.firstElementChild || !slot.querySelector(".pr-loading")) { slot.classList.add("is-loading"); }
            return HRMS.getHtml(withQuery(options.url, values())).then(function (html) {
                if (mine !== token) { return; }
                slot.innerHTML = html;
                slot.classList.remove("is-loading");
                var head = slot.firstElementChild;
                if (count && head) { HRMS.setCountText(count, head.getAttribute("data-count-text") || ""); }
                if (options.loaded) { options.loaded(head); }
            }).catch(function (error) {
                if (mine !== token) { return; }
                slot.classList.remove("is-loading");
                failed(slot, error);
            });
        }
        slot.addEventListener("click", function (event) {
            var b = event.target.closest("[data-page]");
            if (!b || b.disabled || !slot.contains(b)) { return; }
            state.page = parseInt(b.getAttribute("data-page"), 10) || 1;
            load().then(function () { slot.scrollIntoView({ block: "nearest", behavior: "smooth" }); });
        });
        var reloadFirst = function () { state.page = 1; load(); };
        var typed = HRMS.debounce(reloadFirst, 300);
        (options.filters || []).forEach(function (f) {
            f.addEventListener(f.type === "search" ? "input" : "change", f.type === "search" ? typed : reloadFirst);
        });
        return { load: load, first: reloadFirst, values: values };
    }

    /* ---------------------------------------------------- request form -- */

    var form = $("[data-lv-form]");
    var formBody = form ? $("[data-lv-form-body]", form) : null;
    var formChanged = null;   // called after a successful save (reload lists)
    var lastPreview = null;   // the latest preview of the open form (paid / unpaid days)

    function openForm(mode, id, emp) {
        if (!form) { return; }
        $("[data-lv-form-title]", form).textContent = sharedText(id ? "edit" : "new");
        formBody.innerHTML = loading();
        modal("lv-form-modal").show();
        HRMS.getHtml(withQuery(sharedUrl("form"), { mode: mode, id: id || null, emp: emp || null })).then(function (html) {
            formBody.innerHTML = html;
            wireForm();
        }).catch(function (error) { failed(formBody, error); });
    }

    function wireForm() {
        var emp = $("[data-lv-emp]", formBody), type = $("[data-lv-type]", formBody);
        var start = $("[data-lv-start]", formBody), end = $("[data-lv-end]", formBody);
        var halfWrap = $("[data-lv-half-wrap]", formBody), half = $("[data-lv-half]", formBody);
        var docWrap = $("[data-lv-doc-wrap]", formBody), preview = $("[data-lv-preview]", formBody);
        var resume = $("[data-lv-resume]", formBody);
        var previewToken = 0;
        lastPreview = null;

        if (emp && HRMS.searchable && !emp.disabled) { HRMS.searchable(emp); }

        function syncType() {
            var opt = type.options[type.selectedIndex];
            var halfOk = !!(opt && opt.getAttribute("data-half") === "1");
            var oneDay = start.value && end.value && start.value === end.value;
            halfWrap.hidden = !(halfOk && oneDay);
            if (halfWrap.hidden && half) { half.checked = false; }
            docWrap.hidden = !(opt && opt.getAttribute("data-doc") === "1");
        }
        function clearErrors() { $all("[data-valmsg-for]", formBody).forEach(function (e) { e.textContent = ""; }); }

        var runPreview = HRMS.debounce(function () {
            var mine = ++previewToken;
            if (!type.value || !start.value || !end.value || (emp && !emp.value)) { preview.hidden = true; return; }
            var fd = new FormData(form);
            fd.delete("document");
            if (resumeIsAuto()) { fd.delete("ResumeDate"); }
            HRMS.post(sharedUrl("preview"), fd).then(function (res) {
                if (mine !== previewToken) { return; }
                lastPreview = res && res.ready ? res : null;
                if (!res || !res.ready) { preview.hidden = true; return; }
                preview.hidden = false;
                preview.classList.toggle("has-problems", !res.ok);
                $('[data-lv-p="days"]', preview).textContent = res.daysText || "—";
                var limited = res.available !== null && res.available !== undefined;
                $all("[data-lv-p-balance]", preview).forEach(function (el) { el.hidden = !limited; });
                if (limited) {
                    $('[data-lv-p="available"]', preview).textContent = fmt(res.available);
                    var after = $('[data-lv-p="after"]', preview);
                    after.textContent = fmt(res.after);
                    after.classList.toggle("is-neg", res.after < 0);
                }
                // more days than the balance: the days over it are unpaid (asked again on submit)
                var unpaid = Number(res.unpaidDays || 0);
                var split = $("[data-lv-p-split]", preview);
                split.hidden = !(unpaid > 0);
                if (unpaid > 0) {
                    $('[data-lv-p="paid"]', split).textContent = fmt(res.paidDays);
                    $('[data-lv-p="unpaid"]', split).textContent = fmt(unpaid);
                    var total = Number(res.days) || 1;
                    $('[data-lv-p="paid-bar"]', split).style.width = Math.max(0, Math.min(100, Number(res.paidDays) / total * 100)) + "%";
                }
                // the suggested day back at work (next working day), unless typed in
                if (resume && resumeIsAuto() && res.resumeDate) { resume.value = res.resumeDate; }
                var list = $('[data-lv-p="problems"]', preview);
                list.innerHTML = "";
                (res.problems || []).forEach(function (p) {
                    var li = document.createElement("li");
                    li.textContent = p;
                    list.appendChild(li);
                });
            }).catch(function () { if (mine === previewToken) { preview.hidden = true; } });
        }, 250);

        if (emp) {
            emp.addEventListener("change", function () {
                type.innerHTML = "";
                var first = document.createElement("option");
                first.value = "";
                first.textContent = HRMS.t("js.lv_choose_type", "Choose the leave type");
                type.appendChild(first);
                syncType();
                runPreview();
                if (!emp.value) { return; }
                HRMS.getJson(withQuery(sharedUrl("types"), { emp: emp.value })).then(function (types) {
                    types.forEach(function (t) {
                        var o = document.createElement("option");
                        o.value = t.id;
                        o.textContent = t.name + (t.unlimited ? "" : " · " + HRMS.t("js.lv_n_available", "{0} available", fmt(t.available)));
                        o.setAttribute("data-half", t.half ? "1" : "0");
                        o.setAttribute("data-doc", t.doc ? "1" : "0");
                        type.appendChild(o);
                    });
                }).catch(oops);
            });
        }
        type.addEventListener("change", function () { syncType(); runPreview(); });
        start.addEventListener("change", function () {
            if (start.value && (!end.value || end.value < start.value)) { end.value = start.value; }
            end.min = start.value;
            syncType();
            runPreview();
        });
        end.addEventListener("change", function () {
            if (resume) { resume.min = end.value; }
            syncType();
            runPreview();
        });
        if (half) { half.addEventListener("change", runPreview); }
        if (resume) {
            // typed in: kept (and checked); cleared: suggested again
            resume.addEventListener("change", function () {
                resume.setAttribute("data-lv-resume-auto", resume.value ? "0" : "1");
                runPreview();
            });
            if (end.value) { resume.min = end.value; }
        }
        formBody.addEventListener("input", clearErrors);
        if (start.value) { end.min = start.value; }
        syncType();
        runPreview();
    }

    function resumeIsAuto() {
        var r = formBody ? $("[data-lv-resume]", formBody) : null;
        return !r || r.getAttribute("data-lv-resume-auto") === "1";
    }

    /** The days over the balance are unpaid - the employee agrees before the request goes. */
    function askUnpaid(p) {
        var text = sharedText("unpaid-text");
        return HRMS.confirm({
            title: sharedText("unpaid-title"),
            text: text.replace("{0}", fmt(p.paidDays)).replace("{1}", fmt(p.days)).replace("{2}", fmt(p.unpaidDays)),
            name: HRMS.t("js.lv_split", "Paid {0} days · Unpaid {1} days", fmt(p.paidDays), fmt(p.unpaidDays)),
            tone: "primary",
            note: "",
            ok: sharedText("unpaid-ok")
        });
    }

    function fmt(n) {
        if (n === null || n === undefined || n === "") { return "—"; }
        var v = Math.round(Number(n) * 100) / 100;
        return String(v);
    }

    if (form) {
        form.addEventListener("submit", function (event) {
            event.preventDefault();
            var save = $("[data-lv-save]", form);
            var errors = $all("[data-valmsg-for]", formBody);
            errors.forEach(function (e) { e.textContent = ""; });
            var missing = $all("[required]", formBody).filter(function (f) { return !f.disabled && !f.value; });
            if (missing.length) {
                missing[0].focus();
                HRMS.toast(HRMS.t("js.lv_fill_required", "Fill in the fields marked *."), "error");
                return;
            }
            var send = function (acceptUnpaid) {
                var fd = new FormData(form);
                if (resumeIsAuto()) { fd.delete("ResumeDate"); }
                if (acceptUnpaid) { fd.set("AcceptUnpaid", "true"); }
                busy(save, true);
                return HRMS.post(sharedUrl("save"), fd).then(function (res) {
                    busy(save, false);
                    // the balance changed since the preview: ask, then send again
                    if (res && !res.success && res.errorCode === "UNPAID_CONFIRM" && !acceptUnpaid) {
                        var p = lastPreview || {};
                        return (p.unpaidDays > 0 ? askUnpaid(p) : HRMS.confirm({ title: sharedText("unpaid-title"), text: res.message, tone: "primary", note: "", ok: sharedText("unpaid-ok") }))
                            .then(function (ok) { if (ok) { return send(true); } });
                    }
                    if (res && !res.success && res.errors) {
                        Object.keys(res.errors).forEach(function (k) {
                            var slot = $('[data-valmsg-for="' + k + '"]', formBody);
                            if (slot) { slot.textContent = res.errors[k][0]; }
                        });
                    }
                    if (answer(res)) {
                        modal("lv-form-modal").hide();
                        if (formChanged) { formChanged(); }
                    }
                }).catch(function (error) { busy(save, false); oops(error); });
            };
            // ask first - unless the dates have a problem the server refuses anyway
            if (lastPreview && lastPreview.ok && Number(lastPreview.unpaidDays) > 0) {
                askUnpaid(lastPreview).then(function (ok) { if (ok) { send(true); } });
            } else {
                send(false);
            }
        });
    }

    /* -------------------------------------------- one request + actions -- */

    var detailBody = $("[data-lv-detail-body]");
    var current = null;          // { id, level, start } of the request being acted on

    function openDetail(id) {
        if (!detailBody) { return; }
        detailBody.innerHTML = '<div class="modal-body">' + loading() + "</div>";
        modal("lv-detail-modal").show();
        HRMS.getHtml(withQuery(sharedUrl("detail"), { id: id })).then(function (html) {
            detailBody.innerHTML = html;
            wireSettle(detailBody);
        }).catch(function (error) { failed(detailBody, error); });
    }

    // approve (comment optional) / reject / cancel (reason needed)
    var reasonForm = $("[data-lv-reason-form]");
    var reasonAction = null;
    function askReason(action) {
        if (!reasonForm) { return; }
        reasonAction = action;
        var texts = {
            approve: [sharedText("approve"), sharedText("approve-hint"), sharedText("comment"), false],
            reject: [sharedText("reject"), sharedText("reject-hint"), sharedText("reason"), true],
            cancel: [sharedText("cancel"), sharedText("cancel-hint"), sharedText("reason"), false]
        }[action];
        $("[data-lv-reason-title]", reasonForm).textContent = texts[0];
        $("[data-lv-reason-hint]", reasonForm).textContent = texts[1];
        $("[data-lv-reason-label]", reasonForm).textContent = texts[2];
        $("[data-lv-reason-button]", reasonForm).textContent = texts[0];
        var input = $("[data-lv-reason-input]", reasonForm);
        input.value = "";
        input.required = texts[3];
        $("[data-lv-reason-error]", reasonForm).textContent = "";
        var submit = $("[data-lv-reason-submit]", reasonForm);
        submit.className = "btn " + (action === "approve" ? "btn-success" : "btn-danger");
        modal("lv-reason-modal").show();
        window.setTimeout(function () { input.focus(); }, 300);
    }
    if (reasonForm) {
        reasonForm.addEventListener("submit", function (event) {
            event.preventDefault();
            var input = $("[data-lv-reason-input]", reasonForm);
            if (input.required && !input.value.trim()) {
                $("[data-lv-reason-error]", reasonForm).textContent = HRMS.t("js.lv_reason_needed", "Give a reason.");
                input.focus();
                return;
            }
            var submit = $("[data-lv-reason-submit]", reasonForm);
            busy(submit, true);
            HRMS.post(sharedUrl(reasonAction), body({ id: current.id, level: current.level, comment: input.value.trim() }))
                .then(function (res) {
                    if (answer(res)) {
                        modal("lv-reason-modal").hide();
                        var d = modal("lv-detail-modal");
                        if (d) { d.hide(); }
                        refreshAll();
                    }
                }).catch(oops).then(function () { busy(submit, false); });
        });
    }

    // return to work
    var returnForm = $("[data-lv-return-form]");
    if (returnForm) {
        returnForm.addEventListener("submit", function (event) {
            event.preventDefault();
            var date = $("[data-lv-return-date]", returnForm);
            var error = $("[data-lv-return-error]", returnForm);
            error.textContent = "";
            if (!date.value) { error.textContent = HRMS.t("js.lv_return_date_needed", "Enter the date the employee was back at work."); date.focus(); return; }
            var submit = $("[data-lv-return-submit]", returnForm);
            busy(submit, true);
            HRMS.post(sharedUrl("return"), body({ id: current.id, returnDate: date.value, comment: $("[data-lv-return-comment]", returnForm).value.trim() }))
                .then(function (res) {
                    if (answer(res)) {
                        modal("lv-return-modal").hide();
                        var d = modal("lv-detail-modal");
                        if (d) { d.hide(); }
                        refreshAll();
                    }
                }).catch(oops).then(function () { busy(submit, false); });
        });
    }

    // db/86: leave salary settlement (inside the request popup) - with the monthly
    // payroll, or in cash before the leave
    function wireSettle(root) {
        var f = $("[data-lv-settle-form]", root);
        if (!f) { return; }
        var cash = $("[data-lv-st-cash]", f), amount = $("[data-lv-st-amount]", f);
        var sync = function () {
            var on = $("[data-lv-st-mode]:checked", f);
            cash.hidden = !(on && on.value === "CASH");
        };
        $all("[data-lv-st-mode]", f).forEach(function (r) {
            r.addEventListener("change", function () { sync(); if (!cash.hidden) { amount.focus(); } });
        });
        var reset = $("[data-lv-st-reset]", f);
        if (reset) { reset.addEventListener("click", function () { amount.value = amount.getAttribute("data-suggested"); amount.focus(); }); }
        sync();
        f.addEventListener("submit", function (event) {
            event.preventDefault();
            var error = $("[data-lv-settle-error]", f);
            error.textContent = "";
            var mode = $("[data-lv-st-mode]:checked", f);
            if (!mode) { return; }
            if (mode.value === "CASH") {
                var date = $("[data-lv-st-date]", f);
                if (!(Number(amount.value) > 0)) { error.textContent = HRMS.t("js.lv_cash_amount_needed", "Enter the amount paid in cash."); amount.focus(); return; }
                if (!date.value) { error.textContent = HRMS.t("js.lv_cash_date_needed", "Enter the day the cash is paid."); date.focus(); return; }
            }
            var submit = $("[data-lv-settle-save]", f);
            busy(submit, true);
            var fd = new FormData(f);
            if (mode.value !== "CASH") { fd.delete("amount"); fd.delete("paidOn"); }
            HRMS.post(sharedUrl("settle"), fd).then(function (res) {
                if (answer(res)) {
                    if (current) { openDetail(current.id); }
                    refreshAll();
                }
            }).catch(oops).then(function () { busy(submit, false); });
        });
    }

    // the act buttons - in a list row or in the request popup
    document.addEventListener("click", function (event) {
        var b = event.target.closest("[data-lv-act]");
        if (!b) { return; }
        var act = b.getAttribute("data-lv-act");
        var row = b.closest("[data-lv-row]");
        var detail = b.closest(".modal-content") ? $("[data-lv-detail]", b.closest(".modal-content")) : null;
        if (row) {
            current = { id: row.getAttribute("data-lv-row"), level: row.getAttribute("data-level"), start: row.getAttribute("data-start") };
        } else if (detail) {
            current = { id: detail.getAttribute("data-lv-detail"), level: detail.getAttribute("data-level"), start: detail.getAttribute("data-start") };
        }
        if (!current) { return; }
        if (act === "view") { openDetail(current.id); return; }
        if (act === "edit") {
            modal("lv-detail-modal").hide();
            openForm(b.getAttribute("data-mode") || "my", current.id);
            return;
        }
        if (act === "return") {
            var date = $("[data-lv-return-date]");
            date.value = new Date().toISOString().slice(0, 10);
            if (current.start) { date.min = current.start; }
            $("[data-lv-return-comment]").value = "";
            $("[data-lv-return-error]").textContent = "";
            modal("lv-return-modal").show();
            return;
        }
        askReason(act);
    });

    // a list row opens its request
    document.addEventListener("click", function (event) {
        var row = event.target.closest("tr[data-lv-row]");
        if (!row || event.target.closest("button, a, input, select")) { return; }
        current = { id: row.getAttribute("data-lv-row"), level: row.getAttribute("data-level") };
        openDetail(current.id);
    });

    // new request
    document.addEventListener("click", function (event) {
        var b = event.target.closest("[data-lv-new]");
        if (!b) { return; }
        openForm(b.getAttribute("data-lv-new"), null, b.getAttribute("data-emp"));
    });

    /* ------------------------------------------------- ledger + adjust -- */

    var ledgerBody = $("[data-lv-ledger-body]");
    var ledgerOf = null;
    var ledgerChanged = false;

    function openLedger(emp, type) {
        if (!ledgerBody) { return; }
        ledgerOf = { emp: emp, type: type };
        ledgerBody.innerHTML = '<div class="modal-body">' + loading() + "</div>";
        modal("lv-ledger-modal").show();
        return HRMS.getHtml(withQuery(sharedUrl("ledger"), { emp: emp, type: type })).then(function (html) {
            ledgerBody.innerHTML = html;
        }).catch(function (error) { failed(ledgerBody, error); });
    }
    document.addEventListener("click", function (event) {
        var b = event.target.closest("[data-lv-ledger]");
        if (!b) { return; }
        openLedger(b.getAttribute("data-lv-ledger"), b.getAttribute("data-type"));
    });
    if (ledgerBody) {
        ledgerBody.addEventListener("submit", function (event) {
            var f = event.target.closest("[data-lv-adjust-form]");
            if (!f) { return; }
            event.preventDefault();
            var error = $("[data-lv-adjust-error]", f);
            error.textContent = "";
            var days = f.elements.days.value;
            if (days === "" || Number(days) === 0 && f.elements.entryType.value === "ADJUST") {
                error.textContent = HRMS.t("js.lv_days_needed", "Enter the number of days (use a minus sign to take days off).");
                f.elements.days.focus();
                return;
            }
            var fd = new FormData(f);
            fd.append("emp", ledgerOf.emp);
            fd.append("type", ledgerOf.type);
            var submit = $("button[type=submit]", f);
            busy(submit, true);
            HRMS.post(sharedUrl("adjust"), fd).then(function (res) {
                if (answer(res)) { ledgerChanged = true; openLedger(ledgerOf.emp, ledgerOf.type); }
            }).catch(oops).then(function () { busy(submit, false); });
        });
        ledgerBody.addEventListener("click", function (event) {
            var b = event.target.closest("[data-lv-entry-delete]");
            if (!b) { return; }
            confirmThen(HRMS.t("js.lv_delete_entry", "Delete this entry?"), HRMS.t("js.lv_delete_entry_text", "The balance is worked out again without it."), function () {
                return HRMS.post(sharedUrl("delete-entry"), body({ id: b.getAttribute("data-lv-entry-delete") })).then(function (res) {
                    if (answer(res)) { ledgerChanged = true; openLedger(ledgerOf.emp, ledgerOf.type); }
                });
            });
        });
        document.getElementById("lv-ledger-modal").addEventListener("hidden.bs.modal", function () {
            if (ledgerChanged) { ledgerChanged = false; refreshAll(); }
        });
    }

    /* ---------------------------------------------------- confirmation -- */

    var confirmAction = null;
    function confirmThen(title, text, action) {
        var dialog = document.getElementById("lv-confirm-modal");
        if (!dialog) { HRMS.confirm({ title: title, text: text }).then(function (ok) { if (ok) { action(); } }); return; }
        $("[data-lv-confirm-title]", dialog).textContent = title;
        $("[data-lv-confirm-text]", dialog).textContent = text || "";
        confirmAction = action;
        modal("lv-confirm-modal").show();
    }
    var confirmAccept = $("[data-lv-confirm-accept]");
    if (confirmAccept) {
        confirmAccept.addEventListener("click", function () {
            if (!confirmAction) { return; }
            busy(confirmAccept, true);
            Promise.resolve(confirmAction()).catch(oops).then(function () {
                busy(confirmAccept, false);
                confirmAction = null;
                modal("lv-confirm-modal").hide();
            });
        });
    }

    /* ----------------------------------------------------------- pages -- */

    var refreshers = [];
    function refreshAll() { refreshers.forEach(function (fn) { fn(); }); }
    formChanged = refreshAll;

    if (kind === "requests") {
        var kpiSlot = $("[data-lv-kpis]", page);
        var status = $('[data-lv-f="status"]', page);
        var requests = grid({
            slot: $("[data-lv-slot]", page), count: $("[data-lv-count]", page),
            url: page.getAttribute("data-urls-grid"), filters: $all("[data-lv-f]", page)
        });
        var loadKpis = function () {
            return HRMS.getHtml(page.getAttribute("data-urls-kpis")).then(function (html) {
                kpiSlot.innerHTML = html;
                markKpi();
            }).catch(function () { kpiSlot.innerHTML = ""; });
        };
        var chips = $("[data-lv-status-chips]", page);
        var hasStatus = function (value) { return !!(chips && $('[data-lv-status="' + value + '"]', chips)); };
        var markKpi = function () {
            $all("[data-lv-kpi]", kpiSlot).forEach(function (k) {
                var on = k.getAttribute("data-lv-kpi") === status.value;
                k.classList.toggle("is-active", on);
                k.setAttribute("aria-pressed", on ? "true" : "false");
            });
            if (chips) {
                $all("[data-lv-status]", chips).forEach(function (c) {
                    var on = c.getAttribute("data-lv-status") === status.value;
                    c.classList.toggle("is-active", on);
                    c.setAttribute("aria-pressed", on ? "true" : "false");
                });
            }
        };
        // the status buttons: one is always chosen
        if (chips) {
            chips.addEventListener("click", function (event) {
                var c = event.target.closest("[data-lv-status]");
                if (!c || c.getAttribute("data-lv-status") === status.value) { return; }
                status.value = c.getAttribute("data-lv-status");
                status.dispatchEvent(new Event("change"));
            });
        }
        kpiSlot.addEventListener("click", function (event) {
            var k = event.target.closest("[data-lv-kpi]");
            if (!k) { return; }
            var value = k.getAttribute("data-lv-kpi");
            if (!hasStatus(value)) { return; }
            var first = $("[data-lv-status]", chips);
            status.value = status.value === value ? (hasStatus("PENDING") ? "PENDING" : first.getAttribute("data-lv-status")) : value;
            markKpi();
            requests.first();
        });
        status.addEventListener("change", markKpi);
        var exportButton = $("[data-lv-export]");
        if (exportButton) {
            exportButton.addEventListener("click", function () {
                var v = requests.values();
                delete v.page;
                window.location.href = withQuery(page.getAttribute("data-urls-export"), v);
            });
        }
        refreshers.push(function () { loadKpis(); requests.load(); });
        loadKpis();
        requests.load();
    }

    if (kind === "my") {
        var mine = grid({
            slot: $("[data-lv-slot]", page), count: $("[data-lv-count]", page),
            url: page.getAttribute("data-urls-grid"), filters: $all("[data-lv-f]", page)
        });
        var teamSection = $("[data-lv-team]", page);
        var teamStatus = $("[data-lv-team-status]", page);
        var team = grid({
            slot: $("[data-lv-team-slot]", page), count: $("[data-lv-team-count]", page),
            url: page.getAttribute("data-urls-team"),
            extra: function () { return { status: teamStatus.value }; }
        });
        teamStatus.addEventListener("change", team.first);
        refreshers.push(function () {
            mine.load();
            if (!teamSection.hidden) { team.load(); }
            // the balance cards change with every request - the page shows them fresh
            HRMS.getHtml(HRMS.pageUrl().pathname).then(function (html) {
                var doc = new DOMParser().parseFromString(html, "text/html");
                var fresh = doc.querySelector(".lv-cards"), old = $(".lv-cards", page);
                if (fresh && old) { old.replaceWith(fresh); }
            }).catch(function () { });
        });
        mine.load();
        if (!teamSection.hidden) { team.load(); }
    }

    if (kind === "balances") {
        var balances = grid({
            slot: $("[data-lv-slot]", page), count: $("[data-lv-count]", page),
            url: page.getAttribute("data-urls-grid"), filters: $all("[data-lv-f]", page)
        });
        var balanceExport = $("[data-lv-export]");
        if (balanceExport) {
            balanceExport.addEventListener("click", function () {
                var v = balances.values();
                delete v.page;
                window.location.href = withQuery(page.getAttribute("data-urls-export"), v);
            });
        }
        refreshers.push(balances.load);
        balances.load();
    }

    // the employee profile's Leave tab: loads when the tab is first shown
    $all("[data-lv-panel-url]").forEach(function (host) {
        var load = function () {
            HRMS.getHtml(host.getAttribute("data-lv-panel-url")).then(function (html) { host.innerHTML = html; })
                .catch(function (error) { failed(host, error); });
        };
        var pane = host.closest(".tab-pane");
        var tab = pane ? document.querySelector('[data-bs-target="#' + pane.id + '"]') : null;
        if (!pane || pane.classList.contains("active") || !tab) { load(); } else { tab.addEventListener("shown.bs.tab", load, { once: true }); }
    });

    // ... and is drawn again after a change made from it
    refreshers.push(function () {
        var panel = $("[data-lv-employee]");
        if (!panel || !panel.parentElement || !panel.parentElement.hasAttribute("data-lv-panel-url")) { return; }
        var host = panel.parentElement;
        HRMS.getHtml(host.getAttribute("data-lv-panel-url")).then(function (html) { host.innerHTML = html; }).catch(function () { });
    });

    /* -------------------------------------------------------- settings -- */

    if (kind === "settings") {
        var url = function (name) { return page.getAttribute("data-urls-" + name); };
        var text = function (name) { return page.getAttribute("data-text-" + name) || ""; };
        var setForm = $("[data-lv-set-form]");
        var setBody = $("[data-lv-set-body]", setForm);
        var setError = $("[data-lv-set-error]", setForm);
        var setSave = null;     // what the dialog saves: { url, done }

        // tabs
        var tabs = $all("[data-lv-tab]", page);
        var loaded = {};
        function showTab(name) {
            tabs.forEach(function (t) {
                var on = t.getAttribute("data-lv-tab") === name;
                t.classList.toggle("is-active", on);
                t.setAttribute("aria-selected", on ? "true" : "false");
                t.tabIndex = on ? 0 : -1;
            });
            $all("[data-lv-pane]", page).forEach(function (p) { p.hidden = p.getAttribute("data-lv-pane") !== name; });
            if (!loaded[name]) {
                loaded[name] = true;
                if (name === "types") { loadTypes(); }
                if (name === "holidays") { loadHolidays(); }
            }
            try { sessionStorage.setItem("lv.settings.tab", name); } catch (e) { /* private window */ }
        }
        tabs.forEach(function (t, i) {
            t.addEventListener("click", function () { showTab(t.getAttribute("data-lv-tab")); });
            t.addEventListener("keydown", function (event) {
                var step = { ArrowRight: 1, ArrowLeft: -1 }[event.key];
                if (!step) { return; }
                if (HRMS.isRtl) { step = -step; }
                var next = tabs[(i + step + tabs.length) % tabs.length];
                next.focus();
                showTab(next.getAttribute("data-lv-tab"));
            });
        });

        // leave types
        var typesSlot = $("[data-lv-types-slot]", page);
        function loadTypes() {
            return HRMS.getHtml(url("types")).then(function (html) { typesSlot.innerHTML = html; }).catch(function (e) { failed(typesSlot, e); });
        }
        function openSet(title, formUrl, saveUrl, done, wire) {
            $("[data-lv-set-title]", setForm).textContent = title;
            setError.textContent = "";
            setBody.innerHTML = loading();
            setSave = { url: saveUrl, done: done };
            modal("lv-set-modal").show();
            HRMS.getHtml(formUrl).then(function (html) {
                setBody.innerHTML = html;
                if (wire) { wire(); }
                var first = $("input:not([type=hidden]), select", setBody);
                if (first) { first.focus(); }
            }).catch(function (e) { failed(setBody, e); });
        }
        function wireTypeForm() {
            var mode = $("[data-lv-t-mode]", setBody), pay = $("[data-lv-t-pay]", setBody);
            var tiers = $("[data-lv-t-tiers]", setBody), list = $("[data-lv-tier-list]", setBody);
            function syncMode() {
                $all("[data-lv-t-when]", setBody).forEach(function (el) {
                    el.hidden = el.getAttribute("data-lv-t-when").split(" ").indexOf(mode.value) < 0;
                });
            }
            mode.addEventListener("change", syncMode);
            pay.addEventListener("change", function () { tiers.hidden = pay.value !== "TIERED"; });
            $("[data-lv-tier-add]", setBody).addEventListener("click", function () {
                var rows = $all("[data-lv-tier]", list);
                var last = rows[rows.length - 1];
                var copy = last.cloneNode(true);
                var lastTo = parseInt($("[data-lv-tier-to]", last).value, 10);
                $("[data-lv-tier-from]", copy).value = isNaN(lastTo) ? "" : lastTo + 1;
                $("[data-lv-tier-to]", copy).value = "";
                $("[data-lv-tier-pct]", copy).value = "";
                list.appendChild(copy);
                $("[data-lv-tier-to]", copy).focus();
            });
            list.addEventListener("click", function (event) {
                var b = event.target.closest("[data-lv-tier-remove]");
                if (!b) { return; }
                var rows = $all("[data-lv-tier]", list);
                if (rows.length < 2) { return; }
                var tier = b.closest("[data-lv-tier]");
                if (!HRMS.rowHasInput(tier)) { tier.remove(); return; }
                HRMS.confirm({ title: HRMS.t("js.lv_remove_band", "Remove this pay band?"),
                    note: HRMS.t("js.lv_remove_band_note", "It is dropped when you save the leave type.") })
                    .then(function (ok) { if (ok) { tier.remove(); } });
            });
            syncMode();
        }
        /** Pay bands as "1-15:100,16-25:75" - null when a band is incomplete. */
        function tiersValue() {
            var parts = [];
            var ok = true;
            $all("[data-lv-tier]", setBody).forEach(function (row) {
                var f = $("[data-lv-tier-from]", row).value, t = $("[data-lv-tier-to]", row).value, p = $("[data-lv-tier-pct]", row).value;
                if (f === "" && t === "" && p === "") { return; }
                if (f === "" || t === "" || p === "" || Number(t) < Number(f)) { ok = false; return; }
                parts.push(f + "-" + t + ":" + p);
            });
            return ok ? parts.join(",") : null;
        }

        var typeNew = $("[data-lv-type-new]", page);
        if (typeNew) {
            typeNew.addEventListener("click", function () {
                openSet(text("new-type"), url("type-form"), url("type-save"), loadTypes, wireTypeForm);
            });
        }
        typesSlot.addEventListener("click", function (event) {
            var edit = event.target.closest("[data-lv-type-edit]");
            var toggle = event.target.closest("[data-lv-type-toggle]");
            var del = event.target.closest("[data-lv-type-delete]");
            if (edit) {
                openSet(text("edit-type"), withQuery(url("type-form"), { id: edit.getAttribute("data-lv-type-edit") }), url("type-save"), loadTypes, wireTypeForm);
            } else if (toggle) {
                busy(toggle, true);
                HRMS.post(url("type-toggle"), body({ id: toggle.getAttribute("data-lv-type-toggle") }))
                    .then(function (res) { if (answer(res)) { return loadTypes(); } })
                    .catch(oops).then(function () { busy(toggle, false); });
            } else if (del) {
                var name = del.closest("tr").getAttribute("data-name");
                confirmThen(text("delete-type"), name, function () {
                    return HRMS.post(url("type-delete"), body({ id: del.getAttribute("data-lv-type-delete") }))
                        .then(function (res) { if (answer(res)) { return loadTypes(); } });
                });
            }
        });

        // public holidays
        var holidaysSlot = $("[data-lv-holidays-slot]", page);
        var year = $("[data-lv-holiday-year]", page);
        function loadHolidays() {
            holidaysSlot.innerHTML = loading();
            return HRMS.getHtml(withQuery(url("holidays"), { year: year.value })).then(function (html) { holidaysSlot.innerHTML = html; })
                .catch(function (e) { failed(holidaysSlot, e); });
        }
        function wireHolidayForm() {
            var all = $("[data-lv-h-all]", setBody), company = $("[data-lv-h-company]", setBody);
            var from = $("[data-lv-h-from]", setBody), to = $("[data-lv-h-to]", setBody);
            if (all) { all.addEventListener("change", function () { company.hidden = all.checked; }); }
            from.addEventListener("change", function () {
                to.min = from.value;
                if (!to.value || to.value < from.value) { to.value = from.value; }
            });
        }
        year.addEventListener("change", loadHolidays);
        var holidayNew = $("[data-lv-holiday-new]", page);
        if (holidayNew) {
            holidayNew.addEventListener("click", function () {
                openSet(text("new-holiday"), url("holiday-form"), url("holiday-save"), loadHolidays, wireHolidayForm);
            });
        }
        holidaysSlot.addEventListener("click", function (event) {
            var edit = event.target.closest("[data-lv-holiday-edit]");
            var del = event.target.closest("[data-lv-holiday-delete]");
            if (edit) {
                openSet(text("edit-holiday"), withQuery(url("holiday-form"), { id: edit.getAttribute("data-lv-holiday-edit"), year: year.value }),
                    url("holiday-save"), loadHolidays, wireHolidayForm);
            } else if (del) {
                confirmThen(text("delete-holiday"), del.closest("tr").getAttribute("data-name"), function () {
                    return HRMS.post(url("holiday-delete"), body({ id: del.getAttribute("data-lv-holiday-delete") }))
                        .then(function (res) { if (answer(res)) { return loadHolidays(); } });
                });
            }
        });

        // the type / holiday dialog
        setForm.addEventListener("submit", function (event) {
            event.preventDefault();
            if (!setSave) { return; }
            setError.textContent = "";
            var missing = $all("[required]", setBody).filter(function (f) { return !f.value.trim(); });
            if (missing.length) {
                missing[0].focus();
                setError.textContent = HRMS.t("js.lv_fill_required", "Fill in the fields marked *.");
                return;
            }
            var tiersInput = $("[data-lv-tiers-value]", setBody);
            if (tiersInput) {
                var pay = $("[data-lv-t-pay]", setBody);
                var t = pay.value === "TIERED" ? tiersValue() : "";
                if (t === null || (pay.value === "TIERED" && !t)) {
                    setError.textContent = HRMS.t("js.lv_bands_incomplete", "Complete every pay band: from day, to day and the percent paid.");
                    return;
                }
                tiersInput.value = t;
            }
            var save = $("[data-lv-set-save]", setForm);
            busy(save, true);
            HRMS.post(setSave.url, new FormData(setForm)).then(function (res) {
                if (answer(res)) {
                    modal("lv-set-modal").hide();
                    return setSave.done();
                }
                if (res && res.message) { setError.textContent = res.message; }
            }).catch(oops).then(function () { busy(save, false); });
        });

        // weekend + approval route, one form per company
        $all("[data-lv-company-form]", page).forEach(function (f) {
            f.addEventListener("submit", function (event) {
                event.preventDefault();
                var save = $("button[type=submit]", f);
                busy(save, true);
                HRMS.post(url("company"), new FormData(f)).then(answer).catch(oops).then(function () { busy(save, false); });
            });
        });

        var startTab = "types";
        try { startTab = sessionStorage.getItem("lv.settings.tab") || "types"; } catch (e) { /* private window */ }
        if (!$('[data-lv-tab="' + startTab + '"]', page)) { startTab = "types"; }
        showTab(startTab);
    }
})();
