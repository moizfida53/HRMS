import io, re, shutil, os
import xml.etree.ElementTree as ET

def read(p): return io.open(p, encoding='utf-8-sig', newline='').read()
def write(p, s): io.open(p, 'w', encoding='utf-8-sig', newline='').write(s)

# ---------------------------------------------------------------------------
# 1. The view needs PrintedBy, and the header needs System.Collections.Generic
#    for the List<DataRow> it builds.
# ---------------------------------------------------------------------------
p = 'Areas/POS/Views/Orders/Print.cshtml'
t = read(p)
if '@using System.Collections.Generic' not in t:
    t = t.replace('@using System.Linq', '@using System.Linq\r\n@using System.Collections.Generic', 1)
    write(p, t)
    print('Print.cshtml : System.Collections.Generic imported')

# ---------------------------------------------------------------------------
# 2. Controller: pass PrintedBy through
# ---------------------------------------------------------------------------
c = 'Areas/POS/Controllers/OrdersController.cs'
s = read(c)
if 'ViewBag.PrintedBy' not in s:
    shutil.copyfile(c, c + '.bak3')
    anchor = '                ViewBag.PrintCount = printCount;'
    assert anchor in s, 'PrintCount anchor missing'
    s = s.replace(anchor,
                  anchor + '\r\n'
                  '                // Printed By line on the receipt: who pressed the button.\r\n'
                  '                ViewBag.PrintedBy  = POSUser.Current != null ? POSUser.Current.UserName : "";',
                  1)
    write(c, s)
    print('OrdersController : ViewBag.PrintedBy added')
else:
    print('OrdersController : PrintedBy already there')

# ---------------------------------------------------------------------------
# 3. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
cc = read(cp)
rel = r'DBScripts\POS_18_PrintHeader.sql'
if 'Include="%s"' % rel not in cc:
    shutil.copyfile(cp, cp + '.bak14')
    a = '    <Content Include="DBScripts\\POS_17_CheckoutPay.sql" />'
    assert a in cc
    cc = cc.replace(a, '    <Content Include="%s" />\r\n' % rel + a, 1)
    write(cp, cc)
    print('csproj : POS_18 added')
ET.parse(cp); print('csproj : XML VALID')

# ---------------------------------------------------------------------------
# 4. Razor context check on the new view.
#    Track whether each @if / @foreach sits inside an OPEN markup element
#    (needs @) or directly inside a code block (must be plain).
# ---------------------------------------------------------------------------
print()
lines = read(p).split('\n')
in_code_block = 0          # depth of @if/@foreach { } blocks
open_tags = 0              # markup elements left open on the current level
problems = []

VOID = {'br','hr','img','input','meta','link','area','base','col','embed','source','track','wbr'}

for i, raw in enumerate(lines):
    l = raw.strip()
    if not l or l.startswith('@*') or l.startswith('//'):
        continue

    is_at = re.match(r'^@(if|foreach|switch|while)\b', l)
    is_plain = re.match(r'^(if|foreach|switch|while)\s*\(', l)

    if (is_at or is_plain) and in_code_block > 0 and open_tags == 0:
        # code context: @ is wrong
        if is_at:
            problems.append((i + 1, 'has @ but is in CODE context', l[:60]))
    if (is_at or is_plain) and (in_code_block == 0 or open_tags > 0):
        # markup context: @ is required
        if is_plain:
            problems.append((i + 1, 'missing @ but is in MARKUP context', l[:60]))

    # crude tag tracking on this line
    for m in re.finditer(r'<(/?)(\w+)([^>]*?)(/?)>', l):
        closing, tag, attrs, selfclose = m.groups()
        if tag.lower() in VOID or selfclose:
            continue
        open_tags += -1 if closing else 1
    if open_tags < 0:
        open_tags = 0

    if is_at or is_plain:
        in_code_block += 1
    if l == '}' and in_code_block > 0:
        in_code_block -= 1

if problems:
    for ln, why, txt in problems:
        print('  line %-5d %-38s %s' % (ln, why, txt))
else:
    print('  Razor context check: no @if/@foreach in the wrong context')
