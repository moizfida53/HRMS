import io, re, shutil, subprocess
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# 1. ItemsViewController - GetPaymentTypes
# ---------------------------------------------------------------------------
p = 'Controllers/ItemsViewController.cs'
shutil.copyfile(p, p + '.bak5')
c = io.open(p, encoding='utf-8-sig', newline='').read()

if 'GetPaymentTypes' not in c:
    block = io.open('DBScripts/_paytypes_action.cs', encoding='utf-8-sig', newline='').read().rstrip('\n')
    lines = c.split('\n')
    s = next(i for i, l in enumerate(lines) if 'public JsonResult GetAreaList' in l)
    while '[HttpPost]' not in lines[s]:
        s -= 1
    while s > 0 and lines[s-1].strip().startswith('///'):
        s -= 1
    lines = lines[:s] + block.split('\n') + [''] + lines[s:]
    c = '\n'.join(lines)
    io.open(p, 'w', encoding='utf-8-sig', newline='').write(c)
    print('controller : GetPaymentTypes added')
else:
    print('controller : already present')

# ---------------------------------------------------------------------------
# 2. Payment.cshtml - markup + loader + selection handler
# ---------------------------------------------------------------------------
v = 'Views/ItemsViewNew/CheckoutViews/Payment.cshtml'
shutil.copyfile(v, v + '.bak')
t = io.open(v, encoding='utf-8-sig', newline='').read()

# ---- 2a. replace the hard-coded Cash / KNET block ----
start = t.index('                <div class="form-row payment-options mb-2">')
# the block ends at the closing </div> of the payment-options row, just before
# the delivery-info card
end = t.index('            <div id="mainDivDeliveryInfo"')
old_block = t[start:end]
assert 'btnCashPayment' in old_block and 'btnKnetPayment' in old_block, 'payment markup anchor mismatch'

new_block = '''                <div class="form-row payment-options mb-2" id="divPaymentOptions">
                    @* Filled by loadPaymentTypes() from tblInvoicePaymentType
                       where IsOnline = 1. The hard-coded Cash / KNET buttons and
                       the KNetPayment appSetting are gone: which methods appear,
                       in what order, with which icon, is now data. *@
                    <div class="col-12 text-muted" style="font-size:13px;">Loading payment methods&hellip;</div>
                </div>
                @* Holds the real tblInvoicePaymentType.ID of the chosen method *@
                <div id="selectedPayementType" style="display:none;"></div>
            </div>
'''
t = t[:start] + new_block + t[end:]

# ---- 2b. paymentselectionClick: the old text compare no longer applies ----
old_sel = t[t.index('    function paymentselectionClick(obj, type) {'):]
old_sel = old_sel[:old_sel.index('\n    }\n') + len('\n    }\n')]

new_sel = '''    function paymentselectionClick(obj, type) {
        if (!obj) return;

        $('.paymenttype').each(function () { $(this).removeClass('activePayment'); });
        $(obj).addClass('activePayment');
        $('#selectedPayementType').html(type);

        // The button label follows whether money is taken now or on delivery,
        // which is a property of the method rather than of its name.
        var isCod = $(obj).data('iscod') == 1;
        $('#lblPaymentConfirmation').html(isCod ? btnPaymentProcessOrder : btnPaymentProceedtoPayment);
    }
'''
t = t.replace(old_sel, new_sel, 1)

# ---- 2c. append the loader and call it when the payment step opens ----
loader = io.open('DBScripts/_paytypes_js.txt', encoding='utf-8-sig', newline='').read().rstrip('\n')
marker = '    function onViewDetailsItemsOnPaymentView() {'
assert marker in t, 'onViewDetailsItemsOnPaymentView anchor missing'
t = t.replace(marker, loader + '\r\n\r\n' + marker, 1)

# the payment step is entered through onViewDetailsItemsOnPaymentView(); load
# the methods there so they refresh if the table changes mid-session
t = t.replace(marker, marker + '\r\n        loadPaymentTypes();', 1)

io.open(v, 'w', encoding='utf-8-sig', newline='').write(t)
print('Payment.cshtml : markup + loader + handler updated')

# ---------------------------------------------------------------------------
# 3. POSOrderService - trust a real PaymentTypeID when one is sent
# ---------------------------------------------------------------------------
h = 'Helper/POSOrderService.cs'
shutil.copyfile(h, h + '.bak')
s = io.open(h, encoding='utf-8-sig', newline='').read()

old_map = s[s.index('        public static int MapPaymentType(int selectedPayementType, bool isDelivery, out bool isPrepaid)'):]
old_map = old_map[:old_map.index('\n        }\n') + len('\n        }\n')]

new_map = '''        public static int MapPaymentType(int selectedPayementType, bool isDelivery, out bool isPrepaid)
        {
            var types = GetPaymentTypes();

            // Checkout now posts the REAL tblInvoicePaymentType.ID. If the value
            // matches a live row, use it as-is - the customer picked it, so
            // there is nothing to infer.
            var exact = types.FirstOrDefault(t => t.ID == selectedPayementType);
            if (exact != null)
            {
                isPrepaid = exact.IsOnline;
                return exact.ID;
            }

            // Legacy fallback for the old 0 = Cash / 1 = KNET codes, still sent
            // by the older ItemsView checkout.
            PaymentTypeRow row;
            if (selectedPayementType == 0)
            {
                row = (isDelivery ? types.FirstOrDefault(t => t.IsCOD) : null)
                      ?? types.FirstOrDefault(t => t.IsCash && !t.IsCOD)
                      ?? types.FirstOrDefault(t => t.IsCash);
                isPrepaid = false;
            }
            else
            {
                row = Match(types, "knet", "k-net", "k_net")
                      ?? Match(types, "visa")
                      ?? Match(types, "master")
                      ?? types.FirstOrDefault(t => t.IsOnline);
                isPrepaid = row != null && row.IsOnline;
            }

            if (row != null) return row.ID;

            isPrepaid = false;
            return 0;
        }
'''
assert old_map in s, 'MapPaymentType anchor missing'
s = s.replace(old_map, new_map, 1)
io.open(h, 'w', encoding='utf-8-sig', newline='').write(s)
print('POSOrderService : MapPaymentType now honours a real ID')

# ---------------------------------------------------------------------------
# 4. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak12')
cc = io.open(cp, encoding='utf-8-sig', newline='').read()
rel = r'DBScripts\POS_16_PaymentImages.sql'
if 'Include="%s"' % rel not in cc:
    a = '    <Content Include="DBScripts\\POS_15_MyFatoorah.sql" />'
    assert a in cc
    cc = cc.replace(a, '    <Content Include="%s" />\r\n' % rel + a, 1)
    io.open(cp, 'w', encoding='utf-8-sig', newline='').write(cc)
    print('csproj     : POS_16 added')
ET.parse(cp); print('csproj     : XML VALID')

# ---------------------------------------------------------------------------
# 5. checks
# ---------------------------------------------------------------------------
body = io.open(v, encoding='utf-8-sig').read()
print()
print('btnCashPayment gone :', 'btnCashPayment' not in body)
print('btnKnetPayment gone :', 'btnKnetPayment' not in body)
print('KNetPayment setting :', 'KNetPayment' not in body)
print('divPaymentOptions   :', 'divPaymentOptions' in body)
print('loadPaymentTypes    :', body.count('loadPaymentTypes'), 'refs')
