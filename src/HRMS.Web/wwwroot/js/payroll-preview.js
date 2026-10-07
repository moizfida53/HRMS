/* ==========================================================================
 * Payroll design previews (Views/Payroll/Preview) - just enough behaviour to
 * click through the screens that are not built yet: wizard steps, option
 * cards, report list, Pay Items filters and the pay item form. Nothing is
 * saved; buttons with data-toast only show their (translated) message.
 * Payroll Processing has its own, working script: payroll.js.
 * ======================================================================== */
(function () {
    "use strict";
    var HRMS = window.HRMS || {};
    if (!document.querySelector("[data-preview]")) { return; }

    function num(v) { return parseFloat(String(v || "").replace(/,/g, "")); }
    function fmt(v) {
        var s = Math.abs(v).toFixed(3).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
        return (v < 0 ? "-" : "") + s;
    }
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
            countEl.textContent = n === 1 ? HRMS.t("js.prv_one_item", "1 item") : HRMS.t("js.prv_items", "{0} items", n);
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
