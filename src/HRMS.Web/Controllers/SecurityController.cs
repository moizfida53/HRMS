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
/// Write / Full) and its approval rights - and Assign Roles - which roles each user has.
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

    private readonly ISecurityAdminRepository _security;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IRefProtector _refs;

    public SecurityController(ISecurityAdminRepository security, ILookupRepository lookups, ICurrentUser currentUser,
                              ICompanyFilter companyFilter, IRefProtector refs)
    {
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

    [HttpGet("roles")]
    public async Task<IActionResult> Roles()
    {
        if (!Can(PermRoleView)) return Forbid();
        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        var refs = roles.ToDictionary(r => r.RoleId, r => _refs.Protect(RefPurpose.Role, r.RoleId));
        return View("~/Views/Security/Roles.cshtml", new RolesPageModel
        {
            Roles = roles,
            Refs = refs,
            CanEdit = Can(PermRoleEdit),
            OpenRef = roles.Count > 0 ? refs[(roles.FirstOrDefault(r => !r.IsSystem) ?? roles[0]).RoleId] : null
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
    // Assign Roles
    // =======================================================================

    [HttpGet("assign")]
    public async Task<IActionResult> Assign()
    {
        if (!Can(PermUserView)) return Forbid();
        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        return View("~/Views/Security/Assign.cshtml", new AssignPageModel
        {
            Roles = roles.Select(r => (_refs.Protect(RefPurpose.Role, r.RoleId), r.RoleName)).ToList(),
            CanAssign = Can(PermUserAssign)
        });
    }

    /// <summary>The users (search, role filter: a role reference or "none", page).</summary>
    [HttpPost("assign/grid")]
    public async Task<IActionResult> UsersGrid([FromForm] string? search, [FromForm] string? role, [FromForm] int page = 1)
    {
        if (!Can(PermUserView)) return Forbid();
        int? roleFilter = role == "none" ? 0 : _refs.One(RefPurpose.Role, role) is { } rid ? (int)rid : null;
        var result = await _security.UsersAsync(OwnCompany, search, roleFilter, page, 25, Ct);
        return PartialView("~/Views/Security/_UsersGrid.cshtml", new UsersGridModel
        {
            Page = result,
            Refs = result.Items.ToDictionary(u => u.UserId, u => _refs.Protect(RefPurpose.User, u.UserId)),
            CanAssign = Can(PermUserAssign),
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrEmpty(role),
            ManyCompanies = OwnCompany is null && _companyFilter.SelectedIds.Count != 1
        });
    }

    /// <summary>The roles of one user (popup).</summary>
    [HttpPost("assign/panel")]
    public async Task<IActionResult> UserPanel([FromForm(Name = "ref")] string? userRef)
    {
        if (!Can(PermUserView)) return Forbid();
        if (await FindUserAsync(userRef) is not { } user) return NotFound();

        var roles = await _security.RolesAsync(OwnCompany, null, Ct);
        var held = user.RoleIdList.ToHashSet();
        var options = new List<RoleOption>();
        foreach (var r in roles)
        {
            options.Add(new RoleOption(_refs.Protect(RefPurpose.Role, r.RoleId), r, held.Contains(r.RoleId), await MayAssignAsync(r)));
        }
        return PartialView("~/Views/Security/_UserRolesPanel.cshtml", new UserRolesPanelModel
        {
            User = user,
            Ref = userRef!,
            Roles = options,
            CanAssign = Can(PermUserAssign)
        });
    }

    [HttpPost("assign/save")]
    public async Task<IActionResult> SaveUserRoles([FromForm(Name = "ref")] string? userRef, [FromForm] string[]? roles)
    {
        if (!Can(PermUserAssign)) return Denied();
        if (await FindUserAsync(userRef) is not { } user) return NotFoundJson();

        var visible = await _security.RolesAsync(OwnCompany, null, Ct);
        var wanted = new HashSet<int>();
        foreach (var r in roles ?? [])
        {
            if (_refs.One(RefPurpose.Role, r) is { } id) wanted.Add((int)id);
        }

        // no escalation: a role holding rights you do not have can be neither given nor taken away
        var held = user.RoleIdList.ToHashSet();
        foreach (var role in visible)
        {
            if (wanted.Contains(role.RoleId) == held.Contains(role.RoleId) || await MayAssignAsync(role)) continue;
            return Json(ActionResponse.Failed("You can only give or remove roles whose rights you hold yourself.", "FORBIDDEN"));
        }

        var result = await _security.SetUserRolesAsync(OwnCompany, user.UserId, wanted, IsSysAdmin, _currentUser.UserId, Ct);
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

    private IActionResult Denied() => Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
    private IActionResult NotFoundJson() => Json(ActionResponse.Failed("That record was not found. Refresh and try again.", "NOT_FOUND"));
}
