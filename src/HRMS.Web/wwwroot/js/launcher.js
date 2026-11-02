/* =============================================================================
 * Application launcher (/apps): each tile shows its icon and name; the app's
 * description shows in a Bootstrap tooltip on hover or keyboard focus.
 * (A file of its own: the Content-Security-Policy allows no inline script.)
 * ========================================================================== */
(function () {
    "use strict";
    if (!window.bootstrap || !window.bootstrap.Tooltip) { return; }

    var tips = [];
    document.querySelectorAll('.hrms-launcher [data-bs-toggle="tooltip"]').forEach(function (el) {
        tips.push(new window.bootstrap.Tooltip(el, {
            placement: "bottom",
            trigger: "hover focus",
            container: "body",
            customClass: "hrms-app-tooltip",
            fallbackPlacements: ["top", "right", "left"]
        }));
    });

    // a tile opened in a new tab (Online Order) keeps focus here: hide its tooltip
    document.addEventListener("click", function (e) {
        if (e.target.closest(".hrms-app-tile")) { tips.forEach(function (t) { t.hide(); }); }
    });
})();
