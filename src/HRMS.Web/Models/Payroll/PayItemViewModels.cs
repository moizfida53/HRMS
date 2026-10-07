using System.Globalization;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Payroll;

/// <summary>What the signed-in user may do on Pay Items.</summary>
public sealed class PayItemRights
{
    public bool CanCreate { get; init; }
    public bool CanEdit { get; init; }
    public bool CanDelete { get; init; }
    public bool CanApproveHr { get; init; }
    public bool CanApproveFinance { get; init; }
    public long? UserId { get; init; }
    public bool IsSysAdmin { get; init; }

    public bool IsApprover => CanApproveHr || CanApproveFinance;

    /// <summary>True when this user can take the next approval decision on the item.</summary>
    public bool CanApprove(PayItem item) =>
        item.IsPending && (item.ApprovalLevel == 0 ? CanApproveHr : CanApproveFinance);

    /// <summary>The approval would be refused for segregation of duties (shown as a hint, the procedure enforces it).</summary>
    public bool IsOwnSubmission(PayItem item) => !IsSysAdmin && item.SubmittedBy is { } s && s == UserId;
}

public sealed class PayItemsPageModel
{
    public IReadOnlyList<PayItemEmployeeOption> Employees { get; init; } = Array.Empty<PayItemEmployeeOption>();
    public long? SelectedEmployeeId { get; init; }
    public string? SelectedStatus { get; init; }
    public required PayItemRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
}

public sealed class PayItemsGridModel
{
    public required PagedResult<PayItem> Page { get; init; }
    public bool IsFiltered { get; init; }
    public required PayItemRights Rights { get; init; }
    public bool ManyCompanies { get; init; }
}

public sealed class PayItemFormModel
{
    public PayItem? Item { get; init; }
    public long? EmployeeId { get; init; }
    public string ItemClass { get; init; } = Domain.Payroll.ItemClass.Earning;
    public IReadOnlyList<PayItemEmployeeOption> Employees { get; init; } = Array.Empty<PayItemEmployeeOption>();
    public IReadOnlyList<PayItemType> Types { get; init; } = Array.Empty<PayItemType>();
    public IReadOnlyList<DateTime> Months { get; init; } = Array.Empty<DateTime>();
    public DateTime DefaultMonth { get; init; }

    /// <summary>new, edit, revise (a change of an approved salary item) or locked (already paid: comment / last month only).</summary>
    public string Mode { get; init; } = "new";

    public bool IsNew => Item is null;
}

public sealed class PayItemHistoryModel
{
    public required PayItem Item { get; init; }
    public IReadOnlyList<PayItemHistoryEntry> Entries { get; init; } = Array.Empty<PayItemHistoryEntry>();
}

/// <summary>Months, amounts and "applies" texts of the Pay Items screens.</summary>
public static class PayItemFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Month(IUiText L, DateTime month) =>
        $"{L.Month(month.Month, shortName: true)} {month.Year.ToString(Inv)}";

    public static string MonthValue(DateTime month) => month.ToString("yyyy-MM", Inv);

    public static string Applies(IUiText L, PayItem i) => i.AppliesMode switch
    {
        AppliesMode.Monthly when i.EndMonth is { } end => L["pi.every_month_from_to", Month(L, i.StartMonth), Month(L, end)],
        AppliesMode.Monthly => L["pi.every_month_from", Month(L, i.StartMonth)],
        AppliesMode.Instalment => L["pi.instalments_from", PayrollFormat.Count(i.InstalmentCount ?? 0), Month(L, i.StartMonth)]
                                  + (i.PaidCount > 0 ? " · " + L["pi.n_paid", PayrollFormat.Count(i.PaidCount)] : ""),
        _ => L["pi.one_time", Month(L, i.StartMonth)]
    };

    public static string AppliesPlain(IUiText L, string mode) => mode switch
    {
        AppliesMode.Monthly => L["pi.applies_monthly"],
        AppliesMode.Instalment => L["pi.applies_instalments"],
        _ => L["pi.applies_once"]
    };

    public static string ClassLabel(IUiText L, string? cls) => L.Tr(ItemClass.Label(cls));

    public static string StatusLabel(IUiText L, PayItem i) => i.EffectiveStatus switch
    {
        PayItemStatus.Pending => L.Tr("Pending approval"),
        PayItemStatus.Ended => L.Tr("Ended"),
        _ => L.Tr("Active")
    };

    public static string StatusBadge(PayItem i) => i.EffectiveStatus switch
    {
        PayItemStatus.Pending => "warning",
        PayItemStatus.Ended => "muted",
        _ => "success"
    };

    public static string TypeName(IUiText L, string? name, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : name ?? string.Empty;

    public static string EmployeeName(IUiText L, string? name, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : name ?? string.Empty;

    public static string Initials(string? name)
    {
        var parts = (name ?? string.Empty).Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => "?",
            1 => parts[0][..1].ToUpperInvariant(),
            _ => (parts[0][..1] + parts[^1][..1]).ToUpperInvariant()
        };
    }

    /// <summary>The months offered in the form: 3 back to 12 ahead, plus the item's own months.</summary>
    public static IReadOnlyList<DateTime> MonthOptions(DateTime today, params DateTime?[] include)
    {
        var first = new DateTime(today.Year, today.Month, 1).AddMonths(-3);
        var set = new SortedSet<DateTime>(Enumerable.Range(0, 16).Select(first.AddMonths));
        foreach (var m in include)
        {
            if (m is { } d) set.Add(new DateTime(d.Year, d.Month, 1));
        }
        return set.ToList();
    }
}
