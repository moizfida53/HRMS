/*!
 * Areas/POS/Scripts/pos.print.js  -  silent printing to LAN printers
 *
 *   PosPrint.order(invoiceNo, { reprint })    kitchen tickets (new items only unless reprint)
 *   PosPrint.invoice(invoiceNo)               the customer bill
 *   PosPrint.test(printer)                    a test slip (Printer Settings page)
 *   PosPrint.ping()                           is the Print Agent reachable?
 *
 * How it works
 *   The server (PrintController.Jobs) says which printers get what. This script draws
 *   each ticket on a canvas (so Arabic and any font print correctly), turns it into
 *   an ESC/POS raster image, and posts it to the Print Agent on the restaurant's PC
 *   (http://127.0.0.1:9101), which opens the TCP connection to the printer's IP.
 *   When the agent confirms, a "Printed" message shows and fades away.
 *
 * Needs jQuery. Settings: window.POS_PRINT_CFG = { urls: { jobs, markSent }, currency, decimals }.
 */
(function (window, $) {
    'use strict';

    var CFG = window.POS_PRINT_CFG || {};
    var AGENT_KEY = 'pos.print.agent';
    var DEFAULT_AGENT = 'http://127.0.0.1:9101';

    function agentUrl() {
        try { return (localStorage.getItem(AGENT_KEY) || DEFAULT_AGENT).replace(/\/+$/, ''); } catch (e) { return DEFAULT_AGENT; }
    }
    function setAgentUrl(u) { try { localStorage.setItem(AGENT_KEY, u || ''); } catch (e) { } }

    // ---------------------------------------------------------------- toast
    var tHost;
    function toast(msg, kind, ms) {
        if (!tHost) {
            $('<style>.pp-toasts{position:fixed;left:50%;bottom:22px;transform:translateX(-50%);z-index:2000;display:flex;flex-direction:column;gap:8px;align-items:center;pointer-events:none}' +
              '.pp-toast{pointer-events:auto;background:#0F1A15;color:#fff;font:600 14px/1.3 system-ui,"Segoe UI",Arial,sans-serif;padding:11px 18px;border-radius:12px;box-shadow:0 10px 30px rgba(0,0,0,.3);display:flex;gap:10px;align-items:center;max-width:92vw;animation:ppIn .18s ease-out}' +
              '.pp-toast i{width:9px;height:9px;border-radius:50%;background:#2FD07A;flex:0 0 auto}.pp-toast.err i{background:#FF6B73}.pp-toast.info i{background:#FFD86B}' +
              '.pp-toast.out{opacity:0;transform:translateY(8px);transition:all .3s}@keyframes ppIn{from{opacity:0;transform:translateY(10px)}}</style>').appendTo('head');
            tHost = $('<div class="pp-toasts" role="status" aria-live="polite"></div>').appendTo('body');
        }
        var $t = $('<div class="pp-toast ' + (kind || '') + '"><i></i><span></span></div>').appendTo(tHost);
        $t.find('span').text(msg);
        setTimeout(function () { $t.addClass('out'); setTimeout(function () { $t.remove(); }, 320); }, ms || (kind === 'err' ? 7000 : 2200));
        return $t;
    }

    // ------------------------------------------------------------- helpers
    var RTL = /[֐-ࣿיִ-﷿ﹰ-﻿]/;
    function num(v) { var n = parseFloat(v); return isNaN(n) ? 0 : n; }
    function money(v) {
        var dp = CFG.decimals != null ? CFG.decimals : 3;
        return (CFG.currency || 'KD') + ' ' + num(v).toFixed(dp);
    }
    function fmtDate(v) {
        var d = v ? new Date(typeof v === 'string' && /Date\(/.test(v) ? parseInt(v.replace(/\D/g, ''), 10) : v) : new Date();
        if (isNaN(d)) d = new Date();
        function p(n) { return (n < 10 ? '0' : '') + n; }
        return p(d.getDate()) + '/' + p(d.getMonth() + 1) + '/' + d.getFullYear() + ' ' + p(d.getHours()) + ':' + p(d.getMinutes());
    }

    // ------------------------------------------------------ ticket drawing
    var FONT = '"Segoe UI", Tahoma, "Noto Sans Arabic", Arial, sans-serif';

    function Canvas(widthDots) {
        var c = document.createElement('canvas');
        c.width = widthDots; c.height = 6000;
        var x = c.getContext('2d');
        x.fillStyle = '#fff'; x.fillRect(0, 0, c.width, c.height);
        x.fillStyle = '#000'; x.textBaseline = 'top';
        var W = widthDots, M = 6, y = 6;

        function font(px, bold) { x.font = (bold ? '700 ' : '500 ') + px + 'px ' + FONT; }
        function wrap(text, maxW) {
            var words = String(text).split(/\s+/), out = [], cur = '';
            for (var i = 0; i < words.length; i++) {
                var t = cur ? cur + ' ' + words[i] : words[i];
                if (x.measureText(t).width > maxW && cur) { out.push(cur); cur = words[i]; } else cur = t;
            }
            if (cur) out.push(cur);
            return out.length ? out : [''];
        }

        return {
            canvas: c,
            /** one block of text: align left|center|right, optional indent */
            text: function (t, o) {
                o = o || {}; var px = o.size || 24;
                if (t === null || t === undefined || t === '') return;
                font(px, o.bold);
                var ind = o.indent || 0, maxW = W - 2 * M - ind, lines = wrap(t, maxW), lh = Math.round(px * 1.22);
                for (var i = 0; i < lines.length; i++) {
                    var s = lines[i], rtl = RTL.test(s), w = x.measureText(s).width, al = o.align || (rtl ? 'right' : 'left');
                    x.direction = rtl ? 'rtl' : 'ltr';
                    var px0 = al === 'center' ? (W - w) / 2 : al === 'right' ? W - M - w : M + ind;
                    if (o.invert) { x.fillRect(0, y - 2, W, lh + 4); x.fillStyle = '#fff'; }
                    x.textAlign = 'left';
                    x.fillText(s, px0, y);
                    x.fillStyle = '#000';
                    y += lh;
                }
                y += o.gap == null ? 3 : o.gap;
            },
            /** left text + right text on one line (the left one wraps if it must) */
            pair: function (l, r, o) {
                o = o || {}; var px = o.size || 24;
                font(px, o.bold);
                var rw = x.measureText(r).width + 12, lines = wrap(l, W - 2 * M - rw - (o.indent || 0)), lh = Math.round(px * 1.22);
                for (var i = 0; i < lines.length; i++) {
                    x.direction = RTL.test(lines[i]) ? 'rtl' : 'ltr'; x.textAlign = 'left';
                    x.fillText(lines[i], M + (o.indent || 0), y);
                    if (i === 0) { x.direction = 'ltr'; x.fillText(r, W - M - x.measureText(r).width, y); }
                    y += lh;
                }
                y += 3;
            },
            rule: function (dash) {
                y += 3;
                if (dash) { x.setLineDash([6, 5]); } else x.setLineDash([]);
                x.lineWidth = 2; x.beginPath(); x.moveTo(M, y); x.lineTo(W - M, y); x.stroke(); x.setLineDash([]);
                y += 8;
            },
            gap: function (n) { y += n; },
            /** 1-bit raster of what was drawn: { w, h, data (rows of bytes) } */
            raster: function () {
                var h = Math.min(c.height, y + 10), bw = Math.ceil(W / 8), img = x.getImageData(0, 0, W, h).data, out = new Uint8Array(bw * h);
                for (var r = 0; r < h; r++) for (var col = 0; col < W; col++) {
                    var i = (r * W + col) * 4, g = img[i] * 0.3 + img[i + 1] * 0.59 + img[i + 2] * 0.11;
                    if (g < 165) out[r * bw + (col >> 3)] |= 0x80 >> (col & 7);
                }
                return { w: W, h: h, bw: bw, data: out };
            }
        };
    }

    function header(c, t, title) {
        var h = t.Header || {};
        if (h.BranchName) c.text(h.BranchName, { size: 28, bold: true, align: 'center' });
        c.text(title, { size: 30, bold: true, align: 'center', gap: 6 });
        if (t.Reprint) c.text('*** REPRINT ***', { size: 24, bold: true, align: 'center', invert: true });
    }

    function drawOrder(c, t) {
        var h = t.Header || {}, where = h.TableNo ? 'TABLE ' + h.TableNo : 'TAKE AWAY';
        header(c, t, 'KITCHEN ORDER');
        c.text(where, { size: 56, bold: true, align: 'center', gap: 4 });
        if (!h.TableNo && h.CustomerName && !/walk-?in/i.test(h.CustomerName)) c.text(h.CustomerName, { size: 24, bold: true, align: 'center' });
        c.pair('Bill #' + (h.RunningOrder || h.InvoiceNumShow || h.InvoiceNo), fmtDate(new Date()), { size: 22 });
        if (t.PrintedBy) c.text('By ' + t.PrintedBy, { size: 20 });
        c.rule(false);
        $.each(t.Lines || [], function (_, l) {
            var extra = !!l.ParentOrderID, note = $.trim(l.Note || ''), ta = /^\s*TAKE AWAY/i.test(note);
            if (extra) {
                c.text('+ ' + l.ItemName + (num(l.Quantity) > 1 ? ' x' + l.Quantity : ''), { size: 24, indent: 34 });
                return;
            }
            c.text(l.Quantity + ' x  ' + l.ItemName, { size: 32, bold: true, gap: 1 });
            if (l.ItemNameAra) c.text(l.ItemNameAra, { size: 28, bold: true, gap: 1 });
            if (ta) { c.text(' TAKE AWAY ', { size: 26, bold: true, invert: true, gap: 2 }); note = $.trim(note.replace(/^\s*TAKE AWAY\s*[:\-]?\s*/i, '')); }
            if (note) c.text(note, { size: 24, indent: 20 });
            c.gap(6);
        });
        c.rule(false);
        c.text(fmtDate(new Date()), { size: 20, align: 'center' });
    }

    function drawInvoice(c, t) {
        var h = t.Header || {}, dis = num(h.Discount);
        header(c, t, 'INVOICE');
        c.pair('Bill #', String(h.InvoiceNumShow || h.InvoiceNo), { size: 22, bold: true });
        c.pair('Date', fmtDate(h.InvoiceDate), { size: 22 });
        if (h.TableNo) c.pair('Table', String(h.TableNo), { size: 22 });
        else if (h.CustomerName) c.pair('Customer', String(h.CustomerName), { size: 22 });
        if (t.PrintedBy) c.pair('Cashier', t.PrintedBy, { size: 22 });
        c.rule(true);
        $.each(t.Lines || [], function (_, l) {
            if (l.ParentOrderID) { c.pair('+ ' + l.ItemName, num(l.LineTotal) ? num(l.LineTotal).toFixed(3) : '', { size: 21, indent: 26 }); return; }
            c.pair(l.Quantity + ' x ' + l.ItemName, num(l.LineTotal).toFixed(3), { size: 24, bold: true });
            if (l.ItemNameAra) c.text(l.ItemNameAra, { size: 22, indent: 26, gap: 1 });
            c.text(num(l.Quantity) + ' @ ' + num(l.Price).toFixed(3), { size: 19, indent: 26, gap: 4 });
        });
        c.rule(true);
        c.pair('Sub total', money(h.BillAmount), { size: 23 });
        if (dis > 0) c.pair('Discount', '-' + money(dis), { size: 23 });
        c.pair('TOTAL', money(h.NetPayable), { size: 30, bold: true });
        if ((t.Payments || []).length) {
            c.rule(true);
            var change = 0;
            $.each(t.Payments, function (_, p) { c.pair(p.PaymentType, money(p.Amount), { size: 22 }); change += num(p.ChangeGiven); });
            if (change > 0) c.pair('Change', money(change), { size: 24, bold: true });
        }
        c.gap(8);
        c.text('Thank you', { size: 24, bold: true, align: 'center' });
        c.text('شكراً لزيارتكم', { size: 24, bold: true, align: 'center' });
    }

    function drawTest(c, job) {
        c.text('TEST PRINT', { size: 36, bold: true, align: 'center' });
        c.text(job.Name, { size: 26, bold: true, align: 'center' });
        c.text(job.Host + ':' + job.Port, { size: 22, align: 'center' });
        c.text('طباعة تجريبية', { size: 28, bold: true, align: 'center' });
        c.text(fmtDate(new Date()), { size: 20, align: 'center' });
    }

    // ---------------------------------------------------------- ESC/POS
    function escpos(r) {
        var parts = [], BAND = 240;
        parts.push(new Uint8Array([0x1B, 0x40]));                       // initialise
        for (var y0 = 0; y0 < r.h; y0 += BAND) {
            var hh = Math.min(BAND, r.h - y0);
            parts.push(new Uint8Array([0x1D, 0x76, 0x30, 0x00, r.bw & 255, r.bw >> 8, hh & 255, hh >> 8]));
            parts.push(r.data.subarray(y0 * r.bw, (y0 + hh) * r.bw));
        }
        parts.push(new Uint8Array([0x1B, 0x64, 0x04]));                 // feed
        parts.push(new Uint8Array([0x1D, 0x56, 0x42, 0x00]));           // feed + partial cut
        var len = 0, i; for (i = 0; i < parts.length; i++) len += parts[i].length;
        var all = new Uint8Array(len), o = 0; for (i = 0; i < parts.length; i++) { all.set(parts[i], o); o += parts[i].length; }
        return all;
    }
    function b64(bytes) {
        var s = '', CH = 0x8000;
        for (var i = 0; i < bytes.length; i += CH) s += String.fromCharCode.apply(null, bytes.subarray(i, i + CH));
        return btoa(s);
    }

    function build(job) {
        var dots = job.Width === 58 ? 384 : 576, c = Canvas(dots);
        if (job.Kind === 'test') drawTest(c, job);
        else if (job.Kind === 'order') drawOrder(c, job.Ticket);
        else drawInvoice(c, job.Ticket);
        return b64(escpos(c.raster()));
    }

    // ----------------------------------------------------------- agent
    function agentCall(path, body, timeout) {
        var d = $.Deferred(), ctl = window.AbortController ? new AbortController() : null,
            timer = setTimeout(function () { if (ctl) ctl.abort(); }, timeout || 12000);
        fetch(agentUrl() + path, {
            method: body ? 'POST' : 'GET',
            headers: body ? { 'Content-Type': 'application/json' } : {},
            body: body ? JSON.stringify(body) : undefined,
            signal: ctl ? ctl.signal : undefined
        }).then(function (r) { return r.json().catch(function () { return {}; }); })
          .then(function (j) { clearTimeout(timer); if (j && j.ok) d.resolve(j); else d.reject((j && j.error) || 'The Print Agent refused the job.'); })
          .catch(function () { clearTimeout(timer); d.reject('AGENT'); });
        return d.promise();
    }

    function send(job) {
        var d = $.Deferred(), data;
        try { data = build(job); } catch (e) { return d.reject('Could not draw the ticket (' + e.message + ').').promise(); }
        agentCall('/print', { host: job.Host, port: job.Port, data: data }, 15000)
            .done(function () { d.resolve(); })
            .fail(function (e) {
                d.reject(e === 'AGENT'
                    ? 'Print Agent not reachable at ' + agentUrl() + '. Is it running on this PC?'
                    : job.Name + ': ' + e);
            });
        return d.promise();
    }

    function run(jobs, label, onAllOk) {
        var d = $.Deferred(), left = jobs.length, errs = [], ok = 0;
        if (!left) return d.resolve({ ok: 0, errors: [] }).promise();
        $.each(jobs, function (_, job) {
            send(job).done(function () { ok++; }).fail(function (m) { errs.push(m); })
                .always(function () {
                    if (--left) return;
                    if (!errs.length) { toast('Printed' + (label ? ' · ' + label : ''), 'ok'); if (onAllOk) onAllOk(); }
                    else {
                        var uniq = errs.filter(function (m, i) { return errs.indexOf(m) === i; });
                        toast((ok ? 'Some tickets did not print. ' : 'Not printed. ') + uniq.join(' '), 'err');
                    }
                    d.resolve({ ok: ok, errors: errs });
                });
        });
        return d.promise();
    }

    function post(url, data) { return $.ajax({ url: url, type: 'POST', data: data, dataType: 'json' }); }

    /**
     * kind: 'order' | 'invoice'. opts.reprint, opts.orderIds, opts.fallback()
     * (called when the branch has no printer for this kind, so the caller can
     * open the browser print window instead).
     */
    function print(kind, invoiceNo, opts) {
        opts = opts || {};
        var d = $.Deferred();
        $.ajax({ url: CFG.urls.jobs, type: 'GET', dataType: 'json', cache: false,
                 data: { invoiceNo: invoiceNo, kind: kind, reprint: !!opts.reprint, orderIds: (opts.orderIds || []).join(',') } })
        .done(function (r) {
            if (!r || r.Message !== 'Success') { toast((r && r.ErrorMessage) || 'The print job could not be prepared.', 'err'); return d.resolve(); }
            if (r.NoPrinters) {
                if (opts.fallback) { opts.fallback(); }
                else if (!opts.quiet) toast('No ' + (kind === 'order' ? 'order' : 'invoice') + ' printer is set up for this branch.', 'info', 3500);
                return d.resolve({ noPrinters: true });
            }
            if (!r.Jobs.length) { if (!opts.quiet) toast('Nothing new to print.', 'info'); return d.resolve(); }
            run(r.Jobs, kind === 'order' ? 'kitchen' : 'bill', function () {
                if (kind === 'order' && r.OrderIDs && r.OrderIDs.length)
                    post(CFG.urls.markSent, { invoiceNo: invoiceNo, orderIds: r.OrderIDs.join(',') });
            }).always(function (x) { d.resolve(x); });
        }).fail(function () { toast('The print job could not be prepared.', 'err'); d.resolve(); });
        return d.promise();
    }

    window.PosPrint = {
        order:   function (no, o) { return print('order', no, o); },
        invoice: function (no, o) { return print('invoice', no, o); },
        test:    function (p) { return run([{ Name: p.PrinterName, Host: p.IPAddress, Port: +p.Port || 9100, Width: +p.PaperWidthMM || 80, Kind: 'test' }], p.PrinterName); },
        ping:    function () { return agentCall('/ping', null, 4000); },
        agentUrl: agentUrl, setAgentUrl: setAgentUrl, toast: toast
    };
})(window, window.jQuery);
