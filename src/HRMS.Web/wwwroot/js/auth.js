/* ==========================================================================
 * HRMS Kuwait - sign-in page behaviour
 * Password reveal, and a submit guard that prevents a double post.
 * ========================================================================== */
(function () {
    "use strict";

    /* ------------------------------------------------- password reveal --- */

    var toggle = document.querySelector("[data-toggle-password]");
    var password = document.querySelector('input[type="password"]');

    if (toggle && password) {
        toggle.addEventListener("click", function () {
            var revealed = password.getAttribute("type") === "text";

            password.setAttribute("type", revealed ? "password" : "text");
            toggle.setAttribute("aria-pressed", revealed ? "false" : "true");
            toggle.setAttribute("aria-label", revealed ? HRMS.t("js.show_password", "Show password") : HRMS.t("js.hide_password", "Hide password"));

            var show = toggle.querySelector("[data-eye-show]");
            var hide = toggle.querySelector("[data-eye-hide]");
            if (show) { show.hidden = !revealed; }
            if (hide) { hide.hidden = revealed; }

            // Keep the caret where the user left it.
            password.focus();
            var value = password.value;
            password.value = "";
            password.value = value;
        });
    }

    /* --------------------------------------------------- submit guard --- */

    var form = document.querySelector(".hrms-auth form");

    if (form) {
        form.addEventListener("submit", function () {
            var button = form.querySelector("[data-submit]");
            var label = form.querySelector("[data-submit-label]");
            if (!button || button.disabled) { return; }

            // Disabled after the browser has collected the values, so nothing is
            // dropped from the post.
            window.setTimeout(function () {
                button.disabled = true;
                if (label) { label.textContent = HRMS.t("js.signing_in", "Signing in…"); }
            }, 0);
        });
    }

    /* ------------------------------------- not-yet-built links -------- */

    document.querySelectorAll("[data-not-built]").forEach(function (link) {
        link.addEventListener("click", function (event) {
            event.preventDefault();
            if (window.HRMS && window.HRMS.toast) {
                window.HRMS.toast(HRMS.t("js.password_reset_not_built", "Password reset is the next part of Module 1 - not built yet."), "info");
            }
        });
    });
})();
