using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Workforce;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Audit;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Audit Report (db/60): every audited transaction of the employees the user can
/// see - payroll calendar assigned / changed, employee created / updated /
/// activated / deactivated / deleted, salary and bank changes, payroll exclusion
/// and inclusion - filtered by employee, transaction type and date, with export.
/// Opened with AUDIT_REPORT_VIEW (System Administrator by default).
/// </summary>
[Route("audit")]
public sealed class AuditController : Controller
{
    private const int PageSize = 50;
    private const int ExportLimit = 20000;

    private readonly IEmployeeAuditRepository _audit;
    private readonly IEmployeeRepository _employees;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;

    public AuditController(IEmployeeAuditRepository audit, IEmployeeRepository employees, ILookupRepository lookups,
                           ICurrentUser currentUser, ICompanyFilter companyFilter, IUiText text)
    {
        _audit = audit;
        _employees = employees;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;

    /// <summary>The transaction-type groups of the filter (prefix "g:").</summary>
    internal static readonly IReadOnlyDictionary<string, string[]> Groups = new Dictionary<string, string[]>
    {
        ["g:calendar"] = [AuditType.CalendarAssigned, AuditType.CalendarChanged],
        ["g:employee"] = [AuditType.EmployeeCreated, AuditType.EmployeeUpdated, AuditType.EmployeeActivated, AuditType.EmployeeDeactivated, AuditType.EmployeeDeleted],
        ["g:salary"] = [AuditType.SalaryChanged, AuditType.BankChanged],
        ["g:payroll"] = [AuditType.PayrollExcluded, AuditType.PayrollIncluded]
    };

    [HttpGet("")]
    public async Task<IActionResult> Index(long? employee, string? type)
    {
        if (!_currentUser.CanViewAudit()) return Forbid();

        var companyId = _currentUser.LookupCompany(null);
        var companies = _currentUser.OwnCompanies(LookupType.Company, await _lookups.GetAsync(LookupType.Company, cancellationToken: Ct));
        if (_companyFilter.SelectedIds.Count > 0)
        {
            companies = companies.Where(c => _companyFilter.SelectedIds.Contains(c.Id)).ToList();
        }
        var employees = _currentUser.OwnCompanies(LookupType.Employee,
            await _lookups.GetAsync(LookupType.Employee, companyId, includeInactive: true, cancellationToken: Ct));

        // a link from an employee's profile opens the report on that employee, all time
        string? name = null;
        if (employee is > 0 && await OwnsEmployeeAsync(employee.Value) is { } e)
        {
            name = $"{e.FirstName} {e.LastName}".Trim();
        }
        else
        {
            employee = null;
        }

        var today = DateTime.Today;
        ViewData["ActiveArea"] = "security";
        return View(new AuditPageModel
        {
            Companies = companies,
            Employees = employees,
            EmployeeId = employee,
            EmployeeName = name,
            Type = type,
            From = employee is null ? today.AddDays(-30) : today.AddYears(-5),
            To = today
        });
    }

    [HttpGet("grid")]
    public async Task<IActionResult> Grid([FromQuery] AuditQuery query)
    {
        if (!_currentUser.CanViewAudit()) return Forbid();
        var filter = await BuildFilterAsync(query, PageSize);
        if (filter is null) return PartialView("_AuditGrid", NothingToShow());

        var one = query.Mode == "employee" && query.Employee is not null;
        return PartialView("_AuditGrid", new AuditGridModel
        {
            Page = await _audit.ListAsync(filter, Ct),
            IsFiltered = (!one && query.Employee is not null) || !string.IsNullOrEmpty(query.Type) || !string.IsNullOrWhiteSpace(query.Search),
            ManyCompanies = !one && _currentUser.ActiveCompanyId is null && _companyFilter.SingleCompanyId is null && query.Company is null,
            OneEmployee = one,
            Sort = query.SortOrDefault,
            Direction = query.DirOrDefault
        });
    }

    /// <summary>
    /// The audit popup of the employee profile: this employee only, with a search bar and the
    /// date range (no company / employee / type pickers). The grid loads through <see cref="Grid"/>.
    /// </summary>
    [HttpGet("employee-panel")]
    public async Task<IActionResult> EmployeePanel(long employee)
    {
        if (!_currentUser.CanViewAudit()) return Forbid();
        if (await OwnsEmployeeAsync(employee) is not { } e) return NotFound();
        var today = DateTime.Today;
        return PartialView("_EmployeeAuditPanel", new EmployeeAuditPanelModel
        {
            EmployeeId = employee,
            EmployeeName = _text.IsArabic && !string.IsNullOrWhiteSpace(e.ArabicName) ? e.ArabicName : $"{e.FirstName} {e.LastName}".Trim(),
            From = today.AddYears(-1),
            To = today
        });
    }

    /// <summary>The filtered rows (up to 20,000) as an Excel workbook.</summary>
    [HttpGet("export")]
    public async Task<IActionResult> Export([FromQuery] AuditQuery query)
    {
        if (!_currentUser.CanViewAudit()) return Forbid();
        query.Page = 1;
        var filter = await BuildFilterAsync(query, ExportLimit);
        var rows = filter is null ? Array.Empty<EmployeeAuditEntry>() : (await _audit.ListAsync(filter, Ct)).Items;

        var L = _text;
        string[] headers =
        [
            L["aud.date_time"], L["emp.employee_no"], L["pr.employee"], L["common.company"], L["aud.transaction_type"],
            L["aud.field"], L["aud.old_value"], L["aud.new_value"], L["aud.reference"], L["aud.remarks"], L["aud.changed_by"]
        ];
        var data = rows.Select(r => (IReadOnlyList<object?>)new object?[]
        {
            Local(r.ActionDate).ToString("yyyy-MM-dd HH:mm", System.Globalization.CultureInfo.InvariantCulture),
            r.EmployeeNo,
            L.IsArabic && !string.IsNullOrWhiteSpace(r.ArabicName) ? r.ArabicName : r.EmployeeName,
            r.CompanyName,
            L.Tr(AuditType.Label(r.TransactionType)),
            r.FieldName is null ? null : L.Tr(r.FieldName),
            r.OldValue,
            r.NewValue,
            r.Reference,
            r.Remarks is null ? null : L.Tr(r.Remarks),
            r.ActionByName
        });
        var bytes = XlsxFile.Write(L["layout.audit_report"], headers, data, [18, 14, 28, 24, 26, 22, 30, 30, 22, 40, 22], rightToLeft: L.IsArabic);
        return File(bytes, XlsxFile.ContentType, $"audit-report-{DateTime.Today:yyyyMMdd}.xlsx");
    }

    // ------------------------------------------------------------ helpers

    /// <summary>The repository filter from the query, scoped to the user's companies; null = nothing to show.</summary>
    private async Task<EmployeeAuditFilter?> BuildFilterAsync(AuditQuery q, int pageSize)
    {
        // a pinned user stays in their company; the top-bar filter narrows the rest
        int? company = _currentUser.ActiveCompanyId;
        if (q.Company is { } c)
        {
            if (!_currentUser.Allows(c) || (_companyFilter.SelectedIds.Count > 0 && !_companyFilter.SelectedIds.Contains(c))) return null;
            company = c;
        }
        if (q.Employee is { } emp && await OwnsEmployeeAsync(emp) is null) return null;

        string[] types = string.IsNullOrWhiteSpace(q.Type)
            ? []
            : Groups.TryGetValue(q.Type, out var group) ? group
            : AuditType.IsKnown(q.Type) ? [q.Type] : [];
        if (!string.IsNullOrWhiteSpace(q.Type) && types.Length == 0) return null;

        // the user's local days -> UTC instants (the log is stored in UTC)
        var from = q.From?.Date;
        var to = q.To?.Date;
        if (from is not null && to is not null && to < from) (from, to) = (to, from);

        return new EmployeeAuditFilter
        {
            CompanyId = company,
            CompanyIds = company is null ? _companyFilter.Csv : null,
            EmployeeId = q.Employee,
            Types = types,
            DateFromUtc = from is { } f ? DateTime.SpecifyKind(f, DateTimeKind.Local).ToUniversalTime() : null,
            DateToUtc = to is { } t ? DateTime.SpecifyKind(t.AddDays(1), DateTimeKind.Local).ToUniversalTime() : null,
            Search = q.Search,
            Sort = q.SortOrDefault,
            Direction = q.DirOrDefault,
            PageNumber = Math.Max(1, q.Page),
            PageSize = pageSize
        };
    }

    private async Task<Employee?> OwnsEmployeeAsync(long employeeId)
    {
        var e = await _employees.GetByIdAsync(employeeId, Ct);
        return e is not null && _currentUser.Allows(e.CompanyId) ? e : null;
    }

    private static AuditGridModel NothingToShow() => new()
    {
        Page = new PagedResult<EmployeeAuditEntry> { PageNumber = 1, PageSize = PageSize },
        IsFiltered = true
    };

    internal static DateTime Local(DateTime utc) => DateTime.SpecifyKind(utc, DateTimeKind.Utc).ToLocalTime();
}
