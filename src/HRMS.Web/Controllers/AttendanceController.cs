using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Attendance;
using HRMS.Domain.Common;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Attendance;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Time &amp; Attendance (db/126):
/// <list type="bullet">
/// <item>Attendance - every employee's day (clock in / out, worked, late, short, overtime, deduction), corrected by hand.</item>
/// <item>Import - the fingerprint device's report (Excel / CSV): its columns are found, its IDs matched to employees.</item>
/// <item>Monthly Summary - each employee's month, posted to the payroll as one-time pay items.</item>
/// <item>Employees - each employee's device ID and attendance pattern (from a date).</item>
/// <item>Settings - the attendance patterns: hours / shifts and the deduction rules.</item>
/// </list>
/// </summary>
[Route("attendance")]
public sealed class AttendanceController : Controller
{
    public const string PermView = "ATTENDANCE_VIEW";
    public const string PermImport = "ATTENDANCE_IMPORT";
    public const string PermPost = "ATTENDANCE_POST";
    public const string PermSetupView = "ATTENDANCE_SETUP_VIEW";
    public const string PermSetupEdit = "ATTENDANCE_SETUP_EDIT";
    private const long MaxFileBytes = 10 * 1024 * 1024;

    private readonly IAttendanceRepository _repo;
    private readonly IAttendanceService _service;
    private readonly ICurrentUser _user;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _l;

    public AttendanceController(IAttendanceRepository repo, IAttendanceService service, ICurrentUser user, ICompanyFilter companyFilter, IUiText l)
    {
        _repo = repo;
        _service = service;
        _user = user;
        _companyFilter = companyFilter;
        _l = l;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private bool Can(string p) => _user.HasPermission(p);
    private AttScope Scope => _service.Scope;
    private AttRights Rights => new()
    {
        CanView = Can(PermView) || Can(PermImport),
        CanImport = Can(PermImport),
        CanPost = Can(PermPost),
        CanSetupView = Can(PermSetupView) || Can(PermSetupEdit),
        CanSetupEdit = Can(PermSetupEdit)
    };

    private async Task<IReadOnlyList<LookupItem>> CompaniesAsync()
    {
        var all = await _companyFilter.GetCompaniesAsync(Ct);
        if (_user.ActiveCompanyId is { } own) return all.Where(c => c.Id == own).ToList();
        var selected = _companyFilter.SelectedIds;
        return selected.Count > 0 ? all.Where(c => selected.Contains(c.Id)).ToList() : all;
    }

    private async Task<int?> CompanyAsync(int? company)
    {
        var companies = await CompaniesAsync();
        if (company is { } c && companies.Any(x => x.Id == c)) return c;
        var preferred = _user.ActiveCompanyId ?? _companyFilter.SingleCompanyId;
        return companies.Any(x => x.Id == preferred) ? preferred : companies.FirstOrDefault()?.Id;
    }

    private static DateTime? ParseMonth(string? month) =>
        DateTime.TryParseExact(month, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;

    private async Task<(IReadOnlyList<DateTime> Months, DateTime Month)> MonthAsync(int? company, string? month)
    {
        var months = (await _repo.MonthsAsync(Scope, company, Ct)).ToList();
        var thisMonth = new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        var m = ParseMonth(month) ?? (months.Count > 0 ? months[0] : thisMonth);
        if (!months.Contains(m)) months.Add(m);
        if (!months.Contains(thisMonth)) months.Add(thisMonth);
        return (months.OrderByDescending(x => x).ToList(), m);
    }

    private IActionResult Result(SaveResult r) =>
        Json(r.Success ? ActionResponse.Ok(r.Id, _l.Tr(r.Message)) : ActionResponse.Failed(_l.Tr(r.Message), r.ErrorCode));

    private IActionResult Denied() => Json(ActionResponse.Failed(_l.Tr("You do not have permission to do this."), "FORBIDDEN"));

    // =======================================================================
    // Attendance (the days)
    // =======================================================================

    [HttpGet("")]
    public async Task<IActionResult> Index(int? company, string? month, string? status, long? employee, string? q)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        var companies = await CompaniesAsync();
        var co = company is { } c && companies.Any(x => x.Id == c) ? c : (int?)null;
        var (months, m) = await MonthAsync(co, month);
        return View(new AttRegisterModel
        {
            Rights = rights, Companies = companies, CompanyId = co, Months = months, Month = m,
            Status = status, EmployeeId = employee, Search = q,
            Kpis = await _repo.KpisAsync(Scope, co, m, employee, Ct)
        });
    }

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(int? company, string? month, string? status, long? employee, string? q, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        var m = ParseMonth(month) ?? new DateTime(DateTime.Today.Year, DateTime.Today.Month, 1);
        var result = await _repo.RecordsAsync(Scope, new AttRecordFilter
        {
            CompanyId = company, Month = m, EmployeeId = employee, Status = string.IsNullOrWhiteSpace(status) ? null : status, Search = q,
            PageNumber = page, PageSize = 50
        }, Ct);
        return PartialView("_Records", new AttRecordsModel
        {
            Page = result, Rights = rights, ManyCompanies = (await CompaniesAsync()).Count > 1 && company is null,
            IsFiltered = !string.IsNullOrWhiteSpace(status) || !string.IsNullOrWhiteSpace(q) || employee is not null
        });
    }

    /// <summary>The form of a day (id) or of a day to add (employee + date).</summary>
    [HttpGet("day")]
    public async Task<IActionResult> Day(long id = 0, long? employee = null, string? date = null)
    {
        if (!Can(PermImport)) return Forbid();
        AttendanceRecord? record = null;
        if (id > 0)
        {
            record = await _repo.RecordAsync(Scope, id, Ct);
            if (record is null) return NotFound();
        }
        var employees = id > 0 ? [] : (await _repo.MatchListAsync(Scope, Ct)).OrderBy(e => e.EmployeeName).ToList();
        return PartialView("_DayForm", new AttDayFormModel
        {
            Record = record, Employees = employees,
            EmployeeId = employee is { } e && employees.Any(x => x.EmployeeId == e) ? e : null,
            Date = ParseDate(date)
        });
    }

    private static DateTime? ParseDate(string? v) =>
        DateTime.TryParseExact(v, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;

    [HttpPost("day/save")]
    public async Task<IActionResult> SaveDay(long id, long? employeeId, string? date, string? clockIn, string? clockOut, bool excused, string? note)
    {
        if (!Can(PermImport)) return Denied();
        DateTime? workDate = DateTime.TryParseExact(date, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d) ? d : null;
        if (id > 0)
        {
            var current = await _repo.RecordAsync(Scope, id, Ct);
            if (current is null) return Denied();
            workDate = current.WorkDate;
        }
        if (workDate is null) return Json(ActionResponse.Failed(_l.Tr("Enter the date."), "VALIDATION"));
        var cin = At(workDate.Value, clockIn);
        var cout = At(workDate.Value, clockOut);
        if (cin is { } i && cout is { } o && o <= i) cout = o.AddDays(1);      // past midnight

        var (result, month) = id > 0
            ? await _repo.EditRecordAsync(Scope, id, cin, cout, excused, note, _user.UserId, Ct)
            : employeeId is > 0
                ? await _repo.AddRecordAsync(Scope, employeeId.Value, workDate.Value, cin, cout, excused, note, _user.UserId, Ct)
                : (SaveResult.Fail("Select the employee.", "VALIDATION"), null);
        // the times corrected in the day form take over from a mark made on the Attendance Sheet
        if (result.Success && id > 0) await _repo.ClearMarkAsync(Scope, id, Ct);
        if (result.Success && month is not null) await _service.RecalculateAsync([month], null, Ct);
        return Result(result);
    }

    private static DateTime? At(DateTime date, string? time) =>
        TimeSpan.TryParseExact(time, ["hh\\:mm", "h\\:mm", "hh\\:mm\\:ss"], CultureInfo.InvariantCulture, out var t) ? date.Date.Add(t) : null;

    /// <summary>Works a month out again (after a change of a pattern or of an assignment).</summary>
    [HttpPost("recalculate")]
    public async Task<IActionResult> Recalculate(int? company, string? month)
    {
        if (!Can(PermImport)) return Denied();
        if (ParseMonth(month) is not { } m) return Json(ActionResponse.Failed(_l.Tr("Select the month."), "VALIDATION"));
        var companies = await CompaniesAsync();
        var list = company is { } c ? companies.Where(x => x.Id == c).ToList() : companies.ToList();
        var locked = await _service.RecalculateAsync(list.Select(x => new AttMonth(x.Id, m)), null, Ct);
        if (locked.Count > 0 && locked.Count == list.Count)
            return Json(ActionResponse.Failed(_l["att.recalc_locked"], "LOCKED"));
        return Result(SaveResult.Ok(0, locked.Count > 0
            ? $"The month was worked out again - not for {locked.Count} company(ies) whose payroll is already created."
            : "The month was worked out again with the attendance settings now."));
    }

    // =======================================================================
    // Import
    // =======================================================================

    [HttpGet("import")]
    public IActionResult Import()
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        return View(new AttImportPageModel { Rights = rights });
    }

    [HttpGet("import/list")]
    public async Task<IActionResult> Imports(int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        return PartialView("_Imports", new AttImportsModel { Page = await _repo.ImportsAsync(Scope, page, Ct), Rights = rights });
    }

    /// <summary>Reads the file and answers what was found: the columns, the employees, the days.</summary>
    [HttpPost("import/preview")]
    [RequestSizeLimit(MaxFileBytes + 64 * 1024)]
    public async Task<IActionResult> Preview(IFormFile? file)
    {
        if (!Can(PermImport)) return Denied();
        if (file is null || file.Length == 0) return Json(ActionResponse.Failed(_l.Tr("Choose the device's report (.xlsx or .csv)."), "VALIDATION"));
        if (file.Length > MaxFileBytes) return Json(ActionResponse.Failed(_l.Tr("The file is larger than 10 MB."), "VALIDATION"));
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        if (ext == ".xls") return Json(ActionResponse.Failed(_l.Tr("This is an old Excel file (.xls) - open it in Excel and save it as .xlsx (or .csv), then import it."), "VALIDATION"));
        List<string[]> rows;
        try
        {
            await using var buffer = new MemoryStream();
            await file.CopyToAsync(buffer, Ct);
            buffer.Position = 0;
            rows = ext switch
            {
                ".xlsx" or ".xlsm" => XlsxFile.Read(buffer),
                ".csv" or ".txt" => XlsxFile.ReadCsv(buffer, out _),
                _ => throw new InvalidDataException()
            };
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            return Json(ActionResponse.Failed(_l.Tr("The file could not be read - use the device's Excel (.xlsx) or CSV report."), "VALIDATION"));
        }
        if (rows.Count < 2) return Json(ActionResponse.Failed(_l.Tr("The file has no rows."), "VALIDATION"));
        if (rows.Count > 100_000) return Json(ActionResponse.Failed(_l.Tr("The file has more than 100,000 rows - split it by month."), "VALIDATION"));
        var preview = await _service.PreviewAsync(Path.GetFileName(file.FileName), rows, Ct);
        return Json(new { success = true, preview });
    }

    public sealed class ImportInput
    {
        public string? Token { get; set; }
        /// <summary>column index -> role (EmployeeId, Date, ClockIn ...).</summary>
        public Dictionary<int, string>? Roles { get; set; }
        /// <summary>device ID -> employee (0 = leave out).</summary>
        public Dictionary<string, long>? Links { get; set; }
        public bool Remember { get; set; }
    }

    private static Dictionary<int, AttColumn> Roles(Dictionary<int, string>? raw) =>
        (raw ?? []).ToDictionary(k => k.Key, k => Enum.TryParse<AttColumn>(k.Value, true, out var r) ? r : AttColumn.None);

    /// <summary>The preview again with the columns chosen.</summary>
    [HttpPost("import/remap")]
    public async Task<IActionResult> Remap([FromBody] ImportInput input)
    {
        if (!Can(PermImport)) return Denied();
        var preview = await _service.RepreviewAsync(input.Token ?? string.Empty, Roles(input.Roles), Ct);
        return preview is null ? Json(ActionResponse.Failed(_l.Tr("The file is no longer open - choose it again."), "EXPIRED"))
                               : Json(new { success = true, preview });
    }

    [HttpPost("import/confirm")]
    public async Task<IActionResult> Confirm([FromBody] ImportInput input)
    {
        if (!Can(PermImport)) return Denied();
        return Result(await _service.ConfirmAsync(input.Token ?? string.Empty, Roles(input.Roles), input.Links ?? [], input.Remember, Ct));
    }

    [HttpPost("import/delete")]
    public async Task<IActionResult> DeleteImport(long id)
    {
        if (!Can(PermImport)) return Denied();
        var (result, months) = await _repo.DeleteImportAsync(Scope, id, _user.UserId, Ct);
        if (result.Success) await _service.RecalculateAsync(months, null, Ct);
        return Result(result);
    }

    /// <summary>The employees to link an unknown ID to (searchable list).</summary>
    [HttpGet("import/employees")]
    public async Task<IActionResult> LinkEmployees()
    {
        if (!Can(PermImport)) return Forbid();
        var list = await _repo.MatchListAsync(Scope, Ct);
        var many = (await CompaniesAsync()).Count > 1;
        return Json(list.OrderBy(e => e.EmployeeName).Select(e => new
        {
            id = e.EmployeeId, text = $"{e.DisplayNo} · {e.EmployeeName}" + (many ? " · " + e.CompanyName : "")
        }));
    }

    // =======================================================================
    // Monthly Summary - posted to the payroll
    // =======================================================================

    [HttpGet("summary")]
    public async Task<IActionResult> Summary(int? company, string? month)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        var companies = await CompaniesAsync();
        var co = await CompanyAsync(company);
        var (months, m) = await MonthAsync(co, month);
        var range = co is { } rc ? await _repo.SheetPeriodAsync(Scope, rc, m, Ct) : null;
        return View(new AttSummaryModel
        {
            Rights = rights, Companies = companies, CompanyId = co, Months = months, Month = m,
            From = range?.StartDate, To = range?.EndDate,
            Locked = co is { } lk && range is not null && (await _repo.SheetLocksAsync(Scope, lk, range.StartDate, range.EndDate, Ct)).Any(l => l.Reason == "PAYROLL"),
            Rows = co is { } c ? await _repo.SummaryAsync(Scope, c, m, Ct) : [],
            Kpis = co is { } c2 ? await _repo.KpisAsync(Scope, c2, m, null, Ct) : new AttendanceKpis()
        });
    }

    [HttpPost("summary/post")]
    public async Task<IActionResult> Post(int company, string? month)
    {
        if (!Can(PermPost)) return Denied();
        if (await CompanyAsync(company) != company || ParseMonth(month) is not { } m) return Denied();
        // the month is worked out again first, so the latest pattern and salary count
        await _service.RecalculateAsync([new AttMonth(company, m)], null, Ct);
        var rows = await _repo.SummaryAsync(Scope, company, m, Ct);
        var payload = rows.Where(r => r.DeductionAmount > 0 || r.OvertimeAmount > 0)
                          .Select(r => (object)new { employeeId = r.EmployeeId, deduction = r.DeductionAmount, overtime = r.OvertimeAmount }).ToList();
        if (payload.Count == 0) return Json(ActionResponse.Failed(_l.Tr("Nothing to post - no deduction or overtime this month."), "VALIDATION"));
        var result = await _repo.PostAsync(Scope, company, m, payload, _user.UserId, Ct);
        if (result.Success) HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        return Result(result);
    }

    [HttpPost("summary/unpost")]
    public async Task<IActionResult> Unpost(int company, string? month)
    {
        if (!Can(PermPost)) return Denied();
        if (await CompanyAsync(company) != company || ParseMonth(month) is not { } m) return Denied();
        return Result(await _repo.UnpostAsync(Scope, company, m, _user.UserId, Ct));
    }

    [HttpGet("summary/export")]
    public async Task<IActionResult> Export(int company, string? month)
    {
        if (!Rights.CanView) return Forbid();
        if (await CompanyAsync(company) != company || ParseMonth(month) is not { } m) return NotFound();
        var rows = await _repo.SummaryAsync(Scope, company, m, Ct);
        var bytes = XlsxFile.Write(_l["att.summary_sheet"],
            [_l["emp.employee_no"], _l["att.col_employee"], _l["common.department"], _l["att.col_pattern"], _l["att.present"], _l["att.late_days"],
             _l["att.late_hm"], _l["att.short_days"], _l["att.short_hm"], _l["att.absent"], _l["att.leave"], _l["att.to_review"],
             _l["att.overtime_hm"], _l["att.deduction_kwd"], _l["att.overtime_kwd"], _l["att.posted"]],
            rows.Select(r => (IReadOnlyList<object?>)new object?[]
            {
                r.EmployeeNo, r.EmployeeName, r.DepartmentName, r.PatternName, r.PresentDays, r.LateDays, AttFormat.HmOrZero(r.LateMinutes),
                r.ShortDays, AttFormat.HmOrZero(r.ShortMinutes), r.AbsentDays, r.LeaveDays, r.ReviewDays, AttFormat.HmOrZero(r.OvertimeMinutes),
                r.DeductionAmount, r.OvertimeAmount, r.IsPosted ? _l.Date(r.PostedDate) : ""
            }), rightToLeft: _l.IsArabic);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    $"attendance-{m:yyyy-MM}.xlsx");
    }

    // =======================================================================
    // Attendance Sheet - employees down the left, the days across
    // =======================================================================

    /// <summary>The range: a From / To of its own, else the payroll period of the month, else the calendar month (62 days at most).</summary>
    private async Task<AttSheetModel> SheetAsync(int? company, string? month, string? from, string? to, string? q)
    {
        var companies = await CompaniesAsync();
        var co = await CompanyAsync(company);
        var (months, m) = await MonthAsync(co, month);
        var f = ParseDate(from);
        var t = ParseDate(to);
        var isPeriod = f is null || t is null;
        // the payroll month's own days (a From / To of its own may reach outside them: those days are greyed)
        var period = co is { } pc ? await _repo.SheetPeriodAsync(Scope, pc, m, Ct) : null;
        var payFrom = period?.StartDate.Date ?? m;
        var payTo = period?.EndDate.Date ?? m.AddMonths(1).AddDays(-1);
        if (isPeriod)
        {
            f = payFrom;
            t = payTo;
        }
        if (t < f) (f, t) = (t, f);
        var clipped = (t!.Value - f!.Value).TotalDays + 1 > AttSheetModel.MaxDays;
        if (clipped) t = f.Value.AddDays(AttSheetModel.MaxDays - 1);
        var days = Enumerable.Range(0, (int)(t.Value - f.Value).TotalDays + 1).Select(i => f.Value.AddDays(i)).ToList();

        var locks = co is { } lc ? await _repo.SheetLocksAsync(Scope, lc, f.Value, t.Value, Ct) : [];
        var lockedDays = days.Select(d => locks.Any(l => l.StartDate.Date <= d && d <= l.EndDate.Date)).ToList();
        IReadOnlyList<AttSheetRow> rows = [];
        IReadOnlyList<int> perDay = days.Select(_ => 0).ToList();
        if (co is { } c)
        {
            var employees = await _repo.SheetEmployeesAsync(Scope, c, f.Value, t.Value, q, Ct);
            if (employees.Count > 0)
            {
                var records = await _repo.SheetDaysAsync(Scope, c, f.Value, t.Value, Ct);
                var holidays = await _repo.SheetHolidaysAsync(Scope, c, f.Value, t.Value, Ct);
                var leave = await _repo.SheetLeaveAsync(Scope, c, f.Value, t.Value, Ct);
                var patterns = (await _repo.PatternsAsync(Scope, ct: Ct)).Where(p => p.CompanyId == c).ToDictionary(p => p.PatternId);
                var ids = employees.Select(e => e.EmployeeId).ToHashSet();
                var assigns = (await _repo.AssignmentsAsync(Scope, ct: Ct)).Where(a => ids.Contains(a.EmployeeId)).ToList();
                (rows, perDay) = AttSheetModel.Build(days, employees, records, holidays, leave, assigns, patterns);
            }
        }
        return new AttSheetModel
        {
            Rights = Rights, Companies = companies, CompanyId = co, Months = months, Month = m,
            From = f.Value, To = t.Value, IsPeriod = isPeriod, Clipped = clipped, Search = q,
            Days = days, Rows = rows, PresentPerDay = perDay, LockedDays = lockedDays, PayrollFrom = payFrom, PayrollTo = payTo,
            PayrollCreated = locks.Any(l => l.Reason == "PAYROLL")
        };
    }

    [HttpGet("sheet")]
    public async Task<IActionResult> Sheet(int? company, string? month, string? from, string? to, string? q)
    {
        if (!Rights.CanView) return Forbid();
        return View(await SheetAsync(company, month, from, to, q));
    }

    public sealed class SheetMarksInput
    {
        public int Company { get; set; }
        public List<AttMark>? Marks { get; set; }
    }

    /// <summary>The days marked on the Attendance Sheet (right click): saved, then their months worked out again.</summary>
    [HttpPost("sheet/save")]
    public async Task<IActionResult> SheetSave([FromBody] SheetMarksInput? input)
    {
        if (!Can(PermImport)) return Denied();
        if (input?.Marks is not { Count: > 0 } marks) return Json(ActionResponse.Failed(_l.Tr("Nothing to save."), "VALIDATION"));
        if (await CompanyAsync(input.Company) != input.Company) return Denied();
        if (marks.Count > 5000) return Json(ActionResponse.Failed(_l.Tr("Too many changes at once - save in smaller parts."), "VALIDATION"));
        var (result, months) = await _repo.SaveMarksAsync(Scope, input.Company, marks, _user.UserId, Ct);
        if (result.Success && months.Count > 0)
            await _service.RecalculateAsync(months.Select(m => new AttMonth(input.Company, m)).ToList(), null, Ct);
        return Result(result);
    }

    [HttpGet("sheet/export")]
    public async Task<IActionResult> SheetExport(int? company, string? month, string? from, string? to, string? q)
    {
        if (!Rights.CanView) return Forbid();
        var model = await SheetAsync(company, month, from, to, q);
        var inv = CultureInfo.InvariantCulture;
        var headers = new List<string> { _l["emp.employee_no"], _l["att.col_employee"], _l["common.department"] };
        headers.AddRange(model.Days.Select(d => d.ToString("dd ddd", _l.IsArabic ? CultureInfo.GetCultureInfo("ar-KW") : inv)));
        headers.AddRange([_l["att.t_present"], _l["att.t_late"], _l["att.t_short"], _l["att.t_absent"], _l["att.t_leave"], _l["att.t_ded"]]);
        var bytes = XlsxFile.Write(_l["att.nav_sheet"], headers,
            model.Rows.Select(r =>
            {
                var cells = new List<object?> { r.Employee.EmployeeNo, PayrollFormat.EmployeeName(_l, r.Employee.EmployeeName, r.Employee.ArabicName), r.Employee.DepartmentName };
                cells.AddRange(r.Cells.Select(c => (object?)(c.Sub is null ? c.Text : $"{c.Text} {c.Sub}")));
                cells.AddRange([r.Present, AttFormat.HmOrZero(r.LateMinutes), AttFormat.HmOrZero(r.ShortMinutes), r.Absent, r.Leave, r.Deduction]);
                return (IReadOnlyList<object?>)cells;
            }), rightToLeft: _l.IsArabic);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
                    $"attendance-sheet-{model.From:yyyy-MM-dd}-{model.To:yyyy-MM-dd}.xlsx");
    }

    // =======================================================================
    // Employees - device IDs and patterns
    // =======================================================================

    [HttpGet("employees")]
    public async Task<IActionResult> Employees(int? company, int? pattern, string? q)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        return View(new AttEmployeesPageModel
        {
            Rights = rights, Companies = await CompaniesAsync(), CompanyId = company, PatternId = pattern, Search = q,
            Patterns = await _repo.PatternsAsync(Scope, active: true, ct: Ct)
        });
    }

    [HttpGet("employees/grid")]
    public async Task<IActionResult> EmployeesGrid(int? company, int? pattern, string? q, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();
        return PartialView("_Employees", new AttEmployeesModel
        {
            Page = await _repo.EmployeesAsync(Scope, company, pattern, q, page, 50, Ct),
            Patterns = await _repo.PatternsAsync(Scope, active: true, ct: Ct),
            Rights = rights,
            ManyCompanies = (await CompaniesAsync()).Count > 1 && company is null,
            IsFiltered = pattern is not null || !string.IsNullOrWhiteSpace(q)
        });
    }

    public sealed class EmployeeRow
    {
        public long EmployeeId { get; set; }
        public string? DeviceUserId { get; set; }
        public bool SetDevice { get; set; }
        public int? PatternId { get; set; }
        public string? EffectiveFrom { get; set; }
    }

    [HttpPost("employees/save")]
    public async Task<IActionResult> SaveEmployees([FromBody] List<EmployeeRow>? rows)
    {
        if (!Can(PermImport)) return Denied();
        if (rows is null || rows.Count == 0) return Json(ActionResponse.Failed(_l.Tr("Select the employees."), "VALIDATION"));
        var payload = rows.Take(2000).Select(r => (object)new
        {
            employeeId = r.EmployeeId, deviceUserId = r.DeviceUserId, setDevice = r.SetDevice, patternId = r.PatternId,
            effectiveFrom = DateTime.TryParseExact(r.EffectiveFrom, "yyyy-MM-dd", CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
                ? d.ToString("yyyy-MM-dd", CultureInfo.InvariantCulture) : null
        }).ToList();
        var result = await _repo.SetEmployeesAsync(Scope, payload, _user.UserId, Ct);
        return Result(result);
    }

    // =======================================================================
    // Settings - attendance patterns (the list and form use payroll-settings.js)
    // =======================================================================

    [HttpGet("settings")]
    public async Task<IActionResult> Settings()
    {
        var rights = Rights;
        if (!rights.CanSetupView) return Forbid();
        return View(new AttSettingsModel { Rights = rights, Companies = await CompaniesAsync() });
    }

    [HttpGet("settings/grid")]
    public async Task<IActionResult> PatternsGrid(string? search, string? status)
    {
        var rights = Rights;
        if (!rights.CanSetupView) return Forbid();
        var list = await _repo.PatternsAsync(Scope, search, status switch { "active" => true, "inactive" => false, _ => null }, Ct);
        return PartialView("_PatternsGrid", new AttPatternsModel
        {
            Patterns = list, Rights = rights, ManyCompanies = (await CompaniesAsync()).Count > 1,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || !string.IsNullOrWhiteSpace(status)
        });
    }

    [HttpGet("settings/form")]
    public async Task<IActionResult> PatternForm(int id = 0)
    {
        if (!Can(PermSetupEdit)) return Forbid();
        var companies = await CompaniesAsync();
        AttendancePattern pattern;
        if (id > 0)
        {
            pattern = await _repo.PatternAsync(id, Ct) ?? new AttendancePattern();
            if (pattern.PatternId == 0 || companies.All(c => c.Id != pattern.CompanyId)) return NotFound();
        }
        else
        {
            // a new pattern: a 10:00 - 22:00 shift with the usual late slabs (15 / 30 / 45 / 60 minutes)
            pattern = new AttendancePattern
            {
                CompanyId = await CompanyAsync(null) ?? 0, ShiftStart = new TimeSpan(8, 0, 0), ShiftEnd = new TimeSpan(17, 0, 0),
                RequiredMinutes = 480, BreakMinutes = 60, GraceMinutes = 10, WeeklyOffDays = "FRI",
                Slabs =
                [
                    new() { RuleKind = AttCodes.Late, FromMinutes = 11, ToMinutes = 15, DeductionType = AttCodes.DayPercent, Value = 10 },
                    new() { RuleKind = AttCodes.Late, FromMinutes = 16, ToMinutes = 30, DeductionType = AttCodes.DayPercent, Value = 25 },
                    new() { RuleKind = AttCodes.Late, FromMinutes = 31, ToMinutes = 45, DeductionType = AttCodes.DayPercent, Value = 40 },
                    new() { RuleKind = AttCodes.Late, FromMinutes = 46, ToMinutes = 60, DeductionType = AttCodes.DayPercent, Value = 50 },
                    new() { RuleKind = AttCodes.Late, FromMinutes = 61, ToMinutes = null, DeductionType = AttCodes.DayPercent, Value = 100 }
                ]
            };
        }
        return PartialView("_PatternForm", new AttPatternFormModel { Pattern = pattern, Companies = companies });
    }

    [HttpPost("settings/save")]
    public async Task<IActionResult> PatternSave()
    {
        if (!Can(PermSetupEdit)) return Denied();
        var model = new AttendancePattern();
        await TryUpdateModelAsync(model);
        var f = Request.Form;
        // the times and the days off come as text / ticks
        model.ShiftStart = TimeSpan.TryParseExact(f["ShiftStart"], "hh\\:mm", CultureInfo.InvariantCulture, out var s) ? s : null;
        model.ShiftEnd = TimeSpan.TryParseExact(f["ShiftEnd"], "hh\\:mm", CultureInfo.InvariantCulture, out var e) ? e : null;
        model.RequiredMinutes = Minutes(f["RequiredHours"]) ?? model.RequiredMinutes;
        model.WeeklyOffDays = string.Join(",", f["OffDays"].Where(d => AttCodes.WeekDays.Contains(d)));
        model.Slabs = model.Slabs.Where(x => x.FromMinutes >= 0 && (x.ToMinutes is null || x.ToMinutes >= x.FromMinutes)).ToList();
        if ((await CompaniesAsync()).All(c => c.Id != model.CompanyId)) return Denied();
        if (model.PatternId > 0 && await _repo.PatternAsync(model.PatternId, Ct) is { } current
            && (await CompaniesAsync()).All(c => c.Id != current.CompanyId)) return Denied();
        if (model.IsFixed && model.ShiftStart is { } ss && model.ShiftEnd is { } se && f["RequiredHours"].ToString().Length == 0)
        {
            // the required minutes follow the shift (less the break) when not given
            var span = (int)((se > ss ? se - ss : se + TimeSpan.FromDays(1) - ss).TotalMinutes) - model.BreakMinutes;
            if (span > 0) model.RequiredMinutes = span;
        }
        return Result(await _repo.SavePatternAsync(model, _user.UserId, Ct));
    }

    /// <summary>"11:30" or "11.5" -> 690.</summary>
    private static int? Minutes(string? v)
    {
        if (string.IsNullOrWhiteSpace(v)) return null;
        if (TimeSpan.TryParseExact(v.Trim(), ["h\\:mm", "hh\\:mm"], CultureInfo.InvariantCulture, out var t)) return (int)t.TotalMinutes;
        return decimal.TryParse(v, NumberStyles.Number, CultureInfo.InvariantCulture, out var h) && h > 0 ? (int)Math.Round(h * 60) : null;
    }

    [HttpPost("settings/toggle")]
    public async Task<IActionResult> PatternToggle(int id)
    {
        if (!Can(PermSetupEdit) || !await OwnsPattern(id)) return Denied();
        return Result(await _repo.TogglePatternAsync(id, _user.UserId, Ct));
    }

    [HttpPost("settings/delete")]
    public async Task<IActionResult> PatternDelete(int id)
    {
        if (!Can(PermSetupEdit) || !await OwnsPattern(id)) return Denied();
        return Result(await _repo.DeletePatternAsync(id, _user.UserId, Ct));
    }

    private async Task<bool> OwnsPattern(int id) =>
        await _repo.PatternAsync(id, Ct) is { } p && (await CompaniesAsync()).Any(c => c.Id == p.CompanyId);
}
