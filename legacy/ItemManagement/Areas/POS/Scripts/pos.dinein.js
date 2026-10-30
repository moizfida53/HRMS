/*==============================================================================
  Areas/POS/Scripts/pos.dinein.js
--------------------------------------------------------------------------------
  Dine-In floor plan.

    Floor        tabs per area (tblTable.TableType), hexagon tiles placed at
                 tblTable.Xaxis / Yaxis, green = vacant, red = occupied.
    Vacant tap   locks the table at once (red on every screen), then the
                 guest popup: name, mobile, persons.
    Guest OK     order popup: categories right, items middle, order left.
    Busy tap     table popup: bill lines (delete each), Add item, Print, Pay,
                 Transfer, Split bill, Delete bill.
    Admin        Arrange tables: drag tiles, Save layout writes X / Y.
    Take Away    second tab: the Take Away orders of the day (and any still
                 unpaid), each opens the same popup as a table - Add item,
                 Print, Pay, per-line delete, Delete bill.
    Split bill   tap item rows on a table's bill, press Split bill: the Take
                 Payment popup opens for the chosen items, and on payment they go
                 on a new bill (the originals stay, flagged as split).
    Take Payment Cash first, other tenders two to a row, an on-screen keypad
                 that opens with the amount box (touch screens).
    Take away    on a Dine-In order every item can be marked "Take away"; the
    mark         kitchen ticket then prints it so the item is packed.

  Live updates: SignalR hub "dineInHub" (Areas/POS/Hubs/DineInHub.cs). When it
  is not available the floor refreshes on a timer instead.

  Plain ES5 + jQuery on purpose: counter tablets in the field run old browsers.
==============================================================================*/
(function ($, window, document) {
    'use strict';

    var C   = window.DINEIN_CFG || { urls: {} };
    var CUR = C.currency || 'KD';

    var TILE_W = 120, TILE_H = 134, STEP_X = 150, STEP_Y = 175, PAD = 30, SNAP = 10;

    // chair slots around a pointy-top hexagon (tile coordinates, 120 x 134)
    var SEATS = {
        UR: { x: 92.5, y: 10,  r: 30 },  R: { x: 125, y: 67, r: 90 },  LR: { x: 92.5, y: 125, r: -30 },
        LL: { x: 27.5, y: 125, r: 30 },  L: { x: -5,  y: 67, r: 90 },  UL: { x: 27.5, y: 10,  r: -30 }
    };
    var SEAT_LAYOUT = {
        1: ['R'], 2: ['R', 'L'], 3: ['UR', 'LR', 'L'], 4: ['UR', 'LR', 'LL', 'UL'],
        5: ['UR', 'R', 'LR', 'LL', 'UL'], 6: ['UR', 'R', 'LR', 'LL', 'L', 'UL']
    };

    var S = {
        areas: [], tables: [], byId: {}, floor: null,
        pos: {}, scale: 1, canvasW: 0, canvasH: 0,
        arrange: false, drag: null,
        menu: null, menuReq: null, lookups: null, lookupsReq: null, branchId: null,
        guest: null, order: null, tp: null,
        refreshT: null, live: 'wait',
        mode: 'dine',                                   // 'dine' | 'ta'
        ta: { bills: [], lines: [], filter: 'all', loaded: false },
        taT: null
    };

    // =========================================================================
    // utilities
    // =========================================================================
    function esc(s) {
        return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function n(v) { var x = parseFloat(v); return isNaN(x) ? 0 : x; }
    function money(v) { return n(v).toFixed(3); }
    function kd(v) { return CUR + ' ' + money(v); }
    function store(k, v) { try { if (v === undefined) return window.localStorage.getItem(k); window.localStorage.setItem(k, v); } catch (e) { } return null; }

    function newGuid() {
        if (window.crypto && window.crypto.getRandomValues) {
            var b = new Uint8Array(16); window.crypto.getRandomValues(b);
            b[6] = (b[6] & 15) | 64; b[8] = (b[8] & 63) | 128;
            var h = []; for (var i = 0; i < 16; i++) h.push((b[i] + 256).toString(16).slice(1));
            return h.slice(0, 4).join('') + '-' + h.slice(4, 6).join('') + '-' + h.slice(6, 8).join('') + '-' + h.slice(8, 10).join('') + '-' + h.slice(10).join('');
        }
        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
            var r = Math.random() * 16 | 0; return (c === 'x' ? r : (r & 3 | 8)).toString(16);
        });
    }

    /** $.ajax that resolves only on Message === 'Success' and rejects with a readable sentence. */
    function api(type, url, data) {
        return $.ajax({ type: type, url: url, data: data, dataType: 'json', cache: false }).then(
            function (r) {
                if (r && r.Message === 'Success') return r;
                return $.Deferred().reject((r && r.ErrorMessage) || 'Something went wrong. Try again.', r).promise();
            },
            function (xhr) {
                if (xhr.status === 401) {
                    window.location.href = '/POS/Auth/Login?returnUrl=' + encodeURIComponent(window.location.pathname);
                }
                return $.Deferred().reject(xhr.status === 403
                    ? 'You do not have permission to do that.'
                    : 'The server could not be reached. Check the connection and try again.').promise();
            });
    }

    function toast(msg, isErr) {
        var $t = $('<div class="di-toast' + (isErr ? ' is-err' : '') + '"><span class="dot"></span><span></span></div>');
        $t.find('span:last').text(msg);
        $('#diToasts').append($t);
        setTimeout(function () { $t.fadeOut(200, function () { $t.remove(); }); }, isErr ? 5200 : 3200);
    }

    function busy($b, on) { $b.toggleClass('is-busy-btn', !!on).prop('disabled', !!on); }

    // =========================================================================
    // hexagon drawing
    // =========================================================================
    function numSize(no) {
        var l = String(no).length;
        return l <= 2 ? 28 : l === 3 ? 24 : l === 4 ? 20 : 17;
    }

    function tileSvg(no, sub) {
        var pw = Math.min(96, Math.round(String(sub).length * 6.6 + 20));
        return '<svg width="120" height="134" viewBox="0 0 120 134" aria-hidden="true" focusable="false">' +
            '<polygon class="ring" stroke-linejoin="round" points="60,1 117,34 117,100 60,133 3,100 3,34"/>' +
            '<polygon class="rim" points="60,8 111,37 111,98 60,127 9,98 9,37"/>' +
            '<polygon class="top" points="60,11 106,37 106,88 60,114 14,88 14,37"/>' +
            '<polygon class="sheen" points="60,14 103,38 103,58 17,58 17,38"/>' +
            '<text class="no" x="60" y="50" text-anchor="middle" dominant-baseline="central" style="font-size:' + numSize(no) + 'px">' + esc(no) + '</text>' +
            '<rect class="pill" x="' + (60 - pw / 2) + '" y="71" width="' + pw + '" height="22" rx="11"/>' +
            '<text class="sub" x="60" y="82.5" text-anchor="middle" dominant-baseline="central">' + esc(sub) + '</text>' +
            '</svg>';
    }

    /** Small solid hexagon for popup headers. */
    function badgeHex(no, isBusy, w) {
        w = w || 52;
        var rim = isBusy ? '#9E1F28' : '#0E6B3E', top = isBusy ? '#D33A43' : '#1A9A5C';
        return '<svg class="di-hex-badge" width="' + w + '" height="' + Math.round(w * 134 / 120) + '" viewBox="0 0 120 134" aria-hidden="true" focusable="false">' +
            '<polygon points="60,8 111,37 111,98 60,127 9,98 9,37" fill="' + rim + '" stroke="' + rim + '" stroke-width="8" stroke-linejoin="round"/>' +
            '<polygon points="60,11 106,37 106,88 60,114 14,88 14,37" fill="' + top + '" stroke="' + top + '" stroke-width="7" stroke-linejoin="round"/>' +
            '<text x="60" y="62" text-anchor="middle" dominant-baseline="central" fill="#fff" style="font-size:' + (numSize(no) + 8) + 'px;font-weight:800">' + esc(no) + '</text>' +
            '</svg>';
    }

    function chairsHtml(cap, seated, isBusy) {
        var slots = SEAT_LAYOUT[Math.max(1, Math.min(6, cap || 4))], out = '';
        for (var i = 0; i < slots.length; i++) {
            var s = SEATS[slots[i]];
            out += '<span class="chair' + (isBusy && i < seated ? ' is-sat' : '') + '" style="left:' + (s.x - 14) +
                   'px;top:' + (s.y - 4.5) + 'px;transform:rotate(' + s.r + 'deg)"></span>';
        }
        return out;
    }

    function tableSub(t) {
        if (t.Status !== 1) return t.Capacity + ' seats';
        if (t.IsLegacyLock) return 'Occupied';
        if (n(t.BillAmount) > 0) return kd(n(t.BillAmount) - n(t.AmountPaid) > 0.0005 ? n(t.BillAmount) - n(t.AmountPaid) : t.BillAmount);
        return 'Seated · ' + (t.Persons || 0);
    }

    function tileHtml(t) {
        var p = S.pos[t.TableID] || { x: 0, y: 0 }, isBusy = t.Status === 1;
        var cls = 'di-tbl ' + (isBusy ? 'is-busy' : 'is-free') + (t._pending ? ' is-pending' : '') +
                  (S.tp && S.tp.tableId === t.TableID ? ' is-sel' : '');
        var label = 'Table ' + t.Table_No + ', ' + (isBusy ? 'occupied' + (n(t.BillAmount) > 0 ? ', ' + kd(t.BillAmount) : '') : 'vacant, ' + t.Capacity + ' seats');
        return '<button type="button" class="' + cls + '" data-id="' + t.TableID + '" style="left:' + p.x + 'px;top:' + p.y + 'px" aria-label="' + esc(label) + '">' +
            chairsHtml(t.Capacity, t.Persons, isBusy) + tileSvg(t.Table_No, tableSub(t)) +
            '<span class="coords">X ' + Math.round(p.x) + ' · Y ' + Math.round(p.y) + '</span></button>';
    }

    // =========================================================================
    // floor
    // =========================================================================
    function loadFloor() {
        if (S.arrange) return $.Deferred().resolve().promise();   // never clobber a drag in progress
        return api('GET', C.urls.floor).done(function (r) {
            S.areas = r.Areas || [];
            S.tables = r.Tables || [];
            S.byId = {};
            $.each(S.tables, function (_, t) {
                t.Status = n(t.Status); t.Capacity = n(t.Capacity) || 4; t.Persons = n(t.Persons);
                S.byId[t.TableID] = t;
            });
            if (!S.floor || !areaExists(S.floor)) {
                var saved = n(store('di.floor'));
                S.floor = areaExists(saved) ? saved : (S.areas.length ? n(S.areas[0].TableType) : 0);
            }
            renderFloor();
        }).fail(function (msg) { toast(msg, true); });
    }

    function scheduleRefresh() {
        clearTimeout(S.refreshT);
        S.refreshT = setTimeout(loadFloor, 180);
    }

    function areaExists(tt) {
        for (var i = 0; i < S.areas.length; i++) if (n(S.areas[i].TableType) === n(tt)) return true;
        return false;
    }

    function floorTables() {
        return $.grep(S.tables, function (t) { return n(t.TableType) === n(S.floor); });
    }

    /**
     * Where each tile sits. A table with a saved position (Xaxis or Yaxis > 0)
     * stays there. A table at X = 0 and Y = 0 has never been placed, so it is
     * laid out automatically in rows that fit the width of the floor box,
     * filling free cells and never landing on top of a placed table. When the
     * whole floor is unplaced, the grid is centred in the box.
     */
    function computePositions(list) {
        var avail = Math.max(TILE_W + PAD * 2, ($('#diScroll').width() || 1100));
        var cols  = Math.max(1, Math.floor((avail - PAD * 2 + (STEP_X - TILE_W)) / STEP_X));
        var placed = [], auto = [];

        S.pos = {};
        $.each(list, function (_, t) {
            if (n(t.Xaxis) > 0 || n(t.Yaxis) > 0) {
                S.pos[t.TableID] = { x: n(t.Xaxis), y: n(t.Yaxis) };
                placed.push(S.pos[t.TableID]);
            } else {
                auto.push(t);
            }
        });
        if (!auto.length) return;

        // centre the grid when nothing on this floor has been arranged yet
        var used = Math.min(cols, auto.length) * STEP_X - (STEP_X - TILE_W);
        var left = placed.length ? PAD : Math.max(PAD, Math.floor((avail - used) / 2));

        var cell = 0;
        $.each(auto, function (_, t) {
            var x, y;
            do {
                x = left + (cell % cols) * STEP_X;
                y = PAD + Math.floor(cell / cols) * STEP_Y;
                cell++;
            } while (overlaps(placed, x, y));
            S.pos[t.TableID] = { x: x, y: y };
            placed.push(S.pos[t.TableID]);
        });
    }

    function overlaps(placed, x, y) {
        for (var i = 0; i < placed.length; i++) {
            if (Math.abs(placed[i].x - x) < TILE_W + 20 && Math.abs(placed[i].y - y) < TILE_H + 30) return true;
        }
        return false;
    }

    function renderFloor() {
        renderTabs();
        var list = floorTables();
        renderStats();

        $('#diEmpty').prop('hidden', S.tables.length > 0);
        $('.di-floor__scroll').prop('hidden', S.tables.length === 0);

        if (!S.arrange) computePositions(list);
        var html = '';
        $.each(list, function (_, t) { html += tileHtml(t); });
        $('#diCanvas').html(html);
        sizeCanvas();
    }

    function sizeCanvas() {
        var w = 0, h = 0;
        $.each(S.pos, function (id, p) {
            if (!S.byId[id] || n(S.byId[id].TableType) !== n(S.floor)) return;
            w = Math.max(w, p.x + TILE_W); h = Math.max(h, p.y + TILE_H);
        });
        // never narrower than the box itself, so the dotted floor fills it
        S.canvasW = Math.max(w + PAD, S.arrange ? 640 : Math.floor($('#diScroll').width() || 640));
        S.canvasH = Math.max(h + PAD + 30, 420);

        var avail = $('#diScroll').width() || S.canvasW;
        S.scale = S.arrange ? 1 : Math.max(0.55, Math.min(1, avail / S.canvasW));

        $('#diCanvas').css({ width: S.canvasW, height: S.canvasH, transform: 'scale(' + S.scale + ')' });
        $('#diSizer').css({ width: S.canvasW * S.scale, height: S.canvasH * S.scale });
    }

    function renderTabs() {
        var html = '';
        $.each(S.areas, function (_, a) {
            var tt = n(a.TableType);
            html += '<button type="button" data-tt="' + tt + '" class="' + (tt === n(S.floor) ? 'is-on' : '') + '" aria-pressed="' + (tt === n(S.floor)) + '">' +
                    esc(a.AreaName) + '</button>';
        });
        $('#diFloors').html(html).prop('hidden', S.areas.length < 1);
    }

    /** Occupied tables and seated guests, across every floor. */
    function renderStats() {
        var occ = 0, guests = 0;
        $.each(S.tables, function (_, t) {
            if (t.Status === 1) { occ++; guests += t.Persons; }
        });
        $('#diStOcc').text(occ);
        $('#diStGuests').text(guests);
    }

    function patchTile(t) {
        var $old = $('#diCanvas .di-tbl[data-id="' + t.TableID + '"]');
        if ($old.length) $old.replaceWith(tileHtml(t));
    }

    // =========================================================================
    // overlays
    // =========================================================================
    function show(id) { $('#' + id).prop('hidden', false); $('body').addClass('di-lock'); }
    function hide(id) {
        $('#' + id).prop('hidden', true);
        if (!$('.di-ov:not([hidden])').length) $('body').removeClass('di-lock');
    }
    function isOpen(id) { return !$('#' + id).prop('hidden'); }

    // =========================================================================
    // vacant table -> lock -> guest popup
    // =========================================================================
    function seatTable(t) {
        t._pending = true; t.Status = 1; patchTile(t);

        api('POST', C.urls.lock, { tableId: t.TableID, branchId: S.branchId }).done(function () {
            t._pending = false; patchTile(t);
            openGuest(t);
        }).fail(function (msg) {
            t._pending = false;
            toast(msg, true);
            loadFloor();
        });
    }

    function openGuest(t) {
        var $g = $('#diGuest');
        S.guest = { table: t };
        $g.find('.js-hex').html(badgeHex(t.Table_No, true, 56));
        $('#diGuestTitle').text('Seat guests at Table ' + t.Table_No);
        $g.find('.js-sub').text(areaName(t.TableType) + ' · ' + t.Capacity + ' seats');
        $('#diGName').val('');
        $('#diGMobile').val('');
        $('#diGPersons').val(Math.min(2, t.Capacity) || 2);
        $g.find('.js-err').text('');
        guestCap();
        show('diGuest');
        setTimeout(function () { $('#diGName').trigger('focus'); }, 50);
    }

    function guestPersons() { return Math.max(0, Math.min(999, parseInt($('#diGPersons').val(), 10) || 0)); }

    function guestCap() {
        if (!S.guest) return;
        var cap = S.guest.table.Capacity, p = guestPersons();
        $('#diGuest .js-cap').toggleClass('is-over', p > cap).text(p > cap ? 'More than ' + cap + ' seats' : 'of ' + cap + ' seats');
    }

    function guestCancel() {
        if (!S.guest) return hide('diGuest');
        var t = S.guest.table, $b = $('#diGuest .js-cancel');
        busy($b, true);
        api('POST', C.urls.release, { tableId: t.TableID, reason: 'Cancelled' }).always(function () {
            busy($b, false);
            S.guest = null;
            hide('diGuest');
            loadFloor();
        }).done(function () { toast('Table ' + t.Table_No + ' released on all devices'); })
          .fail(function (msg) { toast(msg, true); });
    }

    function guestOk() {
        var t = S.guest.table, p = guestPersons(), $b = $('#diGuest .js-ok'), $err = $('#diGuest .js-err');
        var mobile = $.trim($('#diGMobile').val()).replace(/\D/g, '');
        if (p < 1) { $err.text('Enter the number of persons.'); $('#diGPersons').trigger('focus'); return; }
        if (mobile && mobile.length < 7) { $err.text('That mobile number looks too short.'); $('#diGMobile').trigger('focus'); return; }
        $err.text('');
        busy($b, true);
        api('POST', C.urls.setGuest, { tableId: t.TableID, name: $.trim($('#diGName').val()), mobile: mobile, persons: p })
            .done(function () {
                t.Persons = p; t.CustomerName = $.trim($('#diGName').val()); t.Mobile = mobile;
                S.guest = null;
                hide('diGuest');
                openOrder({ mode: 'new', table: t });
                scheduleRefresh();
            })
            .fail(function (msg) { $err.text(msg); })
            .always(function () { busy($b, false); });
    }

    function areaName(tt) {
        for (var i = 0; i < S.areas.length; i++) if (n(S.areas[i].TableType) === n(tt)) return S.areas[i].AreaName;
        return '';
    }

    // =========================================================================
    // menu + order popup
    // =========================================================================
    function ensureMenu() {
        if (S.menu) return $.Deferred().resolve(S.menu).promise();
        if (S.menuReq) return S.menuReq;
        S.menuReq = api('GET', C.urls.menu).then(function (r) {
            var m = { cats: r.Categories || [], items: r.Items || [], byId: {}, byCat: {} };
            $.each(m.items, function (_, it) {
                it.ItemID = n(it.ItemID); it.CAT_NUM = n(it.CAT_NUM); it.PRICE = n(it.PRICE);
                m.byId[it.ItemID] = it;
                (m.byCat[it.CAT_NUM] = m.byCat[it.CAT_NUM] || []).push(it);
            });
            S.menu = m;
            return m;
        });
        S.menuReq.fail(function () { S.menuReq = null; });
        return S.menuReq;
    }

    /**
     * opts.mode: 'new'      first bill for a table (opts.table)
     *            'add'      more items on an existing bill (opts.table, opts.invoiceNo)
     *            'takeaway' no table
     */
    function openOrder(opts) {
        var t = opts.table, $o = $('#diOrder');
        S.order = { mode: opts.mode, table: t || null, invoiceNo: opts.invoiceNo || null, billLabel: opts.billLabel || '',
                    cart: [], cat: null, q: '', guid: newGuid(), discard: false };

        if (t) {
            $o.find('.js-hex').html(badgeHex(t.Table_No, true, 44));
            $('#diOrderTitle').text('Table ' + t.Table_No + (opts.mode === 'add' ? ' · Add to ' + (opts.billLabel || 'bill') : ' · New order'));
            $o.find('.js-sub').text([areaName(t.TableType), t.CustomerName || 'Walk-in guest', (t.Persons || 0) + ' persons', t.Mobile ? '+965 ' + t.Mobile : '']
                .filter(Boolean).join(' · '));
        } else {
            $o.find('.js-hex').html(badgeHex('TA', true, 44));
            $('#diOrderTitle').text(opts.mode === 'add' ? 'Take Away · Add to ' + (opts.billLabel || 'order') : 'Take Away · New order');
            $o.find('.js-sub').text(opts.mode === 'add' ? 'More items on this Take Away order' : 'Not linked to a table');
        }
        // customer name / mobile: only when starting a new Take Away order
        $o.find('.js-ta-cust').prop('hidden', !(!t && opts.mode === 'takeaway'));
        $o.find('.js-ta-name, .js-ta-mobile').val('');
        $o.find('.js-send-tx').text(opts.mode === 'add' ? 'Add to bill' : 'Process order');
        $o.find('.js-search').val('');
        $o.find('.js-err').text('');
        $o.find('.js-grid').html('<div class="di-cart-empty">Loading menu…</div>');
        $o.find('.js-cats').empty();
        renderCart();
        show('diOrder');

        ensureMenu().done(function (m) {
            S.order.cat = m.cats.length ? n(m.cats[0].CAT_NUM) : null;
            renderOrder();
        }).fail(function (msg) {
            $o.find('.js-grid').html('<div class="di-cart-empty"><b>The menu could not be loaded</b>' + esc(msg) + '</div>');
        });
    }

    // A cart line is an item + whether it is packed to take away. The same item
    // can be on two lines (2 here, 1 to go), so lines are told apart by a key.
    function lineKey(l) { return l.id + (l.ta ? 't' : 'd'); }

    function cartLine(key) {
        var c = S.order.cart;
        for (var i = 0; i < c.length; i++) if (lineKey(c[i]) === String(key)) return i;
        return -1;
    }

    /** Total picked of one item, whatever the line. */
    function cartQty(id) {
        var q = 0;
        $.each(S.order.cart, function (_, l) { if (l.id === id) q += l.qty; });
        return q;
    }

    function cartChanged() {
        S.order.discard = false;
        $('#diOrder .js-err').text('');
        renderOrder();
    }

    /** Tapping an item adds to its dine-in line (a new line if there is none). */
    function addItem(id) {
        var c = S.order.cart, i;
        for (i = 0; i < c.length; i++) if (c[i].id === id && !c[i].ta) break;
        if (i < c.length) c[i].qty = Math.min(999, c[i].qty + 1);
        else c.push({ id: id, qty: 1, ta: false });
        cartChanged();
    }

    function setLineQty(key, q) {
        var i = cartLine(key);
        if (i < 0) return;
        if (q <= 0) S.order.cart.splice(i, 1);
        else S.order.cart[i].qty = Math.min(999, q);
        cartChanged();
    }

    /** Lines of the same item and the same mode are one line. */
    function mergeCart() {
        var out = [], seen = {};
        $.each(S.order.cart, function (_, l) {
            var k = lineKey(l);
            if (seen[k] !== undefined) out[seen[k]].qty = Math.min(999, out[seen[k]].qty + l.qty);
            else { seen[k] = out.length; out.push(l); }
        });
        S.order.cart = out;
    }

    function toggleLineTa(key) {
        var i = cartLine(key);
        if (i < 0) return;
        S.order.cart[i].ta = !S.order.cart[i].ta;
        mergeCart();
        cartChanged();
    }

    /** Pack the whole order to go (or put it all back to dine in). */
    function toggleAllTa() {
        var c = S.order.cart, allTa = c.length > 0;
        $.each(c, function (_, l) { if (!l.ta) allTa = false; });
        $.each(c, function (_, l) { l.ta = !allTa; });
        mergeCart();
        cartChanged();
    }

    function renderOrder() {
        if (!S.menu || !S.order) return;
        var m = S.menu, o = S.order, $o = $('#diOrder');

        // categories with a running count of what is picked from each
        var perCat = {};
        $.each(o.cart, function (_, l) { var it = m.byId[l.id]; if (it) perCat[it.CAT_NUM] = (perCat[it.CAT_NUM] || 0) + l.qty; });
        var cats = '';
        $.each(m.cats, function (_, c) {
            var cn = n(c.CAT_NUM), q = perCat[cn] || 0, on = !o.q && cn === o.cat;
            cats += '<button type="button" data-cat="' + cn + '" class="' + (on ? 'is-on' : '') + '" aria-pressed="' + on + '">' +
                    '<span>' + esc(c.CAT_NAME) + '</span>' + (q ? '<span class="q">' + q + '</span>' : '') + '</button>';
        });
        $o.find('.js-cats').html(cats);

        // items: the category, or a search across everything
        var list, title;
        if (o.q) {
            var q = o.q.toLowerCase();
            list = $.grep(m.items, function (it) {
                return String(it.ITEM_NAME).toLowerCase().indexOf(q) >= 0 || String(it.ITEM_NAME_ARABIC || '').indexOf(o.q) >= 0;
            });
            title = 'Search';
        } else {
            list = m.byCat[o.cat] || [];
            var cat = $.grep(m.cats, function (c) { return n(c.CAT_NUM) === o.cat; })[0];
            title = cat ? cat.CAT_NAME : 'Items';
        }
        $o.find('.js-catname').text(title);
        $o.find('.js-catcount').text(list.length + (list.length === 1 ? ' item' : ' items'));

        var grid = '';
        $.each(list, function (_, it) {
            var q = cartQty(it.ItemID);
            grid += '<button type="button" class="di-item' + (q ? ' in-cart' : '') + '" data-item="' + it.ItemID + '" aria-label="Add ' + esc(it.ITEM_NAME) + '">' +
                '<span class="nm">' + esc(it.ITEM_NAME) + (it.ITEM_NAME_ARABIC ? '<span class="ar">' + esc(it.ITEM_NAME_ARABIC) + '</span>' : '') + '</span>' +
                '<span class="ft"><span class="pr">' + money(it.PRICE) + ' <small>' + esc(CUR) + '</small></span>' +
                '<span class="pl"><svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" aria-hidden="true"><path d="M12 5v14"/><path d="M5 12h14"/></svg></span></span>' +
                '<span class="badge">' + q + '</span></button>';
        });
        $o.find('.js-grid').html(grid || '<div class="di-cart-empty"><b>Nothing found</b>Try another word or category.</div>');

        renderCart();
    }

    function renderCart() {
        var o = S.order, m = S.menu, $o = $('#diOrder'), html = '', count = 0, total = 0;
        if (o && m) {
            var canTa = !!o.table;       // the per-item mark is for Dine-In; a Take Away bill is Take Away as a whole
            $.each(o.cart, function (_, l) {
                var it = m.byId[l.id]; if (!it) return;
                count += l.qty; total += it.PRICE * l.qty;
                html += '<div class="di-cline' + (canTa && l.ta ? ' is-ta' : '') + '" data-key="' + lineKey(l) + '">' +
                    '<div class="nm"><b>' + esc(it.ITEM_NAME) + '</b><small>' + money(it.PRICE) + ' each</small>' +
                    (canTa ? '<button type="button" class="ta js-ta' + (l.ta ? ' is-on' : '') + '" aria-pressed="' + (!!l.ta) + '">' + ICON.bag + '<span>Take away</span></button>' : '') + '</div>' +
                    '<div class="qty"><button type="button" class="js-dec" aria-label="Remove one ' + esc(it.ITEM_NAME) + '">&minus;</button>' +
                    '<span>' + l.qty + '</span><button type="button" class="plus js-inc" aria-label="Add one ' + esc(it.ITEM_NAME) + '">+</button></div>' +
                    '<span class="lt">' + money(it.PRICE * l.qty) + '</span></div>';
            });
        }
        $o.find('.js-lines').html(html || '<div class="di-cart-empty">' +
            '<svg width="36" height="36" viewBox="0 0 24 24" fill="none" stroke="#9AAAA2" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 2l-2 4v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V6l-2-4z"/><path d="M4 6h16"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>' +
            '<b>No items yet</b>Tap an item to add it.</div>');
        // "Pack all" only on a Dine-In order with something in it
        var allTa = !!(o && o.cart.length);
        if (o) $.each(o.cart, function (_, l) { if (!l.ta) allTa = false; });
        $o.find('.js-ta-all').prop('hidden', !(o && o.table && o.cart.length)).text(allTa ? 'Unpack all' : 'Pack all').toggleClass('is-on', allTa);
        $o.find('.js-count').text(count);
        $o.find('.js-bill').text(money(total));
        $o.find('.js-total').text(kd(total));
        $o.find('.js-send').prop('disabled', count === 0);
    }

    function closeOrder(force) {
        var o = S.order;
        if (!o) return hide('diOrder');
        if (!force && o.cart.length && !o.discard) {
            o.discard = true;
            $('#diOrder .js-err').text('There are items on this order. Close again to discard them.');
            return;
        }
        var t = o.table, mode = o.mode, inv = o.invoiceNo;
        S.order = null;
        hide('diOrder');
        if (t && mode === 'new') {
            toast('Table ' + t.Table_No + ' stays occupied. Tap it to order or free it.');
            loadFloor();
        }
        if (t && mode === 'add') openTablePopup(t.TableID);
        if (!t && mode === 'add') openTaPopup(inv);      // back to the Take Away order
    }

    function sendOrder() {
        var o = S.order, $o = $('#diOrder'), $b = $o.find('.js-send'), $err = $o.find('.js-err');
        if (!o || !o.cart.length) return;

        var isTa = !o.table;
        var items = $.map(o.cart, function (l) { return { ItemID: l.id, Quantity: l.qty, TakeAway: !isTa && !!l.ta }; });
        var req;
        if (o.mode === 'add') {
            req = api('POST', C.urls.addItems, { tableId: isTa ? 0 : o.table.TableID, invoiceNo: o.invoiceNo, items: JSON.stringify(items) });
        } else {
            var name = '', mobile = '';
            if (isTa) {
                name = $.trim($o.find('.js-ta-name').val());
                mobile = $.trim($o.find('.js-ta-mobile').val()).replace(/\D/g, '');
                if (mobile && mobile.length < 7) { $err.text('That mobile number looks too short.'); $o.find('.js-ta-mobile').trigger('focus'); return; }
            }
            req = api('POST', C.urls.placeOrder, {
                tableId: o.table ? o.table.TableID : null, branchId: S.branchId,
                items: JSON.stringify(items), clientGuid: o.guid, name: name, mobile: mobile
            });
        }

        busy($b, true); $err.text('');
        req.done(function (r) {
            var t = o.table, mode = o.mode;
            S.order = null;
            // kitchen tickets for what was just ordered (new items only), silently, to the LAN printers
            if (window.PosPrint) PosPrint.order(mode === 'add' ? o.invoiceNo : r.InvoiceNo);
            hide('diOrder');
            closeTablePopup();                       // the order is in: straight back to the page, not the bill
            if (r.Warning) toast(r.Warning, true);
            if (t) {
                toast(mode === 'add' ? 'Items added to Table ' + t.Table_No : 'Order saved · Table ' + t.Table_No);
                loadFloor();
            } else {
                toast(mode === 'add' ? 'Items added to the Take Away order'
                                     : 'Take Away order #' + (r.RunningOrder || r.InvoiceNo) + ' saved · ' + kd(r.NetPayable));
                loadTa();
            }
        }).fail(function (msg) { $err.text(msg); })
          .always(function () { busy($b, false); });
    }

    // =========================================================================
    // occupied table popup
    // =========================================================================
    function openTablePopup(tableId) {
        var t = S.byId[tableId];
        S.tp = { tableId: tableId, data: null, bill: S.tp && S.tp.tableId === tableId ? S.tp.bill : 0, menuOpen: false, sel: {}, canPick: false };
        var $p = $('#diTable');
        $p.find('.js-hex').html(badgeHex(t ? t.Table_No : '', true, 52));
        $('#diTableTitle').text('Table ' + (t ? t.Table_No : ''));
        $p.find('.js-sub').text('');
        $p.find('.js-body').html('<div class="di-cart-empty">Loading…</div>');
        $p.find('.js-actions').empty();
        show('diTable');
        $('#diCanvas .di-tbl').removeClass('is-sel');
        $('#diCanvas .di-tbl[data-id="' + tableId + '"]').addClass('is-sel');
        reloadTablePopup();
    }

    function reloadTablePopup() {
        if (!S.tp) return;
        if (S.tp.ta) return reloadTaPopup();
        var id = S.tp.tableId;
        api('GET', C.urls.table, { id: id }).done(function (r) {
            if (!S.tp || S.tp.tableId !== id) return;
            S.tp.data = r;
            var t = r.Table;
            if (n(t.Status) !== 1) {          // freed on another screen
                closeTablePopup();
                toast('Table ' + t.Table_No + ' is vacant now.');
                return;
            }
            if (S.tp.bill >= (r.Bills || []).length) S.tp.bill = 0;
            renderTablePopup();
        }).fail(function (msg) {
            $('#diTable .js-body').html('<div class="di-cart-empty"><b>Could not load the table</b>' + esc(msg) + '</div>');
        });
    }

    function closeTablePopup() {
        S.tp = null;
        hide('diTable');
        $('#diCanvas .di-tbl').removeClass('is-sel');
    }

    function currentBill() {
        var d = S.tp && S.tp.data;
        return d && d.Bills && d.Bills.length ? d.Bills[S.tp.bill] : null;
    }

    function renderTablePopup() {
        var d = S.tp.data, t = d.Table, bills = d.Bills || [], bill = currentBill(), $p = $('#diTable');

        var isTa = !!S.tp.ta, html;
        if (isTa) {
            var qty = 0;
            $.each(d.Lines || [], function (_, l) { if (!l.ParentOrderID) qty += n(l.Quantity); });
            $p.find('.js-hex').html(badgeHex('TA', true, 52));
            $('#diTableTitle').text('Take Away #' + (bill.RunningOrder || bill.InvoiceNo));
            $p.find('.js-sub').text('Take Away · ' + taTime(bill.InvoiceDate));
            html = '<div class="di-tp-meta">' +
                '<div><span>Customer</span><b>' + esc(taWho(bill)) + '</b></div>' +
                '<div><span>Mobile</span><b>' + esc(bill.Mobile ? '+965 ' + bill.Mobile : '—') + '</b></div>' +
                '<div><span>Items</span><b>' + qty + '</b></div>' +
                '<div><span>Placed</span><b>' + esc(taTime(bill.InvoiceDate)) + '</b></div></div>';
        } else {
            $p.find('.js-hex').html(badgeHex(t.Table_No, true, 52));
            $('#diTableTitle').text('Table ' + t.Table_No);
            $p.find('.js-sub').text([t.AreaName, t.OpenedByName ? 'opened by ' + t.OpenedByName : ''].filter(Boolean).join(' · '));
            html = '<div class="di-tp-meta">' +
                '<div><span>Guest</span><b>' + esc(t.CustomerName || 'Walk-in') + '</b></div>' +
                '<div><span>Mobile</span><b>' + esc(t.Mobile ? '+965 ' + t.Mobile : '—') + '</b></div>' +
                '<div><span>Persons</span><b>' + n(t.Persons) + ' / ' + n(t.Capacity) + '</b></div>' +
                '<div><span>Seated for</span><b>' + n(t.MinutesSeated) + ' min</b></div></div>';
        }

        if (t.IsLegacyLock) {
            html += '<div class="di-note di-note--warn">This table was marked occupied outside the Dine-In screen. If nobody is seated, free it.</div>';
        } else if (!bills.length) {
            html += '<div class="di-note di-note--ok">Guests are seated. Nothing has been ordered yet.</div>';
        } else {
            if (bills.length > 1) {
                html += '<div class="di-bills" role="tablist">';
                $.each(bills, function (i, b) {
                    var paid = n(b.AmountPaid) + 0.0005 >= n(b.NetPayable);
                    html += '<button type="button" role="tab" data-bill="' + i + '" class="' + (i === S.tp.bill ? 'is-on' : '') + '" aria-selected="' + (i === S.tp.bill) + '">' +
                            'Bill ' + (i + 1) + ' · #' + esc(b.RunningOrder || b.InvoiceNo) + (paid ? '<span class="paid">PAID</span>' : '') + '</button>';
                });
                html += '</div>';
            }

            var lines = $.grep(d.Lines || [], function (l) { return n(l.InvoiceNo) === n(bill.InvoiceNo); });
            var parents = $.grep(lines, function (l) { return !l.ParentOrderID; });

            // item rows can be ticked for Split bill: Dine-In, two or more items, nothing paid yet
            S.tp.canPick = !isTa && parents.length >= 2 && n(bill.AmountPaid) <= 0;
            var keep = {};
            $.each(parents, function (_, l) { if (S.tp.sel[l.OrderID]) keep[l.OrderID] = true; });
            S.tp.sel = S.tp.canPick ? keep : {};

            if (S.tp.canPick) html += '<div class="di-pickhint">Tap the items you want on a separate bill, then press <b>Split bill</b>.</div>';
            html += '<div class="di-lines">';
            $.each(parents, function (_, l) {
                html += lineHtml(l, false);
                $.each(lines, function (_, k) { if (n(k.ParentOrderID) === n(l.OrderID)) html += lineHtml(k, true); });
            });
            html += '</div>';
            if (S.tp.canPick) html += '<div class="di-selbar js-selbar" hidden></div>';

            var due = Math.max(0, n(bill.NetPayable) - n(bill.AmountPaid));
            html += '<div class="di-totals">' +
                '<div class="row"><span>Bill #' + esc(bill.RunningOrder || bill.InvoiceNo) + ' · ' + esc(bill.InvoiceNumShow || bill.InvoiceNo) + '</span><span>' + money(bill.BillAmount) + '</span></div>' +
                (n(bill.Discount) > 0 ? '<div class="row"><span>Discount</span><span>&minus;' + money(bill.Discount) + '</span></div>' : '') +
                (n(bill.AmountPaid) > 0 ? '<div class="row"><span>Paid</span><span>' + money(bill.AmountPaid) + '</span></div>' : '') +
                '<div class="due"><span>' + (due > 0 ? 'Amount due' : 'Paid in full') + '</span><strong>' + kd(due > 0 ? due : bill.NetPayable) + '</strong></div></div>';
        }
        $p.find('.js-body').html(html);
        renderTableActions(t, bills, bill);
        updateSelUi();
    }

    // ---- selecting rows for Split bill ------------------------------------------
    function selectedParents() {
        var bill = currentBill(), out = [];
        if (!bill || !S.tp) return out;
        $.each(S.tp.data.Lines || [], function (_, l) {
            if (n(l.InvoiceNo) === n(bill.InvoiceNo) && !l.ParentOrderID && S.tp.sel[l.OrderID]) out.push(l);
        });
        return out;
    }

    /** What the chosen rows add up to: each item plus its extras. */
    function selectedTotal() {
        var bill = currentBill(), total = 0;
        if (!bill) return 0;
        $.each(S.tp.data.Lines || [], function (_, l) {
            if (n(l.InvoiceNo) !== n(bill.InvoiceNo)) return;
            if (S.tp.sel[l.OrderID] || (l.ParentOrderID && S.tp.sel[l.ParentOrderID])) total += n(l.LineTotal);
        });
        return total;
    }

    function updateSelUi() {
        if (!S.tp || S.tp.ta) return;
        var cnt = selectedParents().length;
        $('#diTable .js-selbar').prop('hidden', !cnt)
            .html('<span><b>' + cnt + '</b> ' + (cnt === 1 ? 'item' : 'items') + ' selected</span><strong>' + kd(selectedTotal()) + '</strong>');
        $('#diTable .js-a-split span').text(cnt ? 'Split bill (' + cnt + ')' : 'Split bill');
    }

    function toggleSel($row) {
        var id = n($row.data('order'));
        if (!S.tp || !S.tp.canPick || !id) return;
        if (S.tp.sel[id]) delete S.tp.sel[id]; else S.tp.sel[id] = true;
        $row.toggleClass('is-sel', !!S.tp.sel[id]).attr('aria-checked', !!S.tp.sel[id]);
        updateSelUi();
    }

    /** The comment without the TAKE AWAY mark (the mark is shown as a chip). */
    function cleanNote(c) { return String(c == null ? '' : c).replace(/^\s*TAKE AWAY\s*(-\s*)?/i, ''); }

    function lineHtml(l, isChild) {
        var inTa = !!(S.tp && S.tp.ta), mark = !!l.IsTakeAway && !inTa, note = cleanNote(l.Comments);
        var pick = !isChild && !!(S.tp && S.tp.canPick), sel = pick && !!S.tp.sel[l.OrderID];
        return '<div class="di-line' + (isChild ? ' is-child' : '') + (mark ? ' is-ta' : '') + (pick ? ' is-pick' : '') + (sel ? ' is-sel' : '') + '"' +
            (pick ? ' data-order="' + l.OrderID + '" role="checkbox" aria-checked="' + sel + '" tabindex="0"' : '') + '>' +
            (pick ? '<span class="chk" aria-hidden="true"></span>' : '') +
            '<span class="q">' + n(l.Quantity) + '×</span>' +
            '<span class="n">' + esc(l.ItemName) + (mark ? '<span class="di-tachip">Take away</span>' : '') +
            '<small>' + money(l.Price) + ' each' + (note ? ' · ' + esc(note) : '') + '</small></span>' +
            '<span class="t">' + money(l.LineTotal) + '</span>' +
            (!isChild && !inTa ? '<button type="button" class="tgl js-ta-line' + (mark ? ' is-on' : '') + '" data-order="' + l.OrderID + '" aria-pressed="' + mark +
                '" aria-label="' + (mark ? 'Remove take away from ' : 'Mark take away: ') + esc(l.ItemName) + '" title="' + (mark ? 'Take away - tap to undo' : 'Mark as take away') + '">' + ICON.bag + '</button>' : '') +
            '<button type="button" class="del js-del-line" data-order="' + l.OrderID + '" aria-label="Delete ' + esc(l.ItemName) + '">' +
            '<svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/><path d="M10 11v6"/><path d="M14 11v6"/></svg>' +
            '</button></div>';
    }

    var ICON = {
        add:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="9"/><path d="M12 8v8"/><path d="M8 12h8"/></svg>',
        print: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 9V3h12v6"/><rect x="3" y="9" width="18" height="8" rx="2"/><path d="M6 14h12v7H6z"/></svg>',
        pay:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="2" y="5" width="20" height="14" rx="2"/><path d="M2 10h20"/><path d="M6 15h4"/></svg>',
        move:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M17 3l4 4-4 4"/><path d="M21 7H9"/><path d="M7 21l-4-4 4-4"/><path d="M3 17h12"/></svg>',
        split: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="6" cy="6" r="3"/><circle cx="6" cy="18" r="3"/><path d="M20 4L8.1 15.9"/><path d="M14.5 14.5L20 20"/><path d="M8.1 8.1L12 12"/></svg>',
        trash: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M3 6h18"/><path d="M8 6V4h8v2"/><path d="M19 6l-1 14H6L5 6"/></svg>',
        bag:   '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="M6 2L3 6v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2V6l-3-4z"/><path d="M3 6h18"/><path d="M16 10a4 4 0 0 1-8 0"/></svg>',
        free:  '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><rect x="4" y="11" width="16" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 7.5-2"/></svg>'
    };

    function act(cls, icon, label, disabled, extra) {
        return '<button type="button" class="di-act ' + cls + '"' + (disabled ? ' disabled' : '') + (extra || '') + '>' + icon + '<span>' + label + '</span></button>';
    }

    function renderTableActions(t, bills, bill) {
        var html, $a = $('#diTable .js-actions');
        $a.removeClass('is-four');
        if (S.tp.ta) {
            var dueTa = Math.max(0, n(bill.NetPayable) - n(bill.AmountPaid));
            html = act('js-a-add', ICON.add, 'Add item', false) +
                   '<div style="position:relative;display:flex;">' + act('js-a-print', ICON.print, 'Print', false, ' aria-haspopup="true" style="flex:1"') + '</div>' +
                   '<button type="button" class="di-act di-act--pay js-a-pay"' + (!C.canPay || dueTa <= 0 ? ' disabled' : '') + '>' + ICON.pay + '<b>Pay</b></button>' +
                   act('di-act--danger js-a-delbill', ICON.trash, 'Delete bill', false);
            $a.addClass('is-four').html(html).css('grid-template-columns', '');
            return;
        }
        if (t.IsLegacyLock || !bills.length) {
            html = act('js-a-order', ICON.add, 'Take order', !!t.IsLegacyLock) +
                   act('js-a-transfer', ICON.move, 'Transfer', !!t.IsLegacyLock) +
                   act('di-act--danger js-a-free', ICON.free, 'Free table', false);
            $a.html(html).css('grid-template-columns', 'repeat(3, minmax(0, 1fr))');
            return;
        }
        var due = Math.max(0, n(bill.NetPayable) - n(bill.AmountPaid));

        html = act('js-a-add', ICON.add, 'Add item', false) +
               '<div style="position:relative;display:flex;">' + act('js-a-print', ICON.print, 'Print', false, ' aria-haspopup="true" style="flex:1"') + '</div>' +
               '<button type="button" class="di-act di-act--pay js-a-pay"' + (!C.canPay || due <= 0 ? ' disabled' : '') + '>' + ICON.pay + '<b>Pay</b></button>' +
               act('js-a-transfer', ICON.move, 'Transfer', false) +
               act('js-a-split', ICON.split, 'Split bill', !S.tp.canPick) +
               act('di-act--danger js-a-delbill', ICON.trash, 'Delete bill', false);
        $a.html(html).css('grid-template-columns', '');
    }

    function togglePrintMenu($btn) {
        var $wrap = $btn.parent(), $m = $wrap.find('.di-menu');
        if ($m.length) { $m.remove(); return; }
        $wrap.append('<div class="di-menu" role="menu">' +
            '<button type="button" role="menuitem" data-doc="Thermal">Customer bill</button>' +
            '<button type="button" role="menuitem" data-doc="Kitchen">Kitchen ticket</button>' +
            '<button type="button" role="menuitem" data-doc="A4">A4 invoice</button></div>');
    }

    function printDoc(invoiceNo, doc) {
        window.open(C.urls.print + '?id=' + encodeURIComponent(invoiceNo) + '&doc=' + encodeURIComponent(doc || 'Thermal'),
                    'dineinPrint', 'width=460,height=760');
    }

    // =========================================================================
    // action sheet
    // =========================================================================
    function openSheet(title, sub, body, foot, kind) {
        var $s = $('#diSheet');
        $s.toggleClass('is-pay', kind === 'pay');
        $('#diSheetTitle').text(title);
        $s.find('.js-sub').text(sub || '');
        $s.find('.js-body').html(body);
        $s.find('.js-foot').html(foot);
        show('diSheet');
        setTimeout(function () { $s.find('input,textarea,select').filter(':visible').first().trigger('focus'); }, 50);
    }
    function closeSheet() { hide('diSheet'); }

    function sheetErr(msg) { $('#diSheet .js-err').text(msg || ''); }

    function passwordFields() {
        return '<div class="di-field"><label for="diShPwd">Manager password</label>' +
               '<input id="diShPwd" type="password" class="di-input" autocomplete="off" /></div>' +
               '<div class="di-err js-err" role="alert"></div>';
    }

    // ---- delete one line ----------------------------------------------------
    function sheetDeleteLine(orderId) {
        var line = $.grep(S.tp.data.Lines || [], function (l) { return n(l.OrderID) === n(orderId); })[0];
        if (!line) return;
        openSheet('Delete item', n(line.Quantity) + ' × ' + line.ItemName + ' · ' + money(line.LineTotal),
            '<div class="di-field"><span class="lbl">What happens to it?</span><div class="di-choice">' +
            '<label><input type="radio" name="diDisp" value="1" checked /> Waste</label>' +
            '<label><input type="radio" name="diDisp" value="2" /> Reuse</label></div></div>' +
            '<div class="di-field"><label for="diShNote">Reason</label><textarea id="diShNote" class="di-textarea" maxlength="500" placeholder="e.g. Customer changed their mind"></textarea></div>' +
            passwordFields(),
            '<button type="button" class="di-btn--ghost js-close">Cancel</button>' +
            '<button type="button" class="di-btn--danger grow js-go">Delete item</button>');

        $('#diSheet .js-go').on('click', function () {
            var $b = $(this);
            busy($b, true); sheetErr();
            api('POST', C.urls.deleteLine, {
                tableId: S.tp.tableId, invoiceNo: line.InvoiceNo, orderId: line.OrderID,
                disposition: $('input[name=diDisp]:checked').val(),
                comment: $.trim($('#diShNote').val()), password: $('#diShPwd').val()
            }).done(function (r) {
                closeSheet();
                toast(r.Warning || 'Item deleted', !!r.Warning);
                reloadTablePopup(); loadFloor();
            }).fail(sheetErr).always(function () { busy($b, false); });
        });
    }

    // ---- delete whole bill ----------------------------------------------------
    function sheetDeleteBill() {
        var bill = currentBill();
        ensureLookups().always(function () {
            var reasons = (S.lookups && S.lookups.CancelReasons) || [], opts = '';
            $.each(reasons, function (_, r) { opts += '<option>' + esc(r.ReasonName) + '</option>'; });
            openSheet('Delete bill', 'Bill #' + (bill.RunningOrder || bill.InvoiceNo) + ' · ' + kd(bill.NetPayable),
                '<div class="di-note di-note--busy" style="margin-bottom:14px;">The whole bill is cancelled. The table is freed if nothing else on it is unpaid.</div>' +
                (opts ? '<div class="di-field"><label for="diShReason">Reason</label><select id="diShReason" class="di-input">' + opts + '</select></div>' : '') +
                '<div class="di-field"><label for="diShNote">' + (opts ? 'Note' : 'Reason') + '</label><textarea id="diShNote" class="di-textarea" maxlength="400"></textarea></div>' +
                passwordFields(),
                '<button type="button" class="di-btn--ghost js-close">Keep bill</button>' +
                '<button type="button" class="di-btn--danger grow js-go">Delete bill</button>');

            $('#diSheet .js-go').on('click', function () {
                var $b = $(this), reason = $('#diShReason').val() || '', note = $.trim($('#diShNote').val());
                var comment = reason && note ? reason + ' - ' + note : (reason || note);
                if (!comment) { sheetErr('Give a reason.'); return; }
                busy($b, true); sheetErr();
                api('POST', C.urls.deleteBill, {
                    tableId: S.tp.tableId, invoiceNo: bill.InvoiceNo, comment: comment, password: $('#diShPwd').val()
                }).done(function (r) {
                    closeSheet();
                    if (S.tp.ta) { closeTablePopup(); toast('Take Away bill deleted'); loadTa(); }
                    else if (r.Freed) { var no = S.tp.data.Table.Table_No; closeTablePopup(); toast('Bill deleted · Table ' + no + ' is free'); }
                    else { toast('Bill deleted'); reloadTablePopup(); }
                    loadFloor();
                }).fail(sheetErr).always(function () { busy($b, false); });
            });
        });
    }

    // ---- pay ------------------------------------------------------------------
    function ensureLookups() {
        if (S.lookups) return $.Deferred().resolve(S.lookups).promise();
        if (S.lookupsReq) return S.lookupsReq;
        S.lookupsReq = api('GET', C.urls.lookups).done(function (r) { S.lookups = r; });
        S.lookupsReq.fail(function () { S.lookupsReq = null; });
        return S.lookupsReq;
    }

    /** The tender types for the popup: no COD, Cash first. */
    function payTypes(lk) {
        function isCash(p) {
            return p.IsCash === true || p.IsCash === 1 ||
                   (/cash|\u0646\u0642\u062f/i.test(p.PaymentTypeName || '') && !/deliver|\bcod\b/i.test(p.PaymentTypeName || ''));
        }
        var cash = null, rest = [];
        $.each(lk.PaymentTypes || [], function (_, p) {
            if (!cash && isCash(p)) cash = $.extend({}, p, { PaymentTypeName: 'Cash' });   // shown as Cash even if the row is 'Cash on Delivery'
            else if (!p.IsCOD) rest.push(p);
        });
        return { list: cash ? [cash].concat(rest) : rest, cash: !!cash };
    }

    /**
     * Take Payment popup, used for a whole bill and for a split.
     *   cfg.title, cfg.sub, cfg.due
     *   cfg.onPay(lines, reference)  -> promise; lines = [{TypeID, Amount}]
     *   cfg.done(result)             after a successful payment
     *   cfg.failed(result)           after a refused payment (optional)
     *   cfg.alt = { label, run(), done(result) }   a second way out, e.g. "Split, pay later"
     *
     * Layout: the bill to pay, Cash on its own first row, the other tenders two
     * to a row, and a number pad that opens as soon as an amount box is touched
     * (the first one is touched for you), so nothing needs the on-screen
     * keyboard of the device.
     */
    function openPaySheet(cfg) {
        var due = Math.max(0, n(cfg.due));
        ensureLookups().done(function (lk) {
            var pt = payTypes(lk), rows = '';
            $.each(pt.list, function (i, p) {
                var isCash = pt.cash && i === 0;
                rows += '<div class="di-pay-row' + (isCash ? ' is-cash' : '') + '" data-type="' + p.PaymentTypeID + '" data-ref="' + (p.RequiresReference ? 1 : 0) + '" data-name="' + esc(p.PaymentTypeName) + '">' +
                    '<label class="nm" for="diPay' + i + '">' + esc(p.PaymentTypeName) + '</label>' +
                    '<input id="diPay' + i + '" class="di-input js-amt" type="text" inputmode="none" autocomplete="off" placeholder="0.000" aria-label="' + esc(p.PaymentTypeName) + ' amount" />' +
                    '</div>';
            });

            var keys = '<div class="di-keys" role="group" aria-label="Number pad">' +
                '<div class="di-keys__target">Entering <b class="js-ktarget">Cash</b></div>' +
                '<div class="di-keys__notes"><button type="button" data-add="1">+1</button><button type="button" data-add="5">+5</button>' +
                '<button type="button" data-add="10">+10</button><button type="button" data-add="20">+20</button></div>' +
                '<div class="di-keys__pad">' +
                $.map(['7', '8', '9'], function (k) { return '<button type="button" data-k="' + k + '">' + k + '</button>'; }).join('') +
                '<button type="button" class="k-del" data-k="back" aria-label="Backspace">&#9003;</button>' +
                $.map(['4', '5', '6'], function (k) { return '<button type="button" data-k="' + k + '">' + k + '</button>'; }).join('') +
                '<button type="button" class="k-clr" data-k="clear">C</button>' +
                $.map(['1', '2', '3'], function (k) { return '<button type="button" data-k="' + k + '">' + k + '</button>'; }).join('') +
                '<button type="button" class="k-exact" data-k="exact">Exact</button>' +
                '<button type="button" class="k-0" data-k="0">0</button><button type="button" data-k=".">.</button>' +
                '</div></div>';

            openSheet(cfg.title || 'Take payment', cfg.sub || '',
                '<div class="di-pay">' +
                '<div class="di-pay-top"><div class="di-pay-due"><span>Bill Amount</span><strong>' + kd(due) + '</strong></div>' +
                '<div class="di-pay-sum js-sum"><span>Change Amount</span><b>0.000</b></div></div>' +
                '<div class="di-pay-grid">' + rows + '</div>' + keys +
                '<div class="di-field js-refwrap" hidden><div class="di-refhead"><label for="diPayRef">Reference / approval no.</label><span class="di-referr js-referr" role="alert"></span></div><input id="diPayRef" class="di-input" autocomplete="off" maxlength="100" /></div>' +
                '<div class="di-err js-err" role="alert"></div></div>',
                '<button type="button" class="di-btn--ghost js-close">Cancel</button>' +
                (cfg.alt ? '<button type="button" class="di-btn--ghost js-alt">' + esc(cfg.alt.label) + '</button>' : '') +
                '<button type="button" class="di-btn--go grow js-go" disabled>Take payment</button>', 'pay');

            var $s = $('#diSheet'), $active = null, fresh = false;

            function recalc() {
                var tendered = 0, needRef = false;
                $s.find('.di-pay-row').each(function () {
                    var v = n($(this).find('.js-amt').val());
                    tendered += v;
                    $(this).toggleClass('has-val', v > 0);
                    if (v > 0 && $(this).data('ref') === 1) needRef = true;
                });
                $s.find('.js-refwrap').prop('hidden', !needRef);
                var diff = tendered - due;
                $s.find('.js-sum').toggleClass('is-change', diff > 0.0005)
                  .html(diff < -0.0005 && tendered > 0 ? '<span>Balance still due</span><b>' + kd(-diff) + '</b>'
                                                       : '<span>Change Amount</span><b>' + kd(Math.max(0, diff)) + '</b>');
                $s.find('.js-go').prop('disabled', tendered <= 0 || !C.canPay);
                return tendered;
            }

            function activate($inp) {
                if (!$inp || !$inp.length) return;
                $s.find('.di-pay-row').removeClass('is-active');
                $active = $inp; fresh = true;
                var $row = $inp.closest('.di-pay-row').addClass('is-active');
                $s.find('.js-ktarget').text($row.data('name'));
                $s.find('.di-pay').addClass('has-keys');
            }

            /** What is still owed once the OTHER boxes are counted. */
            function remainder() {
                var others = 0;
                $s.find('.js-amt').each(function () { if (this !== $active[0]) others += n($(this).val()); });
                return Math.max(0, due - others);
            }

            function put(v) { $active.val(v); recalc(); }

            $s.find('.di-pay-grid')
                .on('focus click', '.js-amt', function () { activate($(this)); })
                .on('click', '.di-pay-row', function (e) { if (!$(e.target).is('input')) activate($(this).find('.js-amt')); });

            $s.on('input', '#diPayRef', function () { $s.find('.js-referr').text(''); $s.find('.js-refwrap').removeClass('has-err'); });
            $s.find('.js-amt').on('input', function () {
                this.value = this.value.replace(/[^0-9.]/g, '');
                fresh = false;
                recalc();
            });

            $s.find('.di-keys').on('click', 'button', function () {
                if (!$active) return;
                var k = $(this).data('k'), add = $(this).data('add'), cur = String($active.val() || '');
                if (add !== undefined) {
                    put(String(+(n(cur) + n(add)).toFixed(3))); fresh = false; return;
                }
                if (k === 'back')  { put(cur.slice(0, -1)); fresh = false; return; }
                if (k === 'clear') { put(''); fresh = false; return; }
                if (k === 'exact') { var r = remainder(); put(r > 0 ? money(r) : ''); fresh = true; return; }
                if (fresh) cur = '';
                fresh = false;
                if (k === '.') { if (cur.indexOf('.') >= 0) return; cur = (cur === '' ? '0' : cur) + '.'; }
                else cur += k;
                if (/^0\d/.test(cur)) cur = cur.replace(/^0+/, '') || '0';
                if (/\.\d{4,}/.test(cur) || cur.length > 9) return;
                put(cur);
            });

            function lines() {
                var out = [];
                $s.find('.di-pay-row').each(function () {
                    var v = n($(this).find('.js-amt').val());
                    if (v > 0) out.push({ TypeID: n($(this).data('type')), Amount: v });
                });
                return out;
            }

            function run($b, call, done, failed) {
                busy($s.find('.js-go, .js-alt'), true); sheetErr();
                $s.find('.js-referr').text(''); $s.find('.js-refwrap').removeClass('has-err');
                call.done(function (r) { closeSheet(); done(r); })
                    .fail(function (msg, r) {
                        if (/reference/i.test(msg || '')) {
                            // shown on the Reference line itself, where it cannot be scrolled out of sight
                            $s.find('.js-refwrap').prop('hidden', false).addClass('has-err');
                            $s.find('.js-referr').text(msg);
                            $('#diPayRef').trigger('focus');
                            var el = $s.find('.js-refwrap')[0]; if (el && el.scrollIntoView) el.scrollIntoView({ block: 'nearest' });
                        } else sheetErr(msg);
                        if (failed) failed(r);
                    })
                    .always(function () { busy($s.find('.js-go, .js-alt'), false); recalc(); });
            }

            $s.find('.js-go').on('click', function () {
                if (recalc() <= 0) return;
                run($(this), cfg.onPay(lines(), $.trim($('#diPayRef').val())), cfg.done, cfg.failed);
            });
            if (cfg.alt) $s.find('.js-alt').on('click', function () { run($(this), cfg.alt.run(), cfg.alt.done); });

            recalc();
            activate($s.find('.js-amt').first());          // Cash is ready for the keypad
        }).fail(function (msg) { toast(msg, true); });
    }

    // ---- pay a whole bill -------------------------------------------------------
    function sheetPay() {
        var bill = currentBill(), due = Math.max(0, n(bill.NetPayable) - n(bill.AmountPaid));
        openPaySheet({
            title: 'Take payment',
            sub: (S.tp.ta ? 'Take Away' : 'Table ' + S.tp.data.Table.Table_No) + ' · Bill #' + (bill.RunningOrder || bill.InvoiceNo),
            due: due,
            onPay: function (lines, ref) {
                return api('POST', C.urls.pay, { tableId: S.tp.tableId, invoiceNo: bill.InvoiceNo, lines: JSON.stringify(lines), reference: ref });
            },
            done: function (r) {
                var change = n(r.ChangeGiven);
                toast('Payment recorded' + (change > 0 ? ' · give change ' + kd(change) : ''));
                if (window.PosPrint) PosPrint.invoice(bill.InvoiceNo, { quiet: true });
                if (r.Freed) {
                    var no = S.tp.data.Table.Table_No;
                    closeTablePopup();
                    toast('All bills settled · Table ' + no + ' is free');
                } else reloadTablePopup();
                loadFloor();
                if (S.tp && S.tp.ta) loadTa();
            }
        });
    }

    // ---- transfer -------------------------------------------------------------
    function sheetTransfer() {
        var from = S.tp.data.Table, body = '', any = false, picked = null;
        $.each(S.areas, function (_, a) {
            var free = $.grep(S.tables, function (t) { return n(t.TableType) === n(a.TableType) && t.Status !== 1; });
            if (!free.length) return;
            any = true;
            body += '<div class="di-pick-area">' + esc(a.AreaName) + '</div><div class="di-pick">';
            $.each(free, function (_, t) {
                body += '<button type="button" data-id="' + t.TableID + '" aria-pressed="false">' + esc(t.Table_No) + '<small>' + t.Capacity + ' seats</small></button>';
            });
            body += '</div>';
        });
        openSheet('Transfer Table ' + from.Table_No, 'Guests and all their bills move to the table you pick',
            (any ? body : '<div class="di-note di-note--warn">There is no vacant table right now.</div>') + '<div class="di-err js-err" role="alert"></div>',
            '<button type="button" class="di-btn--ghost js-close">Cancel</button>' +
            '<button type="button" class="di-btn grow js-go" disabled>Pick a table</button>');

        var $s = $('#diSheet');
        $s.find('.di-pick button').on('click', function () {
            $s.find('.di-pick button').removeClass('is-on').attr('aria-pressed', 'false');
            $(this).addClass('is-on').attr('aria-pressed', 'true');
            picked = S.byId[$(this).data('id')];
            $s.find('.js-go').prop('disabled', false).text('Move to Table ' + picked.Table_No);
        });
        $s.find('.js-go').on('click', function () {
            if (!picked) return;
            var $b = $(this);
            busy($b, true); sheetErr();
            api('POST', C.urls.transfer, { fromTableId: from.TableID, toTableId: picked.TableID }).done(function () {
                closeSheet();
                closeTablePopup();
                toast('Moved Table ' + from.Table_No + ' to Table ' + picked.Table_No);
                loadFloor();
            }).fail(function (msg) { sheetErr(msg); loadFloor(); }).always(function () { busy($b, false); });
        });
    }

    // ---- split ----------------------------------------------------------------
    // The rows are ticked on the bill itself (see toggleSel). Split bill opens the
    // Take Payment popup for what was ticked; paying it creates the new bill.
    function startSplit() {
        var bill = currentBill(), picked = selectedParents();
        if (!bill || !S.tp.canPick) return;
        if (!picked.length) { toast('Tap the items you want to split first.', true); $('#diTable .di-pickhint').addClass('is-nudge'); return; }

        var all = $.grep(S.tp.data.Lines || [], function (l) { return n(l.InvoiceNo) === n(bill.InvoiceNo) && !l.ParentOrderID; });
        if (picked.length >= all.length) { toast('Leave at least one item on this bill. To pay everything, use Pay.', true); return; }

        var payload = $.map(picked, function (l) { return { OrderID: l.OrderID, Quantity: n(l.Quantity) }; }), no = bill.RunningOrder || bill.InvoiceNo;
        var tableNo = S.tp.data.Table.Table_No;

        function afterSplit(msg, freed) {
            S.tp.sel = {};
            toast(msg);
            if (freed) { closeTablePopup(); toast('All bills settled · Table ' + tableNo + ' is free'); }
            else reloadTablePopup();
            loadFloor();
        }

        openPaySheet({
            title: 'Pay split bill',
            sub: 'Table ' + tableNo + ' · ' + picked.length + (picked.length === 1 ? ' item' : ' items') + ' from bill #' + no,
            due: selectedTotal(),
            onPay: function (lines, ref) {
                return api('POST', C.urls.splitPay, { tableId: S.tp.tableId, invoiceNo: bill.InvoiceNo, lines: JSON.stringify(payload),
                                                       payLines: JSON.stringify(lines), reference: ref });
            },
            done: function (r) {
                var change = n(r.ChangeGiven);
                afterSplit('Split bill paid' + (change > 0 ? ' · give change ' + kd(change) : ''), r.Freed);
                if (window.PosPrint && r.NewInvoiceNo) PosPrint.invoice(r.NewInvoiceNo, { quiet: true });
            },
            failed: function (r) {
                if (r && r.Split) { closeSheet(); afterSplit('The items are on a new bill. Take its payment from the table.', false); }
            },
            alt: {
                label: 'Split, pay later',
                run: function () { return api('POST', C.urls.split, { tableId: S.tp.tableId, invoiceNo: bill.InvoiceNo, lines: JSON.stringify(payload) }); },
                done: function () { afterSplit('New bill created · unpaid', false); }
            }
        });
    }

    // ---- free a table with no unpaid bill -----------------------------------
    function freeTable() {
        var t = S.tp.data.Table;
        openSheet('Free Table ' + t.Table_No, 'Turns the table green on every screen',
            '<div class="di-note di-note--warn">Only free the table if the guests have left.</div><div class="di-err js-err" role="alert" style="margin-top:10px;"></div>',
            '<button type="button" class="di-btn--ghost js-close">Keep occupied</button>' +
            '<button type="button" class="di-btn--danger grow js-go">Free table</button>');
        $('#diSheet .js-go').on('click', function () {
            var $b = $(this);
            busy($b, true); sheetErr();
            api('POST', C.urls.release, { tableId: t.TableID, reason: 'Freed', force: !!t.IsLegacyLock && C.isAdmin })
                .done(function () { closeSheet(); closeTablePopup(); toast('Table ' + t.Table_No + ' is free'); loadFloor(); })
                .fail(sheetErr).always(function () { busy($b, false); });
        });
    }

    // =========================================================================
    // Take Away tab
    // =========================================================================
    function pad2(v) { return (v < 10 ? '0' : '') + v; }

    /** "7:45 PM" for today, "28/10 7:45 PM" for an older (still unpaid) order. */
    function taTime(iso) {
        var m = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2})/.exec(String(iso || ''));
        if (!m) return '';
        var h = n(m[4]), t = ((h % 12) || 12) + ':' + m[5] + ' ' + (h >= 12 ? 'PM' : 'AM');
        var d = new Date(), today = d.getFullYear() + '-' + pad2(d.getMonth() + 1) + '-' + pad2(d.getDate());
        return (m[1] + '-' + m[2] + '-' + m[3]) === today ? t : m[3] + '/' + m[2] + ' ' + t;
    }

    function taWho(b) {
        var nm = $.trim(b.CustomerName || '');
        return nm && nm !== 'Walk-in Customer' ? nm : 'Walk-in';
    }

    function loadTa() {
        return api('GET', C.urls.takeAway, { branchId: S.branchId }).done(function (r) {
            S.ta.bills = r.Bills || [];
            S.ta.lines = r.Lines || [];
            $.each(S.ta.bills, function (_, b) {
                b.InvoiceNo = n(b.InvoiceNo);
                b.Due = Math.max(0, n(b.NetPayable) - n(b.AmountPaid));
                b.IsPaid = b.Due <= 0.0005;
            });
            S.ta.loaded = true;
            renderTa();
        }).fail(function (msg) { if (S.mode === 'ta') toast(msg, true); });
    }

    function scheduleTaRefresh() {
        clearTimeout(S.taT);
        S.taT = setTimeout(loadTa, 180);
    }

    function renderTa() {
        var all = S.ta.bills, unpaid = 0, f = S.ta.filter;
        $.each(all, function (_, b) { if (!b.IsPaid) unpaid++; });

        // badge on the Take Away button: orders still to be paid
        $('#diTaBadge').text(unpaid).prop('hidden', unpaid < 1);

        var counts = { all: all.length, due: unpaid, paid: all.length - unpaid }, fh = '';
        $.each([['all', 'All'], ['due', 'Unpaid'], ['paid', 'Paid']], function (_, x) {
            fh += '<button type="button" data-f="' + x[0] + '" class="' + (f === x[0] ? 'is-on' : '') + '" aria-pressed="' + (f === x[0]) + '">' +
                  x[1] + '<span class="n">' + counts[x[0]] + '</span></button>';
        });
        $('#diTaFilters').html(fh);

        var list = $.grep(all, function (b) { return f === 'all' || (f === 'due' ? !b.IsPaid : b.IsPaid); });
        var html = '';
        $.each(list, function (_, b) {
            var lines = $.grep(S.ta.lines, function (l) { return n(l.InvoiceNo) === b.InvoiceNo && !l.ParentOrderID; });
            var qty = 0, li = '';
            $.each(lines, function (i, l) {
                qty += n(l.Quantity);
                if (i < 3) li += '<span class="li"><b>' + n(l.Quantity) + '×</b> ' + esc(l.ItemName) + '</span>';
            });
            if (lines.length > 3) li += '<span class="li more">+ ' + (lines.length - 3) + ' more</span>';
            var st = b.IsPaid ? 'Paid' : (n(b.AmountPaid) > 0 ? 'Part paid' : 'Unpaid');
            html += '<button type="button" class="di-tac ' + (b.IsPaid ? 'is-paid' : 'is-due') + '" data-inv="' + b.InvoiceNo + '">' +
                '<span class="hd"><b class="no">#' + esc(b.RunningOrder || b.InvoiceNo) + '</b><span class="tm">' + esc(taTime(b.InvoiceDate)) + '</span><span class="st">' + st + '</span></span>' +
                '<span class="who"><b>' + esc(taWho(b)) + '</b>' + (b.Mobile ? '<small>+965 ' + esc(b.Mobile) + '</small>' : '') + '</span>' +
                '<span class="its">' + (li || '<span class="li more">No items</span>') + '</span>' +
                '<span class="ft"><span>' + qty + (qty === 1 ? ' item' : ' items') + '</span><strong>' +
                kd(b.IsPaid ? b.NetPayable : b.Due) + '</strong></span></button>';
        });
        $('#diTaGrid').html(html);
        $('#diTaEmpty').prop('hidden', list.length > 0)
            .find('strong').text(all.length ? 'Nothing under ' + (f === 'due' ? 'Unpaid' : 'Paid') : 'No Take Away orders');
    }

    function taData(inv) {
        var bill = null;
        $.each(S.ta.bills, function (_, b) { if (b.InvoiceNo === n(inv)) bill = b; });
        if (!bill) return null;
        return {
            Table: { Table_No: 'TA', Status: 1, CustomerName: bill.CustomerName, Mobile: bill.Mobile },
            Bills: [bill],
            Lines: $.grep(S.ta.lines, function (l) { return n(l.InvoiceNo) === bill.InvoiceNo; })
        };
    }

    /** A Take Away order opens in the same popup a busy table does. */
    function openTaPopup(invoiceNo) {
        S.tp = { tableId: 0, ta: true, invoiceNo: n(invoiceNo), data: null, bill: 0, menuOpen: false, sel: {}, canPick: false };
        var $p = $('#diTable'), d = taData(invoiceNo);
        $p.find('.js-hex').html(badgeHex('TA', true, 52));
        $('#diTableTitle').text('Take Away');
        $p.find('.js-sub').text('');
        $p.find('.js-actions').empty();
        if (d) { S.tp.data = d; renderTablePopup(); }
        else $p.find('.js-body').html('<div class="di-cart-empty">Loading…</div>');
        show('diTable');
        reloadTablePopup();
    }

    function reloadTaPopup() {
        var inv = S.tp.invoiceNo;
        return loadTa().done(function () {
            if (!S.tp || !S.tp.ta || S.tp.invoiceNo !== inv) return;
            var d = taData(inv);
            if (!d) { closeTablePopup(); toast('That Take Away order is no longer open.'); return; }
            S.tp.data = d; S.tp.bill = 0;
            renderTablePopup();
        }).fail(function (msg) {
            $('#diTable .js-body').html('<div class="di-cart-empty"><b>Could not load the order</b>' + esc(msg) + '</div>');
        });
    }

    function setMode(m) {
        if (m === S.mode) return;
        if (S.arrange) setArrange(false);
        closeTablePopup();
        S.mode = m;
        var ta = m === 'ta';
        $('#di').toggleClass('is-ta', ta);
        $('#diModeDine').toggleClass('is-on', !ta).attr('aria-pressed', !ta);
        $('#diTakeAway').toggleClass('is-on', ta).attr('aria-pressed', ta);
        $('#diTa').prop('hidden', !ta);
        $('#diTaNew').prop('hidden', !ta);
        if (ta) loadTa();
        else { renderFloor(); loadFloor(); }
    }

    // ---- mark / unmark one item as Take Away ------------------------------------
    function toggleLineTakeAway($btn) {
        var bill = currentBill(), on = !$btn.hasClass('is-on');
        if (!bill) return;
        busy($btn, true);
        api('POST', C.urls.lineTa, { tableId: S.tp.tableId, invoiceNo: bill.InvoiceNo, orderId: $btn.data('order'), on: on })
            .done(function () {
                toast(on ? 'Marked take away. Reprint the kitchen ticket if it was already sent.' : 'Take away mark removed');
                reloadTablePopup();
            })
            .fail(function (msg) { toast(msg, true); })
            .always(function () { busy($btn, false); });
    }

    // =========================================================================
    // admin: arrange mode (pointer events: mouse, pen and touch alike)
    // =========================================================================
    function setArrange(on) {
        S.arrange = !!on;
        $('#di').toggleClass('is-arranging', S.arrange);
        $('#diArrange').toggleClass('is-on', S.arrange).find('span').text(S.arrange ? 'Arranging…' : 'Arrange tables');
        $('#diArrangeBar').prop('hidden', !S.arrange);
        sizeCanvas();
    }

    function onDragStart(e) {
        if (!S.arrange) return;
        var oe = e.originalEvent, $t = $(this), id = n($t.data('id')), p = S.pos[id];
        if (!p || (oe.button !== undefined && oe.button !== 0)) return;
        e.preventDefault();
        S.drag = { id: id, $el: $t, sx: oe.clientX, sy: oe.clientY, ox: p.x, oy: p.y, pid: oe.pointerId };
        $t.addClass('is-dragging');
        if (this.setPointerCapture && oe.pointerId !== undefined) { try { this.setPointerCapture(oe.pointerId); } catch (x) { } }
    }

    function onDragMove(e) {
        var d = S.drag; if (!d) return;
        var oe = e.originalEvent;
        var x = Math.max(0, Math.round((d.ox + (oe.clientX - d.sx) / S.scale) / SNAP) * SNAP);
        var y = Math.max(0, Math.round((d.oy + (oe.clientY - d.sy) / S.scale) / SNAP) * SNAP);
        S.pos[d.id] = { x: x, y: y };
        d.$el.css({ left: x, top: y }).find('.coords').text('X ' + x + ' · Y ' + y);
        if (x + TILE_W + PAD > S.canvasW || y + TILE_H + PAD > S.canvasH) sizeCanvas();
    }

    function onDragEnd() {
        var d = S.drag; if (!d) return;
        d.$el.removeClass('is-dragging');
        S.drag = null;
        sizeCanvas();
    }

    function saveLayout() {
        var $b = $('#diArrangeSave'), positions = [];
        $.each(floorTables(), function (_, t) {
            var p = S.pos[t.TableID];
            if (p) positions.push({ TableID: t.TableID, X: p.x, Y: p.y });
        });
        busy($b, true);
        api('POST', C.urls.saveLayout, { positions: JSON.stringify(positions) }).done(function (r) {
            toast('Layout saved · ' + (r.Updated || positions.length) + ' tables');
            setArrange(false);
            loadFloor();
        }).fail(function (msg) { toast(msg, true); })
          .always(function () { busy($b, false); });
    }

    // =========================================================================
    // live updates (SignalR, with a timer as the safety net)
    // =========================================================================
    function setLive(state) {
        S.live = state;
        var txt = state === 'on' ? 'Live' : state === 'wait' ? 'Reconnecting…' : 'Auto-refresh';
        $('#diLive').removeClass('is-wait is-off').addClass(state === 'on' ? '' : state === 'wait' ? 'is-wait' : 'is-off')
            .attr('title', state === 'off' ? 'Live updates are unavailable; the floor refreshes every 15 seconds.' : '')
            .find('.tx').text(txt);
    }

    function startHub() {
        if (!$.connection || !$.connection.dineInHub) { setLive('off'); return; }

        var hub = $.connection.dineInHub;
        hub.client.tableChanged = function (m) {
            scheduleRefresh();
            if (m && S.tp && n(m.TableID) === n(S.tp.tableId) && isOpen('diTable') && !isOpen('diSheet') && m.By !== C.user)
                reloadTablePopup();
        };
        hub.client.layoutChanged = function () { if (!S.arrange) scheduleRefresh(); };
        hub.client.takeAwayChanged = function (m) {
            if (S.tp && S.tp.ta && isOpen('diTable') && !isOpen('diSheet') && !(m && m.By === C.user)) reloadTablePopup();
            else scheduleTaRefresh();
        };

        var conn = $.connection.hub;
        conn.stateChanged(function (c) {
            // 0 connecting, 1 connected, 2 reconnecting, 4 disconnected
            setLive(c.newState === 1 ? 'on' : c.newState === 4 ? 'off' : 'wait');
        });
        conn.reconnected(function () { scheduleRefresh(); scheduleTaRefresh(); });
        conn.disconnected(function () { setTimeout(connect, 5000); });

        function connect() {
            conn.start().done(function () { setLive('on'); scheduleRefresh(); })
                        .fail(function () { setLive('off'); });
        }
        connect();
    }

    // =========================================================================
    // branch
    // =========================================================================
    function initBranch() {
        ensureLookups().done(function (lk) {
            var list = lk.Branches || [];
            if (!list.length) { loadTa(); return; }
            var saved = n(store('di.branch')), ok = false, opts = '';
            $.each(list, function (_, b) { if (n(b.BranchID) === saved) ok = true; });
            S.branchId = ok ? saved : n(list[0].BranchID);
            if (list.length > 1) {
                $.each(list, function (_, b) {
                    opts += '<option value="' + b.BranchID + '"' + (n(b.BranchID) === S.branchId ? ' selected' : '') + '>' + esc(b.BranchName) + '</option>';
                });
                $('#diBranch').html(opts).prop('hidden', false);
            }
            loadTa();               // fills the badge on the Take Away button
        }).fail(function () { loadTa(); });
    }

    // =========================================================================
    // wiring
    // =========================================================================
    $(function () {
        // floor
        $('#diFloors').on('click', 'button', function () {
            S.floor = n($(this).data('tt'));
            store('di.floor', S.floor);
            renderFloor();
        });
        $('#diCanvas').on('click', '.di-tbl', function () {
            if (S.arrange) return;
            var t = S.byId[$(this).data('id')];
            if (!t || t._pending) return;
            if (t.Status === 1) openTablePopup(t.TableID); else seatTable(t);
        });
        $('#diCanvas').on('pointerdown', '.di-tbl', onDragStart);
        $(document).on('pointermove', onDragMove).on('pointerup pointercancel', onDragEnd);

        $('#diBranch').on('change', function () { S.branchId = n(this.value); store('di.branch', S.branchId); loadTa(); });

        // Dine-In / Take Away
        $('#diModeDine').on('click', function () { setMode('dine'); });
        $('#diTakeAway').on('click', function () { setMode('ta'); });
        $('#diTaNew').on('click', function () { openOrder({ mode: 'takeaway' }); });
        $('#diTaFilters').on('click', 'button', function () { S.ta.filter = String($(this).data('f')); renderTa(); });
        $('#diTaGrid').on('click', '.di-tac', function () { openTaPopup($(this).data('inv')); });

        $('#diArrange').on('click', function () {
            if (S.arrange) { setArrange(false); loadFloor(); return; }
            closeTablePopup();
            setArrange(true);
        });
        $('#diArrangeCancel').on('click', function () { setArrange(false); loadFloor(); });
        $('#diArrangeSave').on('click', saveLayout);

        // guest popup
        var $g = $('#diGuest');
        $g.on('click', '.js-cancel', guestCancel);
        $g.on('click', '.js-ok', guestOk);
        $g.on('click', '.js-inc', function () { $('#diGPersons').val(Math.min(999, guestPersons() + 1)); guestCap(); });
        $g.on('click', '.js-dec', function () { $('#diGPersons').val(Math.max(1, guestPersons() - 1)); guestCap(); });
        $('#diGPersons').on('input', function () { this.value = this.value.replace(/\D/g, '').slice(0, 3); guestCap(); });
        $('#diGMobile').on('input', function () { this.value = this.value.replace(/[^\d ]/g, ''); });
        $g.on('keydown', 'input', function (e) { if (e.key === 'Enter') { e.preventDefault(); guestOk(); } });

        // order popup
        var $o = $('#diOrder');
        $o.on('click', '.js-close', function () { closeOrder(false); });
        $o.on('click', '.js-cats button', function () {
            S.order.cat = n($(this).data('cat')); S.order.q = '';
            $o.find('.js-search').val('');
            renderOrder();
            $o.find('.di-items').scrollTop(0);
        });
        $o.on('click', '.di-item', function () { addItem(n($(this).data('item'))); });
        $o.on('click', '.di-cline .js-inc', function () {
            var k = String($(this).closest('.di-cline').data('key')), i = cartLine(k);
            if (i >= 0) setLineQty(k, S.order.cart[i].qty + 1);
        });
        $o.on('click', '.di-cline .js-dec', function () {
            var k = String($(this).closest('.di-cline').data('key')), i = cartLine(k);
            if (i >= 0) setLineQty(k, S.order.cart[i].qty - 1);
        });
        $o.on('click', '.di-cline .js-ta', function () { toggleLineTa(String($(this).closest('.di-cline').data('key'))); });
        $o.on('click', '.js-ta-all', toggleAllTa);
        $o.on('input', '.js-ta-mobile', function () { this.value = this.value.replace(/[^\d ]/g, ''); });
        $o.on('click', '.js-clear', function () { if (S.order) { S.order.cart = []; renderOrder(); } });
        $o.on('input', '.js-search', function () { if (S.order) { S.order.q = $.trim(this.value); renderOrder(); } });
        $o.on('click', '.js-send', sendOrder);

        // table popup
        var $p = $('#diTable');
        $p.on('click', '.js-close', closeTablePopup);
        $p.on('click', '.di-bills button', function () { S.tp.bill = n($(this).data('bill')); S.tp.sel = {}; renderTablePopup(); });
        $p.on('click', '.js-del-line', function () { sheetDeleteLine($(this).data('order')); });
        $p.on('click', '.js-ta-line', function () { toggleLineTakeAway($(this)); });
        $p.on('click', '.js-a-add', function () {
            if (S.tp.ta) {
                var tb = currentBill();
                openOrder({ mode: 'add', table: null, invoiceNo: tb.InvoiceNo, billLabel: '#' + (tb.RunningOrder || tb.InvoiceNo) });
                hide('diTable');
                return;
            }
            var b = currentBill(), t = S.byId[S.tp.tableId] || S.tp.data.Table;
            var idx = S.tp.bill;
            openOrder({ mode: 'add', table: $.extend({}, t, S.tp.data.Table), invoiceNo: b.InvoiceNo,
                        billLabel: (S.tp.data.Bills.length > 1 ? 'Bill ' + (idx + 1) : 'bill') + ' #' + (b.RunningOrder || b.InvoiceNo) });
            hide('diTable');
        });
        $p.on('click', '.js-a-order', function () {
            var t = $.extend({}, S.byId[S.tp.tableId], S.tp.data.Table);
            closeTablePopup();
            openOrder({ mode: 'new', table: t });
        });
        $p.on('click', '.js-a-print', function (e) { e.stopPropagation(); togglePrintMenu($(this)); });
        $p.on('click', '.di-menu button', function () {
            var no = currentBill().InvoiceNo, doc = $(this).data('doc');
            // A printer set up in Printer Settings prints silently; with none, the browser print window opens as before.
            if (window.PosPrint && doc === 'Thermal') PosPrint.invoice(no, { fallback: function () { printDoc(no, doc); } });
            else if (window.PosPrint && doc === 'Kitchen') PosPrint.order(no, { reprint: true, fallback: function () { printDoc(no, doc); } });
            else printDoc(no, doc);
            $(this).closest('.di-menu').remove();
            setTimeout(reloadTablePopup, 1500);
        });
        $p.on('click', '.js-a-pay', sheetPay);
        $p.on('click', '.js-a-transfer', sheetTransfer);
        $p.on('click', '.js-a-split', startSplit);
        $p.on('click', '.di-line.is-pick', function (e) { if (!$(e.target).closest('button').length) toggleSel($(this)); });
        $p.on('keydown', '.di-line.is-pick', function (e) {
            if ((e.key === ' ' || e.key === 'Enter') && e.target === this) { e.preventDefault(); toggleSel($(this)); }
        });
        $p.on('click', '.js-a-delbill', sheetDeleteBill);
        $p.on('click', '.js-a-free', freeTable);
        $(document).on('click', function (e) { if (!$(e.target).closest('.di-menu, .js-a-print').length) $('.di-menu').remove(); });

        // sheet
        $('#diSheet').on('click', '.js-close', closeSheet);

        // click on the dimmed backdrop closes the read-only popups only
        $('#diTable').on('click', function (e) { if (e.target === this) closeTablePopup(); });
        $('#diSheet').on('click', function (e) { if (e.target === this) closeSheet(); });

        $(document).on('keydown', function (e) {
            if (e.key !== 'Escape') return;
            if (isOpen('diSheet')) closeSheet();
            else if (isOpen('diOrder')) closeOrder(false);
            else if (isOpen('diGuest')) guestCancel();
            else if (isOpen('diTable')) closeTablePopup();
            else if (S.arrange) { setArrange(false); loadFloor(); }
        });

        var rT;
        $(window).on('resize', function () {
            clearTimeout(rT);
            rT = setTimeout(function () { if (S.mode === 'ta') return; if (!S.arrange) renderFloor(); else sizeCanvas(); }, 150);
        });

        // go
        initBranch();
        loadFloor();
        ensureMenu();             // warm the menu so the first order popup opens instantly
        startHub();

        // safety net: SignalR is the fast path, this catches anything missed
        var tick = 0;
        setInterval(function () {
            tick++;
            if (document.hidden || S.arrange) return;
            if (S.live !== 'on' || tick % 2 === 0) { loadFloor(); loadTa(); }   // 15 s without SignalR, 30 s with it
        }, 15000);
        $(document).on('visibilitychange', function () { if (!document.hidden) { loadFloor(); loadTa(); } });
    });

})(jQuery, window, document);
