import io, re, shutil, os
import xml.etree.ElementTree as ET

def read(p):  return io.open(p, encoding='utf-8-sig', newline='').read()
def write(p, s): io.open(p, 'w', encoding='utf-8-sig', newline='').write(s)

def fn_span(lines, pattern):
    s = next(i for i, l in enumerate(lines) if re.search(pattern, l))
    d, e = 0, None
    for i in range(s, len(lines)):
        d += lines[i].count('{') - lines[i].count('}')
        if d == 0 and i > s:
            e = i; break
    assert e is not None, pattern
    return s, e

# ---------------------------------------------------------------------------
# 1. ItemsViewController: StartOnlinePayment + a pay token from SubmitOrder
# ---------------------------------------------------------------------------
p = 'Controllers/ItemsViewController.cs'
shutil.copyfile(p, p + '.bak6')
c = read(p)

if 'StartOnlinePayment' not in c:
    block = read('DBScripts/_startpay_action.cs').rstrip('\n')
    lines = c.split('\n')
    s = next(i for i, l in enumerate(lines) if 'public JsonResult GetPaymentTypes' in l)
    while '[HttpPost]' not in lines[s]:
        s -= 1
    while s > 0 and lines[s-1].strip().startswith('///'):
        s -= 1
    lines = lines[:s] + block.split('\n') + [''] + lines[s:]
    c = '\n'.join(lines)
    print('controller : StartOnlinePayment added')
else:
    print('controller : StartOnlinePayment already present')

# SubmitOrder must hand the browser a token it can spend once.
if 'POSPayToken_' not in c or 'PayToken' not in c:
    old = """                return Json(new
                {
                    Message      = "Success",
                    dtresult     = JsonConvert.SerializeObject(payload),
                    InvoiceNo    = res.InvoiceNo,
                    TrackingCode = res.TrackingCode,
                    Warning      = res.Warning
                }, JsonRequestBehavior.AllowGet);"""
    new = """                // One-shot token for StartOnlinePayment. Held in session so the
                // customer's own browser can start a payment for THIS order
                // without a login, and nobody else can.
                string payToken = Guid.NewGuid().ToString("N");
                if (res.InvoiceNo.HasValue)
                    Session["POSPayToken_" + res.InvoiceNo.Value] = payToken;

                return Json(new
                {
                    Message      = "Success",
                    dtresult     = JsonConvert.SerializeObject(payload),
                    InvoiceNo    = res.InvoiceNo,
                    TrackingCode = res.TrackingCode,
                    Warning      = res.Warning,
                    PayToken     = payToken,
                    IsOnlinePayment = isPrepaid
                }, JsonRequestBehavior.AllowGet);"""
    assert old in c, 'SubmitOrder response anchor missing'
    c = c.replace(old, new, 1)
    print('controller : SubmitOrder now returns PayToken + IsOnlinePayment')

write(p, c)

# ---------------------------------------------------------------------------
# 2. PaymentController.CreateLink -> use the shared service (one money path)
# ---------------------------------------------------------------------------
pc = 'Areas/POS/Controllers/PaymentController.cs'
shutil.copyfile(pc, pc + '.bak')
s = read(pc)
lines = s.split('\n')
a, b = fn_span(lines, r'public JsonResult CreateLink\(')
while '[HttpPost]' not in lines[a]:
    a -= 1
print('PaymentController : CreateLink lines %d-%d -> shared service' % (a + 1, b + 1))

new_create = '''        [HttpPost]
        [POSAuthorize(POSPermission.TakePayment)]
        public JsonResult CreateLink(long invoiceNo, decimal? amount)
        {
            try
            {
                string root = Request.Url.GetLeftPart(UriPartial.Authority);
                string cb   = root + Url.Action("Callback", "Payment", new { area = "POS" });
                string er   = root + Url.Action("Failed",   "Payment", new { area = "POS" });

                var u = POSUser.Current;
                PaymentLinkResult r = PaymentLinkService.Start(
                    invoiceNo, amount, cb, er, u != null ? (int?)u.UserID : null);

                if (!r.Success)
                    return Json(new { Message = "Fail", Detail = r.Error });

                return Json(new
                {
                    Message    = "Success",
                    PaymentUrl = r.PaymentUrl,
                    LinkID     = r.LinkID,
                    Reference  = r.Reference,
                    Amount     = r.Amount,
                    Reused     = r.Reused
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.PaymentController", "CreateLink", null);
                return Json(new { Message = "Fail", Detail = "Could not start the payment." });
            }
        }'''
lines = lines[:a] + new_create.split('\n') + lines[b + 1:]
write(pc, '\n'.join(lines))

# ---------------------------------------------------------------------------
# 3. Payment.cshtml: redirect to the gateway on success
# ---------------------------------------------------------------------------
v = 'Views/ItemsViewNew/CheckoutViews/Payment.cshtml'
shutil.copyfile(v, v + '.bak3')
t = read(v)

anchor = '''                if (result.Message == "Success") {
                    $('#advisement').modal('hide');'''
assert anchor in t, 'SubmitOrderAjaxcall success anchor missing'

new_head = '''                if (result.Message == "Success") {

                    // An online method must be paid before the customer sees a
                    // confirmation screen. Showing "order placed" first and
                    // redirecting after teaches people to close the tab, and the
                    // order is then sitting unpaid.
                    if (result.IsOnlinePayment && result.PayToken) {
                        $('#lblPaymentConfirmation').html('Redirecting to payment...');
                        $.ajax({
                            type: "Post",
                            url: "/ItemsView/StartOnlinePayment",
                            data: { invoiceNo: result.InvoiceNo, payToken: result.PayToken },
                            cache: false
                        }).done(function (pr) {
                            if (pr && pr.Message === "Success" && pr.PaymentUrl) {
                                ClearcartData();
                                // Same tab, not a popup: mobile browsers block
                                // popups opened from an ajax callback, and the
                                // customer must not lose the gateway page.
                                window.location = pr.PaymentUrl;
                            } else {
                                alert('Your order ' + result.InvoiceNo + ' was created, but the payment page '
                                    + 'could not be opened.\\n\\n' + ((pr && pr.Detail) || '')
                                    + '\\n\\nPlease contact the branch to pay.');
                                showOrderConfirmation(result);
                            }
                        }).fail(function () {
                            alert('Your order ' + result.InvoiceNo + ' was created, but the payment page '
                                + 'could not be opened. Please contact the branch to pay.');
                            showOrderConfirmation(result);
                        });
                        return;
                    }

                    $('#advisement').modal('hide');'''

t = t.replace(anchor, new_head, 1)

# showOrderConfirmation(): the non-online path, reused by the failure fallbacks
helper = '''    // Shows the order-placed screen. Split out so the online-payment failure
    // paths can fall back to it instead of leaving the customer on a dead page.
    function showOrderConfirmation(result) {
        $('#advisement').modal('hide');
        $('#divlandingpage').hide();
        $('#divCategoryList').hide();
        $('#divMainItemDetails').hide();
        $('#divCartView').hide();
        $('#divQRCodeMain').hide();
        $('#TrackingOrder').hide();
        $('#divReservation').hide();
        $('#divReservationConfirm').hide();
        $('#divCustomerInfo').hide();
        $('#divDeliveryService').hide();
        $('#divDeliveryAddress').hide();
        $('#divPaymentView').hide();
        $('#divOrderConfirmView').show();
    }

'''
marker = '    function SubmitOrderAjaxcall(objdata) {'
assert marker in t
t = t.replace(marker, helper + marker, 1)

write(v, t)
print('Payment.cshtml : redirects to the gateway for online methods')

# ---------------------------------------------------------------------------
# 4. csproj
# ---------------------------------------------------------------------------
cp = 'ItemManagment.csproj'
cc = read(cp)
changed = False
for kind, rel, anchor in [
    ('Compile', r'Helper\PaymentLinkService.cs',      '    <Compile Include="Helper\\MyFatoorahService.cs" />'),
    ('Content', r'DBScripts\POS_17_CheckoutPay.sql',  '    <Content Include="DBScripts\\POS_16_PaymentImages.sql" />')]:
    if 'Include="%s"' % rel not in cc:
        assert anchor in cc, anchor
        cc = cc.replace(anchor, '    <%s Include="%s" />\r\n' % (kind, rel) + anchor, 1)
        changed = True
        print('csproj     : %s added' % rel)
if changed:
    shutil.copyfile(cp, cp + '.bak13')
    write(cp, cc)
ET.parse(cp); print('csproj     : XML VALID')

# ---------------------------------------------------------------------------
# 5. checks
# ---------------------------------------------------------------------------
print()
body = read(v)
ctrl = read(p)
for label, ok in [
    ('checkout redirects to PaymentUrl', 'window.location = pr.PaymentUrl' in body),
    ('showOrderConfirmation fallback',   'function showOrderConfirmation' in body),
    ('StartOnlinePayment action',        'StartOnlinePayment' in ctrl),
    ('PayToken issued by SubmitOrder',   'POSPayToken_' in ctrl),
    ('PaymentLinkService on disk',       os.path.exists('Helper/PaymentLinkService.cs')),
    ('CreateLink uses shared service',   'PaymentLinkService.Start' in read(pc))]:
    print('  %-36s %s' % (label, ok))
