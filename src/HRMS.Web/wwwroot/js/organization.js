/* ==========================================================================
 * HRMS Kuwait - Organization Setup
 * --------------------------------------------------------------------------
 * One page, eight tabs. Each tab's grid is a server-rendered partial fetched
 * over AJAX; forms are partials injected into a shared Bootstrap modal.
 *
 * All handlers are delegated from a small number of container elements, so
 * replacing the grid HTML never needs anything re-bound.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});

    var slot = document.getElementById("grid-slot");
    if (!slot) { return; }

    var urls = {
        grid: slot.dataset.gridUrl,
        form: slot.dataset.formUrl,
        save: slot.dataset.saveUrl,
        remove: slot.dataset.deleteUrl,
        toggle: slot.dataset.toggleUrl,
        lookup: slot.dataset.lookupUrl,
        duplicate: slot.dataset.duplicateUrl,
        docSection: slot.dataset.docsecUrl,
        docOrder: slot.dataset.docorderUrl
    };

    document.documentElement.setAttribute("data-org-tab", slot.dataset.tab || "");

    var state = {
        tab: slot.dataset.tab,
        singular: "",
        search: "",
        status: "",
        page: 1,
        sortColumn: "",
        sortDirection: "ASC"
    };

    var recordModal = null;
    var confirmModal = null;
    var pendingDelete = null;
    var requestToken = 0;

    /* ====================================================== grid loading === */

    function buildGridUrl() {
        var params = new URLSearchParams();
        params.set("tab", state.tab);
        params.set("PageNumber", state.page);

        if (state.search) { params.set("Search", state.search); }
        if (state.status) { params.set("IsActive", state.status); }
        if (state.sortColumn) {
            params.set("SortColumn", state.sortColumn);
            params.set("SortDirection", state.sortDirection);
        }

        return urls.grid + "?" + params.toString();
    }

    function loadGrid(options) {
        options = options || {};
        var token = ++requestToken;

        slot.classList.add("is-loading");
        slot.setAttribute("aria-busy", "true");

        return HRMS.getHtml(buildGridUrl())
            .then(function (html) {
                // A slower earlier request must not overwrite a newer result.
                if (token !== requestToken) { return; }

                slot.innerHTML = '<div class="hrms-spinner" aria-hidden="true"></div>' + html;
                updateTabCount();

                if (options.focusSearch) {
                    var search = slot.querySelector("[data-grid-search]");
                    if (search) {
                        search.focus();
                        // Put the caret at the end rather than selecting the text.
                        var value = search.value;
                        search.value = "";
                        search.value = value;
                    }
                }
            })
            .catch(function (error) {
                if (token !== requestToken) { return; }
                slot.innerHTML =
                    '<div class="hrms-card"><div class="hrms-empty">' +
                    '<p class="hrms-empty__title">' + HRMS.escape(HRMS.t("js.panel_load_failed", "This panel could not be loaded")) + '</p>' +
                    '<p class="hrms-empty__text"></p>' +
                    '<button type="button" class="btn btn-outline-secondary" data-action="reload">' + HRMS.escape(HRMS.t("js.try_again", "Try again")) + '</button>' +
                    '</div></div>';
                slot.querySelector(".hrms-empty__text").textContent = error.message;
            })
            .finally(function () {
                if (token !== requestToken) { return; }
                slot.classList.remove("is-loading");
                slot.setAttribute("aria-busy", "false");
            });
    }

    // The badges are filled on page load (every tab's total); a reload of the open tab
    // refreshes its own badge - but not while a search or status filter narrows the list.
    function updateTabCount() {
        var counter = slot.querySelector(".hrms-card__count");
        var active = document.querySelector(".hrms-tab.is-active [data-tab-count]");
        if (!active || state.search || state.status) { return; }

        if (counter) {
            var digits = counter.textContent.replace(/[^0-9,]/g, "").trim();
            active.textContent = digits;
            active.hidden = !digits;
        } else {
            // the empty state has no record counter: nothing on record
            active.textContent = "0";
            active.hidden = false;
        }
        syncSwitch();
    }

    /* ============================================================= tabs === */

    function selectTab(key, pushHistory) {
        var button = document.querySelector('.hrms-tab[data-tab="' + key + '"]');
        if (!button) { return; }

        state.tab = key;
        // the tab in use, for the rights-based rules (Security > Create Roles) on the page
        document.documentElement.setAttribute("data-org-tab", key);
        state.singular = button.dataset.singular || "";
        state.search = "";
        state.status = "";
        state.page = 1;
        state.sortColumn = "";
        state.sortDirection = "ASC";

        document.querySelectorAll(".hrms-tab").forEach(function (tab) {
            var isActive = tab === button;
            tab.classList.toggle("is-active", isActive);
            tab.setAttribute("aria-selected", isActive ? "true" : "false");
        });

        slot.setAttribute("aria-labelledby", "tab-" + key);

        var addLabel = document.querySelector("[data-add-label]");
        if (addLabel) { addLabel.textContent = HRMS.t("js.add_named", "Add {0}", state.singular); }

        var description = document.querySelector("[data-tab-description]");
        if (description) { description.textContent = button.dataset.description || ""; }

        // Keep the sidebar highlight in step with the visible master.
        document.querySelectorAll(".hrms-sidebar [data-org-tab]").forEach(function (link) {
            var on = link.getAttribute("data-org-tab") === key;
            link.classList.toggle("is-active", on);
            if (on) { link.setAttribute("aria-current", "page"); } else { link.removeAttribute("aria-current"); }
        });
        syncSwitch();

        if (pushHistory) {
            var url = new URL(window.location.href);
            url.searchParams.set("tab", key);
            window.history.pushState({ tab: key }, "", url.toString());
        }

        button.scrollIntoView({ block: "nearest", inline: "nearest" });

        return loadGrid();
    }

    /* ---- the switcher: the open master, ‹ › to the previous / next one ---- */

    function allTabs() { return Array.prototype.slice.call(document.querySelectorAll(".hrms-tab")); }

    function syncSwitch() {
        var tabs = allTabs();
        var index = tabs.findIndex(function (t) { return t.dataset.tab === state.tab; });
        var current = tabs[index];
        var sw = document.querySelector("[data-org-switch]");
        if (!sw || !current) { return; }
        sw.querySelector("[data-org-switch-title]").textContent = current.firstChild ? current.firstChild.textContent.trim() : current.textContent.trim();
        sw.querySelector("[data-org-switch-pos]").textContent = (index + 1) + " / " + tabs.length;
        var badge = current.querySelector("[data-tab-count]");
        var count = sw.querySelector("[data-org-switch-count]");
        count.textContent = badge && !badge.hidden ? badge.textContent : "";
        count.hidden = !count.textContent;
        sw.querySelectorAll("[data-org-dot]").forEach(function (dot) {
            dot.classList.toggle("is-active", dot.getAttribute("data-org-dot") === state.tab);
        });
        // the names of where the arrows go, for their tooltips
        [-1, 1].forEach(function (step) {
            var to = tabs[(index + step + tabs.length) % tabs.length];
            var arrow = sw.querySelector('[data-org-step="' + step + '"]');
            if (arrow && to) {
                var name = to.firstChild ? to.firstChild.textContent.trim() : to.textContent.trim();
                arrow.title = name;
                arrow.setAttribute("aria-label", name);
            }
        });
    }

    function step(by) {
        var tabs = allTabs();
        var index = tabs.findIndex(function (t) { return t.dataset.tab === state.tab; });
        var to = tabs[(index + by + tabs.length) % tabs.length];
        if (to) { selectTab(to.dataset.tab, true); }
    }

    document.addEventListener("click", function (event) {
        var arrow = event.target.closest("[data-org-step]");
        if (arrow) { step(parseInt(arrow.getAttribute("data-org-step"), 10)); return; }
        var dot = event.target.closest("[data-org-dot]");
        if (dot) { selectTab(dot.getAttribute("data-org-dot"), true); return; }
        // a master in the sidebar: switch in place, no page load
        var link = event.target.closest(".hrms-sidebar [data-org-tab]");
        if (link && !event.ctrlKey && !event.metaKey && !event.shiftKey) {
            event.preventDefault();
            if (link.getAttribute("data-org-tab") !== state.tab) { selectTab(link.getAttribute("data-org-tab"), true); }
            return;
        }
    });

    // ← / → move between masters (not while typing, nor with a dialog open)
    document.addEventListener("keydown", function (event) {
        if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") { return; }
        if (event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) { return; }
        var t = event.target;
        if (t.closest("input, textarea, select, [contenteditable], .modal.show, .hrms-tab, .dropdown-menu")) { return; }
        if (document.querySelector(".modal.show")) { return; }
        event.preventDefault();
        var forward = event.key === "ArrowRight";
        if (HRMS.isRtl) { forward = !forward; }
        step(forward ? 1 : -1);
    });

    document.addEventListener("click", function (event) {
        var tab = event.target.closest(".hrms-tab");
        if (tab && !tab.classList.contains("is-active")) {
            event.preventDefault();
            selectTab(tab.dataset.tab, true);
        }
    });

    window.addEventListener("popstate", function () {
        var key = new URL(window.location.href).searchParams.get("tab") || state.tab;
        selectTab(key, false);
    });

    // Arrow-key traversal across the tab rail, per WAI-ARIA tabs practice.
    document.addEventListener("keydown", function (event) {
        var current = event.target.closest(".hrms-tab");
        if (!current) { return; }

        var keys = { ArrowRight: 1, ArrowLeft: -1, Home: "first", End: "last" };
        if (!(event.key in keys)) { return; }

        event.preventDefault();
        var tabs = Array.prototype.slice.call(document.querySelectorAll(".hrms-tab"));
        var index = tabs.indexOf(current);
        var target;

        if (keys[event.key] === "first") { target = tabs[0]; }
        else if (keys[event.key] === "last") { target = tabs[tabs.length - 1]; }
        else { target = tabs[(index + keys[event.key] + tabs.length) % tabs.length]; }

        target.focus();
        selectTab(target.dataset.tab, true);
    });

    /* ================================================ grid interactions === */

    var runSearch = HRMS.debounce(function () {
        state.page = 1;
        loadGrid({ focusSearch: true });
    }, 300);

    slot.addEventListener("input", function (event) {
        if (event.target.matches("[data-grid-search]")) {
            state.search = event.target.value;
            runSearch();
        }
    });

    slot.addEventListener("change", function (event) {
        if (event.target.matches("[data-grid-status]")) {
            state.status = event.target.value;
            state.page = 1;
            loadGrid();
        }
    });

    slot.addEventListener("click", function (event) {
        var sort = event.target.closest("[data-sort]");
        if (sort) {
            state.sortColumn = sort.dataset.sort;
            state.sortDirection = sort.dataset.direction;
            state.page = 1;
            loadGrid();
            return;
        }

        var page = event.target.closest("[data-page]");
        if (page && !page.disabled) {
            state.page = parseInt(page.dataset.page, 10) || 1;
            loadGrid();
            window.scrollTo({ top: 0, behavior: "smooth" });
            return;
        }

        var action = event.target.closest("[data-action]");
        if (!action) { return; }

        var row = action.closest("tr");

        switch (action.dataset.action) {
            case "add":
                event.preventDefault();
                openForm(0);
                break;

            case "edit":
                event.preventDefault();
                openForm(row.dataset.id);
                break;

            case "toggle":
                event.preventDefault();
                toggleRecord(row.dataset.id, row.dataset.name);
                break;

            case "delete":
                event.preventDefault();
                askDelete(row.dataset.id, row.dataset.name);
                break;

            case "clear-filters":
                event.preventDefault();
                state.search = "";
                state.status = "";
                state.page = 1;
                loadGrid({ focusSearch: true });
                break;

            case "reload":
                event.preventDefault();
                loadGrid();
                break;
        }
    });

    /* ====================================================== page actions === */

    document.querySelector(".hrms-page-head__actions").addEventListener("click", function (event) {
        var action = event.target.closest("[data-action]");
        if (!action) { return; }

        event.preventDefault();

        if (action.dataset.action === "add") {
            openForm(0);
        } else if (action.dataset.action === "export") {
            exportVisibleRows();
        }
    });

    /* ============================================================ forms === */

    function ensureRecordModal() {
        if (!recordModal) {
            recordModal = new bootstrap.Modal(document.getElementById("record-modal"));
        }
        return recordModal;
    }

    function openForm(id) {
        var url = urls.form + "?tab=" + encodeURIComponent(state.tab) + "&id=" + (id || 0);

        HRMS.getHtml(url)
            .then(function (html) {
                var container = document.getElementById("record-modal-content");
                container.innerHTML = html;
                ensureRecordModal().show();

                // Focus the first editable control once the dialog is on screen.
                window.setTimeout(function () {
                    var first = container.querySelector("input:not([type=hidden]), select, textarea");
                    if (first) { first.focus(); }
                }, 180);

                wireCascades(container);
            })
            .catch(function (error) {
                HRMS.toast(error.message, "error");
            });
    }

    /**
     * Repopulates a dependent dropdown when its parent changes - Department by
     * Company, Branch by Company. Uses the single Lookup endpoint.
     */
    function wireCascades(container) {
        container.querySelectorAll("[data-cascade-from]").forEach(function (child) {
            var parent = container.querySelector('[name="' + child.dataset.cascadeFrom + '"]');
            if (!parent) { return; }

            parent.addEventListener("change", function () {
                var query = urls.lookup +
                    "?type=" + encodeURIComponent(child.dataset.lookupType) +
                    (parent.value ? "&companyId=" + encodeURIComponent(parent.value) : "");

                child.disabled = true;

                HRMS.getJson(query)
                    .then(function (items) {
                        var placeholder = child.options.length ? child.options[0].textContent : HRMS.t("js.select_placeholder", "— Select —");
                        child.innerHTML = "";

                        var blank = document.createElement("option");
                        blank.value = "";
                        blank.textContent = placeholder;
                        child.appendChild(blank);

                        items.forEach(function (item) {
                            var option = document.createElement("option");
                            option.value = item.id;
                            option.textContent = item.text;   // textContent, never innerHTML
                            child.appendChild(option);
                        });
                    })
                    .catch(function () {
                        HRMS.toast(HRMS.t("js.dependent_list_refresh_failed", "Could not refresh the dependent list."), "error");
                    })
                    .finally(function () {
                        child.disabled = false;
                    });
            });
        });

        wireDuplicateCheck(container);

        // long lists (e.g. the issuing authorities, db/75) get a search box
        if (HRMS.searchable) {
            container.querySelectorAll("select[data-searchable]").forEach(HRMS.searchable);
        }
    }

    /** Inline uniqueness check as the user leaves the Code field. */
    function wireDuplicateCheck(container) {
        var field = container.querySelector("[data-code-field]");
        if (!field) { return; }

        field.addEventListener("blur", function () {
            var value = field.value.trim();
            if (!value) { return; }

            var form = container.querySelector("#record-form");
            var idInput = form.querySelector('input[type="hidden"][name$="Id"]');
            var scopeName = field.dataset.scopeField;
            var scopeInput = scopeName ? form.querySelector('[name="' + scopeName + '"]') : null;

            var query = urls.duplicate +
                "?tab=" + encodeURIComponent(state.tab) +
                "&code=" + encodeURIComponent(value) +
                "&id=" + encodeURIComponent(idInput ? idInput.value : 0) +
                (scopeInput && scopeInput.value ? "&scopeId=" + encodeURIComponent(scopeInput.value) : "");

            HRMS.getJson(query)
                .then(function (result) {
                    setFieldError(
                        form,
                        field.name,
                        result.isDuplicate ? HRMS.t("js.code_in_use", "That code is already in use.") : null);
                })
                .catch(function () { /* a failed pre-check is not fatal - save still validates */ });
        });
    }

    function setFieldError(form, name, message) {
        var input = form.querySelector('[name="' + name + '"]');
        var target = form.querySelector('[data-valmsg-for="' + name + '"]');

        if (input) { input.classList.toggle("is-invalid", Boolean(message)); }
        if (target) { target.textContent = message || ""; }
    }

    function clearErrors(form) {
        form.querySelectorAll("[data-valmsg-for]").forEach(function (span) { span.textContent = ""; });
        form.querySelectorAll(".is-invalid").forEach(function (input) { input.classList.remove("is-invalid"); });
    }

    document.getElementById("record-modal").addEventListener("submit", function (event) {
        var form = event.target.closest("#record-form");
        if (!form) { return; }

        event.preventDefault();
        clearErrors(form);

        var submit = form.querySelector("[data-submit]");
        var label = submit.querySelector("span");
        var original = label.textContent;

        submit.disabled = true;
        label.textContent = HRMS.t("js.saving", "Saving…");

        HRMS.post(urls.save + "?tab=" + encodeURIComponent(state.tab), new FormData(form))
            .then(function (result) {
                if (result.success) {
                    ensureRecordModal().hide();
                    HRMS.toast(result.message, "success");
                    loadGrid();
                    return;
                }

                if (result.errors) {
                    Object.keys(result.errors).forEach(function (key) {
                        setFieldError(form, key, result.errors[key][0]);
                    });

                    var firstInvalid = form.querySelector(".is-invalid");
                    if (firstInvalid) { firstInvalid.focus(); }
                }

                HRMS.toast(result.message, "error");
            })
            .catch(function (error) {
                HRMS.toast(error.message, "error");
            })
            .finally(function () {
                submit.disabled = false;
                label.textContent = original;
            });
    });

    /* =================================================== toggle / delete === */

    function toggleRecord(id, name) {
        var body = new FormData();
        body.append("tab", state.tab);
        body.append("id", id);

        HRMS.post(urls.toggle, body)
            .then(function (result) {
                HRMS.toast(result.message, result.success ? "success" : "error");
                if (result.success) { loadGrid(); }
            })
            .catch(function (error) { HRMS.toast(error.message, "error"); });
    }

    function askDelete(id, name) {
        pendingDelete = id;

        var dialog = document.getElementById("confirm-modal");
        dialog.querySelector("[data-confirm-name]").textContent = name || HRMS.t("js.this_record", "this record");

        if (!confirmModal) { confirmModal = new bootstrap.Modal(dialog); }
        confirmModal.show();
    }

    document.querySelector("[data-confirm-accept]").addEventListener("click", function () {
        if (!pendingDelete) { return; }

        var button = this;
        var body = new FormData();
        body.append("tab", state.tab);
        body.append("id", pendingDelete);

        button.disabled = true;

        HRMS.post(urls.remove, body)
            .then(function (result) {
                confirmModal.hide();
                HRMS.toast(result.message, result.success ? "success" : "error");
                if (result.success) { loadGrid(); }
            })
            .catch(function (error) { HRMS.toast(error.message, "error"); })
            .finally(function () {
                button.disabled = false;
                pendingDelete = null;
            });
    });

    /* ============================================================ export === */

    /**
     * Exports exactly what is on screen to CSV. Deliberately client-side: it
     * matches what the user is looking at, and it needs no extra endpoint or
     * database permission. A full server-side export belongs in the Reports
     * module, where it can be permission-checked and audited.
     */
    function exportVisibleRows() {
        var table = slot.querySelector(".hrms-table");
        if (!table) {
            HRMS.toast(HRMS.t("js.nothing_to_export_tab", "There is nothing to export on this tab."), "info");
            return;
        }

        var rows = [];

        var headers = Array.prototype.slice
            .call(table.querySelectorAll("thead th"))
            .map(function (th) { return th.textContent.trim(); })
            .filter(function (text) { return text && text !== HRMS.t("js.actions", "Actions"); });
        rows.push(headers);

        table.querySelectorAll("tbody tr").forEach(function (tr) {
            var cells = Array.prototype.slice
                .call(tr.querySelectorAll("td"))
                .filter(function (td) { return !td.classList.contains("hrms-table__actions"); })
                .map(function (td) { return td.textContent.replace(/\s+/g, " ").trim(); });
            rows.push(cells);
        });

        var csv = rows.map(function (row) {
            return row.map(function (cell) {
                // Guard against CSV formula injection when the file opens in Excel.
                if (/^[=+\-@\t\r]/.test(cell)) { cell = "'" + cell; }
                return '"' + cell.replace(/"/g, '""') + '"';
            }).join(",");
        }).join("\r\n");

        var blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" });
        var link = document.createElement("a");
        link.href = URL.createObjectURL(blob);
        link.download = state.tab + "-" + new Date().toISOString().slice(0, 10) + ".csv";
        document.body.appendChild(link);
        link.click();
        document.body.removeChild(link);
        URL.revokeObjectURL(link.href);

        HRMS.toast(HRMS.t("js.exported_rows", "Exported {0} rows from this page.", rows.length - 1), "success");
    }

    /* ======================= Employee Documents: add a section in place (db/63) === */
    // The "+" next to Section opens a small box in the form; Add saves the section,
    // puts it in the dropdown and selects it - the document type form stays open.
    (function initDocumentSections() {
        var modalEl = document.getElementById("record-modal");

        function parts() {
            var root = modalEl.querySelector("[data-docsec]");
            if (!root) { return null; }
            return {
                root: root,
                panel: root.querySelector("[data-docsec-panel]"),
                open: root.querySelector("[data-docsec-open]"),
                select: root.querySelector("[data-docsec-select]"),
                eng: root.querySelector("[data-docsec-eng]"),
                arb: root.querySelector("[data-docsec-arb]"),
                error: root.querySelector("[data-docsec-error]"),
                save: root.querySelector("[data-docsec-save]")
            };
        }

        function show(p, on) {
            p.panel.hidden = !on;
            p.open.setAttribute("aria-expanded", on ? "true" : "false");
            p.open.classList.toggle("active", on);
            p.error.textContent = "";
            p.eng.classList.remove("is-invalid");
            if (on) { p.eng.value = ""; p.arb.value = ""; window.setTimeout(function () { p.eng.focus(); }, 30); }
            else { p.open.focus(); }
        }

        function add(p) {
            var name = p.eng.value.trim();
            if (!name) {
                p.eng.classList.add("is-invalid");
                p.error.textContent = HRMS.t("js.org_section_name_required", "Enter the section name.");
                p.eng.focus();
                return;
            }
            var body = new FormData();
            body.append("nameEng", name);
            body.append("nameArb", p.arb.value.trim());
            p.save.disabled = true;
            HRMS.post(urls.docSection, body)
                .then(function (result) {
                    if (!result.success) {
                        var message = (result.errors && result.errors.SectionNameEng && result.errors.SectionNameEng[0]) || result.message;
                        p.eng.classList.add("is-invalid");
                        p.error.textContent = message || "";
                        return;
                    }
                    var option = document.createElement("option");
                    option.value = String(result.id);
                    option.textContent = (HRMS.isRtl && p.arb.value.trim()) ? p.arb.value.trim() : name;
                    p.select.appendChild(option);
                    p.select.value = option.value;
                    p.select.dispatchEvent(new Event("change", { bubbles: true }));
                    HRMS.toast(result.message, "success");
                    show(p, false);
                })
                .catch(function (error) { HRMS.toast(error.message, "error"); })
                .finally(function () { p.save.disabled = false; });
        }

        modalEl.addEventListener("click", function (event) {
            var p = parts();
            if (!p) { return; }
            if (event.target.closest("[data-docsec-open]")) { show(p, p.panel.hidden); }
            else if (event.target.closest("[data-docsec-cancel]")) { show(p, false); }
            else if (event.target.closest("[data-docsec-save]")) { add(p); }
        });

        // typing a new name clears the last error
        modalEl.addEventListener("input", function (event) {
            var p = parts();
            if (p && event.target === p.eng) { p.eng.classList.remove("is-invalid"); p.error.textContent = ""; }
        });

        // Enter in the box adds the section (it would otherwise submit the document type)
        modalEl.addEventListener("keydown", function (event) {
            var p = parts();
            if (!p || !p.panel.contains(event.target)) { return; }
            if (event.key === "Enter") { event.preventDefault(); add(p); }
            else if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); show(p, false); }
        }, true);
    })();

    /* ================== Employee Documents: drag rows into order (db/64) === */
    // The grip at the start of a row drags it up or down within its own section
    // (mouse, touch or pen); on a focused grip the arrow keys do the same. The
    // section's new order is saved as soon as the row is dropped.
    (function initDocumentOrder() {
        var drag = null;
        var keyMove = null;

        function sectionRows(row) {
            return Array.prototype.filter.call(row.parentNode.children, function (r) {
                return r.dataset.section === row.dataset.section;
            });
        }

        function orderOf(row) {
            return sectionRows(row).map(function (r) { return r.dataset.id; });
        }

        function positionOf(row) { return sectionRows(row).indexOf(row) + 1; }

        function renumber(row) {
            sectionRows(row).forEach(function (r, i) {
                var pos = r.querySelector("[data-docorder-pos]");
                if (pos) { pos.textContent = i + 1; }
            });
        }

        function announce(row) {
            var live = slot.querySelector("[data-docorder-live]");
            if (live) {
                live.textContent = HRMS.t("js.doc_order_moved", "{0} moved to position {1}.", row.dataset.name, positionOf(row));
            }
        }

        function save(row, before) {
            var ids = orderOf(row);
            if (ids.join(",") === before) { return; }

            var body = new FormData();
            ids.forEach(function (id) { body.append("ids", id); });
            row.classList.add("is-saving");

            // each grid names its own address (db/99: Organization Documents), else Employee Documents
            var table = row.closest("table");
            HRMS.post((table && table.dataset.docorderUrl) || urls.docOrder, body)
                .then(function (result) {
                    if (!result.success) {
                        HRMS.toast(result.message || HRMS.t("js.doc_order_failed", "The new order could not be saved."), "error");
                        return loadGrid();
                    }
                    row.classList.remove("is-saving");
                    row.classList.add("is-saved");
                    window.setTimeout(function () { row.classList.remove("is-saved"); }, 1200);
                    HRMS.toast(HRMS.t("js.doc_order_saved", "Order saved."), "success");
                })
                .catch(function (error) {
                    HRMS.toast(error.message, "error");
                    loadGrid();
                });
        }

        /* ---- pointer: listen on the document, so moving the row in the DOM never drops the drag */
        slot.addEventListener("pointerdown", function (event) {
            var handle = event.target.closest("[data-docorder-handle]");
            if (!handle || event.button !== 0 || drag) { return; }
            var row = handle.closest("tr");
            event.preventDefault();
            drag = { row: row, pointer: event.pointerId, before: orderOf(row).join(",") };
            row.classList.add("is-dragging");
            row.closest("table").classList.add("is-dragging");
            document.documentElement.classList.add("hrms-dragging");
        });

        document.addEventListener("pointermove", function (event) {
            if (!drag || event.pointerId !== drag.pointer) { return; }
            event.preventDefault();

            var y = event.clientY;
            var others = sectionRows(drag.row).filter(function (r) { return r !== drag.row; });
            // the first row of the section whose middle is below the pointer: the dragged row goes before it
            var target = null;
            for (var i = 0; i < others.length; i++) {
                var rect = others[i].getBoundingClientRect();
                if (y < rect.top + rect.height / 2) { target = others[i]; break; }
            }
            var anchor = target || (others.length ? others[others.length - 1].nextElementSibling : null);
            if (others.length && drag.row.nextElementSibling !== anchor && drag.row !== anchor) {
                drag.row.parentNode.insertBefore(drag.row, anchor);
                renumber(drag.row);
            }

            // keep the page scrolling while dragging near the top or bottom edge
            if (y < 60) { window.scrollBy(0, -14); }
            else if (y > window.innerHeight - 60) { window.scrollBy(0, 14); }
        }, { passive: false });

        function endDrag(event) {
            if (!drag || event.pointerId !== drag.pointer) { return; }
            var row = drag.row;
            var before = drag.before;
            drag = null;
            row.classList.remove("is-dragging");
            var table = row.closest("table");
            if (table) { table.classList.remove("is-dragging"); }
            document.documentElement.classList.remove("hrms-dragging");
            announce(row);
            save(row, before);
        }
        document.addEventListener("pointerup", endDrag);
        document.addEventListener("pointercancel", endDrag);

        /* ---- keyboard: arrows on a focused grip; a burst of presses saves once */
        slot.addEventListener("keydown", function (event) {
            var handle = event.target.closest("[data-docorder-handle]");
            if (!handle) { return; }
            var key = event.key;
            if (["ArrowUp", "ArrowDown", "Home", "End"].indexOf(key) === -1) { return; }
            event.preventDefault();

            var row = handle.closest("tr");
            var rows = sectionRows(row);
            var index = rows.indexOf(row);
            var to = key === "ArrowUp" ? index - 1 : key === "ArrowDown" ? index + 1 : key === "Home" ? 0 : rows.length - 1;
            if (to < 0 || to >= rows.length || to === index) { return; }

            if (!keyMove || keyMove.row !== row) {
                if (keyMove) { window.clearTimeout(keyMove.timer); save(keyMove.row, keyMove.before); }
                keyMove = { row: row, before: orderOf(row).join(",") };
            }
            row.parentNode.insertBefore(row, to > index ? rows[to].nextElementSibling : rows[to]);
            renumber(row);
            handle.focus();
            announce(row);

            window.clearTimeout(keyMove.timer);
            keyMove.timer = window.setTimeout(function () {
                var job = keyMove;
                keyMove = null;
                save(job.row, job.before);
            }, 600);
        });
    })();

    /* ============================================================== init === */

    var initial = document.querySelector(".hrms-tab.is-active");
    if (initial) {
        state.singular = initial.dataset.singular || "";
    }
    syncSwitch();

    loadGrid();
})();
