/* ==========================================================================
 * HRMS Kuwait - Payroll Settings
 * One script for every settings screen. A screen is made of "masters":
 *
 *   <section data-st-master id="..."
 *            data-grid="list url" data-form="form url" data-save="save url"
 *            data-toggle="url" data-delete="url"
 *            data-title-new / data-title-edit / data-delete-title / data-delete-text>
 *       toolbar: [data-st-filter] inputs/selects (their name = query key)
 *       [data-st-count]  [data-st-slot] (the grid partial is loaded here)
 *
 *   rows:     tr[data-id][data-name] with [data-st-edit] [data-st-toggle] [data-st-delete]
 *             or [data-st-row-post="attr"] (posts {id} to the master's data-<attr> url;
 *             data-confirm="text" asks first)
 *   buttons:  [data-st-add="masterId"] opens the empty form
 *             [data-st-post="url"][data-st-target="masterId"] posts, then reloads
 *
 * The dialog (#st-modal, _Dialogs partial) loads the form partial and posts it
 * as FormData. Inside a form:
 *   data-show-if="Field=A|B"         shown only while Field has one of the values
 *   [data-st-choice]                 radio cards (keeps .is-selected in step)
 *   select[data-options-target][data-options-url]  reloads the target's options
 *                                    (?companyId=value) when it changes; the target
 *                                    may be a selector list, each target can name its
 *                                    own url (data-options-src)
 *   [data-st-lines] + template[data-st-line-template]  editable rows, see below
 *   [data-st-wide]                   the dialog opens extra wide
 *   pre[data-st-sample]              live sample of a bank salary file (bank formats)
 * Every text shown comes from the server (already translated) or HRMS.t().
 * ========================================================================== */
(function () {
    "use strict";

    var HRMS = window.HRMS || (window.HRMS = {});
    var page = document.querySelector("[data-st-page]");
    if (!page) { return; }

    function $(sel, root) { return (root || document).querySelector(sel); }
    function $all(sel, root) { return Array.prototype.slice.call((root || document).querySelectorAll(sel)); }
    function qs(params) {
        return Object.keys(params).filter(function (k) { return params[k] !== null && params[k] !== undefined && params[k] !== ""; })
            .map(function (k) { return encodeURIComponent(k) + "=" + encodeURIComponent(params[k]); }).join("&");
    }
    function withQs(url, params) { var q = qs(params); return q ? url + (url.indexOf("?") >= 0 ? "&" : "?") + q : url; }
    function modal(el) { return el && window.bootstrap ? window.bootstrap.Modal.getOrCreateInstance(el) : null; }
    function busy(button, on) { if (button) { button.disabled = !!on; button.classList.toggle("is-busy", !!on); } }
    function failed() { return HRMS.t("js.st_failed", "The request could not be completed."); }
    var debounce = HRMS.debounce || function (fn, wait) { var t; return function () { clearTimeout(t); t = setTimeout(fn, wait); }; };

    function post(url, data, button) {
        var body = data instanceof FormData ? data : (function () {
            var fd = new FormData();
            Object.keys(data || {}).forEach(function (k) { if (data[k] !== null && data[k] !== undefined) { fd.append(k, data[k]); } });
            return fd;
        })();
        busy(button, true);
        return HRMS.post(url, body).then(function (res) {
            busy(button, false);
            if (res && res.success && res.message) { HRMS.toast(res.message, "success"); }
            else if (res && !res.success && !res.errors) { HRMS.toast(res.message || failed(), "error"); }
            return res;
        }, function (error) {
            busy(button, false);
            HRMS.toast((error && error.message) || failed(), "error");
            return null;
        });
    }

    /* ------------------------------------------------------- confirm dialog */
    var confirmEl = $("#st-confirm");
    function confirmDialog(title, text, button) {
        return new Promise(function (resolve) {
            if (!confirmEl) { resolve(window.confirm(text)); return; }
            $("[data-st-confirm-title]", confirmEl).textContent = title;
            $("[data-st-confirm-text]", confirmEl).textContent = text;
            $("[data-st-confirm-button]", confirmEl).textContent = button || title;
            var accept = $("[data-st-confirm-accept]", confirmEl), done = false;
            function onAccept() { done = true; modal(confirmEl).hide(); resolve(true); }
            function onHide() {
                accept.removeEventListener("click", onAccept);
                confirmEl.removeEventListener("hidden.bs.modal", onHide);
                if (!done) { resolve(false); }
            }
            accept.addEventListener("click", onAccept);
            confirmEl.addEventListener("hidden.bs.modal", onHide);
            modal(confirmEl).show();
        });
    }

    /* ---------------------------------------------------------------- masters */
    var masters = {};

    function Master(el) {
        var self = this;
        this.el = el;
        this.slot = $("[data-st-slot]", el);
        this.count = $("[data-st-count]", el);
        this.page = 1;

        $all("[data-st-filter]", el).forEach(function (f) {
            var reset = function () { self.page = 1; self.load(); };
            f.addEventListener(f.tagName === "INPUT" ? "input" : "change", f.tagName === "INPUT" ? debounce(reset, 300) : reset);
        });

        el.addEventListener("click", function (ev) {
            var pageBtn = ev.target.closest("[data-page]");
            if (pageBtn && !pageBtn.disabled && self.slot.contains(pageBtn)) {
                self.page = parseInt(pageBtn.getAttribute("data-page"), 10) || 1;
                self.load();
                return;
            }
            var tr = ev.target.closest("tr[data-id]");
            if (!tr || !self.slot.contains(tr)) { return; }
            var id = tr.getAttribute("data-id"), name = tr.getAttribute("data-name") || "";
            var btn = ev.target.closest("button");

            if (ev.target.closest("[data-st-edit]")) {
                openForm(self, self.attr("title-edit") + (name ? " · " + name : ""), withQs(self.attr("form"), { id: id }));
            } else if (ev.target.closest("[data-st-toggle]")) {
                post(self.attr("toggle"), { id: id }, btn).then(function (res) { if (res && res.success) { self.load(); } });
            } else if (ev.target.closest("[data-st-delete]")) {
                confirmDialog(self.attr("delete-title") + (name ? " · " + name : ""), self.attr("delete-text"), self.attr("delete-title")).then(function (ok) {
                    if (ok) { post(self.attr("delete"), { id: id }, btn).then(function (res) { if (res && res.success) { self.load(); } }); }
                });
            } else if (ev.target.closest("[data-st-row-post]")) {
                var b = ev.target.closest("[data-st-row-post]");
                var go = function () {
                    post(self.attr(b.getAttribute("data-st-row-post")), { id: id }, b).then(function (res) { if (res && res.success) { reloadAll(); } });
                };
                var text = b.getAttribute("data-confirm");
                if (text) { confirmDialog(b.getAttribute("title") || "", text, b.getAttribute("title")).then(function (ok) { if (ok) { go(); } }); }
                else { go(); }
            }
        });
    }
    Master.prototype.attr = function (name) { return this.el.getAttribute("data-" + name) || ""; };
    Master.prototype.filters = function () {
        var out = { page: this.page };
        $all("[data-st-filter]", this.el).forEach(function (f) { out[f.name] = f.value.trim(); });
        return out;
    };
    Master.prototype.load = function () {
        var self = this;
        self.slot.setAttribute("aria-busy", "true");
        return HRMS.getHtml(withQs(self.attr("grid"), self.filters())).then(function (html) {
            self.slot.innerHTML = html;
            self.slot.removeAttribute("aria-busy");
            var holder = $("[data-count-text]", self.slot);
            HRMS.setCountText(self.count, holder ? holder.getAttribute("data-count-text") : "");
        }, function (error) {
            self.slot.removeAttribute("aria-busy");
            self.slot.innerHTML = "";
            HRMS.toast((error && error.message) || failed(), "error");
        });
    };

    function reloadAll() { Object.keys(masters).forEach(function (k) { masters[k].load(); }); }

    $all("[data-st-master]", page).forEach(function (el, i) {
        var m = new Master(el);
        masters[el.id || ("st-master-" + i)] = m;
        m.load();
    });

    document.addEventListener("click", function (ev) {
        var add = ev.target.closest("[data-st-add]");
        if (add) {
            var m = masters[add.getAttribute("data-st-add")];
            if (m) { openForm(m, m.attr("title-new"), withQs(m.attr("form"), add.dataset.params ? JSON.parse(add.dataset.params) : {})); }
            return;
        }
        var p = ev.target.closest("[data-st-post]");
        if (p) {
            post(p.getAttribute("data-st-post"), {}, p).then(function (res) {
                if (res && res.success) {
                    var target = masters[p.getAttribute("data-st-target")];
                    if (target) { target.load(); } else { reloadAll(); }
                }
            });
        }
    });

    /* ------------------------------------------------------------ the dialog */
    var dialog = $("#st-modal");
    var form = dialog && $("[data-st-form]", dialog);
    var body = dialog && $("[data-st-form-body]", dialog);
    var dialogBox = dialog && $(".modal-dialog", dialog);
    var current = null;

    function openForm(master, title, url) {
        if (!dialog) { return; }
        current = master;
        $("[data-st-form-title]", dialog).textContent = title;
        body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
        modal(dialog).show();
        dialogBox.classList.remove("modal-xl");
        HRMS.getHtml(url).then(function (html) {
            body.innerHTML = html;
            dialogBox.classList.toggle("modal-xl", !!body.querySelector("[data-st-wide]"));
            wireForm(body);
            var first = body.querySelector("input:not([type=hidden]):not([disabled]), select:not([disabled]), textarea");
            if (first) { window.setTimeout(function () { try { first.focus(); } catch (e) { /* hidden */ } }, 200); }
        }, function (error) {
            body.innerHTML = "";
            HRMS.toast((error && error.message) || failed(), "error");
        });
    }

    /** The value a data-show-if rule looks at: a checked radio, else the field itself. */
    function fieldValue(root, name) {
        var checked = root.querySelector('[data-st-field="' + name + '"]:checked');
        if (checked) { return checked.value; }
        var el = root.querySelector('[data-st-field="' + name + '"]') || root.querySelector('[name="' + name + '"]');
        if (!el) { return ""; }
        if (el.type === "checkbox") { return el.checked ? "true" : "false"; }
        return el.value;
    }

    function syncShowIf(root) {
        $all("[data-show-if]", root).forEach(function (el) {
            var rule = el.getAttribute("data-show-if").split("=");
            var allowed = (rule[1] || "").split("|");
            var show = allowed.indexOf(fieldValue(root, rule[0])) >= 0;
            el.hidden = !show;
            // a hidden part posts nothing that could fail validation
            $all("input, select, textarea", el).forEach(function (input) {
                if (show) { if (input.hasAttribute("data-st-off")) { input.disabled = false; input.removeAttribute("data-st-off"); } }
                else if (!input.disabled) { input.disabled = true; input.setAttribute("data-st-off", ""); }
            });
        });
        $all("[data-st-choice]", root).forEach(function (group) {
            $all("label", group).forEach(function (label) {
                var input = $("input", label);
                label.classList.toggle("is-selected", !!(input && input.checked));
            });
        });
    }

    function wireForm(root) {
        $all("select[data-searchable]", root).forEach(HRMS.searchable);
        syncShowIf(root);
        root.addEventListener("change", function (ev) {
            syncShowIf(root);
            var src = ev.target.closest("[data-options-target]");
            if (src) {
                $all(src.getAttribute("data-options-target"), root).forEach(function (target) {
                    var url = target.getAttribute("data-options-src") || src.getAttribute("data-options-url");
                    if (!url) { return; }
                    HRMS.getJson(withQs(url, { companyId: src.value })).then(function (list) {
                        var keep = target.options[0] && !target.options[0].value ? target.options[0] : null;
                        target.innerHTML = "";
                        if (keep) { target.appendChild(keep); }
                        (list || []).forEach(function (o) {
                            var opt = document.createElement("option");
                            opt.value = o.id; opt.textContent = o.text;
                            target.appendChild(opt);
                        });
                        target.dispatchEvent(new Event("hrms:refresh"));
                    });
                });
            }
        });
        wireLines(root);
        wireSample(root);
    }

    /* Editable rows inside a form (e.g. indemnity service slabs):
         <div data-st-lines="Slabs">  <tbody data-st-line-body> rows </tbody>
           <template data-st-line-template> one row </template>
           <button data-st-line-add> </div>
       Each row: inputs named "Slabs[i].Field" are renumbered on add / remove /
       move; [data-st-line-remove] removes its row, [data-st-line-up] /
       [data-st-line-down] move it (the order is what is saved), and
       [data-st-line-no] shows its position. */
    function wireLines(root) {
        $all("[data-st-lines]", root).forEach(function (box) {
            var prefix = box.getAttribute("data-st-lines");
            var tbody = $("[data-st-line-body]", box);
            var template = $("template[data-st-line-template]", box);
            function renumber() {
                var rows = $all("tr", tbody);
                rows.forEach(function (tr, i) {
                    $all("[name]", tr).forEach(function (input) {
                        input.name = input.name.replace(new RegExp("^" + prefix + "\\[\\d+\\]"), prefix + "[" + i + "]");
                    });
                    var no = $("[data-st-line-no]", tr);
                    if (no) { no.textContent = String(i + 1); }
                    var up = $("[data-st-line-up]", tr), down = $("[data-st-line-down]", tr);
                    if (up) { up.disabled = i === 0; }
                    if (down) { down.disabled = i === rows.length - 1; }
                });
                box.dispatchEvent(new Event("st:lines", { bubbles: true }));
            }
            box.addEventListener("click", function (ev) {
                var tr = ev.target.closest("tr");
                if (ev.target.closest("[data-st-line-add]")) {
                    tbody.appendChild(template.content.cloneNode(true));
                    renumber();
                    var last = tbody.lastElementChild && tbody.lastElementChild.querySelector("input, select");
                    if (last) { last.focus(); }
                } else if (ev.target.closest("[data-st-line-remove]")) {
                    tr.remove();
                    renumber();
                } else if (ev.target.closest("[data-st-line-up]") && tr.previousElementSibling) {
                    tbody.insertBefore(tr, tr.previousElementSibling);
                    renumber();
                    $("[data-st-line-up]", tr).focus();
                } else if (ev.target.closest("[data-st-line-down]") && tr.nextElementSibling) {
                    tbody.insertBefore(tr.nextElementSibling, tr);
                    renumber();
                    $("[data-st-line-down]", tr).focus();
                }
            });
            renumber();
        });
    }

    /* Bank formats: a live sample of the salary file from the fields as typed
       (two made-up employees) - shows the delimiter, header, widths and padding. */
    var SAMPLE = [
        { EMPLOYER_CODE: "10045", PAM_FILE_NO: "PAM-7781", EMPLOYEE_CODE: "E0012", CIVIL_ID: "289010112345", EMPLOYEE_NAME: "Ahmad Al-Sabah",
          BANK_WPS_CODE: "NBK", BANK_SWIFT: "NBOKKWKW", IBAN: "KW81NBOK0000000000001000372151", ACCOUNT_NO: "1000372151",
          NET_AMOUNT: "1250.500", BASIC_AMOUNT: "1000.000", ALLOWANCES: "350.000", DEDUCTIONS: "99.500",
          PERIOD_YYYYMM: "202610", PAY_DATE: "2026-10-28", DEBIT_IBAN: "KW81CBKU0000000000001234560101" },
        { EMPLOYER_CODE: "10045", PAM_FILE_NO: "PAM-7781", EMPLOYEE_CODE: "E0047", CIVIL_ID: "290120254321", EMPLOYEE_NAME: "Maria Santos",
          BANK_WPS_CODE: "KFH", BANK_SWIFT: "KFHOKWKW", IBAN: "KW31KFHO0000000000051010173254", ACCOUNT_NO: "51010173254",
          NET_AMOUNT: "420.000", BASIC_AMOUNT: "400.000", ALLOWANCES: "50.000", DEDUCTIONS: "30.000",
          PERIOD_YYYYMM: "202610", PAY_DATE: "2026-10-28", DEBIT_IBAN: "KW81CBKU0000000000001234560101" }
    ];

    function wireSample(root) {
        var out = $("pre[data-st-sample]", root);
        if (!out) { return; }
        function fit(text, f, fixed) {
            text = String(text == null ? "" : text);
            if (!f.width) { return text; }
            if (text.length > f.width) { return text.slice(0, f.width); }
            if (!fixed && !f.pad) { return text; }
            var pad = new Array(f.width - text.length + 1).join(f.pad || " ");
            return f.right ? pad + text : text + pad;
        }
        function render() {
            var typeEl = $("[data-st-sample-type]", root), delimEl = $("[data-st-sample-delim]", root);
            var fixed = typeEl && typeEl.value === "FIXED";
            var delim = fixed ? "" : ((delimEl && delimEl.value) || ",").replace("\\t", "\t");
            var fields = $all("[data-st-line-body] tr", root).map(function (tr) {
                var v = function (sel) { var el = $(sel, tr); return el ? el.value : ""; };
                var right = $("[data-st-sample-right]", tr);
                return {
                    name: v("[data-st-sample-name]"), source: v("[data-st-sample-source]"), constant: v("[data-st-sample-constant]"),
                    width: parseInt(v("[data-st-sample-width]"), 10) || 0, pad: v("[data-st-sample-pad]"), right: !!(right && right.checked)
                };
            });
            var lines = [];
            var header = root.querySelector('input[type=checkbox][name="HasHeader"]');
            if (header && header.checked) {
                lines.push(fields.map(function (f) { return fit(f.name, f, fixed); }).join(delim));
            }
            SAMPLE.forEach(function (emp) {
                lines.push(fields.map(function (f) { return fit(f.source === "CONSTANT" ? f.constant : emp[f.source], f, fixed); }).join(delim));
            });
            var trailer = root.querySelector('input[type=checkbox][name="HasTrailer"]');
            if (trailer && trailer.checked) { lines.push(out.getAttribute("data-trailer-text") || ""); }
            out.textContent = lines.join("\n");
        }
        root.addEventListener("input", render);
        root.addEventListener("change", render);
        root.addEventListener("st:lines", render);
        render();
    }

    if (form) {
        form.addEventListener("submit", function (ev) {
            ev.preventDefault();
            if (!current) { return; }
            $all("[data-valmsg-for]", body).forEach(function (s) { s.textContent = ""; });
            $all(".is-invalid", body).forEach(function (s) { s.classList.remove("is-invalid"); });
            post(current.attr("save"), new FormData(form), $("[data-st-form-save]", dialog)).then(function (res) {
                if (!res) { return; }
                if (res.errors) {
                    var first = null;
                    Object.keys(res.errors).forEach(function (k) {
                        var msg = $('[data-valmsg-for="' + k + '"]', body);
                        if (msg) { msg.textContent = res.errors[k][0]; }
                        var input = form.querySelector('[name="' + k + '"]');
                        if (input) { input.classList.add("is-invalid"); first = first || input; }
                        if (!msg) { HRMS.toast(res.errors[k][0], "error"); }
                    });
                    if (first) { first.focus(); }
                    return;
                }
                if (res.success) {
                    modal(dialog).hide();
                    reloadAll();
                }
            });
        });
    }
})();
