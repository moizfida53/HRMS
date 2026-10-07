/* ==========================================================================
 * HRMS Kuwait - Workforce: Employees
 * --------------------------------------------------------------------------
 * Two independent screens share this file:
 *   - the Employees list (grid-slot): search/filter/sort/paging, toggle and
 *     delete, wired the same way as organization.js's single-tab grid.
 *   - the Employee Profile page (employee-form / compliance-form): Personal
 *     Info and Employment save together in one call (they are the same
 *     row); Kuwait Compliance is a separate 1:1 record saved on its own.
 *
 * Each section below is independently guarded, since only one of the two
 * screens is ever present in the DOM at a time.
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});

    /* ======================================================= list grid === */

    (function initGrid() {
        var slot = document.getElementById("grid-slot");
        if (!slot) { return; }

        var urls = {
            grid: slot.dataset.gridUrl,
            remove: slot.dataset.deleteUrl,
            toggle: slot.dataset.toggleUrl
        };

        var state = {
            search: "",
            status: "",
            page: 1,
            sortColumn: "",
            sortDirection: "ASC"
        };

        var confirmModal = null;
        var pendingDelete = null;
        var requestToken = 0;

        function buildGridUrl() {
            var params = new URLSearchParams();
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
                    if (token !== requestToken) { return; }

                    slot.innerHTML = '<div class="hrms-spinner" aria-hidden="true"></div>' + html;

                    if (options.focusSearch) {
                        var search = slot.querySelector("[data-grid-search]");
                        if (search) {
                            search.focus();
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
                case "toggle":
                    event.preventDefault();
                    toggleRecord(row.dataset.id);
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

        var exportButton = document.querySelector('.hrms-page-head__actions [data-action="export"]');
        if (exportButton) {
            exportButton.addEventListener("click", function (event) {
                event.preventDefault();
                exportVisibleRows();
            });
        }

        function toggleRecord(id) {
            var body = new FormData();
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
            dialog.querySelector("[data-confirm-name]").textContent = name || HRMS.t("js.this_employee", "this employee");

            if (!confirmModal) { confirmModal = new bootstrap.Modal(dialog); }
            confirmModal.show();
        }

        var confirmAccept = document.querySelector("[data-confirm-accept]");
        if (confirmAccept) {
            confirmAccept.addEventListener("click", function () {
                if (!pendingDelete) { return; }

                var button = this;
                var body = new FormData();
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
        }

        function exportVisibleRows() {
            var table = slot.querySelector(".hrms-table");
            if (!table) {
                HRMS.toast(HRMS.t("js.nothing_to_export", "There is nothing to export."), "info");
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
                    if (/^[=+\-@\t\r]/.test(cell)) { cell = "'" + cell; }
                    return '"' + cell.replace(/"/g, '""') + '"';
                }).join(",");
            }).join("\r\n");

            var blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8;" });
            var link = document.createElement("a");
            link.href = URL.createObjectURL(blob);
            link.download = "employees-" + new Date().toISOString().slice(0, 10) + ".csv";
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            URL.revokeObjectURL(link.href);

            HRMS.toast(HRMS.t("js.exported_rows", "Exported {0} rows from this page.", rows.length - 1), "success");
        }

        loadGrid();
    })();

    /* ==================================================== profile forms === */

    (function initProfile() {
        var employeeForm = document.getElementById("employee-form");
        var complianceForm = document.getElementById("compliance-form");
        if (!employeeForm && !complianceForm) { return; }

        function setFieldError(form, name, message) {
            // Personal Info / Employment fields live outside employeeForm's own
            // DOM subtree (they attach via the form="employee-form" attribute),
            // so field lookups search the whole document, not just the form.
            var scope = form.id === "employee-form" ? document : form;
            var input = scope.querySelector('[name="' + name + '"][form], [name="' + name + '"]:not([form])');
            var target = scope.querySelector('[data-valmsg-for="' + name + '"]');

            if (input) { input.classList.toggle("is-invalid", Boolean(message)); }
            if (target) { target.textContent = message || ""; }
        }

        function clearErrors(form) {
            var scope = form.id === "employee-form" ? document : form;
            scope.querySelectorAll("[data-valmsg-for]").forEach(function (span) { span.textContent = ""; });
            scope.querySelectorAll(".is-invalid").forEach(function (input) { input.classList.remove("is-invalid"); });
        }

        function submitButtonFor(form) {
            return document.querySelector('[data-submit][form="' + form.id + '"]') ||
                form.querySelector("[data-submit]");
        }

        function handleSubmit(form, url, onSuccess) {
            clearErrors(form);

            var submit = submitButtonFor(form);
            var label = submit ? submit.querySelector("span") : null;
            var original = label ? label.textContent : null;

            if (submit) { submit.disabled = true; }
            if (label) { label.textContent = HRMS.t("js.saving", "Saving…"); }

            HRMS.post(url, new FormData(form))
                .then(function (result) {
                    if (result.success) {
                        HRMS.toast(result.message, "success");
                        if (onSuccess) { onSuccess(result); }
                        return;
                    }

                    if (result.errors) {
                        Object.keys(result.errors).forEach(function (key) {
                            setFieldError(form, key, result.errors[key][0]);
                        });

                        var firstInvalid = document.querySelector(".is-invalid");
                        document.dispatchEvent(new CustomEvent("form:invalid", { detail: { field: firstInvalid } }));
                        if (firstInvalid) { firstInvalid.focus(); }
                    }

                    HRMS.toast(result.message, "error");
                })
                .catch(function (error) {
                    HRMS.toast(error.message, "error");
                })
                .finally(function () {
                    if (submit) { submit.disabled = false; }
                    if (label) { label.textContent = original; }
                });
        }

        if (employeeForm) {
            employeeForm.addEventListener("submit", function (event) {
                event.preventDefault();

                handleSubmit(employeeForm, employeeForm.dataset.saveUrl || "/employees/save", function (result) {
                    var idField = document.querySelector('[name="EmployeeId"][form="employee-form"]');
                    var wasNew = idField && (!idField.value || idField.value === "0");

                    if (wasNew && result.id) {
                        // A brand-new employee: land back on their own profile so
                        // Kuwait Compliance, Dependents and Documents (which need
                        // the new employee's id) become available. In the Add
                        // wizard, carry on at the next step.
                        var inWizard = Boolean(document.querySelector("[data-wizard]"));
                        window.location.href = "/employees/profile/" + result.id +
                            (inWizard ? "?wizard=true&tab=compliance" : "");
                        return;
                    }

                    if (idField) { idField.value = result.id; }
                    document.dispatchEvent(new CustomEvent("employee:saved", { detail: { result: result } }));
                });
            });
        }

        if (complianceForm) {
            complianceForm.addEventListener("submit", function (event) {
                event.preventDefault();
                handleSubmit(complianceForm, complianceForm.dataset.saveUrl || "/employees/compliance/save", function (result) {
                    document.dispatchEvent(new CustomEvent("compliance:saved", { detail: { result: result } }));
                });
            });
        }
    })();

    /* ====================================================== dependents === */

    // Dependents tab on the Profile page: a small grid-slot (same AJAX-fetch-
    // and-swap pattern as the Employees list grid above) plus one static
    // Add/Edit modal reused for both, and one confirm modal for delete.
    (function initDependents() {
        var slot = document.getElementById("dependents-slot");
        if (!slot) { return; }

        var employeeId = slot.dataset.employeeId;
        var urls = {
            grid: slot.dataset.gridUrl,
            save: "/employees/dependents/save",
            remove: "/employees/dependents/delete"
        };

        var modalEl = document.getElementById("dependent-modal");
        var form = document.getElementById("dependent-form");
        var modalTitle = document.getElementById("dependent-modal-title");
        var dependentModal = null;

        var confirmEl = document.getElementById("dependent-confirm-modal");
        var confirmModal = null;
        var pendingDelete = null;

        function loadGrid() {
            slot.setAttribute("aria-busy", "true");

            return HRMS.getHtml(urls.grid)
                .then(function (html) { slot.innerHTML = html; })
                .catch(function (error) {
                    slot.innerHTML =
                        '<div class="hrms-card"><div class="hrms-empty">' +
                        '<p class="hrms-empty__title">' + HRMS.escape(HRMS.t("js.dependents_load_failed", "Dependents could not be loaded")) + '</p>' +
                        '<p class="hrms-empty__text"></p>' +
                        '<button type="button" class="btn btn-outline-secondary" data-action="reload">' + HRMS.escape(HRMS.t("js.try_again", "Try again")) + '</button>' +
                        '</div></div>';
                    slot.querySelector(".hrms-empty__text").textContent = error.message;
                })
                .finally(function () { slot.setAttribute("aria-busy", "false"); });
        }

        function clearErrors() {
            form.querySelectorAll("[data-valmsg-for]").forEach(function (span) { span.textContent = ""; });
            form.querySelectorAll(".is-invalid").forEach(function (input) { input.classList.remove("is-invalid"); });
        }

        function resetForm() {
            form.reset();
            clearErrors();
            form.querySelector('[name="DependentId"]').value = "0";
            form.querySelector('[name="EmployeeId"]').value = employeeId;
        }

        function openAdd() {
            resetForm();
            modalTitle.textContent = HRMS.t("js.add_dependent", "Add Dependent");
            if (!dependentModal) { dependentModal = new bootstrap.Modal(modalEl); }
            dependentModal.show();
        }

        function openEdit(row) {
            resetForm();
            modalTitle.textContent = HRMS.t("js.edit_dependent", "Edit Dependent");

            form.querySelector('[name="DependentId"]').value = row.dataset.id;
            form.querySelector('[name="FullName"]').value = row.dataset.fullname || "";
            form.querySelector('[name="Relationship"]').value = row.dataset.relationship || "";
            form.querySelector('[name="Gender"]').value = row.dataset.gender || "";
            form.querySelector('[name="DateOfBirth"]').value = row.dataset.dob || "";
            form.querySelector('[name="HasHealthInsurance"][type="checkbox"]').checked = row.dataset.coverage === "true";

            if (!dependentModal) { dependentModal = new bootstrap.Modal(modalEl); }
            dependentModal.show();
        }

        slot.addEventListener("click", function (event) {
            if (event.target.closest('[data-action="add-dependent"]')) {
                openAdd();
                return;
            }

            if (event.target.closest('[data-action="reload"]')) {
                loadGrid();
                return;
            }

            var editButton = event.target.closest('[data-action="edit-dependent"]');
            if (editButton) {
                openEdit(editButton.closest("tr"));
                return;
            }

            var deleteButton = event.target.closest('[data-action="delete-dependent"]');
            if (deleteButton) {
                var row = deleteButton.closest("tr");
                pendingDelete = row.dataset.id;
                confirmEl.querySelector("[data-dependent-confirm-name]").textContent = row.dataset.name || HRMS.t("js.this_dependent", "this dependent");
                if (!confirmModal) { confirmModal = new bootstrap.Modal(confirmEl); }
                confirmModal.show();
            }
        });

        form.addEventListener("submit", function (event) {
            event.preventDefault();
            clearErrors();

            var submit = form.querySelector("[data-submit]");
            var label = submit ? submit.querySelector("span") : null;
            var original = label ? label.textContent : null;

            if (submit) { submit.disabled = true; }
            if (label) { label.textContent = HRMS.t("js.saving", "Saving…"); }

            HRMS.post(urls.save, new FormData(form))
                .then(function (result) {
                    if (result.success) {
                        HRMS.toast(result.message, "success");
                        dependentModal.hide();
                        loadGrid();
                        return;
                    }

                    if (result.errors) {
                        Object.keys(result.errors).forEach(function (key) {
                            var input = form.querySelector('[name="' + key + '"]');
                            var target = form.querySelector('[data-valmsg-for="' + key + '"]');
                            if (input) { input.classList.add("is-invalid"); }
                            if (target) { target.textContent = result.errors[key][0]; }
                        });
                    }

                    HRMS.toast(result.message, "error");
                })
                .catch(function (error) { HRMS.toast(error.message, "error"); })
                .finally(function () {
                    if (submit) { submit.disabled = false; }
                    if (label) { label.textContent = original; }
                });
        });

        var confirmAccept = confirmEl.querySelector("[data-dependent-confirm-accept]");
        confirmAccept.addEventListener("click", function () {
            if (!pendingDelete) { return; }

            var button = this;
            var body = new FormData();
            body.append("id", pendingDelete);
            body.append("employeeId", employeeId);

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

        loadGrid();
    })();

    /* ======================================================= documents === */

    // Documents tab on the Profile page: every active document type, grouped
    // under its Document Section header row, with one upload slot per type.
    // Uploads save immediately (one POST per file) and the grid is reloaded
    // from the server afterwards - same fetch-and-swap pattern as Dependents.
    // Search / filters / collapsed sections are client-side and survive the
    // reload.
    (function initDocuments() {
        var slot = document.getElementById("documents-slot");
        if (!slot) { return; }

        var employeeId = slot.dataset.employeeId;
        var urls = {
            grid: slot.dataset.gridUrl,
            upload: "/employees/documents/upload",
            remove: "/employees/documents/delete"
        };
        var ALLOWED = ["pdf", "jpg", "jpeg", "png"];

        var state = { search: "", req: "", status: "", collapsed: {} };
        var loaded = false;

        var confirmEl = document.getElementById("document-confirm-modal");
        var confirmModal = null;
        var pendingRemove = null;

        function root() { return slot.querySelector("[data-docs-root]"); }

        function loadGrid() {
            slot.setAttribute("aria-busy", "true");

            return HRMS.getHtml(urls.grid)
                .then(function (html) {
                    slot.innerHTML = html;
                    restoreControls();
                    applyView();
                })
                .catch(function (error) {
                    slot.innerHTML =
                        '<div class="hrms-card"><div class="hrms-empty">' +
                        '<p class="hrms-empty__title">' + HRMS.escape(HRMS.t("js.documents_load_failed", "Documents could not be loaded")) + '</p>' +
                        '<p class="hrms-empty__text"></p>' +
                        '<button type="button" class="btn btn-outline-secondary" data-docs-reload>' + HRMS.escape(HRMS.t("js.try_again", "Try again")) + '</button>' +
                        '</div></div>';
                    slot.querySelector(".hrms-empty__text").textContent = error.message;
                })
                .finally(function () { slot.setAttribute("aria-busy", "false"); });
        }

        // The grid only loads when the Documents tab is first shown (or
        // straight away if the page opened on it), not on every Profile visit.
        function ensureLoaded() {
            if (loaded) { return; }
            loaded = true;
            loadGrid();
        }

        var tabButton = document.getElementById("tab-documents-btn");
        var pane = document.getElementById("tab-documents");
        if (pane && pane.classList.contains("active")) {
            ensureLoaded();
        } else if (tabButton) {
            tabButton.addEventListener("shown.bs.tab", ensureLoaded);
        } else {
            ensureLoaded();
        }

        /* ------------------------------------------------ filter / view --- */

        function restoreControls() {
            var r = root();
            if (!r) { return; }
            var search = r.querySelector("[data-docs-search]");
            var req = r.querySelector("[data-docs-filter-req]");
            var status = r.querySelector("[data-docs-filter-status]");
            if (search) { search.value = state.search; }
            if (req) { req.value = state.req; }
            if (status) { status.value = state.status; }
        }

        function rowMatches(row) {
            var q = state.search.trim().toLowerCase();
            if (q && (row.dataset.name || "").indexOf(q) === -1) { return false; }
            if (state.req === "m" && row.dataset.mandatory !== "true") { return false; }
            if (state.req === "o" && row.dataset.mandatory === "true") { return false; }
            if (state.status === "up" && row.dataset.uploaded !== "true") { return false; }
            if (state.status === "miss" && row.dataset.uploaded === "true") { return false; }
            return true;
        }

        function applyView() {
            var r = root();
            if (!r) { return; }

            var rows = Array.prototype.slice.call(r.querySelectorAll(".hrms-docs-row"));
            var shown = 0;
            var visibleBySection = {};

            rows.forEach(function (row) {
                var match = rowMatches(row);
                var section = row.dataset.section;
                if (match) {
                    shown++;
                    visibleBySection[section] = true;
                }
                row.hidden = !match || !!state.collapsed[section];
            });

            r.querySelectorAll("[data-section-row]").forEach(function (header) {
                var key = header.dataset.sectionRow;
                var collapsed = !!state.collapsed[key];
                header.hidden = !visibleBySection[key];
                header.classList.toggle("is-collapsed", collapsed);
                var button = header.querySelector("[data-docs-section]");
                if (button) { button.setAttribute("aria-expanded", collapsed ? "false" : "true"); }
            });

            var noResults = r.querySelector("[data-docs-noresults]");
            if (noResults) { noResults.hidden = shown > 0; }

            var count = r.querySelector("[data-docs-count]");
            if (count) { count.textContent = HRMS.t("js.docs_count_of", "{0} of {1} documents", shown, rows.length); }

            var toggleAll = r.querySelector("[data-docs-toggle-all]");
            var headers = r.querySelectorAll("[data-section-row]");
            var allCollapsed = headers.length > 0 && Array.prototype.every.call(headers, function (h) {
                return !!state.collapsed[h.dataset.sectionRow];
            });
            if (toggleAll) { toggleAll.textContent = allCollapsed ? HRMS.t("js.expand_all", "Expand all") : HRMS.t("js.collapse_all", "Collapse all"); }
        }

        slot.addEventListener("input", function (event) {
            if (event.target.matches("[data-docs-search]")) {
                state.search = event.target.value;
                applyView();
            }
        });

        slot.addEventListener("change", function (event) {
            var target = event.target;

            if (target.matches("[data-docs-filter-req]")) {
                state.req = target.value;
                applyView();
                return;
            }

            if (target.matches("[data-docs-filter-status]")) {
                state.status = target.value;
                applyView();
                return;
            }

            if (target.matches("[data-docs-file]") && target.files && target.files[0]) {
                upload(target.closest("tr"), target.files[0]);
                target.value = "";
            }
        });

        /* ------------------------------------------------------- upload --- */

        function showRowError(row, message) {
            var span = row ? row.querySelector("[data-docs-error]") : null;
            if (span) { span.textContent = message || ""; }
            var zone = row ? row.querySelector(".hrms-upload") : null;
            if (zone) { zone.classList.toggle("is-invalid", !!message); }
        }

        function validate(file) {
            var ext = (file.name.split(".").pop() || "").toLowerCase();
            var maxMb = parseInt((root() || slot).dataset.maxMb || "5", 10);
            if (ALLOWED.indexOf(ext) === -1) { return HRMS.t("js.only_pdf_jpg_png", "Only PDF, JPG or PNG files can be uploaded."); }
            if (file.size > maxMb * 1024 * 1024) {
                return HRMS.t("js.file_too_large", "The file is {0} MB - the limit is {1} MB.", (file.size / 1048576).toFixed(1), maxMb);
            }
            if (file.size === 0) { return HRMS.t("js.file_empty", "This file is empty."); }
            return null;
        }

        function upload(row, file) {
            if (!row) { return; }

            var error = validate(file);
            showRowError(row, error);
            if (error) { return; }

            var body = new FormData();
            body.append("employeeId", employeeId);
            body.append("documentTypeId", row.dataset.typeId);
            body.append("file", file, file.name);

            row.classList.add("is-uploading");
            row.setAttribute("aria-busy", "true");

            HRMS.post(urls.upload, body)
                .then(function (result) {
                    if (result.success) {
                        HRMS.toast(HRMS.t("js.doc_uploaded", "{0} uploaded.", row.dataset.labelName || HRMS.t("js.document", "Document")), "success");
                        return loadGrid();
                    }
                    showRowError(row, result.message);
                    HRMS.toast(result.message, "error");
                })
                .catch(function (err) {
                    showRowError(row, err.message);
                    HRMS.toast(err.message, "error");
                })
                .finally(function () {
                    row.classList.remove("is-uploading");
                    row.removeAttribute("aria-busy");
                });
        }

        // Drag and drop onto an empty upload slot.
        ["dragenter", "dragover"].forEach(function (type) {
            slot.addEventListener(type, function (event) {
                var zone = event.target.closest("[data-docs-drop]");
                if (!zone) { return; }
                event.preventDefault();
                zone.classList.add("is-dragover");
            });
        });

        ["dragleave", "drop"].forEach(function (type) {
            slot.addEventListener(type, function (event) {
                var zone = event.target.closest("[data-docs-drop]");
                if (!zone) { return; }
                event.preventDefault();
                zone.classList.remove("is-dragover");
                if (type === "drop" && event.dataTransfer && event.dataTransfer.files[0]) {
                    upload(zone.closest("tr"), event.dataTransfer.files[0]);
                }
            });
        });

        /* ------------------------------------------- clicks: sections etc --- */

        slot.addEventListener("click", function (event) {
            if (event.target.closest("[data-docs-reload]")) {
                loadGrid();
                return;
            }

            var sectionButton = event.target.closest("[data-docs-section]");
            if (sectionButton) {
                var key = sectionButton.dataset.docsSection;
                state.collapsed[key] = !state.collapsed[key];
                applyView();
                return;
            }

            if (event.target.closest("[data-docs-toggle-all]")) {
                var r = root();
                var headers = r ? r.querySelectorAll("[data-section-row]") : [];
                var allCollapsed = Array.prototype.every.call(headers, function (h) {
                    return !!state.collapsed[h.dataset.sectionRow];
                });
                Array.prototype.forEach.call(headers, function (h) {
                    state.collapsed[h.dataset.sectionRow] = !allCollapsed;
                });
                applyView();
                return;
            }

            var removeButton = event.target.closest("[data-docs-remove]");
            if (removeButton && confirmEl) {
                var row = removeButton.closest("tr");
                pendingRemove = removeButton.dataset.docsRemove;
                confirmEl.querySelector("[data-document-confirm-name]").textContent =
                    (row && row.dataset.labelName) || HRMS.t("js.this_document", "this document");
                if (!confirmModal) { confirmModal = new bootstrap.Modal(confirmEl); }
                confirmModal.show();
            }
        });

        if (confirmEl) {
            confirmEl.querySelector("[data-document-confirm-accept]").addEventListener("click", function () {
                if (!pendingRemove) { return; }

                var button = this;
                var body = new FormData();
                body.append("id", pendingRemove);
                body.append("employeeId", employeeId);

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
                        pendingRemove = null;
                    });
            });
        }
    })();

    /* ==================================================== add wizard === */

    // Add Employee = the Profile page, one section at a time (Previous / Next):
    // Personal -> Employment -> Kuwait Compliance -> Dependents -> Documents.
    // Next on Employment saves the employee (creating it the first time, which
    // reloads the page at the Compliance step with the new id); Next on
    // Compliance saves that form; Dependents and Documents save as you go,
    // exactly as on the Edit page. Saving itself is initProfile()'s job - this
    // only moves between sections and decides when Next may advance.
    (function initWizard() {
        var root = document.querySelector("[data-wizard]");
        if (!root) { return; }

        var order = ["personal", "employment", "compliance", "dependents", "documents"];
        var employeeId = Number(root.dataset.employeeId) || 0;
        var current = Math.max(0, order.indexOf(root.dataset.start));
        var pending = null;   // "employee" | "compliance" while a Next-triggered save is running

        var employeeForm = document.getElementById("employee-form");
        var complianceForm = document.getElementById("compliance-form");
        var indicators = Array.prototype.slice.call(document.querySelectorAll("[data-step-indicator]"));
        var backButton = document.querySelector("[data-wizard-back]");
        var nextButton = document.querySelector("[data-wizard-next]");
        var finishButton = document.querySelector("[data-wizard-finish]");

        function paneOf(name) { return document.getElementById("tab-" + name); }

        function reveal(field) {
            if (!field) { return; }
            var pane = field.closest(".tab-pane");
            if (pane) {
                var idx = order.indexOf(pane.id.replace("tab-", ""));
                if (idx >= 0 && idx !== current) { show(idx); }
            }
            var collapse = field.closest(".accordion-collapse");
            if (collapse && !collapse.classList.contains("show") && window.bootstrap) {
                window.bootstrap.Collapse.getOrCreateInstance(collapse, { toggle: false }).show();
            }
            window.setTimeout(function () { field.focus(); }, 200);
        }

        function validate(name) {
            var pane = paneOf(name);
            if (!pane) { return true; }

            var invalid = null;
            pane.querySelectorAll("[required]").forEach(function (field) {
                var ok = typeof field.checkValidity === "function" ? field.checkValidity() : true;
                field.classList.toggle("is-invalid", !ok);
                if (!ok && !invalid) { invalid = field; }
            });

            if (invalid) {
                var label = invalid.closest("[class*='col-']");
                label = label && label.querySelector("label");
                reveal(invalid);
                HRMS.toast(HRMS.t("js.enter_field_before_continuing", "Enter {0} before continuing.", (label ? label.textContent.replace("*", "").trim() : invalid.name)), "error");
                return false;
            }
            return true;
        }

        function show(index) {
            current = Math.max(0, Math.min(order.length - 1, index));
            var button = document.getElementById("tab-" + order[current] + "-btn");
            if (button && window.bootstrap) { window.bootstrap.Tab.getOrCreateInstance(button).show(); }

            indicators.forEach(function (indicator) {
                var n = order.indexOf(indicator.dataset.stepIndicator);
                indicator.classList.toggle("is-active", n === current);
                indicator.classList.toggle("is-complete", n < current);
            });

            var last = current === order.length - 1;
            if (backButton) { backButton.classList.toggle("d-none", current === 0); }
            if (nextButton) { nextButton.classList.toggle("d-none", last); }
            // Creating the employee is the one step that needs an explicit confirmation.
            var nextLabel = document.querySelector("[data-wizard-next-label]");
            if (nextLabel) {
                nextLabel.textContent = (order[current] === "employment" && !employeeId) ? HRMS.t("js.create_employee_continue", "Create Employee & Continue") : HRMS.t("js.next", "Next");
            }
            if (finishButton) { finishButton.classList.toggle("d-none", !last); }
            window.scrollTo({ top: 0, behavior: "smooth" });
        }

        function submit(form) {
            if (typeof form.requestSubmit === "function") { form.requestSubmit(); }
            else { form.dispatchEvent(new Event("submit", { cancelable: true })); }
        }

        function next() {
            var name = order[current];

            if (name === "personal") {
                if (validate("personal")) { show(current + 1); }
                return;
            }
            if (name === "employment") {
                if (!validate("personal") || !validate("employment")) { return; }

                var confirmEl = !employeeId ? document.getElementById("create-employee-modal") : null;
                if (confirmEl && window.bootstrap) {
                    window.bootstrap.Modal.getOrCreateInstance(confirmEl).show();
                    return;
                }

                pending = "employee";
                submit(employeeForm);   // a new employee reloads at the Compliance step
                return;
            }
            if (name === "compliance" && complianceForm) {
                pending = "compliance";
                submit(complianceForm);
                return;
            }
            show(current + 1);
        }

        document.addEventListener("employee:saved", function () {
            if (pending !== "employee") { return; }
            pending = null;
            if (employeeId) { show(current + 1); }
        });
        document.addEventListener("compliance:saved", function () {
            if (pending !== "compliance") { return; }
            pending = null;
            show(current + 1);
        });
        document.addEventListener("form:invalid", function (event) {
            pending = null;
            reveal(event.detail && event.detail.field);
        });

        var acceptCreate = document.querySelector("[data-create-employee-accept]");
        if (acceptCreate) {
            acceptCreate.addEventListener("click", function () {
                var confirmEl = document.getElementById("create-employee-modal");
                if (confirmEl && window.bootstrap) { window.bootstrap.Modal.getOrCreateInstance(confirmEl).hide(); }
                pending = "employee";
                submit(employeeForm);   // creates the employee, then reloads at the Compliance step
            });
        }

        if (nextButton) { nextButton.addEventListener("click", next); }
        if (backButton) { backButton.addEventListener("click", function () { show(current - 1); }); }
        if (finishButton) {
            finishButton.addEventListener("click", function () {
                HRMS.toast(HRMS.t("js.employee_saved", "Employee saved."), "success");
                window.location.href = "/employees/profile/" + employeeId;
            });
        }

        // Enter must not save a half-filled employee - it behaves like Next.
        document.addEventListener("keydown", function (event) {
            if (event.key !== "Enter") { return; }
            var target = event.target;
            if (!target || target.tagName === "TEXTAREA" || target.tagName === "BUTTON" || !target.closest(".tab-pane")) { return; }
            if (target.closest("#dependent-modal, #dependents-slot, #documents-slot")) { return; }
            event.preventDefault();
            if (nextButton && !nextButton.classList.contains("d-none")) { next(); }
        });

        show(current);
    })();
})();
