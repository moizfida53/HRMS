/*==============================================================================
  Areas/POS/Scripts/pos.ribbon.js

  Ribbon behaviour. Two jobs:

    1. Enable and disable commands from the row selection, the way Word greys
       out formatting when nothing is selected. data-needs="one" means exactly
       one order; data-needs="any" means one or more.

    2. Dispatch commands. Anything a role cannot do is disabled here AND
       re-checked on the server - hiding a button is presentation, not security.

  Loaded after pos.orders.js, which owns the grid and exposes the selection.
==============================================================================*/
(function () {
    'use strict';

    // pos.orders.js keeps the selection; expose a read-only view of it.
    function selectedIds() {
        if (window.POS && typeof POS.getSelected === 'function') return POS.getSelected();
        var ids = [];
        $('#posOrders tbody .pos-chk:checked').each(function () { ids.push(this.value); });
        return ids;
    }

    function syncRibbon() {
        var n = selectedIds().length;
        $('#rbSelCount').text(n + ' selected');

        $('.rb-btn[data-needs]').each(function () {
            var $b     = $(this);
            var needs  = $b.data('needs');
            var perm   = $b.data('perm');
            var enough = (needs === 'one') ? (n === 1) : (n >= 1);

            // A role that cannot do this never gets the button enabled,
            // whatever the selection.
            var allowed = !perm || (POS.perms && POS.perms[perm]);
            if (perm && !allowed) {
                $b.prop('disabled', true).attr('title', 'Your role does not allow this');
                return;
            }
            $b.prop('disabled', !enough);
        });
    }

    function notImplemented(cmd) {
        // Said plainly rather than failing silently: the stored procedures for
        // these exist (sp_POS_ChangeStatus, sp_POS_CancelOrder,
        // sp_POS_TransferOrder, sp_POS_AddPayment, sp_POS_MarkPrinted) but
        // their controller endpoints are the next piece of work.
        alert('"' + cmd + '" is not wired up yet.\n\n'
            + 'The database side is ready; the POS endpoint for it is next.');
    }

    function dispatch(cmd) {
        var ids = selectedIds();
        if (!ids.length) return;

        if (cmd.indexOf('status:') === 0) { notImplemented('Change status'); return; }
        if (cmd.indexOf('print:')  === 0) { notImplemented('Print ' + cmd.split(':')[1]); return; }

        switch (cmd) {
            case 'pay':      notImplemented('Take payment'); break;
            case 'cancel':   notImplemented('Cancel order'); break;
            case 'transfer': notImplemented('Transfer branch'); break;
            case 'refund':   notImplemented('Refund'); break;
            default:         notImplemented(cmd);
        }
    }

    $(function () {
        $('.ribbon').on('click', '.rb-btn[data-cmd]', function () {
            if (this.disabled) return;
            dispatch(String($(this).data('cmd')));
        });

        $('#rbRefresh').on('click', function () {
            if (window.POS && typeof POS.reload === 'function') POS.reload(true);
        });

        $('#rbOpen').on('click', function () {
            var ids = selectedIds();
            if (ids.length === 1 && window.POS && typeof POS.openDrawer === 'function') {
                POS.openDrawer(ids[0]);
            }
        });

        $('#rbSelAll').on('click',  function () { $('#chkAll').prop('checked', true).trigger('change'); });
        $('#rbSelNone').on('click', function () { $('#chkAll').prop('checked', false).trigger('change'); });

        // The grid fires this whenever the selection changes.
        $(document).on('pos:selection', syncRibbon);

        // Catch checkbox clicks even before the grid has wired its own handler.
        $('#posOrders').on('change', '.pos-chk, #chkAll', function () { setTimeout(syncRibbon, 0); });

        // F5 refreshes the grid rather than the whole page - a full reload
        // loses the filter, the scroll position and the selection.
        $(document).on('keydown', function (e) {
            if (e.key === 'F5' && !e.ctrlKey) {
                e.preventDefault();
                if (window.POS && typeof POS.reload === 'function') POS.reload(true);
            }
        });

        syncRibbon();
    });
})();
