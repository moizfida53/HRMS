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
        var rangeTyped = false;     // a From / To typed: a custom range, else the payroll period of the month
        $all("[data-att-sheet-date]", sf).forEach(function (el) { el.addEventListener("change", function () { rangeTyped = true; }); });
        var custom = !!$(".att-range-chip.is-custom", sf);

        /* ---------------- changes not saved: asked before leaving the page ---------------- */
        var pending = {};           // "employee|date" -> the day marked (and how it looked before)
        var leaving = false;
        function pendingKeys() { return Object.keys(pending); }
        function isDirty() { return !leaving && pendingKeys().length > 0; }
        var leaveModal = $("#att-leave-modal");
        var leaveNext = null;
        /** Runs go() now, or - with changes not saved - after asking: save them, leave without them, or stay. */
        function guarded(go, onStay) {
            if (!isDirty() || !leaveModal) { go(); return; }
            leaveNext = { go: go, stay: onStay, chosen: false };
            modal(leaveModal).show();
        }
        if (leaveModal) {
            $("[data-att-leave-yes]", leaveModal).addEventListener("click", function (ev) {
                var next = leaveNext; if (!next) { return; }
                saveMarks(ev.currentTarget).then(function (ok) {
                    if (!ok) { return; }
                    next.chosen = true; modal(leaveModal).hide(); leaving = true; next.go();
                });
            });
            $("[data-att-leave-no]", leaveModal).addEventListener("click", function () {
                var next = leaveNext; if (!next) { return; }
                next.chosen = true; modal(leaveModal).hide(); leaving = true; next.go();
            });
            leaveModal.addEventListener("hidden.bs.modal", function () {
                if (leaveNext && !leaveNext.chosen && leaveNext.stay) { leaveNext.stay(); }
                leaveNext = null;
            });
        }
        // closing the tab / reloading: the browser's own question (it cannot save)
        window.addEventListener("beforeunload", function (ev) {
            if (isDirty()) { ev.preventDefault(); ev.returnValue = ""; return ""; }
        });
        // a link of the app (sidebar, top bar, the employee's days ...)
        document.addEventListener("click", function (ev) {
            if (!isDirty() || ev.defaultPrevented || ev.button !== 0 || ev.ctrlKey || ev.metaKey || ev.shiftKey || ev.altKey) { return; }
            var a = ev.target.closest("a[href]");
            if (!a || a.hasAttribute("download") || (a.target && a.target !== "_self")) { return; }
            var href = a.getAttribute("href");
            if (!href || href.charAt(0) === "#" || href.indexOf("javascript:") === 0) { return; }
            ev.preventDefault();
            guarded(function () { window.location.href = a.href; });
        }, true);

        // the filters: a new company / month / range is a new page
        function submitFilters(period) {
            guarded(function () {
                if (period) { fromEl.disabled = true; toEl.disabled = true; }
                else if (fromEl.value && toEl.value && fromEl.value > toEl.value) { var t = fromEl.value; fromEl.value = toEl.value; toEl.value = t; }
                leaving = true;
                sf.submit();
            }, function () { sf.reset(); rangeTyped = false; });
        }
        $("[data-att-sheet-month]", sf).addEventListener("change", function () { submitFilters(true); });
        $all("[data-att-sheet-auto]", sf).forEach(function (el) {
            el.addEventListener("change", function () { submitFilters(!(custom || rangeTyped)); });
        });
        sf.addEventListener("submit", function (ev) { ev.preventDefault(); submitFilters(!custom && !rangeTyped); });

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
                var td0 = $("thead .is-today", scroller), emp0 = $("thead .att-sheet__emp", scroller);
                if (td0 && emp0) {
                    var rtl = document.dir === "rtl";
                    var x0 = td0.offsetLeft - emp0.offsetWidth - 3 * td0.offsetWidth;
                    if (x0 > 0) { scroller.scrollLeft = rtl ? -x0 : x0; }
                }
            }
        }
        function keepScroll() {
            try { sessionStorage.setItem(SCROLL, JSON.stringify({ href: location.href, x: scroller ? scroller.scrollLeft : 0, y: window.scrollY })); } catch (e) { /* private */ }
        }

        var sModal = $("#att-day-modal");
        if (!sModal) { return; }

        /* ---------------- marking days: right click -> Present, Absent, Late ... ---------------- */
        var MARKS = {
            PRESENT: { kind: "ok", text: "✓" }, ABSENT: { kind: "absent", text: "✗" }, LATE: { kind: "late", text: "L" },
            SHORT: { kind: "short", text: "S" }, LEAVE: { kind: "leave", text: "LV" }, HOLIDAY: { kind: "holiday", text: "H" },
            EXCUSED: { kind: "excused", text: "E" }
        };
        var KIND_MARK = { ok: "PRESENT", absent: "ABSENT", leave: "LEAVE", holiday: "HOLIDAY" };
        var PRESENT_KINDS = { ok: 1, nopattern: 1, late: 1, short: 1, excused: 1 };
        var ctx = $("[data-att-ctx]"), ctxTd = null;
        var saveBtn = $("[data-att-mk-save]"), discardBtn = $("[data-att-mk-discard]");
        var company = page.getAttribute("data-company");

        function keyOf(td) { return td.closest("tr").getAttribute("data-emp") + "|" + td.getAttribute("data-date"); }
        function nameOf(td) { return td.closest("tr").getAttribute("data-name") || ""; }
        function dateText(td) {
            var d = new Date(td.getAttribute("data-date") + "T00:00:00");
            try { return d.toLocaleDateString(document.documentElement.lang || undefined, { weekday: "short", day: "numeric", month: "short", year: "numeric" }); }
            catch (e) { return td.getAttribute("data-date"); }
        }

        var ctxTargets = [];
        function closeCtx() { if (ctx) { ctx.hidden = true; ctxTd = null; } }
        function openCtx(td, x, y) {
            ctxTd = td;
            var locked = td.classList.contains("is-locked");
            // a right click on a selected day acts on every day selected
            ctxTargets = !locked && td.classList.contains("is-selected") && selected.length > 1 ? selected.slice() : [td];
            var many = ctxTargets.length > 1;
            var mark = many ? null : KIND_MARK[td.getAttribute("data-kind")];
            $("[data-att-ctx-head]", ctx).textContent = many ? selCountText(ctxTargets.length) : nameOf(td) + " · " + dateText(td);
            $all("[data-mark]", ctx).forEach(function (b) { b.hidden = locked || b.getAttribute("data-mark") === mark; });
            $("[data-mark-undo]", ctx).hidden = locked || !ctxTargets.some(function (t) { return pending[keyOf(t)]; });
            $("[data-mark-open]", ctx).hidden = locked || many || !$("[data-att-cell]", td);
            $(".dropdown-divider", ctx).hidden = locked;
            $("[data-att-ctx-locked]", ctx).hidden = !locked;
            ctx.hidden = false;
            var w = ctx.offsetWidth, h = ctx.offsetHeight;
            ctx.style.left = Math.max(8, Math.min(x, window.innerWidth - w - 8)) + "px";
            ctx.style.top = Math.max(8, Math.min(y, window.innerHeight - h - 8)) + "px";
            var first = $all("button:not([hidden])", ctx)[0];
            if (first) { first.focus({ preventScroll: true }); }
        }
        page.addEventListener("contextmenu", function (ev) {
            var td = ev.target.closest("td[data-att-day]");
            if (!td || (td.getAttribute("data-can") !== "1" && !td.classList.contains("is-locked"))) { return; }
            ev.preventDefault();
            var x = ev.clientX, y = ev.clientY;
            if (!x && !y) { var rc = td.getBoundingClientRect(); x = rc.left + rc.width / 2; y = rc.bottom; }   // keyboard (menu key / Shift+F10)
            // a day not selected: it becomes the selection
            if (!td.classList.contains("is-locked") && !td.classList.contains("is-selected")) { clearSel(); selectCells([td], true); anchor = td; }
            openCtx(td, x, y);
        });
        document.addEventListener("mousedown", function (ev) { if (ctx && !ctx.hidden && !ctx.contains(ev.target)) { closeCtx(); } });
        window.addEventListener("scroll", closeCtx, true);
        window.addEventListener("resize", closeCtx);
        ctx.addEventListener("keydown", function (ev) {
            ev.stopPropagation();       // the menu's own keys: Escape here does not also clear the selection
            var items = $all("button:not([hidden])", ctx), i = items.indexOf(document.activeElement);
            if (ev.key === "Escape") { var back = ctxTd; closeCtx(); if (back) { var b0 = $("[data-att-cell]", back); if (b0) { b0.focus(); } } ev.preventDefault(); }
            else if (ev.key === "ArrowDown") { items[(i + 1) % items.length].focus(); ev.preventDefault(); }
            else if (ev.key === "ArrowUp") { items[(i - 1 + items.length) % items.length].focus(); ev.preventDefault(); }
            else if (ev.key === "Tab") { closeCtx(); }
        });
        ctx.addEventListener("click", function (ev) {
            var td = ctxTd; if (!td) { return; }
            var b = ev.target.closest("button"); if (!b) { return; }
            var targets = ctxTargets.slice();
            closeCtx();
            if (b.hasAttribute("data-mark-undo")) { targets.forEach(undo); clearSel(); return; }
            if (b.hasAttribute("data-mark-open")) { openDay(td); return; }
            var mark = b.getAttribute("data-mark");
            if (mark === "LATE" || mark === "SHORT" || mark === "EXCUSED") { askDetails(targets, mark); }
            else { targets.forEach(function (t) { setMark(t, mark, null, null); }); clearSel(); }
        });

        // late / short: the minutes (and a comment); excused: the comment
        var mkModal = $("#att-mk-modal"), mkForm = $("[data-att-mk-form]", mkModal), mkTargets = [], mkMark = null;
        var mkMin = $("[data-att-mk-minutes]", mkModal), mkNote = $("[data-att-mk-note]", mkModal);
        function askDetails(targets, mark) {
            mkTargets = targets; mkMark = mark;
            var td = targets[0];
            var p = pending[keyOf(td)];
            var titles = { LATE: HRMS.t("js.att_mk_late", "Late"), SHORT: HRMS.t("js.att_mk_short", "Short hours"), EXCUSED: HRMS.t("js.att_mk_excused", "Excused") };
            $("[data-att-mk-title]", mkModal).textContent = titles[mark];
            $("[data-att-mk-who]", mkModal).textContent = targets.length > 1
                ? selCountText(targets.length) + " · " + HRMS.t("js.att_mk_all_get", "each gets the same")
                : nameOf(td) + " · " + dateText(td);
            var needsMinutes = mark !== "EXCUSED";
            $("[data-att-mk-minutes-wrap]", mkModal).hidden = !needsMinutes;
            mkMin.required = needsMinutes;
            $("[data-att-mk-minutes-label]", mkModal).textContent = mark === "LATE" ? HRMS.t("js.att_mk_late_minutes", "Minutes late") : HRMS.t("js.att_mk_short_minutes", "Minutes short");
            var kindNow = td.getAttribute("data-kind"), minNow = parseInt(td.getAttribute("data-min"), 10) || 0;
            mkMin.value = p && p.status === mark && p.minutes ? p.minutes : (MARKS[mark].kind === kindNow && minNow > 0 ? minNow : "");
            mkNote.value = p && p.note ? p.note : "";
            $("[data-att-mk-note-req]", mkModal).hidden = mark !== "EXCUSED";
            mkNote.required = mark === "EXCUSED";
            mkMin.classList.remove("is-invalid"); mkNote.classList.remove("is-invalid");
            modal(mkModal).show();
        }
        mkModal.addEventListener("shown.bs.modal", function () { (mkMark === "EXCUSED" ? mkNote : mkMin).focus(); });
        mkForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var minutes = null;
            if (mkMark !== "EXCUSED") {
                minutes = parseInt(mkMin.value, 10);
                if (!(minutes > 0 && minutes <= 1440)) { mkMin.classList.add("is-invalid"); mkMin.focus(); return; }
            }
            var note = mkNote.value.trim();
            if (mkMark === "EXCUSED" && !note) { mkNote.classList.add("is-invalid"); mkNote.focus(); return; }
            mkTargets.forEach(function (t) { setMark(t, mkMark, minutes, note || null); });
            clearSel();
            modal(mkModal).hide();
        });

        function draw(td, kind, text, sub, manual, pendingNow) {
            var el = $(".att-cell", td);
            if (!el) { return; }
            el.className = "att-cell att-cell--" + kind + (manual ? " is-manual" : "") + (pendingNow ? " is-pending" : "");
            el.innerHTML = esc(text) + (sub ? "<small>" + esc(sub) + "</small>" : "");
            td.setAttribute("data-kind", kind);
        }
        function setMark(td, mark, minutes, note) {
            var key = keyOf(td), el = $(".att-cell", td);
            if (!pending[key]) {
                pending[key] = { before: { html: el.innerHTML, cls: el.className, kind: td.getAttribute("data-kind"), title: el.getAttribute("title") } };
            }
            var p = pending[key];
            if (p.before.alsoShort === undefined) {
                p.before.alsoShort = td.hasAttribute("data-also-short");
                p.before.lateMin = td.getAttribute("data-late-min") || "0";
                p.before.shortMin = td.getAttribute("data-short-min") || "0";
            }
            td.setAttribute("data-late-min", mark === "LATE" ? String(minutes || 0) : "0");
            td.setAttribute("data-short-min", mark === "SHORT" ? String(minutes || 0) : "0");
            td.removeAttribute("data-also-short");
            p.employeeId = parseInt(td.closest("tr").getAttribute("data-emp"), 10);
            p.date = td.getAttribute("data-date");
            p.status = mark; p.minutes = minutes; p.note = note;
            var m = MARKS[mark];
            draw(td, m.kind, m.text, minutes && mark === "LATE" ? String(minutes) : null, true, true);
            el.setAttribute("title", dateText(td) + " · " + HRMS.t("js.att_mk_not_saved", "Changed - not saved yet") + (note ? " · " + note : ""));
            recount(td);
            syncSave();
        }
        function undo(td) {
            var key = keyOf(td), p = pending[key];
            if (!p) { return; }
            var el = $(".att-cell", td);
            el.className = p.before.cls; el.innerHTML = p.before.html;
            if (p.before.title) { el.setAttribute("title", p.before.title); }
            td.setAttribute("data-kind", p.before.kind);
            if (p.before.alsoShort) { td.setAttribute("data-also-short", "1"); }
            td.setAttribute("data-late-min", p.before.lateMin || "0");
            td.setAttribute("data-short-min", p.before.shortMin || "0");
            delete pending[key];
            recount(td);
            syncSave();
        }
        // the row's totals and the day's count follow the marks (the deduction is worked out on save)
        function recount(td) {
            var tr = td.closest("tr"), cells = $all("td[data-att-day]", tr);
            // L and S are the late / short time (h:mm) the deduction is worked out on
            var c = { p: 0, l: 0, s: 0, a: 0, lv: 0 };
            cells.forEach(function (x) {
                var k = x.getAttribute("data-kind");
                if (PRESENT_KINDS[k]) { c.p++; }
                c.l += parseInt(x.getAttribute("data-late-min"), 10) || 0;
                c.s += parseInt(x.getAttribute("data-short-min"), 10) || 0;
                if (k === "absent") { c.a++; }
                if (k === "leave") { c.lv++; }
            });
            [["p", "is-p"], ["l", "is-l"], ["s", "is-s"], ["a", "is-a"], ["lv", "is-lv"]].forEach(function (t) {
                var cell = $('[data-tot="' + t[0] + '"]', tr);
                if (!cell) { return; }
                cell.textContent = t[0] === "l" || t[0] === "s" ? hm(c[t[0]], "\u2014") : c[t[0]];
                if (t[0] !== "p") { cell.classList.toggle(t[1], c[t[0]] > 0); cell.classList.toggle("is-zero", c[t[0]] === 0); }
            });
            ["l", "s"].forEach(function (k) {
                var f = $('[data-foot-tot="' + k + '"]', page);
                if (!f) { return; }
                var sum = 0;
                $all("td[data-att-day]", page).forEach(function (x) { sum += parseInt(x.getAttribute(k === "l" ? "data-late-min" : "data-short-min"), 10) || 0; });
                f.textContent = hm(sum, "0:00");
            });
            var ded = $('[data-tot="ded"]', tr);
            if (ded) { ded.classList.toggle("is-stale", $all(".att-cell.is-pending", tr).length > 0); }
            var i = td.getAttribute("data-att-day"), foot = $('[data-foot="' + i + '"]', page);
            if (foot) {
                var n = $all('td[data-att-day="' + i + '"]', page).filter(function (x) { return PRESENT_KINDS[x.getAttribute("data-kind")]; }).length;
                foot.textContent = n;
            }
        }
        function hm(min, zero) { return min > 0 ? Math.floor(min / 60) + ":" + ("0" + (min % 60)).slice(-2) : zero; }
        function syncSave() {
            var n = pendingKeys().length;
            if (saveBtn) {
                saveBtn.hidden = n === 0;
                $("[data-att-mk-save-text]", saveBtn).textContent = (saveBtn.getAttribute("data-text") || "Save changes ({0})").replace("{0}", n);
            }
            // work the payroll month out again (the changes not saved yet are saved first)
        var recalcBtn = $("[data-att-recalc]");
        if (recalcBtn) {
            recalcBtn.addEventListener("click", function () {
                saveMarks(recalcBtn).then(function (ok) {
                    if (!ok) { return; }
                    post(url("recalc"), { company: recalcBtn.getAttribute("data-company"), month: recalcBtn.getAttribute("data-month") }, recalcBtn).then(function (res) {
                        if (res && res.success) { keepScroll(); leaving = true; reloadWith(res.message); }
                    });
                });
            });
        }
        if (discardBtn) { discardBtn.hidden = n === 0; }
        }
        /** Saves the marks; resolves true when saved. */
        function saveMarks(button) {
            var keys = pendingKeys();
            if (keys.length === 0) { return Promise.resolve(true); }
            var marks = keys.map(function (k) {
                var p = pending[k];
                return { employeeId: p.employeeId, date: p.date, status: p.status, minutes: p.minutes, note: p.note };
            });
            return postJson(url("marks"), { company: parseInt(company, 10), marks: marks }, button).then(function (res) {
                if (!res || !res.success) { return false; }
                pending = {};
                try { sessionStorage.setItem(FLASH, res.message || ""); } catch (e) { /* private */ }
                return true;
            });
        }
        if (saveBtn) {
            saveBtn.addEventListener("click", function () {
                saveMarks(saveBtn).then(function (ok) { if (ok) { keepScroll(); leaving = true; HRMS.reload(); } });
            });
        }
        if (discardBtn) {
            discardBtn.addEventListener("click", function () {
                pendingKeys().forEach(function (k) {
                    var parts = k.split("|");
                    var td = $('tr[data-emp="' + parts[0] + '"] td[data-date="' + parts[1] + '"]', page);
                    if (td) { undo(td); }
                });
            });
        }
        syncSave();

        /* ---------------- selecting days: a click, Shift+click (a range), a row, a column, all ---------------- */
        var selected = [], anchor = null;
        var selbar = $("[data-att-selbar]"), selCount = $("[data-att-sel-count]"), selAll = $("[data-att-sel-all]");
        var allRows = $all("tr[data-att-row]", page);
        function selectable(td) { return !!td && td.getAttribute("data-can") === "1"; }
        function selCountText(n) {
            return n === 1 ? (selCount ? selCount.getAttribute("data-one") : "1 day")
                           : (selCount ? selCount.getAttribute("data-many") : "{0} days").replace("{0}", n);
        }
        function setSel(td, on) {
            td.classList.toggle("is-selected", on);
            var b = $("[data-att-cell]", td);
            if (b) { b.setAttribute("aria-pressed", on ? "true" : "false"); }
        }
        function syncSel() {
            selected = $all("td[data-att-day].is-selected", page);
            if (selbar) { selbar.hidden = selected.length === 0; }
            if (selCount) { selCount.textContent = selCountText(selected.length); }
            var any = 0, all = 0;
            allRows.forEach(function (tr) {
                var can = $all("td[data-att-day]", tr).filter(selectable);
                var on = can.filter(function (t) { return t.classList.contains("is-selected"); });
                var box = $("[data-att-sel-row]", tr);
                if (box) { box.checked = can.length > 0 && on.length === can.length; box.indeterminate = on.length > 0 && on.length < can.length; }
                any += can.length; all += on.length;
            });
            if (selAll) { selAll.checked = any > 0 && all === any; selAll.indeterminate = all > 0 && all < any; }
            $all("th[data-att-col]", page).forEach(function (th) {
                var col = $all('td[data-att-day="' + th.getAttribute("data-att-col") + '"]', page).filter(selectable);
                th.classList.toggle("is-selected", col.length > 0 && col.every(function (t) { return t.classList.contains("is-selected"); }));
            });
        }
        function selectCells(list, on) { list.filter(selectable).forEach(function (t) { setSel(t, on); }); syncSel(); }
        function clearSel() { $all("td[data-att-day].is-selected", page).forEach(function (t) { setSel(t, false); }); syncSel(); }
        function cellsBetween(a, b) {
            var r1 = allRows.indexOf(a.closest("tr")), r2 = allRows.indexOf(b.closest("tr"));
            var c1 = parseInt(a.getAttribute("data-att-day"), 10), c2 = parseInt(b.getAttribute("data-att-day"), 10);
            var out = [];
            for (var r = Math.min(r1, r2); r <= Math.max(r1, r2); r++) {
                for (var c = Math.min(c1, c2); c <= Math.max(c1, c2); c++) {
                    var t = $('td[data-att-day="' + c + '"]', allRows[r]);
                    if (t) { out.push(t); }
                }
            }
            return out;
        }
        function toggleColumn(th) {
            var col = $all('td[data-att-day="' + th.getAttribute("data-att-col") + '"]', page).filter(selectable);
            var allOn = col.length > 0 && col.every(function (t) { return t.classList.contains("is-selected"); });
            selectCells(col, !allOn);
        }
        page.addEventListener("click", function (ev) {
            var c = ev.target.closest("[data-att-cell]");
            if (c) {
                var td = c.closest("td");
                if (ev.shiftKey && anchor && anchor !== td) { selectCells(cellsBetween(anchor, td), true); }
                else { selectCells([td], !td.classList.contains("is-selected")); }
                anchor = td;
                return;
            }
            var th = ev.target.closest("th[data-att-col]");
            if (th && !th.classList.contains("is-locked")) { toggleColumn(th); }
        });
        page.addEventListener("keydown", function (ev) {
            var th = ev.target.closest && ev.target.closest("th[data-att-col]");
            if (th && (ev.key === "Enter" || ev.key === " ")) { ev.preventDefault(); if (!th.classList.contains("is-locked")) { toggleColumn(th); } }
        });
        document.addEventListener("keydown", function (ev) {
            if (ev.key === "Escape" && !ev.defaultPrevented && selected.length && (!ctx || ctx.hidden) && !document.querySelector(".modal.show")) { clearSel(); }
        });
        page.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-att-sel-row]")) { selectCells($all("td[data-att-day]", ev.target.closest("tr")), ev.target.checked); }
            else if (ev.target.matches("[data-att-sel-all]")) { selectCells($all("td[data-att-day]", page), ev.target.checked); }
        });
        if (selbar) {
            $("[data-att-sel-apply]", selbar).addEventListener("click", function () {
                var mark = $("[data-att-sel-mark]", selbar).value;
                selected.slice().forEach(function (t) { setMark(t, mark, null, null); });
                clearSel();
            });
            $("[data-att-sel-clear]", selbar).addEventListener("click", clearSel);
        }
        syncSel();

        /* ---------------- the day's form (times, excused, note): "Open the day…" in the menu, or a double click ---------------- */
        var sBody = $("[data-att-day-body]", sModal), sForm = $("[data-att-day-form]", sModal);
        function openDay(td) {
            var c = $("[data-att-cell]", td);
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
        }
        page.addEventListener("dblclick", function (ev) {
            var c = ev.target.closest("[data-att-cell]");
            if (c) { ev.preventDefault(); clearSel(); openDay(c.closest("td")); }
        });
        sForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            var fd = new FormData(sForm);
            if (!fd.get("excused")) { fd.set("excused", "false"); }
            var dayBtn = $("[data-att-day-save]", sModal);
            // the marks not saved yet go first (the page is shown again after the day is saved)
            saveMarks(dayBtn).then(function (ok) {
                if (!ok) { return; }
                post(url("save"), fd, dayBtn).then(function (res) {
                    if (res && res.success) {
                        keepScroll();
                        modal(sModal).hide();
                        leaving = true;
                        reloadWith(res.message);
                    }
                });
            });
        });
        return;
    }

    /* ====================================================== Monthly Summary */
    if (mode === "summary") {
        var sform = $("[data-att-filters]", page);
        // work the month out again with the attendance settings now (the page action, outside the page element)
        var sRecalc = $("[data-att-recalc]");
        if (sRecalc) {
            sRecalc.addEventListener("click", function () {
                post(url("recalc"), { company: sRecalc.getAttribute("data-company"), month: sRecalc.getAttribute("data-month") }, sRecalc).then(function (res) {
                    if (res && res.success) { reloadWith(res.message); }
                });
            });
        }
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
        // an employee matched (or linked) to one ID of the file is not offered for another ID
        var takenBy = {};
        people.forEach(function (p) {
            var id = links.hasOwnProperty(p.deviceId) ? links[p.deviceId] : (p.employeeId || 0);
            if (id) { takenBy[id] = p.deviceId; }
        });
        $("[data-att-p-people-list]").innerHTML = people.map(function (p) {
            var linked = links.hasOwnProperty(p.deviceId) ? links[p.deviceId] : (p.employeeId || 0);
            if (!linked) { unmatched++; }
            var by = links.hasOwnProperty(p.deviceId) ? "chosen" : p.matchedBy;
            var cell = p.employeeId && !links.hasOwnProperty(p.deviceId)
                ? '<span class="hrms-table__primary">' + esc(p.employeeName) + '</span><span class="pr-emp-sub">' + esc(p.employeeNo || "") + (p.companyName ? " · " + esc(p.companyName) : "") +
                  ' · <button type="button" class="btn btn-link btn-sm p-0" data-att-relink="' + esc(p.deviceId) + '">' + esc(lab("pick")) + "</button></span>"
                : '<select class="form-select form-select-sm att-link" data-att-link="' + esc(p.deviceId) + '"><option value="0">' + esc(lab("leave-out")) + "</option>" +
                  (employees || []).filter(function (e) { return !takenBy[e.id] || takenBy[e.id] === p.deviceId; })
                      .map(function (e) { return '<option value="' + e.id + '"' + (e.id === linked ? " selected" : "") + ">" + esc(e.text) + "</option>"; }).join("") + "</select>";
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
