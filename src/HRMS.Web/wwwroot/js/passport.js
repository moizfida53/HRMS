/* ==========================================================================
 * HRMS Kuwait - Workforce > Employees > Actions > Passport In / Out (db/93)
 * Where the passport is (company / employee), the next hand-over, and the
 * log of every hand-over (View Transactions, Export to Excel).
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var modalEl = document.getElementById("pp-modal");
    if (!modalEl) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function url(name, params) {
        var q = Object.keys(params || {}).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
        return modalEl.getAttribute("data-urls-" + name) + (q ? "?" + q : "");
    }
    function loading() { return '<div class="pr-loading"><div class="hrms-spinner"></div></div>'; }
    function busy(button, on) { button.disabled = on; button.classList.toggle("is-busy", on); }

    var body = $("[data-pp-body]", modalEl);
    var submit = $("[data-pp-submit]", modalEl);
    var toggle = $("[data-pp-toggle-log]", modalEl);
    var toggleText = $("[data-pp-toggle-text]", modalEl);
    var employeeId = null;
    var logOpen = false;

    function syncToggle() {
        toggleText.textContent = modalEl.getAttribute(logOpen ? "data-text-hide-log" : "data-text-show-log");
        toggle.setAttribute("aria-expanded", logOpen ? "true" : "false");
    }

    function loadLog() {
        var slot = $("[data-pp-log-body]", body);
        if (!slot) { return; }
        slot.innerHTML = loading();
        HRMS.getHtml(url("log", { id: employeeId })).then(function (html) { slot.innerHTML = html; })
            .catch(function (error) { slot.textContent = error.message; });
    }

    function showLog(on) {
        logOpen = on;
        var section = $("[data-pp-log]", body);
        if (section) {
            section.hidden = !on;
            if (on) { loadLog(); window.setTimeout(function () { section.scrollIntoView({ block: "nearest", behavior: "smooth" }); }, 200); }
        }
        syncToggle();
    }

    function loadPanel() {
        body.innerHTML = loading();
        submit.hidden = true;
        return HRMS.getHtml(url("panel", { id: employeeId })).then(function (html) {
            body.innerHTML = html;
            submit.hidden = !$("[data-pp-form]", body);
            if (logOpen) { showLog(true); }
            var first = $("[data-pp-form] select, [data-pp-form] input[type=date]", body);
            if (first) { window.setTimeout(function () { first.focus(); }, 300); }
        }).catch(function (error) { body.textContent = error.message; });
    }

    // Actions menu > Passport In / Out
    document.addEventListener("click", function (event) {
        var open = event.target.closest("[data-passport-open]");
        if (!open) { return; }
        event.preventDefault();
        employeeId = open.getAttribute("data-passport-open");
        logOpen = false;
        syncToggle();
        bootstrap.Modal.getOrCreateInstance(modalEl).show();
        loadPanel();
    });

    toggle.addEventListener("click", function () { showLog(!logOpen); });

    body.addEventListener("click", function (event) {
        if (event.target.closest("[data-pp-export]")) {
            window.location.href = url("export", { id: employeeId });
        }
    });

    function send() {
        var form = $("[data-pp-form]", body);
        if (!form) { return; }
        var error = $("[data-pp-error]", form);
        error.textContent = "";
        var held = form.elements.heldBy, date = form.elements.date;
        if (!held.value) { error.textContent = HRMS.t("js.pp_choose_holder", "Choose who has the passport."); held.focus(); return; }
        if (!date.value) { error.textContent = HRMS.t("js.pp_enter_date", "Enter the date."); date.focus(); return; }
        busy(submit, true);
        HRMS.post(url("save"), new FormData(form)).then(function (res) {
            busy(submit, false);
            if (res && res.success) {
                HRMS.toast(res.message, "success");
                loadPanel();
                return;
            }
            error.textContent = (res && res.message) || HRMS.t("js.something_went_wrong", "Something went wrong. Please try again.");
        }).catch(function (e) { busy(submit, false); error.textContent = e.message; });
    }
    submit.addEventListener("click", send);
    body.addEventListener("submit", function (event) {
        if (event.target.closest("[data-pp-form]")) { event.preventDefault(); send(); }
    });
})();
