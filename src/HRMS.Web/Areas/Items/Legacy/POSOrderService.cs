#nullable disable
using Microsoft.AspNetCore.Http;
using HRMS.Web.Areas.Items.Legacy;
using ConfigurationManager = HRMS.Web.Areas.Items.Legacy.ConfigurationManager;
//==============================================================================
//  Helper/POSOrderService.cs      (v2 - REPLACES the version delivered earlier)
//------------------------------------------------------------------------------
//  Works against the head-office lookup tables after POS_03_Reconcile.sql, and
//  calls sp_POS_ProcessOrder from POS_04_ProcessOrder_v2.sql.
//
//  WHAT CHANGED vs v1
//    * Payment types are resolved by NAME from tblInvoicePaymentType and cached,
//      instead of hard-coded IDs. The HO tables use IDENTITY keys, so the IDs
//      differ per deployment - a hard-coded map would book payments against the
//      wrong type.
//    * Discount is no longer sent as a trusted number; the proc computes it from
//      tblDiscountCode / tblDiscount_Type. InvoiceDiscount remains a fallback.
//    * New: IsPrepaid + PaymentReference, so online payments are recorded and
//      mirrored into the legacy per-method column on tblInvoice.
//    * New in the result: NetPayable (what the customer actually pays) and
//      Warning (e.g. branch does not serve the delivery area).
//
//  NOTE: FinalAmount on tblInvoice is BillAmount - Discount and EXCLUDES
//  DeliveryCharges. Anything shown to a customer must use NetPayable.
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using Microsoft.Data.SqlClient;
using System.Linq;
using System.Runtime.Caching;
using HRMS.Web.Areas.Items.Models;

namespace HRMS.Web.Areas.Items.Legacy
{
    /// <summary>
    /// One row of dbo.TVP_POS_OrderItem.
    /// PROPERTY ORDER MATTERS: DB.ToDataTable builds columns by reflection order
    /// and SQL Server binds a TVP by ordinal, not by name. Do not reorder.
    /// </summary>
    public class POSOrderItem
    {
        public int? ItemID { get; set; }
        public int? HID { get; set; }
        public int? ParentItemID { get; set; }
        public int? CartItemUniqID { get; set; }
        public byte LineType { get; set; }          // 1 Item, 2 Choice, 3 Extra
        public int Quantity { get; set; }
        public decimal? Price { get; set; }
        public string Comments { get; set; }
        public string Extra { get; set; }
    }

    public class POSOrderResult
    {
        public string Message { get; set; }             // Success | Duplicate | Fail
        public long? InvoiceNo { get; set; }
        public string TrackingCode { get; set; }
        public int? RunningOrder { get; set; }
        public decimal BillAmount { get; set; }
        public decimal Discount { get; set; }
        public decimal DeliveryCharges { get; set; }
        public decimal FinalAmount { get; set; }        // bill - discount (matches DB column)
        public decimal NetPayable { get; set; }         // + delivery == what the customer pays
        public int? CustomerId { get; set; }
        public int? AddressID { get; set; }
        public int? PaymentTypeID { get; set; }
        public string Warning { get; set; }
        public string ErrorMessage { get; set; }
    }

    public static class POSOrderService
    {
        // ---------------------------------------------------------------------
        // Payment type lookup, cached for 10 minutes.
        // ---------------------------------------------------------------------
        private const string PaymentCacheKey = "POS_PaymentTypes_v1";

        private class PaymentTypeRow
        {
            public int ID;
            public string Name;
            public bool IsCash, IsOnline, IsCOD;
        }

        private static List<PaymentTypeRow> GetPaymentTypes()
        {
            var cached = MemoryCache.Default.Get(PaymentCacheKey) as List<PaymentTypeRow>;
            if (cached != null) return cached;

            var list = new List<PaymentTypeRow>();
            using (var con = DB.dbConn())
            using (var cmd = new SqlCommand(
                @"SELECT ID, PaymentTypeName, IsCash, IsOnline, IsCOD
                    FROM dbo.tblInvoicePaymentType
                   WHERE ISNULL(IsDeleted,0) = 0 AND ISNULL(IsActive,1) = 1
                   ORDER BY Seqnum, ID;", con))
            {
                con.Open();
                using (var rd = cmd.ExecuteReader())
                    while (rd.Read())
                        list.Add(new PaymentTypeRow
                        {
                            ID       = Convert.ToInt32(rd["ID"]),
                            Name     = Convert.ToString(rd["PaymentTypeName"]) ?? "",
                            IsCash   = rd["IsCash"]   != DBNull.Value && Convert.ToBoolean(rd["IsCash"]),
                            IsOnline = rd["IsOnline"] != DBNull.Value && Convert.ToBoolean(rd["IsOnline"]),
                            IsCOD    = rd["IsCOD"]    != DBNull.Value && Convert.ToBoolean(rd["IsCOD"])
                        });
            }

            MemoryCache.Default.Set(PaymentCacheKey, list,
                new CacheItemPolicy { AbsoluteExpiration = DateTimeOffset.Now.AddMinutes(10) });
            return list;
        }

        /// <summary>Clear the cache after editing payment types in the POS.</summary>
        public static void InvalidatePaymentTypeCache()
        {
            MemoryCache.Default.Remove(PaymentCacheKey);
        }

        /// <summary>
        /// Maps the browser's selectedPayementType (0 = Cash, otherwise KNET,
        /// per Views/ItemsViewNew/CheckoutViews/Payment.cshtml) onto a real
        /// tblInvoicePaymentType.ID.
        ///
        /// >>> CONFIRM against LookupContents.txt: if head office seeded that
        ///     table with its own names, adjust the Match() terms below.
        /// </summary>
        public static int MapPaymentType(int selectedPayementType, bool isDelivery, out bool isPrepaid)
        {
            var types = GetPaymentTypes();

            // Checkout now posts the REAL tblInvoicePaymentType.ID. If it
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

        private static PaymentTypeRow Match(List<PaymentTypeRow> types, params string[] terms)
        {
            return types.FirstOrDefault(t =>
                terms.Any(term => t.Name.IndexOf(term, StringComparison.OrdinalIgnoreCase) >= 0));
        }

        // ---------------------------------------------------------------------
        // Insert
        // ---------------------------------------------------------------------
        public static POSOrderResult ProcessOrder(
            List<POSOrderItem> items,
            CustomerNew customerInfo,
            Address addressInfo,
            int branchId,
            int brandId,
            int orderType,                 // 1 Pickup, 2 Delivery, 3 Dine-in
            int paymentTypeId,             // 0 = let the proc choose the default
            bool isPrepaid,
            string paymentReference,
            DateTime? deliveryDate,
            int discountTypeId,
            decimal invoiceDiscount,
            string discountCode,
            int waiterId,
            Guid clientOrderGuid,
            string comments = null)
        {
            if (items == null || items.Count == 0)
                return new POSOrderResult { Message = "Fail", ErrorMessage = "Cart is empty." };

            DataTable dtItems = DB.ToDataTable(items);

            var spa = new List<SqlParameter>
            {
                new SqlParameter("@BranchID",       SqlDbType.Int)           { Value = branchId },
                new SqlParameter("@BrandID",        SqlDbType.Int)           { Value = brandId },
                new SqlParameter("@InvoiceTypeID",  SqlDbType.Int)           { Value = GetInvoiceTypeId() },
                new SqlParameter("@OrderType",      SqlDbType.Int)           { Value = orderType },
                new SqlParameter("@SourceID",       SqlDbType.Int)           { Value = 1 },

                new SqlParameter("@CustomerId",     SqlDbType.Int)           { Value = AsDb(customerInfo?.id) },
                new SqlParameter("@CustomerName",   SqlDbType.NVarChar, 200) { Value = AsDb(customerInfo?.CustomerName) },
                new SqlParameter("@Mobile",         SqlDbType.NVarChar, 30)  { Value = AsDb(customerInfo?.Mobile) },
                new SqlParameter("@Mobile2",        SqlDbType.NVarChar, 30)  { Value = AsDb(customerInfo?.Mobile2) },
                new SqlParameter("@Email",          SqlDbType.NVarChar, 100) { Value = AsDb(addressInfo?.Email) },
                new SqlParameter("@CivilID",        SqlDbType.NVarChar, 50)  { Value = AsDb(customerInfo?.CivilID) },

                new SqlParameter("@AddressID",      SqlDbType.Int)           { Value = AsDb(addressInfo?.id) },
                new SqlParameter("@AreaID",         SqlDbType.Int)           { Value = AsDb(addressInfo?.Areaid) },
                new SqlParameter("@Block",          SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Block) },
                new SqlParameter("@Street",         SqlDbType.NVarChar, 500) { Value = AsDb(addressInfo?.Street) },
                new SqlParameter("@Lane",           SqlDbType.NVarChar, 100) { Value = AsDb(addressInfo?.Lane) },
                new SqlParameter("@Building",       SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Building) },
                new SqlParameter("@Floor",          SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Floor) },
                new SqlParameter("@Flat",           SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Flat) },
                new SqlParameter("@HouseNo",        SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.HouseNo) },
                new SqlParameter("@PACI",           SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.PACI) },
                new SqlParameter("@AddressRemark",  SqlDbType.NVarChar, 500) { Value = AsDb(addressInfo?.AddressRemark) },
                new SqlParameter("@Lat",            SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Lat) },
                new SqlParameter("@Lng",            SqlDbType.NVarChar, 50)  { Value = AsDb(addressInfo?.Long) },

                new SqlParameter("@DeliveryDate",   SqlDbType.DateTime)      { Value = AsDb(deliveryDate) },
                new SqlParameter("@IsPrepaid",      SqlDbType.Bit)           { Value = isPrepaid },
                new SqlParameter("@PaymentReference",SqlDbType.NVarChar,100) { Value = AsDb(paymentReference) },
                new SqlParameter("@DiscountTypeID", SqlDbType.Int)           { Value = discountTypeId },
                new SqlParameter("@InvoiceDiscount",SqlDbType.Decimal)       { Precision = 18, Scale = 3, Value = invoiceDiscount },
                new SqlParameter("@DiscountCode",   SqlDbType.NVarChar, 50)  { Value = AsDb(discountCode) },
                new SqlParameter("@DeliveryCharges",SqlDbType.Decimal)       { Precision = 18, Scale = 3, Value = DBNull.Value },
                new SqlParameter("@WaiterID",       SqlDbType.Int)           { Value = waiterId },
                new SqlParameter("@Comments",       SqlDbType.NVarChar, 500) { Value = AsDb(comments) },
                new SqlParameter("@ClientOrderGuid",SqlDbType.UniqueIdentifier) { Value = clientOrderGuid },

                new SqlParameter("@dtOrderItems",   SqlDbType.Structured)    { TypeName = "dbo.TVP_POS_OrderItem", Value = dtItems }
            };

            // 0 means "no match found" - omit it so the proc applies its default.
            if (paymentTypeId > 0)
                spa.Add(new SqlParameter("@PaymentTypeID", SqlDbType.Int) { Value = paymentTypeId });

            DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_ProcessOrder", spa.ToArray());

            if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                return new POSOrderResult { Message = "Fail", ErrorMessage = "No response from sp_POS_ProcessOrder." };

            DataRow r = ds.Tables[0].Rows[0];
            return new POSOrderResult
            {
                Message         = Str(r, "Message"),
                InvoiceNo       = Nl (r, "InvoiceNo"),
                TrackingCode    = Str(r, "TrackingCode"),
                RunningOrder    = Ni (r, "RunningOrder"),
                BillAmount      = Dec(r, "BillAmount"),
                Discount        = Dec(r, "Discount"),
                DeliveryCharges = Dec(r, "DeliveryCharges"),
                FinalAmount     = Dec(r, "FinalAmount"),
                NetPayable      = Dec(r, "NetPayable"),
                CustomerId      = Ni (r, "CustomerId"),
                AddressID       = Ni (r, "AddressID"),
                PaymentTypeID   = Ni (r, "PaymentTypeID"),
                Warning         = Str(r, "Warning"),
                ErrorMessage    = Str(r, "ErrorMessage")
            };
        }

        // ----- helpers -------------------------------------------------------

        private static int GetInvoiceTypeId()
        {
            int id;
            var cfg = ConfigurationManager.AppSettings["InvoiceTypeID"];
            return int.TryParse(cfg, out id) ? id : 11;
        }

        private static object AsDb(object v)
        {
            if (v == null) return DBNull.Value;
            var s = v as string;
            if (s != null && s.Length == 0) return DBNull.Value;
            return v;
        }

        private static string Str(DataRow r, string c)
            { return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? r[c].ToString() : null; }
        private static long? Nl(DataRow r, string c)
            { return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? (long?)Convert.ToInt64(r[c]) : null; }
        private static int? Ni(DataRow r, string c)
            { return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? (int?)Convert.ToInt32(r[c]) : null; }
        private static decimal Dec(DataRow r, string c)
            { return r.Table.Columns.Contains(c) && r[c] != DBNull.Value ? Convert.ToDecimal(r[c]) : 0m; }
    }
}

//==============================================================================
//  ItemsViewController.SubmitOrder - the two lines that change from v1
//------------------------------------------------------------------------------
//  Replace the payment-type block with:
//
//      bool isPrepaid;
//      int paymentType = POSOrderService.MapPaymentType(selectedPayementType, !isTakeAway, out isPrepaid);
//
//  and the ProcessOrder call with:
//
//      POSOrderResult res = POSOrderService.ProcessOrder(
//          items, customerInfo, addressInfo,
//          branchid, brandid, orderType, paymentType, isPrepaid, null,
//          DeliveryDate, DiscountTypeID, InvoiceDiscount, DiscountCode,
//          WaiterID, guid);
//
//  In the response payload, FinalAmount must be the amount the customer pays:
//
//      FinalAmount     = res.NetPayable,      // shown to the customer
//      InvoiceTotal    = res.FinalAmount,     // bill - discount, matches the DB
//      DeliveryCharges = res.DeliveryCharges,
//      Warning         = res.Warning,
//
//  Payment.cshtml renders resData[0].FinalAmount as the order total, so mapping
//  NetPayable onto that name keeps the customer-facing figure correct with no
//  front-end change.
//
//  Requires: <Reference Include="System.Runtime.Caching" /> in the .csproj
//            (part of the .NET Framework, no NuGet package needed).
//==============================================================================
