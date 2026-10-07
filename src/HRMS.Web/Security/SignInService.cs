using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Security;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Security;

public sealed class AuthenticationPolicyOptions
{
    public const string SectionName = "Authentication";

    /// <summary>Failed attempts before the account locks.</summary>
    public int MaxFailedAttempts { get; set; } = 5;

    /// <summary>How long a locked account stays locked.</summary>
    public int LockoutMinutes { get; set; } = 15;

    /// <summary>Sliding session lifetime for the sign-in cookie.</summary>
    public int SessionMinutes { get; set; } = 60;

    /// <summary>Lifetime when the user ticks "keep me signed in".</summary>
    public int PersistentDays { get; set; } = 14;

    /// <summary>
    /// true: passwords are also stored as plain text in Security.Users.[Password]
    /// (db/27), sign-in compares against it, and Change Password has no
    /// strength rules (max 50 characters). false (default): hashed only.
    /// The hash is kept current in both modes, so this can be switched back.
    /// </summary>
    public bool SimplePassword { get; set; }

    /// <summary>Longest password the [Password] column holds in simple mode.</summary>
    public const int SimplePasswordMaxLength = 50;
}

public interface ISignInService
{
    Task<LoginResult> PasswordSignInAsync(
        string username, string password, bool rememberMe, CancellationToken cancellationToken = default);

    Task SignOutAsync();

    /// <summary>
    /// Changes the signed-in user's own password after re-checking the
    /// current one. A wrong current password counts towards the normal
    /// lockout, so this cannot be used to guess passwords. On success the
    /// cookie is re-issued (new security stamp, initial-password flag cleared)
    /// so this session stays signed in.
    /// </summary>
    Task<ChangePasswordResult> ChangePasswordAsync(
        string currentPassword, string newPassword, CancellationToken cancellationToken = default);
}

public enum ChangePasswordOutcome
{
    Changed,
    WrongCurrentPassword,
    LockedOut,
    NotSignedIn
}

public sealed record ChangePasswordResult(ChangePasswordOutcome Outcome, DateTime? LockoutEndUtc = null)
{
    public bool Succeeded => Outcome == ChangePasswordOutcome.Changed;
}

/// <summary>
/// Orchestrates a password sign-in: look the account up, apply the policy,
/// verify the hash, record the outcome, and issue the cookie.
/// <para>
/// Every failure path returns the same generic outcome to the caller and takes
/// broadly the same amount of time, so the response cannot be used to work out
/// which usernames exist.
/// </para>
/// </summary>
public sealed class SignInService : ISignInService
{
    private readonly IAuthRepository _auth;
    private readonly IPasswordHasher _hasher;
    private readonly IHttpContextAccessor _http;
    private readonly AuthenticationPolicyOptions _policy;
    private readonly ILogger<SignInService> _logger;

    public SignInService(
        IAuthRepository auth,
        IPasswordHasher hasher,
        IHttpContextAccessor http,
        IOptions<AuthenticationPolicyOptions> policy,
        ILogger<SignInService> logger)
    {
        _auth = auth;
        _hasher = hasher;
        _http = http;
        _policy = policy.Value;
        _logger = logger;
    }

    public async Task<LoginResult> PasswordSignInAsync(
        string username, string password, bool rememberMe,
        CancellationToken cancellationToken = default)
    {
        username = (username ?? string.Empty).Trim();

        var ip = IpAddress();
        var userAgent = UserAgent();

        var user = await _auth.FindForLoginAsync(username, cancellationToken).ConfigureAwait(false);

        // Unknown account. Burn the same work a real verification would, so the
        // response time does not distinguish "no such user" from "wrong password".
        if (user is null)
        {
            _hasher.BurnTime();

            await _auth.RecordFailureAsync(
                null, username, LoginAuditOutcome.UnknownUser, ip, userAgent,
                _policy.MaxFailedAttempts, _policy.LockoutMinutes, cancellationToken).ConfigureAwait(false);

            _logger.LogInformation("Sign-in attempt for an unknown account from {Ip}.", ip);
            return LoginResult.Failure(LoginOutcome.InvalidCredentials);
        }

        // Locked accounts are rejected before the password is even checked, so a
        // lockout cannot be used as an oracle for guessing.
        if (user.IsLockedOut)
        {
            await _auth.RecordFailureAsync(
                user.UserId, username, LoginAuditOutcome.LockedOut, ip, userAgent,
                _policy.MaxFailedAttempts, _policy.LockoutMinutes, cancellationToken).ConfigureAwait(false);

            _logger.LogWarning("Sign-in attempt on locked account {UserId} from {Ip}.", user.UserId, ip);
            return LoginResult.Failure(LoginOutcome.AccountLockedOut, user.LockoutEndUtc);
        }

        if (!user.IsActive)
        {
            _hasher.BurnTime();

            await _auth.RecordFailureAsync(
                user.UserId, username, LoginAuditOutcome.Inactive, ip, userAgent,
                _policy.MaxFailedAttempts, _policy.LockoutMinutes, cancellationToken).ConfigureAwait(false);

            _logger.LogWarning("Sign-in attempt on disabled account {UserId} from {Ip}.", user.UserId, ip);
            return LoginResult.Failure(LoginOutcome.AccountInactive);
        }

        if (!VerifyPassword(user, password, out var needsRehash, out var fillPlain))
        {
            var lockoutEnd = await _auth.RecordFailureAsync(
                user.UserId, username, LoginAuditOutcome.BadPassword, ip, userAgent,
                _policy.MaxFailedAttempts, _policy.LockoutMinutes, cancellationToken).ConfigureAwait(false);

            _logger.LogInformation("Failed sign-in for account {UserId} from {Ip}.", user.UserId, ip);

            return lockoutEnd.HasValue && lockoutEnd.Value > DateTime.UtcNow
                ? LoginResult.Failure(LoginOutcome.AccountLockedOut, lockoutEnd)
                : LoginResult.Failure(LoginOutcome.InvalidCredentials);
        }

        // Transparent work-factor upgrade for hashes created under an older policy.
        if (needsRehash)
        {
            try
            {
                await _auth.ChangePasswordAsync(
                        user.UserId, _hasher.Hash(password), PlainOrNull(password), cancellationToken)
                           .ConfigureAwait(false);
                _logger.LogInformation("Upgraded stored password hash for account {UserId}.", user.UserId);
            }
            catch (Exception ex)
            {
                // Never block a valid sign-in because the upgrade failed.
                _logger.LogWarning(ex, "Password hash upgrade failed for account {UserId}.", user.UserId);
            }
        }

        // Simple mode, account still has no plain copy: store it now (signed in with the hash).
        if (fillPlain && !needsRehash)
        {
            try
            {
                await _auth.SetPlainPasswordAsync(user.UserId, password, cancellationToken).ConfigureAwait(false);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Could not store the plain password for account {UserId}.", user.UserId);
            }
        }

        await _auth.RecordSuccessAsync(user.UserId, username, ip, userAgent, cancellationToken)
                   .ConfigureAwait(false);

        await IssueCookieAsync(user, rememberMe, cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Account {UserId} signed in from {Ip}.", user.UserId, ip);
        return LoginResult.Success(user);
    }

    public async Task<ChangePasswordResult> ChangePasswordAsync(
        string currentPassword, string newPassword, CancellationToken cancellationToken = default)
    {
        var context = _http.HttpContext;
        var principal = context?.User;
        var username = principal?.FindFirstValue(ClaimTypes.Name);

        if (context is null || principal?.Identity?.IsAuthenticated != true ||
            string.IsNullOrEmpty(username) ||
            !long.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var userId))
        {
            return new ChangePasswordResult(ChangePasswordOutcome.NotSignedIn);
        }

        var ip = IpAddress();
        var userAgent = UserAgent();

        // Same lookup as sign-in, then make sure it is really this session's account.
        var user = await _auth.FindForLoginAsync(username, cancellationToken).ConfigureAwait(false);
        if (user is null || user.UserId != userId || !user.IsActive)
        {
            return new ChangePasswordResult(ChangePasswordOutcome.NotSignedIn);
        }

        if (user.IsLockedOut)
        {
            return new ChangePasswordResult(ChangePasswordOutcome.LockedOut, user.LockoutEndUtc);
        }

        if (!VerifyPassword(user, currentPassword, out _, out _))
        {
            var lockoutEnd = await _auth.RecordFailureAsync(
                user.UserId, username, LoginAuditOutcome.BadPassword, ip, userAgent,
                _policy.MaxFailedAttempts, _policy.LockoutMinutes, cancellationToken).ConfigureAwait(false);

            _logger.LogInformation("Change password: wrong current password for account {UserId} from {Ip}.", user.UserId, ip);

            return lockoutEnd.HasValue && lockoutEnd.Value > DateTime.UtcNow
                ? new ChangePasswordResult(ChangePasswordOutcome.LockedOut, lockoutEnd)
                : new ChangePasswordResult(ChangePasswordOutcome.WrongCurrentPassword);
        }

        // CHANGE_PASSWORD also clears MustChangePassword and rotates the
        // security stamp, which ends every OTHER session of this account.
        await _auth.ChangePasswordAsync(
                user.UserId, _hasher.Hash(newPassword), PlainOrNull(newPassword), cancellationToken)
                   .ConfigureAwait(false);

        // Re-read (new stamp, flag cleared) and re-issue this session's cookie,
        // keeping its "keep me signed in" choice.
        var refreshed = await _auth.FindForLoginAsync(username, cancellationToken).ConfigureAwait(false) ?? user;
        var current = await context.AuthenticateAsync(CookieAuthenticationDefaults.AuthenticationScheme).ConfigureAwait(false);
        var persistent = current.Properties?.IsPersistent ?? false;

        await IssueCookieAsync(refreshed, persistent, cancellationToken).ConfigureAwait(false);

        _logger.LogInformation("Account {UserId} changed its password from {Ip}.", user.UserId, ip);
        return new ChangePasswordResult(ChangePasswordOutcome.Changed);
    }

    /// <summary>
    /// SimplePassword mode with a plain copy on file: compare against it
    /// (constant time). Otherwise: the PBKDF2 hash. <paramref name="fillPlain"/>
    /// is true when simple mode is on but the account has no plain copy yet.
    /// </summary>
    private bool VerifyPassword(AuthUser user, string password, out bool needsRehash, out bool fillPlain)
    {
        fillPlain = false;

        if (_policy.SimplePassword && !string.IsNullOrEmpty(user.Password))
        {
            needsRehash = false;
            return CryptographicOperations.FixedTimeEquals(
                Encoding.UTF8.GetBytes(password ?? string.Empty),
                Encoding.UTF8.GetBytes(user.Password));
        }

        var ok = _hasher.Verify(password ?? string.Empty, user.PasswordHash, out needsRehash);
        fillPlain = ok && _policy.SimplePassword
                       && (password?.Length ?? 0) <= AuthenticationPolicyOptions.SimplePasswordMaxLength;
        return ok;
    }

    /// <summary>The value for Security.Users.[Password]: the password in simple mode, else null (cleared).</summary>
    private string? PlainOrNull(string password) =>
        _policy.SimplePassword && password.Length <= AuthenticationPolicyOptions.SimplePasswordMaxLength
            ? password
            : null;

    public async Task SignOutAsync()
    {
        var context = _http.HttpContext;
        if (context is null)
        {
            return;
        }

        await context.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme).ConfigureAwait(false);
    }

    private async Task IssueCookieAsync(AuthUser user, bool rememberMe, CancellationToken cancellationToken)
    {
        var context = _http.HttpContext;
        if (context is null)
        {
            return;
        }

        var permissions = await _auth.GetPermissionsAsync(user.UserId, cancellationToken).ConfigureAwait(false);
        var roles = await _auth.GetRolesAsync(user.UserId, cancellationToken).ConfigureAwait(false);

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.UserId.ToString()),
            new(ClaimTypes.Name, user.Username),
            new(HrmsClaims.DisplayName, user.DisplayName),
            new(HrmsClaims.SecurityStamp, user.SecurityStamp.ToString()),
            new(HrmsClaims.MustChangePassword, user.MustChangePassword ? "true" : "false")
        };

        if (user.CompanyId.HasValue)
        {
            claims.Add(new Claim(HrmsClaims.CompanyId, user.CompanyId.Value.ToString()));
            claims.Add(new Claim(HrmsClaims.CompanyName, user.CompanyName ?? string.Empty));
        }

        if (user.EmployeeId.HasValue)
        {
            claims.Add(new Claim(HrmsClaims.EmployeeId, user.EmployeeId.Value.ToString()));
        }

        foreach (var role in roles)
        {
            claims.Add(new Claim(ClaimTypes.Role, role.RoleCode));
        }

        // Permissions ride in the cookie so authorisation needs no database round
        // trip per request. Rotating SecurityStamp on a role change is what keeps
        // a stale cookie from carrying revoked permissions indefinitely.
        foreach (var permission in permissions)
        {
            claims.Add(new Claim(HrmsClaims.Permission, permission));
        }

        // Primary role, used for the label under the user's name in the top bar.
        var primaryRole = roles.Count > 0 ? roles[0].RoleName : "User";
        claims.Add(new Claim(HrmsClaims.RoleName, primaryRole));

        var identity = new ClaimsIdentity(claims, CookieAuthenticationDefaults.AuthenticationScheme);
        var principal = new ClaimsPrincipal(identity);

        var properties = new AuthenticationProperties
        {
            IsPersistent = rememberMe,
            IssuedUtc = DateTimeOffset.UtcNow,
            ExpiresUtc = rememberMe
                ? DateTimeOffset.UtcNow.AddDays(_policy.PersistentDays)
                : DateTimeOffset.UtcNow.AddMinutes(_policy.SessionMinutes),
            AllowRefresh = true
        };

        await context.SignInAsync(
            CookieAuthenticationDefaults.AuthenticationScheme, principal, properties).ConfigureAwait(false);
    }

    private string? IpAddress()
    {
        var context = _http.HttpContext;
        if (context is null)
        {
            return null;
        }

        // X-Forwarded-For is only trustworthy behind a proxy you control. If this
        // is deployed behind one, configure ForwardedHeadersOptions in Program.cs
        // with KnownProxies rather than trusting the header here.
        return context.Connection.RemoteIpAddress?.ToString();
    }

    private string? UserAgent() =>
        _http.HttpContext?.Request.Headers.UserAgent.ToString();
}

/// <summary>Claim types specific to this application.</summary>
public static class HrmsClaims
{
    public const string DisplayName        = "hrms:display_name";
    public const string RoleName           = "hrms:role_name";
    public const string CompanyId          = "hrms:company_id";
    public const string CompanyName        = "hrms:company_name";
    public const string EmployeeId         = "hrms:employee_id";
    public const string Permission         = "hrms:permission";
    public const string SecurityStamp      = "hrms:security_stamp";
    public const string MustChangePassword = "hrms:must_change_password";
}
