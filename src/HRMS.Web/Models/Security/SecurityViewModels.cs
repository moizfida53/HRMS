using HRMS.Domain.Common;
using HRMS.Domain.Security;
using HRMS.Web.Security;

namespace HRMS.Web.Models.Security;

/// <summary>Security > Create Roles: the roles (left) and the editor of one (right, loaded by POST).</summary>
public sealed class RolesPageModel
{
    public IReadOnlyList<RoleSummary> Roles { get; init; } = Array.Empty<RoleSummary>();
    /// <summary>The reference of each role (never its id), by role id.</summary>
    public IReadOnlyDictionary<int, string> Refs { get; init; } = new Dictionary<int, string>();
    public bool CanEdit { get; init; }
    /// <summary>The role opened first (reference).</summary>
    public string? OpenRef { get; init; }
}

/// <summary>The role editor: details, the page / function access matrix and the approval rights.</summary>
public sealed class RoleEditorModel
{
    public RoleSummary? Role { get; init; }
    public string? Ref { get; init; }
    public bool IsNew => Role is null;
    /// <summary>Read-only: the system role, a role of every company for a pinned user, or no edit right.</summary>
    public bool ReadOnly { get; init; }
    public bool CanDelete { get; init; }
    /// <summary>Not pinned to a company: may choose the role's company (or every company).</summary>
    public bool ChooseCompany { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyDictionary<string, AccessLevel> Levels { get; init; } = new Dictionary<string, AccessLevel>();
    public IReadOnlyDictionary<string, ISet<string>> Approvals { get; init; } = new Dictionary<string, ISet<string>>();

    public AccessLevel LevelOf(string code) => Levels.GetValueOrDefault(code, AccessLevel.None);
    public bool Approves(string code, string column) => Approvals.TryGetValue(code, out var c) && c.Contains(column);
}

/// <summary>Security > Manage Users.</summary>
public sealed class UsersPageModel
{
    /// <summary>The role filter: reference -> name.</summary>
    public IReadOnlyList<(string Ref, string Name)> Roles { get; init; } = Array.Empty<(string, string)>();
    public bool CanCreate { get; init; }
}

public sealed class UsersGridModel
{
    public required PagedResult<UserRoleRow> Page { get; init; }
    public IReadOnlyDictionary<long, string> Refs { get; init; } = new Dictionary<long, string>();
    /// <summary>May change accounts or their roles (else the popup is read-only).</summary>
    public bool CanEdit { get; init; }
    public bool CanDisable { get; init; }
    public long? CurrentUserId { get; init; }
    public bool IsFiltered { get; init; }
    public bool ManyCompanies { get; init; }
}

/// <summary>The user popup: the account, its password and its roles.</summary>
public sealed class UserFormModel
{
    /// <summary>Null = a new user.</summary>
    public UserRoleRow? User { get; init; }
    public string? Ref { get; init; }
    public bool IsNew => User is null;
    public IReadOnlyList<RoleOption> Roles { get; init; } = Array.Empty<RoleOption>();
    /// <summary>Not pinned to a company: may choose the user's company.</summary>
    public bool ChooseCompany { get; init; }
    /// <summary>System Administrator: may also give a user every company.</summary>
    public bool AllowAllCompanies { get; init; }
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? CompanyId { get; init; }
    /// <summary>The employees of the user's company: reference, text, linked now.</summary>
    public IReadOnlyList<(string Ref, string Text, bool Selected)> Employees { get; init; } = Array.Empty<(string, string, bool)>();
    public bool CanEditAccount { get; init; }
    public bool CanAssign { get; init; }
    public bool CanDisable { get; init; }
    public bool SimplePassword { get; init; }
    public bool IsSelf { get; init; }
    /// <summary>The account has rights the signed-in user lacks: it cannot be changed by them.</summary>
    public bool Locked { get; init; }
}

public sealed record RoleOption(string Ref, RoleSummary Role, bool Selected, bool Allowed);
