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

/// <summary>Security > Assign Roles.</summary>
public sealed class AssignPageModel
{
    /// <summary>The role filter: reference -> name.</summary>
    public IReadOnlyList<(string Ref, string Name)> Roles { get; init; } = Array.Empty<(string, string)>();
    public bool CanAssign { get; init; }
}

public sealed class UsersGridModel
{
    public required PagedResult<UserRoleRow> Page { get; init; }
    public IReadOnlyDictionary<long, string> Refs { get; init; } = new Dictionary<long, string>();
    public bool CanAssign { get; init; }
    public bool IsFiltered { get; init; }
    public bool ManyCompanies { get; init; }
}

/// <summary>The roles of one user (popup).</summary>
public sealed class UserRolesPanelModel
{
    public required UserRoleRow User { get; init; }
    public required string Ref { get; init; }
    public IReadOnlyList<RoleOption> Roles { get; init; } = Array.Empty<RoleOption>();
    public bool CanAssign { get; init; }
}

public sealed record RoleOption(string Ref, RoleSummary Role, bool Selected, bool Allowed);
