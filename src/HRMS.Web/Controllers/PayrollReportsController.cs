using System.Globalization;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Web.Localization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll > Payroll Reports (db/51) - kept as a tab rail: Payroll, Salary, Deduction,
/// Overtime and Compliance reports. Each tab lists its reports on the left and the
/// chosen one on the right, for a month (or a whole year) of closed payrolls, one
/// department optionally; every report exports to Excel (CSV) and prints.
/// </summary>
[Route("payroll/reports")]
public sealed class PayrollReportsController : PayrollFinanceControllerBase
{
    private const string PermView = "PAYROLL_REPORT_VIEW";

    private readonly IPayrollFinanceRepository _finance;
    private readonly ILookupRepository _lookups;
    private readonly IUiText _l;

    public PayrollReportsController(IPayrollFinanceRepository finance, ILookupRepository lookups, IUiText l,
                                    ICurrentUser currentUser, ICompanyFilter companyFilter)
        : base(currentUser, companyFilter)
    {
        _finance = finance;
        _lookups = lookups;
        _l = l;
    }

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(Family), new { family = "payroll" });

    [HttpGet("{family}")]
    public async Task<IActionResult> Family(string family, string? report, int? year, string? month, int? dept)
    {
        if (!Can(PermView)) return Forbid();
        if (!ReportCatalog.Families.Contains(family)) return NotFound();

        var data = await LoadAsync(family, report, year, month, dept);
        var periods = data.Periods;
        var companyId = OwnCompany ?? CompanyFilter.SingleCompanyId;
        var departments = companyId is { } cid && data.Report.UsesDepartment
            ? await _lookups.GetAsync(LookupType.Department, cid, cancellationToken: Ct)
            : Array.Empty<LookupItem>();

        var selects = new List<FinanceSelect>();
        if (departments.Count > 0)
        {
            var options = new List<(string, string)> { ("", _l["pr.all_departments"]) };
            options.AddRange(departments.Select(d => (d.Id.ToString(CultureInfo.InvariantCulture), d.Text)));
            selects.Add(new FinanceSelect("dept", _l["common.department"], options, dept?.ToString(CultureInfo.InvariantCulture)));
        }

        var query = new { report = data.Report.Code, year = data.Year, month = data.Month is { } mm ? FinancePeriod.Key(mm) : null, dept };
        return View("~/Views/PayrollReports/Index.cshtml", new ReportPageModel
        {
            Family = family,
            Report = data.Report,
            Reports = ReportCatalog.Of(family),
            Rows = data.Rows,
            HasPeriods = periods.Count > 0,
            ExportUrl = Url.Action(nameof(Export), new { family, query.report, query.year, query.month, query.dept })!,
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(Family), new { family })!,
                Years = YearsOf(periods),
                Months = periods,
                Year = data.Year,
                Month = data.Month,
                Selects = selects,
                Hidden = new Dictionary<string, string?> { ["report"] = data.Report.Code },
                CountText = data.Rows.Count == 1 ? _l["fin.1_row"] : _l["fin.0_rows", PayrollFormat.Count(data.Rows.Count)]
            }
        });
    }

    /// <summary>The report as a CSV file Excel opens (UTF-8 with BOM).</summary>
    [HttpGet("{family}/export")]
    public async Task<IActionResult> Export(string family, string? report, int? year, string? month, int? dept)
    {
        if (!Can(PermView)) return Forbid();
        if (!ReportCatalog.Families.Contains(family)) return NotFound();

        var data = await LoadAsync(family, report, year, month, dept);
        var csv = new StringBuilder();
        CsvWriter.Row(csv, data.Report.Columns.Select(c => (string?)_l[c.LabelKey]).ToArray());
        foreach (var row in data.Rows)
        {
            CsvWriter.Row(csv, data.Report.Columns.Select(c => Plain(row.TryGetValue(c.Key, out var v) ? v : null, c.Kind)).ToArray());
        }
        if (data.Report.Columns.Any(c => c.Total))
        {
            CsvWriter.Row(csv, data.Report.Columns.Select((c, i) => c.Total
                ? Plain(data.Rows.Sum(r => Num(r.TryGetValue(c.Key, out var v) ? v : null)), c.Kind)
                : i == 0 ? (string?)_l["prv.total"] : "").ToArray());
        }

        var period = data.Month is { } mm ? mm.ToString("yyyy-MM", CultureInfo.InvariantCulture) : data.Year?.ToString(CultureInfo.InvariantCulture) ?? "all";
        return CsvWriter.File(this, csv, $"{data.Report.Code.ToLowerInvariant()}_{period}.csv");
    }

    private sealed record ReportData(ReportDefinition Report, IReadOnlyList<DateTime> Periods, int? Year, DateTime? Month,
                                     IReadOnlyList<IDictionary<string, object?>> Rows);

    private async Task<ReportData> LoadAsync(string family, string? report, int? year, string? month, int? dept)
    {
        var def = ReportCatalog.Find(report) is { } r && r.Family == family ? r : ReportCatalog.Of(family)[0];
        var periods = await _finance.ReportPeriodsAsync(OwnCompany, CompanyCsv, Ct);
        var (y, m) = PickPeriod(periods, year, month, defaultToLatest: true);
        y ??= DateTime.Today.Year;
        var rows = await _finance.ReportAsync(def.Code, y, m, def.UsesDepartment ? dept : null, OwnCompany, CompanyCsv, Ct);
        return new ReportData(def, periods, y, m, rows);
    }

    private static decimal Num(object? v) => v switch
    {
        null => 0,
        decimal d => d,
        int i => i,
        long l => l,
        short s => s,
        double db => (decimal)db,
        _ => decimal.TryParse(Convert.ToString(v, CultureInfo.InvariantCulture), NumberStyles.Number, CultureInfo.InvariantCulture, out var x) ? x : 0
    };

    /// <summary>A value as plain text for the CSV (numbers without thousands separators, so Excel reads them as numbers).</summary>
    private string? Plain(object? v, ReportColumnKind kind) => v switch
    {
        null => "",
        DateTime d when kind == ReportColumnKind.Month => d.ToString("yyyy-MM", CultureInfo.InvariantCulture),
        DateTime d => d.ToString(d.TimeOfDay == TimeSpan.Zero ? "yyyy-MM-dd" : "yyyy-MM-dd HH:mm", CultureInfo.InvariantCulture),
        _ when kind == ReportColumnKind.Money => Num(v).ToString("0.000", CultureInfo.InvariantCulture),
        _ when kind is ReportColumnKind.Number or ReportColumnKind.Percent => Num(v).ToString("0.##", CultureInfo.InvariantCulture),
        string s when kind == ReportColumnKind.Status => CodeText(s),
        _ => Convert.ToString(v, CultureInfo.InvariantCulture)
    };

    private string CodeText(string code) => ReportText.Code(_l, code);
}

/// <summary>Status / action codes of the reports in words (fin.code_* labels; an unknown code shows as is).</summary>
public static class ReportText
{
    private static readonly HashSet<string> Known = new(StringComparer.Ordinal)
    {
        "NEW", "LEFT", "CHANGED", "FULL", "RETRY", "GENERATED", "SENT", "SUPERSEDED",
        "DRAFT", "REGISTERED", "VALIDATION", "AWAITING_APPROVAL", "CLOSED", "CANCELLED",
        "CREATED", "SUBMITTED", "APPROVED", "REJECTED", "RETURNED", "REOPENED", "RECALCULATED"
    };

    public static string Code(IUiText l, string? code) =>
        string.IsNullOrEmpty(code) ? "—" : Known.Contains(code) ? l["fin.code_" + code.ToLowerInvariant()] : code;
}
