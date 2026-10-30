import io, re, shutil, subprocess

# ---------------------------------------------------------------------------
# 1. Layout CSS - header needs room for the customer line and a status pill
# ---------------------------------------------------------------------------
p = 'Areas/POS/Views/Shared/_LayoutPOS.cshtml'
shutil.copyfile(p, p + '.bak4')
t = io.open(p, encoding='utf-8-sig', newline='').read()

old = """        .pm-head {
            display: flex; align-items: center; justify-content: space-between;
            padding: 14px 20px; border-bottom: 1px solid var(--pos-border);
        }
        .pm-head h5 { margin: 0; font-size: 19px; font-weight: 600; color: var(--tmm-ink); }"""

new = """        .pm-head {
            display: flex; align-items: center; gap: 14px;
            padding: 14px 20px; border-bottom: 1px solid var(--pos-border);
        }
        .pm-head h5 { margin: 0; font-size: 19px; font-weight: 600; color: var(--tmm-ink); }
        /* min-width:0 lets a long Arabic customer name ellipsis instead of
           pushing the status pill and close button off the dialog */
        .pm-head .who { min-width: 0; flex: 1 1 auto; }
        .pm-head .who .cust {
            font-size: 13.5px; color: var(--pos-muted); margin-top: 2px;
            overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
        }
        .pm-head .who .cust a { color: var(--tmm-teal-dk); }
        .pm-head .stat { flex: 0 0 auto; }"""

assert old in t, 'pm-head css anchor missing'
t = t.replace(old, new, 1)
io.open(p, 'w', encoding='utf-8-sig', newline='').write(t)
print('layout : pm-head css updated')

# ---------------------------------------------------------------------------
# 2. Index markup - header gets a customer line and a status slot
# ---------------------------------------------------------------------------
v = 'Areas/POS/Views/Orders/Index.cshtml'
shutil.copyfile(v, v + '.bak2')
s = io.open(v, encoding='utf-8-sig', newline='').read()

old_head = """    <div class="pm-head">
        <h5 id="pmTitle">Order Details</h5>
        <button class="x" id="pmClose" aria-label="Close">&times;</button>
    </div>"""

new_head = """    <div class="pm-head">
        <div class="who">
            <h5 id="pmTitle">Order Details</h5>
            <div class="cust" id="pmCustomer"></div>
        </div>
        <span class="stat" id="pmStatus"></span>
        <button class="x" id="pmClose" aria-label="Close">&times;</button>
    </div>"""

assert old_head in s, 'pm-head markup anchor missing'
s = s.replace(old_head, new_head, 1)
io.open(v, 'w', encoding='utf-8-sig', newline='').write(s)
print('index  : header markup updated')

# ---------------------------------------------------------------------------
# 3. pos.orders.js - populate header, drop Invoice type / Paid / duplicates
# ---------------------------------------------------------------------------
j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak6')
c = io.open(j, encoding='utf-8-sig', newline='').read()

# header: customer - mobile, and the status pill
old_title = """        $('#pmTitle').text('Order Details');"""
new_title = """        $('#pmTitle').text('Order Details');

        // Customer and mobile now live in the header, separated by a dash.
        var name   = h.CustomerName || '-';
        var mobile = h.Mobile
                   ? '<a href="tel:' + esc(h.Mobile) + '">' + esc(h.Mobile) + '</a>'
                   : '-';
        $('#pmCustomer').html(esc(name) + ' <span class="pos-muted">&ndash;</span> ' + mobile);

        $('#pmStatus').html('<span class="pos-pill" style="background:'
                          + esc(h.StatusColor || '#6c757d') + '">'
                          + esc(h.OrderStatusName || '') + '</span>');"""

assert old_title in c, 'pmTitle anchor missing'
c = c.replace(old_title, new_title, 1)

# clear the header on open so the previous order's details never linger
c = c.replace("""        $('#pmSummary').empty();""",
              """        $('#pmSummary').empty();
        $('#pmCustomer').empty();
        $('#pmStatus').empty();""")

# rebuild the detail block: Customer / Mobile / Status moved to the header,
# Invoice type and Paid dropped as requested
old_kv = """        // Context the reference screen leaves out but a cashier keeps asking for.
        html += '<dl class="pos-kv mt-3" style="grid-template-columns:150px 1fr;">'
             +  kv('Customer', esc(h.CustomerName || '-'))
             +  kv('Mobile',   h.Mobile ? '<a href="tel:' + esc(h.Mobile) + '">' + esc(h.Mobile) + '</a>' : '-')
             +  kv('Invoice type', esc(h.InvoiceTypeName || h.OrderTypeName || '-'))
             +  kv('Status', '<span class="pos-pill" style="background:' + esc(h.StatusColor || '#6c757d') + '">'
                             + esc(h.OrderStatusName) + '</span>')
             +  (h.DriverName ? kv('Driver', esc(h.DriverName)) : '')
             +  kv('Paid', money(h.AmountPaid) + ' of ' + money(h.NetPayable));

        if (h.OrderType === 2) {
            var addr = [h.AreaName, h.Block ? 'Block ' + h.Block : '', h.Street, h.Building, h.Flat]
                       .filter(Boolean).join(', ');
            html += kv('Address', esc(addr || '-'));
        }
        html += '</dl>';"""

new_kv = """        // Customer, mobile and status are in the header now; invoice type and
        // paid-amount were dropped. Only build this block if something is left
        // to put in it - an empty <dl> would leave a stray gap.
        var extra = '';
        if (h.DriverName) extra += kv('Driver', esc(h.DriverName));

        if (h.OrderType === 2) {
            var addr = [h.AreaName, h.Block ? 'Block ' + h.Block : '', h.Street, h.Building, h.Flat]
                       .filter(Boolean).join(', ');
            extra += kv('Address', esc(addr || '-'));
            if (h.AddressRemark) extra += kv('Remark', esc(h.AddressRemark));
        }

        if (extra) {
            html += '<dl class="pos-kv mt-3" style="grid-template-columns:150px 1fr;">'
                 +  extra + '</dl>';
        }"""

assert old_kv in c, 'detail block anchor missing'
c = c.replace(old_kv, new_kv, 1)

io.open(j, 'w', encoding='utf-8-sig', newline='').write(c)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])

body = io.open(j, encoding='utf-8-sig').read()
for term in ["kv('Invoice type'", "kv('Paid'", "kv('Customer'", "kv('Mobile'", "kv('Status'"]:
    print('  %-22s still present: %s' % (term + "'", term in body))
