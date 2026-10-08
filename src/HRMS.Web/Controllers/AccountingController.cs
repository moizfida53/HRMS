using System.Globalization;
using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll > Accounting (db/49-50), three sub-sections with Year / Month filters:
/// Payroll Journal (the journal of a closed payroll from the GL mapping - preview,
/// create), GL Posting (export to Excel, record the posting reference, reverse) and
/// Cost Center Allocation (an employee's cost split across cost centers).
/// </summary>
[Route("payroll/accounting")]
public sealed class AccountingController : PayrollFinanceControllerBase
{
    private const string PermView = "PAYROLL_GL_VIEW";
    private const string PermPost = "PAYROLL_GL_POST";

    private readonly IPayrollFinanceRepository _finance;
    private readonly ILookupRepository _lookups;
    private readonly IUiText _l;

    public AccountingController(IPayrollFinanceRepository finance, ILookupRepository lookups, IUiText l,
                                ICurrentUser currentUser, ICompanyFilter companyFilter)
        : base(currentUser, companyFilter)
    {
        _finance = finance;
        _lookups = lookups;
        _l = l;
    }

    private FinanceRights Rights => new() { CanView = Can(PermView) || Can(PermPost), CanAct = Can(PermPost) };

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(Journal));

    // =======================================================================
    // Payroll Journal
    // =======================================================================

    [HttpGet("journal")]
    public async Task<IActionResult> Journal(int? year, string? month, long? run)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var all = await _finance.JournalRunsAsync(OwnCompany, CompanyCsv, null, null, Ct);
        var months = MonthsOf(all);
        var (y, m) = PickPeriod(months, year, month, defaultToLatest: true);
        var runs = all.Where(r => (y is null || r.RunMonth.Year == y) && (m is null || r.RunMonth == m)).ToList();
        var selected = runs.FirstOrDefault(r => r.PayrollRunId == run) ?? runs.FirstOrDefault(r => r.JournalId is null) ?? runs.FirstOrDefault();

        PayrollJournal? journal = null;
        IReadOnlyList<JournalLine> lines = [];
        AccountingDefaults? defaults = null;
        if (selected is not null)
        {
            if (selected.JournalId is { } jid)
            {
                journal = await _finance.JournalAsync(jid, OwnCompany, CompanyCsv, Ct);
                lines = await _finance.JournalLinesAsync(jid, OwnCompany, CompanyCsv, Ct);
            }
            else
            {
                lines = await _finance.JournalPreviewAsync(selected.PayrollRunId, OwnCompany, CompanyCsv, Ct);
            }
            defaults = await _finance.DefaultsAsync(selected.CompanyId, OwnCompany, CompanyCsv, Ct);
        }

        return View("~/Views/Accounting/Journal.cshtml", new JournalPageModel
        {
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(Journal))!,
                Years = YearsOf(months), Months = months, Year = y, Month = m,
                Selects =
                [
                    new FinanceSelect("run", _l["fin.payroll"],
                        runs.Select(r => (r.PayrollRunId.ToString(CultureInfo.InvariantCulture),
                                          r.RunCode + " · " + _l.MonthYear(r.RunMonth) + (ManyCompanies ? " · " + r.CompanyName : "")
                                          + (r.JournalNo is not null ? " · " + r.JournalNo : ""))).ToList(),
                        selected?.PayrollRunId.ToString(CultureInfo.InvariantCulture))
                ],
                CountText = runs.Count == 1 ? _l["fin.1_payroll"] : _l["fin.0_payrolls", PayrollFormat.Count(runs.Count)]
            },
            Rights = rights,
            Runs = runs,
            Run = selected,
            Journal = journal,
            Lines = lines,
            Defaults = defaults
        });
    }

    [HttpPost("journal/create")]
    public async Task<IActionResult> CreateJournal(long run) =>
        Can(PermPost) ? Result(await _finance.CreateJournalAsync(run, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    [HttpPost("journal/defaults")]
    public async Task<IActionResult> SaveDefaults(int companyId, string? accountCode, string? accountName) =>
        Can(PermPost) ? Result(await _finance.SaveDefaultsAsync(companyId, accountCode, accountName, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    /// <summary>The journal as a CSV file Excel opens (UTF-8 with BOM); counted as an export.</summary>
    [HttpGet("journal/{id:long}/export")]
    public async Task<IActionResult> Export(long id)
    {
        if (!Rights.CanView) return Forbid();
        var journal = await _finance.JournalAsync(id, OwnCompany, CompanyCsv, Ct);
        if (journal is null) return NotFound();
        var lines = await _finance.JournalLinesAsync(id, OwnCompany, CompanyCsv, Ct);
        if (Can(PermPost))
        {
            await _finance.JournalActionAsync(id, "EXPORTED", null, OwnCompany, CompanyCsv, UserId, Ct);
            HttpContext.RequestServices.GetService<Services.IPayrollNavCounts>()?.Invalidate();
        }

        var csv = new StringBuilder();
        CsvWriter.Row(csv, _l["prv.journal"], _l["fin.col_date"], _l["fin.col_line"], _l["prv.gl_account"], _l["prv.account_name"],
                      _l["prv.cost_center"], _l["prv.debit_kwd"], _l["prv.credit_kwd"], _l["fin.col_description"]);
        foreach (var l in lines)
        {
            CsvWriter.Row(csv, journal.JournalNo, journal.JournalDate.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture),
                          l.LineNumber.ToString(CultureInfo.InvariantCulture), l.AccountCode, l.AccountName, l.CostCenterName,
                          l.Debit == 0 ? "" : l.Debit.ToString("0.000", CultureInfo.InvariantCulture),
                          l.Credit == 0 ? "" : l.Credit.ToString("0.000", CultureInfo.InvariantCulture), l.Description);
        }
        CsvWriter.Row(csv, journal.JournalNo, "", "", "", _l["prv.total"], "",
                      lines.Sum(x => x.Debit).ToString("0.000", CultureInfo.InvariantCulture),
                      lines.Sum(x => x.Credit).ToString("0.000", CultureInfo.InvariantCulture), "");
        return CsvWriter.File(this, csv, journal.JournalNo + ".csv");
    }

    [HttpPost("journal/{id:long}/posted")]
    public async Task<IActionResult> Posted(long id, string? reference) =>
        Can(PermPost) ? Result(await _finance.JournalActionAsync(id, "POSTED", reference, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    [HttpPost("journal/{id:long}/reverse")]
    public async Task<IActionResult> Reverse(long id, string? reason) =>
        Can(PermPost) ? Result(await _finance.JournalActionAsync(id, "REVERSE", reason, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    // =======================================================================
    // GL Posting
    // =======================================================================

    [HttpGet("posting")]
    public async Task<IActionResult> Posting(int? year, string? month, string? status, string? q, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var months = MonthsOf(await _finance.JournalRunsAsync(OwnCompany, CompanyCsv, null, null, Ct));
        var (y, m) = PickPeriod(months, year, month, defaultToLatest: false);
        status = status is "OPEN" or "READY" or "EXPORTED" or "POSTED" or "REVERSED" ? status : null;
        var result = await _finance.JournalsAsync(new FinanceFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, Year = y, RunMonth = m, Status = status, Search = q, Page = Math.Max(1, page)
        }, Ct);

        return View("~/Views/Accounting/Posting.cshtml", new PostingPageModel
        {
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(Posting))!,
                Years = YearsOf(months), Months = months, Year = y, Month = m, AllYears = true,
                Selects =
                [
                    new FinanceSelect("status", _l["common.status"],
                        [("", _l["common.all_statuses"]), ("OPEN", _l["fin.jv_not_posted"]), ("READY", _l["fin.jv_ready"]),
                         ("EXPORTED", _l["fin.jv_exported"]), ("POSTED", _l["fin.jv_posted"]), ("REVERSED", _l["fin.jv_reversed"])], status)
                ],
                Search = q,
                SearchPlaceholder = _l["fin.search_journals"],
                CountText = result.TotalCount == 1 ? _l["fin.1_journal"] : _l["prv.0_journals", PayrollFormat.Count(result.TotalCount)]
            },
            Rights = rights,
            Page = result,
            ManyCompanies = ManyCompanies,
            IsFiltered = status is not null || !string.IsNullOrWhiteSpace(q)
        });
    }

    // =======================================================================
    // Cost Center Allocation (list and dialog driven by payroll-settings.js)
    // =======================================================================

    [HttpGet("allocation")]
    public IActionResult Allocation()
    {
        if (!Rights.CanView) return Forbid();
        return View("~/Views/Accounting/Allocation.cshtml", new SettingsPageModel
        {
            Rights = new SettingsRights { CanCreate = Can(PermPost), CanEdit = Can(PermPost), CanDelete = Can(PermPost) }
        });
    }

    [HttpGet("allocation/grid")]
    public async Task<IActionResult> AllocationGrid(int? year, int? month, string? search, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        var y = FinancePeriod.ValidYear(year);
        var result = await _finance.AllocationsAsync(new FinanceFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, Year = y,
            RunMonth = y is { } yy && month is >= 1 and <= 12 ? new DateTime(yy, month.Value, 1) : null,
            Search = search, Page = Math.Max(1, page), PageSize = 50
        }, Ct);
        return PartialView("~/Views/Accounting/_AllocationGrid.cshtml", new SettingsGridModel<CostAllocation>
        {
            Page = result,
            Rights = new SettingsRights { CanCreate = rights.CanAct, CanEdit = rights.CanAct, CanDelete = rights.CanAct },
            ManyCompanies = ManyCompanies,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || month is not null
        });
    }

    [HttpGet("allocation/form")]
    public async Task<IActionResult> AllocationForm(int id = 0)
    {
        if (!Can(PermPost)) return Forbid();
        var allocation = id > 0
            ? await _finance.AllocationAsync(id, OwnCompany, CompanyCsv, Ct)
            : new CostAllocation
            {
                EffectiveFrom = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1),
                Lines = [new CostAllocationLine { SharePercent = 100 }]
            };
        if (allocation is null) return NotFound();

        // every company the user works in: the employees and cost centers of each (the procedure checks they match)
        var companies = await CompaniesAsync(id > 0 ? allocation.CompanyId : null);
        var many = companies.Count > 1;
        var employees = new List<LookupItem>();
        var costCenters = new List<LookupItem>();
        foreach (var co in companies)
        {
            foreach (var e in await _lookups.GetAsync(LookupType.Employee, co.Id, cancellationToken: Ct))
            {
                employees.Add(new LookupItem { Id = e.Id, Code = e.Code, Text = many ? co.Text + " · " + e.Text : e.Text });
            }
            foreach (var c in await _lookups.GetAsync(LookupType.CostCenter, co.Id, cancellationToken: Ct))
            {
                costCenters.Add(new LookupItem { Id = c.Id, Code = c.Code, Text = many ? co.Text + " · " + c.Text : c.Text });
            }
        }
        if (id > 0 && allocation.EmployeeId > 0 && employees.All(e => e.Id != allocation.EmployeeId))
        {
            employees.Insert(0, new LookupItem { Id = (int)allocation.EmployeeId, Text = $"{allocation.EmployeeNo} · {allocation.EmployeeName}" });
        }

        return PartialView("~/Views/Accounting/_AllocationForm.cshtml", new AllocationFormModel
        {
            Allocation = allocation, Companies = companies, Employees = employees, CostCenters = costCenters
        });
    }

    [HttpPost("allocation/save")]
    public async Task<IActionResult> AllocationSave()
    {
        var model = new CostAllocation();
        if (!await TryUpdateModelAsync(model)) return Json(ActionResponse.Invalid(ModelState.Where(e => e.Value?.Errors.Count > 0)
            .ToDictionary(e => e.Key, e => e.Value!.Errors.Select(x => x.ErrorMessage).ToArray())));
        if (!Can(PermPost)) return Denied();
        return Result(await _finance.SaveAllocationAsync(model, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("allocation/delete")]
    public async Task<IActionResult> AllocationDelete(int id) =>
        Can(PermPost) ? Result(await _finance.DeleteAllocationAsync(id, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    private async Task<IReadOnlyList<LookupItem>> CompaniesAsync(int? keep)
    {
        var companies = await _lookups.GetAsync(LookupType.Company, includeInactive: keep is not null, cancellationToken: Ct);
        if (OwnCompany is { } own) return companies.Where(c => c.Id == own).ToList();
        var selected = CompanyFilter.SelectedIds;
        return selected.Count > 0 ? companies.Where(c => selected.Contains(c.Id) || c.Id == keep).ToList() : companies;
    }
}

/// <summary>A CSV file Excel opens directly (UTF-8 with BOM, quoted values).</summary>
internal static class CsvWriter
{
    public static void Row(StringBuilder sb, params string?[] values)
    {
        for (var i = 0; i < values.Length; i++)
        {
            if (i > 0) sb.Append(',');
            var v = values[i] ?? string.Empty;
            // a value starting with = + - @ would run as a formula in Excel
            if (v.Length > 0 && "=+-@".Contains(v[0]) && !decimal.TryParse(v, NumberStyles.Number, CultureInfo.InvariantCulture, out _)) v = "'" + v;
            sb.Append('"').Append(v.Replace("\"", "\"\"", StringComparison.Ordinal)).Append('"');
        }
        sb.Append("\r\n");
    }

    public static FileContentResult File(ControllerBase controller, StringBuilder sb, string fileName)
    {
        var bytes = new UTF8Encoding(encoderShouldEmitUTF8Identifier: true).GetPreamble().Concat(Encoding.UTF8.GetBytes(sb.ToString())).ToArray();
        return controller.File(bytes, "text/csv; charset=utf-8", fileName);
    }
}
