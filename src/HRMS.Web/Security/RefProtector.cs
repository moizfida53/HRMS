using System.Security.Cryptography;
using Microsoft.AspNetCore.DataProtection;

namespace HRMS.Web.Security;

/// <summary>
/// Opaque references in place of database ids in URLs, links and posted fields.
/// <para>
/// A reference is the ids encrypted and signed with ASP.NET Core Data Protection,
/// bound to a purpose (what it may open) and to the signed-in user, and valid for a
/// limited time. Changing a character, reusing it for another purpose, or another
/// user's reference all fail, so ids cannot be guessed or tampered with in the
/// address bar ("parameter tampering" / IDOR). The server still applies the
/// user's company scope and permissions to whatever a reference names.
/// </para>
/// </summary>
public interface IRefProtector
{
    /// <summary>A reference to one or more ids (e.g. payroll, or payroll + employee).</summary>
    string Protect(string purpose, params long[] ids);

    /// <summary>The ids of a reference, or null when it is missing, altered, expired, for another purpose or user.</summary>
    long[]? Unprotect(string purpose, string? reference, int count);

    /// <summary>The single id of a reference, or null.</summary>
    long? One(string purpose, string? reference);
}

/// <summary>The purposes of references - one per kind of thing a reference opens.</summary>
public static class RefPurpose
{
    /// <summary>A payroll on the Payslips pages.</summary>
    public const string PayslipRun = "payslip.run";

    /// <summary>One employee's payslip in one payroll (payroll id, employee id).</summary>
    public const string Payslip = "payslip.slip";

    /// <summary>A payroll in My Payslips (always the signed-in employee's own).</summary>
    public const string MyPayslip = "payslip.my";

    /// <summary>A role on Security > Create Roles / Assign Roles.</summary>
    public const string Role = "security.role";

    /// <summary>A user on Security > Assign Roles.</summary>
    public const string User = "security.user";
}

public sealed class RefProtector : IRefProtector
{
    /// <summary>A page left open over a working day keeps working; a copied link stops working by the next day.</summary>
    private static readonly TimeSpan Lifetime = TimeSpan.FromHours(12);

    private readonly ITimeLimitedDataProtector _root;
    private readonly ICurrentUser _user;

    public RefProtector(IDataProtectionProvider provider, ICurrentUser user)
    {
        _root = provider.CreateProtector("HRMS.Web.Ref.v1").ToTimeLimitedDataProtector();
        _user = user;
    }

    private ITimeLimitedDataProtector For(string purpose) =>
        _root.CreateProtector(purpose).CreateProtector("user:" + (_user.UserId?.ToString(System.Globalization.CultureInfo.InvariantCulture) ?? "-"));

    public string Protect(string purpose, params long[] ids) =>
        For(purpose).Protect(string.Join('.', ids.Select(i => i.ToString(System.Globalization.CultureInfo.InvariantCulture))), Lifetime);

    public long[]? Unprotect(string purpose, string? reference, int count)
    {
        if (string.IsNullOrWhiteSpace(reference) || reference.Length > 1024 || _user.UserId is null) return null;
        try
        {
            var parts = For(purpose).Unprotect(reference, out _).Split('.');
            if (parts.Length != count) return null;
            var ids = new long[count];
            for (var i = 0; i < count; i++)
            {
                if (!long.TryParse(parts[i], System.Globalization.NumberStyles.None, System.Globalization.CultureInfo.InvariantCulture, out ids[i]) || ids[i] <= 0)
                    return null;
            }
            return ids;
        }
        catch (CryptographicException)
        {
            return null;   // altered, expired, another purpose or another user
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public long? One(string purpose, string? reference) => Unprotect(purpose, reference, 1)?[0];
}
