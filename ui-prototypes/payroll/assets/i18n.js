/* ==========================================================================
 * Payroll prototypes - English / Arabic switch
 * --------------------------------------------------------------------------
 * Mirrors the live app: the toggle in the top bar stores the choice and
 * RELOADS the page; Arabic pages get <html lang="ar" dir="rtl"> and
 * Bootstrap's RTL stylesheet. In the live app every label comes from
 * Core.UiLabels; here the Arabic comes from assets/i18n-ar.js (the same
 * wording, so it can be seeded into Core.UiLabels with the Payroll build).
 * ========================================================================== */
(function () {
    "use strict";

    var KEY = "hrms-proto-lang";
    var lang = "en";
    try { lang = window.localStorage.getItem(KEY) || "en"; } catch (e) { /* private mode */ }

    var html = document.documentElement;
    if (lang === "ar") {
        html.setAttribute("lang", "ar");
        html.setAttribute("dir", "rtl");
        html.classList.add("hrms-tr-pending");
        var bs = document.getElementById("bs-css");
        if (bs) { bs.setAttribute("href", bs.getAttribute("href").replace("bootstrap.min.css", "bootstrap.rtl.min.css")); }
    }

    var dict = (window.HRMS_AR && window.HRMS_AR.exact) || {};
    var templates = ((window.HRMS_AR && window.HRMS_AR.templates) || []).map(function (t) {
        return [new RegExp("^" + t[0] + "$"), t[1]];
    });

    function translate(text) {
        var key = text.replace(/\s+/g, " ").trim();
        if (!key) { return null; }
        if (Object.prototype.hasOwnProperty.call(dict, key)) { return dict[key]; }
        for (var i = 0; i < templates.length; i++) {
            var m = templates[i][0].exec(key);
            if (m) {
                return templates[i][1].replace(/\{(\d+)\}/g, function (_, n) { return m[+n + 1]; });
            }
        }
        return null;
    }

    var ATTRS = ["placeholder", "title", "aria-label", "alt", "data-label"];
    var SKIP = { SCRIPT: 1, STYLE: 1, svg: 1, SVG: 1, CODE: 1, TEXTAREA: 1 };

    function translateNode(root) {
        if (!root) { return; }
        if (root.nodeType === 3) { translateText(root); return; }
        if (root.nodeType !== 1 || SKIP[root.nodeName] || root.closest("[data-no-tr]")) { return; }

        var walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT, {
            acceptNode: function (n) {
                var p = n.parentNode;
                if (!p || SKIP[p.nodeName] || (p.closest && p.closest("[data-no-tr], svg, code"))) { return NodeFilter.FILTER_REJECT; }
                return /[A-Za-z]/.test(n.nodeValue) ? NodeFilter.FILTER_ACCEPT : NodeFilter.FILTER_SKIP;
            }
        });
        var nodes = [];
        while (walker.nextNode()) { nodes.push(walker.currentNode); }
        nodes.forEach(translateText);

        var els = [root].concat(Array.prototype.slice.call(root.querySelectorAll("[placeholder],[title],[aria-label],[alt],[data-label]")));
        els.forEach(function (el) {
            if (el.closest && el.closest("[data-no-tr]")) { return; }
            ATTRS.forEach(function (a) {
                var v = el.getAttribute && el.getAttribute(a);
                if (v && /[A-Za-z]/.test(v)) {
                    var t = translate(v);
                    if (t !== null) { el.setAttribute(a, t); }
                }
            });
        });
    }

    function translateText(node) {
        var raw = node.nodeValue;
        var t = translate(raw);
        if (t !== null) {
            var lead = raw.match(/^\s*/)[0], trail = raw.match(/\s*$/)[0];
            node.nodeValue = lead + t + trail;
        }
    }

    document.addEventListener("DOMContentLoaded", function () {
        // Toggle label is always the OTHER language.
        document.querySelectorAll("[data-lang-toggle]").forEach(function (b) {
            var long = b.querySelector(".hrms-lang-toggle__text--long");
            var short = b.querySelector(".hrms-lang-toggle__text--short");
            if (long) { long.textContent = lang === "ar" ? "English" : "العربية"; }
            if (short) { short.textContent = lang === "ar" ? "EN" : "ع"; }
            b.setAttribute("lang", lang === "ar" ? "en" : "ar");
        });

        if (lang === "ar") {
            var t = translate(document.title);
            if (t !== null) { document.title = t; }
            translateNode(document.body);
            html.classList.remove("hrms-tr-pending");

            // Text added later by the prototype scripts (toasts, wizard steps...)
            new MutationObserver(function (records) {
                records.forEach(function (r) {
                    r.addedNodes.forEach(translateNode);
                    if (r.type === "characterData") { translateText(r.target); }
                });
            }).observe(document.body, { childList: true, subtree: true });
        }
    });

    document.addEventListener("click", function (event) {
        var b = event.target.closest("[data-lang-toggle]");
        if (!b) { return; }
        event.preventDefault();
        try { window.localStorage.setItem(KEY, lang === "ar" ? "en" : "ar"); } catch (e) { /* ignore */ }
        window.location.reload();
    });
})();
