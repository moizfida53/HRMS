using System.Globalization;
using System.Text;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Payroll;

/// <summary>What the signed-in user may do on Payslips.</summary>
public sealed class PayslipRights
{
    public bool CanView { get; init; }
    public bool CanGenerate { get; init; }
    public bool CanEmail { get; init; }
}

/// <summary>The three Payslips pages: Generate, Employee Payslips and Email Payslips.</summary>
public sealed class PayslipPageModel
{
    /// <summary>"generate", "employees" or "email" - also the tab (slip-generate / slip-employee / slip-email).</summary>
    public required string Mode { get; init; }
    public required PayslipRights Rights { get; init; }
    public IReadOnlyList<PayslipRun> Runs { get; init; } = Array.Empty<PayslipRun>();
    public PayslipRun? Run { get; init; }
    public PayslipSummary? Summary { get; init; }
    public IReadOnlyList<LookupItem> Departments { get; init; } = Array.Empty<LookupItem>();
    public int? DepartmentId { get; init; }
    public string Status { get; init; } = PayslipFilter.All;
    public string? Search { get; init; }
    /// <summary>The Year and Period filters (period = payroll month, first day).</summary>
    public int? Year { get; init; }
    public DateTime? Month { get; init; }
    public bool EmailConfigured { get; init; }

    /// <summary>The years that have payrolls, newest first.</summary>
    public IReadOnlyList<int> Years => Runs.Select(r => r.RunMonth.Year).Distinct().OrderByDescending(y => y).ToList();

    /// <summary>The payroll months (periods), newest first.</summary>
    public IReadOnlyList<DateTime> Months => Runs.Select(r => r.RunMonth).Distinct().OrderByDescending(m => m).ToList();
    public bool ManyCompanies { get; init; }

    public string Tab => Mode switch { "employees" => "slip-employee", "email" => "slip-email", _ => "slip-generate" };
}

public sealed class PayslipGridModel
{
    public required string Mode { get; init; }
    public required PagedResult<PayslipRow> Page { get; init; }
    public required PayslipRights Rights { get; init; }
    public bool IsFiltered { get; init; }
    public bool ManyCompanies { get; init; }
    /// <summary>Every payroll is listed (no payroll chosen) - show the period column.</summary>
    public bool AllRuns { get; init; }
}

/// <summary>My Payslips - the signed-in employee's own payslips.</summary>
public sealed class MyPayslipsModel
{
    public bool HasEmployee { get; init; }
    public PagedResult<PayslipRow> Page { get; init; } = PagedResult<PayslipRow>.Empty();
}

/// <summary>One payslip, ready to print (English, Arabic or both).</summary>
public sealed class PayslipDocumentModel
{
    public required Payslip Slip { get; init; }
    public IReadOnlyList<PayrollRunLine> Lines { get; init; } = Array.Empty<PayrollRunLine>();
    /// <summary>The language shown (the payslip's own, or a preview choice).</summary>
    public required string Template { get; init; }
    /// <summary>Opened from My Payslips (the employee's own).</summary>
    public bool IsSelf { get; init; }
    public bool CanGenerate { get; init; }
    public string? BackUrl { get; init; }
    /// <summary>The text of a label key in English and in Arabic.</summary>
    public required Func<string, object?[], (string En, string Ar)> Both { get; init; }

    public bool ShowEnglish => Template != PayslipTemplate.Arabic;
    public bool ShowArabic => Template != PayslipTemplate.English;
    public bool IsArabicOnly => Template == PayslipTemplate.Arabic;

    /// <summary>Earnings: every line that adds to the pay.</summary>
    public IReadOnlyList<PayrollRunLine> Earnings => Lines.Where(l => l.Amount > 0).ToList();

    /// <summary>Deductions: every line that takes from the pay (shown as positive amounts).</summary>
    public IReadOnlyList<PayrollRunLine> Deductions => Lines.Where(l => l.Amount < 0).ToList();

    public decimal TotalEarnings => Earnings.Sum(l => l.Amount);
    public decimal TotalDeductions => -Deductions.Sum(l => l.Amount);
}

/// <summary>Labels, badges, masking and the amount in words for the payslip screens.</summary>
public static class PayslipFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string TemplateKey(string? template) => template switch
    {
        PayslipTemplate.English => "ps.template_english",
        PayslipTemplate.Arabic => "ps.template_arabic",
        _ => "ps.template_bilingual"
    };

    public static string EmailBadge(string? status) => status switch
    {
        PayslipEmailStatus.Sent => "success",
        PayslipEmailStatus.Failed => "danger",
        PayslipEmailStatus.Queued or PayslipEmailStatus.Sending => "info",
        _ => "muted"
    };

    public static string EmailKey(string? status) => status switch
    {
        PayslipEmailStatus.Sent => "ps.email_sent",
        PayslipEmailStatus.Failed => "ps.email_failed",
        PayslipEmailStatus.Queued or PayslipEmailStatus.Sending => "ps.email_queued",
        _ => "ps.email_not_sent"
    };

    public static string StageKey(string? stage) => stage switch
    {
        RunStage.Closed => "ps.stage_closed",
        RunStage.AwaitingApproval => "ps.stage_awaiting_approval",
        _ => "ps.stage_validation"
    };

    public static string FilterKey(string filter) => filter switch
    {
        PayslipFilter.Generated => "ps.filter_generated",
        PayslipFilter.NotGenerated => "ps.filter_not_generated",
        PayslipFilter.Outdated => "ps.filter_outdated",
        PayslipFilter.NotSent => "ps.filter_not_sent",
        PayslipFilter.Queued => "ps.filter_queued",
        PayslipFilter.Sent => "ps.filter_sent",
        PayslipFilter.Failed => "ps.filter_failed",
        PayslipFilter.NoEmail => "ps.filter_no_email",
        _ => "ps.filter_all"
    };

    public static string Period(IUiText L, PayslipRun r) =>
        PayrollFormat.Period(L, r.PayFrequency, r.PeriodNumber, r.StartDate, r.EndDate, r.RunMonth);

    public static string Period(IUiText L, PayslipRow r) =>
        PayrollFormat.Period(L, r.PayFrequency, r.PeriodNumber, r.StartDate, r.EndDate, r.RunMonth);

    public static string Period(IUiText L, Payslip s) =>
        PayrollFormat.Period(L, s.PayFrequency, s.PeriodNumber, s.StartDate, s.EndDate, s.RunMonth);

    /// <summary>"DTC-2026-09-01 · September 2026 · Closed" for the payroll pickers.</summary>
    public static string RunOption(IUiText L, PayslipRun r, bool withCompany) =>
        string.Join(" · ", new[]
        {
            r.RunCode, Period(L, r), withCompany ? r.CompanyName : null,
            r.RunType == RunType.OffCycle ? L["pr.off_cycle"] : null, L[StageKey(r.Stage)]
        }.Where(s => !string.IsNullOrWhiteSpace(s)));

    /// <summary>Civil ID with every digit but the last four hidden.</summary>
    public static string MaskCivilId(string? civilId)
    {
        if (string.IsNullOrWhiteSpace(civilId)) return "—";
        var v = civilId.Trim();
        return v.Length <= 4 ? v : new string('•', v.Length - 4) + v[^4..];
    }

    /// <summary>"KW74 •••• 3388" - the country/check digits and the last four.</summary>
    public static string MaskIban(string? iban)
    {
        if (string.IsNullOrWhiteSpace(iban)) return "—";
        var v = iban.Replace(" ", string.Empty, StringComparison.Ordinal).Trim().ToUpperInvariant();
        return v.Length <= 8 ? v : $"{v[..4]} •••• {v[^4..]}";
    }

    /// <summary>"One thousand eighty-seven Kuwaiti dinars and 425 fils".</summary>
    public static string AmountInWords(decimal amount)
    {
        amount = Math.Round(Math.Abs(amount), 3, MidpointRounding.AwayFromZero);
        var dinars = (long)Math.Floor(amount);
        var fils = (int)Math.Round((amount - dinars) * 1000m);
        var words = dinars == 0 ? "Zero" : Words(dinars);
        var text = $"{char.ToUpperInvariant(words[0])}{words[1..]} Kuwaiti {(dinars == 1 ? "dinar" : "dinars")}";
        return fils > 0 ? $"{text} and {fils.ToString(Inv)} fils" : text;
    }

    private static readonly string[] Units =
    [
        "zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten",
        "eleven", "twelve", "thirteen", "fourteen", "fifteen", "sixteen", "seventeen", "eighteen", "nineteen"
    ];

    private static readonly string[] Tens = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy", "eighty", "ninety"];

    private static string Words(long n)
    {
        var sb = new StringBuilder();
        foreach (var (size, name) in new (long, string)[] { (1_000_000_000, "billion"), (1_000_000, "million"), (1_000, "thousand") })
        {
            if (n >= size)
            {
                sb.Append(Words(n / size)).Append(' ').Append(name).Append(' ');
                n %= size;
            }
        }
        if (n >= 100)
        {
            sb.Append(Units[n / 100]).Append(" hundred ");
            n %= 100;
        }
        if (n >= 20)
        {
            sb.Append(Tens[n / 10]);
            if (n % 10 > 0) sb.Append('-').Append(Units[n % 10]);
            sb.Append(' ');
        }
        else if (n > 0)
        {
            sb.Append(Units[n]).Append(' ');
        }
        return sb.ToString().Trim();
    }
}
