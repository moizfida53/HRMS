/* ==========================================================================
 * HRMS Kuwait - Payroll Processing (db/34-35)
 * Payroll Calendar, Create Payroll wizard, Register, Validation, Approval,
 * History and Payroll Comparison. Panels are server-rendered partials (labels from Core.UiLabels);
 * this file only wires them up. Every POST carries the anti-forgery token.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-pr-page]");
    if (!page) { return; }
    var PAGE = page.getAttribute("data-pr-page");

    /* ------------------------------------------------------------- helpers */

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function qs(params) {
        return Object.keys(params).filter(function (k) {
            return params[k] !== null && params[k] !== undefined && params[k] !== "";
        }).map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function withQs(url, params) { var q = qs(params); return q ? url + (url.indexOf("?") >= 0 ? "&" : "?") + q : url; }
    function form(params) {
        var fd = new FormData();
        Object.keys(params).forEach(function (k) {
            if (params[k] !== null && params[k] !== undefined) { fd.append(k, params[k]); }
        });
        return fd;
    }
    function modal(el) { return el && window.bootstrap ? window.bootstrap.Modal.getOrCreateInstance(el) : null; }
    function busy(button, on) {
        if (!button) { return; }
        button.disabled = !!on;
        button.classList.toggle("is-busy", !!on);
    }
    function fail(error) {
        HRMS.toast((error && error.message) || HRMS.t("js.pr_failed", "The request could not be completed."), "error");
    }
    /** POST and toast the server's (already translated) message. Resolves with the ActionResponse. */
    function post(url, params, button) {
        busy(button, true);
        return HRMS.post(url, params instanceof FormData ? params : form(params)).then(function (res) {
            busy(button, false);
            if (res && res.success) {
                if (res.message) { HRMS.toast(res.message, "success"); }
            } else if (res) {
                HRMS.toast(res.message || HRMS.t("js.pr_failed", "The request could not be completed."), "error");
            }
            return res;
        }, function (error) { busy(button, false); fail(error); throw error; });
    }
    function loadInto(slot, url) {
        if (!slot) { return Promise.resolve(); }
        slot.setAttribute("aria-busy", "true");
        return HRMS.getHtml(url).then(function (html) {
            slot.innerHTML = html;
            slot.removeAttribute("aria-busy");
            return slot;
        }, function (error) {
            slot.removeAttribute("aria-busy");
            slot.innerHTML = '<div class="hrms-empty"><p class="hrms-empty__title">' +
                HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + "</p></div>";
            fail(error);
        });
    }
    function setCount(slot, counter) {
        var holder = slot && slot.querySelector("[data-count-text]");
        if (counter) { HRMS.setCountText(counter, holder ? holder.getAttribute("data-count-text") : ""); }
    }
    function num(v) { return parseFloat(String(v || "").replace(/,/g, "")); }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments, self = this; clearTimeout(t); t = setTimeout(function () { fn.apply(self, a); }, wait); };
    };

    var urls = (function () {
        var el = $("[data-run-urls]");
        var out = {};
        if (el) { Array.prototype.forEach.call(el.attributes, function (a) { if (a.name.indexOf("data-") === 0) { out[a.name.slice(5)] = a.value; } }); }
        return out;
    })();
    var RUN = urls.run || page.getAttribute("data-run") || "";
    function openRun(id) { HRMS.go((urls.open || page.getAttribute("data-urls-open") || "/payroll/run/0").replace(/\/0$/, "/" + id)); }

    /* ------------------------------------------- reason / confirm dialogs */

    var reasonModal = $("#reason-modal");
    var reasonOpener = null;
    document.addEventListener("click", function (ev) {
        var opener = ev.target.closest("[data-reason-open]");
        if (!opener || !reasonModal) { return; }
        ev.preventDefault();
        reasonOpener = opener;
        $("[data-reason-title]", reasonModal).textContent = opener.getAttribute("data-reason-title") || "";
        $("[data-reason-text]", reasonModal).textContent = opener.getAttribute("data-reason-text") || "";
        $("[data-reason-label]", reasonModal).textContent = opener.getAttribute("data-reason-label") || "";
        $("[data-reason-button]", reasonModal).textContent = opener.getAttribute("data-reason-button") || "";
        var input = $("[data-reason-input]", reasonModal);
        input.value = opener.getAttribute("data-reason-value") || "";
        input.placeholder = opener.getAttribute("data-reason-placeholder") || "";
        input.classList.remove("is-invalid");
        $("[data-reason-error]", reasonModal).hidden = true;
        var submit = $("[data-reason-submit]", reasonModal);
        submit.classList.toggle("btn-danger", opener.getAttribute("data-reason-danger") === "true");
        submit.classList.toggle("btn-primary", opener.getAttribute("data-reason-danger") !== "true");
        modal(reasonModal).show();
        window.setTimeout(function () { input.focus(); }, 250);
    });
    if (reasonModal) {
        $("[data-reason-form]", reasonModal).addEventListener("submit", function (ev) {
            ev.preventDefault();
            if (!reasonOpener) { return; }
            var input = $("[data-reason-input]", reasonModal);
            var value = input.value.trim();
            if (!value) {
                input.classList.add("is-invalid");
                $("[data-reason-error]", reasonModal).hidden = false;
                return;
            }
            var field = reasonOpener.getAttribute("data-reason-field") || (reasonOpener.getAttribute("data-reason-url").indexOf("/exclude") >= 0 ? "reason" : "comment");
            var params = {};
            params[field] = value;
            var opener = reasonOpener;
            post(opener.getAttribute("data-reason-url"), params, $("[data-reason-submit]", reasonModal)).then(function (res) {
                if (!res || !res.success) { return; }
                modal(reasonModal).hide();
                var refresh = opener.getAttribute("data-reason-refresh");
                var redirect = opener.getAttribute("data-reason-redirect");
                if (redirect && RUN) { HRMS.go("/payroll/" + redirect + "?run=" + RUN); }
                else if (refresh === "employees" && grid) { grid.reload(true); }
                else if (refresh === "payitems" && HRMS.payItemsRefresh) { HRMS.payItemsRefresh(); }
                else { HRMS.reload(); }
            });
        });
    }

    var confirmModal = $("#confirm-modal");
    function confirmDialog(title, text, button) {
        return new Promise(function (resolve) {
            if (!confirmModal) { resolve(window.confirm(text)); return; }
            $("[data-confirm-title]", confirmModal).textContent = title;
            $("[data-confirm-text]", confirmModal).textContent = text;
            $("[data-confirm-button]", confirmModal).textContent = button || title;
            var accept = $("[data-confirm-accept]", confirmModal);
            var done = false;
            function onAccept() { done = true; modal(confirmModal).hide(); resolve(true); }
            function onHide() {
                accept.removeEventListener("click", onAccept);
                confirmModal.removeEventListener("hidden.bs.modal", onHide);
                if (!done) { resolve(false); }
            }
            accept.addEventListener("click", onAccept);
            confirmModal.addEventListener("hidden.bs.modal", onHide);
            modal(confirmModal).show();
        });
    }

    /* ------------------------------------------------- run bar (header) */

    var runSelect = $("[data-run-select]");
    if (runSelect) {
        runSelect.addEventListener("change", function () { openRun(runSelect.value); });
    }

    document.addEventListener("click", function (ev) {
        var stage = ev.target.closest("[data-run-stage]");
        if (stage && urls.stage) {
            post(urls.stage, { run: RUN, stage: stage.getAttribute("data-run-stage") }, stage).then(function (res) {
                if (res && res.success) { openRun(RUN); }
                else if (res && res.errorCode === "HAS_ERRORS") { window.setTimeout(function () { HRMS.reload(); }, 900); }
            });
            return;
        }
        var recalc = ev.target.closest("[data-run-recalc]");
        if (recalc && urls.recalc) {
            post(urls.recalc, { run: RUN }, recalc).then(function (res) {
                if (res && res.success) { HRMS.reload(); }
            });
            return;
        }
        var reval = ev.target.closest("[data-run-revalidate]");
        if (reval) {
            post(urls.revalidate, { run: RUN }, reval).then(function (res) {
                if (res && res.success) { HRMS.reload(); }
            });
        }
    });

    /* ========================================================================
     * Employee list with expandable lines (Create step 2 and the Register)
     * ===================================================================== */

    var grid = null;

    function EmployeeGrid(root, options) {
        var self = this;
        this.root = root;
        this.slot = $("[data-employees-slot]", root);
        this.mode = root.getAttribute("data-mode") || "register";
        this.state = { filter: "", search: "", page: 1 };
        this.expanded = {};
        this.selected = {};
        this.options = options || {};
        this.components = null;

        var search = $("[data-emp-search]", root);
        if (search) {
            search.addEventListener("input", debounce(function () { self.state.search = search.value.trim(); self.state.page = 1; self.reload(); }, 300));
        }
        var filter = $("[data-emp-filter]", root);
        if (filter) {
            filter.addEventListener("change", function () { self.state.filter = filter.value; self.state.page = 1; self.reload(); });
        }
        var expandAll = $("[data-lines-expand-all]", root);
        if (expandAll) {
            expandAll.addEventListener("click", function () {
                var open = expandAll.getAttribute("aria-pressed") !== "true";
                expandAll.setAttribute("aria-pressed", open ? "true" : "false");
                $("span", expandAll).textContent = expandAll.getAttribute(open ? "data-text-hide" : "data-text-show");
                $all("[data-lines-toggle]", self.slot).forEach(function (btn) { self.setOpen(btn.getAttribute("data-lines-toggle"), open); });
            });
        }

        root.addEventListener("click", function (ev) {
            var pageBtn = ev.target.closest("[data-page]");
            if (pageBtn && self.slot.contains(pageBtn) && !pageBtn.disabled) {
                self.state.page = parseInt(pageBtn.getAttribute("data-page"), 10) || 1;
                self.reload();
                return;
            }
            var tg = ev.target.closest("[data-lines-toggle]");
            if (tg) {
                var id = tg.getAttribute("data-lines-toggle");
                self.setOpen(id, !self.expanded[id]);
                return;
            }
            var add = ev.target.closest("[data-add-line]");
            if (add) { self.addLine(add.closest("[data-line-add]"), add); return; }
            var rm = ev.target.closest("[data-line-remove]");
            if (rm) {
                post(urls.removeline || page.getAttribute("data-urls-removeline"), { run: self.run(), lineId: rm.getAttribute("data-line-remove") }, rm)
                    .then(function (res) { if (res && res.success) { self.reload(true); } });
                return;
            }
            var inc = ev.target.closest("[data-emp-include]");
            if (inc) {
                post(urls.include || page.getAttribute("data-urls-include"), { run: self.run(), employeeId: inc.getAttribute("data-emp-include") }, inc)
                    .then(function (res) { if (res && res.success) { self.reload(true); } });
            }
        });
        root.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-add-cls]")) {
                filterTypes(ev.target.closest("[data-line-add]").querySelector("[data-add-type]"), ev.target.value);
            }
            if (ev.target.matches("[data-emp-check-all]")) {
                $all("[data-emp-check]", self.slot).forEach(function (c) {
                    c.checked = ev.target.checked;
                    self.select(c.closest("tr").getAttribute("data-emp"), c.checked);
                });
                self.syncSelection();
            }
            if (ev.target.matches("[data-emp-check]")) {
                self.select(ev.target.closest("tr").getAttribute("data-emp"), ev.target.checked);
                self.syncSelection();
            }
        });
        root.addEventListener("keydown", function (ev) {
            if (ev.key === "Enter" && ev.target.closest("[data-line-add]") && ev.target.matches("input")) {
                ev.preventDefault();
                self.addLine(ev.target.closest("[data-line-add]"), $("[data-add-line]", ev.target.closest("[data-line-add]")));
            }
        });

        // bulk add
        var bulkBtn = $("[data-bulk-open]", root);
        var bulkModal = $("#bulk-line-modal");
        if (bulkBtn && bulkModal) {
            bulkBtn.addEventListener("click", function () {
                self.loadComponents().then(function (list) {
                    var cls = $("[data-bulk-cls]", bulkModal), type = $("[data-bulk-type]", bulkModal);
                    type.innerHTML = list.map(function (c) {
                        return '<option value="' + c.id + '" data-cls="' + HRMS.escape(c.cls) + '">' + HRMS.escape(c.text) + "</option>";
                    }).join("");
                    filterTypes(type, cls.value);
                    var intro = $("[data-bulk-intro]", bulkModal);
                    intro.textContent = intro.getAttribute("data-text").replace("{0}", Object.keys(self.selected).length);
                    $("[data-bulk-amt]", bulkModal).value = "";
                    $("[data-bulk-com]", bulkModal).value = "";
                    $("[data-bulk-error]", bulkModal).hidden = true;
                    modal(bulkModal).show();
                });
            });
            $("[data-bulk-cls]", bulkModal).addEventListener("change", function (ev) { filterTypes($("[data-bulk-type]", bulkModal), ev.target.value); });
            $("[data-bulk-form]", bulkModal).addEventListener("submit", function (ev) {
                ev.preventDefault();
                var amt = $("[data-bulk-amt]", bulkModal), com = $("[data-bulk-com]", bulkModal);
                var bad = !(num(amt.value) > 0) || !com.value.trim();
                $("[data-bulk-error]", bulkModal).hidden = !bad;
                amt.classList.toggle("is-invalid", !(num(amt.value) > 0));
                com.classList.toggle("is-invalid", !com.value.trim());
                if (bad) { return; }
                post(urls.addline || page.getAttribute("data-urls-addline"), {
                    run: self.run(),
                    employeeIds: Object.keys(self.selected).join(","),
                    componentId: $("[data-bulk-type]", bulkModal).value,
                    amount: amt.value,
                    comment: com.value.trim()
                }, $("[data-bulk-add]", bulkModal)).then(function (res) {
                    if (!res || !res.success) { return; }
                    modal(bulkModal).hide();
                    Object.keys(self.selected).forEach(function (id) { self.expanded[id] = true; });
                    self.selected = {};
                    self.reload(true);
                });
            });
        }
    }

    EmployeeGrid.prototype.run = function () { return this.options.run ? this.options.run() : RUN; };

    EmployeeGrid.prototype.reload = function (all) {
        var self = this;
        var url = withQs(urls.employees || page.getAttribute("data-urls-employees"), {
            run: self.run(), mode: self.mode, filter: self.state.filter, search: self.state.search, page: self.state.page
        });
        var counter = $("[data-emp-count]", self.root);
        return loadInto(self.slot, url).then(function () {
            setCount(self.slot, counter);
            $all("[data-emp-check]", self.slot).forEach(function (c) {
                var id = c.closest("tr").getAttribute("data-emp");
                c.checked = !!self.selected[id];
                c.closest("tr").classList.toggle("is-selected", c.checked);
            });
            Object.keys(self.expanded).forEach(function (id) {
                if (self.expanded[id] && $('[data-lines-for="' + id + '"]', self.slot)) { self.setOpen(id, true); }
            });
            self.syncSelection();
            if (all && self.options.onChange) { self.options.onChange(); }
        });
    };

    EmployeeGrid.prototype.setOpen = function (id, open) {
        var row = $('[data-lines-for="' + id + '"]', this.slot);
        var btn = $('[data-lines-toggle="' + id + '"]', this.slot);
        if (!row || !btn) { return; }
        this.expanded[id] = open;
        row.hidden = !open;
        btn.setAttribute("aria-expanded", open ? "true" : "false");
        btn.closest("tr").classList.toggle("is-open", open);
        if (open) {
            var slot = $("[data-lines-slot]", row);
            loadInto(slot, withQs(urls.lines || page.getAttribute("data-urls-lines"), { run: this.run(), employeeId: id })).then(function () {
                var f = slot && slot.querySelector("[data-line-add]");
                if (f) { filterTypes($("[data-add-type]", f), $("[data-add-cls]", f).value); }
            });
        }
    };

    EmployeeGrid.prototype.select = function (id, on) {
        if (on) { this.selected[id] = true; } else { delete this.selected[id]; }
        var tr = $('tr[data-emp="' + id + '"]', this.slot);
        if (tr) { tr.classList.toggle("is-selected", !!on); }
    };

    EmployeeGrid.prototype.syncSelection = function () {
        var n = Object.keys(this.selected).length;
        var btn = $("[data-bulk-open]", this.root), info = $("[data-emp-selected]", this.root);
        if (btn) { btn.disabled = n === 0; }
        if (info) { info.hidden = n === 0; info.textContent = info.getAttribute("data-text").replace("{0}", n); }
    };

    EmployeeGrid.prototype.loadComponents = function () {
        var self = this;
        if (self.components) { return Promise.resolve(self.components); }
        return HRMS.getJson(withQs(urls.components || page.getAttribute("data-urls-components"), { run: self.run() })).then(function (list) {
            self.components = list;
            return list;
        });
    };

    EmployeeGrid.prototype.addLine = function (f, button) {
        var self = this;
        if (!f) { return; }
        var amt = $("[data-add-amt]", f), com = $("[data-add-com]", f), type = $("[data-add-type]", f);
        var okAmt = num(amt.value) > 0, okCom = !!com.value.trim();
        amt.classList.toggle("is-invalid", !okAmt);
        com.classList.toggle("is-invalid", !okCom);
        if (!okAmt || !okCom || !type.value) {
            HRMS.toast(HRMS.t("js.pr_amount_comment", "Enter an amount and a comment."), "error");
            return;
        }
        var id = f.getAttribute("data-line-add");
        post(urls.addline || page.getAttribute("data-urls-addline"), {
            run: self.run(), employeeIds: id, componentId: type.value, amount: amt.value, comment: com.value.trim()
        }, button).then(function (res) {
            if (res && res.success) { self.expanded[id] = true; self.reload(true); }
        });
    };

    /** The Item type select only offers the types of the chosen class. */
    function filterTypes(select, cls) {
        if (!select) { return; }
        var first = null;
        Array.prototype.forEach.call(select.options, function (o) {
            var ok = !o.getAttribute("data-cls") || o.getAttribute("data-cls") === cls;
            o.hidden = !ok; o.disabled = !ok;
            if (ok && !first) { first = o; }
        });
        var cur = select.options[select.selectedIndex];
        if (!cur || cur.disabled) { select.value = first ? first.value : ""; }
    }

    function refreshSide(runId, mode) {
        var kpis = $("[data-kpis-slot]");
        var excl = $("[data-excluded-slot]");
        var p = [];
        if (kpis) { p.push(loadInto(kpis, withQs(urls.kpis || page.getAttribute("data-urls-kpis"), { run: runId, mode: mode }))); }
        if (excl) { p.push(loadInto(excl, withQs(urls.excluded || page.getAttribute("data-urls-excluded"), { run: runId }))); }
        return Promise.all(p);
    }

    /* ========================================================================
     * Payroll Register
     * ===================================================================== */
    if (PAGE === "register") {
        var regRoot = $("[data-employees]");
        if (regRoot) {
            grid = new EmployeeGrid(regRoot, { onChange: function () { refreshSide(RUN, "register"); } });
            grid.reload();
            loadInto($("[data-excluded-slot]"), withQs(urls.excluded, { run: RUN }));
        }
    }

    /* ========================================================================
     * Payroll Validation
     * ===================================================================== */
    if (PAGE === "validation") {
        var exclSlot = $("[data-excluded-slot]");
        if (exclSlot) {
            loadInto(exclSlot, withQs(urls.excluded, { run: RUN })).then(function () { exclSlot.hidden = !exclSlot.children.length; });
            exclSlot.addEventListener("click", function (ev) {
                var inc = ev.target.closest("[data-emp-include]");
                if (!inc) { return; }
                post(urls.include, { run: RUN, employeeId: inc.getAttribute("data-emp-include") }, inc)
                    .then(function (res) { if (res && res.success) { HRMS.reload(); } });
            });
        }
        var issues = $("[data-issues]");
        var iState = { severity: "", status: "", search: "", page: 1 };
        var iSlot = $("[data-issues-slot]");
        var loadIssues = function () {
            return loadInto(iSlot, withQs(urls.issues, { run: RUN, severity: iState.severity, status: iState.status, search: iState.search, page: iState.page }))
                .then(function () { setCount(iSlot, $("[data-issue-count]")); });
        };
        $("[data-issue-severity]", issues).addEventListener("change", function (ev) { iState.severity = ev.target.value; iState.page = 1; loadIssues(); });
        $("[data-issue-status]", issues).addEventListener("change", function (ev) { iState.status = ev.target.value; iState.page = 1; loadIssues(); });
        $("[data-issue-search]", issues).addEventListener("input", debounce(function (ev) { iState.search = ev.target.value.trim(); iState.page = 1; loadIssues(); }, 300));
        iSlot.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (b && !b.disabled) { iState.page = parseInt(b.getAttribute("data-page"), 10) || 1; loadIssues(); }
        });
        loadIssues();
    }

    /* ========================================================================
     * Payroll Approval
     * ===================================================================== */
    if (PAGE === "approval") {
        var dUrls = $("[data-decision-urls]");
        var comment = $("[data-decision-comment]");
        var dError = $("[data-decision-error]");
        document.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-decision]");
            if (!b || !dUrls) { return; }
            var kind = b.getAttribute("data-decision");
            var text = comment ? comment.value.trim() : "";
            if (kind !== "approve" && !text) {
                if (comment) { comment.classList.add("is-invalid"); comment.focus(); }
                if (dError) { dError.hidden = false; }
                return;
            }
            post(dUrls.getAttribute("data-" + kind), { comment: text }, b).then(function (res) {
                if (!res || !res.success) { return; }
                if (kind === "return") { openRun(RUN); } else { HRMS.reload(); }
            });
        });
    }

    /* ========================================================================
     * Runs list (Payrolls and Payroll History)
     * ===================================================================== */
    var runsCard = $("[data-runs]");
    var loadRuns = null;
    if (runsCard) {
        var rState = { page: 1 };
        var rSlot = $("[data-runs-slot]", runsCard);
        var monthSel = $("[data-runs-month]", runsCard), stageSel = $("[data-runs-stage]", runsCard);
        var yearSel = $("[data-runs-year]", runsCard), typeSel = $("[data-runs-type]", runsCard), rSearch = $("[data-runs-search]", runsCard);
        var pendingChk = $("[data-runs-pending]", runsCard);
        /* "Pending Generate PaySlips": closed payrolls with payslips to generate - the stage list does not apply */
        var syncPending = function () { if (pendingChk && stageSel) { stageSel.disabled = pendingChk.checked; } };
        syncPending();
        if (pendingChk) {
            pendingChk.addEventListener("change", function () {
                syncPending();
                rState.page = 1;
                loadRuns();
                if (window.history && window.history.replaceState) {
                    window.history.replaceState(null, "", pendingChk.checked ? withQs(window.location.pathname, { slips: "pending" }) : window.location.pathname);
                }
            });
        }
        loadRuns = function () {
            return loadInto(rSlot, withQs(runsCard.getAttribute("data-url"), {
                mode: runsCard.getAttribute("data-mode"),
                month: monthSel ? (monthSel.value === "all" ? "" : monthSel.value) : "",
                stage: stageSel ? stageSel.value : "",
                year: yearSel ? yearSel.value : "",
                type: typeSel ? typeSel.value : "",
                search: rSearch ? rSearch.value.trim() : "",
                pending: pendingChk && pendingChk.checked ? "true" : "",
                page: rState.page
            })).then(function () { setCount(rSlot, $("[data-runs-count]", runsCard)); });
        };
        // Payroll History: the Period list only offers the months of the chosen year.
        if (yearSel && monthSel && monthSel.hasAttribute("data-runs-month-of-year")) {
            yearSel.addEventListener("change", function () {
                var y = yearSel.value;
                HRMS.filterOptions(monthSel, function (o) { return o.value === "all" || !y || o.getAttribute("data-year") === y; });
            });
        }
        [monthSel, stageSel, yearSel, typeSel].forEach(function (s) {
            if (s) { s.addEventListener("change", function () { rState.page = 1; loadRuns(); }); }
        });
        if (rSearch) { rSearch.addEventListener("input", debounce(function () { rState.page = 1; loadRuns(); }, 300)); }
        rSlot.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (b && !b.disabled) { rState.page = parseInt(b.getAttribute("data-page"), 10) || 1; loadRuns(); }
        });
        document.addEventListener("click", function (ev) {
            var m = ev.target.closest("[data-runs-filter-month]");
            if (!m || !monthSel) { return; }
            ev.preventDefault();
            var v = m.getAttribute("data-runs-filter-month");
            if (!monthSel.querySelector('option[value="' + v + '"]')) {
                var o = document.createElement("option"); o.value = v; o.textContent = v; monthSel.appendChild(o);
            }
            monthSel.value = v;
            if (stageSel) { stageSel.value = ""; }
            rState.page = 1;
            loadRuns().then(function () { runsCard.scrollIntoView({ behavior: "smooth", block: "start" }); });
        });
        loadRuns();
    }


    /* ========================================================================
     * Payroll Comparison: 2-3 payrolls of one company (first = baseline)
     * ===================================================================== */
    if (PAGE === "compare") {
        var cmpCard = $("[data-cmp]"), cmpSlot = $("[data-cmp-slot]");
        var cmpSelects = $all("[data-cmp-run]");
        var cmpGo = $("[data-cmp-go]"), cmpExport = $("[data-cmp-export]"), cmpError = $("[data-cmp-error]");
        var cmpCompany = $("[data-cmp-company]");

        var picked = function () {
            var ids = [];
            cmpSelects.forEach(function (s) { if (s.value && ids.indexOf(s.value) < 0) { ids.push(s.value); } });
            return ids;
        };
        var showError = function (text) {
            if (!cmpError) { return; }
            cmpError.textContent = text || "";
            cmpError.hidden = !text;
        };
        // stage badge + "not closed" flag under each picker, and no payroll picked twice
        var refreshPickers = function () {
            cmpSelects.forEach(function (sel) {
                var status = $('[data-cmp-status="' + sel.getAttribute("data-cmp-run") + '"]');
                var opt = sel.options[sel.selectedIndex];
                if (status) {
                    status.innerHTML = !opt || !opt.value ? "" :
                        '<span class="hrms-badge hrms-badge--' + HRMS.escape(opt.getAttribute("data-badge") || "muted") + '"><span class="hrms-badge__dot"></span>' +
                        HRMS.escape(opt.getAttribute("data-stage") || "") + "</span>" +
                        (opt.getAttribute("data-closed") === "1" ? "" :
                            '<span class="pr-cmp__flag">' + HRMS.escape(HRMS.t("js.pr_cmp_not_closed", "Not closed - figures can still change")) + "</span>");
                }
                Array.prototype.forEach.call(sel.options, function (o) {
                    if (!o.value) { return; }
                    o.disabled = cmpSelects.some(function (other) { return other !== sel && other.value === o.value; });
                });
                sel.dispatchEvent(new Event("hrms:refresh"));   // searchable dropdown re-reads value and disabled options
            });
            var ids = picked();
            var ok = ids.length >= 2;
            if (cmpExport) {
                cmpExport.classList.toggle("disabled", !ok);
                cmpExport.setAttribute("aria-disabled", ok ? "false" : "true");
                cmpExport.href = ok ? withQs(cmpCard.getAttribute("data-export-url"), { runs: ids.join(",") }) : "#";
            }
            if (ok) { showError(""); }
        };
        var wireResult = function () {
            var emps = $("[data-cmp-emps]", cmpSlot);
            if (!emps) { return; }
            var search = $("[data-cmp-search]", emps), kind = $("[data-cmp-kind]", emps), counter = $("[data-cmp-count]", emps);
            var rows = $all("tbody tr[data-kind]", emps), none = $("[data-cmp-none]", emps);
            var apply = function () {
                var q = search.value.trim().toLowerCase(), k = kind.value, shown = 0;
                rows.forEach(function (tr) {
                    var rk = tr.getAttribute("data-kind");
                    var match = (!k || (k === "diff" ? rk !== "same" : rk === k)) &&
                                (!q || (tr.getAttribute("data-search") || "").indexOf(q) >= 0);
                    tr.hidden = !match;
                    if (match) { shown++; }
                });
                if (none) { none.hidden = shown > 0; }
                if (counter) { counter.textContent = (counter.getAttribute("data-count-text") || "{0} / {1}").replace("{0}", shown).replace("{1}", rows.length); }
            };
            search.addEventListener("input", debounce(apply, 150));
            kind.addEventListener("change", apply);
            apply();
        };
        var compare = function (scroll) {
            var ids = picked();
            if (ids.length < 2) {
                showError(HRMS.t("js.pr_cmp_pick_two", "Choose at least two different payrolls to compare."));
                return Promise.resolve();
            }
            busy(cmpGo, true);
            return loadInto(cmpSlot, withQs(cmpCard.getAttribute("data-grid-url"), { runs: ids.join(",") })).then(function () {
                busy(cmpGo, false);
                wireResult();
                if (window.history && window.history.replaceState) {
                    window.history.replaceState(null, "", withQs(cmpCard.getAttribute("data-page-url"), {
                        company: cmpCard.getAttribute("data-company"), runs: ids.join(",")
                    }));
                }
                if (scroll) { cmpSlot.scrollIntoView({ behavior: "smooth", block: "start" }); }
            }, function () { busy(cmpGo, false); });
        };

        if (cmpCompany) {
            // payrolls are per company: switching company reloads the page with that company's payrolls
            cmpCompany.addEventListener("change", function () {
                HRMS.go(withQs(cmpCard.getAttribute("data-page-url"), { company: cmpCompany.value }));
            });
        }
        cmpSelects.forEach(function (s) { s.addEventListener("change", refreshPickers); });
        if (cmpGo) { cmpGo.addEventListener("click", function () { compare(true); }); }
        var swap = $("[data-cmp-swap]");
        if (swap) {
            // make the second payroll the baseline (A <-> B)
            swap.addEventListener("click", function () {
                if (cmpSelects.length < 2) { return; }
                var a = cmpSelects[0].value;
                cmpSelects[0].value = cmpSelects[1].value;
                cmpSelects[1].value = a;
                refreshPickers();
                if (picked().length >= 2 && $("[data-cmp-result]", cmpSlot)) { compare(false); }
            });
        }
        if (cmpExport) {
            cmpExport.addEventListener("click", function (ev) {
                if (cmpExport.classList.contains("disabled")) {
                    ev.preventDefault();
                    showError(HRMS.t("js.pr_cmp_pick_two", "Choose at least two different payrolls to compare."));
                }
            });
        }
        refreshPickers();
        if (picked().length >= 2) { compare(false); }
    }

    /* ========================================================================
     * Payroll Calendar (calendars) and Period (periods) - two pages sharing
     * the record dialog (_RecordModal)
     * ===================================================================== */
    if (PAGE === "calendars" || PAGE === "pay-periods") {
        var cu = $("[data-cal-urls]");
        var calCard = $("[data-calendars]"), calSlot = $("[data-cal-slot]");
        var perCard = $("[data-periods]"), perSlot = $("[data-period-slot]");
        var noop = function () { return Promise.resolve(); };
        var loadCalendars = noop, loadPeriods = noop;

        if (calCard && calSlot) {
            var cState = { search: "", status: "", page: 1 };
            loadCalendars = function () {
                return loadInto(calSlot, withQs(calCard.getAttribute("data-url"), cState)).then(function () { setCount(calSlot, $("[data-cal-count]")); });
            };
            $("[data-cal-search]").addEventListener("input", debounce(function (ev) { cState.search = ev.target.value.trim(); cState.page = 1; loadCalendars(); }, 300));
            $("[data-cal-status]").addEventListener("change", function (ev) { cState.status = ev.target.value; cState.page = 1; loadCalendars(); });
        }

        var perCal = $("[data-period-calendar]"), perYear = $("[data-period-year]"), perCompany = $("[data-period-company]");
        if (perCard && perSlot) {
            loadPeriods = function () {
                // keep the choice in the address bar (a refresh or a shared link shows the same periods)
                if (window.history && window.history.replaceState) {
                    window.history.replaceState(null, "", withQs(window.location.pathname, { calendar: perCal ? perCal.value : "", year: perYear.value }));
                }
                return loadInto(perSlot, withQs(perCard.getAttribute("data-url"), { calendarId: perCal ? perCal.value : "", year: perYear.value }));
            };
            var allCalOptions = perCal ? Array.prototype.slice.call(perCal.options) : [];
            // the calendar list only offers the calendars of the chosen company
            var fillCalendars = function (keep) {
                if (!perCal || !perCompany) { return; }
                var mine = allCalOptions.filter(function (o) { return o.getAttribute("data-company") === perCompany.value; });
                var wanted = keep && mine.some(function (o) { return o.value === perCal.value; }) ? perCal.value : (mine[0] ? mine[0].value : "");
                perCal.innerHTML = "";
                mine.forEach(function (o) { perCal.appendChild(o); });
                perCal.value = wanted;
                perCal.dispatchEvent(new Event("hrms:refresh"));
            };
            if (perCompany) {
                fillCalendars(true);
                perCompany.addEventListener("change", function () { fillCalendars(false); loadPeriods(); });
            }
            if (perCal) { perCal.addEventListener("change", loadPeriods); }
            perYear.addEventListener("change", loadPeriods);
            var gen = $("[data-periods-generate]");
            if (gen) {
                gen.addEventListener("click", function () {
                    if (!perCal || !perCal.value) { return; }
                    post(gen.getAttribute("data-url"), { calendarId: perCal.value, year: perYear.value }, gen).then(function (res) {
                        if (res && res.success) { loadPeriods(); }
                    });
                });
            }
        }

        // record modal (calendar form / period form)
        var recModal = $("#record-modal");
        var recForm = $("[data-record-form]", recModal);
        var recSave = null;
        var openForm = function (title, url, saveUrl) {
            $("[data-record-title]", recModal).textContent = title;
            var body = $("[data-record-body]", recModal);
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            recSave = saveUrl;
            modal(recModal).show();
            loadInto(body, url).then(syncCalendarForm);
        };
        var syncCalendarForm = function () {
            var freq = $("[data-cal-frequency]", recModal), basis = $("[data-cal-basis]", recModal);
            if (freq) {
                var monthly = freq.value === "MONTHLY";
                $all("[data-freq-monthly]", recModal).forEach(function (el) { el.hidden = !monthly; });
                $all("[data-freq-weekly]", recModal).forEach(function (el) { el.hidden = monthly; });
            }
            if (basis) { $all("[data-basis-fixed]", recModal).forEach(function (el) { el.hidden = basis.value !== "FIXED"; }); }
        };
        recModal.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-cal-frequency], [data-cal-basis]")) { syncCalendarForm(); }
        });
        recForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            $all("[data-valmsg-for]", recModal).forEach(function (s) { s.textContent = ""; });
            $all(".is-invalid", recModal).forEach(function (s) { s.classList.remove("is-invalid"); });
            var fd = new FormData(recForm);
            post(recSave, fd, $("[data-record-save]", recModal)).then(function (res) {
                if (!res) { return; }
                if (res.errors) {
                    Object.keys(res.errors).forEach(function (k) {
                        var s = $('[data-valmsg-for="' + k + '"]', recModal);
                        if (s) { s.textContent = res.errors[k][0]; }
                        var input = recForm.querySelector('[name="' + k + '"]');
                        if (input) { input.classList.add("is-invalid"); }
                    });
                    return;
                }
                if (res.success) {
                    modal(recModal).hide();
                    // a calendar changes the counts in the sidebar - reload; a period only its grid
                    if (recSave === cu.getAttribute("data-save")) { window.setTimeout(function () { HRMS.reload(); }, 400); }
                    else { loadPeriods(); }
                }
            });
        });

        var addBtn = $("[data-cal-add]");
        if (addBtn) {
            addBtn.addEventListener("click", function () { openForm(cu.getAttribute("data-title-new"), cu.getAttribute("data-form"), cu.getAttribute("data-save")); });
        }
        if (calSlot) {
            calSlot.addEventListener("click", function (ev) {
                var b = ev.target.closest("[data-page]");
                if (b && !b.disabled) { cState.page = parseInt(b.getAttribute("data-page"), 10) || 1; loadCalendars(); return; }
                var tr = ev.target.closest("tr[data-id]");
                if (!tr) { return; }
                var id = tr.getAttribute("data-id"), name = tr.getAttribute("data-name");
                if (ev.target.closest("[data-cal-edit]")) {
                    openForm(cu.getAttribute("data-title-edit"), withQs(cu.getAttribute("data-form"), { id: id }), cu.getAttribute("data-save"));
                } else if (ev.target.closest("[data-cal-toggle]")) {
                    post(cu.getAttribute("data-toggle"), { id: id }, ev.target.closest("button")).then(function (res) { if (res && res.success) { HRMS.reload(); } });
                } else if (ev.target.closest("[data-cal-delete]")) {
                    confirmDialog(cu.getAttribute("data-delete-title") + " · " + name, cu.getAttribute("data-delete-calendar"), cu.getAttribute("data-delete-title")).then(function (ok) {
                        if (ok) { post(cu.getAttribute("data-delete"), { id: id }).then(function (res) { if (res && res.success) { HRMS.reload(); } }); }
                    });
                }
            });
        }
        if (perSlot) {
            perSlot.addEventListener("click", function (ev) {
                var tr = ev.target.closest("tr[data-id]");
                if (!tr) { return; }
                var id = tr.getAttribute("data-id");
                if (ev.target.closest("[data-period-edit]")) {
                    openForm(cu.getAttribute("data-title-period"), withQs(cu.getAttribute("data-period-form"), { id: id }), cu.getAttribute("data-period-save"));
                } else if (ev.target.closest("[data-period-delete]")) {
                    confirmDialog(cu.getAttribute("data-delete-title"), cu.getAttribute("data-delete-period"), cu.getAttribute("data-delete-title")).then(function (ok) {
                        if (ok) { post(cu.getAttribute("data-period-delete"), { id: id }).then(function (res) { if (res && res.success) { loadPeriods(); } }); }
                    });
                }
            });
        }

        loadCalendars();
        loadPeriods();
    }

    /* ========================================================================
     * Create Payroll - four-step wizard over a server-side DRAFT
     * ===================================================================== */
    if (PAGE === "create") {
        /* Create Payroll: company + month. Each employee is paid by their own payroll
           calendar (db/60), so one draft payroll is made per calendar in use; steps 2-4
           work on one draft at a time (the switcher above the steps). */
        var u = function (name) { return page.getAttribute("data-urls-" + name); };
        var txt = $("[data-cr-text]");
        var T = function (name) { return txt.getAttribute("data-" + name) || ""; };
        var fmt = function (s) { var a = arguments; return s.replace(/\{(\d+)\}/g, function (m, i) { return a[+i + 1] !== undefined ? a[+i + 1] : m; }); };
        var el = {
            company: $("[data-cr-company]"), month: $("[data-cr-month]"), desc: $("[data-cr-desc]"),
            descReq: $("[data-cr-desc-req]"), descHint: $("[data-cr-desc-hint]"), status: $("[data-cr-status]"),
            list: $("[data-cr-plan-list]"), summary: $("[data-cr-plan-summary]"), empty: $("[data-cr-plan-empty]"),
            unassigned: $("[data-cr-unassigned]"), unassignedText: $("[data-cr-unassigned-text]"), sw: $("[data-cr-switch]"),
            next: $("[data-step-next]"), back: $("[data-step-back]"), finalize: $("[data-cr-finalize]"),
            finalizeText: $("[data-cr-finalize-text]"), discard: $("[data-cr-discard]"), finalList: $("[data-cr-final-list]")
        };
        var resumeList = [];
        try { resumeList = JSON.parse(page.getAttribute("data-resume") || "[]"); } catch (e) { resumeList = []; }
        var st = {
            step: 0, plan: null, current: 0,
            // the drafts made so far: { calendarId, periodId, runId, name, period, employees, code }
            drafts: resumeList.map(function (r) { return { calendarId: r.calendarId, periodId: r.periodId, runId: String(r.runId) }; })
        };
        var runId = function () { var d = st.drafts[st.current]; return d ? String(d.runId) : ""; };

        var type = function () { var r = $('[data-cr-type] input:checked'); return r ? r.value : "REGULAR"; };
        var showError = function (key, on) { var e = $('[data-cr-error="' + key + '"]'); if (e) { e.hidden = !on; } };
        var descRequired = function () { return type() !== "REGULAR"; };
        var syncDesc = function () {
            var req = descRequired();
            el.descReq.hidden = !req;
            el.descHint.textContent = T(req ? "desc-required" : "desc-optional");
            if (!req) { showError("desc", false); el.desc.classList.remove("is-invalid"); }
        };

        /* ---------------------------------------------------------- the plan */
        var rows = function () { return $all("[data-cr-cal]", el.list); };
        var rowOf = function (calendarId) { return $('[data-cr-cal="' + calendarId + '"]', el.list); };
        var calOf = function (id) { return (st.plan ? st.plan.calendars : []).filter(function (c) { return String(c.id) === String(id); })[0]; };

        // which rows can be chosen, and the payroll numbers they will get (in order)
        var syncPlan = function () {
            var chosen = 0, employees = 0;
            var seq = st.plan ? st.plan.nextSeq : 1;
            var prefix = st.plan && st.plan.nextCode ? st.plan.nextCode.replace(/\d+$/, "") : "";
            rows().forEach(function (row) {
                var cal = calOf(row.getAttribute("data-cr-cal"));
                var on = $("[data-cr-cal-on]", row);
                var period = $("[data-cr-cal-period]", row);
                var stateEl = $("[data-cr-cal-state]", row);
                var codeEl = $("[data-cr-cal-code]", row);
                var exists = row.getAttribute("data-regular") || "";
                var blocked = !cal || cal.employees === 0 || !period.value || (exists && type() === "REGULAR");
                on.disabled = blocked;
                if (blocked) { on.checked = false; }
                row.classList.toggle("is-off", !on.checked);
                row.classList.toggle("is-blocked", blocked);
                var badge = function (cls, text) { return '<span class="hrms-badge hrms-badge--' + cls + '"><span class="hrms-badge__dot"></span>' + HRMS.escape(text) + "</span>"; };
                stateEl.innerHTML = !cal || cal.employees === 0 ? badge("muted", T("no-employees"))
                    : !period.value ? badge("warning", T("no-period"))
                    : exists && type() === "REGULAR" ? badge("info", fmt(T("exists"), exists))
                    : on.checked ? badge("success", T("ready")) : "";
                if (on.checked) {
                    codeEl.textContent = prefix ? prefix + (seq < 10 ? "0" + seq : String(seq)) : "";
                    seq++; chosen++; employees += cal.employees;
                } else {
                    codeEl.textContent = "";
                }
            });
            el.summary.textContent = chosen ? fmt(T("summary"), chosen, employees) : "";
            showError("plan", false);
            syncDesc();
        };

        var renderPlan = function (plan) {
            st.plan = plan;
            // months
            var want = el.month.value || page.getAttribute("data-month") || plan.month;
            el.month.innerHTML = plan.months.map(function (m) {
                return '<option value="' + m.value + '"' + (m.value === (plan.month || want) ? " selected" : "") + ">" + HRMS.escape(m.text) + "</option>";
            }).join("");
            showError("month", plan.months.length === 0);

            // one row per calendar: the ones that pay someone first
            var resumed = {};
            st.drafts.forEach(function (d) { resumed[String(d.calendarId)] = d; });
            el.list.innerHTML = plan.calendars.map(function (c) {
                var r = resumed[String(c.id)];
                var periodId = r && r.periodId ? r.periodId : c.periodId;
                var meta = [c.frequency, c.employees === 1 ? T("one-employee") : fmt(T("employees"), c.employees)];
                if (c.unassigned > 0) { meta.push(fmt(T("incl-unassigned"), c.unassigned)); }
                var checked = c.employees > 0 && c.periodId && (resumeList.length ? !!r : !(c.regular && type() === "REGULAR"));
                return '<div class="cr-cal" role="listitem" data-cr-cal="' + c.id + '" data-regular="' + HRMS.escape(c.regular || "") + '">' +
                    '<label class="cr-cal__pick"><input type="checkbox" class="form-check-input" data-cr-cal-on' + (checked ? " checked" : "") +
                        ' aria-label="' + HRMS.escape(c.name) + '" /></label>' +
                    '<div class="cr-cal__info"><strong>' + HRMS.escape(c.name) + "</strong>" +
                        (c.isDefault ? ' <span class="cr-cal__default">' + HRMS.escape(T("default")) + "</span>" : "") +
                        '<span class="cr-cal__meta">' + HRMS.escape(meta.join(" · ")) + "</span></div>" +
                    '<div class="cr-cal__period"><select class="form-select form-select-sm" data-cr-cal-period aria-label="' + HRMS.escape(T("period")) + '"' +
                        (c.periods.length ? "" : " disabled") + ">" +
                        c.periods.map(function (p) {
                            return '<option value="' + p.id + '"' + (String(p.id) === String(periodId) ? " selected" : "") + ">" +
                                HRMS.escape(p.text + " · " + p.dates + " · " + p.statusText) + "</option>";
                        }).join("") + "</select></div>" +
                    '<div class="cr-cal__code"><span class="hrms-code-chip" data-cr-cal-code></span></div>' +
                    '<div class="cr-cal__state" data-cr-cal-state></div>' +
                "</div>";
            }).join("");
            el.empty.hidden = plan.calendars.some(function (c) { return c.employees > 0 && c.periodId; });

            // employees with no payroll calendar
            var link = ' <a href="' + HRMS.escape(T("assign-link")) + '">' + "&rarr;</a>";
            if (!plan.calendarsReady) {
                el.unassignedText.textContent = T("not-ready");
                el.unassigned.hidden = false;
            } else if ((plan.unassigned > 0 && !plan.hasDefault) || plan.onInactive > 0) {
                var lines = [];
                if (plan.unassigned > 0 && !plan.hasDefault) { lines.push(fmt(T("unassigned-none"), plan.unassigned)); }
                if (plan.onInactive > 0) { lines.push(fmt(T("on-inactive"), plan.onInactive)); }
                el.unassignedText.innerHTML = lines.map(HRMS.escape).join("<br>") + link;
                el.unassigned.hidden = false;
            } else if (plan.unassigned > 0) {
                el.unassignedText.innerHTML = HRMS.escape(fmt(T("unassigned-default"), plan.unassigned)) + link;
                el.unassigned.hidden = false;
            } else {
                el.unassigned.hidden = true;
            }
            syncPlan();
        };

        var loadPlan = function () {
            el.list.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            return HRMS.getJson(withQs(u("plan"), { companyId: el.company.value, month: el.month.value || page.getAttribute("data-month") }))
                .then(renderPlan, fail);
        };

        // a period changed: does it already have a regular payroll?
        el.list.addEventListener("change", function (ev) {
            var period = ev.target.closest("[data-cr-cal-period]");
            if (period) {
                var row = period.closest("[data-cr-cal]");
                HRMS.getJson(withQs(u("next"), { periodId: period.value })).then(function (n) {
                    row.setAttribute("data-regular", n && n.ok && n.regular ? n.regular : "");
                    if (n && n.ok && !n.regular && type() === "REGULAR") { $("[data-cr-cal-on]", row).checked = true; }
                    syncPlan();
                });
                return;
            }
            if (ev.target.closest("[data-cr-cal-on]")) { syncPlan(); }
        });

        el.company.addEventListener("change", function () {
            el.month.value = "";
            page.setAttribute("data-month", "");
            HRMS.getJson(withQs(u("calendars"), { companyId: el.company.value })).then(function (data) {
                var fill = function (select, list) {
                    var first = select.querySelector('option[value=""]');
                    select.innerHTML = (first ? first.outerHTML : "") + list.map(function (x) {
                        return '<option value="' + x.id + '">' + HRMS.escape(x.text) + "</option>";
                    }).join("");
                };
                fill($('[data-cr-scope="ScopeDepartmentId"]'), data.departments);
                fill($('[data-cr-scope="ScopeWorkLocationId"]'), data.locations);
            });
            loadPlan();
        });
        el.month.addEventListener("change", loadPlan);
        $("[data-cr-type]").addEventListener("change", function () {
            $all("[data-cr-type] label").forEach(function (l) { l.classList.toggle("is-selected", !!$("input:checked", l)); });
            // a regular payroll skips periods that already have one; an off-cycle one may take them
            rows().forEach(function (row) {
                var on = $("[data-cr-cal-on]", row);
                if (type() !== "REGULAR" && row.getAttribute("data-regular") && !on.checked) { on.checked = true; }
            });
            syncPlan();
        });
        el.desc.addEventListener("input", function () { if (el.desc.value.trim()) { showError("desc", false); el.desc.classList.remove("is-invalid"); } });

        /* -------------------------------------------------------- the drafts */
        var stamp = function () {
            var now = new Date();
            el.status.textContent = fmt(T("saved"), ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2));
        };
        var remember = function () {
            var ids = st.drafts.map(function (d) { return d.runId; }).join(",");
            if (window.history && window.history.replaceState) {
                window.history.replaceState(null, "", window.location.pathname + (ids ? "?drafts=" + ids : ""));
            }
            el.discard.hidden = !ids;
        };

        // one draft per chosen calendar (kept in sync: new ones made, unchosen ones discarded)
        var saveDrafts = function () {
            var chosen = rows().filter(function (row) { return $("[data-cr-cal-on]", row).checked; }).map(function (row) {
                var cal = calOf(row.getAttribute("data-cr-cal"));
                var period = $("[data-cr-cal-period]", row);
                return {
                    calendarId: cal.id, periodId: period.value, name: cal.name, employees: cal.employees,
                    period: period.options[period.selectedIndex] ? period.options[period.selectedIndex].text.split(" · ")[0] : "",
                    code: $("[data-cr-cal-code]", row).textContent
                };
            });
            var scope = {};
            $all("[data-cr-scope]").forEach(function (s) { scope[s.getAttribute("data-cr-scope")] = s.value; });
            var old = st.drafts.slice();
            var made = [];
            el.status.textContent = T("calculating");
            busy(el.next, true);

            var chain = Promise.resolve(true);
            chosen.forEach(function (c) {
                chain = chain.then(function (ok) {
                    if (!ok) { return false; }
                    var prev = old.filter(function (d) { return String(d.calendarId) === String(c.calendarId); })[0];
                    var p = Object.assign({
                        PayrollRunId: prev ? prev.runId : "", CompanyId: el.company.value, PayrollCalendarId: c.calendarId,
                        PayrollPeriodId: c.periodId, RunType: type(), Description: el.desc.value.trim()
                    }, scope);
                    return HRMS.post(u("draft"), form(p)).then(function (res) {
                        if (!res || !res.success) {
                            HRMS.toast((res && res.message) || HRMS.t("js.pr_failed", "The request could not be completed."), "error");
                            // keep what is already saved, so nothing is left behind
                            if (prev) { made.push(prev); }
                            return false;
                        }
                        made.push(Object.assign({}, c, { runId: String(res.id) }));
                        return true;
                    });
                });
            });
            return chain.then(function (ok) {
                // drafts of calendars no longer chosen are discarded
                var keep = made.map(function (d) { return d.runId; });
                var drop = ok ? old.filter(function (d) { return keep.indexOf(String(d.runId)) < 0; }) : [];
                return Promise.all(drop.map(function (d) { return HRMS.post(u("discard"), form({ run: d.runId })); })).then(function () {
                    busy(el.next, false);
                    st.drafts = made;
                    if (st.current >= st.drafts.length) { st.current = 0; }
                    remember();
                    if (ok) { stamp(); } else { el.status.textContent = ""; }
                    return ok;
                });
            }, function (error) { busy(el.next, false); el.status.textContent = ""; fail(error); return false; });
        };

        /* ------------------------------------------- one draft at a time (2-4) */
        var renderSwitch = function () {
            var show = st.step > 0 && st.drafts.length > 0;
            el.sw.hidden = !show;
            if (!show) { return; }
            el.sw.innerHTML = st.drafts.map(function (d, i) {
                return '<button type="button" class="cr-switch__item' + (i === st.current ? " is-active" : "") + '" role="tab" aria-selected="' +
                    (i === st.current ? "true" : "false") + '" data-cr-switch-to="' + i + '">' +
                    '<span class="cr-switch__name">' + HRMS.escape(d.name || "") + "</span>" +
                    '<span class="cr-switch__meta">' + HRMS.escape([d.period, d.code].filter(Boolean).join(" · ")) + "</span></button>";
            }).join("") + (st.drafts.length > 1 && st.step < 3 ? '<span class="cr-switch__hint">' + HRMS.escape(T("switch-hint")) + "</span>" : "");
        };
        el.sw.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-cr-switch-to]");
            if (!b) { return; }
            st.current = parseInt(b.getAttribute("data-cr-switch-to"), 10) || 0;
            empGrid.components = null; empGrid.state.page = 1;
            goStep(st.step);
        });

        var empRoot = $("[data-employees]");
        var empGrid = new EmployeeGrid(empRoot, { run: runId, onChange: function () { refreshSide(runId(), "create"); } });
        grid = empGrid;

        // the scope (department, location, ...) applies to every payroll made here
        $all("[data-cr-scope]").forEach(function (s) {
            s.addEventListener("change", function () {
                saveDrafts().then(function (ok) {
                    if (ok) { empGrid.components = null; empGrid.state.page = 1; empGrid.reload(); refreshSide(runId(), "create"); }
                });
            });
        });

        var show = function (step) {
            st.step = step;
            $all("[data-step-pane]").forEach(function (p) { p.hidden = parseInt(p.getAttribute("data-step-pane"), 10) !== step; });
            $all("[data-step-head]").forEach(function (h) {
                var i = parseInt(h.getAttribute("data-step-head"), 10);
                h.classList.toggle("is-active", i === step);
                h.classList.toggle("is-complete", i < step);
                var circle = $(".hrms-wizard-step__circle", h);
                circle.innerHTML = i < step
                    ? '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><polyline points="4,12 9,17 20,6"/></svg>'
                    : String(i + 1);
            });
            el.back.disabled = step === 0;
            el.next.hidden = step === 3;
            el.finalize.hidden = step !== 3;
            el.finalizeText.textContent = st.drafts.length > 1 ? fmt(T("create-n"), st.drafts.length) : T("create-one");
            renderSwitch();
            window.scrollTo({ top: 0, behavior: "smooth" });
        };

        // step 4: every payroll that will be created, with its totals
        var renderFinal = function () {
            $("[data-cr-final-title]").textContent = st.drafts.length > 1 ? fmt(T("final-title-n"), st.drafts.length) : $("[data-cr-final-title]").textContent;
            el.finalList.innerHTML = st.drafts.map(function (d, i) {
                return '<section class="cr-final__item" data-cr-final="' + i + '">' +
                    '<header class="cr-final__head"><span class="pr-runname-big">' + HRMS.escape(d.code || "") + "</span>" +
                    '<span class="cr-final__meta">' + HRMS.escape([d.name, d.period].filter(Boolean).join(" · ")) + "</span>" +
                    '<span class="cr-final__state" data-cr-final-state></span></header>' +
                    '<div data-cr-final-kpis></div></section>';
            }).join("");
            return Promise.all(st.drafts.map(function (d, i) {
                return loadInto($('[data-cr-final="' + i + '"] [data-cr-final-kpis]', el.finalList), withQs(u("kpis"), { run: d.runId, mode: "final" }));
            }));
        };

        var goStep = function (step) {
            if (step === 1) {
                return Promise.all([empGrid.reload(), refreshSide(runId(), "create")]).then(function () { show(1); });
            }
            if (step === 2) {
                return loadInto($("[data-check-slot]"), withQs(u("check"), { run: runId() })).then(function () { show(2); });
            }
            if (step === 3) {
                show(3);
                return renderFinal();
            }
            show(step);
            return Promise.resolve();
        };

        el.next.addEventListener("click", function () {
            if (st.step === 0) {
                if (!el.month.value) { showError("month", true); return; }
                var any = rows().some(function (row) { return $("[data-cr-cal-on]", row).checked; });
                if (!any) { showError("plan", true); el.list.scrollIntoView({ behavior: "smooth", block: "center" }); return; }
                if (descRequired() && !el.desc.value.trim()) {
                    showError("desc", true); el.desc.classList.add("is-invalid"); el.desc.focus(); return;
                }
                saveDrafts().then(function (ok) { if (ok) { st.current = 0; empGrid.components = null; goStep(1); } });
                return;
            }
            goStep(st.step + 1);
        });
        el.back.addEventListener("click", function () { if (st.step > 0) { goStep(st.step - 1); } });
        document.addEventListener("click", function (ev) {
            var g = ev.target.closest("[data-goto-step]");
            if (g) { ev.preventDefault(); goStep(parseInt(g.getAttribute("data-goto-step"), 10)); return; }
            var f = ev.target.closest("[data-goto-filter]");
            if (f) {
                ev.preventDefault();
                var sel = $("[data-emp-filter]", empRoot);
                sel.value = f.getAttribute("data-goto-filter");
                empGrid.state.filter = sel.value;
                goStep(1);
            }
        });

        // create every draft, one after the other; stop at the first that cannot be created
        el.finalize.addEventListener("click", function () {
            var created = [];
            busy(el.finalize, true);
            var chain = Promise.resolve(true);
            st.drafts.forEach(function (d, i) {
                chain = chain.then(function (ok) {
                    if (!ok) { return false; }
                    el.status.textContent = fmt(T("creating"), i + 1, st.drafts.length);
                    return HRMS.post(u("finalize"), form({ run: d.runId })).then(function (res) {
                        var stateEl = $('[data-cr-final="' + i + '"] [data-cr-final-state]', el.finalList);
                        if (res && res.success) {
                            created.push(d.runId);
                            if (stateEl) { stateEl.innerHTML = '<span class="hrms-badge hrms-badge--success"><span class="hrms-badge__dot"></span>' + HRMS.escape(res.message || "") + "</span>"; }
                            return true;
                        }
                        HRMS.toast((res && res.message) || HRMS.t("js.pr_failed", "The request could not be completed."), "error");
                        st.current = i;
                        if (res && res.errorCode === "DESCRIPTION_REQUIRED") {
                            goStep(0).then(function () { showError("desc", true); el.desc.classList.add("is-invalid"); el.desc.focus(); });
                        } else if (res && (res.errorCode === "REGULAR_EXISTS" || res.errorCode === "PERIOD_CLOSED")) {
                            goStep(0).then(loadPlan);
                        } else if (res && res.errorCode === "NO_EMPLOYEES") {
                            goStep(1);
                        }
                        return false;
                    });
                });
            });
            chain.then(function (ok) {
                busy(el.finalize, false);
                // the created ones leave the draft list
                st.drafts = st.drafts.filter(function (d) { return created.indexOf(d.runId) < 0; });
                if (st.current >= st.drafts.length) { st.current = 0; }
                remember();
                if (!ok) { el.status.textContent = created.length ? fmt(T("created"), created.length) : ""; renderSwitch(); return; }
                if (created.length === 1) { openRun(created[0]); return; }
                window.location.href = u("payrolls");
            }, function (error) { busy(el.finalize, false); fail(error); });
        });

        var discard = function (ids, button) {
            return confirmDialog(button.textContent.trim(), HRMS.t("js.pr_discard_drafts", "Discard these drafts? The lines added in them are removed."), button.textContent.trim())
                .then(function (ok) {
                    if (!ok) { return; }
                    busy(button, true);
                    Promise.all(ids.map(function (id) { return HRMS.post(u("discard"), form({ run: id })); })).then(function () {
                        window.location.href = u("create");
                    }, function (error) { busy(button, false); fail(error); });
                });
        };
        el.discard.addEventListener("click", function () {
            var ids = st.drafts.map(function (d) { return d.runId; });
            if (ids.length) { discard(ids, el.discard); }
        });
        $all("[data-draft-discard]").forEach(function (b) {
            b.addEventListener("click", function () { discard(b.getAttribute("data-draft-discard").split(","), b); });
        });

        // first paint: the plan; a resumed set of drafts goes straight to step 2
        if (st.drafts.length) { el.discard.hidden = false; }
        syncDesc();
        (el.company && el.company.value ? loadPlan() : Promise.resolve()).then(function () {
            if (!st.drafts.length) { return; }
            // names / periods / numbers of the resumed drafts come from the plan rows
            st.drafts.forEach(function (d) {
                var row = rowOf(d.calendarId), cal = calOf(d.calendarId);
                if (!row || !cal) { return; }
                var period = $("[data-cr-cal-period]", row);
                d.name = cal.name; d.employees = cal.employees;
                d.period = period.options[period.selectedIndex] ? period.options[period.selectedIndex].text.split(" · ")[0] : "";
                d.code = $("[data-cr-cal-code]", row).textContent;
            });
            goStep(1);
        });
    }
    /* ========================================================================
     * Pay Items - one list of salary, earnings, deductions and loans
     * ===================================================================== */
    if (PAGE === "payitems") {
        var pu = function (name) { return page.getAttribute("data-urls-" + name); };
        var pt = function (name) { return page.getAttribute("data-text-" + name) || ""; };
        var withId = function (url, id) { return url.replace(/\/0(\?|$)/, "/" + id + "$1"); };
        var piSlot = $("[data-pi-slot]"), piCount = $("[data-pi-count]"), piKpis = $("[data-pi-kpis]"), piEmpCard = $("[data-pi-employee]");
        var piEmp = $("[data-pi-emp]"), piStatus = $("[data-pi-status]"), piSearch = $("[data-pi-search]");
        var pState = { search: "", emp: piEmp.value, cls: "", status: piStatus.value, page: 1 };

        var loadItems = function () {
            return loadInto(piSlot, withQs(pu("grid"), pState)).then(function () { setCount(piSlot, piCount); });
        };
        var loadKpis = function () { return loadInto(piKpis, pu("kpis")); };
        var loadEmpCard = function () {
            if (!pState.emp) { piEmpCard.innerHTML = ""; return Promise.resolve(); }
            return loadInto(piEmpCard, withId(pu("employee"), pState.emp));
        };
        HRMS.payItemsRefresh = function () { loadItems(); loadKpis(); loadEmpCard(); };

        piSearch.addEventListener("input", debounce(function () { pState.search = piSearch.value.trim(); pState.page = 1; loadItems(); }, 300));
        piEmp.addEventListener("change", function () {
            pState.emp = piEmp.value; pState.page = 1; loadItems(); loadEmpCard();
            var url = new URL(window.location.href);
            if (pState.emp) { url.searchParams.set("emp", pState.emp); } else { url.searchParams.delete("emp"); }
            window.history.replaceState(null, "", url.toString());
        });
        piStatus.addEventListener("change", function () { pState.status = piStatus.value; pState.page = 1; loadItems(); });
        $all("[data-pi-class] input").forEach(function (r) {
            r.addEventListener("change", function () { pState.cls = r.value; pState.page = 1; loadItems(); });
        });
        piKpis.addEventListener("click", function (ev) {
            if (!ev.target.closest("[data-pi-show-pending]")) { return; }
            piStatus.value = "PENDING"; pState.status = "PENDING"; pState.page = 1; loadItems();
            $("[data-pi-list]").scrollIntoView({ behavior: "smooth", block: "start" });
        });

        /* ---- the add / edit form ---- */
        var piModal = $("#pi-modal"), piForm = $("[data-pi-form]"), piBody = $("[data-pi-form-body]");
        var figures = null;

        var syncForm = function () {
            var root = piBody;
            var clsInput = $("[data-pi-class-choice] input:checked", root);
            var cls = clsInput ? clsInput.value : "EARNING";
            $all("[data-pi-class-choice] label", root).forEach(function (l) { l.classList.toggle("is-selected", !!$("input:checked", l)); });

            var empSel = $("[data-pi-employee]", root);
            var empOpt = empSel && empSel.options[empSel.selectedIndex];
            var company = empOpt ? empOpt.getAttribute("data-company") : null;

            // item types of this class and of the employee's company
            var typeSel = $("[data-pi-type]", root);
            var firstOk = null;
            Array.prototype.forEach.call(typeSel.options, function (o) {
                var c = o.getAttribute("data-cls");
                if (!c) { return; }
                var ok = c === cls && (!company || o.getAttribute("data-company") === company);
                o.hidden = !ok; o.disabled = !ok && !typeSel.disabled;
                if (ok && !firstOk) { firstOk = o; }
            });
            var cur = typeSel.options[typeSel.selectedIndex];
            if (!typeSel.disabled && (!cur || cur.hidden)) { typeSel.value = firstOk ? firstOk.value : ""; }

            // applies: instalments only for deductions
            var appliesSel = $("[data-pi-applies]", root);
            Array.prototype.forEach.call(appliesSel.options, function (o) {
                var only = o.getAttribute("data-cls-only");
                o.hidden = !!only && only !== cls; o.disabled = o.hidden;
            });
            if (appliesSel.options[appliesSel.selectedIndex].hidden) { appliesSel.value = "ONCE"; }
            var applies = cls === "SALARY" ? "MONTHLY" : cls === "LOAN" ? "INSTALMENT" : appliesSel.value;

            $all("[data-show-for]", root).forEach(function (el) {
                var forCls = (" " + el.getAttribute("data-show-for") + " ").indexOf(" " + cls + " ") >= 0;
                var forApplies = !el.hasAttribute("data-show-applies") || el.getAttribute("data-show-applies") === applies;
                el.hidden = !(forCls && forApplies);
            });
            var fromLabel = $("[data-pi-from-label]", root);
            if (fromLabel) { fromLabel.textContent = fromLabel.getAttribute(applies === "ONCE" ? "data-once" : "data-many"); }
            var amtLabel = $("[data-pi-amount-label]", root), amt = $("[data-pi-amount]", root);
            if (amtLabel && amt) { amtLabel.textContent = amt.getAttribute(applies === "INSTALMENT" ? "data-label-instalment" : "data-label-default"); }

            // the posted values for this class
            var startSel = $all("[data-pi-start]", root).filter(function (s) {
                return (" " + s.getAttribute("data-pi-start") + " ").indexOf(" " + cls + " ") >= 0;
            })[0];
            var countIn = $('[data-pi-count="' + (cls === "LOAN" ? "LOAN" : "DEDUCTION") + '"]', root);
            var outApplies = $('[data-pi-out="applies"]', root), outStart = $('[data-pi-out="start"]', root), outCount = $('[data-pi-out="count"]', root);
            if (outApplies && outApplies.name) { outApplies.value = applies; }
            if (outStart && outStart.name && startSel) { outStart.value = startSel.value; }
            if (outCount && outCount.name) { outCount.value = applies === "INSTALMENT" && countIn ? countIn.value : ""; }
            var until = $("[data-pi-until]", root);
            if (until) { until.disabled = applies !== "MONTHLY" || cls === "SALARY" || cls === "LOAN"; }

            // deduction in instalments: the total
            var dedTotal = $("[data-pi-ded-total]", root);
            if (dedTotal) {
                var a = num(amt && amt.value), n = parseInt(countIn && countIn.value, 10);
                dedTotal.textContent = cls === "DEDUCTION" && applies === "INSTALMENT" && a > 0 && n > 0
                    ? HRMS.t("js.pi_total_n", "Total {0}", fmt(a * n)) : "";
            }
            if (cls === "LOAN") { loanChecks(); }
        };

        var fmt = function (v) {
            var s = Math.abs(v).toFixed(3).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
            return (v < 0 ? "-" : "") + s;
        };
        var setCheck = function (li, state, meta) {
            if (!li) { return; }
            var icon = $(".pr-check__icon", li);
            icon.classList.remove("is-ok", "is-warn", "is-err");
            icon.classList.add("is-" + state);
            $("[data-pi-check-meta]", li).textContent = meta;
        };
        var loanChecks = function () {
            var root = piBody;
            var total = num($("[data-pi-total]", root).value), n = parseInt($('[data-pi-count="LOAN"]', root).value, 10);
            var monthly = total > 0 && n > 0 ? Math.round(total / n * 1000) / 1000 : 0;
            $("[data-pi-loan-monthly]", root).textContent = monthly ? fmt(monthly) : "—";
            var capLi = $('[data-pi-check="cap"]', root), shareLi = $('[data-pi-check="share"]', root);
            if (!figures || !(figures.monthlySalary > 0)) {
                setCheck(capLi, "warn", HRMS.t("js.pi_no_salary", "No active salary items for this employee"));
                setCheck(shareLi, "warn", "—");
                return;
            }
            var cap = figures.monthlySalary * 3;
            setCheck(capLi, total <= cap ? "ok" : "warn", fmt(total || 0) + (total <= cap ? " ≤ " : " > ") + fmt(cap));
            var share = Math.round((monthly + (figures.monthlyDeductions || 0)) / figures.monthlySalary * 100);
            setCheck(shareLi, share <= 50 ? "ok" : "warn", HRMS.t("js.pi_share", "{0}% of salary · limit 50%", share));
        };
        var loadFigures = function () {
            var empSel = $("[data-pi-employee]", piBody);
            figures = null;
            if (!empSel || !empSel.value) { syncForm(); return; }
            HRMS.getJson(withId(pu("figures"), empSel.value)).then(function (f) { figures = f; syncForm(); }, function () { syncForm(); });
        };

        var openItemForm = function (id, title) {
            $("[data-pi-form-title]").textContent = title;
            piBody.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            modal(piModal).show();
            var params = id ? { id: id } : { emp: pState.emp, cls: pState.cls };
            loadInto(piBody, withQs(pu("form"), params)).then(function () {
                var mode = ($("[data-pi-mode]", piBody) || page).getAttribute("data-pi-mode");
                if (mode === "revise") { $("[data-pi-form-title]").textContent = pt("revise"); }
                loadFigures();
            });
        };
        piBody.addEventListener("change", function (ev) {
            if (ev.target.matches("[data-pi-employee]")) { loadFigures(); return; }
            syncForm();
        });
        piBody.addEventListener("input", function (ev) {
            if (ev.target.matches("[data-pi-total], [data-pi-count], [data-pi-amount]")) { syncForm(); }
        });
        piForm.addEventListener("submit", function (ev) {
            ev.preventDefault();
            syncForm();
            var fd = new FormData(piForm);
            ["Amount", "TotalAmount"].forEach(function (k) {
                var v = fd.get(k);
                if (v !== null) { fd.set(k, String(v).replace(/,/g, "").trim()); }
            });
            ["StartMonth", "EndMonth"].forEach(function (k) {
                var v = fd.get(k);
                if (v) { fd.set(k, v + "-01"); }
            });
            post(pu("save"), fd, $("[data-pi-save]")).then(function (res) {
                if (res && res.success) { modal(piModal).hide(); HRMS.payItemsRefresh(); }
            });
        });
        var addBtn = $("[data-pi-add]");
        if (addBtn) { addBtn.addEventListener("click", function () { openItemForm(0, pt("new")); }); }

        /* ---- row actions ---- */
        var piHistoryModal = $("#pi-history-modal"), piEndModal = $("#pi-end-modal");
        var endFor = null;
        piSlot.addEventListener("click", function (ev) {
            var b = ev.target.closest("[data-page]");
            if (b && !b.disabled) { pState.page = parseInt(b.getAttribute("data-page"), 10) || 1; loadItems(); return; }
            var tr = ev.target.closest("tr[data-id]");
            if (!tr) { return; }
            var id = tr.getAttribute("data-id"), name = tr.getAttribute("data-name");
            if (ev.target.closest("[data-pi-edit]")) {
                openItemForm(id, pt("edit"));
            } else if (ev.target.closest("[data-pi-history]")) {
                var hb = $("[data-pi-history-body]");
                hb.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
                modal(piHistoryModal).show();
                loadInto(hb, withId(pu("history"), id));
            } else if (ev.target.closest("[data-pi-approve]")) {
                var ab = ev.target.closest("[data-pi-approve]");
                confirmDialog(pt("approve-title") + " · " + name, pt("approve"), pt("approve-title")).then(function (ok) {
                    if (ok) { post(pu("approve"), { id: id }, ab).then(function (res) { if (res && res.success) { HRMS.payItemsRefresh(); } }); }
                });
            } else if (ev.target.closest("[data-pi-delete]")) {
                confirmDialog(pt("delete-title") + " · " + name, pt("delete"), pt("delete-title")).then(function (ok) {
                    if (ok) { post(pu("delete"), { id: id }).then(function (res) { if (res && res.success) { HRMS.payItemsRefresh(); } }); }
                });
            } else if (ev.target.closest("[data-pi-end]")) {
                endFor = id;
                var mode = tr.getAttribute("data-mode");
                $("[data-pi-end-what]").textContent = name;
                $("[data-pi-end-monthly]").hidden = mode !== "MONTHLY";
                $("[data-pi-end-instalment]").hidden = mode !== "INSTALMENT";
                $("#pi-end-now").checked = true;
                var sel = $("[data-pi-end-select]");
                sel.disabled = true;
                sel.innerHTML = "";
                // the month it started, up to 12 months ahead
                var start = tr.getAttribute("data-start").split("-"), d = new Date(+start[0], +start[1] - 1, 1), now = new Date();
                var last = new Date(now.getFullYear(), now.getMonth() + 12, 1);
                var months = $all("[data-pi-month-names] span").map(function (s) { return s.textContent; });
                for (; d <= last; d = new Date(d.getFullYear(), d.getMonth() + 1, 1)) {
                    var v = d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0");
                    var o = document.createElement("option");
                    o.value = v;
                    o.textContent = (months[d.getMonth()] || v) + " " + d.getFullYear();
                    if (d.getFullYear() === now.getFullYear() && d.getMonth() === now.getMonth()) { o.selected = true; }
                    sel.appendChild(o);
                }
                $("[data-pi-end-comment]").value = "";
                modal(piEndModal).show();
            }
        });
        piEndModal.addEventListener("change", function (ev) {
            if (ev.target.name === "pi-end-when") { $("[data-pi-end-select]").disabled = !$("#pi-end-month").checked; }
        });
        $("[data-pi-end-form]").addEventListener("submit", function (ev) {
            ev.preventDefault();
            var monthly = !$("[data-pi-end-monthly]").hidden && $("#pi-end-month").checked;
            post(pu("end"), { id: endFor, endMonth: monthly ? $("[data-pi-end-select]").value : "", comment: $("[data-pi-end-comment]").value.trim() },
                 $("[data-pi-end-save]")).then(function (res) {
                if (res && res.success) { modal(piEndModal).hide(); HRMS.payItemsRefresh(); }
            });
        });

        /* ---- export (the current filters) ---- */
        $("[data-pi-export]").addEventListener("click", function () {
            window.location.href = withQs(pu("export"), { search: pState.search, emp: pState.emp, cls: pState.cls, status: pState.status });
        });

        /* ---- import ---- */
        var impForm = $("[data-pi-import-form]");
        if (impForm) {
            var fileIn = $("[data-pi-file]"), drop = $("[data-pi-drop]"), impSave = $("[data-pi-import-save]");
            var fileName = $("[data-pi-file-name]"), defaultName = fileName.textContent;
            var chosen = null;
            var pick = function (f) {
                chosen = f || null;
                fileName.textContent = chosen ? chosen.name : defaultName;
                drop.classList.toggle("has-file", !!chosen);
                impSave.disabled = !chosen;
                $("[data-pi-import-result]").hidden = true;
            };
            fileIn.addEventListener("change", function () { pick(fileIn.files[0]); });
            ["dragenter", "dragover"].forEach(function (n) {
                drop.addEventListener(n, function (ev) { ev.preventDefault(); drop.classList.add("is-over"); });
            });
            ["dragleave", "drop"].forEach(function (n) {
                drop.addEventListener(n, function (ev) { ev.preventDefault(); drop.classList.remove("is-over"); });
            });
            drop.addEventListener("drop", function (ev) { if (ev.dataTransfer && ev.dataTransfer.files.length) { pick(ev.dataTransfer.files[0]); } });
            $("#pi-import-modal").addEventListener("hidden.bs.modal", function () { fileIn.value = ""; pick(null); });
            impForm.addEventListener("submit", function (ev) {
                ev.preventDefault();
                if (!chosen) { return; }
                var fd = new FormData();
                fd.append("file", chosen);
                busy(impSave, true);
                HRMS.post(pu("import"), fd).then(function (res) {
                    busy(impSave, false);
                    if (res && res.success) {
                        HRMS.toast(res.message, "success");
                        modal($("#pi-import-modal")).hide();
                        HRMS.payItemsRefresh();
                        return;
                    }
                    $("[data-pi-import-result]").hidden = false;
                    $("[data-pi-import-message]").textContent = (res && res.message) || HRMS.t("js.pr_failed", "The request could not be completed.");
                    $("[data-pi-import-errors]").innerHTML = ((res && res.errors) || []).map(function (e) {
                        return '<tr><td class="text-center">' + HRMS.escape(e.row === null || e.row === undefined ? "—" : String(e.row)) + "</td><td class=\"pr-neg\">" + HRMS.escape(e.message || "") + "</td></tr>";
                    }).join("");
                }, function (error) { busy(impSave, false); fail(error); });
            });
        }

        // first paint
        loadKpis();
        loadItems();
        loadEmpCard();
    }
})();
