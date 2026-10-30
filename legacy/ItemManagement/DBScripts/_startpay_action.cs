        /// <summary>
        /// Starts an online payment for an order the customer has just placed,
        /// and returns the gateway URL for the browser to go to.
        ///
        /// This is reachable WITHOUT a POS login, because the caller is the
        /// customer. It is guarded by a one-shot token that SubmitOrder put in
        /// their session: without it, anyone could POST an invoice number and
        /// have us send that customer's name to the gateway, or mint payment
        /// links for orders that are not theirs.
        ///
        /// Whether the order is an online one is read from the INVOICE, never
        /// from the request - the browser does not get to decide that a
        /// cash-on-delivery order should skip payment.
        /// </summary>
        [HttpPost]
        public JsonResult StartOnlinePayment(long invoiceNo, string payToken)
        {
            try
            {
                string expected = Session["POSPayToken_" + invoiceNo] as string;

                if (string.IsNullOrEmpty(expected) ||
                    !string.Equals(expected, payToken, StringComparison.Ordinal))
                {
                    DB.AuditTrail(new Exception("StartOnlinePayment token mismatch for invoice " + invoiceNo),
                                  "ItemsViewController", "StartOnlinePayment", null);
                    return Json(new { Message = "Fail", Detail = "This payment session is no longer valid." },
                                JsonRequestBehavior.AllowGet);
                }

                if (!PaymentLinkService.IsOnlineOrder(invoiceNo))
                    return Json(new { Message = "NotOnline" }, JsonRequestBehavior.AllowGet);

                string root = Request.Url.GetLeftPart(UriPartial.Authority);
                string cb   = root + Url.Action("Callback", "Payment", new { area = "POS" });
                string er   = root + Url.Action("Failed",   "Payment", new { area = "POS" });

                PaymentLinkResult r = PaymentLinkService.Start(invoiceNo, null, cb, er, null);

                if (!r.Success)
                    return Json(new { Message = "Fail", Detail = r.Error }, JsonRequestBehavior.AllowGet);

                // One shot. The token is spent whether or not the customer
                // completes the payment, so a stale confirmation page cannot be
                // replayed to mint more links.
                Session.Remove("POSPayToken_" + invoiceNo);

                return Json(new
                {
                    Message    = "Success",
                    PaymentUrl = r.PaymentUrl,
                    Reference  = r.Reference,
                    Amount     = r.Amount
                }, JsonRequestBehavior.AllowGet);
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "ItemsViewController", "StartOnlinePayment", null);
                return Json(new { Message = "Fail", Detail = "Could not start the payment." },
                            JsonRequestBehavior.AllowGet);
            }
        }
