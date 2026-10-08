/* ==========================================================================
 * HRMS Kuwait - Payroll Dashboard
 * The page is rendered by the server; this script only sends the period
 * form when another payroll month is picked (form[data-dash-period]).
 * ========================================================================== */
(function () {
    "use strict";

    document.querySelectorAll("form[data-dash-period]").forEach(function (form) {
        var select = form.querySelector("[data-dash-month]");
        if (!select) return;
        select.addEventListener("change", function () {
            form.classList.add("is-loading");
            form.submit();
        });
    });
})();
