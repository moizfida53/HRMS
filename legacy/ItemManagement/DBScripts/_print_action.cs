        /// <summary>
        /// Printable document for one order.
        ///
        /// Rendered server-side and told to print itself on load, so the
        /// operator gets the browser's printer chooser (or their default
        /// printer with one Enter). Nothing is fetched by AJAX here: a print
        /// window that has to wait for a round trip can fire window.print()
        /// against a half-built page.
        ///
        /// doc  = Thermal | A4 | Kitchen
        /// lang = en | ar   (ar switches the whole document to RTL)
        /// </summary>
        [HttpGet]
        public ActionResult Print(long id, string doc = "Thermal", string lang = "en")
        {
            try
            {
                SqlParameter[] spa = { new SqlParameter("@InvoiceNo", SqlDbType.BigInt) { Value = id } };
                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_GetOrderDetails", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return HttpNotFound("Order not found.");

                // Count the print BEFORE rendering, so the REPRINT stamp on the
                // paper reflects the copy actually coming out of the printer.
                // A kitchen ticket that can be reprinted silently is a standard
                // route to duplicate-order fraud.
                int printCount = MarkPrinted(id, doc);

                ViewBag.Doc        = doc;
                ViewBag.Lang       = (lang ?? "en").ToLowerInvariant() == "ar" ? "ar" : "en";
                ViewBag.PrintCount = printCount;
                ViewBag.Header     = ds.Tables[0].Rows[0];
                ViewBag.Lines      = ds.Tables.Count > 1 ? ds.Tables[1] : null;
                ViewBag.Payments   = ds.Tables.Count > 3 ? ds.Tables[3] : null;

                return View("Print");
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "Print", null);
                return new HttpStatusCodeResult(500, "Could not build the document.");
            }
        }

        /// <summary>
        /// Increments PrintCount / LastPrintedOn via sp_POS_MarkPrinted and
        /// returns the new count. A failure here must not stop the operator
        /// printing, so it is logged and swallowed.
        /// </summary>
        private int MarkPrinted(long invoiceNo, string doc)
        {
            try
            {
                var dt = new DataTable();
                dt.Columns.Add("Value", typeof(long));
                dt.Rows.Add(invoiceNo);

                var u = POSUser.Current;
                SqlParameter[] spa =
                {
                    new SqlParameter("@InvoiceNos", SqlDbType.Structured)
                        { TypeName = "dbo.TVP_POS_BigIntList", Value = dt },
                    new SqlParameter("@DocType",  SqlDbType.VarChar, 20)  { Value = doc ?? "Invoice" },
                    new SqlParameter("@UserID",   SqlDbType.Int)          { Value = u != null ? (object)u.UserID : DBNull.Value },
                    new SqlParameter("@UserName", SqlDbType.NVarChar, 100){ Value = u != null ? (object)u.UserName : DBNull.Value }
                };

                DataSet r = DB.ExecuteStoredProcDataSet("sp_POS_MarkPrinted", spa);
                if (r != null && r.Tables.Count > 0 && r.Tables[0].Rows.Count > 0)
                    return Convert.ToInt32(r.Tables[0].Rows[0]["PrintCount"]);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.OrdersController", "MarkPrinted", null);
            }
            return 1;
        }
