//==============================================================================
//  REPLACEMENT for ItemsViewController.SubmitOrder
//  File   : Controllers/ItemsViewController.cs
//  Lines  : 547 - 648  (the whole existing SubmitOrder method)
//
//  Replace the entire existing method with the version below.
//  Requires: Helper/POSOrderService.cs  +  POS_01_Schema.sql  +  POS_02_ProcessOrder.sql
//
//  WHAT STAYS THE SAME
//    - The route (/ItemsView/SubmitOrder) and the action signature: all three
//      existing JS callers keep working with zero front-end changes.
//    - sp_GetCartItemList is still used to expand the cart (it is what resolves
//      choices and extras into priceable lines).
//    - The JSON response shape: { Message, dtresult, InvoiceNo }. Payment.cshtml
//      reads result.dtresult[0].InvoiceNo/.DeliveryDate/.FinalAmount;
//      MainJs/ItemsView/BindCartDetails.js reads result.InvoiceNo. Both are fed.
//
//  WHAT CHANGES
//    - The WebClient POST to ProcessOrderHD is gone when OrderMode = LocalDB.
//    - Prices are recomputed in SQL from tblItems instead of trusted from the
//      browser.
//    - A per-submission GUID makes a retry or a double-tap idempotent.
//==============================================================================

[HttpPost]
public JsonResult SubmitOrder(List<CartDetails> orderDetails, CustomerNew customerInfo, Address addressInfo,
    int branchid, DateTime? DeliveryDate, int selectedPayementType, int DiscountTypeID, decimal InvoiceDiscount,
    string DiscountCode, Guid? clientOrderGuid = null)
{
    try
    {
        // ------------------------------------------------------------------
        // 1. Expand the cart (unchanged - this resolves choices and extras)
        // ------------------------------------------------------------------
        DataTable dt = DB.ToDataTable(orderDetails);
        SqlParameter[] spa1 = {
            new SqlParameter { ParameterName = "@dttblCartItems", Value = dt }
        };

        DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetCartItemList", spa1);
        if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
            return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);

        int brandid = 0;
        if (ds.Tables.Count == 2 && ds.Tables[1].Rows.Count > 0)
            brandid = Convert.ToInt32(ds.Tables[1].Rows[0]["BrandID"]);

        // ------------------------------------------------------------------
        // 2. Waiter (unchanged)
        // ------------------------------------------------------------------
        int WaiterID = 0;
        HttpCookie cookie = Request.Cookies["eCommerceCook"];
        if (cookie != null && !string.IsNullOrEmpty(cookie["IsWaiterLogin"]))
            WaiterID = Convert.ToInt32(cookie["WaiterID"]);

        // ------------------------------------------------------------------
        // 3. Legacy path - kept behind a switch so a bad night is an
        //    appSetting edit, not a redeploy. Remove once LocalDB is proven.
        // ------------------------------------------------------------------
        string orderMode = System.Configuration.ConfigurationManager.AppSettings["OrderMode"] ?? "LocalDB";
        if (orderMode.Equals("CallCenter", StringComparison.OrdinalIgnoreCase))
            return SubmitOrderViaCallCenter(ds.Tables[0], customerInfo, addressInfo, branchid, brandid,
                                            DeliveryDate, selectedPayementType, DiscountTypeID,
                                            InvoiceDiscount, DiscountCode, WaiterID);

        // ------------------------------------------------------------------
        // 4. Build the TVP rows
        // ------------------------------------------------------------------
        var items = new List<POSOrderItem>();
        foreach (DataRow row in ds.Tables[0].Rows)
        {
            items.Add(new POSOrderItem
            {
                // The cart currently identifies items by HID. The proc resolves
                // either HID or tblItems.ID, so both are sent and it picks.
                ItemID         = ToNullableInt(row["HID"]),
                HID            = ToNullableInt(row["HID"]),
                ParentItemID   = ToNullableInt(row["ParentItemID"]),
                CartItemUniqID = ToNullableInt(row["CartItemUniqID"]),
                LineType       = (ToNullableInt(row["ParentItemID"]) ?? 0) > 0 ? (byte)2 : (byte)1,
                Quantity       = Convert.ToInt32(row["Qty"]),
                Price          = row["PRICE"] != DBNull.Value ? Convert.ToDecimal(row["PRICE"]) : (decimal?)null,
                Comments       = row.Table.Columns.Contains("Comments") ? Convert.ToString(row["Comments"]) : null,
                Extra          = row.Table.Columns.Contains("ChoiceName") ? Convert.ToString(row["ChoiceName"]) : null
            });
        }

        // ------------------------------------------------------------------
        // 5. Order type + payment type
        // ------------------------------------------------------------------
        bool isTakeAway = customerInfo != null && customerInfo.TakeAway == true;
        int orderType   = isTakeAway ? 1 : 2;                 // 1 Pickup, 2 Delivery
        int paymentType = POSOrderService.MapPaymentType(selectedPayementType, !isTakeAway);

        // Idempotency key. If the browser did not send one, fall back to a
        // deterministic key so a retry of the SAME cart within the same minute
        // still collapses into one invoice.
        Guid guid = clientOrderGuid ?? BuildFallbackGuid(customerInfo, branchid, items);

        // ------------------------------------------------------------------
        // 6. Insert
        // ------------------------------------------------------------------
        POSOrderResult res = POSOrderService.ProcessOrder(
            items, customerInfo, addressInfo,
            branchid, brandid, orderType, paymentType,
            DeliveryDate, DiscountTypeID, InvoiceDiscount, DiscountCode,
            WaiterID, guid);

        if (res.Message != "Success" && res.Message != "Duplicate")
        {
            DB.AuditTrail(new Exception(res.ErrorMessage ?? "sp_POS_ProcessOrder failed"),
                          "ItemsViewController", "SubmitOrder", null);
            return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);
        }

        // ------------------------------------------------------------------
        // 7. Response shaped exactly like the call-centre one
        //    (an array, because Payment.cshtml does JSON.parse(...)[0])
        // ------------------------------------------------------------------
        var payload = new[]
        {
            new
            {
                InvoiceNo       = res.InvoiceNo,
                TrackingCode    = res.TrackingCode,
                RunningOrder    = res.RunningOrder,
                DeliveryDate    = DeliveryDate,
                BillAmount      = res.BillAmount,
                Discount        = res.Discount,
                DeliveryCharges = res.DeliveryCharges,
                FinalAmount     = res.NetAmount,
                PaymentType     = paymentType,
                CustomerId      = res.CustomerId,
                AddressID       = res.AddressID
            }
        };

        return Json(new
        {
            Message      = "Success",
            dtresult     = JsonConvert.SerializeObject(payload),
            InvoiceNo    = res.InvoiceNo,
            TrackingCode = res.TrackingCode
        }, JsonRequestBehavior.AllowGet);
    }
    catch (Exception ex)
    {
        DB.AuditTrail(ex, "ItemsViewController", "SubmitOrder", null);
        return Json(new { Message = "Fail", dtresult = "", InvoiceNo = (long?)null }, JsonRequestBehavior.AllowGet);
    }
}

// -----------------------------------------------------------------------------
// Helpers - add alongside SubmitOrder in ItemsViewController
// -----------------------------------------------------------------------------
private static int? ToNullableInt(object v)
{
    if (v == null || v == DBNull.Value) return null;
    int i;
    return int.TryParse(v.ToString(), out i) ? i : (int?)null;
}

/// <summary>
/// Deterministic idempotency key for clients that do not send one:
/// same customer + branch + cart contents inside the same minute = same GUID,
/// so a double-tap or a retry after a timeout returns the original invoice.
/// </summary>
private static Guid BuildFallbackGuid(CustomerNew c, int branchId, List<POSOrderItem> items)
{
    string basis = string.Concat(
        c != null ? c.Mobile : "", "|", branchId, "|",
        DateTime.Now.ToString("yyyyMMddHHmm"), "|",
        string.Join(",", items.Select(x => x.ItemID + "x" + x.Quantity)));

    using (var md5 = System.Security.Cryptography.MD5.Create())
        return new Guid(md5.ComputeHash(System.Text.Encoding.UTF8.GetBytes(basis)));
}

/// <summary>
/// The original call-centre path, unchanged, reachable via OrderMode=CallCenter.
/// Delete once the local path is proven in production.
/// </summary>
private JsonResult SubmitOrderViaCallCenter(DataTable dtItems, CustomerNew customerInfo, Address addressInfo,
    int branchid, int brandid, DateTime? DeliveryDate, int selectedPayementType, int DiscountTypeID,
    decimal InvoiceDiscount, string DiscountCode, int WaiterID)
{
    var value = new List<ItemViewOrder>();
    foreach (DataRow dtRow in dtItems.Rows)
    {
        value.Add(new ItemViewOrder
        {
            WaiterID       = WaiterID,
            ItemID         = dtRow["HID"].ToString(),
            Quantity       = Convert.ToInt32(dtRow["Qty"].ToString()),
            Comments       = dtRow["Comments"].ToString(),
            Price          = Convert.ToDecimal(dtRow["PRICE"].ToString()),
            HID            = 0,
            BID            = 0,
            CartItemUniqID = Convert.ToInt32(dtRow["CartItemUniqID"].ToString()),
            ParentItemID   = Convert.ToInt32(dtRow["ParentItemID"].ToString())
        });
    }

    string webServiceUrl = System.Configuration.ConfigurationManager.AppSettings["CallCenterUrl"];
    if (string.IsNullOrEmpty(webServiceUrl))
        return Json(new { Message = "Fail", dtresult = "" }, JsonRequestBehavior.AllowGet);

    var data = new
    {
        OrderDetails    = value,
        CustomerInfo    = customerInfo,
        addressInfo     = addressInfo,
        DeliveryDate    = DeliveryDate,
        DiscountTypeID  = DiscountTypeID,
        InvoiceDiscount = InvoiceDiscount,
        selectedPayementType = selectedPayementType,
        BranchID        = branchid,
        HID             = 0,
        BID             = 0,
        WaiterID        = WaiterID,
        BrandId         = brandid,
        InvoiceTypeID   = System.Configuration.ConfigurationManager.AppSettings["InvoiceTypeID"],
        DeliveryCharges = 0,
        DiscountCode    = DiscountCode,
        IsOnlineOrder   = true
    };

    string inputJson = (new System.Web.Script.Serialization.JavaScriptSerializer()).Serialize(data);
    using (var client = new System.Net.WebClient())
    {
        client.Headers["Content-type"] = "application/json";
        client.Encoding = System.Text.Encoding.UTF8;
        string jsonstr = client.UploadString(webServiceUrl + "/DmToCallCenterServices/ProcessOrderHD", inputJson);
        result str = JsonConvert.DeserializeObject<result>(jsonstr);
        return Json(str, JsonRequestBehavior.AllowGet);
    }
}


//==============================================================================
//  Web.config  -  add inside <appSettings>
//==============================================================================
//    <!-- LocalDB = insert into tblInvoice/tblOrder via sp_POS_ProcessOrder
//         CallCenter = legacy HTTP post to ProcessOrderHD -->
//    <add key="OrderMode" value="LocalDB" />
//
//  And change InvoiceTypeID from 10 (Call Centre) to 11 (QR Menu Online)
//  once orders no longer flow through the call centre:
//    <add key="InvoiceTypeID" value="11" />


//==============================================================================
//  ItemsViewController.cs - required usings (add any that are missing)
//==============================================================================
//    using System.Linq;
//    using Jar.Helper;      // POSOrderService, POSOrderItem, POSOrderResult
//    using Newtonsoft.Json;


//==============================================================================
//  OPTIONAL but recommended - front-end idempotency
//------------------------------------------------------------------------------
//  In Views/ItemsViewNew/CheckoutViews/Payment.cshtml, generate one GUID when
//  the checkout screen opens and send it with the order. A retry then reuses the
//  same key instead of minting a new order.
//
//    var _orderGuid = (function () {
//        return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
//            var r = Math.random() * 16 | 0;
//            return (c === 'x' ? r : (r & 0x3 | 0x8)).toString(16);
//        });
//    })();
//
//  then add to objdata:      clientOrderGuid: _orderGuid
//  and disable the button:   $('#btnProcessOrder').prop('disabled', true);
//                            // re-enable in the ajax error/complete handler
//==============================================================================
