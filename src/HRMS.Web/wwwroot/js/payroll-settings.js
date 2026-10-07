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
 *                                    (?companyId=value) when it changes
 *   [data-st-lines] + template[data-st-line-template]  editable rows, see below
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
    var current = null;

    function openForm(master, title, url) {
        if (!dialog) { return; }
        current = master;
        $("[data-st-form-title]", dialog).textContent = title;
        body.innerHTML = '<div class="pr-loading"><div class="hrms-spinner"></div></div>';
        modal(dialog).show();
        HRMS.getHtml(url).then(function (html) {
            body.innerHTML = html;
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
                var target = $(src.getAttribute("data-options-target"), root);
                if (!target) { return; }
                HRMS.getJson(withQs(src.getAttribute("data-options-url"), { companyId: src.value })).then(function (list) {
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
            }
        });
        wireLines(root);
    }

    /* Editable rows inside a form (e.g. indemnity service slabs):
         <div data-st-lines="Slabs">  <tbody data-st-line-body> rows </tbody>
           <template data-st-line-template> one row </template>
           <button data-st-line-add> </div>
       Each row: inputs named "Slabs[i].Field" are renumbered on add / remove;
       [data-st-line-remove] removes its row. */
    function wireLines(root) {
        $all("[data-st-lines]", root).forEach(function (box) {
            var prefix = box.getAttribute("data-st-lines");
            var tbody = $("[data-st-line-body]", box);
            var template = $("template[data-st-line-template]", box);
            function renumber() {
                $all("tr", tbody).forEach(function (tr, i) {
                    $all("[name]", tr).forEach(function (input) {
                        input.name = input.name.replace(new RegExp("^" + prefix + "\\[\\d+\\]"), prefix + "[" + i + "]");
                    });
                });
            }
            box.addEventListener("click", function (ev) {
                if (ev.target.closest("[data-st-line-add]")) {
                    tbody.appendChild(template.content.cloneNode(true));
                    renumber();
                    var last = tbody.lastElementChild && tbody.lastElementChild.querySelector("input, select");
                    if (last) { last.focus(); }
                } else if (ev.target.closest("[data-st-line-remove]")) {
                    ev.target.closest("tr").remove();
                    renumber();
                }
            });
            renumber();
        });
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
