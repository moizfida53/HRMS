/* ============================================================================
 * DeviceBackButton.js
 * ----------------------------------------------------------------------------
 * Makes the hardware / browser BACK button behave like the on-screen "back
 * arrow" inside the menu, instead of leaving the application.
 *
 * Behaviour:
 *   - Deeper views (item details, items, sub-category, category ...): a Back
 *     press runs the SAME action as that view's on-screen ".back-btn".
 *   - Initial / home page (the view the app first loaded on) OR any top-level
 *     view with no back arrow: a Back press asks the user to confirm before
 *     leaving the page.
 *
 * How it stays correct: on every Back press we look at which view is currently
 * visible and act on it (no fragile counters). We also remember the "home"
 * view captured at load, so leaving the initial page always prompts to exit.
 *
 * Self-contained: it does NOT modify any existing navigation function.
 * Include it AFTER Index.js / BindCartDetails.js.
 * ========================================================================== */
(function () {
    "use strict";

    // Views ordered from DEEPEST to SHALLOWEST. The first one that is visible
    // is the "current" view. Missing ids are skipped safely.
    var VIEW_ORDER = [
        "#divMainItemDetails",          // item details
        "#divCartView",                 // cart
        "#divQRCodeMain",               // generated QR
        "#QRScanView",                  // QR scanner
        "#divReservationConfirm",       // reservation steps
        "#divReservationCustomerInfo",
        "#divReservation",
        "#divMainItemList",             // items listing
        "#divSubCategoryList",          // sub-categories
        "#divCategoryList"              // categories
    ];

    var trapInstalled = false;   // true once we've pushed our first buffer entry
    var exiting = false;         // true when the user has confirmed leaving
    var homeKey = null;          // the view the app started on (null = landing/section)

    function isArabic() {
        if ($("body").hasClass("rtl")) { return true; }
        if (($("html").attr("dir") || "").toLowerCase() === "rtl") { return true; }
        var $lang = $("#selectedLang");
        return $lang.length > 0 && ($lang.val() || "").toUpperCase() === "AR";
    }

    // Id of the view that is currently on screen, or null at a top-level
    // (section / landing) view that is not part of the back chain.
    function currentViewKey() {
        for (var i = 0; i < VIEW_ORDER.length; i++) {
            var $v = $(VIEW_ORDER[i]);
            if ($v.length && $v.is(":visible")) { return VIEW_ORDER[i]; }
        }
        return null;
    }

    // Run the EXACT action the on-screen arrow runs (its inline onclick),
    // without triggering the <a href="#"> default jump.
    function runBackButton($btn) {
        var code = ($btn.attr("onclick") || "").trim();
        if (!code) { return false; }
        try {
            (new Function(code)).call($btn[0]);
            return true;
        } catch (e) {
            if (window.console && console.error) {
                console.error("DeviceBackButton: could not run back action:", code, e);
            }
            return false;
        }
    }

    // Push a single buffer entry so the next Back press lands on us.
    function arm() {
        if (!window.history || !history.pushState) { return; }
        try {
            history.pushState({ emenuTrap: true }, "");
            trapInstalled = true;
        } catch (e) { /* history API unavailable - ignore */ }
    }

    function doExit() {
        exiting = true;
        try { history.back(); } catch (e) { /* nothing to go back to */ }
    }

    function doStay() {
        arm();
    }

    // Initial / top-level page: confirm before leaving.
    function confirmExit() {
        var arabic  = isArabic();
        var title   = arabic ? "تأكيد الخروج"                                : "Exit page?";
        var message = arabic ? "هل أنت متأكد أنك تريد الخروج من الصفحة؟"      : "Are you sure you want to exit the page?";
        var yesTxt  = arabic ? "نعم"                                          : "Yes";
        var noTxt   = arabic ? "لا"                                           : "No";

        if (typeof $.confirm === "function") {
            // Only the two buttons (or Esc => No) can close it, so there is no
            // ambiguous dismissal path that could double-arm the history buffer.
            $.confirm({
                title: title,
                content: message,
                icon: "fa fa-sign-out",
                theme: "bootstrap",
                type: "orange",
                opacity: 0.2,
                animation: "scale",
                closeAnimation: "scale",
                closeIcon: false,
                backgroundDismiss: false,
                escapeKey: "no",
                rtl: arabic,
                buttons: {
                    yes: { text: yesTxt, btnClass: "btn-orange", action: doExit },
                    no:  { text: noTxt, action: doStay }
                }
            });
        } else if (window.confirm(message)) {
            doExit();
        } else {
            doStay();
        }
    }

    function onPopState() {
        if (!trapInstalled || exiting) { return; }

        var key = currentViewKey();
        var atHome = (key === homeKey);                         // back here = leaving the app
        var $btn = key ? $(key).find(".back-btn:visible").first() : $();

        if (!atHome && $btn.length) {
            arm();                  // keep one buffer entry for the next press
            runBackButton($btn);    // mirror the on-screen back arrow
        } else {
            confirmExit();          // initial/home page or no back arrow: confirm exit
        }
    }

    // In-page links (<a href="#">) are used purely as click targets in this SPA —
    // their behaviour lives in onclick. Their DEFAULT action (navigate to the empty
    // "#" fragment) adds a history entry AND fires a spurious popstate, which
    // onPopState would wrongly treat as a back/exit attempt. That is why the
    // "Exit page?" prompt appeared when simply changing category. We suppress only
    // that default navigation; the element's onclick still runs, and anchors with a
    // real fragment (href="#nav-home" etc.) are NOT affected.
    function suppressHashNavigation(e) {
        var t = e.target;
        var a = (t && t.closest) ? t.closest('a[href="#"]') : null;
        if (a) { e.preventDefault(); }
    }

    $(function () {
        if (!window.history || !history.pushState) { return; } // very old browser: leave default behavior
        document.addEventListener("click", suppressHashNavigation, false);
        homeKey = currentViewKey();   // remember the page the app loaded on
        window.addEventListener("popstate", onPopState);
        arm();                        // install the initial buffer entry
    });
})();
