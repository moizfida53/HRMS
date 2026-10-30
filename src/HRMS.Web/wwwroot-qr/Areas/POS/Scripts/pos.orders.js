/*==============================================================================
  Areas/POS/Scripts/pos.orders.js   (v2)

  Order List: facet panel + server-side grid + delta polling + details drawer.

  Design points that matter on a counter machine:

    * Every filter, sort and page is resolved by SQL Server. The browser only
      ever holds one page of rows.

    * Facet counts come from a separate proc that excludes each group's own
      filter, so ticking a brand never hides the other brands.

    * Search is debounced. Without it, typing an 8-digit mobile fires eight
      queries and the LAST ONE TO RETURN wins - not the last one sent - which
      shows results for a prefix of what was typed.

    * Delta polling patches changed rows in place. A poll that finds nothing
      costs one round trip and no redraw, and it pauses on hidden tabs.
==============================================================================*/
(function () {
    'use strict';

    var lookups = null, table = null;
    var rowVer = null, pollTimer = null, pollWorker = null;
    var sel = { brand: {}, branch: {}, itype: {}, status: {} };
    var facetCache = null;

    var POLL_MS = 7000, DEBOUNCE = 300;

    // ------------------------------------------------------------------ utils
    function esc(s) {
        if (s === null || s === undefined) return '';
        return String(s).replace(/[&<>"']/g, function (c) {
            return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c];
        });
    }
    function money(v) { var n = parseFloat(v); return isNaN(n) ? '' : n.toFixed(3); }

    // One badge colour per Invoice Type, so the channel a row came from (QR
    // Menu, Call Centre, Walk-in, ...) reads at a glance off the Invoice
    // Type cell alone - see its column render() below, not the row as a
    // whole. tblInvoiceType_Master is an open list the branch edits, not a
    // fixed enum, so this hashes the ID to a hue instead of a hard-coded map
    // that would miss whatever types this deployment actually has. The
    // golden-angle step keeps adjacent IDs from landing on similar hues the
    // way a plain id*N step tends to.
    var itypeColorCache = {};
    function itypeColor(id) {
        if (id === null || id === undefined || id === '') return '';
        var key = String(id);
        if (itypeColorCache[key] === undefined) {
            var n = parseInt(id, 10);
            var hue = isNaN(n) ? 0 : (n * 137.508) % 360;   // golden angle
            itypeColorCache[key] = 'hsl(' + Math.round(hue) + ', 62%, 88%)';
        }
        return itypeColorCache[key];
    }

    // ASP.NET serialises DateTime as /Date(1234567890000)/
    function parseDate(v) {
        if (!v) return null;
        var m = /\/Date\((-?\d+)\)\//.exec(v);
        if (m) return new Date(parseInt(m[1], 10));
        var d = new Date(v);
        return isNaN(d.getTime()) ? null : d;
    }
    function fmtDT(v) {
        var d = parseDate(v);
        if (!d) return '';
        var MM = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
        var h = d.getHours(), ap = h >= 12 ? 'PM' : 'AM';
        h = h % 12; if (h === 0) h = 12;
        return ('0' + d.getDate()).slice(-2) + '-' + MM[d.getMonth()] + '-' + String(d.getFullYear()).slice(-2)
             + '<br><span class="pos-muted" style="font-size:11.5px;">'
             + ('0' + h).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2) + ' ' + ap + '</span>';
    }
    function debounce(fn, ms) {
        var t;
        return function () {
            var self = this, a = arguments;
            clearTimeout(t);
            t = setTimeout(function () { fn.apply(self, a); }, ms);
        };
    }
    function keys(o) { return Object.keys(o).filter(function (k) { return o[k]; }); }
    function csv(o)  { return keys(o).join(','); }

    // ---------------------------------------------------------------- filters
    function currentFilters() {
        var mode = $('#fDateMode').val() || 'Today';
        return {
            BrandIDs:       csv(sel.brand),
            BranchIDs:      csv(sel.branch),
            InvoiceTypeIDs: csv(sel.itype),
            StatusIDs:      csv(sel.status),
            DateMode:       mode,
            FromDate:       mode === 'Range' ? ($('#fFrom').val() || null) : null,
            ToDate:         mode === 'Range' ? ($('#fTo').val()   || null) : null,
            Search:         $('#fSearch').val() || '',
            PaymentStatus:  $('#fPaymentStatus').val() || '',
            IncludeDeleted: false,
            // Only orders whose DeliveryDate lands on a later calendar day
            // than InvoiceDate - a customer who booked ahead, not just one
            // whose delivery slot is later the same day.
            ScheduledOnly:  $('#fScheduledOnly').is(':checked')
        };
    }

    // ----------------------------------------------------------------- facets
    function loadFacets() {
        $.ajax({
            type: 'POST', url: POS.urls.facets,
            contentType: 'application/json; charset=utf-8',
            data: JSON.stringify(currentFilters())
        }).done(function (res) {
            if (!res || res.Message !== 'Success') {
                facetError('Could not load filters.');
                return;
            }
            facetCache = res;

            // A filter with one option cannot narrow anything - it only costs a
            // click and a block of screen. Hide the group instead of showing a
            // single permanently-redundant checkbox.
            var multiBrand = (res.Brands || []).length > 1;
            $('#facetBrandBox').toggle(multiBrand);
            if (!multiBrand) sel.brand = {};      // never filter by a hidden group

            if (multiBrand) {
                renderFacet('#facetBrands', res.Brands, 'brand', 'BrandID', 'BrandName');
            }
            renderFacet('#facetBranches', res.Branches,     'branch', 'BranchID',      'BranchName');
            renderFacet('#facetTypes',    res.InvoiceTypes, 'itype',  'InvoiceTypeID', 'InvoiceTypeName');

            // Statuses come from lookups (names, colours, order) but the counts
            // come from here, so the panel is redrawn once both are in hand.
            renderStatusFacet(lookups ? lookups.Statuses : []);
            renderChips();
        }).fail(function (xhr) {
            facetError('Could not load filters (' + xhr.status + ').');
        });
    }

    function facetError(msg) {
        $('#facetBrands, #facetBranches, #facetTypes').html(
            '<div class="text-danger" style="padding:8px 12px;font-size:12.5px;">' + esc(msg) + '</div>');
    }

    function facetError(msg) {
        $('#facetBrands, #facetBranches, #facetTypes').html(
            '<div class="text-danger" style="padding:8px 12px;font-size:12.5px;">' + esc(msg) + '</div>');
    }

    function renderFacet(target, rows, group, idKey, nameKey) {
        var $t = $(target).empty();

        if (!rows || !rows.length) {
            $t.append('<div class="pos-muted" style="padding:8px 12px;font-size:12.5px;">'
                    + 'None configured</div>');
            return;
        }

        $.each(rows, function (_, r) {
            var id = String(r[idKey]);
            var n  = parseInt(r.Cnt, 10) || 0;
            var $l = $('<label>')
                .append($('<input type="checkbox">')
                    .attr('data-group', group).attr('data-id', id)
                    .prop('checked', !!sel[group][id]))
                .append($('<span class="nm">').text(r[nameKey] || ('#' + id)))
                .append($('<span class="cnt">').addClass(n === 0 ? 'zero' : '').text(n));
            $t.append($l);
        });
    }

    // ------------------------------------------------------------ status icons
    //
    // The status used to be a coloured pill: the same rounded rectangle every
    // time, told apart only by hue. At a glance on a busy counter screen that
    // is one shape repeated seven times, and hue alone fails for the roughly
    // 1 in 12 men with a colour vision deficiency.
    //
    // Each status now draws its own glyph. The colour from tblOrderStatus is
    // kept, but as the stroke colour rather than a fill - it reinforces the
    // shape instead of carrying the whole meaning.
    //
    // Icons are matched on WORDS in the status name, not on the exact string
    // or the ID, because both get edited: names are renamed in the DB and IDs
    // differ between installs. "Order Received", "Received", "New Order" all
    // land on the same clipboard.
    var STATUS_ICONS = {
        received:  '<path d="M9 5h-2a2 2 0 0 0 -2 2v12a2 2 0 0 0 2 2h10a2 2 0 0 0 2 -2v-12a2 2 0 0 0 -2 -2h-2" />'
                 + '<rect x="9" y="3" width="6" height="4" rx="2" />'
                 + '<path d="M9 14l2 2l4 -4" />',

        kitchen:   '<path d="M12 3c1.918 0 3.52 1.35 3.91 3.151a4 4 0 0 1 2.09 7.723v7.126h-12v-7.126a4 4 0 1 1 2.092 -7.723a4 4 0 0 1 3.908 -3.151z" />'
                 + '<path d="M6.161 17.009l11.839 -.009" />',

        ready:     '<path d="M12 3l8 4.5v9l-8 4.5l-8 -4.5v-9z" />'
                 + '<path d="M12 12l8 -4.5" />'
                 + '<path d="M12 12v9" />'
                 + '<path d="M12 12l-8 -4.5" />',

        dispatched:'<circle cx="7" cy="17" r="2" />'
                 + '<circle cx="17" cy="17" r="2" />'
                 + '<path d="M5 17h-2v-11a1 1 0 0 1 1 -1h9v12m-4 0h6m4 0h2v-6h-8m0 -5h5l3 5" />',

        driver:    '<circle cx="5" cy="17" r="2" />'
                 + '<circle cx="18" cy="17" r="2" />'
                 + '<path d="M7 17h9" />'
                 + '<path d="M5 17l4 -6h4l3 6" />'
                 + '<path d="M13 11l-1.5 -4h-1.5" />'
                 + '<path d="M16 7h3" />',

        delivered: '<path d="M12 3l8 4.5v4.5" />'
                 + '<path d="M12 12l8 -4.5" />'
                 + '<path d="M12 21l-8 -4.5v-9l8 -4.5" />'
                 + '<path d="M12 12v4" />'
                 + '<path d="M15 19l2 2l4 -4" />',

        deleted:   '<path d="M4 7h16" />'
                 + '<path d="M10 11v6" />'
                 + '<path d="M14 11v6" />'
                 + '<path d="M5 7l1 12a2 2 0 0 0 2 2h8a2 2 0 0 0 2 -2l1 -12" />'
                 + '<path d="M9 7v-3h6v3" />',

        // Anything unrecognised. A dot is deliberately dull: a new status
        // should look unstyled rather than borrow another status's meaning.
        fallback:  '<circle cx="12" cy="12" r="8" />'
    };

    // Word -> icon. Order matters: the first term found in the name wins, so
    // "Order Ready" is checked for "ready" before the generic "order".
    var STATUS_WORDS = [
        ['deleted',    'deleted'], ['cancel',   'deleted'],   ['void',    'deleted'],
        ['kitchen',    'kitchen'], ['prepar',   'kitchen'],   ['cook',    'kitchen'],
        ['ready',      'ready'],   ['pack',     'ready'],
        ['dispatch',   'dispatched'], ['out for', 'dispatched'], ['shipped', 'dispatched'],
        ['driver',     'driver'],  ['rider',    'driver'],    ['on the way', 'driver'],
        ['deliver',    'delivered'], ['complete', 'delivered'], ['collected', 'delivered'],
        ['receiv',     'received'], ['new',     'received'],  ['placed',  'received'],
        ['confirm',    'received'], ['accept',  'received']
    ];

    function statusIconKey(name) {
        var n = String(name || '').toLowerCase();
        for (var i = 0; i < STATUS_WORDS.length; i++) {
            if (n.indexOf(STATUS_WORDS[i][0]) !== -1) return STATUS_WORDS[i][1];
        }
        return 'fallback';
    }

    // size is the box in px: 20 in the grid, 22 in the drawer, 26 in the facet
    // panel. The stroke stays at 1.8 on all three - the icons are drawn on a
    // fixed 24-unit viewBox, so the line weight scales with the box.
    function statusIcon(name, color, size) {
        var body = STATUS_ICONS[statusIconKey(name)] || STATUS_ICONS.fallback;
        var s = size || 20;
        return '<svg class="pos-st-ico" xmlns="http://www.w3.org/2000/svg" width="' + s + '" height="' + s + '"'
             + ' viewBox="0 0 24 24" fill="none" stroke="' + esc(color || 'currentColor') + '"'
             + ' stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true">'
             + body + '</svg>';
    }

    // The status as it appears everywhere outside the facet panel: icon plus
    // the name, no filled background.
    function statusBadge(name, color, size) {
        return '<span class="pos-status">' + statusIcon(name, color, size)
             + '<span class="pos-status-tx">' + esc(name || '') + '</span></span>';
    }

    // The list of statuses is fixed (from lookups); the counts beside them are
    // live and arrive with the facet response. The two are rendered together so
    // the panel never flickers between a counted and an uncounted state: if the
    // counts have not arrived yet the badge is simply absent, not zero. Showing
    // 0 for "not known yet" reads as "no orders", which is a different claim.
    function renderStatusFacet(statuses) {
        var $t = $('#facetStatus').empty();
        var counts = (facetCache && facetCache.Statuses) || null;

        $.each(statuses || [], function (_, s) {
            // Every status the database hands back is listed. This used to skip
            // OrderStatusID 0 on the grounds that the seeded "New" status never
            // lands on an invoice - but the IDs are per-install and get renamed,
            // so that rule silently hid a real, in-use status. Whether a status
            // belongs on this panel is now answered by tblOrderStatus.IsActive,
            // which is what sp_POS_GetLookups already filters on.
            var id = String(s.OrderStatusID);

            var $l = $('<label class="st-row">')
                .append($('<input type="checkbox">')
                    .attr('data-group', 'status').attr('data-id', id)
                    .prop('checked', !!sel.status[id]))
                .append($(statusIcon(s.OrderStatusName, s.ColorHex, 26)))
                .append($('<span class="nm">').text(s.OrderStatusName));

            if (counts) {
                var hit = counts.filter(function (c) {
                    return String(c.OrderStatusID) === id;
                })[0];
                var n = hit ? (parseInt(hit.Cnt, 10) || 0) : 0;
                // A zero is greyed rather than hidden: a status that vanished
                // from the panel would look like a configuration problem.
                $l.append($('<span class="cnt">').addClass(n === 0 ? 'zero' : '').text(n));
            }

            $t.append($l);
        });
    }

    function renderChips() {
        var $c = $('#activeChips').empty();
        var groups = [
            ['brand',  'Brands',       facetCache && facetCache.Brands,       'BrandID',       'BrandName'],
            ['branch', 'Branch',       facetCache && facetCache.Branches,     'BranchID',      'BranchName'],
            ['itype',  'Invoice Type', facetCache && facetCache.InvoiceTypes, 'InvoiceTypeID', 'InvoiceTypeName']
        ];
        var any = false;

        $.each(groups, function (_, g) {
            $.each(keys(sel[g[0]]), function (_, id) {
                var name = id;
                if (g[2]) {
                    var hit = g[2].filter(function (r) { return String(r[g[3]]) === id; })[0];
                    if (hit) name = hit[g[4]];
                }
                any = true;
                $c.append($('<span class="chip">')
                    .append(document.createTextNode(g[1] + ': ' + name))
                    .append($('<button aria-label="Remove">&times;</button>')
                        .attr('data-group', g[0]).attr('data-id', id)));
            });
        });

        $.each(keys(sel.status), function (_, id) {
            var s = (lookups && lookups.Statuses || []).filter(function (x) { return String(x.OrderStatusID) === id; })[0];
            any = true;
            $c.append($('<span class="chip">')
                .append(document.createTextNode('Status: ' + (s ? s.OrderStatusName : id)))
                .append($('<button aria-label="Remove">&times;</button>')
                    .attr('data-group', 'status').attr('data-id', id)));
        });

        $c.toggle(any);
    }

    // Distance from the grid card to the bottom of the window, minus room
    // for the pagination/info row DataTables draws below the scroll area and
    // the card's own padding. Measured live rather than a fixed calc(vh-Npx)
    // guess, so it stays correct whether the toolbar sits on one line or
    // wraps to two on a narrow screen.
    function gridScrollHeight() {
        var $card = $('#posOrders').closest('.card');
        var top = $card.length ? $card[0].getBoundingClientRect().top : 260;
        var h = window.innerHeight - top - 70;
        return Math.max(h, 220) + 'px';
    }

    // ------------------------------------------------------------------- grid
    function initGrid() {
        // scrollY turns the grid into its own scroll region - header row
        // pinned, body rows scrolling underneath - instead of a tall table
        // growing the whole page. scrollCollapse lets it shrink back down
        // when a filtered page has fewer rows than would fill the space, so
        // an empty gap does not open up under a short result set.
        //
        // gridScrollHeight() measures the real distance from the grid to the
        // bottom of the window at draw time, so it stays correct if the
        // toolbar/filters row wraps to a second line - a fixed calc(vh - Npx)
        // guess would not.
        table = $('#posOrders').DataTable({
            serverSide: true,
            processing: true,
            searching: false,               // our own debounced box drives it
            lengthChange: true,
            pageLength: 50,
            lengthMenu: [25, 50, 100, 200],
            order: [[5, 'desc']],
            deferRender: true,              // build DOM only for visible rows
            scrollY: gridScrollHeight(),
            scrollCollapse: true,
            ajax: {
                url: POS.urls.list,
                type: 'POST',
                contentType: 'application/json; charset=utf-8',
                data: function (d) {
                    var f = currentFilters();
                    f.Draw = d.draw; f.Start = d.start; f.Length = d.length;
                    var col = d.order && d.order.length ? d.columns[d.order[0].column].data : 'InvoiceDate';
                    f.SortCol = col;
                    f.SortDir = d.order && d.order.length ? d.order[0].dir : 'desc';
                    return JSON.stringify(f);
                },
                dataSrc: function (json) { syncUrl(); return json.data || []; }
            },
            columns: [
                {
                    data: 'InvoiceNo',
                    render: function (v, t, row) {
                        // Sorting and filtering still work on InvoiceNo - the
                        // column's data is unchanged, only what is drawn.
                        return '<strong>' + esc(invNo(row)) + '</strong>'
                             + (row.TrackingCode ? '<br><span class="pos-muted" style="font-size:11.5px;">'
                                                   + esc(row.TrackingCode) + '</span>' : '');
                    }
                },
                {
                    data: 'InvoiceTypeName',
                    render: function (v, t, row) {
                        var c = itypeColor(row.InvoiceTypeID);
                        return c
                            ? '<span class="itype-badge" style="background:' + c + ';">' + esc(v) + '</span>'
                            : esc(v);
                    }
                },
                { data: 'CustomerName',    render: function (v) { return esc(v || '-'); } },
                {
                    data: 'Mobile', render: function (v) {
                        if (!v) return '';
                        var digits = String(v).replace(/[^0-9]/g, '');
                        return esc(v) + ' <a href="https://wa.me/' + encodeURIComponent(digits) +
                               '" target="_blank" rel="noopener" title="WhatsApp" ' +
                               'onclick="event.stopPropagation()">&#128172;</a>';
                    }
                },
                { data: 'AreaName',     render: function (v) { return esc(v || '-'); } },
                { data: 'DeliveryDate', render: function (v) { return fmtDT(v); } },
                {
                    data: 'Amount', className: 'text-right',
                    render: function (v, t, row) {
                        var s = '<strong>' + money(v) + '</strong>';
                        if (row.PaymentStatus === 'Unpaid')  s += '<br><span class="text-danger" style="font-size:11px;">Unpaid</span>';
                        if (row.PaymentStatus === 'Partial') s += '<br><span class="text-warning" style="font-size:11px;">Partial</span>';
                        return s;
                    }
                },
                { data: 'DriverName', render: function (v) { return esc(v || '-'); } },
                { data: 'BrandName',  render: function (v) { return esc(v); } },
                { data: 'BranchName', render: function (v) { return esc(v); } },
                {
                    data: null, orderable: false, className: 'text-nowrap',
                    render: function (row) {
                        var status = statusBadge(row.OrderStatusName, row.StatusColor, 20);

                        // No view button: clicking anywhere on the row already
                        // opens the details drawer, so the eye was a second way
                        // to do the same thing taking up space next to Pay.

                        // Pay shows only where it can actually be used: an order
                        // that still owes money and is not closed. It is no
                        // longer limited to cash-on-delivery - the dialog offers
                        // every payment type, so any unpaid order can be settled
                        // at the counter.
                        var owes  = (parseFloat(row.Amount) || 0)
                                  - (parseFloat(row.AmountPaid) || 0) > 0.0005;
                        var canPay = owes && !row.IsTerminal
                                     && POS.perms && POS.perms.takePayment;
                        var pay = '<button class="act-btn" data-act="pay" title="'
                                + (canPay ? 'Take payment' : 'Nothing outstanding on this order')
                                + '"' + (canPay ? '' : ' disabled') + '>&#128179;</button>';

                        return '<div style="line-height:1.9">' + status + '<br>' + pay + '</div>';
                    }
                }
            ],
            createdRow: function (tr, data) { $(tr).attr('data-inv', data.InvoiceNo); }
        });
    }

    function reload(keepPage) { if (table) table.ajax.reload(null, !keepPage); }

    function refreshAll(keepPage) { reload(keepPage); loadFacets(); }

    // The active filter is mirrored into the URL, so one person can send
    // another a link to exactly the view they are looking at.
    function syncUrl() {
        var f = currentFilters();
        var q = $.param({ br: f.BrandIDs, b: f.BranchIDs, it: f.InvoiceTypeIDs,
                          s: f.StatusIDs, d: f.DateMode, q: f.Search, p: f.PaymentStatus,
                          sc: f.ScheduledOnly ? '1' : '' });
        if (window.history && history.replaceState) {
            history.replaceState(null, '', location.pathname + '?' + q);
        }
    }

    function restoreFromUrl() {
        var p = new URLSearchParams(location.search);
        function fill(key, group) {
            var v = p.get(key);
            if (!v) return;
            $.each(v.split(','), function (_, id) { if (id) sel[group][id] = true; });
        }
        fill('br', 'brand'); fill('b', 'branch'); fill('it', 'itype'); fill('s', 'status');
        if (p.get('d')) { $('#fDateMode').val(p.get('d')); $('#fRangeWrap').toggle(p.get('d') === 'Range'); }
        if (p.get('q')) $('#fSearch').val(p.get('q'));
        if (p.get('p')) $('#fPaymentStatus').val(p.get('p'));
        if (p.get('sc') === '1') {
            $('#fScheduledOnly').prop('checked', true);
            $('#fScheduledWrap').addClass('on');
        }
    }

    // -------------------------------------------------------------- polling
    function poll() {
        $.ajax({ url: POS.urls.changes, type: 'POST',
                 data: { sinceRowVer: rowVer, branchIDs: csv(sel.branch) } })
        .done(function (res) {
            if (!res || res.Message !== 'Success') { setLive(false); return; }
            setLive(true);

            var first = (rowVer === null);
            rowVer = res.RowVer || rowVer;
            if (first) return;          // first poll only sets the watermark

            var changes = res.Changed || [];
            if (!changes.length) return;

            // pos.alerts.js owns the sound and the toast stack; it keeps its own
            // per-invoice list so a status change never re-sounds an old order.
            if (window.POSAlerts) { POSAlerts.notify(changes); }
            else if (changes.some(function (c) { return c.IsNewOrder; })) { beep(); }

            // Anything not on the current page means this page is stale.
            var needReload = changes.some(function (c) {
                return $('#posOrders tbody tr[data-inv="' + c.InvoiceNo + '"]').length === 0;
            });
            if (needReload) { refreshAll(true); return; }

            changes.forEach(function (c) {
                var row = table.row($('#posOrders tbody tr[data-inv="' + c.InvoiceNo + '"]'));
                var d = row.data();
                if (!d) return;
                d.OrderStatusID   = c.OrderStatusID;
                d.OrderStatusName = c.OrderStatusName;
                d.StatusColor     = c.StatusColor;
                d.Amount          = c.NetPayable;
                row.data(d);
            });
            table.draw(false);
            loadFacets();
        })
        .fail(function () { setLive(false); });
    }

    function setLive(ok) {
        // colours come from the layout (#posLiveDot.is-live / .is-down)
        $('#posLiveDot').toggleClass('is-live', !!ok).toggleClass('is-down', !ok)
                        .attr('title', ok ? 'Live' : 'Connection problem')
                        .html('&#9679; ' + (ok ? 'live' : 'offline'));
    }

    function beep() {
        try {
            // WebAudio: no asset to ship and no autoplay-blocked <audio>
            // element, which matters on locked-down counter machines.
            var Ctx = window.AudioContext || window.webkitAudioContext;
            if (!Ctx) return;
            var c = new Ctx(), o = c.createOscillator(), g = c.createGain();
            o.connect(g); g.connect(c.destination);
            o.frequency.value = 880;
            g.gain.setValueAtTime(0.12, c.currentTime);
            g.gain.exponentialRampToValueAtTime(0.001, c.currentTime + 0.35);
            o.start(); o.stop(c.currentTime + 0.35);
        } catch (e) { /* a nicety; never break the grid for it */ }
    }

    function startPolling() {
        if (pollTimer) { clearInterval(pollTimer); pollTimer = null; }

        // The tab must keep polling while it is in the BACKGROUND - a cashier
        // switching to another tab must still hear a new order land. A plain
        // setInterval will not do: browsers clamp background timers to roughly
        // one tick a minute, so an order could sit unannounced for that long.
        // A Web Worker has its own timer that is not clamped that way.
        try {
            var src = 'var t=null;onmessage=function(e){' +
                      'if(e.data&&e.data.stop){clearInterval(t);return;}' +
                      'clearInterval(t);t=setInterval(function(){postMessage(1);},e.data.ms);};';
            var w = new Worker(URL.createObjectURL(new Blob([src], { type: 'text/javascript' })));
            w.onmessage = function () { poll(); };
            w.postMessage({ ms: POLL_MS });
            pollWorker = w;
        } catch (e) {
            // No Worker (or a CSP that blocks blob: workers): fall back to a
            // timer. It still runs in the background, just more slowly.
            pollTimer = setInterval(poll, POLL_MS);
        }

        // Returning to the tab should feel instant rather than waiting out the
        // remainder of a tick.
        $(document).on('visibilitychange.posPoll', function () {
            if (!document.hidden) poll();
        });

        poll();
    }

    // --------------------------------------------------------------- drawer
    // ------------------------------------------------------- details modal
    var openInvoice = null;

    function openDrawer(invoiceNo) {          // name kept: pos.context.js calls it
        openInvoice = invoiceNo;

        $('#pmScrim').addClass('open');
        $('#posModal').addClass('open').attr('aria-hidden', 'false');
        $('#pmSummary').empty();
        $('#pmCustomer').empty();
        $('#pmStatus').empty();
        $('#pmBody').html('<div class="pos-muted">Loading&hellip;</div>');
        $('#pmFoot').hide();

        $.getJSON(POS.urls.details, { id: invoiceNo })
            .done(function (res) {
                if (!res || res.Message !== 'Success') {
                    $('#pmBody').html('<div class="text-danger">Could not load this order.</div>');
                    return;
                }
                renderDrawer(res);
            })
            .fail(function (xhr) {
                $('#pmBody').html('<div class="text-danger">Could not load this order ('
                                + xhr.status + ').</div>');
            });
    }

    function closeDrawer() {
        openInvoice = null;
        $('#posModal').removeClass('open').attr('aria-hidden', 'true');
        $('#pmScrim').removeClass('open');
    }

    function renderDrawer(res) {
        var h = res.Header || {};
        openHeader = h;

        $('#pmTitle').text('Order Details');

        // Customer and mobile now live in the header, separated by a dash.
        var name   = h.CustomerName || '-';
        var mobile = h.Mobile
                   ? '<a href="tel:' + esc(h.Mobile) + '">' + esc(h.Mobile) + '</a>'
                   : '-';
        $('#pmCustomer').html(esc(name) + ' <span class="pos-muted">&ndash;</span> ' + mobile);

        $('#pmStatus').html(statusBadge(h.OrderStatusName, h.StatusColor, 22));

        // ---- summary strip ----
        var sum = ''
          + cell('Invoice No',     esc(invNo(h)))
          + cell('Bill Amount',    money(h.BillAmount))
          + cell('Delivery Charge', money(h.DeliveryCharges))
          + cell('Total Discount', money(h.Discount), 'disc')
          + cell('Final Amount',   money(h.NetPayable), 'final');
        $('#pmSummary').html(sum);

        // ---- line items ----
        var rows = (res.Lines || []).filter(function (l) { return !l.Deleted; });

        // Items can be removed while the order is still being taken and
        // acknowledged. Past that the kitchen has made them, so the line stops
        // being editable - and the button stops being shown rather than being
        // shown and refused.
        var canDelete = !h.IsTerminal
                     && parseInt(h.OrderStatusID, 10) <= LINE_EDIT_MAX_STATUS;

        var html = '<table class="table table-sm mb-0"><thead><tr>'
                 + '<th>Item Name</th><th>Price</th><th>Qty</th><th>Discount</th>'
                 + '<th>Total Price</th><th>Order Time</th><th>Comments</th>'
                 + (canDelete ? '<th></th>' : '')
                 + '</tr></thead><tbody>';

        if (!rows.length) {
            html += '<tr><td colspan="' + (canDelete ? 8 : 7) + '" class="pos-muted">'
                 +  'No items on this order.</td></tr>';
        }

        $.each(rows, function (_, l) {
            // Choices and extras are indented under their parent item rather
            // than listed as peers, so the modifiers read as part of the dish.
            var isSub = l.LineType > 1;
            html += '<tr' + (isSub ? ' class="sub"' : '') + '>'
                 +  '<td' + (isSub ? ' style="padding-left:26px;"' : '') + '>'
                 +      (isSub ? '&#8627; ' : '') + esc(l.ItemName) + '</td>'
                 +  '<td>' + money(l.Price) + '</td>'
                 +  '<td>' + esc(l.Quantity) + '</td>'
                 +  '<td>' + money(l.Discount) + '</td>'
                 +  '<td>' + money(l.TotalAmount) + '</td>'
                 +  '<td>' + timeOnly(l.OrderTime) + '</td>'
                 +  '<td>' + esc(l.Comments || l.Extra || '') + '</td>';

            if (canDelete) {
                // Extras and choices have no button of their own: they are
                // removed with the item they belong to, and offering to delete
                // the cheese but not the burger invites half-priced nonsense.
                html += '<td class="text-right">'
                     +  (isSub ? ''
                               : '<button class="line-del" data-order="' + esc(l.OrderID) + '"'
                                 + ' data-name="' + esc(l.ItemName) + '"'
                                 + ' title="Delete this item">&#128465;</button>')
                     +  '</td>';
            }

            html += '</tr>';
        });
        html += '</tbody></table>';
        html += '<div class="pm-count">Showing 1 to ' + rows.length + ' of ' + rows.length + ' entries</div>';

        // Customer, mobile and status are in the header now; invoice type and
        // paid-amount were dropped. Only build this block if something is left
        // to put in it - an empty <dl> would leave a stray gap.
        // Address was removed from this dialog; it still prints on the
        // receipt, where the driver actually needs it.
        var extra = '';
        if (h.DriverName) extra += kv('Driver', esc(h.DriverName));

        if (extra) {
            html += '<dl class="pos-kv mt-3" style="grid-template-columns:150px 1fr;">'
                 +  extra + '</dl>';
        }

        $('#pmBody').html(html);

        // ---- footer buttons ----
        // Pay is enabled only where it can actually be used: a cash-on-delivery
        // order that still owes money and is not already closed.
        var owes    = (h.NetPayable || 0) - (h.AmountPaid || 0) > 0.001;
        var canPay  = h.IsCOD && owes && !h.IsTerminal && POS.perms && POS.perms.takePayment;
        var canCncl = !h.IsTerminal && POS.perms && POS.perms.cancel;

        // IDs, not names, throughout below: OrderStatusName is whatever the
        // branch renamed it to (see tblPOS_OrderStatus_Master) - the ID is
        // the one thing guaranteed to stay put.
        var curStatusID = parseInt(h.OrderStatusID, 10);

        // KITCHEN_STATUS (2, "Preparing") is when the kitchen actually starts
        // on the order - not LINE_EDIT_MAX_STATUS below, which deliberately
        // stays open through the start of that status so a line can still be
        // pulled a moment after prep begins. Modify is the whole order, not
        // one line, so it locks the instant the order reaches the kitchen.
        var KITCHEN_STATUS = 2;
        var canMod = !h.IsTerminal && curStatusID < KITCHEN_STATUS;

        // Once a driver is actually en route (5, "On the Way") there is no
        // branch left to hand the order back to for collection - and
        // IsTerminal already covers Delivered/Cancelled/Refunded (6/7/8).
        //
        // This one is hidden outright rather than shown-disabled like the
        // buttons above: past this point "convert to pickup" is not a
        // choice that will ever become available again on this order, so
        // there is nothing to signal by leaving it visible.
        var ON_THE_WAY_STATUS = 5;
        var pastPickupWindow = h.IsTerminal || curStatusID === ON_THE_WAY_STATUS;
        var canPick = h.OrderType === 2 && !pastPickupWindow;

        setBtn('#pmPay',    canPay,  canPay  ? 'Take payment' : 'Not a pending cash-on-delivery order');
        setBtn('#pmCancel', canCncl, canCncl ? 'Cancel this order' : 'Not available for this order or role');
        setBtn('#pmModify', canMod,  canMod  ? 'Modify the order' : 'The kitchen already has this order');
        setBtn('#pmPickup', canPick, canPick ? 'Convert to pickup' : 'Only a delivery order can become a pickup');
        $('#pmPickup').toggle(!pastPickupWindow);
        setBtn('#pmPrint',  true,    'Print');

        updateBranchButton(h);
        updateStatusButton(h);

        $('#pmFoot').show();
    }

    // Opens the printable document in its own window, which then calls
    // window.print() itself. A popup is used rather than a hidden iframe so
    // the operator can pick a different printer, reprint, or switch to A4
    // without going back to the grid.
    //
    // The details drawer closes when the operator is done with the print - the
    // order has been dealt with, and leaving the drawer sitting open behind the
    // print window means the next thing they click is the wrong order. "Done"
    // is whichever comes first: the browser's print dialog being dismissed (the
    // popup posts back through POS.onPrintClosed) or the popup itself closing.
    function printOrder(invoiceNo, doc) {
        if (!invoiceNo) return;
        var url = POS.urls.print + '?id=' + encodeURIComponent(invoiceNo)
                + '&doc=' + encodeURIComponent(doc || 'Thermal');
        var w = window.open(url, 'posPrint_' + invoiceNo,
                            'width=420,height=760,menubar=no,toolbar=no');
        if (!w) {
            alert('The print window was blocked.\n\n'
                + 'Allow pop-ups for this site, then press Print again.');
            return;
        }
        w.focus();

        // Fallback for the popup being closed without printing - there is no
        // event for that, so its closed flag is polled. Cleared after two
        // minutes so a popup left open all shift does not keep a timer alive.
        var waited = 0;
        var poll = setInterval(function () {
            waited += 500;
            if (w.closed) { clearInterval(poll); onPrintFinished(invoiceNo); }
            else if (waited > 120000) { clearInterval(poll); }
        }, 500);

        // The count and, on a first print, the status changed server-side.
        setTimeout(function () { refreshAll(true); }, 1200);
    }

    // Called once per print, from whichever signal arrives first.
    var printFinishedFor = null;
    function onPrintFinished(invoiceNo) {
        // Compared as text: the popup sends a string, the closed-window poll
        // sends the number it was called with, and 123 !== '123'.
        var key = String(invoiceNo);
        if (printFinishedFor === key) return;         // both signals fired
        printFinishedFor = key;
        closeDrawer();
        refreshAll(true);
    }

    // Creates a MyFatoorah payment page and opens it. The window is opened
    // BEFORE the ajax call: a popup opened from an async callback is blocked
    // by every browser, because it is no longer inside the click gesture.
    function payWithMyFatoorah(invoiceNo) {
        if (!invoiceNo) return;

        var w = window.open('', 'posPay_' + invoiceNo, 'width=480,height=780');
        if (w) { w.document.write('<p style="font:14px sans-serif;padding:24px">Opening payment page&hellip;</p>'); }

        $.ajax({ type: 'POST', url: POS.urls.payLink, data: { invoiceNo: invoiceNo } })
            .done(function (res) {
                if (res && res.Message === 'Success' && res.PaymentUrl) {
                    if (w) { w.location = res.PaymentUrl; w.focus(); }
                    else   { window.location = res.PaymentUrl; }
                    watchPayment(invoiceNo, res.Reference);
                } else {
                    if (w) w.close();
                    alert('Could not start the payment.\n\n' + ((res && res.Detail) || ''));
                }
            })
            .fail(function () {
                if (w) w.close();
                alert('Could not start the payment.');
            });
    }

    // The webhook usually books the payment before the customer is even
    // redirected, so the grid is re-checked for a while rather than waiting for
    // the operator to press refresh.
    function watchPayment(invoiceNo, reference) {
        var tries = 0;
        var t = setInterval(function () {
            if (++tries > 20) { clearInterval(t); return; }   // ~2 minutes
            if (reference) {
                $.ajax({ type: 'POST', url: POS.urls.payRefresh, data: { reference: reference } })
                    .done(function (r) {
                        if (r && r.Outcome === 'Paid') { clearInterval(t); refreshAll(true); }
                    });
            } else {
                refreshAll(true);
            }
        }, 6000);
    }

    // ------------------------------------------------------------ cancelling
    //
    // Cancelling needs a reason and a manager's delete password. Both are
    // checked again in SQL - this is the courtesy layer, not the guard.
    function openCancelDialog() {
        if (!openInvoice) return;

        $('#coInvoice').text(invNo(openHeader) || openInvoice);
        $('#coReason').val('');
        $('#coPassword').val('');
        $('#coError').hide().text('');
        $('#coConfirm').prop('disabled', false).text('Cancel Order');

        $('#coScrim').addClass('open');
        $('#cancelModal').addClass('open').attr('aria-hidden', 'false');
        setTimeout(function () { $('#coReason').focus(); }, 50);
    }

    function closeCancelDialog() {
        $('#cancelModal').removeClass('open').attr('aria-hidden', 'true');
        $('#coScrim').removeClass('open');
        // Not left in the DOM: it is a manager's password.
        $('#coPassword').val('');
    }

    function cancelError(msg) {
        $('#coError').text(msg).show();
        $('#coConfirm').prop('disabled', false).text('Cancel Order');
    }

    function submitCancel() {
        var invoiceNo = openInvoice;
        var reason    = ($('#coReason').val() || '').trim();
        var password  = $('#coPassword').val() || '';

        if (!invoiceNo) { closeCancelDialog(); return; }

        if (!reason)   { cancelError('Type the reason for cancelling this order.'); $('#coReason').focus();   return; }
        if (!password) { cancelError('The manager password is required.');          $('#coPassword').focus(); return; }

        $('#coConfirm').prop('disabled', true).text('Cancelling\u2026');

        $.ajax({
            type: 'POST', url: POS.urls.cancel,
            data: { invoiceNo: invoiceNo, comment: reason, password: password }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                closeCancelDialog();
                closeDrawer();
                refreshAll(true);
            } else {
                // The password box is cleared on a rejection but the reason is
                // kept - retyping a paragraph because a password was mistyped
                // is how people give up and stop recording reasons.
                cancelError((res && res.ErrorMessage) || 'The cancellation could not be recorded.');
                $('#coPassword').val('').focus();
            }
        }).fail(function (xhr) {
            cancelError('The cancellation could not be sent (' + xhr.status + ').');
        });
    }

    // --------------------------------------------------------- take payment
    //
    // Every row in tblInvoicePaymentType gets an amount box - all of them, not
    // just the online ones, because the counter settles in cash far more often
    // than anything else and a method missing from this list cannot be taken at
    // all.
    //
    // The boxes hold what was TENDERED. Change is the excess over the balance
    // due; the figure here is a courtesy so the cashier knows what to hand
    // back, and the server works it out again from the balance at the moment
    // the payment lands. A tab open since before a part-payment would otherwise
    // compute change against a stale balance.
    var payCtx = null;   // { invoiceNo, customer, total, paid, due }

    // The number the customer sees. InvoiceNo remains the key everything is
    // looked up and posted by; this is only ever printed on screen. The
    // fallback matters during the deploy window - a page cached from before
    // POS_32 has rows without the column, and a blank invoice number is worse
    // than the old one.
    function invNo(row) {
        if (!row) return '';
        return row.InvoiceNumShow || row.InvoiceNo || '';
    }

    function money3(n) {
        var v = parseFloat(n);
        return (isNaN(v) ? 0 : v).toFixed(3);
    }

    function openPayDialog(invoiceNo, row) {
        if (!invoiceNo) return;

        var total = parseFloat(row && row.Amount) || 0;
        var paid  = parseFloat(row && row.AmountPaid) || 0;
        var due   = Math.max(0, total - paid);

        payCtx = {
            invoiceNo: invoiceNo,
            invoiceShow: invNo(row),
            customer:  (row && row.CustomerName) || '-',
            total:     total,
            paid:      paid,
            due:       due
        };

        $('#tpInvoice').text(payCtx.invoiceShow || invoiceNo);
        $('#tpCustomer').text(payCtx.customer);
        $('#tpFinal').text(money3(total));

        // The strip shows the bill. Anything already settled is called out
        // separately and only when it exists - the change below is worked out
        // against what is LEFT, and without this line an order that was
        // half-paid earlier would appear to be giving the wrong change.
        $('#tpPaid').text(money3(paid));
        $('#tpDue').text(money3(due));
        $('#tpPaidRow').toggle(paid > 0.0005);

        $('#tpReference').val('');
        $('#tpRefRow').hide();
        $('#tpError').hide().text('');
        $('#tpConfirm').prop('disabled', false).text('Take Payment');

        renderPayTypes();
        updatePayTotals();

        $('#tpScrim').addClass('open');
        $('#payModal').addClass('open').attr('aria-hidden', 'false');

        // After the dialog is on screen, never before: a hidden element has no
        // rendered width, so measuring the labels while display:none returns 0
        // for every one of them.
        sizePayLabels($('#tpTypes'));

        setTimeout(function () { $('#tpTypes input').first().focus().select(); }, 50);
    }

    function closePayDialog() {
        $('#payModal').removeClass('open').attr('aria-hidden', 'true');
        $('#tpScrim').removeClass('open');
        payCtx = null;
    }

    function renderPayTypes() {
        var types = (lookups && lookups.PaymentTypes) || [];
        var $t = $('#tpTypes').empty();

        if (!types.length) {
            $t.append('<div class="pos-muted" style="font-size:12.5px;padding:8px 0;">'
                    + 'No payment types are configured.</div>');
            return;
        }

        $.each(types, function (_, p) {
            var id   = p.PaymentTypeID != null ? p.PaymentTypeID : p.ID;
            var name = p.PaymentTypeName || ('#' + id);

            var $row = $('<div class="tp-row">')
                .attr('data-type', id)
                .attr('data-reqref', p.RequiresReference ? 1 : 0)
                .append($('<span class="nm">').text(name))
                .append($('<input type="number" step="0.001" min="0" class="form-control" placeholder="0.000">'));

            $t.append($row);
        });
    }

    // Every amount box starts at the same x, and the label column is exactly as
    // wide as the longest payment-type name plus a little air.
    //
    // Measured rather than guessed: the names come from the database and can be
    // renamed or translated, and a hard-coded width either clips "Cash on
    // Delivery" or leaves a trough of empty space after "Cash". Measuring is
    // done on the real elements after they are in the DOM, so it accounts for
    // the font actually in use.
    function sizePayLabels($t) {
        var widest = 0;

        $t.find('.tp-row .nm').each(function () {
            // scrollWidth, not width: the element is already ellipsised by CSS,
            // so its rendered width is the truncated width, not the text's.
            var w = this.scrollWidth;
            if (w > widest) widest = w;
        });

        // Bounded so one absurd name cannot squeeze the boxes off the dialog.
        var labelPx = Math.min(Math.max(Math.ceil(widest) + 8, 90), 260);
        $t.css('--tp-label', labelPx + 'px');
    }

    // Sum of the boxes, the change, and whether a reference is needed.
    function updatePayTotals() {
        if (!payCtx) return;

        var entered = 0, needsRef = false;

        $('#tpTypes .tp-row').each(function () {
            var v = parseFloat($(this).find('input').val());
            if (!isNaN(v) && v > 0) {
                entered += v;
                if ($(this).attr('data-reqref') === '1') needsRef = true;
            }
        });

        $('#tpEntered').text(money3(entered));

        var change = entered - payCtx.due;
        var hasChange = change > 0.0005;
        $('#tpChangeRow').toggleClass('on', hasChange);
        $('#tpChange').text(money3(hasChange ? change : 0));

        $('#tpRefRow').toggle(needsRef);
    }

    function submitPayment() {
        if (!payCtx) return;

        var lines = [], entered = 0, needsRef = false;

        $('#tpTypes .tp-row').each(function () {
            var v = parseFloat($(this).find('input').val());
            if (isNaN(v) || v <= 0) return;
            entered += v;
            if ($(this).attr('data-reqref') === '1') needsRef = true;
            lines.push({ TypeID: parseInt($(this).attr('data-type'), 10), Amount: v });
        });

        if (!lines.length) {
            payError('Enter an amount against at least one payment type.');
            return;
        }

        var reference = ($('#tpReference').val() || '').trim();
        if (needsRef && !reference) {
            payError('A reference number is required for the selected payment type.');
            $('#tpReference').focus();
            return;
        }

        $('#tpConfirm').prop('disabled', true).text('Saving…');

        $.ajax({
            type: 'POST', url: POS.urls.takePay,
            data: {
                invoiceNo: payCtx.invoiceNo,
                lines:     JSON.stringify(lines),
                reference: reference
            }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                // Change is stated one last time on the way out: the number the
                // cashier has to act on should not disappear with the dialog.
                var change = parseFloat(res.ChangeGiven) || 0;
                closePayDialog();
                refreshAll(true);
                if (change > 0.0005) {
                    alert('Payment recorded.\n\nChange to give: ' + money3(change));
                }
            } else {
                payError((res && res.ErrorMessage) || 'The payment could not be recorded.');
            }
        }).fail(function (xhr) {
            payError('The payment could not be sent (' + xhr.status + ').');
        });
    }

    function payError(msg) {
        $('#tpError').text(msg).show();
        $('#tpConfirm').prop('disabled', false).text('Take Payment');
    }

    // ------------------------------------------------------- deleting a line
    //
    // Same authorisation as cancelling the order - waste or reuse, a comment,
    // and a manager's delete password - because it is the same act at a
    // smaller scale: something the customer was charged for is being taken
    // off, after the kitchen has already been told to make it.
    //
    // The line is not removed from the order in the database. It is flagged
    // Deleted, its extras and choices go with it, and the invoice is re-totalled
    // from what remains. sp_POS_DeleteOrderLine does all three in one
    // transaction and re-checks every rule.
    var delCtx = null;   // { invoiceNo, orderId, itemName }

    function openDeleteLine(orderId, itemName) {
        if (!openInvoice || !orderId) return;

        delCtx = { invoiceNo: openInvoice, orderId: orderId, itemName: itemName || 'this item' };

        $('#dlItem').text(delCtx.itemName);
        $('#dlInvoice').text(invNo(openHeader) || delCtx.invoiceNo);
        $('input[name="dlDisposition"]').prop('checked', false);
        $('#dlComment').val('');
        $('#dlPassword').val('');
        $('#dlError').hide().text('');
        $('#dlConfirm').prop('disabled', false).text('Delete Item');

        $('#dlScrim').addClass('open');
        $('#delLineModal').addClass('open').attr('aria-hidden', 'false');
        setTimeout(function () { $('#dlComment').focus(); }, 50);
    }

    function closeDeleteLine() {
        $('#delLineModal').removeClass('open').attr('aria-hidden', 'true');
        $('#dlScrim').removeClass('open');
        $('#dlPassword').val('');
        delCtx = null;
    }

    function delLineError(msg) {
        $('#dlError').text(msg).show();
        $('#dlConfirm').prop('disabled', false).text('Delete Item');
    }

    function submitDeleteLine() {
        if (!delCtx) { closeDeleteLine(); return; }

        var disposition = $('input[name="dlDisposition"]:checked').val();
        var comment     = ($('#dlComment').val() || '').trim();
        var password    = $('#dlPassword').val() || '';

        if (!disposition) { delLineError('Choose Waste or Reuse.');                 return; }
        if (!comment)     { delLineError('Type why this item is being removed.');   $('#dlComment').focus();  return; }
        if (!password)    { delLineError('The manager password is required.');      $('#dlPassword').focus(); return; }

        $('#dlConfirm').prop('disabled', true).text('Deleting…');

        $.ajax({
            type: 'POST', url: POS.urls.delLine,
            data: {
                invoiceNo:   delCtx.invoiceNo,
                orderId:     delCtx.orderId,
                disposition: disposition,
                comment:     comment,
                password:    password
            }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                var inv = delCtx.invoiceNo;
                var warn = res.Warning;
                closeDeleteLine();
                // The drawer is reopened rather than closed: the operator is
                // usually removing more than one line, and the totals they need
                // to check have just changed.
                openDrawer(inv);
                refreshAll(true);
                if (warn) alert(warn);
            } else {
                // The comment survives a rejected password, same as the cancel
                // dialog - retyping it is how people stop bothering to explain.
                delLineError((res && res.ErrorMessage) || 'The item could not be deleted.');
                $('#dlPassword').val('').focus();
            }
        }).fail(function (xhr) {
            delLineError('The delete could not be sent (' + xhr.status + ').');
        });
    }

    // ------------------------------------------------- branch / status / pickup
    //
    // Both used to be <select> dropdowns bound to the order that is open, not
    // filled once at page load: what they may offer depends on where this
    // order currently is. They are now footer buttons that open a shared
    // picker dialog (#pickModal) - see openPicker() below - with one option
    // per branch or status rendered as its own .pm-btn. The option lists
    // themselves are still built exactly as before; only where they end up
    // (an array read by the picker, not a <select>'s <option> tags) changed.
    var openHeader = null;   // the header of the order in the drawer
    var branchOptions = [];  // [{ id, label }, ...] - built by updateBranchButton()
    var statusOptions = [];  // [{ id, label, color }, ...] - built by updateStatusButton()

    // Branch can only move while the order is still New (status 0) - placed
    // but with no ticket printed anywhere yet. Once it moves to Received
    // (status 1, set by sp_POS_MarkPrinted when a ticket is actually printed)
    // or later, a kitchen somewhere has already started on it, and moving the
    // order does not move the food. See DBScripts/POS_26_StatusOnPrint.sql,
    // which is what introduced status 0 as the order's starting point.
    var BRANCH_CHANGE_STATUS = 0;

    // The bin disappears one step later, at Received (status 1): past that,
    // items have been made. Cancelling the whole order is still possible,
    // with a reason and a password behind it.
    var LINE_EDIT_MAX_STATUS = 2;

    function updateBranchButton(h) {
        var branches = (lookups && lookups.Branches) || [];
        var allowed  = parseInt(h.OrderStatusID, 10) === BRANCH_CHANGE_STATUS
                       && POS.perms && POS.perms.transfer;

        branchOptions = [];
        $.each(branches, function (_, b) {
            // The branch it is already at is not a change.
            if (parseInt(b.BranchID, 10) === parseInt(h.BranchID, 10)) return;
            branchOptions.push({ id: b.BranchID, label: b.BranchName });
        });

        // Shown but dead rather than hidden: a control that vanishes reads as a
        // fault, one that is greyed reads as "not now", and the title says why.
        setBtn('#pmBranchBtn', allowed,
            allowed ? 'Move this order to another branch'
                    : 'The branch can only be changed before the order has moved past New');
    }

    function updateStatusButton(h) {
        var all = (lookups && lookups.Statuses) || [];
        var cur = parseInt(h.OrderStatusID, 10);
        var allowed = !h.IsTerminal && POS.perms && POS.perms.changeStatus;

        statusOptions = [];
        $.each(all, function (_, st) {
            var id = parseInt(st.OrderStatusID, 10);

            // Forward only. Dragging an order backwards is how a delivered
            // order ends up back in the kitchen queue.
            if (!(id > cur)) return;

            // Cancelling is not a status change here: it needs a reason and a
            // manager's password, which is what the Cancel Order button is for.
            if (id === 6 || id === 7 || id === 8) return;

            // A status that does not apply to this kind of order - pickup vs
            // delivery - would be refused by the server anyway.
            if (h.OrderType === 1 && st.AppliesToPickup === false) return;
            if (h.OrderType !== 1 && st.AppliesToDelivery === false) return;

            statusOptions.push({ id: id, label: st.OrderStatusName, color: st.ColorHex });
        });

        var hasAny = statusOptions.length > 0;
        setBtn('#pmStatusBtn', allowed && hasAny,
            !allowed  ? 'This order is closed, or your role cannot change the status'
          : !hasAny   ? 'There is no status after this one'
                      : 'Move this order forward');
    }

    // ---- the picker dialog shared by both buttons above ----
    var pickerKind = null;   // 'branch' | 'status' - which list is on screen, and which fn a tap calls

    function openPicker(kind) {
        if (!openHeader) return;
        pickerKind = kind;

        var isBranch = kind === 'branch';
        var options  = isBranch ? branchOptions : statusOptions;

        $('#pickTitle').text(isBranch ? 'Change Branch' : 'Update Status');
        $('#pickInvoice').text(invNo(openHeader) || openInvoice);

        var $grid = $('#pickGrid').empty();
        if (!options.length) {
            $grid.append($('<div class="pick-empty">')
                .text(isBranch ? 'No other branch is available.' : 'There is no status after this one.'));
        } else {
            $.each(options, function (_, opt) {
                var $btn = $('<button type="button" class="pm-btn">').attr('data-id', opt.id);
                // A status option carries the same colour dot used everywhere
                // else that status is shown, so the picker still reads as "the
                // order's status" rather than a plain unrelated list.
                if (!isBranch) $btn.append(statusIcon(opt.label, opt.color, 16));
                $btn.append($('<span>').text(opt.label));
                $grid.append($btn);
            });
        }

        $('#pickScrim').addClass('open');
        $('#pickModal').addClass('open').attr('aria-hidden', 'false');
    }

    function closePicker() {
        pickerKind = null;
        $('#pickModal').removeClass('open').attr('aria-hidden', 'true');
        $('#pickScrim').removeClass('open');
    }

    // Picking an option no longer commits it straight away - see openConfirm()
    // below. Status transitions in particular are no longer limited to the
    // next configured step, so this confirm is the one checkpoint before the
    // change is sent, in place of the server's old blanket "not a permitted
    // transition" refusal.
    function choosePickerOption(id) {
        var kind = pickerKind;
        closePicker();
        openConfirm(kind, id);
    }

    function changeBranch(branchId, done) {
        if (!openInvoice || !branchId) { if (done) done(false, 'Nothing to change.'); return; }

        $.ajax({
            type: 'POST', url: POS.urls.chBranch,
            data: { invoiceNo: openInvoice, branchId: branchId, reason: 'Changed from the order list' }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                var inv = openInvoice;
                openDrawer(inv);
                refreshAll(true);
                if (done) done(true);
                if (res.Warning) alert(res.Warning);
            } else {
                if (done) done(false, (res && res.ErrorMessage) || 'The branch could not be changed.');
            }
        }).fail(function (xhr) {
            if (done) done(false, 'The branch change could not be sent (' + xhr.status + ').');
        });
    }

    function changeStatus(statusId, done) {
        if (!openInvoice || !statusId) { if (done) done(false, 'Nothing to change.'); return; }

        $.ajax({
            type: 'POST', url: POS.urls.chStatus,
            data: { invoiceNo: openInvoice, statusId: statusId }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                var inv = openInvoice;
                openDrawer(inv);
                refreshAll(true);
                if (done) done(true);
            } else {
                // The server still has the last word (role checks, a status
                // that stopped applying underneath the picker) - its reason is
                // shown in the confirm dialog rather than a generic failure.
                if (done) done(false, (res && res.ErrorMessage) || 'The status could not be changed.');
            }
        }).fail(function (xhr) {
            if (done) done(false, 'The status change could not be sent (' + xhr.status + ').');
        });
    }

    // ---- confirmation, shared by Update Status and Change Branch ----
    //
    // Same shell as the other dialogs (.co-dialog / .pos-scrim). Status
    // transitions are open now rather than limited to the next configured
    // step, and a branch transfer moves an order's kitchen assignment
    // outright - both are exactly the kind of one-tap action that deserves a
    // "are you sure" before it reaches the server.
    var confirmCtx = null;   // { kind: 'branch'|'status', id }

    function openConfirm(kind, id) {
        var isBranch = kind === 'branch';
        var options  = isBranch ? branchOptions : statusOptions;
        var opt = options.filter(function (o) { return String(o.id) === String(id); })[0];
        if (!opt) return;

        confirmCtx = { kind: kind, id: id };

        $('#cfTitle').text(isBranch ? 'Confirm Branch Transfer' : 'Confirm Status Update');
        var inv = esc(invNo(openHeader) || openInvoice || '');
        $('#cfMessage').html(isBranch
            ? 'Transfer order <strong>' + inv + '</strong> to <strong>' + esc(opt.label) + '</strong>?'
            : 'Change the status of order <strong>' + inv + '</strong> to <strong>' + esc(opt.label) + '</strong>?');
        $('#cfError').hide().text('');
        $('#cfConfirm').prop('disabled', false).text('Confirm');

        $('#cfScrim').addClass('open');
        $('#confirmModal').addClass('open').attr('aria-hidden', 'false');
    }

    function closeConfirm() {
        $('#confirmModal').removeClass('open').attr('aria-hidden', 'true');
        $('#cfScrim').removeClass('open');
        confirmCtx = null;
    }

    function submitConfirm() {
        if (!confirmCtx) { closeConfirm(); return; }
        var ctx = confirmCtx;

        $('#cfConfirm').prop('disabled', true).text('Please wait…');

        var after = function (ok, msg) {
            if (ok) {
                closeConfirm();
            } else {
                $('#cfError').text(msg || 'The change could not be made.').show();
                $('#cfConfirm').prop('disabled', false).text('Confirm');
            }
        };

        if (ctx.kind === 'branch') changeBranch(ctx.id, after);
        else                       changeStatus(ctx.id, after);
    }

    // ---- change to pickup ----
    function openPickupDialog() {
        if (!openInvoice || !openHeader) return;

        var $s = $('#pkBranch').empty();
        $.each((lookups && lookups.Branches) || [], function (_, b) {
            $s.append($('<option>').val(b.BranchID).text(b.BranchName));
        });
        // Defaults to the branch the order is already at: most collections are
        // from the branch that is making the food.
        $s.val(openHeader.BranchID);

        $('#pkInvoice').text(invNo(openHeader) || openInvoice);
        $('#pkError').hide().text('');
        $('#pkConfirm').prop('disabled', false).text('Change to Pickup');

        $('#pkScrim').addClass('open');
        $('#pickupModal').addClass('open').attr('aria-hidden', 'false');
    }

    function closePickupDialog() {
        $('#pickupModal').removeClass('open').attr('aria-hidden', 'true');
        $('#pkScrim').removeClass('open');
    }

    function submitPickup() {
        var branchId = parseInt($('#pkBranch').val(), 10);
        if (!openInvoice) { closePickupDialog(); return; }
        if (!branchId) {
            $('#pkError').text('Select the branch the customer is collecting from.').show();
            return;
        }

        $('#pkConfirm').prop('disabled', true).text('Changing…');

        $.ajax({
            type: 'POST', url: POS.urls.toPickup,
            data: { invoiceNo: openInvoice, branchId: branchId, invoiceType: 3 }
        }).done(function (res) {
            if (res && res.Message === 'Success') {
                var inv = openInvoice, warn = res.Warning;
                closePickupDialog();
                openDrawer(inv);
                refreshAll(true);
                if (warn) alert(warn);
            } else {
                $('#pkError').text((res && res.ErrorMessage) || 'The order could not be changed to pickup.').show();
                $('#pkConfirm').prop('disabled', false).text('Change to Pickup');
            }
        }).fail(function (xhr) {
            $('#pkError').text('The change could not be sent (' + xhr.status + ').').show();
            $('#pkConfirm').prop('disabled', false).text('Change to Pickup');
        });
    }

    // Said plainly rather than failing quietly.
    function pending(what, backing) {
        alert(what + ' is not wired up yet.\n\n'
            + 'The database side (' + backing + ') is ready; '
            + 'the POS endpoint for it is next.');
    }

    function setBtn(sel, on, title) { $(sel).prop('disabled', !on).attr('title', title); }

    function cell(label, value, cls) {
        return '<div class="cell ' + (cls || '') + '">'
             + '<div class="lbl">' + label + '</div>'
             + '<div class="val">' + value + '</div></div>';
    }

    function kv(k, v) { return '<dt>' + k + '</dt><dd>' + v + '</dd>'; }

    function timeOnly(v) {
        var d = parseDate(v);
        if (!d) return '';
        var h = d.getHours(), ap = h >= 12 ? 'PM' : 'AM';
        h = h % 12; if (h === 0) h = 12;
        return ('0' + h).slice(-2) + ':' + ('0' + d.getMinutes()).slice(-2) + ' ' + ap;
    }

    // ---------------------------------------------------------------- events
    function wire() {
        var debounced = debounce(function () { refreshAll(); }, DEBOUNCE);
        $('#fSearch').on('input', debounced);
        $('#fPaymentStatus, #fFrom, #fTo').on('change', function () { refreshAll(); });

        $('#fScheduledOnly').on('change', function () {
            $('#fScheduledWrap').toggleClass('on', this.checked);
            refreshAll();
        });

        $('#fDateMode').on('change', function () {
            $('#fRangeWrap').toggle(this.value === 'Range');
            // A range with no dates would query all time; wait for the dates.
            if (this.value === 'Range' && !$('#fFrom').val() && !$('#fTo').val()) return;
            refreshAll();
        });

        $('#btnRefresh').on('click', function () { refreshAll(true); });

        // show/hide the whole filter column
        $('#btnToggleFilters').on('click', function () {
            var show = !$('#olSide').is(':visible');
            $('#olSide').toggle(show);
            $(this).toggleClass('on', show);
        });

        // clear button inside the search field
        function syncClear() {
            $('#searchShell').toggleClass('has-value', !!$('#fSearch').val());
        }
        $('#fSearch').on('input', syncClear);
        syncClear();

        $('#btnClearSearch').on('click', function () {
            $('#fSearch').val('').focus();
            syncClear();
            refreshAll();
        });

        $('#btnReset').on('click', function () {
            sel = { brand: {}, branch: {}, itype: {}, status: {} };
            $('#fSearch').val('');
            $('#fPaymentStatus').val('');
            $('#fScheduledOnly').prop('checked', false);
            $('#fScheduledWrap').removeClass('on');
            $('#fDateMode').val('Today');
            $('#fRangeWrap').hide();
            $('.facet input[type=checkbox]').prop('checked', false);
            $('#searchShell').removeClass('has-value');
            refreshAll();
        });

        // facet checkboxes
        $('.ol-side').on('change', 'input[type=checkbox]', function () {
            var g = $(this).data('group'), id = String($(this).data('id'));
            if (this.checked) sel[g][id] = true; else delete sel[g][id];
            refreshAll();
        });

        // collapse a facet group
        $('.ol-side').on('click', '.facet > header', function () {
            var $f = $(this).closest('.facet').toggleClass('collapsed');
            $(this).find('.toggle').html($f.hasClass('collapsed') ? '+' : '&minus;');
        });

        // chip remove
        $('#activeChips').on('click', 'button[data-group]', function () {
            var g = $(this).data('group'), id = String($(this).data('id'));
            delete sel[g][id];
            $('.facet input[data-group="' + g + '"][data-id="' + id + '"]').prop('checked', false);
            refreshAll();
        });

        // row actions
        $('#posOrders tbody').on('click', '.act-btn', function (e) {
            e.stopPropagation();
            if (this.disabled) return;
            var inv = $(this).closest('tr').attr('data-inv');
            var act = $(this).data('act');
            if (act === 'pay') {
                // The row already holds the customer, the total and what has
                // been paid, so the dialog opens filled in without a round trip.
                var d = table.row($(this).closest('tr')).data();
                openPayDialog(inv, d);
            }
        });

        $('#posOrders tbody').on('click', 'tr', function (e) {
            if ($(e.target).is('a, button') || $(e.target).closest('button').length) return;
            var inv = $(this).attr('data-inv');
            if (inv) openDrawer(inv);
        });

        $('#pmClose, #pmScrim').on('click', closeDrawer);

        // Footer actions. Each proc exists; the controller endpoint is next.
        $('#pmPay').on('click',    function () { payWithMyFatoorah(openInvoice); });
        $('#pmCancel').on('click', openCancelDialog);
        $('#coClose').on('click',  closeCancelDialog);
        $('#coBack').on('click',   closeCancelDialog);
        $('#coScrim').on('click',  closeCancelDialog);
        $('#coConfirm').on('click', submitCancel);

        // Delete a line off the order
        $('#pmBody').on('click', '.line-del', function () {
            openDeleteLine($(this).data('order'), $(this).data('name'));
        });
        $('#dlClose').on('click', closeDeleteLine);
        $('#dlBack').on('click',  closeDeleteLine);
        $('#dlScrim').on('click', closeDeleteLine);
        $('#dlConfirm').on('click', submitDeleteLine);
        $('#dlPassword').on('keydown', function (e) {
            if (e.key === 'Enter') { e.preventDefault(); submitDeleteLine(); }
        });
        $('#delLineModal').on('keydown', function (e) {
            if (e.key === 'Escape') { e.stopPropagation(); closeDeleteLine(); }
        });

        // Take payment
        $('#tpClose').on('click',  closePayDialog);
        $('#tpCancel').on('click', closePayDialog);
        $('#tpScrim').on('click',  closePayDialog);
        $('#tpConfirm').on('click', submitPayment);
        $('#tpTypes').on('input', 'input', updatePayTotals);

        // Double-clicking an empty box fills it with whatever is still owed
        // after the other boxes - the quick-fill the "Exact" button used to do,
        // without a button next to every amount. It completes a split rather
        // than overwriting the boxes already filled in, and it never touches a
        // box that has a figure in it.
        $('#tpTypes').on('dblclick', 'input', function () {
            var $me = $(this);
            if (($me.val() || '').trim() !== '') return;

            var others = 0;
            $('#tpTypes .tp-row input').each(function () {
                if ($(this).is($me)) return;
                var v = parseFloat($(this).val());
                if (!isNaN(v) && v > 0) others += v;
            });

            var rest = (payCtx ? payCtx.due : 0) - others;
            if (rest > 0) {
                $me.val(rest.toFixed(3));
                updatePayTotals();
                $me.select();
            }
        });
        $('#payModal').on('keydown', function (e) {
            if (e.key === 'Escape') { e.stopPropagation(); closePayDialog(); }
            if (e.key === 'Enter' && !$(e.target).is('button')) { e.preventDefault(); submitPayment(); }
        });

        // Enter in the password box submits; Escape backs out of the dialog
        // without touching the drawer behind it.
        $('#coPassword').on('keydown', function (e) {
            if (e.key === 'Enter') { e.preventDefault(); submitCancel(); }
        });
        $('#cancelModal').on('keydown', function (e) {
            if (e.key === 'Escape') { e.stopPropagation(); closeCancelDialog(); }
        });
        $('#pmModify').on('click', function () { pending('Modifying the order', 'a modify-order screen'); });
        $('#pmPickup').on('click', openPickupDialog);
        $('#pkClose').on('click',  closePickupDialog);
        $('#pkBack').on('click',   closePickupDialog);
        $('#pkScrim').on('click',  closePickupDialog);
        $('#pkConfirm').on('click', submitPickup);

        // Branch / status picker. Disabled buttons never fire click, so the
        // allowed-or-not check that used to guard the <select> is not needed
        // here - setBtn() in updateBranchButton()/updateStatusButton() already
        // decided that.
        $('#pmBranchBtn').on('click', function () { openPicker('branch'); });
        $('#pmStatusBtn').on('click', function () { openPicker('status'); });
        $('#pickGrid').on('click', '.pm-btn', function () { choosePickerOption($(this).data('id')); });
        $('#pickClose').on('click', closePicker);
        $('#pickBack').on('click',  closePicker);
        $('#pickScrim').on('click', closePicker);
        $('#pickModal').on('keydown', function (e) {
            if (e.key === 'Escape') { e.stopPropagation(); closePicker(); }
        });

        // Status/branch confirmation - the checkpoint that replaced the
        // server's old blanket "not a permitted transition" refusal.
        $('#cfClose').on('click', closeConfirm);
        $('#cfBack').on('click',  closeConfirm);
        $('#cfScrim').on('click', closeConfirm);
        $('#cfConfirm').on('click', submitConfirm);
        $('#confirmModal').on('keydown', function (e) {
            if (e.key === 'Escape') { e.stopPropagation(); closeConfirm(); }
            if (e.key === 'Enter')  { e.preventDefault(); submitConfirm(); }
        });

        $('#pmPrint').on('click', function () { printOrder(openInvoice, 'Thermal'); });

        $(document).on('keydown', function (e) {
            if ($(e.target).is('input, select, textarea')) {
                if (e.key === 'Escape') $(e.target).blur();
                return;
            }
            if (e.key === '/')      { e.preventDefault(); $('#fSearch').focus(); }
            else if (e.key === 'Escape') closeDrawer();
            else if (e.key === 'F5') { e.preventDefault(); refreshAll(true); }
        });

        document.addEventListener('visibilitychange', function () {
            if (!document.hidden) poll();
        });
    }

    // ------------------------------------------------------------------- API
    // pos.context.js lives in a separate file and must not reach into this
    // one's internals, so the few things it needs are published explicitly.
    window.POS = window.POS || {};
    POS.getSelected = function () { return []; };     // no tick column in this layout
    POS.reload      = function (keepPage) { refreshAll(keepPage); };
    POS.openDrawer  = function (inv) { openDrawer(inv); };
    // Called by the print popup when its print dialog is dismissed.
    POS.onPrintClosed = function (inv) { onPrintFinished(inv); };

    // ----------------------------------------------------------------- start
    $(function () {
        if (window.Notification && Notification.permission === 'default') {
            Notification.requestPermission();
        }

        $.getJSON(POS.urls.lookups)
            .done(function (res) {
                if (res && res.Message === 'Success') {
                    lookups = res;
                    renderStatusFacet(res.Statuses);
                }
            })
            .always(function () {
                restoreFromUrl();
                renderStatusFacet(lookups ? lookups.Statuses : []);
                initGrid();
                wire();
                loadFacets();
                startPolling();

                // Keep the grid's own scroll region sized to the window and
                // its header cells aligned with the body below - both drift
                // if the toolbar wraps to a second line or the window is
                // resized after the initial scrollY was measured.
                var resizeGrid = debounce(function () {
                    if (!table) return;
                    $('#posOrders_wrapper .dataTables_scrollBody').css({
                        height: gridScrollHeight(), 'max-height': gridScrollHeight()
                    });
                    table.columns.adjust();
                }, 150);
                $(window).on('resize', resizeGrid);
            });
    });
})();
