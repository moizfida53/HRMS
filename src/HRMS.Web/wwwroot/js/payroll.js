/* ==========================================================================
 * HRMS Kuwait - Payroll Processing (db/34-35)
 * Payroll Calendar, Create Payroll wizard, Register, Validation, Approval,
 * History. Panels are server-rendered partials (labels from Core.UiLabels);
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
    function openRun(id) { window.location.href = (urls.open || page.getAttribute("data-urls-open") || "/payroll/run/0").replace(/\/0$/, "/" + id); }

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
                if (redirect && RUN) { window.location.href = "/payroll/" + redirect + "?run=" + RUN; }
                else if (refresh === "employees" && grid) { grid.reload(true); }
                else if (refresh === "payitems" && HRMS.payItemsRefresh) { HRMS.payItemsRefresh(); }
                else { window.location.reload(); }
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
                else if (res && res.errorCode === "HAS_ERRORS") { window.setTimeout(function () { window.location.reload(); }, 900); }
            });
            return;
        }
        var recalc = ev.target.closest("[data-run-recalc]");
        if (recalc && urls.recalc) {
            post(urls.recalc, { run: RUN }, recalc).then(function (res) {
                if (res && res.success) { window.location.reload(); }
            });
            return;
        }
        var reval = ev.target.closest("[data-run-revalidate]");
        if (reval) {
            post(urls.revalidate, { run: RUN }, reval).then(function (res) {
                if (res && res.success) { window.location.reload(); }
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
                    .then(function (res) { if (res && res.success) { window.location.reload(); } });
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
                if (kind === "return") { openRun(RUN); } else { window.location.reload(); }
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

    // Compare two payrolls (History)
    var cmp = $("[data-compare]");
    if (cmp && $("[data-compare-run]", cmp)) {
        $("[data-compare-run]", cmp).addEventListener("click", function () {
            loadInto($("[data-compare-slot]", cmp), withQs(cmp.getAttribute("data-url"), { a: $("[data-compare-a]", cmp).value, b: $("[data-compare-b]", cmp).value }));
        });
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
                    if (recSave === cu.getAttribute("data-save")) { window.setTimeout(function () { window.location.reload(); }, 400); }
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
                    post(cu.getAttribute("data-toggle"), { id: id }, ev.target.closest("button")).then(function (res) { if (res && res.success) { window.location.reload(); } });
                } else if (ev.target.closest("[data-cal-delete]")) {
                    confirmDialog(cu.getAttribute("data-delete-title") + " · " + name, cu.getAttribute("data-delete-calendar"), cu.getAttribute("data-delete-title")).then(function (ok) {
                        if (ok) { post(cu.getAttribute("data-delete"), { id: id }).then(function (res) { if (res && res.success) { window.location.reload(); } }); }
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
        var u = function (name) { return page.getAttribute("data-urls-" + name); };
        var txt = $("[data-cr-text]");
        var el = {
            company: $("[data-cr-company]"), calendar: $("[data-cr-calendar]"), period: $("[data-cr-period]"),
            name: $("[data-cr-name]"), nameHint: $("[data-cr-name-hint]"), desc: $("[data-cr-desc]"),
            descReq: $("[data-cr-desc-req]"), descHint: $("[data-cr-desc-hint]"), regular: $("[data-cr-regular-exists]"),
            regularCode: $("[data-cr-regular-code]"), status: $("[data-cr-status]"),
            next: $("[data-step-next]"), back: $("[data-step-back]"), finalize: $("[data-cr-finalize]"), discard: $("[data-cr-discard]")
        };
        var st = { step: 0, runId: page.getAttribute("data-run") || "", next: null };
        var runId = function () { return st.runId; };

        var type = function () { var r = $('[data-cr-type] input:checked'); return r ? r.value : "REGULAR"; };
        var showError = function (key, on) { var e = $('[data-cr-error="' + key + '"]'); if (e) { e.hidden = !on; } };

        var setOptions = function (select, list, selected, empty) {
            select.innerHTML = (empty ? '<option value="">' + HRMS.escape(empty) + "</option>" : "") + list.map(function (x) {
                return '<option value="' + x.id + '"' + (String(x.id) === String(selected) ? " selected" : "") + ">" + HRMS.escape(x.text) + "</option>";
            }).join("");
        };

        var loadPeriodsFor = function () {
            var cal = el.calendar.value;
            showError("calendar", !cal);
            if (!cal) { el.period.innerHTML = ""; return refreshName(); }
            return HRMS.getJson(withQs(u("periods"), { calendarId: cal })).then(function (list) {
                var want = el.period.getAttribute("data-selected");
                // default: the first open period
                if (!want) {
                    // the period of today, else the first one still open
                    var current = list.filter(function (p) { return p.current; })[0];
                    var firstOpen = list.filter(function (p) { return p.status !== "APPROVED"; })[0];
                    want = current ? current.id : (firstOpen ? firstOpen.id : (list[0] ? list[0].id : ""));
                }
                el.period.innerHTML = list.map(function (p) {
                    return '<option value="' + p.id + '"' + (String(p.id) === String(want) ? " selected" : "") + ">" +
                        HRMS.escape(p.text + " · " + p.dates + " · " + p.statusText) + "</option>";
                }).join("");
                el.period.removeAttribute("data-selected");
                showError("period", list.length === 0);
                return refreshName();
            });
        };

        var descRequired = function () { return type() !== "REGULAR" || (st.next && st.next.seq > 1); };
        var refreshName = function () {
            var period = el.period.value;
            if (!period) { el.name.value = ""; st.next = null; syncDesc(); return Promise.resolve(); }
            return HRMS.getJson(withQs(u("next"), { periodId: period })).then(function (n) {
                st.next = n.ok ? n : null;
                el.name.value = n.ok ? n.code : "";
                el.nameHint.textContent = n.ok ? n.hint : "";
                var exists = n.ok && n.regular && type() === "REGULAR";
                el.regular.hidden = !exists;
                if (exists) { el.regularCode.textContent = n.regular; }
                syncDesc();
            });
        };
        var syncDesc = function () {
            var req = descRequired();
            el.descReq.hidden = !req;
            el.descHint.textContent = txt.getAttribute(req ? "data-desc-required" : "data-desc-optional");
            if (!req) { showError("desc", false); el.desc.classList.remove("is-invalid"); }
        };

        el.company.addEventListener("change", function () {
            HRMS.getJson(withQs(u("calendars"), { companyId: el.company.value })).then(function (data) {
                var def = data.calendars.filter(function (c) { return c.isDefault; })[0] || data.calendars[0];
                setOptions(el.calendar, data.calendars, def ? def.id : "");
                setOptions($('[data-cr-scope="ScopeDepartmentId"]'), data.departments, "", $('[data-cr-scope="ScopeDepartmentId"] option[value=""]').textContent);
                setOptions($('[data-cr-scope="ScopeWorkLocationId"]'), data.locations, "", $('[data-cr-scope="ScopeWorkLocationId"] option[value=""]').textContent);
                loadPeriodsFor();
            });
        });
        el.calendar.addEventListener("change", loadPeriodsFor);
        el.period.addEventListener("change", refreshName);
        $("[data-cr-type]").addEventListener("change", function () {
            $all("[data-cr-type] label").forEach(function (l) { l.classList.toggle("is-selected", !!$("input:checked", l)); });
            refreshName();
        });
        el.desc.addEventListener("input", function () { if (el.desc.value.trim()) { showError("desc", false); el.desc.classList.remove("is-invalid"); } });

        var saveDraft = function () {
            var p = {
                PayrollRunId: runId(), CompanyId: el.company.value, PayrollCalendarId: el.calendar.value,
                PayrollPeriodId: el.period.value, RunType: type(), Description: el.desc.value.trim()
            };
            $all("[data-cr-scope]").forEach(function (s) { p[s.getAttribute("data-cr-scope")] = s.value; });
            el.status.textContent = txt.getAttribute("data-calculating");
            return post(u("draft"), p, el.next).then(function (res) {
                if (!res || !res.success) { el.status.textContent = ""; return false; }
                st.runId = String(res.id);
                page.setAttribute("data-run", st.runId);
                if (window.history && window.history.replaceState) {
                    window.history.replaceState(null, "", window.location.pathname + "?draft=" + st.runId);
                }
                var now = new Date();
                el.status.textContent = txt.getAttribute("data-saved").replace("{0}",
                    ("0" + now.getHours()).slice(-2) + ":" + ("0" + now.getMinutes()).slice(-2));
                el.discard.hidden = false;
                return true;
            });
        };

        var empRoot = $("[data-employees]");
        var empGrid = new EmployeeGrid(empRoot, { run: runId, onChange: function () { refreshSide(runId(), "create"); } });
        grid = empGrid;

        $all("[data-cr-scope]").forEach(function (s) {
            s.addEventListener("change", function () {
                saveDraft().then(function (ok) {
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
            window.scrollTo({ top: 0, behavior: "smooth" });
        };

        var goStep = function (step) {
            if (step === 1) {
                return Promise.all([empGrid.reload(), refreshSide(runId(), "create")]).then(function () { show(1); });
            }
            if (step === 2) {
                return loadInto($("[data-check-slot]"), withQs(u("check"), { run: runId() })).then(function () { show(2); });
            }
            if (step === 3) {
                return Promise.all([
                    refreshName(),
                    loadInto($("[data-final-kpis]"), withQs(u("kpis"), { run: runId(), mode: "final" }))
                ]).then(function () { $("[data-cr-final-name]").textContent = el.name.value; show(3); });
            }
            show(step);
            return Promise.resolve();
        };

        el.next.addEventListener("click", function () {
            if (st.step === 0) {
                if (!el.calendar.value) { showError("calendar", true); return; }
                if (!el.period.value) { showError("period", true); return; }
                if (st.next && st.next.regular && type() === "REGULAR") { el.regular.scrollIntoView({ behavior: "smooth" }); return; }
                if (descRequired() && !el.desc.value.trim()) {
                    showError("desc", true); el.desc.classList.add("is-invalid"); el.desc.focus(); return;
                }
                saveDraft().then(function (ok) { if (ok) { empGrid.components = null; goStep(1); } });
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

        el.finalize.addEventListener("click", function () {
            post(u("finalize"), { run: runId() }, el.finalize).then(function (res) {
                if (res && res.success) { openRun(runId()); return; }
                if (res && res.errorCode === "DESCRIPTION_REQUIRED") {
                    goStep(0).then(function () { showError("desc", true); el.desc.classList.add("is-invalid"); el.desc.focus(); });
                } else if (res && (res.errorCode === "REGULAR_EXISTS" || res.errorCode === "PERIOD_CLOSED")) {
                    goStep(0).then(refreshName);
                } else if (res && res.errorCode === "NO_EMPLOYEES") {
                    goStep(1);
                }
            });
        });

        var discard = function (id, button) {
            return confirmDialog(button.textContent.trim(), HRMS.t("js.pr_discard_draft", "Discard this draft? The lines added in it are removed."), button.textContent.trim())
                .then(function (ok) {
                    if (!ok) { return; }
                    post(u("discard"), { run: id }, button).then(function (res) {
                        if (res && res.success) { window.location.href = window.location.pathname; }
                    });
                });
        };
        el.discard.addEventListener("click", function () { if (runId()) { discard(runId(), el.discard); } });
        $all("[data-draft-discard]").forEach(function (b) {
            b.addEventListener("click", function () { discard(b.getAttribute("data-draft-discard"), b); });
        });

        // first paint
        if (runId()) { el.discard.hidden = false; }
        (el.calendar.value ? loadPeriodsFor() : Promise.resolve(showError("calendar", true))).then(function () {
            if (runId()) { goStep(1); }
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
