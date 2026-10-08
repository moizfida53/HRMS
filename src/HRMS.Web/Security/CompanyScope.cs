using HRMS.Domain.Common;

namespace HRMS.Web.Security;

/// <summary>
/// The company boundary of a signed-in user, checked on every record a request names by id.
/// A user pinned to a company (ActiveCompanyId) may only read or change that company's
/// records, whatever id is put in an address or a posted field; a user with no company
/// claim works across companies by design. Every id-taking action checks the record it
/// loads with <see cref="Allows"/> - an id from another company answers "not found".
/// </summary>
public static class CompanyScope
{
    /// <summary>True when the user may reach a record of <paramref name="companyId"/>.</summary>
    public static bool Allows(this ICurrentUser user, int? companyId) =>
        user.ActiveCompanyId is not { } own || companyId == own;

    /// <summary>The company a lookup may list: the user's own one when pinned, else the one asked for.</summary>
    public static int? LookupCompany(this ICurrentUser user, int? requested) =>
        user.ActiveCompanyId ?? requested;

    /// <summary>The Company lookup lists every company - a pinned user only sees their own.</summary>
    public static IReadOnlyList<LookupItem> OwnCompanies(this ICurrentUser user, string lookupType, IReadOnlyList<LookupItem> items) =>
        user.ActiveCompanyId is { } own && string.Equals(lookupType, LookupType.Company, StringComparison.OrdinalIgnoreCase)
            ? items.Where(i => i.Id == own).ToList()
            : items;

    /// <summary>The CompanyId property of an organization / workforce record (null when it has none).</summary>
    public static int? CompanyOf(object? record) =>
        record?.GetType().GetProperty("CompanyId")?.GetValue(record) switch
        {
            int i => i,
            long l => (int)l,
            _ => null
        };
}
