namespace HRMS.Domain.Security;

/// <summary>A role on Security > Create Roles (db/57, ROLES / ROLE_GET).</summary>
public sealed class RoleSummary
{
    public int RoleId { get; init; }
    public string RoleCode { get; init; } = string.Empty;
    public string RoleName { get; init; } = string.Empty;
    public string? Description { get; init; }
    /// <summary>Null = a role shared by every company.</summary>
    public int? CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public bool IsActive { get; init; }
    /// <summary>System Administrator - always every right, never edited or deleted.</summary>
    public bool IsSystem { get; init; }
    /// <summary>The signed-in user may change it (their company's role, or any when not pinned).</summary>
    public bool IsEditable { get; init; }
    public int UserCount { get; init; }
    public int PermissionCount { get; init; }
    public DateTime? ModifiedDate { get; init; }
}

/// <summary>A user on Security > Manage Users (db/57, USERS).</summary>
public sealed class UserRoleRow
{
    public long UserId { get; init; }
    public string Username { get; init; } = string.Empty;
    public string? Email { get; init; }
    public string? DisplayName { get; init; }
    public string? EmployeeCode { get; init; }
    public int? CompanyId { get; init; }
    public string? CompanyName { get; init; }
    public bool IsActive { get; init; }
    public DateTime? LastLoginDate { get; init; }
    public long? EmployeeId { get; init; }
    public bool MustChangePassword { get; init; }
    public bool IsLockedOut { get; init; }
    /// <summary>CSV of role ids.</summary>
    public string? RoleIds { get; init; }
    /// <summary>Role names separated by "|".</summary>
    public string? RoleNames { get; init; }

    public IReadOnlyList<int> RoleIdList =>
        (RoleIds ?? string.Empty).Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(x => int.TryParse(x, out var i) ? i : 0).Where(i => i > 0).ToList();

    public IReadOnlyList<string> RoleNameList =>
        (RoleNames ?? string.Empty).Split('|', StringSplitOptions.RemoveEmptyEntries);
}

/// <summary>What Create Roles saves.</summary>
public sealed class RoleSaveRequest
{
    public int RoleId { get; init; }
    public string RoleCode { get; init; } = string.Empty;
    public string RoleName { get; init; } = string.Empty;
    public string? Description { get; init; }
    public int? RoleCompanyId { get; init; }
    public bool IsActive { get; init; } = true;
    public IReadOnlyCollection<string> ManagedCodes { get; init; } = Array.Empty<string>();
    public IReadOnlyCollection<string> GrantedCodes { get; init; } = Array.Empty<string>();
}

/// <summary>What Manage Users saves: the account and its roles (one transaction).</summary>
public sealed class UserSaveRequest
{
    /// <summary>0 = a new user.</summary>
    public long UserId { get; init; }
    public string Username { get; init; } = string.Empty;
    public string? Email { get; init; }
    /// <summary>Null = every company (System Administrator only).</summary>
    public int? UserCompanyId { get; init; }
    public long? EmployeeId { get; init; }
    public bool IsActive { get; init; } = true;
    /// <summary>A new password (hash); null keeps the current one.</summary>
    public string? PasswordHash { get; init; }
    /// <summary>Simple-password mode only (db/27).</summary>
    public string? PlainPassword { get; init; }
    public bool MustChangePassword { get; init; } = true;
    public IReadOnlyCollection<int> RoleIds { get; init; } = Array.Empty<int>();
}
