/* Areas/POS/Scripts/pos.printers.js - Printer Settings page */
(function ($) {
    'use strict';
    var C = window.PRINTERS_CFG, S = { branch: 0, printers: [], cats: [], pc: {}, catById: {} };

    function esc(s) { return $('<div>').text(s == null ? '' : s).html(); }
    function modal(open) {
        $('#prScrim').toggleClass('open', open); $('#prModal').toggleClass('open', open).attr('aria-hidden', !open);
        if (open) setTimeout(function () { $('#prName').trigger('focus'); }, 60);
    }
    function err(m) { $('#prError').text(m || '').toggle(!!m); }

    function load(branch) {
        $.getJSON(C.urls.settings, { branchId: branch || '' }).done(function (r) {
            if (r.Message !== 'Success') { PosPrint.toast(r.ErrorMessage || 'Could not load printers.', 'err'); return; }
            S.branch = r.BranchID; S.printers = r.Printers; S.cats = r.Categories;
            S.catById = {}; $.each(S.cats, function (_, c) { S.catById[c.CAT_NUM] = c; });
            S.pc = {}; $.each(r.PrinterCats, function (_, x) { (S.pc[x.PrinterID] = S.pc[x.PrinterID] || []).push(x.CAT_NUM); });
            var $b = $('#prBranch').empty();
            $.each(r.Branches, function (_, b) { $b.append($('<option>').val(b.BranchID).text(b.BranchName)); });
            $b.val(S.branch);
            render();
        }).fail(function () { PosPrint.toast('Could not load printers.', 'err'); });
    }

    function render() {
        var $t = $('#prTable tbody').empty();
        $('#prEmpty').prop('hidden', S.printers.length > 0);
        $.each(S.printers, function (_, p) {
            var kinds = (p.PrintInvoice ? '<span class="pr-badge inv">Invoice</span>' : '') + (p.PrintOrder ? '<span class="pr-badge ord">Order</span>' : '') +
                        (p.IsActive ? '' : '<span class="pr-badge off">Off</span>');
            var cats = !p.PrintOrder ? '<span class="text-muted">-</span>' : p.AllCategories ? 'All categories' :
                $.map(S.pc[p.PrinterID] || [], function (id) { return esc((S.catById[id] || {}).CAT_NAME || ('#' + id)); }).join(', ');
            $t.append('<tr data-id="' + p.PrinterID + '"><td><div class="pr-name">' + esc(p.PrinterName) + '</div><div class="pr-ip">' + esc(p.IPAddress) + ':' + p.Port + '</div></td>' +
                '<td>' + kinds + '</td><td class="pr-cats">' + cats + '</td><td>' + p.PaperWidthMM + ' mm</td>' +
                '<td><button class="pr-btn js-test">Test</button><button class="pr-btn js-edit">Edit</button><button class="pr-btn del js-del">Delete</button></td></tr>');
        });
    }

    function drawCats(selected) {
        var q = $.trim($('#prCatSearch').val()).toLowerCase(), $l = $('#prCatList').empty(), sel = {};
        $.each(selected, function (_, id) { sel[id] = true; });
        // keep ticks made before a search filter was typed
        $('#prCatList').data('sel', $('#prCatList').data('sel') || sel);
        var cur = $('#prCatList').data('sel');
        $.each(S.cats, function (_, c) {
            var nm = c.CAT_NAME + (c.CAT_NAME_ARABIC ? ' · ' + c.CAT_NAME_ARABIC : '');
            if (q && nm.toLowerCase().indexOf(q) < 0) return;
            $l.append('<label><input type="checkbox" value="' + c.CAT_NUM + '"' + (cur[c.CAT_NUM] ? ' checked' : '') + ' /> ' + esc(nm) + '</label>');
        });
    }
    function syncCatBox() {
        $('#prCatBox').prop('hidden', !$('#prOrd').is(':checked'));
        $('#prCatList').toggleClass('off', $('#prAllCats').is(':checked'));
        $('#prInvWrap').toggleClass('on', $('#prInv').is(':checked'));
        $('#prOrdWrap').toggleClass('on', $('#prOrd').is(':checked'));
    }

    function openForm(p) {
        p = p || { PrinterID: 0, PrinterName: '', IPAddress: '', Port: 9100, PaperWidthMM: 80, PrintInvoice: false, PrintOrder: false, AllCategories: true, IsActive: true };
        err('');
        $('#prTitle').text(p.PrinterID ? 'Edit Printer' : 'Add Printer');
        $('#prId').val(p.PrinterID); $('#prName').val(p.PrinterName); $('#prIp').val(p.IPAddress); $('#prPort').val(p.Port);
        $('#prPaper').val(p.PaperWidthMM); $('#prInv').prop('checked', !!p.PrintInvoice); $('#prOrd').prop('checked', !!p.PrintOrder);
        $('#prAllCats').prop('checked', p.AllCategories !== false); $('#prActive').prop('checked', p.IsActive !== false);
        $('#prCatSearch').val('');
        var sel = {}; $.each(S.pc[p.PrinterID] || [], function (_, id) { sel[id] = true; });
        $('#prCatList').data('sel', sel); drawCats([]);
        syncCatBox(); modal(true);
    }

    function formData() {
        var sel = $('#prCatList').data('sel') || {}, ids = [];
        $.each(sel, function (id, on) { if (on) ids.push(id); });
        return {
            printerId: +$('#prId').val() || 0, branchId: S.branch, name: $.trim($('#prName').val()), ip: $.trim($('#prIp').val()),
            port: +$('#prPort').val() || 9100, paperWidth: +$('#prPaper').val(), printInvoice: $('#prInv').is(':checked'),
            printOrder: $('#prOrd').is(':checked'), allCategories: $('#prAllCats').is(':checked'), categoryIds: ids.join(','),
            active: $('#prActive').is(':checked')
        };
    }

    function save() {
        var d = formData();
        if (!d.name) return err('Enter the printer name.');
        if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(d.ip)) return err('Enter a valid IPv4 address, e.g. 192.168.1.50.');
        if (!d.printInvoice && !d.printOrder) return err('Tick Print Invoice, Print Order, or both.');
        if (d.printOrder && !d.allCategories && !d.categoryIds) return err('Select at least one category, or tick All categories.');
        err(''); $('#prSave').prop('disabled', true);
        $.post(C.urls.save, d, null, 'json').done(function (r) {
            if (r.Message === 'Success') { modal(false); PosPrint.toast('Printer saved', 'ok'); load(S.branch); }
            else err(r.ErrorMessage || 'The printer could not be saved.');
        }).fail(function () { err('The printer could not be saved.'); })
          .always(function () { $('#prSave').prop('disabled', false); });
    }

    function checkAgent() {
        var $a = $('#prAgent').removeClass('ok bad'), $t = $('#prAgentText').text('Checking the Print Agent…');
        $('#prAgentUrl').val(PosPrint.agentUrl());
        PosPrint.ping().done(function (j) { $a.addClass('ok'); $t.text('Print Agent connected' + (j.version ? ' (v' + j.version + ')' : '') + ' - ready to print from this browser.'); })
            .fail(function () { $a.addClass('bad'); $t.text('Print Agent not reachable from this browser. Start it on this PC, or correct the address.'); });
    }

    $(function () {
        $('#prBranch').on('change', function () { load(+this.value); });
        $('#prAdd').on('click', function () { openForm(); });
        $('#prClose, #prCancel, #prScrim').on('click', function () { modal(false); });
        $('#prInv, #prOrd, #prAllCats').on('change', syncCatBox);
        $('#prCatSearch').on('input', function () { drawCats([]); });
        $('#prCatList').on('change', 'input', function () {
            var sel = $('#prCatList').data('sel') || {}; sel[this.value] = this.checked; $('#prCatList').data('sel', sel);
        });
        $('#prSave').on('click', save);
        $('#prTest').on('click', function () {
            var d = formData();
            if (!/^\d{1,3}(\.\d{1,3}){3}$/.test(d.ip)) return err('Enter a valid IPv4 address first.');
            err(''); PosPrint.test({ PrinterName: d.name || 'Printer', IPAddress: d.ip, Port: d.port, PaperWidthMM: d.paperWidth });
        });
        $('#prTable').on('click', '.js-test', function () { PosPrint.test(find(this)); })
                     .on('click', '.js-edit', function () { openForm(find(this)); })
                     .on('click', '.js-del', function () {
                         var p = find(this);
                         if (!window.confirm('Remove printer "' + p.PrinterName + '"?')) return;
                         $.post(C.urls.del, { printerId: p.PrinterID, branchId: S.branch }, null, 'json').done(function (r) {
                             if (r.Message === 'Success') { PosPrint.toast('Printer removed', 'ok'); load(S.branch); }
                             else PosPrint.toast('The printer could not be removed.', 'err');
                         });
                     });
        $('#prAgentCheck').on('click', function () { PosPrint.setAgentUrl($.trim($('#prAgentUrl').val())); checkAgent(); });
        $(document).on('keydown', function (e) { if (e.key === 'Escape') modal(false); });
        function find(el) { var id = +$(el).closest('tr').data('id'); return $.grep(S.printers, function (p) { return p.PrinterID === id; })[0]; }
        checkAgent(); load();
    });
})(window.jQuery);
