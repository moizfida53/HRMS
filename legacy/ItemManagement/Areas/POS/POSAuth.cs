//==============================================================================
//  Areas/POS/POSAuth.cs
//------------------------------------------------------------------------------
//  Session-backed identity, a permission-checking action filter, and the login
//  controller for the POS Area.
//
//  Permissions are re-checked SERVER SIDE on every action. The UI hides buttons
//  a role cannot use, but hiding a button is presentation, not security -- the
//  filter below is what actually stops a cashier POSTing a refund.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\POSAuth.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Linq;
using System.Web;
using System.Web.Mvc;
using Jar.Helper;

namespace Jar.Areas.POS
{
    /// <summary>The signed-in POS operator, held in session.</summary>
    [Serializable]
    public class POSUser
    {
        public int UserID { get; set; }
        public string UserName { get; set; }
        public string LoginName { get; set; }
        public int BrandID { get; set; }
        public int RoleID { get; set; }
        public string RoleName { get; set; }

        public bool CanChangeStatus { get; set; }
        public bool CanCancel { get; set; }
        public bool CanRefund { get; set; }
        public bool CanTransfer { get; set; }
        public bool CanTakePayment { get; set; }
        public bool CanViewReports { get; set; }
        public bool CanEndDay { get; set; }
        public bool CanManageMasters { get; set; }

        /// <summary>
        /// Branches (dbo.tblbranch.id) this user is allowed to see in the
        /// Order List and Dashboard reports - set from User Management, not
        /// related to BrandID above. Never null after login; empty means the
        /// user sees nothing in either place unless CanManageMasters is true.
        /// See POSBranchScope, which is what actually enforces this.
        /// </summary>
        public List<int> BranchIDs { get; set; } = new List<int>();

        public const string SessionKey = "POSUser";

        public static POSUser Current
        {
            get
            {
                return HttpContext.Current != null && HttpContext.Current.Session != null
                     ? HttpContext.Current.Session[SessionKey] as POSUser
                     : null;
            }
        }

        public bool Has(POSPermission p)
        {
            switch (p)
            {
                case POSPermission.ChangeStatus:  return CanChangeStatus;
                case POSPermission.Cancel:        return CanCancel;
                case POSPermission.Refund:        return CanRefund;
                case POSPermission.Transfer:      return CanTransfer;
                case POSPermission.TakePayment:   return CanTakePayment;
                case POSPermission.ViewReports:   return CanViewReports;
                case POSPermission.EndDay:        return CanEndDay;
                case POSPermission.ManageMasters: return CanManageMasters;
                default:                          return true;   // None
            }
        }
    }

    public enum POSPermission
    {
        None, ChangeStatus, Cancel, Refund, Transfer, TakePayment, ViewReports, EndDay, ManageMasters
    }

    /// <summary>
    /// Put [POSAuthorize] on a controller to require a login, and
    /// [POSAuthorize(POSPermission.Cancel)] on an action to require a permission.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class POSAuthorizeAttribute : ActionFilterAttribute
    {
        private readonly POSPermission _permission;

        public POSAuthorizeAttribute() : this(POSPermission.None) { }
        public POSAuthorizeAttribute(POSPermission permission) { _permission = permission; }

        public override void OnActionExecuting(ActionExecutingContext ctx)
        {
            var user = POSUser.Current;
            bool isAjax = ctx.HttpContext.Request.IsAjaxRequest();

            if (user == null)
            {
                // An expired session must not answer an AJAX call with a login
                // PAGE -- the grid would try to parse HTML as JSON and fail with
                // a meaningless error. Return 401 and let the client redirect.
                if (isAjax)
                {
                    ctx.HttpContext.Response.StatusCode = 401;
                    ctx.Result = new JsonResult
                    {
                        Data = new { Message = "Unauthorized", Redirect = "/POS/Auth/Login" },
                        JsonRequestBehavior = JsonRequestBehavior.AllowGet
                    };
                }
                else
                {
                    string ret = ctx.HttpContext.Request.RawUrl;
                    ctx.Result = new RedirectResult("/POS/Auth/Login?returnUrl=" + HttpUtility.UrlEncode(ret));
                }
                return;
            }

            if (_permission != POSPermission.None && !user.Has(_permission))
            {
                ctx.HttpContext.Response.StatusCode = 403;
                ctx.Result = new JsonResult
                {
                    Data = new { Message = "Forbidden", Detail = "Your role does not allow this action." },
                    JsonRequestBehavior = JsonRequestBehavior.AllowGet
                };
                return;
            }

            base.OnActionExecuting(ctx);
        }
    }

    /// <summary>
    /// Narrows a branch-ID filter down to what the current user is actually
    /// allowed to see, for the Order List and Dashboard reports.
    ///
    ///   - A CanManageMasters user (today: Administrator) is never narrowed -
    ///     whatever they asked for is returned unchanged, including "nothing
    ///     asked for" (null/blank), which every existing branch-filtered proc
    ///     already treats as "no restriction".
    ///   - Anyone else is confined to POSUser.BranchIDs: an empty request
    ///     becomes their full assigned set; a specific request becomes the
    ///     overlap between what they asked for and what they are assigned.
    ///   - A user with NO assigned branches - or a request that does not
    ///     overlap their assigned set at all - gets back "-1", a CSV that
    ///     cannot match any real dbo.tblbranch.id. That lets every existing
    ///     "@BranchIDs IN (SELECT value FROM STRING_SPLIT(...))"-style proc
    ///     correctly return zero rows without any of those procs changing.
    /// </summary>
    public static class POSBranchScope
    {
        public const string NoAccessCsv = "-1";

        public static string ResolveCsv(POSUser user, string requestedCsv)
        {
            if (user == null || user.CanManageMasters) return requestedCsv;

            var assigned = user.BranchIDs;
            if (assigned == null || assigned.Count == 0) return NoAccessCsv;

            if (string.IsNullOrWhiteSpace(requestedCsv))
                return string.Join(",", assigned);

            var requested = requestedCsv.Split(',')
                .Select(s => { int n; return int.TryParse(s.Trim(), out n) ? (int?)n : null; })
                .Where(n => n.HasValue)
                .Select(n => n.Value);

            var effective = requested.Intersect(assigned).ToList();
            return effective.Count > 0 ? string.Join(",", effective) : NoAccessCsv;
        }
    }

    namespace Controllers
    {
        public class AuthController : Controller
        {
            [HttpGet]
            public ActionResult Login(string returnUrl)
            {
                ViewBag.ReturnUrl = returnUrl;
                return View();
            }

            [HttpPost]
            [ValidateAntiForgeryToken]
            public ActionResult Login(string username, string password, string returnUrl)
            {
                if (string.IsNullOrWhiteSpace(username) || string.IsNullOrWhiteSpace(password))
                {
                    ViewBag.Error = "Enter a username and password.";
                    ViewBag.ReturnUrl = returnUrl;
                    return View();
                }

                try
                {
                    SqlParameter[] spa =
                    {
                        new SqlParameter("@Username", SqlDbType.NVarChar, 50) { Value = username },
                        new SqlParameter("@Password", SqlDbType.NVarChar, 50) { Value = password }
                    };

                    DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_Login", spa);

                    if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    {
                        // One message for both failure modes, so the form cannot
                        // be used to work out which usernames exist.
                        ViewBag.Error = "Invalid username or password.";
                        ViewBag.ReturnUrl = returnUrl;
                        return View();
                    }

                    DataRow r = ds.Tables[0].Rows[0];
                    var user = new POSUser
                    {
                        UserID           = Convert.ToInt32(r["UserID"]),
                        UserName         = Convert.ToString(r["UserName"]),
                        LoginName        = Convert.ToString(r["LoginName"]),
                        BrandID          = r["BrandID"] != DBNull.Value ? Convert.ToInt32(r["BrandID"]) : 0,
                        RoleID           = Convert.ToInt32(r["RoleID"]),
                        RoleName         = Convert.ToString(r["RoleName"]),
                        CanChangeStatus  = Convert.ToBoolean(r["CanChangeStatus"]),
                        CanCancel        = Convert.ToBoolean(r["CanCancel"]),
                        CanRefund        = Convert.ToBoolean(r["CanRefund"]),
                        CanTransfer      = Convert.ToBoolean(r["CanTransfer"]),
                        CanTakePayment   = Convert.ToBoolean(r["CanTakePayment"]),
                        CanViewReports   = Convert.ToBoolean(r["CanViewReports"]),
                        CanEndDay        = Convert.ToBoolean(r["CanEndDay"]),
                        CanManageMasters = Convert.ToBoolean(r["CanManageMasters"])
                    };

                    // Order List / Dashboard branch access - result set 1.
                    // Absent on a database where POS_34 has not run yet, so
                    // this does not assume it is there.
                    if (ds.Tables.Count > 1)
                    {
                        foreach (DataRow br in ds.Tables[1].Rows)
                        {
                            if (br["BranchID"] != DBNull.Value)
                                user.BranchIDs.Add(Convert.ToInt32(br["BranchID"]));
                        }
                    }

                    // New session ID on login: without this, a session fixed
                    // before login stays valid afterwards (session fixation).
                    Session.Clear();
                    Session[POSUser.SessionKey] = user;

                    // Only ever redirect to a local path. An open redirect here
                    // would let a crafted link bounce a signed-in operator to an
                    // external lookalike page.
                    if (!string.IsNullOrEmpty(returnUrl) && Url.IsLocalUrl(returnUrl))
                        return Redirect(returnUrl);

                    return RedirectToAction("Index", "Dashboard", new { area = "POS" });
                }
                catch (Exception ex)
                {
                    DB.AuditTrail(ex, "POS.AuthController", "Login", null);
                    ViewBag.Error = "Login failed. Please try again.";
                    ViewBag.ReturnUrl = returnUrl;
                    return View();
                }
            }

            [HttpGet]
            public ActionResult Logout()
            {
                Session.Clear();
                Session.Abandon();
                return RedirectToAction("Login");
            }
        }
    }
}
