/* ==========================================================================
 * HRMS Kuwait - Workforce > Organizations (db/73)
 * The active companies in one row (scrolls sideways); the one picked opens
 * below - master / child: its document categories, and the documents of the
 * category picked as cards (filtered by status too): add / change / renew
 * (the previous version goes to History), view the scan, remove.
 * The company opens in place - it never reaches the address bar.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-od-page]");
    if (!page) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function url(name, params) {
        var base = page.getAttribute("data-urls-" + name);
        var q = Object.keys(params || {}).filter(function (k) { return params[k] !== null && params[k] !== undefined; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
        return q ? base + "?" + q : base;
    }
    function modal(id) { return bootstrap.Modal.getOrCreateInstance(document.getElementById(id)); }
    function loading() { return '<div class="pr-loading"><div class="hrms-spinner"></div></div>'; }
    function oops(error) { HRMS.toast((error && error.message) || HRMS.t("js.something_went_wrong", "Something went wrong. Please try again."), "error"); }

    var companiesSlot = $("[data-od-companies]", page);
    var panel = $("[data-od-panel]", page);
    var current = null;     // the company open below
    var filter = "";        // status: "" / expired / due / missing / valid
    var category = "";      // master: "" = every category

    /* --------------------------------------------- company strip -- */
    // the companies scroll sideways; the arrows show while there is more that way
    var scroller = $("[data-od-scroller]", page);
    function syncArrows() {
        if (!scroller || !companiesSlot) { return; }
        var max = companiesSlot.scrollWidth - companiesSlot.clientWidth;
        var x = Math.abs(companiesSlot.scrollLeft);       // RTL scrolls to negative values
        $("[data-od-scroll='-1']", scroller).hidden = x <= 2;
        $("[data-od-scroll='1']", scroller).hidden = x >= max - 2;
    }
    if (scroller && companiesSlot) {
        scroller.addEventListener("click", function (event) {
            var b = event.target.closest("[data-od-scroll]");
            if (!b) { return; }
            var dir = Number(b.getAttribute("data-od-scroll")) * (HRMS.isRtl ? -1 : 1);
            companiesSlot.scrollBy({ left: dir * companiesSlot.clientWidth * 0.8, behavior: "smooth" });
        });
        companiesSlot.addEventListener("scroll", syncArrows, { passive: true });
        window.addEventListener("resize", syncArrows);
        syncArrows();
    }

    /* ------------------------------------------------------ companies -- */

    function markCompany() {
        $all("[data-od-company]", companiesSlot).forEach(function (b) {
            var on = b.getAttribute("data-od-company") === String(current);
            b.classList.toggle("is-active", on);
            b.setAttribute("aria-pressed", on ? "true" : "false");
            if (on) { b.scrollIntoView({ behavior: "smooth", block: "nearest", inline: "nearest" }); }
        });
        syncArrows();
    }

    function openCompany(id, keepFilter) {
        current = id;
        if (!keepFilter) { filter = ""; category = ""; }
        markCompany();
        if (!panel.firstElementChild || !panel.querySelector(".pr-loading")) { panel.classList.add("is-loading"); }
        return HRMS.getHtml(url("panel", { company: id })).then(function (html) {
            panel.innerHTML = html;
            panel.classList.remove("is-loading");
            applyFilter();
        }).catch(function (error) {
            panel.classList.remove("is-loading");
            panel.innerHTML = '<div class="hrms-card"><div class="hrms-empty"><p class="hrms-empty__title"></p></div></div>';
            panel.querySelector("p").textContent = error.message;
        });
    }

    function refresh() {
        HRMS.getHtml(url("companies")).then(function (html) { companiesSlot.innerHTML = html; markCompany(); }).catch(function () { });
        if (current) { openCompany(current, true); }
    }

    if (companiesSlot) {
        companiesSlot.addEventListener("click", function (event) {
            var b = event.target.closest("[data-od-company]");
            if (!b) { return; }
            openCompany(b.getAttribute("data-od-company"));
        });
    }

    /* --------------------------------------------------------- filter -- */

    function applyFilter() {
        var shown = 0;
        var n = { "": 0, expired: 0, due: 0, missing: 0, valid: 0 };
        $all("[data-od-doc]", panel).forEach(function (d) {
            var inCat = !category || d.getAttribute("data-cat") === category;
            var st = d.getAttribute("data-status");
            if (inCat) { n[""]++; n[st] = (n[st] || 0) + 1; }
            var on = inCat && (!filter || st === filter);
            d.hidden = !on;
            if (on) { shown++; }
        });
        // the status buttons count within the category picked
        $all("[data-od-filter]", panel).forEach(function (b) {
            var key = b.getAttribute("data-od-filter");
            var on = key === filter;
            b.classList.toggle("is-active", on);
            b.setAttribute("aria-pressed", on ? "true" : "false");
            var num = $("[data-od-n]", b);
            if (num) { num.textContent = n[key] || 0; }
            b.disabled = key !== "" && !n[key] && !on;
        });
        $all("[data-od-cat]", panel).forEach(function (m) {
            var on = m.getAttribute("data-od-cat") === category;
            m.classList.toggle("is-active", on);
            m.setAttribute("aria-selected", on ? "true" : "false");
        });
        var title = $("[data-od-child-title]", panel);
        if (title) {
            var picked = category ? $('[data-od-cat="' + category + '"]', panel) : null;
            title.textContent = picked ? picked.getAttribute("data-label") : title.getAttribute("data-all");
        }
        var none = $("[data-od-nomatch]", panel);
        if (none) { none.hidden = shown > 0; }
    }

    panel && panel.addEventListener("click", function (event) {
        var cat = event.target.closest("[data-od-cat]");
        if (cat) {
            category = cat.getAttribute("data-od-cat");
            filter = "";
            applyFilter();
            return;
        }
        var f = event.target.closest("[data-od-filter]");
        if (f) {
            var value = f.getAttribute("data-od-filter");
            filter = filter === value ? "" : value;
            applyFilter();
            return;
        }
        var act = event.target.closest("[data-od-act]");
        if (!act) { return; }
        var doc = act.closest("[data-od-doc]");
        var type = doc.getAttribute("data-od-doc");
        switch (act.getAttribute("data-od-act")) {
            case "add": openForm(type, false, "add"); break;
            case "edit": openForm(type, false, "edit"); break;
            case "renew": openForm(type, true, "renew"); break;
            case "history": openHistory(type, doc.getAttribute("data-name")); break;
            case "delete": askDelete(doc.getAttribute("data-id"), doc.getAttribute("data-name")); break;
        }
    });

    /* ----------------------------------------------------------- form -- */

    var form = $("[data-od-form]");
    var formBody = $("[data-od-form-body]", form);
    var formError = $("[data-od-form-error]", form);

    function openForm(type, renew, mode) {
        $("[data-od-form-title]", form).textContent = page.getAttribute("data-text-" + mode) || "";
        formError.textContent = "";
        formBody.innerHTML = loading();
        modal("od-form-modal").show();
        HRMS.getHtml(url("form", { company: current, type: type, renew: renew ? "true" : null })).then(function (html) {
            formBody.innerHTML = html;
            var issue = $("[data-od-issue]", formBody), expiry = $("[data-od-expiry]", formBody);
            if (issue && expiry) {
                issue.addEventListener("change", function () {
                    if (issue.value && (!expiry.min || expiry.min < issue.value)) { expiry.min = issue.value; }
                });
            }
            var first = $("input:not([type=hidden]), textarea", formBody);
            if (first) { window.setTimeout(function () { first.focus(); }, 250); }
        }).catch(function (error) { formBody.textContent = error.message; });
    }

    form.addEventListener("submit", function (event) {
        event.preventDefault();
        formError.textContent = "";
        $all("[data-valmsg-for]", formBody).forEach(function (e) { e.textContent = ""; });
        var missing = $all("[required]", formBody).filter(function (f) { return !f.value; });
        if (missing.length) {
            missing[0].focus();
            formError.textContent = HRMS.t("js.od_fill_required", "Fill in the fields marked *.");
            return;
        }
        var file = $("[data-od-file]", formBody);
        if (file && file.files && file.files[0]) {
            var ext = (file.files[0].name.split(".").pop() || "").toLowerCase();
            if (["pdf", "jpg", "jpeg", "png"].indexOf(ext) === -1) {
                formError.textContent = HRMS.t("js.only_pdf_jpg_png", "Only PDF, JPG or PNG files can be uploaded.");
                return;
            }
        }
        var save = $("[data-od-save]", form);
        save.disabled = true;
        HRMS.post(url("save"), new FormData(form)).then(function (res) {
            if (res && res.success) {
                HRMS.toast(res.message, "success");
                modal("od-form-modal").hide();
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

    /* -------------------------------------------------------- history -- */

    function openHistory(type, name) {
        var body = $("[data-od-history-body]");
        $("[data-od-history-title]").textContent = (page.getAttribute("data-text-history") || "{0}").replace("{0}", name || "");
        body.innerHTML = loading();
        modal("od-history-modal").show();
        HRMS.getHtml(url("history", { company: current, type: type }))
            .then(function (html) { body.innerHTML = html; })
            .catch(function (error) { body.textContent = error.message; });
    }

    /* --------------------------------------------------------- remove -- */

    var removing = null;
    function askDelete(id, name) {
        removing = id;
        $("[data-od-confirm-name]").textContent = name || "";
        modal("od-confirm-modal").show();
    }
    $("[data-od-confirm-accept]").addEventListener("click", function () {
        if (!removing) { return; }
        var button = this;
        var body = new FormData();
        body.append("id", removing);
        button.disabled = true;
        HRMS.post(url("delete"), body).then(function (res) {
            HRMS.toast(res.message, res.success ? "success" : "error");
            if (res.success) { modal("od-confirm-modal").hide(); refresh(); }
        }).catch(oops).then(function () { button.disabled = false; removing = null; });
    });

    /* --------------------------------------------------------- viewer -- */

    // a scan from the list or from History (History steps aside and comes back)
    var viewer = document.getElementById("od-viewer-modal");
    var returnTo = null;
    function openViewer(link) {
        var src = link.getAttribute("data-od-view");
        var type = (link.getAttribute("data-type") || "").toLowerCase();
        var name = link.getAttribute("data-file") || "";
        var body = $("[data-od-viewer-body]", viewer);
        $("[data-od-viewer-title]", viewer).textContent = link.getAttribute("data-title") || name;
        $("[data-od-viewer-file]", viewer).textContent = name;
        $("[data-od-viewer-download]", viewer).href = src + (src.indexOf("?") === -1 ? "?" : "&") + "download=true";
        body.innerHTML = "";
        if (type.indexOf("image/") === 0) {
            var img = document.createElement("img");
            img.className = "doc-viewer__img";
            img.src = src;
            img.alt = name;
            img.addEventListener("click", function () { img.classList.toggle("is-actual"); });
            body.appendChild(img);
        } else {
            var frame = document.createElement("iframe");
            frame.className = "doc-viewer__frame";
            frame.src = src;
            frame.title = name;
            body.appendChild(frame);
        }
        modal("od-viewer-modal").show();
    }
    document.addEventListener("click", function (event) {
        var link = event.target.closest("[data-od-view]");
        if (!link) { return; }
        event.preventDefault();
        var parent = link.closest(".modal.show");
        if (parent && parent !== viewer) {
            returnTo = parent;
            parent.addEventListener("hidden.bs.modal", function () { openViewer(link); }, { once: true });
            modal(parent.id).hide();
            return;
        }
        openViewer(link);
    });
    viewer.addEventListener("hidden.bs.modal", function () {
        $("[data-od-viewer-body]", viewer).innerHTML = "";
        if (returnTo) { modal(returnTo.id).show(); returnTo = null; }
    });

    /* ---------------------------------------------------------- start -- */

    // the company named by the address (a Dashboard alert), else the first one
    var start = page.getAttribute("data-selected");
    if (!start || !$('[data-od-company="' + start + '"]', companiesSlot)) {
        var firstCard = companiesSlot && $("[data-od-company]", companiesSlot);
        start = firstCard ? firstCard.getAttribute("data-od-company") : null;
    }
    if (start && panel) { openCompany(start); }
})();
