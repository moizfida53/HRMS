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

    /* --------------------------------------- sidebar: auto-minimize ----- */
    // Desktop (>= 992px): the sidebar rests as an icon rail (html.nav-mini, set by
    // nav-mode.js before the first paint) and expands over the page (html.nav-peek)
    // when the pointer rests on it, the mouse wheel scrolls over it, or the keyboard
    // moves into it; it minimizes again shortly after the pointer leaves. The pin
    // button keeps it open (remembered per browser). Below 992px it stays a drawer.
    var root = document.documentElement;
    var desktop = window.matchMedia("(min-width: 992px)");
    var NAV_MODE = "hrms:nav-mode";
    var pinButton = sidebar ? sidebar.querySelector("[data-nav-pin]") : null;
    var peekTimer = null, leaveTimer = null;

    function isMini() { return root.classList.contains("nav-mini"); }
    function isPeek() { return root.classList.contains("nav-peek"); }
    function accountMenuOpen() { return !!(sidebar && sidebar.querySelector(".hrms-sidebar__footer .dropdown-menu.show")); }

    function collapseOf(el) { return window.bootstrap ? window.bootstrap.Collapse.getOrCreateInstance(el, { toggle: false }) : null; }

    // Auto-collapse inactive sections: back to only what leads to the current page
    // (inactive groups / sub-sections close, the current page's ones reopen).
    function foldInactive() {
        if (!sidebar) { return; }
        Array.prototype.forEach.call(sidebar.querySelectorAll(".hrms-sidebar__nav .collapse"), function (el) {
            var holdsActive = !!el.querySelector(".is-active");
            var shown = el.classList.contains("show");
            if (holdsActive === shown) { return; }
            var c = collapseOf(el);
            if (c) { if (holdsActive) { c.show(); } else { c.hide(); } }
        });
    }

    function syncPin() {
        if (!pinButton) { return; }
        var pinned = !isMini();
        var label = pinButton.getAttribute(pinned ? "data-label-unpin" : "data-label-pin") || "";
        pinButton.setAttribute("aria-pressed", pinned ? "true" : "false");
        pinButton.setAttribute("title", label);
        pinButton.setAttribute("aria-label", label);
    }

    function setPeek(on) {
        window.clearTimeout(peekTimer);
        window.clearTimeout(leaveTimer);
        if (on && (!isMini() || !desktop.matches)) { return; }
        if (on === isPeek()) { return; }
        root.classList.toggle("nav-peek", on);
        if (!on) { foldInactive(); }
    }

    function setPinned(pinned) {
        root.classList.toggle("nav-mini", !pinned);
        root.classList.remove("nav-peek");
        try { window.localStorage.setItem(NAV_MODE, pinned ? "pinned" : "auto"); } catch (e) { /* storage off */ }
        syncPin();
        if (!pinned) { foldInactive(); }
    }

    if (sidebar) {
        syncPin();
        // transitions only after the first paint (no animation on page load)
        window.requestAnimationFrame(function () { root.classList.add("nav-ready"); });

        if (pinButton) {
            pinButton.addEventListener("click", function () {
                var pinNow = isMini();
                setPinned(pinNow);
                if (!pinNow && sidebar.matches(":hover")) { root.classList.add("nav-peek"); }
            });
        }

        sidebar.addEventListener("mouseenter", function () {
            window.clearTimeout(leaveTimer);
            if (!isMini() || isPeek()) { return; }
            peekTimer = window.setTimeout(function () { setPeek(true); }, 140);
        });
        sidebar.addEventListener("mouseleave", function () {
            window.clearTimeout(peekTimer);
            if (!isPeek() || accountMenuOpen()) { return; }
            leaveTimer = window.setTimeout(function () { setPeek(false); }, 380);
        });
        // a turn of the mouse wheel over the rail opens it at once
        sidebar.addEventListener("wheel", function () {
            if (isMini() && !isPeek()) { setPeek(true); }
        }, { passive: true });
        // keyboard users: tabbing into the rail opens it, tabbing out closes it
        sidebar.addEventListener("focusin", function (event) {
            if (isMini() && event.target.matches && event.target.matches(":focus-visible")) { setPeek(true); }
        });
        sidebar.addEventListener("focusout", function (event) {
            if (isPeek() && !sidebar.contains(event.relatedTarget) && !sidebar.matches(":hover") && !accountMenuOpen()) { setPeek(false); }
        });
        // the account menu closed while the pointer is elsewhere
        sidebar.addEventListener("hidden.bs.dropdown", function () {
            if (isPeek() && !sidebar.matches(":hover")) { setPeek(false); }
        });

        // Accordion: opening a group or a sub-section closes the others at its level.
        sidebar.addEventListener("show.bs.collapse", function (event) {
            var el = event.target;
            var level = el.classList.contains("hrms-nav-group__items") ? ".hrms-nav-group__items"
                      : el.classList.contains("hrms-nav-sub") ? ".hrms-nav-sub" : null;
            if (!level) { return; }
            var scope = level === ".hrms-nav-sub" ? (el.closest(".hrms-nav-group__items") || sidebar) : sidebar;
            Array.prototype.forEach.call(scope.querySelectorAll(level + ".show"), function (other) {
                if (other !== el) {
                    var c = collapseOf(other);
                    if (c) { c.hide(); }
                }
            });
        });

        var onDesktopChange = function () { if (!desktop.matches) { root.classList.remove("nav-peek"); } };
        if (desktop.addEventListener) { desktop.addEventListener("change", onDesktopChange); } else if (desktop.addListener) { desktop.addListener(onDesktopChange); }
    }

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

    /* ------------------------------------------------------------------
     * Searchable dropdown: <select data-searchable> gets a button and a
     * menu with a search box inside it. The <select> stays the source of
     * truth (value, name, form posts, "change" events), so page scripts
     * keep reading select.value and listening to "change" as before.
     *   HRMS.searchable(select)            enhance one select (done for every
     *                                      [data-searchable] on page load)
     *   HRMS.filterOptions(select, keep)   show only the options keep(option)
     *                                      accepts (keep = null shows all again)
     *   select.dispatchEvent(new Event("hrms:refresh"))  re-read the options
     * ------------------------------------------------------------------ */
    var comboSeq = 0;

    HRMS.searchable = function (select) {
        if (!select || select.hrmsCombo) { return select && select.hrmsCombo; }
        var id = "hrms-combo-" + (++comboSeq);
        var wrap = document.createElement("div");
        wrap.className = "hrms-combo";
        if (select.hidden) { wrap.hidden = true; }   // a select hidden on purpose (e.g. only one company) stays hidden
        select.parentNode.insertBefore(wrap, select);
        wrap.appendChild(select);
        select.classList.add("hrms-combo__native");
        select.setAttribute("tabindex", "-1");
        select.setAttribute("aria-hidden", "true");

        var button = document.createElement("button");
        button.type = "button";
        button.className = "form-select hrms-combo__toggle";
        button.setAttribute("aria-haspopup", "listbox");
        button.setAttribute("aria-expanded", "false");
        button.setAttribute("aria-controls", id + "-list");
        // the <label for> of the select now names the button
        if (select.id) {
            var label = document.querySelector('label[for="' + select.id + '"]');
            if (label) {
                if (!label.id) { label.id = select.id + "-label"; }
                button.setAttribute("aria-labelledby", label.id + " " + id + "-value");
                label.addEventListener("click", function (e) { e.preventDefault(); button.focus(); });
            }
        } else if (select.getAttribute("aria-label")) {
            button.setAttribute("aria-label", select.getAttribute("aria-label"));
        }
        var valueSpan = document.createElement("span");
        valueSpan.className = "hrms-combo__value";
        valueSpan.id = id + "-value";
        button.appendChild(valueSpan);
        wrap.appendChild(button);

        var menu = document.createElement("div");
        menu.className = "hrms-combo__menu";
        menu.hidden = true;
        var search = document.createElement("input");
        search.type = "search";
        search.className = "form-control form-control-sm hrms-combo__search";
        search.setAttribute("autocomplete", "off");
        search.placeholder = HRMS.t("js.combo_search", "Search…");
        search.setAttribute("aria-label", search.placeholder);
        search.setAttribute("aria-controls", id + "-list");
        var list = document.createElement("ul");
        list.className = "hrms-combo__list";
        list.id = id + "-list";
        list.setAttribute("role", "listbox");
        var empty = document.createElement("div");
        empty.className = "hrms-combo__empty";
        empty.textContent = HRMS.t("js.combo_no_match", "No match");
        empty.hidden = true;
        menu.appendChild(search);
        menu.appendChild(list);
        menu.appendChild(empty);
        wrap.appendChild(menu);

        var active = -1;
        function items() { return Array.prototype.slice.call(list.querySelectorAll(".hrms-combo__item:not([hidden])")); }
        function norm(t) { return (t || "").toLocaleLowerCase().normalize("NFKD").replace(/[̀-ًͯ-ٟ]/g, ""); }

        function render() {
            var current = select.options[select.selectedIndex];
            valueSpan.textContent = current ? current.textContent.trim() : "";
            button.disabled = select.disabled;
            list.innerHTML = "";
            Array.prototype.forEach.call(select.options, function (o, i) {
                var li = document.createElement("li");
                li.className = "hrms-combo__item";
                li.id = id + "-opt-" + i;
                li.setAttribute("role", "option");
                li.setAttribute("data-index", String(i));
                li.setAttribute("aria-selected", o.selected ? "true" : "false");
                if (o.disabled) { li.setAttribute("aria-disabled", "true"); }
                li.textContent = o.textContent.trim();
                list.appendChild(li);
            });
        }

        function filter() {
            var q = norm(search.value.trim());
            var shown = 0;
            Array.prototype.forEach.call(list.children, function (li) {
                var hit = !q || norm(li.textContent).indexOf(q) >= 0;
                li.hidden = !hit;
                if (hit) { shown++; }
            });
            empty.hidden = shown > 0;
            setActive(items().findIndex(function (li) { return li.getAttribute("aria-selected") === "true"; }));
            if (active < 0) { setActive(0); }
        }

        function setActive(i) {
            var all = items();
            all.forEach(function (li) { li.classList.remove("is-active"); });
            active = all.length ? Math.max(0, Math.min(i, all.length - 1)) : -1;
            if (active >= 0) {
                all[active].classList.add("is-active");
                search.setAttribute("aria-activedescendant", all[active].id);
                // keep the active option visible inside the list only (never scroll the page)
                var li = all[active];
                if (li.offsetTop < list.scrollTop) { list.scrollTop = li.offsetTop; }
                else if (li.offsetTop + li.offsetHeight > list.scrollTop + list.clientHeight) { list.scrollTop = li.offsetTop + li.offsetHeight - list.clientHeight; }
            } else {
                search.removeAttribute("aria-activedescendant");
            }
        }

        // The menu is position:fixed at the button, so a card's overflow:hidden never clips
        // it; it opens upwards when there is no room below, and follows scrolling.
        function place() {
            if (menu.hidden) { return; }
            var r = button.getBoundingClientRect();
            var width = Math.max(r.width, Math.min(280, window.innerWidth - 16));
            var rtl = window.getComputedStyle(wrap).direction === "rtl";
            var left = rtl ? r.right - width : r.left;
            left = Math.max(8, Math.min(left, window.innerWidth - width - 8));
            menu.style.width = width + "px";
            menu.style.left = left + "px";
            var below = window.innerHeight - r.bottom, h = menu.offsetHeight;
            menu.style.top = (below < h + 8 && r.top > below ? Math.max(8, r.top - h - 4) : r.bottom + 4) + "px";
        }
        window.addEventListener("resize", place);
        window.addEventListener("scroll", place, true);

        function open() {
            if (select.disabled || !menu.hidden) { return; }
            render();
            menu.hidden = false;
            place();
            wrap.classList.add("is-open");
            button.setAttribute("aria-expanded", "true");
            search.value = "";
            filter();
            search.focus({ preventScroll: true });
        }

        function close(focusButton) {
            if (menu.hidden) { return; }
            menu.hidden = true;
            wrap.classList.remove("is-open");
            button.setAttribute("aria-expanded", "false");
            if (focusButton) { button.focus(); }
        }

        function choose(li) {
            if (!li || li.getAttribute("aria-disabled") === "true") { return; }
            var index = parseInt(li.getAttribute("data-index"), 10);
            var changed = select.selectedIndex !== index;
            select.selectedIndex = index;
            render();
            close(true);
            if (changed) { select.dispatchEvent(new Event("change", { bubbles: true })); }
        }

        button.addEventListener("click", function () { if (menu.hidden) { open(); } else { close(true); } });
        button.addEventListener("keydown", function (e) {
            if (e.key === "ArrowDown" || e.key === "ArrowUp" || e.key === "Enter" || e.key === " ") { e.preventDefault(); open(); }
            else if (e.key.length === 1 && !e.ctrlKey && !e.metaKey && !e.altKey) { open(); search.value = e.key; filter(); e.preventDefault(); }
        });
        search.addEventListener("input", filter);
        search.addEventListener("keydown", function (e) {
            if (e.key === "ArrowDown") { e.preventDefault(); setActive(active + 1); }
            else if (e.key === "ArrowUp") { e.preventDefault(); setActive(active - 1); }
            else if (e.key === "Home" && !search.value) { e.preventDefault(); setActive(0); }
            else if (e.key === "End" && !search.value) { e.preventDefault(); setActive(items().length - 1); }
            else if (e.key === "Enter") { e.preventDefault(); choose(items()[active]); }
            else if (e.key === "Escape") { e.preventDefault(); close(true); }
            else if (e.key === "Tab") { close(false); }
        });
        list.addEventListener("mousedown", function (e) { e.preventDefault(); });   // keep focus in the search box
        list.addEventListener("click", function (e) { choose(e.target.closest(".hrms-combo__item")); });
        list.addEventListener("mousemove", function (e) {
            var li = e.target.closest(".hrms-combo__item");
            if (li) { setActive(items().indexOf(li)); }
        });
        document.addEventListener("mousedown", function (e) { if (!wrap.contains(e.target)) { close(false); } });
        select.addEventListener("change", render);
        select.addEventListener("hrms:refresh", render);

        render();
        select.hrmsCombo = { open: open, close: close, refresh: render };
        return select.hrmsCombo;
    };

    HRMS.filterOptions = function (select, keep) {
        if (!select) { return; }
        if (!select.hrmsAllOptions) { select.hrmsAllOptions = Array.prototype.slice.call(select.options); }
        var value = select.value;
        select.innerHTML = "";
        select.hrmsAllOptions.forEach(function (o) {
            if (!keep || keep(o)) { select.appendChild(o); }
        });
        // keep the chosen option when it is still offered, else fall back to the first one
        var still = Array.prototype.some.call(select.options, function (o) { return o.value === value; });
        select.value = still ? value : (select.options[0] ? select.options[0].value : "");
        select.dispatchEvent(new Event("hrms:refresh"));
        return still;
    };

    Array.prototype.forEach.call(document.querySelectorAll("select[data-searchable]"), HRMS.searchable);

    /** Puts "12 payrolls" in a toolbar count badge with the number in bold (text only - never HTML). */
    HRMS.setCountText = function (el, text) {
        if (!el) { return; }
        el.textContent = "";
        if (!text) { return; }
        var m = /[0-9][0-9,.]*/.exec(text);
        if (!m) { el.textContent = text; return; }
        el.appendChild(document.createTextNode(text.slice(0, m.index)));
        var strong = document.createElement("strong");
        strong.textContent = m[0];
        el.appendChild(strong);
        el.appendChild(document.createTextNode(text.slice(m.index + m[0].length)));
    };

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
