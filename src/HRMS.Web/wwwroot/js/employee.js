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
                        if (result.success) { changed(); if (loaded) { loadGrid(); } }
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

    /* ============================================= payroll calendar (db/60) === */
    // The list holds every company's calendars; only the selected company's are
    // offered. Changing an assigned calendar asks for a reason (Audit Report).
    (function initPayrollCalendar() {
        var root = document.querySelector("[data-paycal]");
        var select = root && root.querySelector("[data-paycal-select]");
        var company = document.getElementById("f-CompanyId");
        if (!select || !company) { return; }

        var original = root.getAttribute("data-original") || "";
        var locked = root.getAttribute("data-locked") === "1";
        var none = root.querySelector("[data-paycal-none]");
        var reasonBox = document.querySelector("[data-paycal-reason]");
        var reasonInput = reasonBox && reasonBox.querySelector("input");

        function filter(pickDefault) {
            var co = company.value;
            var firstOfCompany = null, selectedVisible = false;
            Array.prototype.forEach.call(select.options, function (o) {
                if (!o.value) { return; }
                var mine = o.getAttribute("data-company") === co;
                o.hidden = !mine;
                o.disabled = !mine;
                if (mine && !firstOfCompany) { firstOfCompany = o; }   // default calendar first (server order)
                if (mine && o.selected) { selectedVisible = true; }
            });
            if (!locked && !selectedVisible) {
                select.value = pickDefault && firstOfCompany ? firstOfCompany.value : "";
            }
            // required once the company has a calendar (a company not on payroll yet has none)
            if (!locked) { select.required = !!firstOfCompany; }
            if (none) { none.hidden = !co || !!firstOfCompany; }
            syncReason();
        }

        function syncReason() {
            if (!reasonBox) { return; }
            var changed = !!original && select.value !== original;
            reasonBox.hidden = !changed;
            if (reasonInput) {
                reasonInput.required = changed;
                if (!changed) { reasonInput.value = ""; }
            }
        }

        company.addEventListener("change", function () { filter(true); });
        select.addEventListener("change", syncReason);
        filter(!original);
    })();

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

        // Saves one form; resolves true when it saved. options.quiet: no success toast
        // (Save Changes shows one for everything); options.button: the button showing "Saving…".
        function handleSubmit(form, url, onSuccess, options) {
            options = options || {};
            clearErrors(form);

            var submit = options.button || submitButtonFor(form);
            var label = submit ? submit.querySelector("span") : null;
            var original = label ? label.textContent : null;

            if (submit) { submit.disabled = true; }
            if (label) { label.textContent = HRMS.t("js.saving", "Saving…"); }

            return HRMS.post(url, new FormData(form))
                .then(function (result) {
                    if (result.success) {
                        if (!options.quiet) { HRMS.toast(result.message, "success"); }
                        if (onSuccess) { onSuccess(result); }
                        return true;
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
                    return false;
                })
                .catch(function (error) {
                    HRMS.toast(error.message, "error");
                    return false;
                })
                .finally(function () {
                    if (submit) { submit.disabled = false; }
                    if (label) { label.textContent = original; }
                });
        }

        function saveEmployee(options) {
            return handleSubmit(employeeForm, employeeForm.dataset.saveUrl || "/employees/save", function (result) {
                var idField = document.querySelector('[name="EmployeeId"][form="employee-form"]');
                var wasNew = idField && (!idField.value || idField.value === "0");

                if (wasNew && result.id) {
                    // A brand-new employee: land back on their own profile so
                    // Kuwait Compliance, Dependents and Documents (which need
                    // the new employee's id) become available. In the Add
                    // wizard, carry on at the next step.
                    var inWizard = Boolean(document.querySelector("[data-wizard]"));
                    HRMS.go("/employees/profile/" + result.id +
                        (inWizard ? "?wizard=true&tab=compliance" : ""));
                    return;
                }

                if (idField) { idField.value = result.id; }
                document.dispatchEvent(new CustomEvent("employee:saved", { detail: { result: result } }));
            }, options);
        }

        // Kuwait Compliance is saved with Save Changes when something in it was changed
        var complianceDirty = false;
        function saveCompliance(options) {
            return handleSubmit(complianceForm, complianceForm.dataset.saveUrl || "/employees/compliance/save", function (result) {
                complianceDirty = false;
                document.dispatchEvent(new CustomEvent("compliance:saved", { detail: { result: result } }));
            }, options);
        }
        if (complianceForm) {
            ["input", "change"].forEach(function (type) {
                complianceForm.addEventListener(type, function () { complianceDirty = true; });
            });
        }

        // Save Changes (next to the employee's name): one click saves every section the
        // user may edit - Personal Info / Employment, then Kuwait Compliance.
        var saveAllButton = document.querySelector("[data-save-all]");
        function saveAll() {
            var doEmployee = saveAllButton.dataset.saveEmployee === "true" && employeeForm;
            var doCompliance = saveAllButton.dataset.saveCompliance === "true" && complianceForm && complianceDirty;
            var options = { quiet: true, button: saveAllButton };

            var chain = Promise.resolve(true);
            if (doEmployee) { chain = chain.then(function () { return saveEmployee(options); }); }
            if (doCompliance) {
                chain = chain.then(function (ok) {
                    if (!ok) { return false; }
                    return saveCompliance(options).then(function (saved) {
                        if (!saved) { document.dispatchEvent(new CustomEvent("profile:show-tab", { detail: { tab: "compliance" } })); }
                        return saved;
                    });
                });
            }
            chain.then(function (ok) {
                if (!ok) { return; }
                if (!doEmployee && !doCompliance) { HRMS.toast(HRMS.t("js.nothing_to_save", "There are no changes to save."), "info"); return; }
                // saved: say so, then back to the Employees page (the message shows there too)
                var message = HRMS.t("js.changes_saved_successfully", "Changes saved successfully.");
                if (document.documentElement.classList.contains("hrms-embed") && window.parent !== window) {
                    // inside the Dashboard's alert popup: the Dashboard closes it and shows the message
                    window.parent.postMessage({ type: "hrms:employee-saved", close: true, message: message }, window.location.origin);
                    return;
                }
                HRMS.toast(message, "success");
                HRMS.flash(message, "success");
                saveAllButton.disabled = true;
                window.setTimeout(function () { window.location.href = "/employees"; }, 900);
            });
        }

        if (employeeForm) {
            employeeForm.addEventListener("submit", function (event) {
                event.preventDefault();
                // the Add wizard saves one step at a time; elsewhere Save Changes saves everything
                if (saveAllButton && !document.querySelector("[data-wizard]")) { saveAll(); }
                else { saveEmployee(); }
            });
        }

        if (complianceForm) {
            complianceForm.addEventListener("submit", function (event) {
                event.preventDefault();
                // Enter in a compliance field, or the wizard's Next: same as Save Changes outside the wizard
                if (saveAllButton && !document.querySelector("[data-wizard]")) { saveAll(); }
                else { saveCompliance(); }
            });
        }

        // a section that failed to save is brought into view
        document.addEventListener("profile:show-tab", function (event) {
            var button = document.getElementById("tab-" + event.detail.tab + "-btn");
            if (button && window.bootstrap) { bootstrap.Tab.getOrCreateInstance(button).show(); }
        });
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
        var replaceEl = document.getElementById("document-replace-modal");
        var pendingReplace = null;
        var viewerEl = document.getElementById("document-viewer-modal");

        function root() { return slot.querySelector("[data-docs-root]"); }

        // the Kuwait Compliance images (db/71) show the same files: each side tells the other
        function changed() { document.dispatchEvent(new CustomEvent("hrms:documents-changed", { detail: { source: "documents" } })); }
        document.addEventListener("hrms:documents-changed", function (event) {
            if (loaded && (!event.detail || event.detail.source !== "documents")) { loadGrid(); }
        });

        /** Removes one file after the "Remove document" confirmation (also used by Kuwait Compliance). */
        HRMS.removeDocument = function (attachmentId, name) {
            if (!confirmEl) { return; }
            pendingRemove = attachmentId;
            confirmEl.querySelector("[data-document-confirm-name]").textContent = name || HRMS.t("js.this_document", "this document");
            if (!confirmModal) { confirmModal = new bootstrap.Modal(confirmEl); }
            confirmModal.show();
        };

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
                var fileRow = target.closest("tr");
                var chosen = target.files[0];
                target.value = "";
                // A file is already on record: replacing it is destructive, so ask first.
                if (fileRow && fileRow.dataset.uploaded === "true" && replaceEl) {
                    pendingReplace = { row: fileRow, file: chosen };
                    replaceEl.querySelector("[data-document-replace-name]").textContent =
                        fileRow.dataset.labelName || HRMS.t("js.this_document", "this document");
                    bootstrap.Modal.getOrCreateInstance(replaceEl).show();
                    return;
                }
                upload(fileRow, chosen);
            }
        });

        if (replaceEl) {
            replaceEl.querySelector("[data-document-replace-accept]").addEventListener("click", function () {
                var job = pendingReplace;
                pendingReplace = null;
                bootstrap.Modal.getOrCreateInstance(replaceEl).hide();
                if (job) { upload(job.row, job.file); }
            });
            replaceEl.addEventListener("hidden.bs.modal", function () { pendingReplace = null; });
        }

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
                        changed();
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

            var viewButton = event.target.closest("[data-docs-view]");
            if (viewButton && viewerEl) {
                event.preventDefault();
                openViewer(viewButton);
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

        /* ------------------------------------------------------- viewer --- */

        // Images and PDFs open in a popup (not a new tab) that can be maximised
        // to the full window and restored, like a normal window.
        function setViewerMaximized(on) {
            var dialog = viewerEl.querySelector("[data-docview-dialog]");
            var sizeButton = viewerEl.querySelector("[data-docview-size]");
            var label = on ? sizeButton.dataset.titleRestore : sizeButton.dataset.titleMax;
            dialog.classList.toggle("modal-fullscreen", on);
            dialog.classList.toggle("modal-dialog-centered", !on);
            dialog.classList.toggle("modal-xl", !on);
            viewerEl.classList.toggle("is-maximized", on);
            sizeButton.setAttribute("aria-pressed", on ? "true" : "false");
            sizeButton.title = label;
            sizeButton.setAttribute("aria-label", label);
            sizeButton.querySelector("[data-docview-icon-max]").hidden = on;
            sizeButton.querySelector("[data-docview-icon-restore]").hidden = !on;
        }

        function openViewer(button) {
            var url = button.dataset.docsView;
            var type = (button.dataset.docsType || "").toLowerCase();
            var name = button.dataset.docsName || "";
            var body = viewerEl.querySelector("[data-docview-body]");

            viewerEl.querySelector("[data-docview-title]").textContent = button.dataset.docsTitle || name;
            viewerEl.querySelector("[data-docview-file]").textContent = name;
            viewerEl.querySelector("[data-docview-download]").href = url + (url.indexOf("?") === -1 ? "?" : "&") + "download=true";
            body.innerHTML = "";

            if (type.indexOf("image/") === 0 || /\.(jpe?g|png)$/i.test(name)) {
                var img = document.createElement("img");
                img.className = "doc-viewer__img";
                img.src = url;
                img.alt = name;
                img.title = HRMS.t("js.docview_zoom", "Click to toggle actual size");
                img.addEventListener("click", function () { img.classList.toggle("is-actual"); });
                body.appendChild(img);
            } else {
                var frame = document.createElement("iframe");
                frame.className = "doc-viewer__frame";
                frame.src = url;
                frame.title = name;
                body.appendChild(frame);
            }

            setViewerMaximized(false);
            bootstrap.Modal.getOrCreateInstance(viewerEl).show();
        }

        // an image or PDF anywhere else on the page (Kuwait Compliance, previous images) opens here too
        // (from inside another popup, e.g. Previous images, that popup steps aside and comes back after)
        var returnTo = null;
        document.addEventListener("click", function (event) {
            var viewButton = event.target.closest("[data-docs-view]");
            if (!viewButton || !viewerEl || slot.contains(viewButton)) { return; }
            event.preventDefault();
            var parent = viewButton.closest(".modal.show");
            if (parent && parent !== viewerEl) {
                returnTo = parent;
                parent.addEventListener("hidden.bs.modal", function () { openViewer(viewButton); }, { once: true });
                bootstrap.Modal.getOrCreateInstance(parent).hide();
                return;
            }
            openViewer(viewButton);
        });

        if (viewerEl) {
            viewerEl.querySelector("[data-docview-size]").addEventListener("click", function () {
                setViewerMaximized(this.getAttribute("aria-pressed") !== "true");
            });
            viewerEl.addEventListener("hidden.bs.modal", function () {
                viewerEl.querySelector("[data-docview-body]").innerHTML = "";
                setViewerMaximized(false);
                if (returnTo) { bootstrap.Modal.getOrCreateInstance(returnTo).show(); returnTo = null; }
            });
        }

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
                        if (result.success) { changed(); if (loaded) { loadGrid(); } }
                    })
                    .catch(function (error) { HRMS.toast(error.message, "error"); })
                    .finally(function () {
                        button.disabled = false;
                        pendingRemove = null;
                    });
            });
        }
    })();

    /* ================================ Kuwait Compliance images (db/71) === */

    // Civil ID, Passport, Residency and Work Permit images inside their Kuwait
    // Compliance sections: view, upload, confirm them against the expiry date;
    // near the expiry a new image waits as a renewal until it is confirmed with
    // the new date, and the old one is archived ("Previous images").
    (function initComplianceImages() {
        var form = document.getElementById("compliance-form");
        var url = form && form.dataset.kcdUrl;
        if (!url) { return; }

        var employeeId = form.dataset.kcdEmployee;
        var names = document.querySelector("[data-kcd-names]");
        var confirmEl = document.getElementById("kcd-confirm-modal");
        var confirmForm = confirmEl.querySelector("[data-kcd-confirm-form]");
        var historyEl = document.getElementById("kcd-history-modal");
        var ALLOWED = ["pdf", "jpg", "jpeg", "png"];
        var FIELDS = {
            CIVIL_ID: ["CivilIdExpiryDate", "CivilIdNumber"],
            PASSPORT: ["PassportExpiryDate", "PassportNumber"],
            RESIDENCY: ["ResidencyExpiryDate", "ResidencyNumber"],
            WORK_PERMIT: ["WorkPermitExpiryDate", "WorkPermitNumber"]
        };
        var maxMb = 5;
        var pending = null;   // { key, renewal }

        function itemName(key) { return (names && names.getAttribute("data-" + key.toLowerCase())) || key; }
        function field(name) { return form.querySelector('[name="' + name + '"]'); }

        function load() {
            return HRMS.getHtml(url).then(function (html) {
                var holder = document.createElement("div");
                holder.innerHTML = html;
                var rootEl = holder.querySelector("[data-kcd-root]");
                if (rootEl) { maxMb = parseInt(rootEl.dataset.maxMb, 10) || maxMb; }
                holder.querySelectorAll("[data-kcd-group]").forEach(function (group) {
                    var target = form.querySelector('[data-kcd-slot="' + group.dataset.kcdGroup + '"]');
                    if (target) { target.innerHTML = ""; target.appendChild(group); }
                });
            }).catch(function () {
                form.querySelectorAll("[data-kcd-slot]").forEach(function (target) { target.innerHTML = ""; });
            });
        }

        function upload(input) {
            var file = input.files && input.files[0];
            var item = input.closest(".kcd__item");
            var error = item && item.querySelector("[data-kcd-error]");
            input.value = "";
            if (!file) { return; }
            if (error) { error.textContent = ""; }
            var ext = (file.name.split(".").pop() || "").toLowerCase();
            if (ALLOWED.indexOf(ext) === -1) {
                if (error) { error.textContent = HRMS.t("js.only_pdf_jpg_png", "Only PDF, JPG or PNG files can be uploaded."); }
                return;
            }
            if (file.size > maxMb * 1024 * 1024) {
                if (error) { error.textContent = HRMS.t("js.kcd_too_big", "The file is larger than {0} MB.", maxMb); }
                return;
            }
            var body = new FormData();
            body.append("employeeId", employeeId);
            body.append("documentTypeId", input.dataset.kcdFile);
            body.append("file", file);
            if (item) { item.classList.add("is-busy"); }
            HRMS.post("/employees/documents/upload", body)
                .then(function (result) {
                    HRMS.toast(result.message, result.success ? "success" : "error");
                    if (result.success) {
                        document.dispatchEvent(new CustomEvent("hrms:documents-changed", { detail: { source: "compliance" } }));
                        return load();
                    }
                })
                .catch(function (err) { HRMS.toast(err.message, "error"); })
                .finally(function () { if (item) { item.classList.remove("is-busy"); } });
        }

        function openConfirm(key, renewal) {
            pending = { key: key, renewal: renewal };
            var mode = renewal ? "renewal" : "first";
            var group = form.querySelector('[data-kcd-group="' + key + '"]');
            var expiryField = field(FIELDS[key][0]);
            var numberField = field(FIELDS[key][1]);
            var expiry = confirmForm.querySelector("[data-kcd-expiry]");
            var number = confirmForm.querySelector("[data-kcd-number]");
            var previous = confirmForm.querySelector("[data-kcd-previous]");
            var current = group ? group.dataset.confirmedExpiry : "";

            confirmForm.querySelector("[data-kcd-confirm-title]").textContent =
                (names.dataset[renewal ? "textRenewal" : "textConfirm"] || "").replace("{0}", itemName(key));
            ["[data-kcd-confirm-hint]", "[data-kcd-expiry-label]", "[data-kcd-confirm-button]"].forEach(function (sel) {
                var el = confirmForm.querySelector(sel);
                el.textContent = el.getAttribute("data-text-" + mode) || "";
            });
            // first time: the date already on the form; a renewal: the new date is entered
            var onForm = expiryField ? expiryField.value : "";
            expiry.value = !renewal ? onForm : (current && onForm > current ? onForm : "");
            expiry.min = renewal && current ? current : "";
            number.value = numberField ? numberField.value : "";
            number.maxLength = numberField && numberField.maxLength > 0 ? numberField.maxLength : 50;
            previous.textContent = renewal && current ? previous.dataset.text.replace("{0}", group.dataset.confirmedExpiryText || current) : "";
            previous.hidden = !(renewal && current);
            confirmForm.querySelector("[data-kcd-confirm-error]").textContent = "";
            bootstrap.Modal.getOrCreateInstance(confirmEl).show();
            window.setTimeout(function () { expiry.focus(); }, 300);
        }

        confirmForm.addEventListener("submit", function (event) {
            event.preventDefault();
            if (!pending) { return; }
            var expiry = confirmForm.querySelector("[data-kcd-expiry]");
            var number = confirmForm.querySelector("[data-kcd-number]");
            var error = confirmForm.querySelector("[data-kcd-confirm-error]");
            error.textContent = "";
            if (!expiry.value) {
                error.textContent = HRMS.t("js.kcd_expiry_needed", "Enter the expiry date the images apply to.");
                expiry.focus();
                return;
            }
            var submit = confirmForm.querySelector("[data-kcd-confirm-submit]");
            var body = new FormData();
            body.append("employeeId", employeeId);
            body.append("key", pending.key);
            body.append("expiryDate", expiry.value);
            body.append("number", number.value.trim());
            submit.disabled = true;
            HRMS.post("/employees/documents/compliance/confirm", body)
                .then(function (result) {
                    if (!result.success) { error.textContent = result.message; return; }
                    HRMS.toast(result.message, "success");
                    // the date (and number) are saved: the form shows them, so Save Changes keeps them
                    var expiryField = field(FIELDS[pending.key][0]);
                    var numberField = field(FIELDS[pending.key][1]);
                    if (expiryField) { expiryField.value = expiry.value; expiryField.defaultValue = expiry.value; }
                    if (numberField && number.value.trim()) { numberField.value = number.value.trim(); numberField.defaultValue = numberField.value; }
                    bootstrap.Modal.getOrCreateInstance(confirmEl).hide();
                    document.dispatchEvent(new CustomEvent("hrms:documents-changed", { detail: { source: "compliance" } }));
                    return load();
                })
                .catch(function (err) { error.textContent = err.message; })
                .finally(function () { submit.disabled = false; });
        });

        function openHistory(key) {
            var body = historyEl.querySelector("[data-kcd-history-body]");
            historyEl.querySelector("[data-kcd-history-title]").textContent = (names.dataset.textHistory || "{0}").replace("{0}", itemName(key));
            body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
            bootstrap.Modal.getOrCreateInstance(historyEl).show();
            HRMS.getHtml(url + "/history?key=" + encodeURIComponent(key))
                .then(function (html) { body.innerHTML = html; })
                .catch(function (err) { body.textContent = err.message; });
        }

        form.addEventListener("change", function (event) {
            if (event.target.matches("[data-kcd-file]")) { upload(event.target); }
        });

        form.addEventListener("click", function (event) {
            var history = event.target.closest("[data-kcd-history]");
            if (history) { event.preventDefault(); openHistory(history.dataset.kcdHistory); return; }
            var confirmButton = event.target.closest("[data-kcd-confirm]");
            if (confirmButton) { openConfirm(confirmButton.dataset.kcdConfirm, confirmButton.dataset.renewal === "1"); return; }
            var discard = event.target.closest("[data-kcd-discard]");
            if (discard && HRMS.removeDocument) { HRMS.removeDocument(discard.dataset.kcdDiscard, discard.dataset.name); }
        });

        document.addEventListener("hrms:documents-changed", function (event) {
            if (!event.detail || event.detail.source !== "compliance") { load(); }
        });

        load();
    })();

    /* ============================================ date field alerts (db/65) === */

    // The bell next to a date field (administrators): reminders like a phone's -
    // N months / weeks / days before the date, or on the day. They belong to the
    // field, so they apply to that date of every employee.
    (function initDateAlerts() {
        var modalEl = document.getElementById("date-alert-modal");
        if (!modalEl) { return; }

        var list = modalEl.querySelector("[data-alert-list]");
        var empty = modalEl.querySelector("[data-alert-empty]");
        var error = modalEl.querySelector("[data-alert-error]");
        var template = modalEl.querySelector("[data-alert-template]");
        var saveButton = modalEl.querySelector("[data-alert-save]");
        var current = null;   // the bell being edited
        var opened = "";      // the alerts as the popup opened (to tell whether anything changed)
        var discard = false;  // Cancel: close without saving
        var UNIT_ORDER = { M: 3, W: 2, D: 1 };
        var DAYS = { M: 30, W: 7, D: 1 };

        function unitText(unit, value) {
            if (value === 1) {
                return unit === "M" ? HRMS.t("js.alert_1_month", "1 month") : unit === "W" ? HRMS.t("js.alert_1_week", "1 week") : HRMS.t("js.alert_1_day", "1 day");
            }
            return unit === "M" ? HRMS.t("js.alert_n_months", "{0} months", value)
                 : unit === "W" ? HRMS.t("js.alert_n_weeks", "{0} weeks", value)
                 : HRMS.t("js.alert_n_days", "{0} days", value);
        }

        // "On the day" / "2 months before"
        function ruleText(unit, value) {
            return value === 0 ? HRMS.t("js.alert_on_the_day", "On the day")
                               : HRMS.t("js.alert_before", "{0} before", unitText(unit, value));
        }

        // "M2,W1,D0" -> rules, one of each
        function parseRules(csv) {
            var seen = {};
            return (csv || "").split(",").filter(Boolean).map(function (token) {
                return { unit: token.charAt(0), value: parseInt(token.slice(1), 10) || 0 };
            }).filter(function (r) { var key = r.unit + r.value; if (seen[key]) { return false; } seen[key] = true; return true; });
        }

        // earliest reminder first, "on the day" last - the order they go off
        function sortRules(rules) {
            return rules.sort(function (a, b) { return b.value * DAYS[b.unit] - a.value * DAYS[a.unit] || UNIT_ORDER[b.unit] - UNIT_ORDER[a.unit]; });
        }

        function readRows() {
            return Array.prototype.map.call(list.children, function (row) {
                return {
                    row: row,
                    unit: row.querySelector("[data-alert-unit]").value,
                    raw: row.querySelector("[data-alert-value]").value.trim(),
                    value: parseInt(row.querySelector("[data-alert-value]").value, 10)
                };
            });
        }

        function refresh() {
            var rows = readRows();
            empty.hidden = rows.length > 0;
            rows.forEach(function (r) {
                var valid = r.raw !== "" && !isNaN(r.value) && r.value >= 0 && r.value <= 99;
                r.row.querySelector("[data-alert-when]").textContent = !valid ? "" :
                    r.value === 0 ? HRMS.t("js.alert_on_the_day", "On the day") : HRMS.t("js.alert_before_word", "before");
                r.row.querySelector("[data-alert-unit]").hidden = valid && r.value === 0;
                r.row.classList.toggle("is-on-the-day", valid && r.value === 0);
            });
            // a quick option is "on" while the same alert is in the list
            modalEl.querySelectorAll("[data-alert-preset]").forEach(function (chip) {
                var unit = chip.dataset.unit;
                var value = parseInt(chip.dataset.value, 10);
                var on = rows.some(function (r) { return r.value === value && (value === 0 || r.unit === unit); });
                chip.classList.toggle("is-on", on);
                chip.setAttribute("aria-pressed", on ? "true" : "false");
            });
            modalEl.querySelector("[data-alert-add]").disabled = rows.length >= 10;
        }

        function addRow(unit, value, focus) {
            var row = template.content.firstElementChild.cloneNode(true);
            row.querySelector("[data-alert-unit]").value = unit || "D";
            row.querySelector("[data-alert-value]").value = value === undefined || value === null ? "" : value;
            list.appendChild(row);
            refresh();
            if (focus) { row.querySelector("[data-alert-value]").focus(); }
            return row;
        }

        function setBell(bell, rules) {
            var csv = rules.map(function (r) { return r.unit + r.value; }).join(",");
            bell.dataset.rules = csv;
            bell.classList.toggle("is-set", rules.length > 0);
            bell.querySelector("[data-date-alert-count]").textContent = rules.length ? rules.length : "";
            var name = bell.dataset.fieldName;
            bell.title = rules.length
                ? name + " - " + rules.map(function (r) { return ruleText(r.unit, r.value); }).join(", ")
                : HRMS.t("js.alert_none_set", "{0}: no alerts set", name);
        }

        // presets carry their own text
        modalEl.querySelectorAll("[data-alert-preset]").forEach(function (chip) {
            var value = parseInt(chip.dataset.value, 10);
            chip.textContent = value === 0 ? HRMS.t("js.alert_on_the_day", "On the day") : unitText(chip.dataset.unit, value);
        });
        document.querySelectorAll("[data-date-alert]").forEach(function (bell) { setBell(bell, parseRules(bell.dataset.rules)); });

        document.addEventListener("click", function (event) {
            var bell = event.target.closest("[data-date-alert]");
            if (!bell) { return; }
            event.preventDefault();
            current = bell;
            modalEl.querySelector("[data-alert-field]").textContent = bell.dataset.fieldName;
            error.textContent = "";
            list.innerHTML = "";
            sortRules(parseRules(bell.dataset.rules)).forEach(function (r) { addRow(r.unit, r.value); });
            refresh();
            opened = rulesCsv(collect() || []);
            discard = false;
            bootstrap.Modal.getOrCreateInstance(modalEl).show();
        });

        modalEl.addEventListener("click", function (event) {
            var chip = event.target.closest("[data-alert-preset]");
            if (chip) {
                var unit = chip.dataset.unit;
                var value = parseInt(chip.dataset.value, 10);
                var match = readRows().filter(function (r) { return r.value === value && (value === 0 || r.unit === unit); });
                if (match.length) { match.forEach(function (r) { r.row.remove(); }); refresh(); }
                else if (list.children.length < 10) { addRow(unit, value); }
                error.textContent = "";
                return;
            }
            if (event.target.closest("[data-alert-add]")) {
                addRow("D", "", true);
                return;
            }
            var remove = event.target.closest("[data-alert-remove]");
            if (remove) {
                remove.closest("li").remove();
                refresh();
            }
        });

        modalEl.addEventListener("input", function () { error.textContent = ""; refresh(); });
        modalEl.addEventListener("change", refresh);

        // the rows as rules (one of each, earliest first); null when a row is not a valid number
        function collect() {
            // a row whose number was cleared counts as deleted, like the bin
            var rows = readRows().filter(function (r) { return r.raw !== ""; });
            var bad = rows.filter(function (r) { return isNaN(r.value) || r.value < 0 || r.value > 99 || String(r.value) !== r.raw.replace(/^0+(?=\d)/, ""); });
            modalEl.querySelectorAll(".hrms-alerts__value").forEach(function (input) { input.classList.remove("is-invalid"); });
            if (bad.length) {
                bad.forEach(function (r) { r.row.querySelector("[data-alert-value]").classList.add("is-invalid"); });
                return null;
            }
            var seen = {};
            return sortRules(rows.map(function (r) { return { unit: r.value === 0 ? "D" : r.unit, value: r.value }; })
                .filter(function (r) { var key = r.unit + r.value; if (seen[key]) { return false; } seen[key] = true; return true; }));
        }

        function rulesCsv(rules) { return rules.map(function (r) { return r.unit + r.value; }).join(","); }

        function save() {
            if (!current) { return Promise.resolve(false); }
            var rules = collect();
            if (rules === null) {
                error.textContent = HRMS.t("js.alert_value_invalid", "Enter a whole number from 0 to 99 for each alert.");
                var firstBad = modalEl.querySelector(".hrms-alerts__value.is-invalid");
                if (firstBad) { firstBad.focus(); }
                return Promise.resolve(false);
            }

            var body = new FormData();
            body.append("fieldKey", current.dataset.dateAlert);
            rules.forEach(function (r) { body.append("units", r.unit); body.append("values", r.value); });

            saveButton.disabled = true;
            return HRMS.post(modalEl.dataset.saveUrl, body)
                .then(function (result) {
                    if (!result.success) { error.textContent = result.message; return false; }
                    // the alerts as stored on the server, read back after the save
                    var stored = sortRules(parseRules(typeof result.rules === "string" ? result.rules : rulesCsv(rules)));
                    // the same field can have a bell in more than one place
                    document.querySelectorAll('[data-date-alert="' + current.dataset.dateAlert + '"]').forEach(function (bell) { setBell(bell, stored); });
                    opened = rulesCsv(stored);
                    if (opened !== rulesCsv(rules)) {
                        // the database kept something else than was sent: say so instead of "saved"
                        list.innerHTML = "";
                        stored.forEach(function (r) { addRow(r.unit, r.value); });
                        error.textContent = HRMS.t("js.alert_not_stored", "The database did not store these alerts as entered - it holds the ones shown. Run db/65 again, then retry.");
                        return false;
                    }
                    HRMS.toast(result.message, "success");
                    return true;
                })
                .catch(function (err) { error.textContent = err.message; return false; })
                .finally(function () { saveButton.disabled = false; });
        }

        saveButton.addEventListener("click", function () {
            save().then(function (ok) { if (ok) { discard = true; bootstrap.Modal.getOrCreateInstance(modalEl).hide(); } });
        });

        // Cancel throws the changes away; closing any other way (X, Esc, outside) keeps them, like a phone
        modalEl.querySelector("[data-alert-cancel]").addEventListener("click", function () {
            discard = true;
            bootstrap.Modal.getOrCreateInstance(modalEl).hide();
        });
        modalEl.addEventListener("hide.bs.modal", function (event) {
            if (discard || !current) { return; }
            var rules = collect();
            if (rules !== null && rulesCsv(rules) === opened) { return; }   // nothing changed
            event.preventDefault();
            save().then(function (ok) { if (ok) { discard = true; bootstrap.Modal.getOrCreateInstance(modalEl).hide(); } });
        });
        modalEl.addEventListener("hidden.bs.modal", function () { discard = false; current = null; });
    })();

    /* ============================== open the date a Dashboard alert is about === */

    // Shown inside the Dashboard's alert popup: tell it a save happened, so its list refreshes on close.
    if (document.documentElement.classList.contains("hrms-embed") && window.parent !== window) {
        ["employee:saved", "compliance:saved"].forEach(function (name) {
            document.addEventListener(name, function () { window.parent.postMessage("hrms:employee-saved", window.location.origin); });
        });
    }

    // ?focus=<field>: open the section holding the field, scroll to it and highlight it.
    (function initFocusField() {
        var marker = document.querySelector("[data-profile-focus]");
        var field = marker ? document.getElementById(marker.dataset.profileFocus) : null;
        if (!field) { return; }

        function reveal() {
            field.scrollIntoView({ block: "center" });
            var holder = field.closest("[class*='col-']") || field.parentElement;
            holder.classList.add("hrms-focus-field");
            field.focus({ preventScroll: true });
            window.setTimeout(function () { holder.classList.remove("hrms-focus-field"); }, 6000);
        }

        var collapse = field.closest(".collapse:not(.show)");
        if (collapse && window.bootstrap) {
            collapse.addEventListener("shown.bs.collapse", reveal, { once: true });
            bootstrap.Collapse.getOrCreateInstance(collapse, { toggle: false }).show();
        } else {
            window.setTimeout(reveal, 150);
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
                HRMS.go("/employees/profile/" + employeeId);
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
