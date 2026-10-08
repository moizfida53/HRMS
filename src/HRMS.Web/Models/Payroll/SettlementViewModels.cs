using System.Globalization;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Payroll;

/// <summary>What the signed-in user may do on Final Settlement.</summary>
public sealed class SettlementRights
{
    public bool CanProcess { get; init; }
    public bool CanPay { get; init; }
    public bool CanCancel { get; init; }
    public bool CanApproveHr { get; init; }
    public bool CanApproveFinance { get; init; }
    public long? UserId { get; init; }
    /// <summary>May approve their own submissions (System Administrator or the "approve own" right).</summary>
    public bool CanApproveOwn { get; init; }

    public bool IsApprover => CanApproveHr || CanApproveFinance;

    /// <summary>True when this user can take the next approval decision.</summary>
    public bool CanApprove(int approvalLevel) => approvalLevel == 0 ? CanApproveHr : CanApproveFinance;

    /// <summary>The approval would be refused for segregation of duties (a hint; the procedure enforces it).</summary>
    public bool IsOwnSubmission(long? submittedBy) => !CanApproveOwn && submittedBy is { } s && s == UserId;
}

public sealed class SettlementListPageModel
{
    public required SettlementRights Rights { get; init; }
    public string? Status { get; init; }
    public string? Type { get; init; }
    public string? Search { get; init; }
    /// <summary>"list" (every settlement) or "encashment" (leave encashment page).</summary>
    public string Mode { get; init; } = "list";
}

public sealed class SettlementGridModel
{
    public required PagedResult<FinalSettlementRow> Page { get; init; }
    public bool IsFiltered { get; init; }
    public bool ManyCompanies { get; init; }
    public required SettlementRights Rights { get; init; }
}

/// <summary>The settlement form: a new settlement, or the details of a draft being changed.</summary>
public sealed class SettlementFormModel
{
    public FinalSettlement? Settlement { get; init; }
    public IReadOnlyList<SettlementEmployeeOption> Employees { get; init; } = Array.Empty<SettlementEmployeeOption>();
    public long? EmployeeId { get; init; }
    public string Type { get; init; } = SettlementType.Resignation;
    /// <summary>The leave encashment form (no exit) instead of the exit form.</summary>
    public bool IsEncashment => Type == SettlementType.Encashment;
    public IReadOnlyList<DateTime> PayMonths { get; init; } = Array.Empty<DateTime>();
    public bool IsNew => Settlement is null;
}

public sealed class SettlementPageModel
{
    public required FinalSettlement Settlement { get; init; }
    public IReadOnlyList<FinalSettlementLine> Lines { get; init; } = Array.Empty<FinalSettlementLine>();
    public IReadOnlyList<FinalSettlementHistoryEntry> History { get; init; } = Array.Empty<FinalSettlementHistoryEntry>();
    public required SettlementRights Rights { get; init; }
    public SettlementFormModel? Form { get; init; }

    public bool Editable => Settlement.IsDraft && Rights.CanProcess;

    public IEnumerable<FinalSettlementLine> Section(string section) =>
        Lines.Where(l => l.Section == section);
}

public sealed class SettlementStatementModel
{
    public required FinalSettlement Settlement { get; init; }
    public IReadOnlyList<FinalSettlementLine> Lines { get; init; } = Array.Empty<FinalSettlementLine>();
    /// <summary>The text of a label key in English and in Arabic (the statement is bilingual).</summary>
    public required Func<string, object?[], (string En, string Ar)> Both { get; init; }
}

/// <summary>Labels, badges and line texts of the Final Settlement screens.</summary>
public static class SettlementFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string TypeLabel(IUiText L, string? type) => L.Tr(SettlementType.Label(type));

    public static string TypeKey(string? type) => type switch
    {
        SettlementType.Resignation => "fs.type_resignation",
        SettlementType.Termination => "fs.type_termination",
        SettlementType.ContractEnd => "fs.type_contract_end",
        SettlementType.Retirement => "fs.type_retirement",
        SettlementType.Death => "fs.type_death",
        SettlementType.Disability => "fs.type_disability",
        _ => "fs.type_encashment"
    };

    public static string StatusLabel(IUiText L, string status, int level = 0) => status switch
    {
        SettlementStatus.Draft => L["fs.status_draft"],
        SettlementStatus.Pending => level == 0 ? L["fs.status_pending_hr"] : L["fs.status_pending_finance"],
        SettlementStatus.Approved => L["fs.status_approved"],
        SettlementStatus.Paid => L["fs.status_paid"],
        _ => L["fs.status_cancelled"]
    };

    public static string StatusBadge(string status) => status switch
    {
        SettlementStatus.Draft => "muted",
        SettlementStatus.Pending => "warning",
        SettlementStatus.Approved => "info",
        SettlementStatus.Paid => "success",
        _ => "danger"
    };

    public static string MethodLabel(IUiText L, string? method) => method switch
    {
        PaymentMethod.Bank => L["fs.method_bank"],
        PaymentMethod.Cheque => L["fs.method_cheque"],
        PaymentMethod.Cash => L["fs.method_cash"],
        PaymentMethod.Payroll => L["fs.method_payroll"],
        _ => "—"
    };

    public static string HistoryLabel(IUiText L, string action, int? level) => action switch
    {
        "CREATED" => L["fs.h_created"],
        "CHANGED" => L["fs.h_changed"],
        "LINE_ADDED" => L["fs.h_line_added"],
        "LINE_REMOVED" => L["fs.h_line_removed"],
        "LINE_WAIVED" => L["fs.h_line_waived"],
        "LINE_RESTORED" => L["fs.h_line_restored"],
        "SUBMITTED" => L["fs.h_submitted"],
        "APPROVED" => level == 1 ? L["fs.h_approved_hr"] : L["fs.h_approved_finance"],
        "RETURNED" => L["fs.h_returned"],
        "REJECTED" => L["fs.h_rejected"],
        "PAID" => L["fs.h_paid"],
        "CANCELLED" => L["fs.h_cancelled"],
        _ => action
    };

    /// <summary>"8 years 7 months 15 days" from the hire date and the last working day.</summary>
    public static string Service(IUiText L, DateTime? hire, DateTime lastDay)
    {
        if (hire is not { } from || from > lastDay) return "—";
        var end = lastDay.AddDays(1);
        var years = end.Year - from.Year;
        if (from.AddYears(years) > end) years--;
        var afterYears = from.AddYears(years);
        var months = 0;
        while (afterYears.AddMonths(months + 1) <= end) months++;
        var days = (end - afterYears.AddMonths(months)).Days;
        return L["fs.service_ymd", years, months, days];
    }

    /// <summary>"8y 7m" for the list.</summary>
    public static string ServiceShort(IUiText L, decimal serviceYears)
    {
        var y = (int)Math.Floor(serviceYears);
        var m = (int)Math.Floor((serviceYears - y) * 12m);
        return L["fs.service_short", y, m];
    }

    public static string Years(decimal? value) => (value ?? 0).ToString("0.####", Inv);

    public static string Num(decimal? value) => (value ?? 0).ToString("0.##", Inv);

    public static string Pct(decimal? value) => (value ?? 0).ToString("0.##", Inv) + "%";

    public static string Name(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

    public static string Range(IUiText L, DateTime? from, DateTime? to) =>
        from is { } f && to is { } t ? (f == t ? L.DayMonth(f) : $"{L.DayMonth(f)} – {L.DayMonth(t)}") : string.Empty;

    /// <summary>The main text of a line.</summary>
    public static string Title(IUiText L, FinalSettlementLine l) => l.LineCode switch
    {
        "LEAVE" => L["fs.leave_encashment_n_days", Num(l.Quantity)],
        "IND_SLAB" => (l.Unit, l.ToYears) switch
        {
            ("DAYS", { } to) => L["fs.years_x_y_days_per_year", Num(l.FromYears), Num(to), Num(l.Rate)],
            ("DAYS", null) => L["fs.years_x_plus_days_per_year", Num(l.FromYears), Num(l.Rate)],
            (_, { } to) => L["fs.years_x_y_months_per_year", Num(l.FromYears), Num(to), Num(l.Rate)],
            _ => L["fs.years_x_plus_months_per_year", Num(l.FromYears), Num(l.Rate)]
        },
        "SALARY" when l.Section == SettlementSection.Recovery => L["fs.salary_paid_after_last_day"],
        "MANUAL" => l.Description ?? string.Empty,
        _ => Name(L, l.Description, l.ArabicDescription)
    };

    /// <summary>How the amount was worked out (shown under the title).</summary>
    public static string Detail(IUiText L, FinalSettlementLine l, decimal divisor = 26)
    {
        string M(decimal? v) => PayrollFormat.Money(v ?? 0);
        switch (l.LineCode)
        {
            case "SALARY" when l.Section == SettlementSection.Recovery:
                return $"{l.SourceRef} · {Range(L, l.PeriodFrom, l.PeriodTo)} · {M(l.Basis)} ÷ {Num(l.Rate)} × {Num(l.Quantity)}";
            case "SALARY":
                return l.Quantity is { } q && l.Rate is { } r && q < r && l.Amount != l.Basis
                    ? $"{Range(L, l.PeriodFrom, l.PeriodTo)} · {M(l.Basis)} ÷ {Num(r)} × {Num(q)}"
                    : $"{Range(L, l.PeriodFrom, l.PeriodTo)} · {L["fs.full_month"]}";
            case "LEAVE":
                return $"{M(l.Basis)} ÷ {Num(l.Rate)} × {Num(l.Quantity)}";
            case "IND_SLAB":
                return l.Unit == "DAYS"
                    ? $"{Years(l.Quantity)} × {Num(l.Rate)} × ({M(l.Basis)} ÷ {Num(divisor)})"
                    : $"{Years(l.Quantity)} × {Num(l.Rate)} × {M(l.Basis)}";
            case "PIFSS":
                return $"{Range(L, l.PeriodFrom, l.PeriodTo)} · {Pct(l.Rate)} × {M(l.Basis)}";
            case "LOAN":
                return L["fs.balance_of_0_1_of_2_left", M(l.Basis), Num(l.Quantity), Num(l.Rate)];
            case "PAY_ITEM" when l.Quantity is { } left && l.PeriodFrom is null:
                return L["fs.balance_of_0_1_of_2_left", M(l.Basis), Num(left), Num(l.Rate)];
            case "PAY_ITEM":
                var parts = new List<string>();
                if (!string.IsNullOrWhiteSpace(l.SourceRef)) parts.Add(l.SourceRef!);
                if (l.PeriodFrom is not null) parts.Add(Range(L, l.PeriodFrom, l.PeriodTo));
                if (l.Quantity is { } d && l.Rate is { } dm && d < dm && Math.Abs(l.Amount) != l.Basis) parts.Add($"{M(l.Basis)} ÷ {Num(dm)} × {Num(d)}");
                return string.Join(" · ", parts);
            case "MANUAL":
                return L["fs.added_by_hand"];
            default:
                return string.Empty;
        }
    }

    public static string Initials(string? name) => PayItemFormat.Initials(name);

    /// <summary>Payroll months offered for a leave encashment: this month and the next 5.</summary>
    public static IReadOnlyList<DateTime> PayMonthOptions(DateTime today, DateTime? include)
    {
        var first = new DateTime(today.Year, today.Month, 1);
        var set = new SortedSet<DateTime>(Enumerable.Range(0, 6).Select(first.AddMonths));
        if (include is { } m) set.Add(new DateTime(m.Year, m.Month, 1));
        return set.ToList();
    }
}
