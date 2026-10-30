import io, re, shutil, subprocess
import xml.etree.ElementTree as ET

# ---------------------------------------------------------------------------
# 1. Web.config - all MyFatoorah settings, nothing hard-coded
# ---------------------------------------------------------------------------
p = 'Web.config'
shutil.copyfile(p, p + '.bak3')
t = io.open(p, encoding='utf-8-sig', newline='').read()

block = '''    <!-- ==================== MyFatoorah ====================
         Get the API token from the MyFatoorah portal:
             Live  -> MyFatoorah portal > Integration Settings > API Key
             Test  -> https://demo.myfatoorah.com  (test token)

         BaseUrl is REGIONAL on live. Using the wrong region returns
         "Invalid token" even when the token is correct:
             Kuwait          https://api.myfatoorah.com
             Saudi Arabia    https://api-sa.myfatoorah.com
             UAE             https://api-ae.myfatoorah.com
             Qatar / Bahrain / Oman / Jordan / Egypt  - see MyFatoorah docs
             TEST (any)      https://apitest.myfatoorah.com
    ==================================================== -->
    <add key="MyFatoorah.Enabled" value="false"/>
    <add key="MyFatoorah.BaseUrl" value="https://apitest.myfatoorah.com"/>
    <add key="MyFatoorah.ApiToken" value=""/>
    <add key="MyFatoorah.CurrencyIso" value="KWD"/>
    <add key="MyFatoorah.Language" value="EN"/>
    <add key="MyFatoorah.MobileCountryCode" value="965"/>
    <!-- LNK = just return a payment link. SMS / EML / ALL make MyFatoorah
         message the customer directly as well. -->
    <add key="MyFatoorah.NotificationOption" value="LNK"/>
    <!-- Leave blank to use this site's own /POS/Payment/Callback and /Failed.
         Set them only if the site is reached on a different public host. -->
    <add key="MyFatoorah.CallBackUrl" value=""/>
    <add key="MyFatoorah.ErrorUrl" value=""/>
    <!-- Webhook URL to register in the MyFatoorah portal:
         https://YOUR-SITE/POS/Payment/Webhook -->
    <add key="MyFatoorah.WebhookSecret" value=""/>
    <add key="MyFatoorah.TimeoutMs" value="20000"/>
'''

if 'MyFatoorah.ApiToken' not in t:
    anchor = '    <add key="OrderMode" value="LocalDB"/>'
    if anchor not in t:
        anchor = '    <add key="InvoiceTypeID" value="1"/>'
    assert anchor in t, 'appSettings anchor missing'
    t = t.replace(anchor, anchor + '\r\n' + block, 1)
    io.open(p, 'w', encoding='utf-8-sig', newline='').write(t)
    print('Web.config : MyFatoorah keys added')
else:
    print('Web.config : keys already present')

ET.parse(p); print('Web.config : XML VALID')

# ---------------------------------------------------------------------------
# 2. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
shutil.copyfile(cp, cp + '.bak11')
c = io.open(cp, encoding='utf-8-sig', newline='').read()

def add(kind, rel, anchor):
    global c
    if 'Include="%s"' % rel in c:
        return 'already there'
    assert anchor in c, 'anchor missing for ' + rel
    c = c.replace(anchor, '    <%s Include="%s" />\r\n' % (kind, rel) + anchor, 1)
    return 'ADDED'

print('csproj  Helper\\MyFatoorahService.cs           :',
      add('Compile', r'Helper\MyFatoorahService.cs',
          '    <Compile Include="Helper\\POSOrderService.cs" />'))
print('csproj  Areas\\POS\\Controllers\\PaymentController.cs :',
      add('Compile', r'Areas\POS\Controllers\PaymentController.cs',
          '    <Compile Include="Areas\\POS\\Controllers\\OrdersController.cs" />'))
print('csproj  Areas\\POS\\Views\\Payment\\Result.cshtml :',
      add('Content', r'Areas\POS\Views\Payment\Result.cshtml',
          '    <Content Include="Areas\\POS\\Views\\Orders\\Print.cshtml" />'))
print('csproj  DBScripts\\POS_15_MyFatoorah.sql       :',
      add('Content', r'DBScripts\POS_15_MyFatoorah.sql',
          '    <Content Include="DBScripts\\POS_14_DetailLines.sql" />'))

io.open(cp, 'w', encoding='utf-8-sig', newline='').write(c)
ET.parse(cp); print('csproj  XML VALID')

# ---------------------------------------------------------------------------
# 3. Layout + grid: wire the Pay button to MyFatoorah
# ---------------------------------------------------------------------------
lp = 'Areas/POS/Views/Shared/_LayoutPOS.cshtml'
shutil.copyfile(lp, lp + '.bak6')
lt = io.open(lp, encoding='utf-8-sig', newline='').read()
if 'payLink:' not in lt:
    lt = lt.replace(
        "        print:   '@Url.Action(\"Print\",   \"Orders\", new { area = \"POS\" })',",
        "        print:   '@Url.Action(\"Print\",   \"Orders\", new { area = \"POS\" })',\r\n"
        "        payLink: '@Url.Action(\"CreateLink\", \"Payment\", new { area = \"POS\" })',\r\n"
        "        payRefresh: '@Url.Action(\"Refresh\", \"Payment\", new { area = \"POS\" })',")
    io.open(lp, 'w', encoding='utf-8-sig', newline='').write(lt)
    print('layout  : payment urls added')
else:
    print('layout  : payment urls already there')

j = 'Areas/POS/Scripts/pos.orders.js'
shutil.copyfile(j, j + '.bak8')
t = io.open(j, encoding='utf-8-sig', newline='').read()

old_pay = """        $('#pmPay').on('click',    function () { pending('Taking payment', 'sp_POS_AddPayment'); });"""
new_pay = """        $('#pmPay').on('click',    function () { payWithMyFatoorah(openInvoice); });"""
assert old_pay in t, 'pay handler anchor missing'
t = t.replace(old_pay, new_pay, 1)

if 'function payWithMyFatoorah(' not in t:
    t = t.replace('    // Said plainly rather than failing quietly.',
"""    // Creates a MyFatoorah payment page and opens it. The window is opened
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
                    alert('Could not start the payment.\\n\\n' + ((res && res.Detail) || ''));
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

    // Said plainly rather than failing quietly.""", 1)

io.open(j, 'w', encoding='utf-8-sig', newline='').write(t)
r = subprocess.run(['node', '--check', j], capture_output=True, text=True)
print('pos.orders.js :', 'SYNTAX OK' if r.returncode == 0 else r.stderr[:400])
