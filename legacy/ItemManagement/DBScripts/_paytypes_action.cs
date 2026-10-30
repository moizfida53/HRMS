        /// <summary>
        /// Payment methods for the customer checkout.
        ///
        /// Returns only tblInvoicePaymentType rows with IsOnline = 1, so the
        /// list is controlled from the database rather than from markup and an
        /// appSetting. Image holds a file name resolved against /images.
        ///
        /// Pass includeCOD=1 to also show cash on delivery.
        /// </summary>
        [HttpPost]
        public JsonResult GetPaymentTypes(bool includeCOD = false)
        {
            try
            {
                SqlParameter[] spa =
                {
                    new SqlParameter("@IncludeCOD", SqlDbType.Bit) { Value = includeCOD }
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_GetOnlinePaymentTypes", spa);

                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return Json(new { Message = "Success", dtresult = "[]" }, JsonRequestBehavior.AllowGet);

                // Resolve the image to a usable URL here rather than in the
                // browser: the site can run under a virtual directory, where a
                // hard-coded "../../images/x.png" breaks depending on the
                // current route depth.
                string baseUrl = Url.Content("~/images/");
                DataTable dt = ds.Tables[0];

                if (!dt.Columns.Contains("ImageUrl")) dt.Columns.Add("ImageUrl", typeof(string));

                foreach (DataRow r in dt.Rows)
                {
                    string img = r["Image"] != DBNull.Value ? Convert.ToString(r["Image"]).Trim() : "";
                    if (img.Length == 0)
                    {
                        r["ImageUrl"] = "";                       // the view falls back to a label
                    }
                    else if (img.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
                          || img.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                          || img.StartsWith("/"))
                    {
                        r["ImageUrl"] = img;                      // already a full path or CDN url
                    }
                    else
                    {
                        r["ImageUrl"] = baseUrl + img;
                    }
                }

                return Json(new
                {
                    Message  = "Success",
                    dtresult = JsonConvert.SerializeObject(dt)
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "GetPaymentTypes", null);
                return Json(new { Message = "Fail" }, JsonRequestBehavior.AllowGet);
            }
        }
