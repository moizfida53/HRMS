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
        duplicate: slot.dataset.duplicateUrl
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

    function updateTabCount() {
        var counter = slot.querySelector(".hrms-card__count");
        var active = document.querySelector(".hrms-tab.is-active [data-tab-count]");
        if (!active) { return; }

        if (counter) {
            var digits = counter.textContent.replace(/[^0-9,]/g, "").trim();
            active.textContent = digits;
            active.hidden = !digits;
        } else {
            active.hidden = true;
        }
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

        // Keep the sidebar highlight in step with the visible tab.
        document.querySelectorAll('.hrms-sidebar .hrms-nav-link[href*="tab="]').forEach(function (link) {
            link.classList.toggle("is-active", link.href.indexOf("tab=" + key) !== -1);
        });

        if (pushHistory) {
            var url = new URL(window.location.href);
            url.searchParams.set("tab", key);
            window.history.pushState({ tab: key }, "", url.toString());
        }

        button.scrollIntoView({ block: "nearest", inline: "nearest" });

        return loadGrid();
    }

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

    /* ============================================================== init === */

    var initial = document.querySelector(".hrms-tab.is-active");
    if (initial) {
        state.singular = initial.dataset.singular || "";
    }

    loadGrid();
})();
