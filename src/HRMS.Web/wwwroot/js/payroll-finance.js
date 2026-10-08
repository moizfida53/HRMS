/* ==========================================================================
 * HRMS Kuwait - Bank Processing, Accounting and Payroll Reports
 * The pages are rendered by the server; this script only:
 *
 *   form[data-fin-filters]   the Year / Month filter row: the month list follows
 *                            the year, any change sends the form (a new period
 *                            drops the payroll picked and the page)
 *   [data-fin-action="url"]  an action button: opens #fin-dialog (title / text,
 *                            optional text field data-fin-field + label, optional
 *                            date data-fin-date), then posts
 *                              ids        data-fin-ids, or the ticked rows
 *                                         (data-fin-selected)
 *                              data-fin-extra='{"status":"PAID"}'  more fields
 *                            and reloads the page with the result message
 *   form[data-fin-form]      posts the form; data-fin-download opens the new
 *                            file (bank file) before reloading
 *   [data-fin-check]         row tick boxes + [data-fin-check-all] + the bulk bar
 *   [data-fin-pager]         the pagination buttons change ?page=
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-fin-page]");
    if (!page) { return; }

    var TOAST_KEY = "hrms:fin-toast";
    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function failed() { return HRMS.t("js.fin_failed", "The request could not be completed."); }
    function busy(el, on) { if (el) { el.disabled = !!on; el.classList.toggle("is-busy", !!on); } }

    /* a message to show after the reload */
    try {
        var pending = window.sessionStorage.getItem(TOAST_KEY);
        if (pending) {
            window.sessionStorage.removeItem(TOAST_KEY);
            HRMS.toast(pending, "success");
        }
    } catch (e) { /* storage off */ }

    function reloadWith(message) {
        try { if (message) { window.sessionStorage.setItem(TOAST_KEY, message); } } catch (e) { /* storage off */ }
        window.location.reload();
    }

    function send(url, data, button) {
        var body = new FormData();
        Object.keys(data).forEach(function (k) {
            var v = data[k];
            if (Array.isArray(v)) { v.forEach(function (x) { body.append(k, x); }); }
            else if (v !== null && v !== undefined && v !== "") { body.append(k, v); }
        });
        busy(button, true);
        return HRMS.post(url, body).then(function (res) {
            busy(button, false);
            if (!res || !res.success) { HRMS.toast((res && res.message) || failed(), "error"); return null; }
            return res;
        }, function (error) {
            busy(button, false);
            HRMS.toast((error && error.message) || failed(), "error");
            return null;
        });
    }

    /* ------------------------------------------------------- filter row */
    $all("form[data-fin-filters]", page).forEach(function (form) {
        var year = $("[data-fin-year]", form);
        var month = $("[data-fin-month]", form);

        function syncMonths() {
            if (!year || !month) { return; }
            var y = year.value;
            HRMS.filterOptions(month, function (o) { return !o.value || !y || o.getAttribute("data-year") === y; });
        }
        function submit(resetPicks) {
            if (resetPicks) {
                $all('select[name="run"], input[name="run"], input[name="file"]', form).forEach(function (el) { el.disabled = true; });
            }
            form.submit();
        }

        syncMonths();
        if (year) { year.addEventListener("change", function () { syncMonths(); submit(true); }); }
        if (month) { month.addEventListener("change", function () { submit(true); }); }
        $all("[data-fin-auto]", form).forEach(function (s) { s.addEventListener("change", function () { submit(false); }); });
        var search = $("[data-fin-search]", form);
        if (search) { search.addEventListener("change", function () { submit(false); }); }
    });

    /* ------------------------------------------------------- pagination */
    $all("[data-fin-pager]", page).forEach(function (pager) {
        pager.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (!b || b.disabled) { return; }
            var url = new URL(window.location.href);
            url.searchParams.set("page", b.getAttribute("data-page"));
            window.location.href = url.toString();
        });
    });

    /* ------------------------------------------------------- selection */
    var scope = $("[data-fin-select-scope]", page) || page;
    var bulk = $("[data-fin-bulk]", scope);
    function ticked() { return $all("[data-fin-check]:checked", scope).map(function (c) { return c.value; }); }
    function syncBulk() {
        if (!bulk) { return; }
        var n = ticked().length;
        bulk.hidden = n === 0;
        var count = $("[data-fin-bulk-count]", bulk);
        if (count) { count.textContent = HRMS.t("js.fin_selected", "{0} selected", n); }
        var all = $("[data-fin-check-all]", scope);
        if (all) {
            var boxes = $all("[data-fin-check]", scope);
            all.checked = boxes.length > 0 && n === boxes.length;
            all.indeterminate = n > 0 && n < boxes.length;
        }
    }
    scope.addEventListener("change", function (ev) {
        if (ev.target.matches("[data-fin-check-all]")) {
            $all("[data-fin-check]", scope).forEach(function (c) { c.checked = ev.target.checked; });
        }
        if (ev.target.matches("[data-fin-check], [data-fin-check-all]")) { syncBulk(); }
    });
    syncBulk();

    /* ------------------------------------------------------- the dialog */
    var dialog = $("#fin-dialog");
    var current = null;

    function openDialog(button) {
        current = button;
        if (!dialog || !window.bootstrap) { return; }
        $("[data-fin-dialog-title]", dialog).textContent = button.getAttribute("data-fin-title") || "";
        $("[data-fin-dialog-text]", dialog).textContent = button.getAttribute("data-fin-text") || "";
        $("[data-fin-dialog-ok]", dialog).textContent = button.getAttribute("data-fin-ok") || button.getAttribute("data-fin-title") || "OK";

        var field = button.getAttribute("data-fin-field");
        var fieldBox = $("[data-fin-dialog-field]", dialog);
        fieldBox.hidden = !field;
        $("[data-fin-dialog-label]", dialog).textContent = button.getAttribute("data-fin-label") || "";
        $("[data-fin-dialog-input]", dialog).value = "";
        $("[data-fin-dialog-error]", dialog).textContent = "";

        var dateName = button.getAttribute("data-fin-date");
        $("[data-fin-dialog-date]", dialog).hidden = !dateName;
        $("[data-fin-dialog-date-input]", dialog).value = button.getAttribute("data-fin-date-value") || "";

        window.bootstrap.Modal.getOrCreateInstance(dialog).show();
        window.setTimeout(function () {
            var focus = field ? $("[data-fin-dialog-input]", dialog) : $("[data-fin-dialog-ok]", dialog);
            if (focus) { focus.focus(); }
        }, 250);
    }

    if (dialog) {
        $("[data-fin-dialog-form]", dialog).addEventListener("submit", function (ev) {
            ev.preventDefault();
            if (!current) { return; }
            var b = current;
            var data = {};
            try { data = JSON.parse(b.getAttribute("data-fin-extra") || "{}"); } catch (e) { data = {}; }

            var ids = b.hasAttribute("data-fin-selected") ? ticked() : (b.getAttribute("data-fin-ids") || "").split(",").filter(Boolean);
            if (ids.length) { data.ids = ids; }

            var field = b.getAttribute("data-fin-field");
            if (field) {
                var value = $("[data-fin-dialog-input]", dialog).value.trim();
                if (!value && !b.hasAttribute("data-fin-optional")) {
                    $("[data-fin-dialog-error]", dialog).textContent = HRMS.t("js.fin_required", "This is required.");
                    $("[data-fin-dialog-input]", dialog).focus();
                    return;
                }
                data[field] = value;
            }
            var dateName = b.getAttribute("data-fin-date");
            if (dateName) { data[dateName] = $("[data-fin-dialog-date-input]", dialog).value; }

            var ok = $("[data-fin-dialog-ok]", dialog);
            send(b.getAttribute("data-fin-action"), data, ok).then(function (res) {
                if (!res) { return; }
                window.bootstrap.Modal.getOrCreateInstance(dialog).hide();
                reloadWith(res.message);
            });
        });
    }

    page.addEventListener("click", function (ev) {
        var b = ev.target.closest("[data-fin-action]");
        if (!b || b.disabled) { return; }
        ev.preventDefault();
        if (b.hasAttribute("data-fin-selected") && ticked().length === 0) { return; }
        openDialog(b);
    });

    /* ------------------------------------------------------- forms */
    $all("form[data-fin-form], form[data-fin-generate]", page).forEach(function (form) {
        form.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var button = form.querySelector('button[type="submit"]');
            var data = {};
            new FormData(form).forEach(function (v, k) { data[k] = v; });
            send(form.getAttribute("action"), data, button).then(function (res) {
                if (!res) { return; }
                var download = page.getAttribute("data-fin-download");
                if (form.hasAttribute("data-fin-generate") && download && res.id) {
                    // the browser downloads the new file, then the page shows it in the list
                    var a = document.createElement("a");
                    a.href = download.replace("__id__", String(res.id));
                    a.setAttribute("download", "");
                    document.body.appendChild(a);
                    a.click();
                    a.remove();
                    try { window.sessionStorage.setItem(TOAST_KEY, res.message || ""); } catch (e) { /* storage off */ }
                    window.setTimeout(function () { window.location.reload(); }, 900);
                    return;
                }
                reloadWith(res.message);
            });
        });
    });
})();
