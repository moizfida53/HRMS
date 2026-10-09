/* ==========================================================================
 * HRMS Kuwait - Security: Create Roles and Manage Users (db/57)
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
 *   Manage Users   [data-sec-user-add]     a new user (popup)
 *                  [data-sec-user="ref"]   a user: account, password, roles
 *                  [data-sec-user-toggle]  activate / deactivate
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

    /* ====================================================== Manage Users */
    var usersPage = $("[data-sec-users-page]");
    if (usersPage) {
        var url = function (k) { return usersPage.getAttribute("data-urls-" + k); };
        var slot = $("[data-sec-users-slot]", usersPage);
        var search = $("[data-sec-user-search]", usersPage);
        var roleSel = $("[data-sec-user-role]", usersPage);
        var countEl = $("[data-sec-user-count]", usersPage);
        var pageNo = 1, seq = 0;

        var loadUsers = function () {
            var mine = ++seq;
            slot.setAttribute("aria-busy", "true");
            HRMS.postHtml(url("grid"), fd({
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
        var body = modalEl && $("[data-sec-modal-body]", modalEl);
        var saveBtn = modalEl && $("[data-sec-user-save]", modalEl);
        var userForm = null;

        var PW_RULES = {
            length: function (v) { return v.length >= 8; },
            "case": function (v) { return /[a-z]/.test(v) && /[A-Z]/.test(v); },
            digit: function (v) { return /\d/.test(v); }
        };

        var clearErrors = function () {
            $all("[data-valmsg-for]", userForm).forEach(function (m) { m.textContent = ""; });
            $all(".is-invalid", userForm).forEach(function (i) { i.classList.remove("is-invalid"); });
        };
        var showError = function (name, message) {
            var input = $('[name="' + name + '"]', userForm);
            var target = $('[data-valmsg-for="' + name + '"]', userForm);
            if (input) {
                input.classList.add("is-invalid");
                var combo = input.closest(".hrms-combo");
                if (combo) { combo.classList.add("is-invalid"); }
            }
            if (target) { target.textContent = message; }
        };

        // roles of another company than the user's are not offered (global roles always are)
        var filterRoles = function () {
            var company = $("[data-sec-user-company]", userForm);
            var value = company ? company.value : null;
            var shown = 0, hiddenAny = false;
            $all("li[data-role-company]", userForm).forEach(function (li) {
                var rc = li.getAttribute("data-role-company");
                var show = !company || !value || !rc || rc === value;
                li.hidden = !show;
                if (!show) {
                    hiddenAny = true;
                    var box = $('input[name="roles"]', li);
                    if (box && box.checked && !box.disabled) { box.checked = false; li.querySelector(".sec-role-pick").classList.remove("is-selected"); }
                } else { shown++; }
            });
            var none = $("[data-sec-no-roles]", userForm);
            if (none) { none.hidden = shown > 0; }
            var hint = $("[data-sec-roles-company]", userForm);
            if (hint) { hint.hidden = !hiddenAny; }
            countRoles();
        };
        var countRoles = function () {
            var el = $("[data-sec-role-count]", userForm);
            if (!el) { return; }
            var n = $all('input[name="roles"]:checked', userForm).length;
            el.textContent = n > 0 ? "(" + n + ")" : "";
        };

        var loadEmployees = function () {
            var company = $("[data-sec-user-company]", userForm);
            var emp = $("[data-sec-user-employee]", userForm);
            var hint = $("[data-sec-employee-hint]", userForm);
            if (!company || !emp) { return; }
            var keepFirst = emp.options[0];
            emp.innerHTML = "";
            emp.appendChild(keepFirst);
            emp.value = "";
            if (!company.value) {
                emp.disabled = true;
                if (hint) { hint.textContent = HRMS.t("js.sec_employee_company_first", "Choose the company first to link an employee."); }
                emp.dispatchEvent(new Event("hrms:refresh"));
                return;
            }
            HRMS.post(url("employees"), fd({ companyId: company.value })).then(function (list) {
                (list || []).forEach(function (e) {
                    var o = document.createElement("option");
                    o.value = e.value; o.textContent = e.text;
                    emp.appendChild(o);
                });
                emp.disabled = false;
                if (hint) { hint.textContent = HRMS.t("js.sec_linked_employee_hint", "Optional - the employee this person is (for My Payslips and their own records)."); }
                emp.dispatchEvent(new Event("hrms:refresh"));
            }, function (err) { HRMS.toast((err && err.message) || failed(), "error"); });
        };

        var wireForm = function () {
            userForm = $("[data-sec-user-form]", body);
            if (!userForm) { return; }
            var canSave = userForm.getAttribute("data-can-save") === "true";
            if (saveBtn) { saveBtn.hidden = !canSave; saveBtn.disabled = false; }
            var t = $("[data-sec-panel-title]", userForm);
            if (t) { $("[data-sec-modal-title]", modalEl).textContent = t.textContent.trim(); }
            if (HRMS.searchable) { $all("select[data-searchable]", userForm).forEach(HRMS.searchable); }
            filterRoles();

            var company = $("[data-sec-user-company]", userForm);
            if (company) { company.addEventListener("change", function () { loadEmployees(); filterRoles(); }); }

            var reset = $("[data-sec-pw-reset]", userForm);
            var fields = $("[data-sec-pw-fields]", userForm);
            if (reset && fields) {
                reset.addEventListener("change", function () {
                    fields.hidden = !reset.checked;
                    if (reset.checked) { $("#su-password", userForm).focus(); }
                });
            }
            var pw = $("#su-password", userForm);
            if (pw) {
                pw.addEventListener("input", function () {
                    $all("[data-rule]", userForm).forEach(function (li) { li.classList.toggle("is-met", PW_RULES[li.getAttribute("data-rule")](pw.value)); });
                });
            }

            userForm.addEventListener("change", function (e) {
                if (e.target.matches('input[name="roles"]')) {
                    e.target.closest(".sec-role-pick").classList.toggle("is-selected", e.target.checked);
                    countRoles();
                }
            });
            userForm.addEventListener("click", function (e) {
                var toggle = e.target.closest("[data-sec-pw-toggle]");
                if (!toggle) { return; }
                var input = toggle.parentNode.querySelector("input");
                var show = input.type === "password";
                input.type = show ? "text" : "password";
                toggle.setAttribute("aria-label", show ? HRMS.t("js.hide_password", "Hide password") : HRMS.t("js.show_password", "Show password"));
                toggle.classList.toggle("is-on", show);
            });
            userForm.addEventListener("submit", function (e) { e.preventDefault(); if (saveBtn && !saveBtn.hidden) { saveBtn.click(); } });
            var first = $("#su-username:not([disabled])", userForm);
            if (first && userForm.getAttribute("data-new") === "true") { window.setTimeout(function () { first.focus(); }, 250); }
        };

        var openUser = function (ref, name) {
            if (!modalEl || !window.bootstrap) { return; }
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            userForm = null;
            $("[data-sec-modal-title]", modalEl).textContent = name || HRMS.t("js.sec_add_user", "Add user");
            if (saveBtn) { saveBtn.hidden = true; }
            window.bootstrap.Modal.getOrCreateInstance(modalEl).show();
            HRMS.postHtml(url("panel"), fd({ ref: ref || null })).then(function (html) {
                body.innerHTML = html;
                wireForm();
            }, function (error) {
                body.innerHTML = "";
                HRMS.toast((error && error.message) || failed(), "error");
            });
        };

        var addBtn = $("[data-sec-user-add]");
        if (addBtn) { addBtn.addEventListener("click", function () { openUser(null, null); }); }

        usersPage.addEventListener("click", function (e) {
            var pg = e.target.closest("[data-page]");
            if (pg && !pg.disabled) { pageNo = parseInt(pg.getAttribute("data-page"), 10) || 1; loadUsers(); return; }

            var tg = e.target.closest("[data-sec-user-toggle]");
            if (tg) {
                var activate = tg.getAttribute("data-active") === "true";
                var who = tg.getAttribute("data-sec-user-name") || "";
                var question = activate
                    ? HRMS.t("js.sec_confirm_activate", "Activate {0}? They can sign in again.")
                    : HRMS.t("js.sec_confirm_deactivate", "Deactivate {0}? They are signed out and can no longer sign in.");
                if (!window.confirm(question.replace("{0}", who))) { return; }
                busy(tg, true);
                HRMS.post(url("toggle"), fd({ ref: tg.getAttribute("data-sec-user-toggle"), active: activate ? "true" : "false" })).then(function (res) {
                    busy(tg, false);
                    if (res && res.success) { HRMS.toast(res.message, "success"); loadUsers(); }
                    else { HRMS.toast((res && res.message) || failed(), "error"); }
                }, function (err) { busy(tg, false); HRMS.toast((err && err.message) || failed(), "error"); });
                return;
            }

            var u = e.target.closest("[data-sec-user]");
            if (u) { openUser(u.getAttribute("data-sec-user"), u.getAttribute("data-sec-user-name")); }
        });

        if (saveBtn) {
            saveBtn.addEventListener("click", function () {
                if (!userForm) { return; }
                clearErrors();
                var isNew = userForm.getAttribute("data-new") === "true";
                var simple = userForm.getAttribute("data-simple") === "true";
                var reset = $("[data-sec-pw-reset]", userForm);
                var setPw = isNew || (reset && reset.checked);
                var accountEditable = !$("#su-username", userForm).closest("fieldset").disabled;

                // quick checks so the common mistakes need no round trip
                var bad = false;
                if (accountEditable) {
                    if (!$("#su-username", userForm).value.trim()) { showError("username", HRMS.t("js.sec_enter_username", "Enter the user name.")); bad = true; }
                    if (setPw) {
                        var p1 = $("#su-password", userForm).value, p2 = $("#su-confirm", userForm).value;
                        if (!p1) { showError("password", HRMS.t("js.sec_enter_password", "Enter a password.")); bad = true; }
                        else if (simple ? p1.length > 50 : !(PW_RULES.length(p1) && PW_RULES["case"](p1) && PW_RULES.digit(p1))) {
                            showError("password", HRMS.t("js.password_rules_not_met", "The new password doesn't meet the rules below.")); bad = true;
                        } else if (p1 !== p2) { showError("confirmPassword", HRMS.t("js.passwords_dont_match", "The two new passwords don't match.")); bad = true; }
                    }
                }
                if (bad) { var f1 = $(".is-invalid", userForm); if (f1) { f1.focus(); } return; }

                var data = new FormData(userForm);
                data.delete("roles");
                // every ticked role, also the ones you cannot change (so they stay)
                $all('input[name="roles"]:checked', userForm).forEach(function (c) { data.append("roles", c.value); });
                var active = $("#su-active", userForm);
                data.set("isActive", active && active.checked ? "true" : "false");
                if (!setPw) { data.delete("password"); data.delete("confirmPassword"); data.set("resetPassword", "false"); }
                var mc = $("#su-must", userForm);
                data.set("mustChangePassword", mc && mc.checked ? "true" : "false");
                var ref = userForm.getAttribute("data-ref");
                if (ref) { data.set("ref", ref); }

                busy(saveBtn, true);
                HRMS.post(url("save"), data).then(function (res) {
                    busy(saveBtn, false);
                    if (res && res.success) {
                        HRMS.toast(res.message, "success");
                        window.bootstrap.Modal.getOrCreateInstance(modalEl).hide();
                        loadUsers();
                    } else if (res && res.errors) {
                        Object.keys(res.errors).forEach(function (k) { showError(k, res.errors[k][0]); });
                        var f2 = $(".is-invalid", userForm); if (f2) { f2.focus(); }
                    } else {
                        HRMS.toast((res && res.message) || failed(), "error");
                    }
                }, function (err) { busy(saveBtn, false); HRMS.toast((err && err.message) || failed(), "error"); });
            });
        }

        loadUsers();
    }
})();
