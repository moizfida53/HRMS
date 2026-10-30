import io, re, shutil, subprocess
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# 1. OrdersController - Print + MarkPrinted
# ---------------------------------------------------------------------------
p = 'Areas/POS/Controllers/OrdersController.cs'
shutil.copyfile(p, p + '.bak2')
c = io.open(p, encoding='utf-8-sig', newline='').read()

if 'ActionResult Print' not in c:
    block = io.open('DBScripts/_print_action.cs', encoding='utf-8-sig', newline='').read().rstrip('\n')
    anchor = '''        /// <summary>Counter order entry. Placeholder screen for now.</summary>
        public ActionResult Place()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }'''
    assert anchor in c, 'Place action anchor missing'
    c = c.replace(anchor, anchor + '\r\n\r\n' + block, 1)
    io.open(p, 'w', encoding='utf-8-sig', newline='').write(c)
    print('controller : Print + MarkPrinted added')
else:
    print('controller : Print already present')

# ---------------------------------------------------------------------------
# 2. pos.orders.js - drop Address from the modal, wire the Print button
# ---------------------------------------------------------------------------
j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak7')
t = io.open(j, encoding='utf-8-sig', newline='').read()

old_extra = """        var extra = '';
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

new_extra = """        // Address was removed from this dialog; it still prints on the
        // receipt, where the driver actually needs it.
        var extra = '';
        if (h.DriverName) extra += kv('Driver', esc(h.DriverName));

        if (extra) {
            html += '<dl class="pos-kv mt-3" style="grid-template-columns:150px 1fr;">'
                 +  extra + '</dl>';
        }"""

assert old_extra in t, 'address block anchor missing'
t = t.replace(old_extra, new_extra, 1)

# Print now opens the real document
old_print = """        $('#pmPrint').on('click',  function () { pending('Printing', 'sp_POS_MarkPrinted'); });"""
new_print = """        $('#pmPrint').on('click', function () { printOrder(openInvoice, 'Thermal'); });"""
assert old_print in t, 'print handler anchor missing'
t = t.replace(old_print, new_print, 1)

# printOrder helper
if 'function printOrder(' not in t:
    t = t.replace('    // Said plainly rather than failing quietly.',
"""    // Opens the printable document in its own window, which then calls
    // window.print() itself. A popup is used rather than a hidden iframe so
    // the operator can pick a different printer, reprint, or switch to A4
    // without going back to the grid.
    function printOrder(invoiceNo, doc) {
        if (!invoiceNo) return;
        var url = POS.urls.print + '?id=' + encodeURIComponent(invoiceNo)
                + '&doc=' + encodeURIComponent(doc || 'Thermal');
        var w = window.open(url, 'posPrint_' + invoiceNo,
                            'width=420,height=760,menubar=no,toolbar=no');
        if (!w) {
            alert('The print window was blocked.\\n\\n'
                + 'Allow pop-ups for this site, then press Print again.');
            return;
        }
        w.focus();
        // The count changed server-side, so the row is stale.
        setTimeout(function () { refreshAll(true); }, 1200);
    }

    // Said plainly rather than failing quietly.""", 1)

io.open(j, 'w', encoding='utf-8-sig', newline='').write(t)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])

# ---------------------------------------------------------------------------
# 3. Layout - print url
# ---------------------------------------------------------------------------
lp = 'Areas/POS/Views/Shared/_LayoutPOS.cshtml'
shutil.copyfile(lp, lp + '.bak5')
lt = io.open(lp, encoding='utf-8-sig', newline='').read()
if 'print:' not in lt:
    lt = lt.replace(
        "        details: '@Url.Action(\"Details\", \"Orders\", new { area = \"POS\" })',",
        "        details: '@Url.Action(\"Details\", \"Orders\", new { area = \"POS\" })',\r\n"
        "        print:   '@Url.Action(\"Print\",   \"Orders\", new { area = \"POS\" })',")
    io.open(lp, 'w', encoding='utf-8-sig', newline='').write(lt)
    print('layout     : POS.urls.print added')
else:
    print('layout     : print url already there')

# ---------------------------------------------------------------------------
# 4. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak10')
cc = io.open(cp, encoding='utf-8-sig', newline='').read()
rel = r'Areas\POS\Views\Orders\Print.cshtml'
if 'Include="%s"' % rel not in cc:
    a = '    <Content Include="Areas\\POS\\Views\\Orders\\Place.cshtml" />'
    assert a in cc
    cc = cc.replace(a, '    <Content Include="%s" />\r\n' % rel + a, 1)
    io.open(cp, 'w', encoding='utf-8-sig', newline='').write(cc)
    print('csproj     : Print.cshtml added')
else:
    print('csproj     : already there')
ET.parse(cp); print('csproj XML : VALID')
