namespace HRMS.Domain.Security;

/// <summary>
/// The credential row plus the account state the sign-in policy needs.
/// Returned by the LOGIN_LOOKUP action of Security.usp_Auth_Manage.
/// </summary>
public sealed class AuthUser
{
    public long UserId { get; set; }

    public string Username { get; set; } = string.Empty;

    public string? Email { get; set; }

    /// <summary>
    /// PBKDF2 hash in the application's own format. Never leaves the server
    /// and is never written to a log or a claim.
    /// </summary>
    public string? PasswordHash { get; set; }

    /// <summary>
    /// Plain-text password (Security.Users.[Password], db/27). Only read when
    /// Authentication:SimplePassword is true; null when not set.
    /// </summary>
    public string? Password { get; set; }

    public bool IsActive { get; set; }

    public int FailedLoginAttempts { get; set; }

    public DateTime? LockoutEndUtc { get; set; }

    public bool MustChangePassword { get; set; }

    public bool TwoFactorEnabled { get; set; }

    /// <summary>Rotated on password change; invalidates existing sign-in cookies.</summary>
    public Guid SecurityStamp { get; set; }

    public int? CompanyId { get; set; }

    public string? CompanyName { get; set; }

    public long? EmployeeId { get; set; }

    public string? EmployeeName { get; set; }

    public bool IsLockedOut =>
        LockoutEndUtc.HasValue && LockoutEndUtc.Value > DateTime.UtcNow;

    /// <summary>Employee name when the account is linked to one, otherwise the username.</summary>
    public string DisplayName =>
        string.IsNullOrWhiteSpace(EmployeeName) ? Username : EmployeeName.Trim();
}

/// <summary>Why a sign-in attempt ended the way it did.</summary>
public enum LoginOutcome
{
    Success,
    InvalidCredentials,
    AccountInactive,
    AccountLockedOut,
    MustChangePassword
}

public sealed class LoginResult
{
    public required LoginOutcome Outcome { get; init; }

    public AuthUser? User { get; init; }

    /// <summary>Set when the account is locked, so the UI can say for how long.</summary>
    public DateTime? LockoutEndUtc { get; init; }

    public bool Succeeded => Outcome is LoginOutcome.Success or LoginOutcome.MustChangePassword;

    public static LoginResult Failure(LoginOutcome outcome, DateTime? lockoutEnd = null) =>
        new() { Outcome = outcome, LockoutEndUtc = lockoutEnd };

    public static LoginResult Success(AuthUser user) => new()
    {
        Outcome = user.MustChangePassword ? LoginOutcome.MustChangePassword : LoginOutcome.Success,
        User = user
    };
}

/// <summary>Audit outcome codes accepted by the LOGIN_FAILURE action.</summary>
public static class LoginAuditOutcome
{
    public const string BadPassword = "BAD_PASSWORD";
    public const string UnknownUser = "UNKNOWN_USER";
    public const string Inactive    = "INACTIVE";
    public const string LockedOut   = "LOCKED_OUT";
}

public sealed class RoleInfo
{
    public string RoleCode { get; set; } = string.Empty;
    public string RoleName { get; set; } = string.Empty;
}
