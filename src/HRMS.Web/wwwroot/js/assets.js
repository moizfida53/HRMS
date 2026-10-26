/* ==========================================================================
 * HRMS Kuwait - Workforce > Assets (db/84)
 * Company cars, motor bikes, phones ...: the figures and type chips filter
 * the list; add / change / assign an asset in a popup, take it back
 * (Return), see who held it (History), delete it (confirmed). Nothing here
 * puts a record id in the address bar.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-as-page]");
    if (!page) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function url(name, params) {
        var base = page.getAttribute("data-urls-" + name);
        var q = Object.keys(params || {}).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
        return q ? base + "?" + q : base;
    }
    function modal(id) { return bootstrap.Modal.getOrCreateInstance(document.getElementById(id)); }
    function loading() { return '<div class="pr-loading"><div class="hrms-spinner"></div></div>'; }
    function oops(error) { HRMS.toast((error && error.message) || HRMS.t("js.something_went_wrong", "Something went wrong. Please try again."), "error"); }
    function body(fields) { var f = new FormData(); Object.keys(fields).forEach(function (k) { f.append(k, fields[k]); }); return f; }

    var summarySlot = $("[data-as-summary]", page);
    var grid = $("[data-as-grid]", page);
    var count = $("[data-as-count]", page);
    var search = $("[data-as-search]", page);
    var state = { type: page.getAttribute("data-type") || "", status: page.getAttribute("data-status") || "", q: "", page: 1 };

    /* ------------------------------------------------------ list ----- */

    function loadGrid() {
        grid.setAttribute("aria-busy", "true");
        return HRMS.getHtml(url("grid", { type: state.type, status: state.status, q: state.q, page: state.page })).then(function (html) {
            grid.innerHTML = html;
            grid.removeAttribute("aria-busy");
            var total = $("[data-as-total]", grid);
            var n = total ? parseInt(total.getAttribute("data-as-total"), 10) || 0 : 0;
            count.textContent = n === 1 ? HRMS.t("js.as_one_asset", "1 asset") : HRMS.t("js.as_n_assets", "{0} assets", n);
        }).catch(function (error) { grid.removeAttribute("aria-busy"); grid.textContent = error.message; });
    }

    function loadSummary() {
        return HRMS.getHtml(url("summary", { type: state.type, status: state.status })).then(function (html) { summarySlot.innerHTML = html; }).catch(function () { });
    }

    function refresh() { loadSummary(); return loadGrid(); }

    // the figures (status) and the type chips filter the list; a second click clears
    summarySlot.addEventListener("click", function (event) {
        var st = event.target.closest("[data-as-status]");
        var ty = event.target.closest("[data-as-type]");
        if (st) {
            var s = st.getAttribute("data-as-status");
            state.status = state.status === s ? "" : s;
        } else if (ty) {
            state.type = ty.getAttribute("data-as-type");
        } else {
            return;
        }
        state.page = 1;
        refresh();
    });

    search.addEventListener("input", HRMS.debounce(function () {
        state.q = search.value.trim();
        state.page = 1;
        loadGrid();
    }, 300));

    grid.addEventListener("click", function (event) {
        var pg = event.target.closest("[data-as-goto]");
        if (pg && !pg.disabled) { state.page = parseInt(pg.getAttribute("data-as-goto"), 10) || 1; loadGrid(); return; }
        var act = event.target.closest("[data-as-act]");
        if (!act) { return; }
        var row = act.closest("[data-as-row]");
        var id = row.getAttribute("data-as-row");
        switch (act.getAttribute("data-as-act")) {
            case "edit": openForm(id, "edit"); break;
            case "assign": openForm(id, "assign"); break;
            case "return": askReturn(id, row.getAttribute("data-name"), row.getAttribute("data-holder")); break;
            case "history": openHistory(id, row.getAttribute("data-name")); break;
            case "delete": askDelete(id, row.getAttribute("data-name")); break;
        }
    });

    document.addEventListener("click", function (event) {
        if (event.target.closest("[data-as-add]")) { openForm(0, "add"); }
    });

    /* ------------------------------------------------------ form ----- */

    var form = $("[data-as-form]");
    var formBody = $("[data-as-form-body]", form);
    var formError = $("[data-as-form-error]", form);

    function wireForm(mode) {
        // the expiry date follows the type: its name, or hidden for a type without one
        var syncType = function () {
            var t = $('input[name="AssetTypeId"]:checked', formBody);
            var box = $("[data-as-expiry-box]", formBody);
            var has = !t || t.getAttribute("data-has-expiry") === "1";
            box.hidden = !has;
            if (!has) { $("[data-as-expiry]", formBody).value = ""; }
            var label = t && t.getAttribute("data-expiry-label");
            $("[data-as-expiry-label]", formBody).textContent = label || HRMS.t("js.as_expiry_date", "Expiry date");
        };
        $all('input[name="AssetTypeId"]', formBody).forEach(function (r) { r.addEventListener("change", syncType); });
        syncType();

        // employees of the asset's company only
        var company = $("[data-as-company]", formBody);
        var employee = $("[data-as-employee]", formBody);
        if (HRMS.searchable) { $all("select[data-searchable]", formBody).forEach(function (s) { HRMS.searchable(s); }); }
        var syncCompany = function () {
            var co = company ? company.value : "";
            HRMS.filterOptions(employee, function (o) {
                var of = o.getAttribute("data-company");
                return !o.value || !co || !of || of === co;
            });
        };
        if (company && company.tagName === "SELECT") { company.addEventListener("change", syncCompany); }
        syncCompany();

        // a change of holder asks for a handover remark (kept in the history)
        var original = $("[data-as-original]", formBody);
        var remarks = $("[data-as-remarks]", formBody);
        var since = formBody.querySelector('[name="AssignedDate"]');
        employee.addEventListener("change", function () {
            var changed = original ? employee.value !== original.getAttribute("data-as-original") : !!employee.value;
            remarks.hidden = !changed || !original;
            if (employee.value && !since.value) { since.value = new Date().toISOString().slice(0, 10); }
        });

        // expiry not before purchase
        var purchase = $("[data-as-purchase]", formBody), expiry = $("[data-as-expiry]", formBody);
        purchase.addEventListener("change", function () { expiry.min = purchase.value || ""; });
        expiry.min = purchase.value || "";

        var focus = mode === "assign" ? employee : $('input[name="AssetTypeId"]:checked', formBody) ? $("#as-brand", formBody) : $('input[name="AssetTypeId"]', formBody);
        if (mode === "assign") {
            var section = $("[data-as-assign]", formBody);
            section.classList.add("is-highlight");
            window.setTimeout(function () { section.scrollIntoView({ block: "center", behavior: "smooth" }); }, 250);
        }
        if (mode === "assign" && employee.hrmsCombo) { window.setTimeout(function () { employee.hrmsCombo.open(); }, 450); }
        else if (focus && mode !== "assign") { window.setTimeout(function () { focus.focus(); }, 300); }
    }

    function openForm(id, mode) {
        $("[data-as-form-title]", form).textContent = page.getAttribute("data-text-" + mode) || "";
        formError.textContent = "";
        formBody.innerHTML = loading();
        modal("as-form-modal").show();
        HRMS.getHtml(url("form", { id: id || null, type: !id && state.type ? state.type : null })).then(function (html) {
            formBody.innerHTML = html;
            wireForm(mode);
        }).catch(function (error) { formBody.textContent = error.message; });
    }

    form.addEventListener("submit", function (event) {
        event.preventDefault();
        formError.textContent = "";
        $all("[data-valmsg-for]", formBody).forEach(function (e) { e.textContent = ""; });
        if (!$('input[name="AssetTypeId"]:checked', formBody)) {
            formError.textContent = HRMS.t("js.as_choose_type", "Choose the asset type.");
            return;
        }
        var brand = formBody.querySelector('[name="Brand"]'), model = formBody.querySelector('[name="Model"]');
        if (!brand.value.trim() && !model.value.trim()) {
            brand.focus();
            formError.textContent = HRMS.t("js.as_brand_or_model", "Enter the brand or the model.");
            return;
        }
        var save = $("[data-as-save]", form);
        save.disabled = true;
        HRMS.post(url("save"), new FormData(form)).then(function (res) {
            if (res && res.success) {
                HRMS.toast(res.message, "success");
                modal("as-form-modal").hide();
                refresh();
                return;
            }
            var msg = (res && res.message) || "";
            if (res && res.errors) {
                Object.keys(res.errors).forEach(function (k) {
                    var slot = $('[data-valmsg-for="' + k + '"]', formBody);
                    if (slot) { slot.textContent = res.errors[k][0]; }
                    msg = msg || res.errors[k][0];
                });
            }
            formError.textContent = msg;
        }).catch(oops).then(function () { save.disabled = false; });
    });

    /* ------------------------------------------- return / delete ----- */

    function askReturn(id, name, holder) {
        HRMS.confirm({
            title: HRMS.t("js.as_return_title", "Take this asset back?"),
            text: holder ? HRMS.t("js.as_return_text", "{0} no longer uses it - it becomes available again.", holder) : "",
            name: name, tone: "primary", note: "", ok: HRMS.t("js.as_return", "Return")
        }).then(function (ok) {
            if (!ok) { return; }
            HRMS.post(url("return"), body({ id: id })).then(function (res) {
                HRMS.toast(res.message, res.success ? "success" : "error");
                if (res.success) { refresh(); }
            }).catch(oops);
        });
    }

    function askDelete(id, name) {
        HRMS.confirm({ title: HRMS.t("js.as_delete_title", "Delete this asset?"), name: name }).then(function (ok) {
            if (!ok) { return; }
            HRMS.post(url("delete"), body({ id: id })).then(function (res) {
                HRMS.toast(res.message, res.success ? "success" : "error");
                if (res.success) { refresh(); }
            }).catch(oops);
        });
    }

    /* --------------------------------------------------- history ----- */

    function openHistory(id, name) {
        var slot = $("[data-as-history-body]");
        $("[data-as-history-title]").textContent = (page.getAttribute("data-text-history") || "{0}").replace("{0}", name || "");
        slot.innerHTML = loading();
        modal("as-history-modal").show();
        HRMS.getHtml(url("history", { id: id })).then(function (html) { slot.innerHTML = html; }).catch(function (error) { slot.textContent = error.message; });
    }

    loadGrid();
})();
