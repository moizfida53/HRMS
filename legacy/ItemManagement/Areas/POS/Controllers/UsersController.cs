//==============================================================================
//  Areas/POS/Controllers/UsersController.cs
//------------------------------------------------------------------------------
//  Admin-only User Management: list every tblUser row, add a user, update a
//  user, and assign / re-assign a role.
//
//  Gated on POSPermission.ManageMasters - the same permission that already
//  gates the "Settings" drawer link. Today only the Administrator role
//  (RoleID 1) has CanManageMasters = 1, so this is Admin-only in practice,
//  and it stays correct if another role is ever granted the same permission
//  instead of hard-coding a role name or ID here.
//
//  Passwords: a value typed into Add/Update User is salted and hashed
//  (PasswordHash/PasswordSalt) by sp_POS_User_Save - this controller never
//  sees or stores plain text, and never returns a password/hash to the
//  browser. See DBScripts/POS_33_UserManagement.sql for the full story.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Controllers\UsersController.cs" />
//==============================================================================

using System;
using System.Collections.Generic;
using System.Data;
using System.Data.SqlClient;
using System.Web.Mvc;
using Jar.Helper;

namespace Jar.Areas.POS.Controllers
{
    [POSAuthorize(POSPermission.ManageMasters)]
    public class UsersController : Controller
    {
        public ActionResult Index()
        {
            ViewBag.User = POSUser.Current;
            return View();
        }

        // ---------------------------------------------------------------------
        // Grid + role dropdown, one round trip
        // ---------------------------------------------------------------------
        [HttpGet]
        public JsonResult List()
        {
            try
            {
                DataSet users = DB.ExecuteStoredProcDataSet("sp_POS_User_List");
                DataSet roles = DB.ExecuteStoredProcDataSet("sp_POS_Role_List");

                return JsonGet(new
                {
                    Message = "Success",
                    Users   = users != null && users.Tables.Count > 0 ? Rows(users.Tables[0]) : new List<Dictionary<string, object>>(),
                    Roles   = roles != null && roles.Tables.Count > 0 ? Rows(roles.Tables[0]) : new List<Dictionary<string, object>>(),
                    // Order List / Dashboard branch access, per user - result
                    // set 1 of sp_POS_User_List. Empty (not missing) on a
                    // database where POS_34 has not run yet.
                    UserBranches = users != null && users.Tables.Count > 1 ? Rows(users.Tables[1]) : new List<Dictionary<string, object>>()
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.UsersController", "List", null);
                return JsonGet(new { Message = "Fail" });
            }
        }

        // ---------------------------------------------------------------------
        // Add User (userId == 0) and Update User (userId > 0), including the
        // role and the Order List / Dashboard branch access picked on the
        // same form. newPassword is optional on update - left blank, the
        // password is not touched. branchIds is always the COMPLETE set the
        // form is showing checked, not a delta - see sp_POS_User_Save.
        // ---------------------------------------------------------------------
        // No [ValidateAntiForgeryToken]: none of this Area's other AJAX POST
        // actions carry a token either (see OrdersController) - [POSAuthorize]
        // plus the session cookie is the existing trust boundary here.
        [HttpPost]
        public JsonResult Save(int userId, string name, string username, string newPassword, int? branchId, int roleId, string branchIds)
        {
            try
            {
                var actor = POSUser.Current;
                SqlParameter[] spa =
                {
                    P("@UserID",        SqlDbType.Int,        0, userId > 0 ? (object)userId : null),
                    P("@Name",          SqlDbType.NVarChar, 100, name),
                    P("@Username",      SqlDbType.NVarChar,  50, username),
                    P("@NewPassword",   SqlDbType.NVarChar,  50, newPassword),
                    P("@BranchID",      SqlDbType.Int,        0, branchId),
                    P("@RoleID",        SqlDbType.Int,        0, roleId),
                    P("@BranchIDs",     SqlDbType.NVarChar, 1000, branchIds),
                    P("@ActorUserID",   SqlDbType.Int,        0, actor != null ? (object)actor.UserID : null),
                    P("@ActorUserName", SqlDbType.NVarChar, 100, actor != null ? actor.UserName : null)
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_User_Save", spa);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", Detail = "No response from the database." });

                DataRow r = ds.Tables[0].Rows[0];
                bool ok = Convert.ToString(r["Message"]) == "Success";

                return JsonGet(new
                {
                    Message = ok ? "Success" : "Fail",
                    UserID  = r["UserID"] != DBNull.Value ? Convert.ToInt32(r["UserID"]) : 0,
                    Detail  = r.Table.Columns.Contains("ErrorMessage") && r["ErrorMessage"] != DBNull.Value
                              ? Convert.ToString(r["ErrorMessage"]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.UsersController", "Save", null);
                return JsonGet(new { Message = "Fail", Detail = "The user could not be saved." });
            }
        }

        // ---------------------------------------------------------------------
        // Quick Assign / Re-Assign Role from the grid row, without opening the
        // full edit form.
        // ---------------------------------------------------------------------
        [HttpPost]
        public JsonResult ChangeRole(int userId, int roleId)
        {
            try
            {
                var actor = POSUser.Current;
                SqlParameter[] spa =
                {
                    P("@UserID",        SqlDbType.Int,        0, userId),
                    P("@RoleID",        SqlDbType.Int,        0, roleId),
                    P("@ActorUserID",   SqlDbType.Int,        0, actor != null ? (object)actor.UserID : null),
                    P("@ActorUserName", SqlDbType.NVarChar, 100, actor != null ? actor.UserName : null)
                };

                DataSet ds = DB.ExecuteStoredProcDataSet("sp_POS_User_ChangeRole", spa);
                if (ds == null || ds.Tables.Count == 0 || ds.Tables[0].Rows.Count == 0)
                    return JsonGet(new { Message = "Fail", Detail = "No response from the database." });

                DataRow r = ds.Tables[0].Rows[0];
                bool ok = Convert.ToString(r["Message"]) == "Success";

                return JsonGet(new
                {
                    Message = ok ? "Success" : "Fail",
                    Detail  = r.Table.Columns.Contains("ErrorMessage") && r["ErrorMessage"] != DBNull.Value
                              ? Convert.ToString(r["ErrorMessage"]) : null
                });
            }
            catch (Exception ex)
            {
                DB.AuditTrail(ex, "POS.UsersController", "ChangeRole", null);
                return JsonGet(new { Message = "Fail", Detail = "The role could not be changed." });
            }
        }

        // ---------------------------------------------------------------------
        // helpers (same pattern as OrdersController - not shared, each
        // controller in this Area keeps its own copy)
        // ---------------------------------------------------------------------
        private JsonResult JsonGet(object data)
        {
            return new JsonResult
            {
                Data = data,
                JsonRequestBehavior = JsonRequestBehavior.AllowGet,
                MaxJsonLength = int.MaxValue
            };
        }

        private static SqlParameter P(string name, SqlDbType type, int size, object value)
        {
            var p = size > 0 ? new SqlParameter(name, type, size) : new SqlParameter(name, type);
            if (value == null) { p.Value = DBNull.Value; return p; }
            var s = value as string;
            p.Value = (s != null && s.Length == 0) ? DBNull.Value : value;
            return p;
        }

        private static List<Dictionary<string, object>> Rows(DataTable dt)
        {
            var list = new List<Dictionary<string, object>>(dt.Rows.Count);
            foreach (DataRow r in dt.Rows)
            {
                var d = new Dictionary<string, object>(dt.Columns.Count);
                foreach (DataColumn c in dt.Columns)
                {
                    object v = r[c];
                    d[c.ColumnName] = v == DBNull.Value ? null : v;
                }
                list.Add(d);
            }
            return list;
        }
    }
}
