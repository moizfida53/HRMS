import io, re, shutil
import xml.etree.ElementTree as ET

def read(p):  return io.open(p, encoding='utf-8-sig', newline='').read()
def write(p, s): io.open(p, 'w', encoding='utf-8-sig', newline='').write(s)

def fn_span(lines, pattern):
    """Line indexes of a brace-balanced block starting at the first line
       matching `pattern`. Line-ending agnostic, unlike string slicing."""
    s = next(i for i, l in enumerate(lines) if re.search(pattern, l))
    d, e = 0, None
    for i in range(s, len(lines)):
        d += lines[i].count('{') - lines[i].count('}')
        if d == 0 and i > s:
            e = i; break
    assert e is not None, pattern
    return s, e

# ---------------------------------------------------------------------------
# 1. Payment.cshtml
# ---------------------------------------------------------------------------
v = 'Views/ItemsViewNew/CheckoutViews/Payment.cshtml'
if not io.open(v + '.bak', encoding='utf-8-sig', newline='').read():
    pass
t = read(v + '.bak')          # always start from the pristine copy

# ---- 1a. hard-coded Cash / KNET block -> data-driven container ----
start = t.index('                <div class="form-row payment-options mb-2">')
end   = t.index('            <div id="mainDivDeliveryInfo"')
assert 'btnCashPayment' in t[start:end] and 'btnKnetPayment' in t[start:end], 'markup anchor mismatch'

new_block = ('                <div class="form-row payment-options mb-2" id="divPaymentOptions">\r\n'
             '                    @* Filled by loadPaymentTypes() from tblInvoicePaymentType\r\n'
             '                       where IsOnline = 1. The hard-coded Cash / KNET buttons and\r\n'
             '                       the KNetPayment appSetting are gone: which methods appear,\r\n'
             '                       in what order, with which icon, is now data. *@\r\n'
             '                    <div class="col-12 text-muted" style="font-size:13px;">Loading payment methods&hellip;</div>\r\n'
             '                </div>\r\n'
             '                @* Holds the real tblInvoicePaymentType.ID of the chosen method *@\r\n'
             '                <div id="selectedPayementType" style="display:none;"></div>\r\n'
             '            </div>\r\n')
t = t[:start] + new_block + t[end:]

# ---- 1b. paymentselectionClick ----
lines = t.split('\n')
s, e = fn_span(lines, r'function paymentselectionClick\(')
new_sel = '''    function paymentselectionClick(obj, type) {\r
        if (!obj) return;\r
\r
        $('.paymenttype').each(function () { $(this).removeClass('activePayment'); });\r
        $(obj).addClass('activePayment');\r
        $('#selectedPayementType').html(type);\r
\r
        // The button label follows whether money is taken now or on delivery,\r
        // which is a property of the method rather than of its name.\r
        var isCod = $(obj).data('iscod') == 1;\r
        $('#lblPaymentConfirmation').html(isCod ? btnPaymentProcessOrder : btnPaymentProceedtoPayment);\r
    }\r'''
print('paymentselectionClick : lines %d-%d' % (s + 1, e + 1))
lines = lines[:s] + new_sel.split('\n') + lines[e + 1:]
t = '\n'.join(lines)

# ---- 1c. loader, and call it when the payment step opens ----
loader = read('DBScripts/_paytypes_js.txt').rstrip('\n').rstrip('\r')
marker = '    function onViewDetailsItemsOnPaymentView() {'
assert marker in t
t = t.replace(marker, loader + '\r\n\r\n' + marker, 1)
t = t.replace(marker, marker + '\r\n        loadPaymentTypes();', 1)

write(v, t)
print('Payment.cshtml : rewritten')

# ---------------------------------------------------------------------------
# 2. POSOrderService.MapPaymentType
# ---------------------------------------------------------------------------
h = 'Helper/POSOrderService.cs'
src = read(h + '.bak') if __import__('os').path.exists(h + '.bak') else read(h)
if not __import__('os').path.exists(h + '.bak'):
    shutil.copyfile(h, h + '.bak')

lines = src.split('\n')
s, e = fn_span(lines, r'public static int MapPaymentType\(')
print('MapPaymentType        : lines %d-%d' % (s + 1, e + 1))

new_map = '''        public static int MapPaymentType(int selectedPayementType, bool isDelivery, out bool isPrepaid)\r
        {\r
            var types = GetPaymentTypes();\r
\r
            // Checkout now posts the REAL tblInvoicePaymentType.ID. If it\r
            // matches a live row, use it as-is - the customer picked it, so\r
            // there is nothing to infer.\r
            var exact = types.FirstOrDefault(t => t.ID == selectedPayementType);\r
            if (exact != null)\r
            {\r
                isPrepaid = exact.IsOnline;\r
                return exact.ID;\r
            }\r
\r
            // Legacy fallback for the old 0 = Cash / 1 = KNET codes, still sent\r
            // by the older ItemsView checkout.\r
            PaymentTypeRow row;\r
            if (selectedPayementType == 0)\r
            {\r
                row = (isDelivery ? types.FirstOrDefault(t => t.IsCOD) : null)\r
                      ?? types.FirstOrDefault(t => t.IsCash && !t.IsCOD)\r
                      ?? types.FirstOrDefault(t => t.IsCash);\r
                isPrepaid = false;\r
            }\r
            else\r
            {\r
                row = Match(types, "knet", "k-net", "k_net")\r
                      ?? Match(types, "visa")\r
                      ?? Match(types, "master")\r
                      ?? types.FirstOrDefault(t => t.IsOnline);\r
                isPrepaid = row != null && row.IsOnline;\r
            }\r
\r
            if (row != null) return row.ID;\r
\r
            isPrepaid = false;\r
            return 0;\r
        }\r'''
lines = lines[:s] + new_map.split('\n') + lines[e + 1:]
write(h, '\n'.join(lines))
print('POSOrderService       : MapPaymentType honours a real ID')

# ---------------------------------------------------------------------------
# 3. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
cc = read(cp)
rel = r'DBScripts\POS_16_PaymentImages.sql'
if 'Include="%s"' % rel not in cc:
    shutil.copyfile(cp, cp + '.bak12')
    a = '    <Content Include="DBScripts\\POS_15_MyFatoorah.sql" />'
    assert a in cc
    cc = cc.replace(a, '    <Content Include="%s" />\r\n' % rel + a, 1)
    write(cp, cc)
    print('csproj                : POS_16 added')
else:
    print('csproj                : already there')
ET.parse(cp)

# ---------------------------------------------------------------------------
# 4. checks
# ---------------------------------------------------------------------------
body = read(v)
print()
for label, ok in [('btnCashPayment removed', 'btnCashPayment' not in body),
                  ('btnKnetPayment removed', 'btnKnetPayment' not in body),
                  ('KNetPayment setting gone', 'KNetPayment' not in body),
                  ('divPaymentOptions present', 'divPaymentOptions' in body),
                  ('loadPaymentTypes defined+called', body.count('loadPaymentTypes') >= 2)]:
    print('  %-34s %s' % (label, ok))
