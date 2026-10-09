using System.Security.Claims;
using HRMS.Data.Repositories;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Authentication.Cookies;

namespace HRMS.Web.Security;

/// <summary>
/// Keeps the sign-in cookie in step with Security > Create Roles / Manage Users. At most
/// once a minute per user, the account, its permission codes and roles are read again:
/// a deactivated account, or one whose security stamp changed (an administrator reset its
/// password, deactivated it or renamed it) is signed out; otherwise, when the rights differ
/// from the cookie's, the cookie is re-issued with the new ones - so a right given or
/// removed applies within a minute, without signing in again.
/// A database hiccup leaves the session as it is.
/// </summary>
public static class PermissionRefresh
{
    private const string CheckedKey = ".hrms.perm_checked";
    private static readonly TimeSpan Interval = TimeSpan.FromMinutes(1);

    public static async Task ValidateAsync(CookieValidatePrincipalContext context)
    {
        if (context.Principal?.Identity is not ClaimsIdentity identity || !identity.IsAuthenticated) return;
        if (!long.TryParse(identity.FindFirst(ClaimTypes.NameIdentifier)?.Value, out var userId)) return;

        var now = DateTimeOffset.UtcNow;
        if (context.Properties.Items.TryGetValue(CheckedKey, out var last)
            && long.TryParse(last, out var ticks) && now - new DateTimeOffset(ticks, TimeSpan.Zero) < Interval)
        {
            return;
        }

        IReadOnlyList<string> permissions;
        IReadOnlyList<HRMS.Domain.Security.RoleInfo> roles;
        HRMS.Domain.Security.AuthUser? account;
        try
        {
            var auth = context.HttpContext.RequestServices.GetRequiredService<IAuthRepository>();
            account = await auth.FindForLoginAsync(identity.FindFirst(ClaimTypes.Name)?.Value ?? string.Empty, context.HttpContext.RequestAborted);
            permissions = await auth.GetPermissionsAsync(userId, context.HttpContext.RequestAborted);
            roles = await auth.GetRolesAsync(userId, context.HttpContext.RequestAborted);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return;
        }

        var stamp = identity.FindFirst(HrmsClaims.SecurityStamp)?.Value;
        if (account is null || account.UserId != userId || !account.IsActive
            || (stamp is not null && !string.Equals(stamp, account.SecurityStamp.ToString(), StringComparison.OrdinalIgnoreCase)))
        {
            context.RejectPrincipal();
            await context.HttpContext.SignOutAsync(CookieAuthenticationDefaults.AuthenticationScheme);
            return;
        }

        context.Properties.Items[CheckedKey] = now.UtcTicks.ToString(System.Globalization.CultureInfo.InvariantCulture);
        context.ShouldRenew = true;

        var had = identity.FindAll(HrmsClaims.Permission).Select(c => c.Value).ToHashSet(StringComparer.Ordinal);
        var hadRoles = identity.FindAll(ClaimTypes.Role).Select(c => c.Value).ToHashSet(StringComparer.Ordinal);
        if (had.SetEquals(permissions) && hadRoles.SetEquals(roles.Select(r => r.RoleCode))) return;

        var fresh = new ClaimsIdentity(
            identity.Claims.Where(c => c.Type is not (HrmsClaims.Permission or ClaimTypes.Role or HrmsClaims.RoleName)),
            identity.AuthenticationType);
        foreach (var role in roles) fresh.AddClaim(new Claim(ClaimTypes.Role, role.RoleCode));
        foreach (var permission in permissions) fresh.AddClaim(new Claim(HrmsClaims.Permission, permission));
        fresh.AddClaim(new Claim(HrmsClaims.RoleName, roles.Count > 0 ? roles[0].RoleName : "User"));

        context.ReplacePrincipal(new ClaimsPrincipal(fresh));
    }
}
