/* Payroll prototypes - just enough behaviour to click through the screens.
   No data is saved anywhere. */
(function () {
    "use strict";
    var HRMS = window.HRMS || {};

    // Any element with data-toast shows that message as the app's own toast.
    document.addEventListener("click", function (ev) {
        var el = ev.target.closest("[data-toast]");
        if (el && HRMS.toast) {
            HRMS.toast(el.getAttribute("data-toast"), el.getAttribute("data-toast-type") || "success");
        }
        // Selectable option cards (wizards)
        var choice = ev.target.closest(".pr-choice label");
        if (choice) {
            choice.parentElement.querySelectorAll("label").forEach(function (l) { l.classList.remove("is-selected"); });
            choice.classList.add("is-selected");
        }
        // Report list (left rail) - highlight the picked report
        var rep = ev.target.closest(".pr-report-list a");
        if (rep) {
            ev.preventDefault();
            rep.closest(".pr-report-list").querySelectorAll("a").forEach(function (a) { a.classList.remove("is-active"); });
            rep.classList.add("is-active");
            var title = document.querySelector("[data-report-title]");
            if (title) { title.textContent = rep.querySelector("span").firstChild.textContent.trim(); }
        }
    });

    // Validation filter chips on the workbench: All / Errors / Warnings
    document.querySelectorAll("[data-val-filter]").forEach(function (btn) {
        btn.addEventListener("click", function () {
            var f = btn.getAttribute("data-val-filter");
            document.querySelectorAll("[data-val-filter]").forEach(function (b) { b.classList.toggle("active", b === btn); });
            document.querySelectorAll(".pr-val__item").forEach(function (it) {
                it.hidden = f !== "all" && !it.classList.contains(f === "err" ? "is-err" : "is-warn");
            });
        });
    });

    // Wizard prototypes: Next / Back move between the step panes on the page.
    var panes = document.querySelectorAll("[data-step-pane]");
    if (panes.length) {
        var steps = document.querySelectorAll(".hrms-wizard-step");
        var lines = document.querySelectorAll(".hrms-wizard-step__line");
        var current = 0;
        panes.forEach(function (p, i) { if (!p.hidden) { current = i; } });
        var show = function (n) {
            current = Math.max(0, Math.min(panes.length - 1, n));
            panes.forEach(function (p, i) { p.hidden = i !== current; });
            steps.forEach(function (s, i) {
                s.classList.toggle("is-active", i === current);
                s.classList.toggle("is-complete", i < current);
                var c = s.querySelector(".hrms-wizard-step__circle");
                if (c) { c.innerHTML = i < current ? "&#10003;" : String(i + 1); }
            });
            document.querySelectorAll("[data-step-back]").forEach(function (b) { b.disabled = current === 0; });
            document.querySelectorAll("[data-step-next]").forEach(function (b) { b.hidden = current === panes.length - 1; });
            document.querySelectorAll("[data-step-finish]").forEach(function (b) { b.hidden = current !== panes.length - 1; });
            window.scrollTo({ top: 0, behavior: "smooth" });
        };
        document.querySelectorAll("[data-step-next]").forEach(function (b) { b.addEventListener("click", function () { show(current + 1); }); });
        document.querySelectorAll("[data-step-back]").forEach(function (b) { b.addEventListener("click", function () { show(current - 1); }); });
        steps.forEach(function (s, i) { s.style.cursor = "pointer"; s.addEventListener("click", function () { show(i); }); });
        show(current);
    }

    /* ======================================================================
     * Payroll runs: one selected payroll moves through
     *   Registered -> Validation -> Awaiting Approval -> Closed (or Cancelled)
     * Stage changes are kept in localStorage so the flow can be clicked
     * through; the live app keeps them in Payroll.PayrollRuns.
     * ==================================================================== */
    var STAGES = ["Registered", "Validation", "Awaiting Approval", "Closed"];
    var STAGE_PAGE = ["pp-register", "pp-validation", "pp-approval", "pp-approval"];
    var STAGE_BADGE = { "Registered": "info", "Validation": "warning", "Awaiting Approval": "purple", "Closed": "success", "Cancelled": "muted" };
    var store = {
        get: function (k) { try { return window.localStorage.getItem(k); } catch (e) { return null; } },
        set: function (k, v) { try { window.localStorage.setItem(k, v); } catch (e) { /* ignore */ } }
    };
    function allRuns() {
        var extra = [];
        try { extra = JSON.parse(store.get("pr-extra-runs") || "[]"); } catch (e) { extra = []; }
        return (window.PR_RUNS || []).concat(extra).map(function (r) {
            var o = Object.assign({}, r);
            o.stage = store.get("pr-stage:" + r.id) || r.stage;
            o.level = +(store.get("pr-level:" + r.id) || r.level || 1);
            return o;
        });
    }
    function findRun(id) { return allRuns().filter(function (r) { return r.id === id; })[0] || null; }
    function stageIdx(s) { return s === "Cancelled" ? -1 : STAGES.indexOf(s); }
    function pageOf(r) { var i = stageIdx(r.stage); return STAGE_PAGE[i < 0 ? 0 : i] + ".html?run=" + encodeURIComponent(r.id); }
    function setStage(id, stage) { store.set("pr-stage:" + id, stage); if (stage !== "Awaiting Approval") { store.set("pr-level:" + id, "1"); } }
    function esc(t) { return String(t).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
    function badgeHtml(stage, extra) {
        return '<span class="hrms-badge hrms-badge--' + STAGE_BADGE[stage] + '"><span class="hrms-badge__dot"></span>' + esc(stage) + '</span>' + (extra || "");
    }
    function toast(msg, type) { if (HRMS.toast) { HRMS.toast(msg, type || "success"); } }
    var params = new URLSearchParams(window.location.search);
    var page = (window.location.pathname.split("/").pop() || "").replace(".html", "");
    var runId = params.get("run");
    var run = runId ? findRun(runId) : null;

    // ---- tabs: Register / Validation / Approval only for a selected run, in sequence
    document.querySelectorAll("[data-run-tab]").forEach(function (tab) {
        var need = +tab.getAttribute("data-run-tab");
        var idx = run ? stageIdx(run.stage) : -2;
        var show = run && (need === 0 || idx >= need);
        tab.hidden = !show;
        if (show) { tab.setAttribute("href", tab.getAttribute("href").split("?")[0] + "?run=" + encodeURIComponent(run.id)); }
    });

    // ---- run-scoped pages: need a run, and never ahead of its stage
    var runbar = document.querySelector("[data-runbar]");
    if (runbar) {
        var pageStage = +runbar.getAttribute("data-page-stage");
        if (!run) {
            window.location.replace("pp-calendar.html?pick=1");
            return;
        }
        var idx = stageIdx(run.stage);
        if ((idx < 0 && pageStage > 0) || (idx >= 0 && pageStage > idx)) {
            window.location.replace(pageOf(run));
            return;
        }

        // selector
        var select = runbar.querySelector("[data-run-select]");
        allRuns().forEach(function (r) {
            var o = document.createElement("option");
            o.value = r.id; o.textContent = r.id; o.selected = r.id === run.id;
            select.appendChild(o);
        });
        select.addEventListener("change", function () { window.location.href = pageOf(findRun(select.value)); });
        runbar.querySelector("[data-run-desc]").innerHTML = "<strong>" + esc(run.desc) + "</strong>";
        runbar.querySelector("[data-run-sub]").innerHTML =
            "<span>" + esc(run.period) + "</span> · <span>" + esc(run.cal) + "</span> · <span>" + esc(run.type) + "</span>";

        // stage stepper
        runbar.querySelectorAll("[data-stage-step]").forEach(function (li) {
            var i = +li.getAttribute("data-stage-step");
            li.classList.toggle("is-done", idx > i || run.stage === "Closed");
            li.classList.toggle("is-current", idx === i && run.stage !== "Closed");
        });
        var cancelled = run.stage === "Cancelled";
        runbar.classList.toggle("is-cancelled", cancelled);
        runbar.querySelector("[data-run-cancelled]").hidden = !cancelled;
        // a payroll can be cancelled until it is approved
        runbar.querySelector("[data-run-cancel]").hidden = !(idx >= 0 && idx <= 2);

        // stage-only parts: actions only on the stage the run is in
        document.querySelectorAll("[data-when-stage]").forEach(function (el) {
            el.hidden = el.getAttribute("data-when-stage") !== run.stage;
        });
        var locked = document.querySelector("[data-when-locked]");
        if (locked && run.stage !== ["Registered", "Validation", "Awaiting Approval"][pageStage]) {
            locked.hidden = false;
            var t = locked.querySelector("[data-locked-title]"), x = locked.querySelector("[data-locked-text]");
            if (cancelled) { t.textContent = "This payroll was cancelled."; x.textContent = "It keeps its number and is read-only."; }
            else if (run.stage === "Closed") { t.textContent = "This payroll is approved and closed."; x.textContent = "Payslips, the bank file and the journal can be generated."; }
            else { t.textContent = "This stage is complete."; x.textContent = "The payroll has moved on; this screen is read-only."; }
        }

        // approval level
        document.querySelectorAll("[data-level-badge]").forEach(function (b) { b.textContent = "Level " + run.level + " of 2"; });
        document.querySelectorAll("[data-approval-timeline] [data-level]").forEach(function (li) {
            var l = +li.getAttribute("data-level");
            var reached = run.stage === "Closed" ? 4 : (run.stage === "Awaiting Approval" ? run.level : 0);
            li.className = l < reached ? "is-done" : (l === reached ? "is-current" : "is-todo");
        });
    }

    // ---- actions
    document.addEventListener("click", function (ev) {
        var adv = ev.target.closest("[data-run-advance]");
        if (adv && run) {
            var to = adv.getAttribute("data-run-advance");
            setStage(run.id, to);
            toast("Moved to " + to, adv.hasAttribute("data-advance-back") ? "info" : "success");
            window.setTimeout(function () { window.location.href = pageOf(findRun(run.id)); }, 350);
        }
        var appr = ev.target.closest("[data-run-approve]");
        if (appr && run) {
            if (run.level < 2) { store.set("pr-level:" + run.id, "2"); toast("Level 1 approved - waiting for the Finance Manager"); }
            else { setStage(run.id, "Closed"); toast("Moved to Closed"); }
            window.setTimeout(function () { window.location.reload(); }, 350);
        }
        if (ev.target.closest("[data-run-cancel-confirm]")) {
            var reason = document.querySelector("[data-cancel-reason]");
            if (reason && !reason.value.trim()) { reason.classList.add("is-invalid"); return; }
            var id = run ? run.id : (document.querySelector("[data-cancel-target]") || {}).value;
            if (id) { setStage(id, "Cancelled"); toast("Payroll cancelled", "info"); window.setTimeout(function () { window.location.reload(); }, 350); }
        }
        if (ev.target.closest("[data-proto-fix]")) {
            ev.preventDefault();
            document.querySelectorAll("[data-needs-no-errors]").forEach(function (b) { b.disabled = false; });
            var n = document.querySelector("[data-val-errors]"); if (n) { n.textContent = "0"; }
            var bn = document.querySelector("[data-errors-banner]"); if (bn) { bn.hidden = true; }
            document.querySelectorAll("tr.pr-row-error").forEach(function (tr) { tr.hidden = true; });
            toast("Validation re-run: 0 errors, 7 warnings");
        }
        if (ev.target.closest("[data-proto-reset]")) {
            ev.preventDefault();
            (window.PR_RUNS || []).forEach(function (r) { try { localStorage.removeItem("pr-stage:" + r.id); localStorage.removeItem("pr-level:" + r.id); } catch (e) { } });
            store.set("pr-extra-runs", "[]");
            window.location.reload();
        }
    });

    // ---- Payroll Calendar: every payroll with its stage
    var body = document.querySelector("[data-runs-body]");
    if (body) {
        if (params.get("pick")) { toast("Select a payroll first", "info"); }
        var perSel = document.querySelector("[data-runs-period]"), stSel = document.querySelector("[data-runs-stage]");
        var render = function () {
            var rows = allRuns().filter(function (r) {
                return (!perSel.value || r.month === perSel.value) && (!stSel.value || r.stage === stSel.value);
            }).sort(function (a, b) { return a.id < b.id ? 1 : -1; });
            body.innerHTML = rows.map(function (r) {
                var lvl = r.stage === "Awaiting Approval" ? '<div class="hrms-text-xs hrms-muted mt-1">Level ' + r.level + ' of 2</div>' : "";
                var open = '<a class="btn-icon" href="' + pageOf(r) + '" title="Open" aria-label="Open">' +
                    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M2 12s3.6-7 10-7 10 7 10 7-3.6 7-10 7-10-7-10-7z"/><circle cx="12" cy="12" r="3"/></svg></a>';
                var steps = '<span class="pr-mini-stages" aria-hidden="true">' + STAGES.map(function (s, i) {
                    var k = stageIdx(r.stage); return '<i class="' + (r.stage === "Closed" || k > i ? "is-done" : (k === i ? "is-current" : "")) + '"></i>';
                }).join("") + "</span>";
                return '<tr class="' + (r.stage === "Cancelled" ? "pr-row-cancelled" : "") + '">' +
                    '<td data-label="Payroll"><a class="hrms-code-chip" href="' + pageOf(r) + '">' + esc(r.id) + '</a><div class="hrms-text-xs hrms-muted mt-1">' + esc(r.desc) + '</div></td>' +
                    '<td data-label="Period" class="col-p2">' + esc(r.period) + '</td>' +
                    '<td data-label="Calendar" class="col-p3">' + esc(r.cal) + '</td>' +
                    '<td data-label="Type" class="col-p3">' + esc(r.type) + '</td>' +
                    '<td data-label="Employees" class="text-center col-p3">' + r.emp + '</td>' +
                    '<td data-label="Net (KWD)" class="pr-money col-p2">' + esc(r.net) + '</td>' +
                    '<td data-label="Stage">' + steps + badgeHtml(r.stage) + lvl + '</td>' +
                    '<td class="hrms-table__actions">' + open + '</td></tr>';
            }).join("") || '<tr><td colspan="8" class="text-center hrms-muted py-4">No payrolls match</td></tr>';
            var c = document.querySelector("[data-runs-count]"); if (c) { c.textContent = rows.length + " payrolls"; }
        };
        perSel.addEventListener("change", render); stSel.addEventListener("change", render);
        render();
    }

    // ---- Create Payroll: generated run name + description rule
    var nameEl = document.querySelector("[data-run-name]");
    if (nameEl) {
        var co = (window.PR_COMPANY || { code: "DTC" }).code;
        var per = document.querySelector("[data-run-period]"), calSel = document.querySelector("[data-run-calendar]");
        var desc = document.querySelector("[data-run-desc-input]");
        var typeOf = function () { var c = document.querySelector("[data-run-type] input:checked"); return c ? c.value : "Regular"; };
        var refresh = function () {
            var month = per.value;
            var same = allRuns().filter(function (r) { return r.id.indexOf(co + "-" + month + "-") === 0; });
            var cancelled = same.filter(function (r) { return r.stage === "Cancelled"; }).length;
            var next = co + "-" + month + "-" + String(same.length + 1).padStart(2, "0");
            nameEl.value = next;
            document.querySelectorAll("[data-run-name-final]").forEach(function (x) { x.textContent = next; });
            var hint = document.querySelector("[data-run-name-hint]");
            hint.textContent = same.length
                ? same.length + " payroll(s) already issued for this company in " + per.options[per.selectedIndex].text.split(" (")[0] + (cancelled ? " (" + cancelled + " cancelled)" : "") + " - this is number " + (same.length + 1) + "."
                : "First payroll for this company in " + per.options[per.selectedIndex].text.split(" (")[0] + ".";
            var required = same.length > 0 || typeOf() !== "Regular";
            document.querySelector("[data-run-desc-req]").hidden = !required;
            document.querySelector("[data-run-desc-hint]").textContent = required
                ? "Required: say why this payroll is generated - it is shown on the Payroll Calendar and in the approval."
                : "Optional for the first regular payroll of the month.";
            desc.dataset.required = required ? "1" : "";
            var regular = same.filter(function (r) { return r.type === "Regular" && r.cal === calSel.value && r.stage !== "Cancelled"; })[0];
            var block = typeOf() === "Regular" && regular;
            document.querySelector("[data-regular-exists]").hidden = !block;
            if (regular) { document.querySelector("[data-regular-exists-id]").textContent = regular.id; }
            document.querySelectorAll("[data-run-create]").forEach(function (b) { b.disabled = !!block; });
        };
        [per, calSel].forEach(function (x) { x.addEventListener("change", refresh); });
        document.addEventListener("change", function (ev) { if (ev.target.closest("[data-run-type]")) { refresh(); } });
        desc.addEventListener("input", function () { desc.classList.remove("is-invalid"); document.querySelector("[data-run-desc-error]").hidden = true; });
        refresh();

        document.querySelectorAll("[data-run-create]").forEach(function (b) {
            b.addEventListener("click", function () {
                if (desc.dataset.required && !desc.value.trim()) {
                    desc.classList.add("is-invalid");
                    document.querySelector("[data-run-desc-error]").hidden = false;
                    var first = document.querySelector("[data-step-pane]");
                    document.querySelectorAll(".hrms-wizard-step")[0].click();
                    desc.focus();
                    return;
                }
                var extra = [];
                try { extra = JSON.parse(store.get("pr-extra-runs") || "[]"); } catch (e) { extra = []; }
                var month = per.value, label = per.options[per.selectedIndex].text.split(" (")[0];
                extra.push({ id: nameEl.value, month: month, period: label, cal: calSel.value, type: typeOf(),
                             desc: desc.value.trim() || "Regular monthly payroll", emp: typeOf() === "Regular" ? 412 : 6,
                             net: "—", stage: "Registered", by: "Priya Nair" });
                store.set("pr-extra-runs", JSON.stringify(extra));
                toast("Payroll created - Registered");
                window.setTimeout(function () { window.location.href = "pp-register.html?run=" + encodeURIComponent(nameEl.value); }, 350);
            });
        });
    }
})();

/* ==========================================================================
 * Pay items as line items (feedback round 3)
 *  - Create Payroll, step 2: every employee's lines, add / remove lines for
 *    this payroll, add the same line to several selected employees.
 *  - Pay Items: one list filtered by employee and class; the item form
 *    shows the fields of the chosen class.
 * ======================================================================== */
(function () {
    "use strict";
    var HRMS = window.HRMS || {};
    function toast(msg, type) { if (HRMS.toast) { HRMS.toast(msg, type || "success"); } }
    function esc(t) { return String(t).replace(/[&<>"]/g, function (c) { return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" }[c]; }); }
    function num(v) { return parseFloat(String(v || "").replace(/,/g, "")); }
    function fmt(v) {
        var s = Math.abs(v).toFixed(3).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (v < 0 ? "-" : "") + s;
    }
    var BADGE = { Salary: "info", Earning: "success", Deduction: "warning", Loan: "purple", Statutory: "muted" };
    var LABEL = { Salary: "Salary", Earning: "Earning", Deduction: "Deduction", Loan: "Loan / advance", Statutory: "Statutory" };

    // A class select filters the item-type select next to it.
    function filterTypes(typeSel, cls) {
        var first = null;
        Array.prototype.forEach.call(typeSel.options, function (o) {
            var c = o.getAttribute("data-cls");
            var ok = !c || c === cls;
            o.hidden = !ok; o.disabled = !ok;
            if (ok && c && !first) { first = o; }
        });
        var cur = typeSel.options[typeSel.selectedIndex];
        if (!cur || cur.disabled) { typeSel.value = first ? first.value : ""; }
    }

    /* ------------------------------------------------ Create Payroll: step 2 */
    var empTable = document.querySelector(".pr-emp-table");
    if (empTable) {
        var kErn = document.querySelector("[data-kpi-ern]"), kDed = document.querySelector("[data-kpi-ded]");
        var base = { ern: kErn ? num(kErn.textContent) : 0, ded: kDed ? num(kDed.textContent) : 0, plus: 0, minus: 0 };

        var lineHtml = function (cls, type, comment, amt) {
            return '<tr data-line data-new="1" data-cls="' + cls + '" data-amt="' + amt.toFixed(3) + '">' +
                '<td data-label="Class"><span class="hrms-badge hrms-badge--' + BADGE[cls] + '"><span class="hrms-badge__dot"></span>' + LABEL[cls] + '</span></td>' +
                '<td data-label="Item type" class="hrms-nowrap">' + esc(type) + '</td>' +
                '<td data-label="Comment" class="pr-line-comment" data-no-tr>' + esc(comment) + '</td>' +
                '<td data-label="Source"><span class="pr-line-src is-new">Added in this payroll</span></td>' +
                '<td data-label="Amount (KWD)" class="pr-money' + (amt < 0 ? " pr-neg" : "") + '">' + fmt(amt) + '</td>' +
                '<td class="pr-line-act"><button type="button" class="btn-icon btn-icon--danger" title="Remove" aria-label="Remove" data-line-remove>' +
                '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M4 7h16M10 4h4M9 7v11M15 7v11"/><path d="M6 7l1 13h10l1-13"/></svg></button></td></tr>';
        };
        var empRow = function (code) { return empTable.querySelector('tr[data-emp="' + code + '"]'); };
        var linesRow = function (code) { return empTable.querySelector('tr[data-lines-for="' + code + '"]'); };

        var recalc = function (code) {
            var t = { sal: 0, ern: 0, ded: 0 }, n = 0;
            linesRow(code).querySelectorAll("tr[data-line]").forEach(function (l) {
                var a = num(l.getAttribute("data-amt")), c = l.getAttribute("data-cls");
                t[c === "Salary" ? "sal" : (c === "Earning" ? "ern" : "ded")] += a; n++;
            });
            var row = empRow(code);
            ["sal", "ern", "ded"].forEach(function (k) { row.querySelector('[data-sum="' + k + '"]').textContent = fmt(t[k]); });
            row.querySelector('[data-sum="net"]').textContent = fmt(t.sal + t.ern + t.ded);
            row.querySelector("[data-lines-count]").textContent = n;
        };
        var summary = function () {
            var count = 0, plus = 0, minus = 0;
            empTable.querySelectorAll("tr[data-line]").forEach(function (l) {
                if (l.getAttribute("data-new") !== "1" && !l.querySelector(".pr-line-src.is-new")) { return; }
                var a = num(l.getAttribute("data-amt"));
                count++; if (a >= 0) { plus += a; } else { minus += -a; }
            });
            if (base.first === undefined) { base.first = true; base.plus = plus; base.minus = minus; }
            document.querySelectorAll("[data-added-count]").forEach(function (x) { x.textContent = count; });
            var p = document.querySelector("[data-added-plus]"), m = document.querySelector("[data-added-minus]");
            if (p) { p.textContent = fmt(plus); }
            if (m) { m.textContent = fmt(minus); }
            if (kErn) { kErn.textContent = fmt(base.ern + plus - base.plus); }
            if (kDed) { kDed.textContent = fmt(base.ded - (minus - base.minus)); }
        };
        summary();

        var addLine = function (code, cls, type, amount, comment) {
            var amt = cls === "Earning" ? Math.abs(amount) : -Math.abs(amount);
            linesRow(code).querySelector("[data-lines-body]").insertAdjacentHTML("beforeend", lineHtml(cls, type, comment, amt));
            recalc(code);
        };
        var setOpen = function (code, open) {
            var btn = empRow(code).querySelector("[data-lines-toggle]");
            linesRow(code).hidden = !open;
            btn.setAttribute("aria-expanded", open ? "true" : "false");
            empRow(code).classList.toggle("is-open", open);
        };

        empTable.addEventListener("click", function (ev) {
            var tg = ev.target.closest("[data-lines-toggle]");
            if (tg) { var c = tg.getAttribute("data-lines-toggle"); setOpen(c, linesRow(c).hidden); return; }
            var rm = ev.target.closest("[data-line-remove]");
            if (rm) {
                var code = rm.closest("[data-lines-for]").getAttribute("data-lines-for");
                rm.closest("tr").remove(); recalc(code); summary(); toast("Line removed", "info"); return;
            }
            var add = ev.target.closest("[data-add-line]");
            if (add) {
                var f = add.closest("[data-line-add]"), code2 = f.getAttribute("data-line-add");
                var amtEl = f.querySelector("[data-add-amt]"), comEl = f.querySelector("[data-add-com]");
                var amount = num(amtEl.value), comment = comEl.value.trim();
                amtEl.classList.toggle("is-invalid", !(amount > 0));
                comEl.classList.toggle("is-invalid", !comment);
                if (!(amount > 0) || !comment) { toast("Enter an amount and a comment.", "danger"); return; }
                var typeSel = f.querySelector("[data-add-type]");
                addLine(code2, f.querySelector("[data-add-cls]").value, typeSel.options[typeSel.selectedIndex].text, amount, comment);
                amtEl.value = ""; comEl.value = "";
                summary(); toast("Line added");
            }
        });
        empTable.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-add-cls]")) {
                filterTypes(ev.target.closest("[data-line-add]").querySelector("[data-add-type]"), ev.target.value);
            }
        });
        empTable.querySelectorAll("[data-line-add]").forEach(function (f) { filterTypes(f.querySelector("[data-add-type]"), "Earning"); });

        // Show all lines / hide all lines
        var expandBtn = document.querySelector("[data-lines-expand-all]");
        if (expandBtn) {
            expandBtn.addEventListener("click", function () {
                var open = expandBtn.getAttribute("aria-pressed") !== "true";
                expandBtn.setAttribute("aria-pressed", open ? "true" : "false");
                expandBtn.querySelector("span").textContent = open ? "Hide all lines" : "Show all lines";
                empTable.querySelectorAll("tr[data-emp]").forEach(function (r) { if (!r.hidden) { setOpen(r.getAttribute("data-emp"), open); } });
            });
        }

        // Search and the "Show" filter
        var search = document.querySelector("[data-emp-search]"), show = document.querySelector("[data-emp-filter]");
        var applyFilter = function () {
            var q = (search.value || "").trim().toLowerCase(), f = show.value;
            empTable.querySelectorAll("tr[data-emp]").forEach(function (r) {
                var code = r.getAttribute("data-emp");
                var ok = !q || r.getAttribute("data-emp-name").indexOf(q) >= 0;
                if (ok && f === "added") { ok = !!linesRow(code).querySelector('tr[data-new="1"], .pr-line-src.is-new'); }
                else if (ok && f !== "all") { ok = (" " + r.getAttribute("data-flags") + " ").indexOf(" " + f + " ") >= 0; }
                r.hidden = !ok;
                if (!ok) { linesRow(code).hidden = true; }
                else if (r.classList.contains("is-open")) { linesRow(code).hidden = false; }
            });
        };
        if (search) { search.addEventListener("input", applyFilter); }
        if (show) { show.addEventListener("change", applyFilter); }

        // Selection and "Add line to selected"
        var checks = function () { return Array.prototype.slice.call(empTable.querySelectorAll("[data-emp-check]")); };
        var selected = function () { return checks().filter(function (c) { return c.checked && !c.closest("tr").hidden; }); };
        var bulkBtn = document.querySelector("[data-bulk-open]"), selInfo = document.querySelector("[data-emp-selected]");
        var syncSel = function () {
            var n = selected().length;
            bulkBtn.disabled = n === 0;
            selInfo.hidden = n === 0;
            selInfo.textContent = n + " selected";
            checks().forEach(function (c) { c.closest("tr").classList.toggle("is-selected", c.checked); });
        };
        empTable.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-emp-check-all]")) {
                checks().forEach(function (c) { if (!c.closest("tr").hidden) { c.checked = ev.target.checked; } });
            }
            if (ev.target.matches("[data-emp-check], [data-emp-check-all]")) { syncSel(); }
        });
        var bm = document.getElementById("bulk-line-modal");
        if (bm) {
            var bCls = bm.querySelector("[data-bulk-cls]"), bType = bm.querySelector("[data-bulk-type]");
            filterTypes(bType, bCls.value);
            bCls.addEventListener("change", function () { filterTypes(bType, bCls.value); });
            bm.addEventListener("show.bs.modal", function () { bm.querySelector("[data-bulk-count]").textContent = selected().length; });
            bm.querySelector("[data-bulk-add]").addEventListener("click", function () {
                var amtEl = bm.querySelector("[data-bulk-amt]"), comEl = bm.querySelector("[data-bulk-com]");
                var amount = num(amtEl.value), comment = comEl.value.trim();
                var bad = !(amount > 0) || !comment;
                bm.querySelector("[data-bulk-error]").hidden = !bad;
                amtEl.classList.toggle("is-invalid", !(amount > 0)); comEl.classList.toggle("is-invalid", !comment);
                if (bad) { return; }
                var rows = selected();
                rows.forEach(function (c) {
                    var code = c.closest("tr").getAttribute("data-emp");
                    addLine(code, bCls.value, bType.options[bType.selectedIndex].text, amount, comment);
                    setOpen(code, true);
                    c.checked = false;
                });
                var all = empTable.querySelector("[data-emp-check-all]"); if (all) { all.checked = false; }
                syncSel(); summary();
                amtEl.value = ""; comEl.value = "";
                if (window.bootstrap) { window.bootstrap.Modal.getOrCreateInstance(bm).hide(); }
                toast("Line added to " + rows.length + " employees");
            });
        }
    }

    // Links that jump to a wizard step (e.g. "Review" in the check list)
    document.addEventListener("click", function (ev) {
        var g = ev.target.closest("[data-step-goto]");
        if (!g) { return; }
        ev.preventDefault();
        var s = document.querySelectorAll(".hrms-wizard-step")[+g.getAttribute("data-step-goto")];
        if (s) { s.click(); }
    });

    /* ------------------------------------------------------------ Pay Items */
    var itemsTable = document.querySelector("tr[data-item]");
    if (itemsTable) {
        var empSel = document.querySelector("[data-items-emp]"), q = document.querySelector("[data-items-search]");
        var countEl = document.querySelector("[data-items-count]");
        var apply = function () {
            var emp = empSel.value, cls = (document.querySelector("[data-items-class] input:checked") || {}).value || "";
            var text = (q.value || "").trim().toLowerCase(), n = 0;
            document.querySelectorAll("tr[data-item]").forEach(function (r) {
                var ok = (!emp || r.getAttribute("data-emp") === emp) && (!cls || r.getAttribute("data-cls") === cls)
                    && (!text || r.textContent.toLowerCase().indexOf(text) >= 0);
                r.hidden = !ok; if (ok) { n++; }
            });
            document.querySelectorAll("[data-emp-summary]").forEach(function (s) { s.hidden = s.getAttribute("data-emp-summary") !== emp; });
            countEl.textContent = n + " items";
        };
        var pre = new URLSearchParams(window.location.search).get("emp");
        if (pre && empSel.querySelector('option[value="' + pre + '"]')) { empSel.value = pre; }
        empSel.addEventListener("change", apply);
        q.addEventListener("input", apply);
        document.querySelectorAll("[data-items-class] input").forEach(function (r) { r.addEventListener("change", apply); });
        apply();
    }

    // The pay item form: fields follow the chosen class
    var itemForm = document.querySelector("[data-item-class]");
    if (itemForm) {
        var modalBody = itemForm.closest(".modal-body");
        var typeSel = modalBody.querySelector("[data-item-type]"), appliesSel = modalBody.querySelector("[data-item-applies]");
        var syncForm = function () {
            var cls = (itemForm.querySelector("input:checked") || {}).value || "Earning";
            modalBody.querySelectorAll("[data-show-for]").forEach(function (el) {
                el.hidden = (" " + el.getAttribute("data-show-for") + " ").indexOf(" " + cls + " ") < 0;
            });
            filterTypes(typeSel, cls);
            Array.prototype.forEach.call(appliesSel.options, function (o) {
                var only = o.getAttribute("data-cls-only");
                o.hidden = o.disabled = !!only && only !== cls;
            });
            if (appliesSel.options[appliesSel.selectedIndex].disabled) { appliesSel.value = "once"; }
        };
        itemForm.addEventListener("change", syncForm);
        syncForm();
        var tot = modalBody.querySelector("[data-loan-total]"), cnt = modalBody.querySelector("[data-loan-count]"), mon = modalBody.querySelector("[data-loan-monthly]");
        var loanCalc = function () {
            var t = num(tot.value), c = parseInt(cnt.value, 10);
            mon.textContent = t > 0 && c > 0 ? fmt(t / c) : "—";
        };
        [tot, cnt].forEach(function (x) { x.addEventListener("input", loanCalc); });
        loanCalc();
    }
})();
