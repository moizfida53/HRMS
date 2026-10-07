using System.Security.Claims;

namespace HRMS.Web.Security;

/// <summary>
/// The signed-in user, as the rest of the application needs to see them.
/// </summary>
public interface ICurrentUser
{
    bool IsAuthenticated { get; }

    /// <summary>Security.Users.UserId. Passed to every stored procedure as @UserId.</summary>
    long? UserId { get; }

    string UserName { get; }

    string DisplayName { get; }

    string RoleName { get; }

    /// <summary>Initials for the avatar chip.</summary>
    string Initials { get; }

    /// <summary>
    /// The company the user is currently working in. Scopes every grid and
    /// dropdown. Null means "all companies the user may see".
    /// </summary>
    int? ActiveCompanyId { get; }

    string ActiveCompanyName { get; }

    long? EmployeeId { get; }

    /// <summary>True while a seeded or reset password is still in place.</summary>
    bool MustChangePassword { get; }

    bool HasPermission(string permissionCode);

    bool IsInRole(string roleCode);
}

/// <summary>
/// Reads the current user from the sign-in cookie's claims. No database round
/// trip per request - permissions are carried in the ticket, and rotating a
/// user's SecurityStamp on a password or role change invalidates it.
/// </summary>
public sealed class ClaimsCurrentUser : ICurrentUser
{
    private readonly IHttpContextAccessor _http;

    public ClaimsCurrentUser(IHttpContextAccessor http) => _http = http;

    private ClaimsPrincipal? Principal => _http.HttpContext?.User;

    public bool IsAuthenticated => Principal?.Identity?.IsAuthenticated ?? false;

    public long? UserId =>
        long.TryParse(Principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id) ? id : null;

    public string UserName => Principal?.FindFirstValue(ClaimTypes.Name) ?? string.Empty;

    public string DisplayName
    {
        get
        {
            var name = Principal?.FindFirstValue(HrmsClaims.DisplayName);
            return string.IsNullOrWhiteSpace(name) ? UserName : name;
        }
    }

    public string RoleName
    {
        get
        {
            var role = Principal?.FindFirstValue(HrmsClaims.RoleName);
            return string.IsNullOrWhiteSpace(role) ? "User" : role;
        }
    }

    public string Initials
    {
        get
        {
            var source = DisplayName;
            if (string.IsNullOrWhiteSpace(source))
            {
                return "?";
            }

            var parts = source.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);

            return parts.Length switch
            {
                0 => "?",
                1 => parts[0][..Math.Min(2, parts[0].Length)].ToUpperInvariant(),
                _ => string.Concat(parts[0][0], parts[^1][0]).ToUpperInvariant()
            };
        }
    }

    public int? ActiveCompanyId =>
        int.TryParse(Principal?.FindFirstValue(HrmsClaims.CompanyId), out var id) ? id : null;

    public string ActiveCompanyName
    {
        get
        {
            var name = Principal?.FindFirstValue(HrmsClaims.CompanyName);
            return string.IsNullOrWhiteSpace(name) ? "All companies" : name;
        }
    }

    public long? EmployeeId =>
        long.TryParse(Principal?.FindFirstValue(HrmsClaims.EmployeeId), out var id) ? id : null;

    public bool MustChangePassword =>
        string.Equals(Principal?.FindFirstValue(HrmsClaims.MustChangePassword), "true", StringComparison.OrdinalIgnoreCase);

    public bool HasPermission(string permissionCode)
    {
        if (Principal is null || string.IsNullOrWhiteSpace(permissionCode))
        {
            return false;
        }

        return Principal.HasClaim(HrmsClaims.Permission, permissionCode)
            || Principal.HasClaim(HrmsClaims.Permission, "SYSTEM_ADMIN");
    }

    public bool IsInRole(string roleCode) =>
        Principal?.IsInRole(roleCode) ?? false;
}
