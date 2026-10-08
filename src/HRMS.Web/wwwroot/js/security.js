/* ==========================================================================
 * HRMS Kuwait - Security: Create Roles and Assign Roles (db/57)
 * The pages are rendered by the server; this script wires them up.
 *
 *   Create Roles   [data-sec-role="ref"]   opens a role's editor (POST, its
 *                                          reference in the body)
 *                  the access matrix       Read / Write / Full per page and
 *                                          function - each level includes the
 *                                          ones below; a page tick applies to
 *                                          its functions; a module tick to its
 *                                          pages; a function needs its page
 *                  save                    posts access=ITEM:R|W|F and
 *                                          approval=APR:L1|L2|SELF
 *   Assign Roles   [data-sec-user="ref"]   opens the user's roles (popup)
 *
 * No database id is put in an address or a posted field - only references.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var FLASH = "hrms-sec-flash";
    var ORDER = { R: 1, W: 2, F: 3 };
    var KEYS = ["R", "W", "F"];

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function failed() { return HRMS.t("js.sec_failed", "The request could not be completed."); }
    var debounce = HRMS.debounce || function (fn, wait) {
        var t; return function () { var a = arguments, s = this; clearTimeout(t); t = setTimeout(function () { fn.apply(s, a); }, wait); };
    };
    function busy(b, on) { if (b) { b.disabled = !!on; b.classList.toggle("is-busy", !!on); } }
    function fd(obj) { var f = new FormData(); Object.keys(obj).forEach(function (k) { if (obj[k] !== null && obj[k] !== undefined) { f.append(k, obj[k]); } }); return f; }
    function store(key, val) { try { if (val === null) { sessionStorage.removeItem(key); } else { sessionStorage.setItem(key, val); } } catch (e) { /* private mode */ } }
    function read(key) { try { return sessionStorage.getItem(key); } catch (e) { return null; } }

    (function flash() {
        var msg = read(FLASH);
        if (msg) { store(FLASH, null); HRMS.toast(msg, "success"); }
    })();

    /* ====================================================== Create Roles */
    var rolesPage = $("[data-sec-roles]");
    if (rolesPage) {
        var editor = $("[data-sec-editor]", rolesPage);
        var current = null;           // the open role's reference ("" = new)
        var form = null;

        var isDirty = function () { return form && form.getAttribute("data-dirty") === "true"; };
        var confirmLeave = function () {
            return !isDirty() || window.confirm(HRMS.t("js.sec_discard_changes", "Discard the changes to this role?"));
        };

        var select = function (ref) {
            $all("[data-sec-role]", rolesPage).forEach(function (b) {
                var on = b.getAttribute("data-sec-role") === ref;
                b.classList.toggle("is-active", on);
                b.setAttribute("aria-selected", on ? "true" : "false");
            });
        };

        var load = function (ref) {
            current = ref || "";
            select(current);
            editor.setAttribute("aria-busy", "true");
            editor.innerHTML = '<div class="hrms-card"><div class="pr-loading"><div class="hrms-spinner"></div></div></div>';
            HRMS.postHtml(rolesPage.getAttribute("data-urls-panel"), fd({ ref: current || null })).then(function (html) {
                editor.innerHTML = html;
                editor.removeAttribute("aria-busy");
                form = $("[data-sec-role-form]", editor);
                if (form) { wireEditor(form); }
                if (window.innerWidth < 992) { editor.scrollIntoView({ behavior: "smooth", block: "start" }); }
            }, function (error) {
                editor.removeAttribute("aria-busy");
                editor.innerHTML = "";
                HRMS.toast((error && error.message) || failed(), "error");
            });
        };

        rolesPage.addEventListener("click", function (e) {
            var b = e.target.closest("[data-sec-role]");
            if (b) { if (b.getAttribute("data-sec-role") !== current && confirmLeave()) { load(b.getAttribute("data-sec-role")); } return; }
            if (e.target.closest("[data-sec-new]") && confirmLeave()) { load(""); }
        });

        var roleSearch = $("[data-sec-role-search]", rolesPage);
        if (roleSearch) {
            roleSearch.addEventListener("input", function () {
                var q = roleSearch.value.trim().toLowerCase();
                $all("[data-sec-role]", rolesPage).forEach(function (b) {
                    b.parentElement.hidden = !!q && b.getAttribute("data-sec-search-text").indexOf(q) < 0;
                });
            });
        }

        window.addEventListener("beforeunload", function (e) { if (isDirty()) { e.preventDefault(); e.returnValue = ""; } });

        // the role to open: the one just saved (?open=, mapped by the server) or the first one
        var first = rolesPage.getAttribute("data-open");
        if (first) { load(first); }
        if (window.history && window.history.replaceState && /[?&]open=/.test(window.location.search)) {
            window.history.replaceState(null, "", window.location.pathname);
        }

        /* ---------------------------------------------- the editor */
        var wireEditor = function (f) {
            var matrix = $("[data-sec-matrix]", f);
            var readOnly = $("fieldset", f) && $("fieldset", f).disabled;

            var checks = function (row) {
                var o = {};
                KEYS.forEach(function (k) { o[k] = $('input[data-sec-level="' + k + '"]', row); });
                return o;
            };
            var levelOf = function (row) {
                var c = checks(row), lvl = 0;
                KEYS.forEach(function (k) { if (c[k] && c[k].checked) { lvl = ORDER[k]; } });
                return lvl;
            };
            var setLevel = function (row, lvl) {
                var c = checks(row);
                KEYS.forEach(function (k) { if (c[k]) { c[k].checked = ORDER[k] <= lvl; } });
            };
            var fnRows = function (page) { return $all('tr[data-sec-parent="' + page.getAttribute("data-sec-item") + '"]', matrix); };
            var pageOf = function (fn) { return $('tr[data-sec-item="' + fn.getAttribute("data-sec-parent") + '"]', matrix); };

            /* functions are only open while their page is readable */
            var syncFunctions = function (page) {
                var off = levelOf(page) === 0;
                fnRows(page).forEach(function (fn) {
                    if (off) { setLevel(fn, 0); }
                    fn.classList.toggle("is-off", off);
                    $all("input[data-sec-level]", fn).forEach(function (i) { i.disabled = off || readOnly; });
                    $all("[data-sec-inherit]", fn).forEach(function (i) { i.classList.toggle("is-on", !off); });
                });
            };
            var syncModules = function () {
                $all("[data-sec-module]", matrix).forEach(function (body) {
                    var pages = $all("tr.sec-row--page", body);
                    KEYS.forEach(function (k) {
                        var box = $('input[data-sec-module-col="' + k + '"]', body);
                        if (!box) { return; }
                        var offered = pages.filter(function (p) { return !!checks(p)[k]; });
                        var on = offered.filter(function (p) { return levelOf(p) >= ORDER[k]; }).length;
                        box.disabled = offered.length === 0 || readOnly;
                        box.checked = offered.length > 0 && on === offered.length;
                        box.indeterminate = on > 0 && on < offered.length;
                    });
                });
            };
            var summary = function () {
                var el = $("[data-sec-summary]", f);
                if (!el) { return; }
                var pages = $all("tr.sec-row--page[data-sec-item]", matrix).filter(function (r) { return levelOf(r) > 0; }).length;
                var fns = $all("tr.sec-row--fn", matrix).filter(function (r) { return levelOf(r) > 0; }).length;
                var apr = $all('input[name="approval"]:checked', f).length;
                el.textContent = HRMS.t("js.sec_summary", "{0} pages · {1} functions · {2} approval rights")
                    .replace("{0}", pages).replace("{1}", fns).replace("{2}", apr);
            };
            var dirty = function () {
                f.setAttribute("data-dirty", "true");
                var d = $("[data-sec-dirty]", f);
                if (d) { d.hidden = false; }
                summary();
            };
            var setPage = function (page, lvl) {
                setLevel(page, lvl);
                // a page tick applies to its functions (each up to what it offers)
                fnRows(page).forEach(function (fn) { setLevel(fn, lvl); });
                syncFunctions(page);
            };

            $all("tr.sec-row--page[data-sec-item]", matrix).forEach(syncFunctions);
            syncModules();
            summary();

            f.addEventListener("change", function (e) {
                var t = e.target;
                if (t.matches("input[data-sec-level]")) {
                    var row = t.closest("tr");
                    var k = t.getAttribute("data-sec-level");
                    var lvl = t.checked ? ORDER[k] : ORDER[k] - 1;
                    if (row.classList.contains("sec-row--fn")) {
                        setLevel(row, lvl);
                        var page = pageOf(row);
                        if (lvl > 0 && levelOf(page) === 0) { setLevel(page, 1); syncFunctions(page); }
                    } else {
                        setPage(row, lvl);
                    }
                    syncModules();
                    dirty();
                    return;
                }
                if (t.matches("input[data-sec-module-col]")) {
                    var col = ORDER[t.getAttribute("data-sec-module-col")];
                    $all("tr.sec-row--page", t.closest("[data-sec-module]")).forEach(function (p) {
                        var cur = levelOf(p);
                        if (t.checked && cur < col) { setPage(p, col); }
                        if (!t.checked && cur >= col) { setPage(p, col - 1); }
                    });
                    syncModules();
                    dirty();
                    return;
                }
                if (t.closest(".sec-details") || t.name === "approval") { dirty(); }
            });
            f.addEventListener("input", function (e) { if (e.target.closest(".sec-details")) { dirty(); } });

            /* expand / collapse functions */
            var toggle = function (btn, open) {
                var page = btn.closest("tr");
                btn.setAttribute("aria-expanded", open ? "true" : "false");
                page.classList.toggle("is-open", open);
                fnRows(page).forEach(function (fn) { fn.hidden = !open; });
            };
            f.addEventListener("click", function (e) {
                var tg = e.target.closest("[data-sec-toggle]");
                if (tg) { toggle(tg, tg.getAttribute("aria-expanded") !== "true"); return; }
                var all = e.target.closest("[data-sec-expand-all]");
                if (all) {
                    var btns = $all("[data-sec-toggle]", matrix);
                    var open = btns.some(function (b) { return b.getAttribute("aria-expanded") !== "true"; });
                    btns.forEach(function (b) { toggle(b, open); });
                    all.textContent = open ? HRMS.t("js.sec_collapse_all", "Collapse all") : HRMS.t("js.sec_expand_all", "Expand all");
                    return;
                }
                var preset = e.target.closest("[data-sec-preset]");
                if (preset) {
                    var lv = { R: 1, F: 3, N: 0 }[preset.getAttribute("data-sec-preset")];
                    $all("tr.sec-row--page[data-sec-item]", matrix).forEach(function (p) { setPage(p, lv); });
                    syncModules();
                    dirty();
                    return;
                }
                if (e.target.closest("[data-sec-discard]")) {
                    if (!isDirty() || window.confirm(HRMS.t("js.sec_discard_changes", "Discard the changes to this role?"))) {
                        f.setAttribute("data-dirty", "false");
                        load(current);
                    }
                    return;
                }
                var del = e.target.closest("[data-sec-delete]");
                if (del) {
                    if (!window.confirm(del.getAttribute("data-confirm"))) { return; }
                    busy(del, true);
                    HRMS.post(rolesPage.getAttribute("data-urls-delete"), fd({ ref: current })).then(function (res) {
                        busy(del, false);
                        if (res && res.success) {
                            f.setAttribute("data-dirty", "false");
                            store(FLASH, res.message);
                            window.location.reload();
                        } else {
                            HRMS.toast((res && res.message) || failed(), "error");
                        }
                    }, function (err) { busy(del, false); HRMS.toast((err && err.message) || failed(), "error"); });
                }
            });

            /* search the pages and functions */
            var filter = $("[data-sec-filter]", f);
            if (filter) {
                filter.addEventListener("input", debounce(function () {
                    var q = filter.value.trim().toLowerCase();
                    var any = false;
                    $all("[data-sec-module]", matrix).forEach(function (body) {
                        var shown = 0;
                        $all("tr.sec-row--page", body).forEach(function (p) {
                            var fns = fnRows(p);
                            var fnHits = fns.filter(function (fn) { return !q || fn.getAttribute("data-sec-search").indexOf(q) >= 0; });
                            var hit = !q || p.getAttribute("data-sec-search").indexOf(q) >= 0 || fnHits.length > 0;
                            p.hidden = !hit;
                            var tg = $("[data-sec-toggle]", p);
                            fns.forEach(function (fn) {
                                fn.hidden = q ? !(hit && fnHits.indexOf(fn) >= 0) : !(tg && tg.getAttribute("aria-expanded") === "true");
                            });
                            if (hit) { shown++; }
                        });
                        body.hidden = shown === 0;
                        if (shown > 0) { any = true; }
                    });
                    var empty = $("[data-sec-filter-empty]", f);
                    if (empty) { empty.hidden = any; }
                }, 150));
            }

            /* save */
            f.addEventListener("submit", function (e) {
                e.preventDefault();
                if (readOnly) { return; }
                var name = $("[name=roleName]", f), code = $("[name=roleCode]", f);
                code.value = code.value.trim().toUpperCase();
                if (!name.value.trim() || !code.value || !/^[A-Z0-9_]+$/.test(code.value)) {
                    (name.value.trim() ? code : name).focus();
                    f.classList.add("was-validated");
                    HRMS.toast(HRMS.t("js.sec_name_code", "Enter the role name and a code (letters, digits and _)."), "error");
                    return;
                }
                var body = new FormData();
                body.append("ref", current || "");
                body.append("roleName", name.value.trim());
                body.append("roleCode", code.value);
                body.append("description", ($("[name=description]", f).value || "").trim());
                var company = $("[name=companyId]", f);
                if (company && company.value) { body.append("companyId", company.value); }
                body.append("isActive", $("[name=isActive]", f).checked ? "true" : "false");
                $all("tr[data-sec-item]", matrix).forEach(function (row) {
                    var lvl = levelOf(row);
                    if (lvl > 0) { body.append("access", row.getAttribute("data-sec-item") + ":" + KEYS[lvl - 1]); }
                });
                $all('input[name="approval"]:checked', f).forEach(function (a) { body.append("approval", a.value); });

                var btn = $("[data-sec-save]", f);
                busy(btn, true);
                HRMS.post(rolesPage.getAttribute("data-urls-save"), body).then(function (res) {
                    busy(btn, false);
                    if (res && res.success) {
                        f.setAttribute("data-dirty", "false");
                        store(FLASH, res.message);
                        // references differ on every request: the server maps this one back to its list
                        window.location.href = window.location.pathname + "?open=" + encodeURIComponent(res.ref || current || "");
                    } else {
                        HRMS.toast((res && res.message) || failed(), "error");
                    }
                }, function (err) { busy(btn, false); HRMS.toast((err && err.message) || failed(), "error"); });
            });
        };
    }

    /* ====================================================== Assign Roles */
    var assignPage = $("[data-sec-assign]");
    if (assignPage) {
        var slot = $("[data-sec-users-slot]", assignPage);
        var search = $("[data-sec-user-search]", assignPage);
        var roleSel = $("[data-sec-user-role]", assignPage);
        var countEl = $("[data-sec-user-count]", assignPage);
        var pageNo = 1, seq = 0;

        var loadUsers = function () {
            var mine = ++seq;
            slot.setAttribute("aria-busy", "true");
            HRMS.postHtml(assignPage.getAttribute("data-urls-grid"), fd({
                search: search && search.value.trim() ? search.value.trim() : null,
                role: roleSel && roleSel.value ? roleSel.value : null,
                page: String(pageNo)
            })).then(function (html) {
                if (mine !== seq) { return; }
                slot.innerHTML = html;
                slot.removeAttribute("aria-busy");
                var holder = $("[data-total]", slot);
                if (countEl && HRMS.setCountText) { HRMS.setCountText(countEl, holder ? holder.getAttribute("data-count-text") : ""); }
            }, function (error) {
                if (mine !== seq) { return; }
                slot.removeAttribute("aria-busy");
                HRMS.toast((error && error.message) || failed(), "error");
            });
        };
        if (search) { search.addEventListener("input", debounce(function () { pageNo = 1; loadUsers(); }, 300)); }
        if (roleSel) { roleSel.addEventListener("change", function () { pageNo = 1; loadUsers(); }); }

        var modalEl = document.getElementById("sec-user-modal");
        var saveBtn = modalEl && $("[data-sec-user-save]", modalEl);
        var openRef = null;

        assignPage.addEventListener("click", function (e) {
            var pg = e.target.closest("[data-page]");
            if (pg && !pg.disabled) { pageNo = parseInt(pg.getAttribute("data-page"), 10) || 1; loadUsers(); return; }
            var u = e.target.closest("[data-sec-user]");
            if (!u || !modalEl || !window.bootstrap) { return; }
            openRef = u.getAttribute("data-sec-user");
            var body = $("[data-sec-modal-body]", modalEl);
            $("[data-sec-modal-title]", modalEl).textContent = u.getAttribute("data-sec-user-name") || "";
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            if (saveBtn) { saveBtn.disabled = true; }
            window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
            HRMS.postHtml(assignPage.getAttribute("data-urls-panel"), fd({ ref: openRef })).then(function (html) {
                body.innerHTML = html;
                var t = $("[data-sec-panel-title]", body);
                if (t) { $("[data-sec-modal-title]", modalEl).textContent = t.textContent.trim(); }
            }, function (error) {
                body.innerHTML = "";
                HRMS.toast((error && error.message) || failed(), "error");
            });
        });

        if (modalEl) {
            modalEl.addEventListener("change", function (e) {
                if (!e.target.matches('input[name="roles"]')) { return; }
                e.target.closest(".sec-role-pick").classList.toggle("is-selected", e.target.checked);
                if (saveBtn) { saveBtn.disabled = false; }
            });
        }
        if (saveBtn) {
            saveBtn.addEventListener("click", function () {
                var body = new FormData();
                body.append("ref", openRef);
                $all('input[name="roles"]:checked', modalEl).forEach(function (c) { body.append("roles", c.value); });
                busy(saveBtn, true);
                HRMS.post(assignPage.getAttribute("data-urls-save"), body).then(function (res) {
                    busy(saveBtn, false);
                    if (res && res.success) {
                        HRMS.toast(res.message, "success");
                        window.bootstrap.Modal.getOrCreateInstance(modalEl).hide();
                        loadUsers();
                    } else {
                        HRMS.toast((res && res.message) || failed(), "error");
                    }
                }, function (err) { busy(saveBtn, false); HRMS.toast((err && err.message) || failed(), "error"); });
            });
        }

        loadUsers();
    }
})();
