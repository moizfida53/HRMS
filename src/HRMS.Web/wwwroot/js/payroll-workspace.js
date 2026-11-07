/* =====================================================================
   payroll-workspace.js - db/123: the header of a payroll's pages
   (Views/Payroll/_RunBar.cshtml): switch to another payroll on the same
   tab, the payroll funding popup, and the tab rail kept in view on a phone.
   Loaded by the header itself, on every page of a payroll.
   ===================================================================== */
(function () {
    "use strict";
    if (window.__hrmsWorkspace) { return; }
    window.__hrmsWorkspace = true;

    function ready(fn) {
        if (document.readyState !== "loading") { fn(); } else { document.addEventListener("DOMContentLoaded", fn); }
    }

    ready(function () {
        var head = document.querySelector("[data-ws]");
        if (!head) { return; }

        // another payroll: the same tab when it is open at that payroll's stage, else its overview
        var select = head.querySelector("[data-ws-run]");
        if (select) {
            select.addEventListener("change", function () {
                if (select.value) { window.HRMS && HRMS.go ? HRMS.go(select.value) : (window.location.href = select.value); }
            });
        }

        // the active tab scrolled into view (the rail scrolls sideways on small screens)
        var rail = document.querySelector("[data-ws-tabs] .ws-tabs__rail");
        var active = rail && rail.querySelector(".ws-tab.is-active");
        if (rail && active && rail.scrollWidth > rail.clientWidth) {
            var left = active.offsetLeft - (rail.clientWidth - active.offsetWidth) / 2;
            rail.scrollLeft = Math.max(0, left);
        }

        // the payroll funding popup
        var modalEl = document.getElementById("ws-funding-modal");
        document.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-ws-funding]");
            if (!b || !modalEl || !window.bootstrap) { return; }
            modalEl.querySelector("[data-ws-funding-heading]").textContent = b.getAttribute("data-ws-funding-title") || "";
            var body = modalEl.querySelector("[data-ws-funding-body]");
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            bootstrap.Modal.getOrCreateInstance(modalEl).show();
            HRMS.getHtml(b.getAttribute("data-ws-funding")).then(function (html) {
                body.innerHTML = html;
            }, function () {
                body.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' +
                    HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div>";
            });
        });
    });
})();
