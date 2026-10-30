/* ============================================================================
   AdminLang.js
   ----------------------------------------------------------------------------
   English / Arabic language switcher for the ADMIN "Item Management" pages
   (Views/Category/Index.cshtml rendered inside Views/Shared/_LayoutNew.cshtml).

   WHAT IT DOES
   ------------
   1. Static chrome (labels, table headers, validation msgs) carry data-lbl /
      data-lbl-ph whose value is a labelName in tblLabelName (prefixed "adm_").
      On toggle we fetch the labels (reusing /ItemsView/GetLangLabels ->
      sp_GetLangLabels, which returns id, labelName, LabelTest), build a
      { labelName -> text } map and paint the DOM by key.
   2. Category names, item names and the Add/Edit popup TITLES + action BUTTONS
      are rendered/reset at runtime by Category.js. Those read the current
      language via getAdmLang() and the current-language text via
      getAdmLbl(key, fallbackEng), and Category.js re-renders the visible list
      through the onAdminLangChanged() hook we call after every switch.
   3. Because Category.js rebuilds popup content, we also re-apply static labels
      whenever a modal is shown (excluding .modal-title / .btn, which Category.js
      owns per Add vs Edit state).

   PUBLIC HELPERS
   --------------
   * toggleAdminLang()            -> flips EN <-> AR (wired to the header button)
   * applyAdminLang('EN'|'AR')    -> force a language
   * getAdmLang()                 -> 'EN' | 'AR' (current)
   * getAdmLbl(key, fallbackEng)  -> current-language text for a key
   * onAdminLangChanged(lang)     -> optional hook (defined in Category.js)
   ============================================================================ */
(function (window, $) {
    "use strict";

    var STORAGE_KEY = "admLang";
    var LABELS_URL = "/ItemsView/GetLangLabels";

    window.admLabels = window.admLabels || {}; // { labelName : text } current lang
    var cache = {};                            // cache["AR"], cache["EN"]

    function currentLang() {
        try { return localStorage.getItem(STORAGE_KEY) || "EN"; } catch (e) { return "EN"; }
    }
    function storeLang(lang) {
        try { localStorage.setItem(STORAGE_KEY, lang); } catch (e) { /* ignore */ }
    }

    /* Header button shows the language you will switch TO: default (EN) shows the
       Arabic glyph "ع"; when Arabic is active it shows "EN". */
    function updateIcon(lang) {
        // Slide the toggle: is-ar => knob right, AR highlighted, UAE flag shown.
        var $t = $("#btnAdminLang");
        $t.toggleClass("is-ar", lang === "AR");
        $t.attr("aria-checked", lang === "AR" ? "true" : "false");
        $t.attr("title", lang === "AR"
            ? "التبديل إلى الإنجليزية / Switch to English"
            : "التبديل إلى العربية / Switch to Arabic");
    }

    function setRtl(isRtl) {
        if (isRtl) {
            $("html").attr("lang", "ar").attr("dir", "rtl");
            $("body").addClass("rtl");
        } else {
            $("html").attr("lang", "en").attr("dir", "ltr");
            $("body").removeClass("rtl");
        }
    }

    /* Apply a { key -> text } map to all data-lbl / data-lbl-ph elements inside
       $scope (default: whole body). When excludeManaged is true, .modal-title and
       .btn are skipped because Category.js sets those per Add/Edit state. */
    function applyMap(map, $scope, excludeManaged) {
        if (!map) { return; }
        var $root = $scope || $(document.body);

        var $els = $root.find("[data-lbl]");
        if (excludeManaged) { $els = $els.not(".modal-title").not(".btn"); }
        $els.each(function () {
            var v = map[this.getAttribute("data-lbl")];
            if (v != null && v !== "") { $(this).text(v); }
        });

        $root.find("[data-lbl-ph]").each(function () {
            var v = map[this.getAttribute("data-lbl-ph")];
            if (v != null && v !== "") { $(this).attr("placeholder", v); }
        });
    }

    function paintAll(map) {
        window.admLabels = map;
        applyMap(map, null, false);
    }

    function fetchAndApply(lang, done) {
        if (cache[lang]) { paintAll(cache[lang]); if (done) { done(); } return; }
        $.ajax({
            type: "POST",
            url: LABELS_URL,
            data: JSON.stringify({ selectedLang: lang }),
            contentType: "application/json; charset=utf-8",
            dataType: "json",
            cache: false
        }).done(function (result) {
            var map = {};
            if (result && result.Message === "Success" && result.dtLabels) {
                var rows = JSON.parse(result.dtLabels);
                for (var i = 0; i < rows.length; i++) { map[rows[i].labelName] = rows[i].LabelTest; }
            }
            cache[lang] = map;
            paintAll(map);
            if (done) { done(); }
        }).fail(function () {
            if (done) { done(); }   // keep English on failure
        });
    }

    function notifyChanged(lang) {
        if (typeof window.onAdminLangChanged === "function") {
            try { window.onAdminLangChanged(lang); } catch (e) { /* ignore */ }
        }
    }

    window.getAdmLang = function () { return currentLang(); };

    window.applyAdminLang = function (lang) {
        lang = (lang === "AR") ? "AR" : "EN";
        storeLang(lang);
        setRtl(lang === "AR");
        updateIcon(lang);
        fetchAndApply(lang, function () { notifyChanged(lang); });
    };

    window.toggleAdminLang = function () {
        window.applyAdminLang(currentLang() === "AR" ? "EN" : "AR");
        return false;
    };

    /* Current-language text for a key, with English fallback (used by Category.js
       for runtime titles, buttons and pop-up messages). */
    window.getAdmLbl = function (key, fallbackEng) {
        var v = window.admLabels ? window.admLabels[key] : null;
        return (v != null && v !== "") ? v : (fallbackEng || "");
    };

    /* Re-apply static labels whenever a popup opens (Category.js rebuilds popup
       content). Titles/buttons are excluded – Category.js sets them by getAdmLbl. */
    $(document).on("shown.bs.modal", function (e) {
        if (currentLang() === "AR") { applyMap(window.admLabels, $(e.target), true); }
    });

    /* On load: restore Arabic if it was previously chosen. */
    $(function () {
        var lang = currentLang();
        updateIcon(lang);
        if (lang === "AR") {
            setRtl(true);
            fetchAndApply("AR", function () { notifyChanged("AR"); });
        }
    });

})(window, jQuery);
