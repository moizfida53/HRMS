/* =====================================================================
   attendance.js - Time & Attendance (db/126)
     register   the days: filters, list, edit / add a day, work the month out again
     import     the device report: preview (columns, employees, sample), remap, link, import
     summary    post the month to the payroll / take it back
     employees  device IDs (saved as typed) and patterns (to the employees ticked)
   ===================================================================== */
(function () {
    "use strict";

    var page = document.querySelector("[data-att-page]");
    if (!page) { return; }
    var mode = page.getAttribute("data-att-page");

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function url(name) { return page.getAttribute("data-url-" + name); }
    function esc(s) { return HRMS.escape(s == null ? "" : String(s)); }
    function qs(base, params) {
        var parts = Object.keys(params).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); });
        return parts.length ? base + (base.indexOf("?") >= 0 ? "&" : "?") + parts.join("&") : base;
    }
    function busy(b, on) { if (b) { b.disabled = on; b.classList.toggle("is-busy", on); } }
    function failed() { return HRMS.t("js.att_failed", "The request could not be completed."); }
    function modal(el) { return window.bootstrap.Modal.getOrCreateInstance(el); }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments; clearTimeout(t); t = setTimeout(function () { fn.apply(null, a); }, wait); };
    };
    var FLASH = "hrms:att-flash";
    (function showFlash() {
        try { var m = sessionStorage.getItem(FLASH); if (m) { sessionStorage.removeItem(FLASH); HRMS.toast(m, "success"); } } catch (e) { /* private */ }
    })();
    function reloadWith(message) {
        try { if (message) { sessionStorage.setItem(FLASH, message); } } catch (e) { /* private */ }
        HRMS.reload();
    }
    /** POST a form / object; resolves with the answer (a failure is toasted). */
    function post(u, body, button) {
        var fd = body instanceof FormData ? body : (function () {
            var f = new FormData(); Object.keys(body || {}).forEach(function (k) { if (body[k] !== null && body[k] !== undefined) { f.append(k, body[k]); } }); return f;
        })();
        busy(button, true);
        return HRMS.post(u, fd).then(function (res) {
            busy(button, false);
            if (!res || !res.success) { HRMS.toast((res && res.message) || failed(), "error"); }
            return res;
        }, function (err) { busy(button, false); HRMS.toast((err && err.message) || failed(), "error"); return null; });
    }
    function postJson(u, data, button) {
        busy(button, true);
        return fetch(u, {
            method: "POST", credentials: "same-origin",
            headers: { "Content-Type": "application/json", "RequestVerificationToken": HRMS.antiForgeryToken() },
            body: JSON.stringify(data)
        }).then(function (r) {
            if (!r.ok) { throw new Error(HRMS.t("js.server_rejected", "The server rejected the request ({0}).", r.status)); }
            return r.json();
        }).then(function (res) {
            busy(button, false);
            if (!res || !res.success) { HRMS.toast((res && res.message) || failed(), "error"); }
            return res;
        }, function (err) { busy(button, false); HRMS.toast((err && err.message) || failed(), "error"); return null; });
    }

    /* ------------------------------------------------ a list with filters */
    function wireList(opts) {
        var list = $("[data-att-list]", page);
        var slot = $("[data-att-slot]", page);
        var form = $("[data-att-filters]", page);
        var count = $("[data-att-count]", page);
        var state = { page: 1 };
        function filters() {
            var out = {};
            $all("[name]", form).forEach(function (el) { out[el.name] = el.value; });
            out.page = state.page;
            return out;
        }
        function load() {
            slot.setAttribute("aria-busy", "true");
            return HRMS.getHtml(qs(opts.gridUrl, filters())).then(function (html) {
                slot.innerHTML = html;
                slot.removeAttribute("aria-busy");
                var holder = $("[data-count-text]", slot);
                if (count) { HRMS.setCountText(count, holder ? holder.getAttribute("data-count-text") : ""); }
                if (opts.onLoad) { opts.onLoad(slot); }
            }, function () {
                slot.removeAttribute("aria-busy");
                slot.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' + esc(failed()) + "</p></div>";
            });
        }
        // a filter that changes the figures (company, month) reloads the page; the others only the list
        $all("[data-att-filter]", form).forEach(function (el) {
            el.addEventListener("change", function () {
                if (opts.reloadOn && opts.reloadOn.indexOf(el.name) >= 0) {
                    HRMS.go(qs(form.getAttribute("action") || window.location.pathname, filters()).replace(/[?&]page=\d+/, ""));
                    return;
                }
                state.page = 1; load();
            });
        });
        var search = $("[data-att-search]", form);
        if (search) { search.addEventListener("input", debounce(function () { state.page = 1; load(); }, 350)); }
        form.addEventListener("submit", function (ev) { ev.preventDefault(); state.page = 1; load(); });
        list.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (b && !b.disabled && slot.contains(b)) { state.page = parseInt(b.getAttribute("data-page"), 10) || 1; load(); }
        });
        load();
        return { load: load };
    }

    /* ====================================================== Attendance */
    if (mode === "register") {
        var grid = wireList({ gridUrl: url("grid"), reloadOn: ["company", "month"] });
        var dayModal = $("#att-day-modal"), dayBody = $("[data-att-day-body]", dayModal), dayForm = $("[data-att-day-form]", dayModal);

        function openDay(id, title) {
            $("[data-att-day-title]", dayModal).textContent = title;
            dayBody.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            modal(dayModal).show();
            HRMS.getHtml(qs(url("day"), { id: id || 0 })).then(function (html) {
                dayBody.innerHTML = html;
                $all("select[data-searchable]", dayBody).forEach(HRMS.searchable);
            }, function () { dayBody.innerHTML = ""; HRMS.toast(failed(), "error"); });
        }
        page.addEventListener("click", function (ev) {
            var e = ev.target.closest("[data-att-edit]");
            if (e) { openDay(e.getAttribute("data-att-edit"), HRMS.t("js.att_edit_day", "Change the day")); }
        });
        var addBtn = $("[data-att-add]");
        if (addBtn) { addBtn.addEventListener("click", function () { openDay(0, HRMS.t("js.att_add_day", "Add a day")); }); }
        dayForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var fd = new FormData(dayForm);
            if (!fd.get("excused")) { fd.set("excused", "false"); }
            post(url("save"), fd, $("[data-att-day-save]", dayModal)).then(function (res) {
                if (res && res.success) { modal(dayModal).hide(); HRMS.toast(res.message, "success"); grid.load(); }
            });
        });
        var recalc = $("[data-att-recalc]");
        if (recalc) {
            recalc.addEventListener("click", function () {
                post(url("recalc"), { company: recalc.getAttribute("data-company") || "", month: recalc.getAttribute("data-month") }, recalc).then(function (res) {
                    if (res && res.success) { reloadWith(res.message); }
                });
            });
        }
        return;
    }

    /* ====================================================== Attendance Sheet */
    if (mode === "sheet") {
        var sf = $("[data-att-sheet-filters]");
        var fromEl = $("[name=from]", sf), toEl = $("[name=to]", sf);
        var dirty = false;          // a From / To typed: a custom range, else the payroll period of the month
        $all("[data-att-sheet-date]", sf).forEach(function (el) { el.addEventListener("change", function () { dirty = true; }); });
        var custom = !!$(".att-range-chip.is-custom", sf);
        function submitPeriod() { fromEl.disabled = true; toEl.disabled = true; sf.submit(); }
        $("[data-att-sheet-month]", sf).addEventListener("change", submitPeriod);
        $all("[data-att-sheet-auto]", sf).forEach(function (el) {
            el.addEventListener("change", function () { if (custom || dirty) { sf.submit(); } else { submitPeriod(); } });
        });
        sf.addEventListener("submit", function () {
            if (!custom && !dirty) { fromEl.disabled = true; toEl.disabled = true; }
            else if (fromEl.value && toEl.value && fromEl.value > toEl.value) { var t = fromEl.value; fromEl.value = toEl.value; toEl.value = t; }
        });

        var pr = $("[data-att-print]");
        if (pr) { pr.addEventListener("click", function () { window.print(); }); }

        // keep the sheet's scroll across a reload (after a day is saved)
        var scroller = $("[data-att-sheet-scroll]"), SCROLL = "hrms:att-sheet-scroll";
        if (scroller) {
            try {
                var sv = JSON.parse(sessionStorage.getItem(SCROLL) || "null");
                if (sv && sv.href === location.href) { scroller.scrollLeft = sv.x; window.scrollTo(0, sv.y); }
                sessionStorage.removeItem(SCROLL);
            } catch (e) { /* private */ }
            // the first visit: today in view
            if (!scroller.scrollLeft) {
                var td = $("thead .is-today", scroller), emp = $("thead .att-sheet__emp", scroller);
                if (td && emp) {
                    var rtl = document.dir === "rtl";
                    var x = td.offsetLeft - emp.offsetWidth - 3 * td.offsetWidth;
                    if (x > 0) { scroller.scrollLeft = rtl ? -x : x; }
                }
            }
        }

        var sModal = $("#att-day-modal");
        if (!sModal) { return; }
        var sBody = $("[data-att-day-body]", sModal), sForm = $("[data-att-day-form]", sModal);
        page.addEventListener("click", function (ev) {
            var c = ev.target.closest("[data-att-cell]");
            if (!c) { return; }
            var rec = c.getAttribute("data-rec");
            var isNew = !rec || rec === "0";
            $("[data-att-day-title]", sModal).textContent = isNew
                ? HRMS.t("js.att_add_day", "Add a day") + " · " + c.getAttribute("data-name")
                : HRMS.t("js.att_edit_day", "Change the day");
            sBody.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            modal(sModal).show();
            var args = isNew ? { employee: c.getAttribute("data-emp"), date: c.getAttribute("data-date") } : { id: rec };
            HRMS.getHtml(qs(url("day"), args)).then(function (html) {
                sBody.innerHTML = html;
                $all("select[data-searchable]", sBody).forEach(HRMS.searchable);
            }, function () { sBody.innerHTML = ""; HRMS.toast(failed(), "error"); });
        });
        sForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var fd = new FormData(sForm);
            if (!fd.get("excused")) { fd.set("excused", "false"); }
            post(url("save"), fd, $("[data-att-day-save]", sModal)).then(function (res) {
                if (res && res.success) {
                    try { sessionStorage.setItem(SCROLL, JSON.stringify({ href: location.href, x: scroller ? scroller.scrollLeft : 0, y: window.scrollY })); } catch (e) { /* private */ }
                    modal(sModal).hide();
                    reloadWith(res.message);
                }
            });
        });
        return;
    }

    /* ====================================================== Monthly Summary */
    if (mode === "summary") {
        var sform = $("[data-att-filters]", page);
        $all("[data-att-filter]", sform).forEach(function (el) {
            el.addEventListener("change", function () { HRMS.go(qs(sform.getAttribute("action"), { company: $("[name=company]", sform).value, month: $("[name=month]", sform).value })); });
        });
        var body = { company: page.getAttribute("data-company"), month: page.getAttribute("data-month") };
        var postBtn = $("[data-att-post]");
        if (postBtn) {
            postBtn.addEventListener("click", function () {
                HRMS.confirm({ title: postBtn.getAttribute("data-confirm-title"), text: postBtn.getAttribute("data-confirm-text"), tone: "primary",
                               ok: HRMS.t("js.att_post", "Post to payroll"), note: "" })
                    .then(function (ok) { if (ok) { post(url("post"), body, postBtn).then(function (res) { if (res && res.success) { reloadWith(res.message); } }); } });
            });
        }
        var unpostBtn = $("[data-att-unpost]");
        if (unpostBtn) {
            unpostBtn.addEventListener("click", function () {
                HRMS.confirm({ title: HRMS.t("js.att_unpost_title", "Take the posting back?"),
                               text: HRMS.t("js.att_unpost_text", "The month's attendance deductions and overtime are removed from the payroll; the days can be changed again."),
                               ok: HRMS.t("js.att_unpost", "Take back"), note: "" })
                    .then(function (ok) { if (ok) { post(url("unpost"), body, unpostBtn).then(function (res) { if (res && res.success) { reloadWith(res.message); } }); } });
            });
        }
        return;
    }

    /* ====================================================== Employees */
    if (mode === "employees") {
        var labels = $("template[data-att-labels]");
        var bulk = $("[data-att-bulk]", page);
        function checked() { return $all("[data-att-check]:checked", page); }
        function syncBulk() {
            if (!bulk) { return; }
            var n = checked().length;
            bulk.hidden = n === 0;
            var c = $("[data-att-bulk-count]", bulk);
            c.textContent = n === 1 ? c.getAttribute("data-one") : c.getAttribute("data-many").replace("{0}", n);
        }
        var egrid = wireList({ gridUrl: url("grid"), onLoad: syncBulk });
        page.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-att-check-all]")) {
                $all("[data-att-check]", page).forEach(function (b) { b.checked = ev.target.checked; });
                syncBulk();
            } else if (ev.target.matches("[data-att-check]")) { syncBulk(); }
            else if (ev.target.matches("[data-att-device]")) {
                // the device ID is saved as soon as it is changed
                var tr = ev.target.closest("tr[data-id]");
                postJson(url("save"), [{ employeeId: parseInt(tr.getAttribute("data-id"), 10), deviceUserId: ev.target.value.trim(), setDevice: true }], null)
                    .then(function (res) { if (res && res.success) { HRMS.toast(labels.getAttribute("data-saved"), "success"); } });
            }
        });
        if (bulk) {
            $("[data-att-bulk-apply]", bulk).addEventListener("click", function (ev) {
                var sel = $("[data-att-bulk-pattern]", bulk);
                if (!sel.value) { HRMS.toast(labels.getAttribute("data-pick-pattern"), "error"); sel.focus(); return; }
                var company = sel.options[sel.selectedIndex].getAttribute("data-company");
                var rows = checked().map(function (b) { return b.closest("tr[data-id]"); });
                var other = rows.filter(function (tr) { return tr.getAttribute("data-company") !== company; });
                if (other.length) { HRMS.toast(labels.getAttribute("data-other-company"), "error"); return; }
                var from = $("[data-att-bulk-from]", bulk).value;
                postJson(url("save"), rows.map(function (tr) {
                    return { employeeId: parseInt(tr.getAttribute("data-id"), 10), patternId: parseInt(sel.value, 10), effectiveFrom: from };
                }), ev.currentTarget).then(function (res) {
                    if (res && res.success) { HRMS.toast(res.message, "success"); egrid.load(); }
                });
            });
        }
        return;
    }

    /* ====================================================== Import */
    if (mode !== "import") { return; }
    var L = $("template[data-att-labels]");
    function lab(n) { return L.getAttribute("data-" + n) || ""; }
    var roles = JSON.parse(page.getAttribute("data-roles") || "[]");
    var upload = $("[data-att-upload]"), preview = $("[data-att-preview]"), fileInput = $("[data-att-file]"), drop = $("[data-att-drop]");
    var current = null, employees = null, links = {};

    /* the files imported */
    var importsSlot = $("[data-att-imports]"), importsCount = $("[data-att-imports-count]"), importsPage = 1;
    function loadImports() {
        HRMS.getHtml(qs(url("list"), { page: importsPage })).then(function (html) {
            importsSlot.innerHTML = html;
            var h = $("[data-count-text]", importsSlot);
            HRMS.setCountText(importsCount, h ? h.getAttribute("data-count-text") : "");
        });
    }
    importsSlot.addEventListener("click", function (ev) {
        var p = ev.target.closest("[data-page]");
        if (p && !p.disabled) { importsPage = parseInt(p.getAttribute("data-page"), 10) || 1; loadImports(); return; }
        var d = ev.target.closest("[data-att-delete-import]");
        if (d) {
            HRMS.confirm({ title: lab("delete-title"), name: d.getAttribute("data-name"), text: lab("delete-text"), ok: lab("delete-title") }).then(function (ok) {
                if (ok) { post(url("delete"), { id: d.getAttribute("data-att-delete-import") }, d).then(function (res) { if (res && res.success) { HRMS.toast(res.message, "success"); loadImports(); } }); }
            });
        }
    });
    loadImports();

    if (!upload) { return; }

    /* 1. the file */
    function send(file) {
        if (!file) { return; }
        var fd = new FormData();
        fd.append("file", file);
        drop.classList.add("is-busy");
        HRMS.post(url("preview"), fd).then(function (res) {
            drop.classList.remove("is-busy");
            fileInput.value = "";
            if (!res || !res.success) { HRMS.toast((res && res.message) || failed(), "error"); return; }
            links = {};
            show(res.preview);
        }, function (err) { drop.classList.remove("is-busy"); HRMS.toast((err && err.message) || failed(), "error"); });
    }
    fileInput.addEventListener("change", function () { send(fileInput.files[0]); });
    ["dragenter", "dragover"].forEach(function (n) { drop.addEventListener(n, function (ev) { ev.preventDefault(); drop.classList.add("is-over"); }); });
    ["dragleave", "drop"].forEach(function (n) { drop.addEventListener(n, function (ev) { ev.preventDefault(); drop.classList.remove("is-over"); }); });
    drop.addEventListener("drop", function (ev) { if (ev.dataTransfer && ev.dataTransfer.files.length) { send(ev.dataTransfer.files[0]); } });

    function reset() {
        current = null; links = {};
        preview.hidden = true; upload.hidden = false;
    }
    $all("[data-att-reset]", page).forEach(function (b) { b.addEventListener("click", reset); });

    function rolesNow() {
        var out = {};
        $all("[data-att-role]", preview).forEach(function (s) { out[s.getAttribute("data-att-role")] = s.value; });
        return out;
    }
    function fmtDate(iso) {
        if (!iso) { return "—"; }
        var p = iso.split("-");
        return new Date(+p[0], +p[1] - 1, +p[2]).toLocaleDateString(document.documentElement.lang || undefined, { day: "2-digit", month: "short", year: "numeric" });
    }

    /* 2. what was found */
    function show(pv) {
        current = pv;
        upload.hidden = true; preview.hidden = false;
        $("[data-att-p-file]").textContent = pv.fileName;
        var fmt = $("[data-att-p-format]");
        fmt.textContent = pv.format === "PUNCH" ? fmt.getAttribute("data-punch") : fmt.getAttribute("data-paired");
        $("[data-att-p-rows]").textContent = pv.dataRows;
        $("[data-att-p-days]").textContent = pv.days;
        $("[data-att-p-period]").textContent = pv.from ? fmtDate(pv.from) + " – " + fmtDate(pv.to) : "—";
        var people = pv.people || [];
        var matched = people.filter(function (p) { return p.employeeId; }).length;
        $("[data-att-p-people]").textContent = lab("n-of-m").replace("{0}", matched).replace("{1}", people.length);
        $("[data-att-p-skipped]").textContent = pv.skipped;
        var prob = $("[data-att-p-problem]");
        prob.hidden = !pv.problem;
        $("[data-att-p-problem-text]").textContent = pv.problem || "";
        var warn = $("[data-att-p-warn]");
        warn.hidden = !(pv.warnings && pv.warnings.length);
        $("[data-att-p-warn-text]").textContent = (pv.warnings || []).join(" ");

        // the columns and how each is read (changed here -> read again)
        $("[data-att-p-columns]").innerHTML = (pv.columns || []).map(function (c) {
            var opts = roles.map(function (r) { return '<option value="' + r.value + '"' + (r.value === c.role ? " selected" : "") + ">" + esc(r.text) + "</option>"; }).join("");
            var by = c.basis === "header" ? lab("by-header") : c.basis === "data" ? lab("by-data") : c.basis === "chosen" ? lab("by-chosen") : lab("by-none");
            return '<tr class="' + (c.role === "None" || c.role === "Total" ? "is-muted" : "") + '">' +
                '<td data-label="">' + '<strong>' + esc(c.header || ("#" + (c.index + 1))) + '</strong></td>' +
                '<td class="att-cols__sample" dir="auto">' + esc(c.sample || "—") + "</td>" +
                '<td><select class="form-select form-select-sm" data-att-role="' + c.index + '">' + opts + "</select>" +
                '<span class="att-by att-by--' + esc(c.basis) + '">' + esc(by) + "</span></td></tr>";
        }).join("");

        var skips = $("[data-att-p-skips]");
        skips.hidden = !(pv.skipReasons && pv.skipReasons.length);
        $("[data-att-p-skip-list]").innerHTML = (pv.skipReasons || []).map(function (s) { return "<li>" + esc(s) + "</li>"; }).join("");

        $("[data-att-p-sample]").innerHTML = (pv.sample || []).map(function (d) {
            return "<tr><td><span class=\"hrms-code-chip\">" + esc(d.id) + "</span> <span class=\"pr-emp-sub\">" + esc(d.name || "") + "</span></td><td>" + esc(fmtDate(d.date)) +
                "</td><td class=\"text-center hrms-numeric\">" + esc(d.clockIn || "—") + "</td><td class=\"text-center hrms-numeric\">" + esc(d.clockOut || "—") + "</td></tr>";
        }).join("");

        renderPeople();
    }

    function renderPeople() {
        var people = current.people || [];
        var unmatched = 0;
        $("[data-att-p-people-list]").innerHTML = people.map(function (p) {
            var linked = links.hasOwnProperty(p.deviceId) ? links[p.deviceId] : (p.employeeId || 0);
            if (!linked) { unmatched++; }
            var by = links.hasOwnProperty(p.deviceId) ? "chosen" : p.matchedBy;
            var cell = p.employeeId && !links.hasOwnProperty(p.deviceId)
                ? '<span class="hrms-table__primary">' + esc(p.employeeName) + '</span><span class="pr-emp-sub">' + esc(p.employeeNo || "") + (p.companyName ? " · " + esc(p.companyName) : "") +
                  ' · <button type="button" class="btn btn-link btn-sm p-0" data-att-relink="' + esc(p.deviceId) + '">' + esc(lab("pick")) + "</button></span>"
                : '<select class="form-select form-select-sm att-link" data-att-link="' + esc(p.deviceId) + '"><option value="0">' + esc(lab("leave-out")) + "</option>" +
                  (employees || []).map(function (e) { return '<option value="' + e.id + '"' + (e.id === linked ? " selected" : "") + ">" + esc(e.text) + "</option>"; }).join("") + "</select>";
            return '<tr class="' + (linked ? "" : "is-unmatched") + '"><td><span class="hrms-code-chip">' + esc(p.deviceId) + "</span></td><td dir=\"auto\">" + esc(p.fileName || "—") +
                '</td><td class="text-center">' + p.days + "</td><td>" + cell + '</td><td><span class="att-m att-m--' + esc(by) + '">' + esc(lab("m-" + by)) + "</span></td></tr>";
        }).join("");
        var badge = $("[data-att-p-unmatched]");
        badge.hidden = unmatched === 0;
        badge.textContent = lab("unmatched").replace("{0}", unmatched);
        // the employees to choose from are loaded once, when a select is needed
        if (!employees && $("[data-att-link]", preview)) {
            HRMS.getJson(url("employees")).then(function (list) { employees = list || []; renderPeople(); });
        }
        $all("[data-att-link]", preview).forEach(function (s) { if (employees) { HRMS.searchable(s); } });
        var days = people.reduce(function (n, p) {
            var linked = links.hasOwnProperty(p.deviceId) ? links[p.deviceId] : p.employeeId;
            return n + (linked ? p.days : 0);
        }, 0);
        var btn = $("[data-att-confirm]");
        $("[data-att-confirm-text]").textContent = btn.getAttribute("data-label").replace("{0}", days);
        btn.disabled = !!current.problem || days === 0;
    }

    preview.addEventListener("change", function (ev) {
        var r = ev.target.closest("[data-att-role]");
        if (r) {
            postJson(url("remap"), { token: current.token, roles: rolesNow() }, null).then(function (res) { if (res && res.success) { show(res.preview); } });
            return;
        }
        var l = ev.target.closest("[data-att-link]");
        if (l) { links[l.getAttribute("data-att-link")] = parseInt(l.value, 10) || 0; renderPeople(); }
    });
    preview.addEventListener("click", function (ev) {
        var r = ev.target.closest("[data-att-relink]");
        if (r) {
            var p = (current.people || []).filter(function (x) { return x.deviceId === r.getAttribute("data-att-relink"); })[0];
            links[p.deviceId] = p.employeeId || 0;
            renderPeople();
        }
    });

    /* 3. import */
    $("[data-att-confirm]").addEventListener("click", function (ev) {
        postJson(url("confirm"), { token: current.token, roles: rolesNow(), links: links, remember: $("[data-att-remember]").checked }, ev.currentTarget)
            .then(function (res) {
                if (res && res.success) {
                    try { sessionStorage.setItem(FLASH, res.message); } catch (e) { /* private */ }
                    var month = current.from ? current.from.substring(0, 7) : "";
                    HRMS.go(qs(url("register"), { month: month }));
                }
            });
    });
})();
