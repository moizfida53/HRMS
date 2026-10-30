#nullable disable
//==============================================================================
//  Areas/POS/POSAuth.cs  (moved from the old ItemManagement project)
//------------------------------------------------------------------------------
//  The POS no longer has its own login page or session user. Everyone signs in
//  through HRMS (/account/login); the POS operator is worked out per request
//  from that sign-in:
//
//    - who:          Security.Users (DisplayName, Username, BrandID)
//    - what:         the 8 POS flags of the user's QR role (dbo.fn_QR_RoleFlags,
//                    merge script 02), plus any POS_* permission an HRMS role
//                    gives them. SYSTEM_ADMIN gets every flag.
//    - which branch: dbo.tblPOS_UserBranch_Map (Order List / Dashboard scope)
//
//  Permissions are still re-checked SERVER SIDE on every action by
//  [POSAuthorize(...)] - hiding a button is presentation, not security.
//==============================================================================

using System;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Security.Claims;
using HRMS.Web.Areas.Items.Legacy;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace HRMS.Web.Areas.POS
{
    /// <summary>The signed-in POS operator for the current request.</summary>
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
        /// Branches (dbo.tblbranch.id) this user may see in the Order List and
        /// Dashboard. Empty = nothing, unless CanManageMasters (see POSBranchScope).
        /// </summary>
        public List<int> BranchIDs { get; set; } = new List<int>();

        /// <summary>True when the user holds at least one POS permission (or is an administrator).</summary>
        public bool HasAnyPosAccess =>
            CanChangeStatus || CanCancel || CanRefund || CanTransfer || CanTakePayment
            || CanViewReports || CanEndDay || CanManageMasters;

        private static IHttpContextAccessor _accessor;

        /// <summary>Called once from Program.cs so the old static POSUser.Current keeps working.</summary>
        public static void Configure(IHttpContextAccessor accessor) => _accessor = accessor;

        /// <summary>The operator for the current request; null when nobody is signed in.</summary>
        public static POSUser Current
        {
            get
            {
                var http = _accessor?.HttpContext;
                return http == null ? null : For(http);
            }
        }

        public static POSUser For(HttpContext http)
        {
            if (http.Items.TryGetValue(typeof(POSUser), out var cached)) return cached as POSUser;

            POSUser user = null;
            var principal = http.User;
            if (principal.Identity?.IsAuthenticated == true
                && long.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
            {
                user = Load(userId, principal);
            }

            http.Items[typeof(POSUser)] = user;
            return user;
        }

        private static POSUser Load(long userId, ClaimsPrincipal principal)
        {
            string id = userId.ToString(CultureInfo.InvariantCulture);
            var ds = DB.GetData(
                "SELECT UserID = CAST(u.UserId AS INT), UserName = ISNULL(NULLIF(u.DisplayName, N''), u.Username), " +
                "       LoginName = u.Username, BrandID = ISNULL(TRY_CAST(u.BrandID AS INT), 0), " +
                "       RoleID = ISNULL(qr.LegacyRoleId, 0), " +
                // as sp_POS_Login: a QR Menu user without a POS role works as a Cashier
                "       RoleName = ISNULL(f.RoleName, CASE WHEN u.IsQrMenuUser = 1 THEN N'Cashier' ELSE N'' END), " +
                "       CanChangeStatus = ISNULL(f.CanChangeStatus, ISNULL(u.IsQrMenuUser, 0)), CanCancel = ISNULL(f.CanCancel, 0), " +
                "       CanRefund = ISNULL(f.CanRefund, 0), CanTransfer = ISNULL(f.CanTransfer, 0), " +
                "       CanTakePayment = ISNULL(f.CanTakePayment, ISNULL(u.IsQrMenuUser, 0)), CanViewReports = ISNULL(f.CanViewReports, 0), " +
                "       CanEndDay = ISNULL(f.CanEndDay, 0), CanManageMasters = ISNULL(f.CanManageMasters, 0) " +
                "FROM Security.Users u " +
                "OUTER APPLY dbo.fn_QR_UserRole(u.UserId) qr " +
                "OUTER APPLY dbo.fn_QR_RoleFlags(qr.LegacyRoleId) f " +
                "WHERE u.UserId = " + id + " AND u.Deleted = 0; " +
                "SELECT BranchID FROM dbo.tblPOS_UserBranch_Map WHERE UserID = " + id + ";");

            if (ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0) return null;

            var r = ds.Tables[0].Rows[0];
            var user = new POSUser
            {
                UserID = Convert.ToInt32(r["UserID"]),
                UserName = Convert.ToString(r["UserName"]),
                LoginName = Convert.ToString(r["LoginName"]),
                BrandID = Convert.ToInt32(r["BrandID"]),
                RoleID = Convert.ToInt32(r["RoleID"]),
                RoleName = Convert.ToString(r["RoleName"]),
                CanChangeStatus = Convert.ToBoolean(r["CanChangeStatus"]),
                CanCancel = Convert.ToBoolean(r["CanCancel"]),
                CanRefund = Convert.ToBoolean(r["CanRefund"]),
                CanTransfer = Convert.ToBoolean(r["CanTransfer"]),
                CanTakePayment = Convert.ToBoolean(r["CanTakePayment"]),
                CanViewReports = Convert.ToBoolean(r["CanViewReports"]),
                CanEndDay = Convert.ToBoolean(r["CanEndDay"]),
                CanManageMasters = Convert.ToBoolean(r["CanManageMasters"])
            };
            if (ds.Tables.Count > 1)
                foreach (System.Data.DataRow br in ds.Tables[1].Rows)
                    if (br["BranchID"] != DBNull.Value) user.BranchIDs.Add(Convert.ToInt32(br["BranchID"]));

            // POS_* permissions given through an HRMS role count too; SYSTEM_ADMIN gets everything.
            var perms = principal.FindAll(HrmsClaims.Permission).Select(c => c.Value)
                                 .ToHashSet(StringComparer.OrdinalIgnoreCase);
            bool admin = perms.Contains("SYSTEM_ADMIN");
            user.CanChangeStatus  |= admin || perms.Contains("POS_CHANGE_STATUS");
            user.CanCancel        |= admin || perms.Contains("POS_CANCEL");
            user.CanRefund        |= admin || perms.Contains("POS_REFUND");
            user.CanTransfer      |= admin || perms.Contains("POS_TRANSFER");
            user.CanTakePayment   |= admin || perms.Contains("POS_TAKE_PAYMENT");
            user.CanViewReports   |= admin || perms.Contains("POS_VIEW_REPORTS");
            user.CanEndDay        |= admin || perms.Contains("POS_END_DAY");
            user.CanManageMasters |= admin || perms.Contains("POS_MANAGE_MASTERS");
            if (admin && string.IsNullOrEmpty(user.RoleName)) user.RoleName = "Administrator";
            return user;
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
                default:                          return HasAnyPosAccess;   // None = "any POS access"
            }
        }
    }

    public enum POSPermission
    {
        None, ChangeStatus, Cancel, Refund, Transfer, TakePayment, ViewReports, EndDay, ManageMasters
    }

    /// <summary>
    /// [POSAuthorize] on a controller requires a signed-in user with some POS access;
    /// [POSAuthorize(POSPermission.Cancel)] on an action requires that permission.
    /// Signing in itself is enforced by the HRMS global authorize filter.
    /// </summary>
    [AttributeUsage(AttributeTargets.Class | AttributeTargets.Method, AllowMultiple = false)]
    public class POSAuthorizeAttribute : ActionFilterAttribute
    {
        private readonly POSPermission _permission;

        public POSAuthorizeAttribute() : this(POSPermission.None) { }
        public POSAuthorizeAttribute(POSPermission permission) { _permission = permission; Order = -100; }

        public override void OnActionExecuting(ActionExecutingContext ctx)
        {
            // A method-level attribute replaces the class-level one for that action.
            var own = ctx.ActionDescriptor.FilterDescriptors
                         .Select(f => f.Filter).OfType<POSAuthorizeAttribute>().LastOrDefault();
            if (own != null && !ReferenceEquals(own, this)) return;

            var http = ctx.HttpContext;
            var user = POSUser.For(http);
            bool isAjax = string.Equals(http.Request.Headers["X-Requested-With"], "XMLHttpRequest", StringComparison.OrdinalIgnoreCase)
                          || http.Request.Method != HttpMethods.Get;

            if (user == null)
            {
                if (isAjax)
                {
                    http.Response.StatusCode = 401;
                    ctx.Result = new LegacyJsonResult(new { Message = "Unauthorized", Redirect = "/account/login" });
                }
                else
                {
                    ctx.Result = new RedirectResult("/account/login?returnUrl=" + Uri.EscapeDataString(http.Request.Path + http.Request.QueryString));
                }
                return;
            }

            if (!user.Has(_permission))
            {
                if (isAjax)
                {
                    http.Response.StatusCode = 403;
                    ctx.Result = new LegacyJsonResult(new { Message = "Forbidden", Detail = "Your role does not allow this action." });
                }
                else
                {
                    ctx.Result = new RedirectResult("/POS/Home/Denied");
                }
                return;
            }

            base.OnActionExecuting(ctx);
        }
    }

    /// <summary>
    /// Narrows a branch-ID filter to what the current user may see (Order List, Dashboard).
    /// CanManageMasters users are never narrowed; others are confined to BranchIDs,
    /// and "-1" (matches nothing) when they have none or ask for none of theirs.
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
                .Select(s => int.TryParse(s.Trim(), out var n) ? (int?)n : null)
                .Where(n => n.HasValue)
                .Select(n => n.Value);

            var effective = requested.Intersect(assigned).ToList();
            return effective.Count > 0 ? string.Join(",", effective) : NoAccessCsv;
        }
    }

    namespace Controllers
    {
        /// <summary>Base for every POS controller: area, legacy JSON/Session helpers, relaxed CSP.</summary>
        [Area("POS")]
        public abstract class PosController : LegacyController
        {
            /// <summary>Replaces MVC 4's !HttpContext.IsCustomErrorEnabled: SQL detail only in Development.</summary>
            protected bool IsDevelopment =>
                HttpContext?.RequestServices.GetService(typeof(Microsoft.AspNetCore.Hosting.IWebHostEnvironment))
                    is Microsoft.AspNetCore.Hosting.IWebHostEnvironment env && env.EnvironmentName == "Development";

            /// <summary>Renders a partial view to HTML (the old RenderHelper.PartialView), for JSON replies.</summary>
            protected string RenderPartialToString(string viewPath, object model)
            {
                var engine = (Microsoft.AspNetCore.Mvc.ViewEngines.ICompositeViewEngine)
                    HttpContext.RequestServices.GetService(typeof(Microsoft.AspNetCore.Mvc.ViewEngines.ICompositeViewEngine));
                var found = engine.GetView(executingFilePath: null, viewPath: viewPath, isMainPage: false);
                if (!found.Success) throw new InvalidOperationException("Partial view not found: " + viewPath);

                ViewData.Model = model;
                using var writer = new System.IO.StringWriter();
                var viewContext = new Microsoft.AspNetCore.Mvc.Rendering.ViewContext(
                    ControllerContext, found.View, ViewData, TempData, writer,
                    new Microsoft.AspNetCore.Mvc.ViewFeatures.HtmlHelperOptions());
                found.View.RenderAsync(viewContext).GetAwaiter().GetResult();
                return writer.ToString();
            }
        }

        /// <summary>/POS opens the Dine-In screen; /POS/Home/Denied explains a missing permission.</summary>
        public class HomeController : PosController
        {
            public IActionResult Index() => RedirectToAction("Index", "DineIn", new { area = "POS" });

            public IActionResult Denied() => Content(
                "<!doctype html><meta charset=utf-8><title>No access</title>" +
                "<div style=\"font-family:system-ui,sans-serif;max-width:520px;margin:80px auto;text-align:center\">" +
                "<h2>No access to this POS page</h2><p>Your role does not include this part of the POS. " +
                "Ask an administrator to give your role the POS permission it needs.</p>" +
                "<p><a href=\"/apps\">Back to apps</a></p></div>", "text/html");
        }
    }
}
