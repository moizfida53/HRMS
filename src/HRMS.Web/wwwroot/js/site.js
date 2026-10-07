/* ==========================================================================
 * HRMS Kuwait - application shell behaviour
 * Sidebar drawer, global search shortcut, and the toast host used by every
 * module. Loaded on every page.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});

    /* ------------------------------------------------------------ labels --- */
    // UI text for scripts comes from Core.UiLabels (keys "js.*"), emitted by the
    // layout as <script type="application/json" id="hrms-labels">. HRMS.t(key,
    // fallback, arg0, arg1...) returns the text in the user's language, with
    // {0}, {1} replaced; the English fallback keeps the page usable if a label
    // has not been added yet.
    var labels = null;
    HRMS.t = function (key, fallback) {
        if (labels === null) {
            labels = {};
            var block = document.getElementById("hrms-labels");
            if (block) {
                try { labels = JSON.parse(block.textContent || "{}"); } catch (e) { labels = {}; }
            }
        }
        var text = Object.prototype.hasOwnProperty.call(labels, key) ? labels[key] : (fallback || key);
        var args = Array.prototype.slice.call(arguments, 2);
        return args.length ? text.replace(/\{(\d+)\}/g, function (m, i) { return args[i] !== undefined ? args[i] : m; }) : text;
    };
    HRMS.isRtl = document.documentElement.getAttribute("dir") === "rtl";
    HRMS.escape = function (text) {
        return String(text).replace(/[&<>"']/g, function (c) {
            return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c];
        });
    };

    /* ---------------------------------------------------------- sidebar --- */

    var shell = document.getElementById("app-shell");
    var sidebar = document.getElementById("app-sidebar");

    function setNav(open) {
        if (!shell) { return; }

        shell.classList.toggle("is-nav-open", open);
        document.body.style.overflow = open ? "hidden" : "";

        var toggle = document.querySelector("[data-nav-toggle]");
        if (toggle) {
            toggle.setAttribute("aria-expanded", open ? "true" : "false");
        }

        if (open && sidebar) {
            var firstLink = sidebar.querySelector(".hrms-nav-link:not(.is-disabled)");
            if (firstLink) { firstLink.focus(); }
        }
    }

    document.addEventListener("click", function (event) {
        if (event.target.closest("[data-nav-toggle]")) {
            event.preventDefault();
            setNav(!shell.classList.contains("is-nav-open"));
            return;
        }

        if (event.target.closest("[data-nav-close]")) {
            event.preventDefault();
            setNav(false);
        }
    });

    /* ------------------------------------------------- top-bar search --- */

    // The search field is tucked behind an icon button at the top right and
    // opens in a small panel underneath it.
    var topSearch = document.querySelector("[data-topsearch]");
    var topSearchToggle = topSearch ? topSearch.querySelector("[data-topsearch-toggle]") : null;
    var topSearchPanel = topSearch ? topSearch.querySelector(".hrms-topsearch__panel") : null;

    function setSearch(open) {
        if (!topSearch || !topSearchPanel) { return; }

        topSearch.classList.toggle("is-open", open);
        topSearchPanel.hidden = !open;
        topSearchToggle.setAttribute("aria-expanded", open ? "true" : "false");

        if (open) {
            var input = document.getElementById("global-search");
            if (input) { input.focus(); input.select(); }
        }
    }

    function searchIsOpen() {
        return !!(topSearch && topSearch.classList.contains("is-open"));
    }

    if (topSearchToggle) {
        topSearchToggle.addEventListener("click", function () { setSearch(!searchIsOpen()); });
    }

    document.addEventListener("click", function (event) {
        if (searchIsOpen() && !event.target.closest("[data-topsearch]")) { setSearch(false); }
    });

    document.addEventListener("keydown", function (event) {
        // Escape closes the search panel first, then the drawer.
        if (event.key === "Escape" && searchIsOpen()) {
            setSearch(false);
            topSearchToggle.focus();
            return;
        }

        // Escape closes the drawer.
        if (event.key === "Escape" && shell && shell.classList.contains("is-nav-open")) {
            setNav(false);
            var toggle = document.querySelector("[data-nav-toggle]");
            if (toggle) { toggle.focus(); }
            return;
        }

        // Ctrl/Cmd+K opens global search.
        if ((event.ctrlKey || event.metaKey) && event.key.toLowerCase() === "k" && topSearch) {
            event.preventDefault();
            setSearch(true);
        }
    });

    // Returning to a wide viewport should not leave the drawer state stuck on.
    var wide = window.matchMedia("(min-width: 992px)");
    var onWidthChange = function (query) {
        if (query.matches) { setNav(false); }
    };

    if (wide.addEventListener) {
        wide.addEventListener("change", onWidthChange);
    } else if (wide.addListener) {
        wide.addListener(onWidthChange);
    }

    /* ------------------------------------------------------------ toast --- */

    var ICONS = {
        success: '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><polyline points="4,12 9,17 20,6"></polyline></svg>',
        error: '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4l9.5 16H2.5z"></path><path d="M12 10v4.5"></path><circle cx="12" cy="17.3" r="0.7" fill="currentColor" stroke="none"></circle></svg>',
        info: '<svg width="17" height="17" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"></circle><path d="M12 11v5"></path><circle cx="12" cy="7.8" r="0.7" fill="currentColor" stroke="none"></circle></svg>'
    };

    /**
     * Shows a transient message. Text is inserted with textContent, never
     * innerHTML, so a database message can never carry markup into the page.
     */
    HRMS.toast = function (message, type, timeout) {
        var host = document.getElementById("toast-host");
        if (!host || !message) { return; }

        type = ICONS[type] ? type : "info";

        var toast = document.createElement("div");
        toast.className = "hrms-toast hrms-toast--" + type;

        var icon = document.createElement("span");
        icon.innerHTML = ICONS[type];
        icon.setAttribute("aria-hidden", "true");

        var text = document.createElement("span");
        text.className = "hrms-toast__text";
        text.textContent = message;

        var close = document.createElement("button");
        close.type = "button";
        close.className = "hrms-toast__close";
        close.setAttribute("aria-label", HRMS.t("js.dismiss", "Dismiss"));
        close.innerHTML = "&times;";

        toast.appendChild(icon.firstChild ? icon : document.createElement("span"));
        toast.appendChild(text);
        toast.appendChild(close);
        host.appendChild(toast);

        var removed = false;
        function remove() {
            if (removed) { return; }
            removed = true;
            toast.classList.add("is-leaving");
            window.setTimeout(function () {
                if (toast.parentNode) { toast.parentNode.removeChild(toast); }
            }, 200);
        }

        close.addEventListener("click", remove);
        window.setTimeout(remove, timeout || (type === "error" ? 7000 : 4000));
    };

    /* ------------------------------------------------- anti-forgery token -- */

    HRMS.antiForgeryToken = function () {
        var field = document.querySelector('input[name="__RequestVerificationToken"]');
        return field ? field.value : "";
    };

    /**
     * fetch() wrapper that attaches the anti-forgery header and treats any
     * non-2xx response as a failure with a message safe to show the user.
     */
    HRMS.post = function (url, body) {
        return fetch(url, {
            method: "POST",
            credentials: "same-origin",
            headers: { "RequestVerificationToken": HRMS.antiForgeryToken() },
            body: body
        }).then(function (response) {
            if (!response.ok) {
                throw new Error(HRMS.t("js.server_rejected", "The server rejected the request ({0}).", response.status));
            }
            return response.json();
        });
    };

    HRMS.getJson = function (url) {
        return fetch(url, {
            credentials: "same-origin",
            headers: { "Accept": "application/json" }
        }).then(function (response) {
            if (!response.ok) {
                throw new Error(HRMS.t("js.could_not_load_data", "Could not load data ({0}).", response.status));
            }
            return response.json();
        });
    };

    HRMS.getHtml = function (url) {
        return fetch(url, {
            credentials: "same-origin",
            headers: { "Accept": "text/html", "X-Requested-With": "XMLHttpRequest" }
        }).then(function (response) {
            if (!response.ok) {
                throw new Error(HRMS.t("js.could_not_load_panel", "Could not load the panel ({0}).", response.status));
            }
            return response.text();
        });
    };

    /* --------------------------------------------------- company filter -- */

    // Top-bar company dropdown. The choice is saved in a cookie that the
    // server reads on every request (ICompanyFilter), so it carries over
    // from page to page until changed. "all" = every company.
    (function initCompanyFilter() {
        var root = document.querySelector("[data-company-filter]");
        if (!root) { return; }

        var all = root.querySelector("[data-company-all]");
        var boxes = Array.prototype.slice.call(root.querySelectorAll("[data-company-id]"));
        if (!all || !boxes.length) { return; }

        var cookieName = root.dataset.cookie || "hrms_companies";

        all.addEventListener("change", function () {
            if (all.checked) { boxes.forEach(function (b) { b.checked = false; }); }
            else if (!boxes.some(function (b) { return b.checked; })) { all.checked = true; }
        });

        boxes.forEach(function (box) {
            box.addEventListener("change", function () {
                var any = boxes.some(function (b) { return b.checked; });
                // Ticking every company is the same as "All companies".
                var every = boxes.every(function (b) { return b.checked; });
                if (every) { boxes.forEach(function (b) { b.checked = false; }); }
                all.checked = !any || every;
            });
        });

        function save(value) {
            var secure = window.location.protocol === "https:" ? "; Secure" : "";
            document.cookie = cookieName + "=" + encodeURIComponent(value) +
                "; Path=/; Max-Age=" + (60 * 60 * 24 * 365) + "; SameSite=Lax" + secure;
            window.location.reload();
        }

        root.querySelector("[data-company-apply]").addEventListener("click", function () {
            var ids = boxes.filter(function (b) { return b.checked; }).map(function (b) { return b.value; });
            save(ids.length ? ids.join(",") : "all");
        });

        root.querySelector("[data-company-clear]").addEventListener("click", function () { save("all"); });
    })();

    /* -------------------------------------------------- change password -- */

    // Dialog in _Layout, opened from the account menu or the initial-password
    // banner. Rules mirror ChangePasswordViewModel; the server re-checks all.
    (function initChangePassword() {
        var modalEl = document.getElementById("change-password-modal");
        var form = document.getElementById("change-password-form");
        if (!modalEl || !form) { return; }

        var newInput = form.querySelector('[name="NewPassword"]');
        // Authentication:SimplePassword - no strength rules, just 1-50 characters.
        var simple = form.dataset.simple === "true";
        var rules = {
            length: function (v) { return v.length >= 8; },
            "case": function (v) { return /[a-z]/.test(v) && /[A-Z]/.test(v); },
            digit: function (v) { return /\d/.test(v); }
        };

        function updateRules() {
            var value = newInput.value;
            form.querySelectorAll("[data-rule]").forEach(function (li) {
                li.classList.toggle("is-met", rules[li.dataset.rule](value));
            });
        }

        function clearErrors() {
            form.querySelectorAll("[data-valmsg-for]").forEach(function (s) { s.textContent = ""; });
            form.querySelectorAll(".is-invalid").forEach(function (i) { i.classList.remove("is-invalid"); });
        }

        function showError(name, message) {
            var input = form.querySelector('[name="' + name + '"]');
            var target = form.querySelector('[data-valmsg-for="' + name + '"]');
            if (input) { input.classList.add("is-invalid"); }
            if (target) { target.textContent = message; }
        }

        newInput.addEventListener("input", updateRules);

        form.addEventListener("click", function (event) {
            var toggle = event.target.closest("[data-pw-toggle]");
            if (!toggle) { return; }
            var input = toggle.parentNode.querySelector("input");
            var show = input.type === "password";
            input.type = show ? "text" : "password";
            toggle.setAttribute("aria-label", show ? HRMS.t("js.hide_password", "Hide password") : HRMS.t("js.show_password", "Show password"));
            toggle.classList.toggle("is-on", show);
        });

        modalEl.addEventListener("show.bs.modal", function () {
            form.reset();
            clearErrors();
            updateRules();
            form.querySelectorAll("input[type=text][name$=Password]").forEach(function (i) { i.type = "password"; });
        });

        modalEl.addEventListener("shown.bs.modal", function () {
            form.querySelector('[name="CurrentPassword"]').focus();
        });

        form.addEventListener("submit", function (event) {
            event.preventDefault();
            clearErrors();

            // Quick client-side checks so the common mistakes don't need a round trip.
            var current = form.querySelector('[name="CurrentPassword"]').value;
            var next = newInput.value;
            var confirm = form.querySelector('[name="ConfirmPassword"]').value;
            var bad = false;

            if (!current) { showError("CurrentPassword", HRMS.t("js.enter_current_password", "Enter your current password.")); bad = true; }
            if (simple) {
                if (!next) { showError("NewPassword", HRMS.t("js.enter_new_password", "Enter a new password.")); bad = true; }
                else if (next.length > 50) { showError("NewPassword", HRMS.t("js.max_50_chars", "Use at most 50 characters.")); bad = true; }
                else if (next === current) {
                    showError("NewPassword", HRMS.t("js.password_must_differ", "The new password must be different from the current one."));
                    bad = true;
                }
            } else if (!rules.length(next) || !rules["case"](next) || !rules.digit(next)) {
                showError("NewPassword", HRMS.t("js.password_rules_not_met", "The new password doesn't meet the rules below."));
                bad = true;
            } else if (next === current) {
                showError("NewPassword", HRMS.t("js.password_must_differ", "The new password must be different from the current one."));
                bad = true;
            }
            if (next && confirm !== next) { showError("ConfirmPassword", HRMS.t("js.passwords_dont_match", "The two new passwords don't match.")); bad = true; }
            if (bad) {
                var first = form.querySelector(".is-invalid");
                if (first) { first.focus(); }
                return;
            }

            var submit = form.querySelector("[data-cp-submit]");
            var label = submit.querySelector("span");
            var original = label.textContent;
            submit.disabled = true;
            label.textContent = HRMS.t("js.saving", "Saving…");

            HRMS.post(form.getAttribute("action"), new FormData(form))
                .then(function (result) {
                    if (result.success) {
                        bootstrap.Modal.getOrCreateInstance(modalEl).hide();
                        HRMS.toast(result.message, "success", 6000);
                        // The initial-password banner is server-rendered; reload to drop it.
                        if (document.querySelector(".hrms-password-banner")) {
                            window.setTimeout(function () { window.location.reload(); }, 1200);
                        }
                        return;
                    }

                    if (result.errors) {
                        Object.keys(result.errors).forEach(function (key) {
                            showError(key, result.errors[key][0]);
                        });
                        var firstInvalid = form.querySelector(".is-invalid");
                        if (firstInvalid) { firstInvalid.focus(); }
                    } else {
                        HRMS.toast(result.message, "error");
                    }
                })
                .catch(function (error) { HRMS.toast(error.message, "error"); })
                .finally(function () {
                    submit.disabled = false;
                    label.textContent = original;
                });
        });
    })();

    HRMS.debounce = function (fn, wait) {
        var timer = null;
        return function () {
            var context = this;
            var args = arguments;
            window.clearTimeout(timer);
            timer = window.setTimeout(function () { fn.apply(context, args); }, wait);
        };
    };
})();
