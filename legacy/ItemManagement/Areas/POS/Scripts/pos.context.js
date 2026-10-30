/*==============================================================================
  Areas/POS/Scripts/pos.context.js

  Right-click menu for the orders grid, replacing the ribbon.

  Rules that make a context menu usable rather than annoying:

    * Right-clicking a row that is NOT part of the current tick selection acts
      on that row alone. Right-clicking one that IS selected acts on the whole
      selection. This is how file managers behave, and it stops an operator
      accidentally applying a command to nine other orders.

    * Commands a role cannot use are shown DISABLED, not hidden. A cashier who
      cannot see a Cancel item assumes the system is broken; one who sees it
      greyed out understands immediately.

    * The menu is repositioned to stay inside the viewport, so right-clicking
      the bottom row does not open a menu half off screen.
==============================================================================*/
(function () {
    'use strict';

    var $menu, targetIds = [];

    function selectedIds() {
        if (window.POS && typeof POS.getSelected === 'function') return POS.getSelected();
        var ids = [];
        $('#posOrders tbody .pos-chk:checked').each(function () { ids.push(this.value); });
        return ids;
    }

    function openMenu(x, y, ids) {
        targetIds = ids;

        $('#ctxCap').text(ids.length === 1 ? 'Order ' + ids[0] : ids.length + ' orders selected');

        $menu.find('button[data-cmd]').each(function () {
            var $b   = $(this);
            var perm = $b.data('perm');
            var one  = $b.data('single') === 1;

            var allowed = !perm || (POS.perms && POS.perms[perm]);
            var fits    = !one || ids.length === 1;

            $b.prop('disabled', !allowed || !fits)
              .attr('title', !allowed ? 'Your role does not allow this'
                                      : (!fits ? 'Select a single order for this' : ''));
        });

        // Show first so the browser reports real dimensions, then correct the
        // position. Measuring a display:none element returns zero.
        $menu.addClass('open').css({ left: 0, top: 0 });

        var w  = $menu.outerWidth(), h = $menu.outerHeight();
        var vw = $(window).width(),  vh = $(window).height();
        var sx = $(window).scrollLeft(), sy = $(window).scrollTop();

        var left = (x + w > sx + vw) ? Math.max(sx + 4, x - w) : x;
        var top  = (y + h > sy + vh) ? Math.max(sy + 4, y - h) : y;

        $menu.css({ left: left + 'px', top: top + 'px' });
    }

    function closeMenu() { $menu.removeClass('open'); }

    function notImplemented(label) {
        // Stated plainly rather than failing quietly. The stored procedures
        // exist (sp_POS_ChangeStatus, sp_POS_CancelOrder, sp_POS_TransferOrder,
        // sp_POS_AddPayment, sp_POS_MarkPrinted); their controller endpoints
        // are the next piece of work.
        alert(label + ' is not wired up yet.\n\n'
            + 'The database side is ready; the POS endpoint for it is next.');
    }

    function dispatch(cmd) {
        if (!targetIds.length) return;

        if (cmd === 'open') {
            if (window.POS && typeof POS.openDrawer === 'function') POS.openDrawer(targetIds[0]);
            return;
        }
        if (cmd.indexOf('status:') === 0) { notImplemented('Changing status'); return; }
        if (cmd.indexOf('print:')  === 0) { notImplemented('Printing the ' + cmd.split(':')[1] + ' document'); return; }

        switch (cmd) {
            case 'pay':      notImplemented('Taking payment'); break;
            case 'transfer': notImplemented('Transferring branch'); break;
            case 'cancel':   notImplemented('Cancelling the order'); break;
            case 'refund':   notImplemented('Refunding'); break;
            default:         notImplemented(cmd);
        }
    }

    $(function () {
        $menu = $('#posCtx');
        if (!$menu.length) return;

        $('#posOrders').on('contextmenu', 'tbody tr', function (e) {
            var inv = $(this).attr('data-inv');
            if (!inv) return;                       // empty-table placeholder row
            e.preventDefault();

            var sel = selectedIds();
            // Acting on a row outside the selection must not hit the selection.
            var ids = (sel.length && sel.indexOf(inv) >= 0) ? sel : [inv];

            openMenu(e.pageX, e.pageY, ids);
        });

        $menu.on('click', 'button[data-cmd]', function () {
            if (this.disabled) return;
            var cmd = String($(this).data('cmd'));
            closeMenu();
            dispatch(cmd);
        });

        // Close on anything that means "I'm done here".
        $(document).on('mousedown', function (e) {
            if (!$(e.target).closest('#posCtx').length) closeMenu();
        });
        $(document).on('keydown', function (e) { if (e.key === 'Escape') closeMenu(); });
        $(window).on('resize scroll', closeMenu);
    });
})();
