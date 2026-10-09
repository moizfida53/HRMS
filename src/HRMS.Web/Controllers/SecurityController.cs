using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Security;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Security;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Security (db/57): Create Roles - a role's access to every page and function (Read /
/// Write / Full) and its approval rights - and Manage Users - the accounts that sign in
/// (add, edit, reset password, activate / deactivate) and the roles each one has.
/// The ticks become permission codes (AccessCatalog) in Security.RolePermissions, the codes
/// sign-in loads and every controller checks; signed-in users pick them up within a minute
/// (PermissionRefresh). Roles and users are named by opaque references, never their ids.
/// </summary>
[Route("security")]
public sealed class SecurityController : Controller
{
    private const string PermRoleView = "SECURITY_ROLE_VIEW";
    private const string PermRoleEdit = "SECURITY_ROLE_EDIT";
    private const string PermRoleDelete = "SECURITY_ROLE_DELETE";
    private const string PermUserView = "SECURITY_USER_VIEW";
    private const string PermUserAssign = "SECURITY_USER_ASSIGN";
    private const string PermUserEdit = "SECURITY_USER_EDIT";
    private const string PermUserDisable = "SECURITY_USER_DISABLE";

    private readonly ISecurityAdminRepository _security;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IRefProtector _refs;
    private readonly IPasswordHasher _hasher;
    private readonly AuthenticationPolicyOptions _authPolicy;

    public SecurityController(ISecurityAdminRepository security, ILookupRepository lookups, ICurrentUser currentUser,
                              ICompanyFilter companyFilter, IRefProtector refs, IPasswordHasher hasher,
                              Microsoft.Extensions.Options.IOptions<AuthenticationPolicyOptions> authPolicy)
    {
        _hasher = hasher;
        _authPolicy = authPolicy.Value;
        _security = security;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _refs = refs;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");

    // =======================================================================
    // Create Roles
    // =======================================================================

    /// <param name="open">A role reference to open first (after a save) - mapped back to the list's own reference.</param>
    [HttpGet("roles")]
    public async Task<IActionResult> Roles(string? open)
    {
        if (!Can(PermRoleView)) return Forbid();
        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        var refs = roles.ToDictionary(r => r.RoleId, r => _refs.Protect(RefPurpose.Role, r.RoleId));
        return View("~/Views/Security/Roles.cshtml", new RolesPageModel
        {
            Roles = roles,
            Refs = refs,
            CanEdit = Can(PermRoleEdit),
            OpenRef = _refs.One(RefPurpose.Role, open) is { } openId && refs.TryGetValue((int)openId, out var openRef)
                ? openRef
                : roles.Count > 0 ? refs[(roles.FirstOrDefault(r => !r.IsSystem) ?? roles[0]).RoleId] : null
        });
    }

    /// <summary>The editor of a role (ref), or of a new one (no ref).</summary>
    [HttpPost("roles/panel")]
    public async Task<IActionResult> RolePanel([FromForm(Name = "ref")] string? roleRef)
    {
        if (!Can(PermRoleView)) return Forbid();

        RoleSummary? role = null;
        var codes = new HashSet<string>(StringComparer.Ordinal);
        if (!string.IsNullOrEmpty(roleRef))
        {
            if (_refs.One(RefPurpose.Role, roleRef) is not { } id) return NotFound();
            role = await _security.RoleAsync(OwnCompany, (int)id, Ct);
            if (role is null) return NotFound();
            codes.UnionWith(await _security.RoleCodesAsync(OwnCompany, role.RoleId, Ct));
        }
        else if (!Can(PermRoleEdit))
        {
            return Forbid();
        }

        // System Administrator holds every right (sign-in also treats it so)
        if (role?.IsSystem == true) codes.UnionWith(AccessCatalog.ManagedCodes);

        var levels = AccessCatalog.AllItems.ToDictionary(i => i.Code, i => i.LevelIn(codes));
        var approvals = AccessCatalog.Approvals.ToDictionary(a => a.Code, a =>
        {
            ISet<string> cols = new HashSet<string>(StringComparer.Ordinal);
            if (codes.Contains(a.Level1)) cols.Add("L1");
            if (codes.Contains(a.Level2)) cols.Add("L2");
            if (codes.Contains(a.Self)) cols.Add("SELF");
            return cols;
        });

        var editable = Can(PermRoleEdit) && (role is null || (role.IsEditable && !role.IsSystem));
        return PartialView("~/Views/Security/_RoleEditor.cshtml", new RoleEditorModel
        {
            Role = role,
            Ref = roleRef,
            ReadOnly = !editable,
            CanDelete = role is not null && !role.IsSystem && role.IsEditable && Can(PermRoleDelete),
            ChooseCompany = OwnCompany is null,
            Companies = OwnCompany is null ? await _lookups.GetAsync(LookupType.Company, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            Levels = levels,
            Approvals = approvals
        });
    }

    /// <summary>
    /// Save a role: its details, the level ticked per page / function ("access" = ITEM:R|W|F)
    /// and the approvals ticked ("approval" = APR:L1|L2|SELF).
    /// </summary>
    [HttpPost("roles/save")]
    public async Task<IActionResult> SaveRole([FromForm(Name = "ref")] string? roleRef, [FromForm] string? roleCode, [FromForm] string? roleName,
                                              [FromForm] string? description, [FromForm] int? companyId, [FromForm] bool isActive,
                                              [FromForm] string[]? access, [FromForm] string[]? approval)
    {
        if (!Can(PermRoleEdit)) return Denied();

        var roleId = 0;
        var current = new HashSet<string>(StringComparer.Ordinal);
        if (!string.IsNullOrEmpty(roleRef))
        {
            if (_refs.One(RefPurpose.Role, roleRef) is not { } id) return NotFoundJson();
            roleId = (int)id;
            current.UnionWith(await _security.RoleCodesAsync(OwnCompany, roleId, Ct));
        }

        var levels = new Dictionary<string, AccessLevel>(StringComparer.Ordinal);
        foreach (var entry in access ?? [])
        {
            var parts = entry.Split(':');
            if (parts.Length != 2 || AccessCatalog.Find(parts[0]) is null) continue;
            levels[parts[0]] = parts[1] switch { "F" => AccessLevel.Full, "W" => AccessLevel.Write, "R" => AccessLevel.Read, _ => AccessLevel.None };
        }
        var approvals = new Dictionary<string, ISet<string>>(StringComparer.Ordinal);
        foreach (var entry in approval ?? [])
        {
            var parts = entry.Split(':');
            if (parts.Length != 2 || parts[1] is not ("L1" or "L2" or "SELF")) continue;
            if (!approvals.TryGetValue(parts[0], out var set)) approvals[parts[0]] = set = new HashSet<string>(StringComparer.Ordinal);
            set.Add(parts[1]);
        }

        var granted = new HashSet<string>(AccessCatalog.CodesFor(levels, approvals), StringComparer.Ordinal);
        var leftAsWas = false;
        if (!IsSysAdmin)
        {
            // no escalation: a right you do not hold yourself can be neither given nor taken away
            var kept = AccessCatalog.ManagedCodes.Where(c => !Can(c)).ToList();
            var changed = kept.Any(c => granted.Contains(c) != current.Contains(c));
            granted.ExceptWith(kept);
            granted.UnionWith(kept.Where(current.Contains));
            leftAsWas = changed;
        }

        var result = await _security.SaveRoleAsync(OwnCompany, new RoleSaveRequest
        {
            RoleId = roleId,
            RoleCode = roleCode ?? string.Empty,
            RoleName = roleName ?? string.Empty,
            Description = description,
            RoleCompanyId = OwnCompany ?? (companyId is > 0 ? companyId : null),
            IsActive = isActive,
            ManagedCodes = AccessCatalog.ManagedCodes,
            GrantedCodes = granted
        }, _currentUser.UserId, Ct);

        if (!result.Success) return Json(ActionResponse.Failed(result.Message, result.ErrorCode));
        return Json(new
        {
            success = true,
            // whole sentences, so the message is translated like any other (msg.* by its English text)
            message = !leftAsWas ? result.Message
                    : roleId == 0 ? "Role created. Rights you do not hold yourself were left out."
                    : "Role saved. Rights you do not hold yourself were left as they were.",
            id = 0,
            @ref = _refs.Protect(RefPurpose.Role, result.Id)
        });
    }

    [HttpPost("roles/delete")]
    public async Task<IActionResult> DeleteRole([FromForm(Name = "ref")] string? roleRef)
    {
        if (!Can(PermRoleDelete)) return Denied();
        if (_refs.One(RefPurpose.Role, roleRef) is not { } id) return NotFoundJson();
        var result = await _security.DeleteRoleAsync(OwnCompany, (int)id, _currentUser.UserId, Ct);
        return Json(result.Success ? ActionResponse.Ok(0, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    // =======================================================================
    // Manage Users - the accounts that sign in, with their roles
    // =======================================================================

    /// <summary>The old Assign Roles address: role assignment is part of Manage Users now.</summary>
    [HttpGet("assign")]
    public IActionResult Assign() => RedirectToAction(nameof(Users));

    [HttpGet("users")]
    public async Task<IActionResult> Users()
    {
        if (!Can(PermUserView)) return Forbid();
        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        return View("~/Views/Security/Users.cshtml", new UsersPageModel
        {
            Roles = roles.Select(r => (_refs.Protect(RefPurpose.Role, r.RoleId), r.RoleName)).ToList(),
            CanCreate = Can(PermUserEdit)
        });
    }

    /// <summary>The users (search, role filter: a role reference or "none", page).</summary>
    [HttpPost("users/grid")]
    public async Task<IActionResult> UsersGrid([FromForm] string? search, [FromForm] string? role, [FromForm] int page = 1)
    {
        if (!Can(PermUserView)) return Forbid();
        int? roleFilter = role == "none" ? 0 : _refs.One(RefPurpose.Role, role) is { } rid ? (int)rid : null;
        var result = await _security.UsersAsync(OwnCompany, search, roleFilter, page, 25, Ct);
        return PartialView("~/Views/Security/_UsersGrid.cshtml", new UsersGridModel
        {
            Page = result,
            Refs = result.Items.ToDictionary(u => u.UserId, u => _refs.Protect(RefPurpose.User, u.UserId)),
            CanEdit = Can(PermUserEdit) || Can(PermUserAssign),
            CanDisable = Can(PermUserDisable),
            CurrentUserId = _currentUser.UserId,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(role),
            ManyCompanies = OwnCompany is null && _companyFilter.SelectedIds.Count != 1
        });
    }

    /// <summary>The user form (popup): a user (ref), or a new one (no ref).</summary>
    [HttpPost("users/panel")]
    public async Task<IActionResult> UserPanel([FromForm(Name = "ref")] string? userRef)
    {
        if (!Can(PermUserView)) return Forbid();

        UserRoleRow? user = null;
        if (!string.IsNullOrEmpty(userRef))
        {
            if (await FindUserAsync(userRef) is not { } found) return NotFound();
            user = found;
        }
        else if (!Can(PermUserEdit))
        {
            return Forbid();
        }

        var held = user?.RoleIdList.ToHashSet() ?? [];
        var options = new List<RoleOption>();
        foreach (var r in await _security.RolesAsync(OwnCompany, null, Ct))
        {
            options.Add(new RoleOption(_refs.Protect(RefPurpose.Role, r.RoleId), r, held.Contains(r.RoleId), await MayAssignAsync(r)));
        }

        var companyId = user?.CompanyId ?? OwnCompany;
        var manageable = user is null || await MayManageAsync(user);
        return PartialView("~/Views/Security/_UserForm.cshtml", new UserFormModel
        {
            User = user,
            Ref = user is null ? null : userRef,
            Roles = options,
            ChooseCompany = OwnCompany is null,
            AllowAllCompanies = IsSysAdmin,
            Companies = OwnCompany is null ? await _lookups.GetAsync(LookupType.Company, cancellationToken: Ct) : Array.Empty<LookupItem>(),
            CompanyId = companyId,
            Employees = await LinkedEmployeeOptionsAsync(companyId, user),
            CanEditAccount = Can(PermUserEdit) && manageable,
            CanAssign = Can(PermUserAssign),
            CanDisable = Can(PermUserDisable) && manageable && user?.UserId != _currentUser.UserId,
            SimplePassword = _authPolicy.SimplePassword,
            IsSelf = user is not null && user.UserId == _currentUser.UserId,
            Locked = user is not null && !manageable
        });
    }

    /// <summary>The employees of a company, for the "linked employee" list (references, never ids).</summary>
    [HttpPost("users/employees")]
    public async Task<IActionResult> UserEmployees([FromForm] int? companyId)
    {
        if (!Can(PermUserEdit)) return Forbid();
        var company = _currentUser.LookupCompany(companyId);
        if (company is null) return Json(Array.Empty<object>());
        var items = await EmployeeOptionsAsync(company.Value, null);
        return Json(items.Select(e => new { value = e.Ref, text = e.Text }));
    }

    /// <summary>
    /// Save a user: the account (name, email, company, linked employee, active, a new password)
    /// and the roles ticked ("roles" = role references) - one transaction.
    /// </summary>
    [HttpPost("users/save")]
    public async Task<IActionResult> SaveUser([FromForm(Name = "ref")] string? userRef, [FromForm] string? username, [FromForm] string? email,
                                              [FromForm] int? companyId, [FromForm] string? employee, [FromForm] bool isActive,
                                              [FromForm] bool resetPassword, [FromForm] string? password, [FromForm] string? confirmPassword,
                                              [FromForm] bool mustChangePassword, [FromForm] string[]? roles)
    {
        if (!Can(PermUserEdit) && !Can(PermUserAssign)) return Denied();

        UserRoleRow? user = null;
        if (!string.IsNullOrEmpty(userRef))
        {
            if (await FindUserAsync(userRef) is not { } found) return NotFoundJson();
            user = found;
        }
        else if (!Can(PermUserEdit))
        {
            return Denied();
        }

        var visible = await _security.RolesAsync(OwnCompany, null, Ct);
        var held = user?.RoleIdList.ToHashSet() ?? [];
        var wanted = new HashSet<int>();
        if (Can(PermUserAssign))
        {
            foreach (var r in roles ?? [])
            {
                if (_refs.One(RefPurpose.Role, r) is { } id) wanted.Add((int)id);
            }
            // no escalation: a role holding rights you do not have can be neither given nor taken away
            foreach (var role in visible)
            {
                if (wanted.Contains(role.RoleId) == held.Contains(role.RoleId) || await MayAssignAsync(role)) continue;
                return Json(ActionResponse.Failed("You can only give or remove roles whose rights you hold yourself.", "FORBIDDEN"));
            }
        }
        else
        {
            wanted.UnionWith(held);   // no right to change roles: they stay as they are
        }

        // only roles can change (Assign right only): the account stays as it is
        if (!Can(PermUserEdit))
        {
            var rolesOnly = await _security.SetUserRolesAsync(OwnCompany, user!.UserId, wanted, IsSysAdmin, _currentUser.UserId, Ct);
            return Json(rolesOnly.Success ? ActionResponse.Ok(0, rolesOnly.Message) : ActionResponse.Failed(rolesOnly.Message, rolesOnly.ErrorCode));
        }

        // a non-administrator cannot take over an account with more rights than their own
        if (user is not null && !await MayManageAsync(user))
        {
            return Json(ActionResponse.Failed("You can only change accounts whose rights you hold yourself.", "FORBIDDEN"));
        }

        var errors = new Dictionary<string, string[]>(StringComparer.Ordinal);
        if (string.IsNullOrWhiteSpace(username)) errors["username"] = ["Enter the user name."];

        int? company = OwnCompany ?? (companyId is > 0 ? companyId : null);
        if (company is null && !IsSysAdmin) errors["companyId"] = ["Choose the user's company."];

        long? employeeId = null;
        if (!string.IsNullOrEmpty(employee))
        {
            if (_refs.One(RefPurpose.UserEmployee, employee) is { } eid) employeeId = eid;
            else errors["employee"] = ["Choose the employee again."];
        }

        string? hash = null, plain = null;
        var setPassword = user is null || resetPassword;
        if (setPassword)
        {
            var pw = password ?? string.Empty;
            if (pw.Length == 0) errors["password"] = ["Enter a password."];
            else if (PasswordProblem(pw) is { } problem) errors["password"] = [problem];
            else if (pw != confirmPassword) errors["confirmPassword"] = ["The two passwords don't match."];
            else
            {
                hash = _hasher.Hash(pw);
                plain = _authPolicy.SimplePassword && pw.Length <= AuthenticationPolicyOptions.SimplePasswordMaxLength ? pw : null;
            }
        }
        if (errors.Count > 0) return Json(ActionResponse.Invalid(errors));

        // the Active switch needs the deactivate right; without it the account keeps its state
        var active = Can(PermUserDisable) ? isActive : user?.IsActive ?? true;

        var result = await _security.SaveUserAsync(OwnCompany, new UserSaveRequest
        {
            UserId = user?.UserId ?? 0,
            Username = username!.Trim(),
            Email = email,
            UserCompanyId = company,
            EmployeeId = employeeId,
            IsActive = active,
            PasswordHash = hash,
            PlainPassword = plain,
            MustChangePassword = mustChangePassword,
            RoleIds = wanted
        }, IsSysAdmin, _currentUser.UserId, Ct);

        if (!result.Success) return Json(ActionResponse.Failed(result.Message, result.ErrorCode));
        return Json(ActionResponse.Ok(0, result.Message));
    }

    /// <summary>Activate or deactivate a user (a deactivated user is signed out within a minute).</summary>
    [HttpPost("users/toggle")]
    public async Task<IActionResult> ToggleUser([FromForm(Name = "ref")] string? userRef, [FromForm] bool active)
    {
        if (!Can(PermUserDisable)) return Denied();
        if (await FindUserAsync(userRef) is not { } user) return NotFoundJson();
        if (!await MayManageAsync(user))
        {
            return Json(ActionResponse.Failed("You can only change accounts whose rights you hold yourself.", "FORBIDDEN"));
        }
        var result = await _security.SetUserActiveAsync(OwnCompany, user.UserId, active, IsSysAdmin, _currentUser.UserId, Ct);
        return Json(result.Success ? ActionResponse.Ok(0, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    // =======================================================================
    // helpers
    // =======================================================================

    private async Task<UserRoleRow?> FindUserAsync(string? userRef)
    {
        // the user a reference names, if in the signed-in user's company scope
        return _refs.One(RefPurpose.User, userRef) is { } id ? await _security.UserAsync(OwnCompany, id, Ct) : null;
    }

    /// <summary>A System Administrator may assign any role; anyone else only roles whose rights they hold.</summary>
    private async Task<bool> MayAssignAsync(RoleSummary role)
    {
        if (IsSysAdmin) return true;
        if (role.IsSystem) return false;
        var codes = await _security.RoleCodesAsync(OwnCompany, role.RoleId, Ct);
        return codes.All(Can);
    }

    /// <summary>
    /// A System Administrator may manage any account; anyone else only accounts whose roles
    /// carry no right they lack themselves (never a System Administrator's).
    /// </summary>
    private async Task<bool> MayManageAsync(UserRoleRow user)
    {
        if (IsSysAdmin) return true;
        if (user.UserId == _currentUser.UserId) return true;
        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        var byId = roles.ToDictionary(r => r.RoleId);
        foreach (var id in user.RoleIdList)
        {
            // a role the caller cannot even see (another company's) is not theirs to judge
            if (!byId.TryGetValue(id, out var role) || !await MayAssignAsync(role)) return false;
        }
        return true;
    }

    /// <summary>The employees of a company: reference, "code - name", and whether it is the one linked now.</summary>
    private async Task<IReadOnlyList<(string Ref, string Text, bool Selected)>> EmployeeOptionsAsync(int companyId, long? selected)
    {
        if (!_currentUser.Allows(companyId)) return Array.Empty<(string, string, bool)>();
        var items = await _lookups.GetAsync(LookupType.Employee, companyId, cancellationToken: Ct);
        return items.Select(e => (_refs.Protect(RefPurpose.UserEmployee, e.Id),
                                  string.IsNullOrWhiteSpace(e.Code) ? e.Text : $"{e.Code} - {e.Text}",
                                  selected == e.Id)).ToList();
    }

    /// <summary>
    /// The employees of the user's company, and always the one linked now - even when the
    /// list leaves it out (e.g. no longer active) - so saving never unlinks it by accident.
    /// </summary>
    private async Task<IReadOnlyList<(string Ref, string Text, bool Selected)>> LinkedEmployeeOptionsAsync(int? companyId, UserRoleRow? user)
    {
        if (companyId is not { } company) return Array.Empty<(string, string, bool)>();
        var options = (await EmployeeOptionsAsync(company, user?.EmployeeId)).ToList();
        if (user?.EmployeeId is { } linked && !options.Any(o => o.Selected))
        {
            var text = string.IsNullOrWhiteSpace(user.EmployeeCode) ? user.DisplayName ?? user.Username : $"{user.EmployeeCode} - {user.DisplayName}";
            options.Insert(0, (_refs.Protect(RefPurpose.UserEmployee, linked), text, true));
        }
        return options;
    }

    /// <summary>The same rules as Change Password (simple mode: at most 50 characters).</summary>
    private string? PasswordProblem(string password)
    {
        if (_authPolicy.SimplePassword)
        {
            return password.Length > AuthenticationPolicyOptions.SimplePasswordMaxLength ? "Use at most 50 characters." : null;
        }
        if (password.Length < 8) return "Use at least 8 characters.";
        if (password.Length > 128) return "Use at most 128 characters.";
        if (!password.Any(char.IsUpper) || !password.Any(char.IsLower) || !password.Any(char.IsDigit))
        {
            return "Use upper- and lower-case letters and at least one number.";
        }
        return null;
    }

    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
    private IActionResult NotFoundJson() => Json(ActionResponse.Failed("That record was not found. Refresh and try again.", "NOT_FOUND"));
}
