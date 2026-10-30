import io, re, shutil, subprocess

# ---------------------------------------------------------------------------
# 1. Layout: swap the drawer CSS for modal CSS
# ---------------------------------------------------------------------------
p = 'Areas/POS/Views/Shared/_LayoutPOS.cshtml'
shutil.copyfile(p, p + '.bak3')
t = io.open(p, encoding='utf-8-sig', newline='').read()

css = io.open('DBScripts/_modal_css.txt', encoding='utf-8-sig', newline='').read().rstrip('\n')

start = t.index('        /* ---------------- details drawer ---------------- */')
end   = t.index('        .pos-muted { color: var(--pos-muted); }')
t = t[:start] + css + '\r\n\r\n' + t[end:]

# the drawer element and its backdrop are gone
t = t.replace('<div class="pos-backdrop" id="posBackdrop"></div>\r\n', '')
t = t.replace('<div class="pos-backdrop" id="posBackdrop"></div>\n', '')

io.open(p, 'w', encoding='utf-8-sig', newline='').write(t)
print('layout   : modal css in, drawer css out')

# ---------------------------------------------------------------------------
# 2. Orders/Index.cshtml: replace the <aside> drawer with the modal
# ---------------------------------------------------------------------------
v = 'Areas/POS/Views/Orders/Index.cshtml'
shutil.copyfile(v, v + '.bak')
s = io.open(v, encoding='utf-8-sig', newline='').read()

modal = '''@* ---------------- order details modal ---------------- *@
<div class="pos-modal-scrim" id="pmScrim"></div>

<div class="pos-modal" id="posModal" role="dialog" aria-modal="true"
     aria-labelledby="pmTitle" aria-hidden="true">

    <div class="pm-head">
        <h5 id="pmTitle">Order Details</h5>
        <button class="x" id="pmClose" aria-label="Close">&times;</button>
    </div>

    <div class="pm-summary" id="pmSummary"></div>

    <div class="pm-body" id="pmBody"></div>

    <div class="pm-foot" id="pmFoot" style="display:none;">
        <button class="pm-btn cancel" id="pmCancel"><span class="i">&#128465;</span> Cancel Order</button>
        <button class="pm-btn modify" id="pmModify"><span class="i">&#9998;</span> Modify Order</button>
        <button class="pm-btn pay"    id="pmPay"><span class="i">&#128181;</span> Pay</button>
        <button class="pm-btn pickup" id="pmPickup"><span class="i">&#128694;</span> Change to Pickup</button>
        <button class="pm-btn print"  id="pmPrint"><span class="i">&#128424;</span> Print</button>
    </div>
</div>'''

s = re.sub(r'@\* -+ details drawer -+ \*@\s*<aside class="pos-drawer".*?</aside>',
           modal, s, flags=re.S)
io.open(v, 'w', encoding='utf-8-sig', newline='').write(s)
print('index    : drawer markup -> modal markup')

# ---------------------------------------------------------------------------
# 3. pos.orders.js: modal open/close/render + button wiring
# ---------------------------------------------------------------------------
j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak5')
c = io.open(j, encoding='utf-8-sig', newline='').read()

def span(src, name):
    lines = src.split('\n')
    st = next(i for i, l in enumerate(lines) if re.match(r'\s*function %s\(' % re.escape(name), l))
    d, e = 0, None
    for i in range(st, len(lines)):
        d += lines[i].count('{') - lines[i].count('}')
        if d == 0 and i > st:
            e = i; break
    return st, e

# replace the three drawer functions in one contiguous block
s1, _  = span(c, 'openDrawer')
_,  e3 = span(c, 'renderDrawer')
lines = c.split('\n')
assert 'drwBody' in '\n'.join(lines[s1:e3+1]), 'drawer block anchor mismatch'
print('   drawer fns lines %d-%d' % (s1 + 1, e3 + 1))

newjs = io.open('DBScripts/_modal_js.txt', encoding='utf-8-sig', newline='').read().rstrip('\n')
c = '\n'.join(lines[:s1] + newjs.split('\n') + lines[e3+1:])

# close handlers + footer actions
c = c.replace("""        $('#drwClose, #posBackdrop').on('click', closeDrawer);""",
"""        $('#pmClose, #pmScrim').on('click', closeDrawer);

        // Footer actions. Each proc exists; the controller endpoint is next.
        $('#pmPay').on('click',    function () { pending('Taking payment', 'sp_POS_AddPayment'); });
        $('#pmCancel').on('click', function () { pending('Cancelling the order', 'sp_POS_CancelOrder'); });
        $('#pmModify').on('click', function () { pending('Modifying the order', 'a modify-order screen'); });
        $('#pmPickup').on('click', function () { pending('Changing to pickup', 'sp_POS_ChangeStatus'); });
        $('#pmPrint').on('click',  function () { pending('Printing', 'sp_POS_MarkPrinted'); });""")

if 'function pending(' not in c:
    c = c.replace('    function setBtn(sel, on, title)',
"""    // Said plainly rather than failing quietly.
    function pending(what, backing) {
        alert(what + ' is not wired up yet.\\n\\n'
            + 'The database side (' + backing + ') is ready; '
            + 'the POS endpoint for it is next.');
    }

    function setBtn(sel, on, title)""", 1)

io.open(j, 'w', encoding='utf-8-sig', newline='').write(c)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:500])

# nothing should still reference the drawer
left = [l for l in io.open(j, encoding='utf-8-sig').read().split('\n')
        if 'drwBody' in l or 'posDrawer' in l or 'posBackdrop' in l]
print('leftover drawer refs:', left if left else 'none')
