using HRMS.Data.Infrastructure;
using HRMS.Data.Repositories;
using HRMS.Domain.Common;
using HRMS.Domain.Payroll;
using HRMS.Domain.Workforce;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Workforce;
using HRMS.Web.Security;
using HRMS.Web.Services;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Rendering;
using Microsoft.AspNetCore.Mvc.ViewEngines;
using Microsoft.AspNetCore.Mvc.ViewFeatures;

namespace HRMS.Web.Controllers;

/// <summary>
/// Workforce - Employees &amp; Kuwait Compliance. One employee list grid,
/// and one Employee Profile page per employee with tabbed sections
/// (Personal Info, Employment, Kuwait Compliance, Documents), rather than
/// Organization Setup's "tabs switch between eight different masters" -
/// here every tab but Kuwait Compliance is the same underlying row.
/// </summary>
[Route("employees")]
public sealed class EmployeesController : Controller
{
    private readonly IEmployeeRepository _employees;
    private readonly IEmployeeComplianceRepository _compliance;
    private readonly IEmployeeDependentRepository _dependents;
    private readonly IEmployeeDocumentRepository _documents;
    private readonly IDocumentStorage _storage;
    private readonly ILookupRepository _lookups;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IPayrollCalendarRepository _calendars;
    private readonly IEmployeePayrollCalendarRepository _payrollCalendar;
    private readonly IEmployeeAuditor _auditor;
    private readonly ILogger<EmployeesController> _logger;

    /// <summary>Dropdowns the Personal Info and Employment tabs need on the profile screen.</summary>
    private static readonly string[] ProfileLookupTypes =
    [
        LookupType.Company, LookupType.Branch, LookupType.Department, LookupType.Section,
        LookupType.JobPosition, LookupType.Designation, LookupType.Grade, LookupType.CostCenter,
        LookupType.Location, LookupType.Country, LookupType.Employee
    ];

    public EmployeesController(
        IEmployeeRepository employees,
        IEmployeeComplianceRepository compliance,
        IEmployeeDependentRepository dependents,
        IEmployeeDocumentRepository documents,
        IDocumentStorage storage,
        ILookupRepository lookups,
        ICurrentUser currentUser,
        ICompanyFilter companyFilter,
        IPayrollCalendarRepository calendars,
        IEmployeePayrollCalendarRepository payrollCalendar,
        IEmployeeAuditor auditor,
        IDateAlertRepository dateAlerts,
        IComplianceDocumentRepository complianceDocuments,
        IEmployeeLeaveTermsRepository leaveTerms,
        IAssetRepository assets,
        IEmployeeProfileRepository profile,
        ILogger<EmployeesController> logger)
    {
        _profile = profile;
        _assets = assets;
        _leaveTerms = leaveTerms;
        _dateAlerts = dateAlerts;
        _complianceDocuments = complianceDocuments;
        _employees = employees;
        _compliance = compliance;
        _dependents = dependents;
        _documents = documents;
        _storage = storage;
        _lookups = lookups;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _calendars = calendars;
        _payrollCalendar = payrollCalendar;
        _auditor = auditor;
        _logger = logger;
    }

    private readonly IDateAlertRepository _dateAlerts;
    private readonly IComplianceDocumentRepository _complianceDocuments;
    private readonly IEmployeeLeaveTermsRepository _leaveTerms;
    private readonly IAssetRepository _assets;
    private readonly IEmployeeProfileRepository _profile;

    /// <summary>The assets the employee holds (Workforce > Assets, db/84) - for users who may open Assets.</summary>
    private async Task<IReadOnlyList<HRMS.Domain.Assets.AssetRow>?> TryGetAssetsAsync(long employeeId)
    {
        if (!_currentUser.CanOpen("assets")) return null;
        try
        {
            return await _assets.EmployeeAsync(employeeId, new AssetScope(_currentUser.ActiveCompanyId, null, _currentUser.UserId), Ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "The assets of employee {EmployeeId} could not be read (run db/84).", employeeId);
            return null;
        }
    }

    /// <summary>
    /// The Employee fields of the Personal Info and Employment tabs (both post with one Save).
    /// A tab the user may only read posts nothing (its fieldset is disabled), so on Save its
    /// fields keep the values the database holds (db/82: a right per tab).
    /// </summary>
    private static readonly string[] PersonalFields =
    [
        "ArabicName", "Block", "BloodGroup", "BuildingNumber", "CompanyPhone", "CurrentResidenceCountryId", "DateOfBirth",
        "EmergencyContactName", "EmergencyContactPhone", "EmergencyContactRelation", "EmployeeCode", "EmployeeNo", "Extension",
        "FatherIsDeceased", "FatherMobileNumber", "FatherName", "FatherOccupation", "FirstName", "FlatNumber", "FloorNumber",
        "Gender", "Landmark", "LastName", "MaritalStatus", "MiddleName", "MobileNumber", "NationalityCountryId", "Neighborhood",
        "PaciNumber", "PersonalEmail", "Religion", "StreetName", "WorkEmail"
    ];

    private static readonly string[] EmploymentFields =
    [
        "Allowances", "BankName", "BasicSalary", "BranchId", "CompanyAssets", "CompanyId", "CostCenterId", "DepartmentId",
        "DesignationId", "EmploymentStatus", "EmploymentType", "GradeId", "HireDate", "Iban", "NoticePeriodDays", "PositionId",
        "ProbationEndDate", "ReportingManagerId", "SectionId", "TerminationDate", "WorkLocationId"
    ];

    private static void KeepStored(Employee model, Employee stored, IEnumerable<string> fields)
    {
        foreach (var name in fields)
        {
            var prop = typeof(Employee).GetProperty(name);
            if (prop is { CanRead: true, CanWrite: true }) prop.SetValue(model, prop.GetValue(stored));
        }
    }

    /// <summary>The employee's own annual leave (db/82); null when db/82 has not been run yet.</summary>
    private async Task<EmployeeLeaveTerms?> TryGetLeaveTermsAsync(long employeeId)
    {
        try
        {
            return await _leaveTerms.GetAsync(employeeId, Ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Annual leave of employee {EmployeeId} could not be read (run db/82).", employeeId);
            return null;
        }
    }

    private CancellationToken Ct => HttpContext.RequestAborted;

    // =======================================================================
    // Shell + grid
    // =======================================================================

    // Views live under Views/Workforce, not Views/Employees - the controller
    // is named after the route ("employees"), the folder after the module
    // ("Workforce", alongside the Kuwait Compliance views it also owns), so
    // every action names its view explicitly rather than relying on the
    // {ControllerName} convention.
    private const string ViewsRoot = "~/Views/Workforce/";

    /// <summary>
    /// The employee an id names exists and is in the user's company (CompanyScope) - checked
    /// on every action that takes an employee id, so changing it in the address or a posted
    /// field cannot reach another company's employee.
    /// </summary>
    // read once per request (the profile's panels call ask the same question four times)
    private readonly Dictionary<long, Task<bool>> _owns = new();

    private Task<bool> OwnsEmployeeAsync(long employeeId)
    {
        if (employeeId <= 0) return Task.FromResult(false);
        if (_currentUser.ActiveCompanyId is null) return Task.FromResult(true);
        if (!_owns.TryGetValue(employeeId, out var owns))
        {
            _owns[employeeId] = owns = ReadOwnsAsync(employeeId);
        }
        return owns;
    }

    private async Task<bool> ReadOwnsAsync(long employeeId)
    {
        var employee = await _employees.GetByIdAsync(employeeId, Ct);
        return employee is not null && _currentUser.Allows(employee.CompanyId);
    }

    private EmployeeAccess Access => _currentUser.EmployeeAccess();
    private static IActionResult NoRight() =>
        new JsonResult(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));

    private static IActionResult NotYours() =>
        new JsonResult(ActionResponse.Failed("That record was not found.", "NOT_FOUND"));

    [HttpGet("")]
    [HttpGet("index")]
    public IActionResult Index() => Access.View ? View(ViewsRoot + "Index.cshtml") : Forbid();

    [HttpGet("grid")]
    public async Task<IActionResult> Grid([FromQuery] GridRequest request, [FromQuery] bool all = false)
    {
        if (!Access.View) return Forbid();
        // Scope the list to the user's active company once they have one,
        // same as every Organization Setup grid.
        // a pinned user's own company always wins over a CompanyId in the query string
        request.CompanyId = _currentUser.ActiveCompanyId ?? request.CompanyId;

        // Top-bar company filter (cookie) - always from the server, never the query string.
        request.CompanyIds = _companyFilter.Csv;

        // all=true: every employee in one response - the page then searches, sorts and pages
        // in the browser, with no further calls (the procedure returns 200 rows per call)
        PagedResult<Employee> page;
        if (all)
        {
            request.Search = null;
            request.IsActive = null;
            request.PageSize = 200;
            var items = new List<Employee>();
            for (request.PageNumber = 1; request.PageNumber <= 500; request.PageNumber++)
            {
                var chunk = await _employees.ListAsync(request, Ct);
                items.AddRange(chunk.Items);
                if (chunk.Items.Count == 0 || items.Count >= chunk.TotalCount) break;
            }
            page = new PagedResult<Employee> { Items = items, TotalCount = items.Count, PageNumber = 1, PageSize = Math.Max(items.Count, 1) };
            request.PageNumber = 1;
        }
        else
        {
            page = await _employees.ListAsync(request, Ct);
        }

        return PartialView(ViewsRoot + "_EmployeesGrid.cshtml", new EmployeeGridViewModel
        {
            Page = page,
            Request = request,
            ClientSide = all,
            Missing = await TryGetCompletenessAsync(page.Items.Select(e => e.EmployeeId))
        });
    }

    // =======================================================================
    // Add - the Profile page in step-by-step mode (Personal -> Employment -> Compliance -> Dependents -> Documents)
    // =======================================================================

    /// <summary>
    /// A brand-new employee gets a dedicated wizard screen rather than the
    /// tabbed Profile page - the two are different jobs (walk someone
    /// through entering a new record vs. letting them jump straight to
    /// whichever section of an existing one they need), so they get
    /// different UIs even though they post to the same Save action.
    /// </summary>
    [HttpGet("add")]
    public async Task<IActionResult> Add()
    {
        if (!Access.Create) return Forbid();
        // Pre-select the company when the top-bar filter is narrowed to exactly one.
        var employee = new Employee { CompanyId = _currentUser.ActiveCompanyId ?? _companyFilter.SingleCompanyId ?? 0 };
        var alertsTask = TryListDateAlertsAsync();
        var lookups = await LoadProfileLookupsAsync(includeInactive: false);

        // Same page as editing (every section, same fields) - shown as a
        // step-by-step wizard instead of tabs.
        return View(ViewsRoot + "Profile.cshtml", new EmployeeProfileViewModel
        {
            Employee = employee,
            IsNew = true,
            Wizard = true,
            ActiveTab = "personal",
            Lookups = lookups,
            PayrollCalendars = await LoadPayrollCalendarsAsync(lookups, null),
            CanChangePayrollCalendar = _currentUser.CanChangePayrollCalendar(),
            CanManageDateAlerts = _currentUser.CanManageDateAlerts(),
            DateAlertRules = await alertsTask
        });
    }

    // =======================================================================
    // Profile - one page, tabbed sections (existing employees)
    // =======================================================================

    [HttpGet("profile/{id:long}")]
    [HttpGet("profile")]
    public async Task<IActionResult> Profile(long id = 0, string? tab = null, bool wizard = false, bool embed = false, string? focus = null)
    {
        // A new employee is created through the Add wizard, not this page -
        // redirect rather than 404 so an old profile/0 link still works.
        if (id <= 0)
        {
            return RedirectToAction(nameof(Add));
        }

        if (!Access.View) return Forbid();

        // Everything the page and its tabs show comes from ONE database call (db/97). A part
        // that call could not give (a database without db/97, or a part that failed) is read
        // on its own - those reads run at the same time.
        var access = Access;
        var showComplianceImages = !wizard && access.ComplianceView && access.DocumentView;
        var clock = System.Diagnostics.Stopwatch.StartNew();
        var data = await TryLoadProfileAsync(new EmployeeProfileLoadRequest(
            id,
            LookupCompanyId: _currentUser.LookupCompany(null),
            UserCompanyId: _currentUser.ActiveCompanyId,
            UserId: _currentUser.UserId,
            IncludeInactive: true,
            WithDateAlerts: _currentUser.CanManageDateAlerts(),
            WithAssets: _currentUser.CanOpen("assets"),
            WithDependents: access.DependentView,
            WithDocuments: access.DocumentView,
            WithComplianceDocuments: showComplianceImages));
        bool Has(string part) => data?.Has(part) == true;

        var employeeTask = Has(EmployeeProfileData.Employee)
            ? Task.FromResult(data!.One<Employee>(EmployeeProfileData.Employee)) : _employees.GetByIdAsync(id, Ct);
        // Compliance is a separate 1:1 record that may not exist yet, even for
        // an existing employee - that is a normal state, rendered as an empty form.
        var complianceTask = Has(EmployeeProfileData.Compliance)
            ? Task.FromResult(data!.One<EmployeeKuwaitCompliance>(EmployeeProfileData.Compliance)) : _compliance.GetAsync(id, Ct);
        var lookupsTask = ProfileLookupTypes.All(t => Has(EmployeeProfileData.LookupPrefix + t))
            ? Task.FromResult(OwnLookups(ProfileLookupTypes.Select(t => data!.Many<LookupItem>(EmployeeProfileData.LookupPrefix + t)).ToArray()))
            : LoadProfileLookupsAsync(includeInactive: true);
        var payrollCalendarTask = Has(EmployeeProfileData.PayrollCalendar)
            ? Task.FromResult(data!.One<EmployeePayrollCalendar>(EmployeeProfileData.PayrollCalendar)) : TryGetPayrollCalendarAsync(id);
        var calendarsTask = Has(EmployeeProfileData.Calendars)
            ? FilterCalendarsAsync(data!.Many<PayrollCalendar>(EmployeeProfileData.Calendars), lookupsTask, payrollCalendarTask)
            : LoadPayrollCalendarsAsync(lookupsTask, payrollCalendarTask);
        var alertsTask = !_currentUser.CanManageDateAlerts() || Has(EmployeeProfileData.DateAlerts)
            ? Task.FromResult<IReadOnlyList<DateAlertRule>>(data?.Many<DateAlertRule>(EmployeeProfileData.DateAlerts) ?? []) : TryListDateAlertsAsync();
        var leaveTermsTask = Has(EmployeeProfileData.LeaveTerms)
            ? Task.FromResult(data!.One<EmployeeLeaveTerms>(EmployeeProfileData.LeaveTerms)) : TryGetLeaveTermsAsync(id);
        var assetsTask = !_currentUser.CanOpen("assets") ? Task.FromResult<IReadOnlyList<HRMS.Domain.Assets.AssetRow>?>(null)
            : Has(EmployeeProfileData.Assets) ? Task.FromResult<IReadOnlyList<HRMS.Domain.Assets.AssetRow>?>(data!.Many<HRMS.Domain.Assets.AssetRow>(EmployeeProfileData.Assets))
            : TryGetAssetsAsync(id);
        await Task.WhenAll(employeeTask, complianceTask, lookupsTask, payrollCalendarTask, calendarsTask, alertsTask, leaveTermsTask, assetsTask);
        Response.Headers["Server-Timing"] = $"profile;desc=\"profile data ({(data is null ? "separate calls" : "one call")})\";dur={clock.ElapsedMilliseconds}";

        var employee = employeeTask.Result;

        // another company's employee answers "not found", like a missing one
        if (employee is null || !_currentUser.Allows(employee.CompanyId))
        {
            return NotFound();
        }

        var compliance = complianceTask.Result;
        var lookups = lookupsTask.Result;
        var payrollCalendar = payrollCalendarTask.Result;
        employee.PayrollCalendarId = payrollCalendar?.PayrollCalendarId;

        // the Dashboard's alert popup shows this page in a frame of the same site
        // (SecurityHeadersMiddleware forbids framing everywhere else)
        if (embed)
        {
            Response.Headers["X-Frame-Options"] = "SAMEORIGIN";
            Response.Headers["Content-Security-Policy"] = Response.Headers["Content-Security-Policy"].ToString()
                .Replace("frame-ancestors 'none'", "frame-ancestors 'self'", StringComparison.Ordinal);
        }
        var focusField = DateAlertFields.Find(focus);

        return View(ViewsRoot + "Profile.cshtml", new EmployeeProfileViewModel
        {
            Employee = employee,
            Compliance = compliance,
            IsNew = false,
            Wizard = wizard,
            ActiveTab = !string.IsNullOrWhiteSpace(tab) ? tab : focusField?.Tab ?? "personal",
            Embed = embed,
            Focus = focusField?.Key,
            Lookups = lookups,
            PayrollCalendar = payrollCalendar,
            PayrollCalendars = calendarsTask.Result,
            CanChangePayrollCalendar = _currentUser.CanChangePayrollCalendar(),
            CanManageDateAlerts = _currentUser.CanManageDateAlerts(),
            DateAlertRules = alertsTask.Result,
            LeaveTerms = leaveTermsTask.Result,
            Assets = assetsTask.Result,
            // the Dependents / Documents tabs and the compliance images, drawn into the page:
            // the browser does not ask for them again
            Preloaded = data is null ? [] : PreloadedPanels(data, id, compliance, showComplianceImages)
        });
    }

    /// <summary>The one-call read of the profile (db/97); null when it cannot be used, so each part is read on its own.</summary>
    private async Task<EmployeeProfileData?> TryLoadProfileAsync(EmployeeProfileLoadRequest request)
    {
        try
        {
            return await _profile.LoadAsync(request, Ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "The employee profile could not be read in one call (run db/97) - reading it part by part.");
            return null;
        }
    }

    /// <summary>The panels of the tabs, built from the one-call read (each needs the same right as its own address).</summary>
    private List<PreloadedPanel> PreloadedPanels(EmployeeProfileData data, long id, EmployeeKuwaitCompliance? compliance, bool showComplianceImages)
    {
        var access = Access;
        var maxMb = (int)(_storage.MaxFileSizeBytes / 1024 / 1024);
        var panels = new List<PreloadedPanel>();

        if (access.DependentView && data.Has(EmployeeProfileData.Dependents))
        {
            panels.Add(new($"/employees/dependents/{id}/grid", ViewsRoot + "Partials/_DependentsGrid.cshtml",
                data.Many<EmployeeDependent>(EmployeeProfileData.Dependents)));
        }

        var complianceRows = data.Has(EmployeeProfileData.ComplianceDocuments)
            ? data.Many<ComplianceDocumentRow>(EmployeeProfileData.ComplianceDocuments) : null;

        if (access.DocumentView && data.Has(EmployeeProfileData.Documents) && (!showComplianceImages || complianceRows is not null))
        {
            IReadOnlyList<EmployeeDocumentRow> rows = data.Many<EmployeeDocumentRow>(EmployeeProfileData.Documents);
            if (showComplianceImages)
            {
                var linked = complianceRows!.Select(r => r.DocumentTypeId).ToHashSet();
                rows = rows.Where(r => !linked.Contains(r.DocumentTypeId)).ToList();
            }
            panels.Add(new($"/employees/documents/{id}/grid" + (showComplianceImages ? "?exceptCompliance=true" : ""),
                ViewsRoot + "Partials/_DocumentsGrid.cshtml",
                new EmployeeDocumentsViewModel { EmployeeId = id, Rows = rows, MaxFileSizeMb = maxMb }));
        }

        if (showComplianceImages && complianceRows is not null)
        {
            var groups = BuildComplianceGroups(complianceRows, compliance);
            panels.Add(new($"/employees/documents/{id}/compliance", ViewsRoot + "Partials/_ComplianceDocuments.cshtml",
                new ComplianceDocumentsViewModel
                {
                    EmployeeId = id,
                    Groups = groups,
                    CanUpload = access.DocumentUpload && access.ComplianceEdit,
                    CanConfirm = access.ComplianceEdit,
                    CanDiscard = access.DocumentDelete && access.ComplianceEdit,
                    MaxFileSizeMb = maxMb
                }));
            panels.Add(new($"/employees/documents/{id}/compliance/thumbs", ViewsRoot + "Partials/_ComplianceThumbs.cshtml",
                new ComplianceDocumentsViewModel { EmployeeId = id, Groups = groups }));
        }
        return panels;
    }

    /// <summary>
    /// Dropdowns the Personal Info and Employment sections need, on both the
    /// Add wizard and the Profile page. <paramref name="includeInactive"/>
    /// is true for an existing employee so a value pointing at a since-
    /// deactivated row does not silently disappear from its dropdown.
    /// </summary>
    private async Task<Dictionary<string, IReadOnlyList<LookupItem>>> LoadProfileLookupsAsync(bool includeInactive)
    {
        // all the lists at once (one call each, run together)
        var companyId = _currentUser.LookupCompany(null);
        var lists = await Task.WhenAll(ProfileLookupTypes.Select(type => _lookups.GetAsync(
            type,
            companyId: companyId,
            parentId: null,
            includeInactive: includeInactive,
            cancellationToken: Ct)));

        return OwnLookups(lists);
    }

    /// <summary>The lists by type (in <see cref="ProfileLookupTypes"/> order); a user pinned to a company only gets that company's.</summary>
    private Dictionary<string, IReadOnlyList<LookupItem>> OwnLookups(IReadOnlyList<LookupItem>[] lists)
    {
        var lookups = new Dictionary<string, IReadOnlyList<LookupItem>>(StringComparer.OrdinalIgnoreCase);
        for (var i = 0; i < ProfileLookupTypes.Length; i++)
        {
            lookups[ProfileLookupTypes[i]] = _currentUser.OwnCompanies(ProfileLookupTypes[i], lists[i]);
        }
        return lookups;
    }

    private static async Task<IReadOnlyList<PayrollCalendar>> FilterCalendarsAsync(IReadOnlyList<PayrollCalendar> all,
        Task<Dictionary<string, IReadOnlyList<LookupItem>>> lookups, Task<EmployeePayrollCalendar?> current)
    {
        await Task.WhenAll(lookups, current);
        return FilterCalendars(all, lookups.Result, current.Result?.PayrollCalendarId);
    }

    /// <summary>The calendars of the companies on the form (active ones, plus the employee's own even when deactivated).</summary>
    private static IReadOnlyList<PayrollCalendar> FilterCalendars(IEnumerable<PayrollCalendar> all,
        IReadOnlyDictionary<string, IReadOnlyList<LookupItem>> lookups, int? currentCalendarId)
    {
        var companies = lookups.TryGetValue(LookupType.Company, out var list) ? list.Select(c => c.Id).ToHashSet() : new HashSet<int>();
        return all
            .Where(c => companies.Contains(c.CompanyId) && (c.IsActive || c.PayrollCalendarId == currentCalendarId))
            .OrderByDescending(c => c.IsDefault).ThenBy(c => c.CalendarName, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    /// <summary>Starts as soon as the lists and the employee's calendar are in, alongside the page's other reads.</summary>
    private async Task<IReadOnlyList<PayrollCalendar>> LoadPayrollCalendarsAsync(
        Task<Dictionary<string, IReadOnlyList<LookupItem>>> lookups, Task<EmployeePayrollCalendar?> current)
    {
        await Task.WhenAll(lookups, current);
        return await LoadPayrollCalendarsAsync(lookups.Result, current.Result?.PayrollCalendarId);
    }

    /// <summary>
    /// The payroll calendars of the companies on the form (active ones, plus the employee's
    /// own even when it has since been deactivated). The page shows the selected company's only.
    /// </summary>
    private async Task<IReadOnlyList<PayrollCalendar>> LoadPayrollCalendarsAsync(
        IReadOnlyDictionary<string, IReadOnlyList<LookupItem>> lookups, int? currentCalendarId)
    {
        try
        {
            var page = await _calendars.ListAsync(new GridRequest
            {
                CompanyId = _currentUser.ActiveCompanyId,
                PageSize = 200,
                SortColumn = "CalendarName"
            }, Ct);
            return FilterCalendars(page.Items, lookups, currentCalendarId);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Payroll calendars could not be loaded for the employee form.");
            return Array.Empty<PayrollCalendar>();
        }
    }

    /// <summary>The employee's payroll calendar; null when db/60 has not been run yet.</summary>
    /// <summary>The reminders on every date field (db/65), for the bells - only for a user who sets them.</summary>
    private async Task<IReadOnlyList<DateAlertRule>> TryListDateAlertsAsync()
    {
        if (!_currentUser.CanManageDateAlerts()) return Array.Empty<DateAlertRule>();
        try
        {
            return await _dateAlerts.ListRulesAsync(Ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "The date field alerts could not be read (run db/65).");
            return Array.Empty<DateAlertRule>();
        }
    }

    /// <summary>
    /// The bell next to a date field: replaces that field's reminders, which apply to every
    /// employee. <paramref name="units"/> and <paramref name="values"/> pair up (M / W / D, 0-99; 0 = on the day).
    /// </summary>
    [HttpPost("date-alerts")]
    public async Task<IActionResult> SaveDateAlerts(string? fieldKey, [FromForm] string[]? units, [FromForm] int[]? values)
    {
        if (!_currentUser.CanManageDateAlerts())
        {
            return Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
        }

        var field = DateAlertFields.Find(fieldKey);
        units ??= [];
        values ??= [];
        if (field is null || units.Length != values.Length)
        {
            return Json(ActionResponse.Failed("This date field does not take alerts.", "VALIDATION"));
        }

        var rules = new List<DateAlertRule>();
        for (var i = 0; i < units.Length; i++)
        {
            var unit = units[i]?.Trim().ToUpperInvariant();
            if (!DateAlertRule.IsUnit(unit) || values[i] < 0 || values[i] > DateAlertRule.MaxValue)
            {
                return Json(ActionResponse.Failed("Each alert needs a number from 0 to 99 and months, weeks or days.", "VALIDATION"));
            }
            // "on the day" is the same in any unit
            var rule = new DateAlertRule { FieldKey = field.Key, UnitCode = values[i] == 0 ? "D" : unit!, Value = values[i] };
            if (!rules.Any(r => r.UnitCode == rule.UnitCode && r.Value == rule.Value)) rules.Add(rule);
        }
        if (rules.Count > DateAlertRule.MaxRulesPerField)
        {
            return Json(ActionResponse.Failed("A date field can have up to 10 alerts.", "VALIDATION"));
        }

        var result = await _dateAlerts.SaveRulesAsync(field.Key, rules, _currentUser.UserId, Ct);
        if (!result.Success) return Json(ActionResponse.Failed(result.Message, result.ErrorCode));

        // what is stored now, read back - the bell shows exactly that
        var stored = (await _dateAlerts.ListRulesAsync(Ct))
            .Where(r => string.Equals(r.FieldKey?.Trim(), field.Key, StringComparison.OrdinalIgnoreCase))
            .Select(r => r.UnitCode?.Trim() + r.Value.ToString(System.Globalization.CultureInfo.InvariantCulture))
            .ToList();
        if (rules.Count == 0 && stored.Count > 0)
        {
            _logger.LogWarning("Removing the alerts of {Field} left {Count} in Employee.DateFieldAlerts (procedure answered {Message}).",
                field.Key, stored.Count, result.Message);
        }
        return Json(new { success = true, message = result.Message, id = result.Id, rules = string.Join(",", stored) });
    }

    private async Task<EmployeePayrollCalendar?> TryGetPayrollCalendarAsync(long employeeId)
    {
        try
        {
            return await _payrollCalendar.GetAsync(employeeId, Ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "The payroll calendar of employee {EmployeeId} could not be read (run db/60).", employeeId);
            return null;
        }
    }

    // =======================================================================
    // Write actions
    // =======================================================================

    /// <summary>Saves Personal Info and Employment together - both tabs are one row.</summary>
    [HttpPost("save")]
    public async Task<IActionResult> Save()
    {
        var model = new Employee();
        var valid = await TryUpdateModelAsync(model);

        // a new employee needs Create; an existing one the edit right of Personal Info or Employment
        var access = Access;
        if (model.EmployeeId > 0 ? !(access.Edit || access.EmploymentEdit) : !access.Create) return NoRight();

        // a tab the user may only read keeps what the database holds
        Employee? stored = null;
        if (model.EmployeeId > 0 && !(access.Edit && access.EmploymentEdit))
        {
            stored = await _employees.GetByIdAsync(model.EmployeeId, Ct);
            if (stored is null) return NotYours();
            if (!access.Edit) KeepStored(model, stored, PersonalFields);
            if (!access.EmploymentEdit) KeepStored(model, stored, EmploymentFields);
            // validate the record as it will be saved (the read-only tab posted nothing)
            ModelState.Clear();
            valid = TryValidateModel(model);
        }
        if (!valid)
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        // once created, the Employment details are mandatory (the wizard may still leave them blank)
        if (model.EmployeeId > 0 && access.EmploymentEdit && !IsWizardPost())
        {
            var missing = new Dictionary<string, string[]>();
            if (model.HireDate is null) missing[nameof(Employee.HireDate)] = [Required];
            if (model.NoticePeriodDays is null) missing[nameof(Employee.NoticePeriodDays)] = [Required];
            if (Request.HasFormContentType && string.IsNullOrWhiteSpace(Request.Form["AnnualLeaveDays"]))
                missing["AnnualLeaveDays"] = [Required];
            if (model.BasicSalary is null or <= 0) missing[nameof(Employee.BasicSalary)] = [Required];
            if (string.IsNullOrWhiteSpace(model.BankName)) missing[nameof(Employee.BankName)] = [Required];
            if (string.IsNullOrWhiteSpace(model.Iban)) missing[nameof(Employee.Iban)] = [Required];
            if (missing.Count > 0) return Json(ActionResponse.Invalid(missing));

            // the Kuwait Compliance tab is saved first (when changed), so the stored record must be complete too
            if (access.ComplianceEdit)
            {
                var storedCompliance = await _compliance.GetAsync(model.EmployeeId, Ct) ?? new EmployeeKuwaitCompliance { EmployeeId = model.EmployeeId };
                var gaps = ComplianceMissing(storedCompliance, model.NationalityCountryId is { } nat ? await IsKuwaitiCountryAsync(nat) : false);
                if (gaps.Count > 0) return Json(ActionResponse.Invalid(gaps));
            }
        }

        // the employee (when editing) and the company chosen must both be the user's
        if (!_currentUser.Allows(model.CompanyId) || (model.EmployeeId > 0 && !await OwnsEmployeeAsync(model.EmployeeId)))
        {
            return NotYours();
        }

        // ---- payroll calendar (db/60): required; once assigned only an administrator changes it
        var isNew = model.EmployeeId <= 0;
        var before = isNew ? null : stored ?? await _employees.GetByIdAsync(model.EmployeeId, Ct);
        var current = isNew ? null : await TryGetPayrollCalendarAsync(model.EmployeeId);
        var reason = Request.HasFormContentType ? Request.Form["PayrollCalendarReason"].ToString().Trim() : string.Empty;
        var (calendarId, calendarError, errorField) = await CheckPayrollCalendarAsync(model, current?.PayrollCalendarId, reason);
        if (calendarError is not null)
        {
            return Json(ActionResponse.Invalid(new Dictionary<string, string[]> { [errorField] = [calendarError] }));
        }

        var result = await _employees.SaveAsync(model, _currentUser.UserId, Ct);

        if (!result.Success)
        {
            _logger.LogInformation(
                "Employee save rejected by the database with {Code}.", result.ErrorCode);
            return Json(ActionResponse.Failed(result.Message, result.ErrorCode));
        }

        var employeeId = isNew ? result.Id : model.EmployeeId;
        var message = result.Message;

        // a new employee: "created" is the first row of their audit trail
        if (isNew && await _employees.GetByIdAsync(employeeId, Ct) is { } created)
        {
            await _auditor.CreatedAsync(created);
        }

        // the calendar is set after the employee row exists; the procedure logs the assignment / change
        if (calendarId is { } cal && cal != current?.PayrollCalendarId)
        {
            SaveResult set;
            try
            {
                set = await _payrollCalendar.SetAsync(employeeId, cal, string.IsNullOrEmpty(reason) ? null : reason, _currentUser.UserId, Ct);
            }
            catch (Exception ex)
            {
                // db/60 not run yet: the employee is saved, the calendar cannot be
                _logger.LogWarning(ex, "Payroll calendar of employee {EmployeeId} could not be saved (run db/60).", employeeId);
                set = SaveResult.Fail("The payroll calendar could not be saved.", "NOT_READY");
            }
            if (!set.Success)
            {
                _logger.LogWarning("Payroll calendar of employee {EmployeeId} not saved: {Code}.", employeeId, set.ErrorCode);
                // the employee itself is saved (a new one must keep its id), so this is reported, not failed
                message = $"{message} {set.Message}";
            }
        }

        // annual leave (Employment Terms, db/82): blank = the Annual Leave type's days
        if ((isNew ? access.Create : access.EmploymentEdit) && Request.HasFormContentType && Request.Form.ContainsKey("AnnualLeaveDays"))
        {
            var raw = Request.Form["AnnualLeaveDays"].ToString().Trim();
            decimal? days = decimal.TryParse(raw, System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var d) ? d : null;
            if (raw.Length > 0 && days is null or < 0 or > 366)
            {
                message = $"{message} Annual leave must be a number of days between 0 and 366 - it was not saved.";
            }
            else
            {
                try
                {
                    var set = await _leaveTerms.SetAsync(employeeId, days, _currentUser.UserId, Ct);
                    if (!set.Success) message = $"{message} {set.Message}";
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Annual leave of employee {EmployeeId} could not be saved (run db/82).", employeeId);
                    message = $"{message} Annual leave could not be saved.";
                }
            }
        }

        // audit: the record as the database now holds it, against the one before the save
        if (before is not null && await _employees.GetByIdAsync(employeeId, Ct) is { } after)
        {
            await _auditor.UpdatedAsync(before, after);
        }

        return Json(ActionResponse.Ok(employeeId, message));
    }

    /// <summary>
    /// The calendar to set (null = leave as is) or an error for the form field it belongs to.
    /// A disabled (locked) field posts nothing, which keeps the assigned calendar.
    /// </summary>
    private async Task<(int? CalendarId, string? Error, string Field)> CheckPayrollCalendarAsync(Employee model, int? currentId, string reason)
    {
        const string field = nameof(Employee.PayrollCalendarId);
        var target = model.PayrollCalendarId ?? currentId;
        if (target is null)
        {
            // required once the company has a payroll calendar (a company not on payroll yet has none)
            var any = await _calendars.ListAsync(new GridRequest { CompanyId = model.CompanyId, IsActive = true, PageSize = 1 }, Ct);
            return any.TotalCount > 0 || any.Items.Count > 0
                ? (null, "Choose the payroll calendar the employee is paid by.", field)
                : (null, null, field);
        }

        var calendar = await _calendars.GetByIdAsync(target.Value, Ct);
        var changing = currentId is not null && target != currentId;

        if (calendar is null || calendar.CompanyId != model.CompanyId)
        {
            return (null, model.PayrollCalendarId is null && currentId is not null
                ? "The employee's payroll calendar belongs to another company. Only an administrator can change it."
                : "Choose a payroll calendar of the employee's company.", field);
        }
        if (changing && !_currentUser.CanChangePayrollCalendar())
        {
            return (null, "Only an administrator can change the payroll calendar once it is assigned.", field);
        }
        if (target != currentId && !calendar.IsActive)
        {
            return (null, "This payroll calendar is inactive.", field);
        }
        if (changing && string.IsNullOrWhiteSpace(reason))
        {
            return (null, "Enter the reason for changing the payroll calendar.", "PayrollCalendarReason");
        }
        return (target, null, field);
    }

    /// <summary>Saves the Kuwait Compliance tab - a separate record, saved independently.</summary>
    [HttpPost("compliance/save")]
    public async Task<IActionResult> SaveCompliance()
    {
        var model = new EmployeeKuwaitCompliance();

        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        if (model.EmployeeId <= 0)
        {
            return Json(ActionResponse.Failed(
                "Save the employee's Personal Info first, then add Kuwait compliance details."));
        }

        if (!Access.ComplianceEdit) return NoRight();
        if (!await OwnsEmployeeAsync(model.EmployeeId))
        {
            return NotYours();
        }

        // once created, the identity documents are mandatory; residency, sponsor and work permit
        // only for a non-Kuwaiti (the wizard may still leave them blank)
        // the nationality chosen on Personal Info in the same save counts (it is saved after this tab)
        var kuwaiti = Access.Edit && int.TryParse(Request.Form["_NationalityCountryId"], out var nationalityId)
            ? await IsKuwaitiCountryAsync(nationalityId)
            : await IsKuwaitiAsync(model.EmployeeId);
        if (!IsWizardPost() && ComplianceMissing(model, kuwaiti) is { Count: > 0 } missing)
        {
            return Json(ActionResponse.Invalid(missing));
        }

        var (code, message) = await _compliance.UpsertAsync(model, _currentUser.UserId, Ct);
        var success = string.Equals(code, ResultCode.Success, StringComparison.Ordinal);

        if (!success)
        {
            _logger.LogInformation("Kuwait compliance save rejected by the database with {Code}.", code);
        }

        return Json(success
            ? ActionResponse.Ok(model.EmployeeId, string.IsNullOrWhiteSpace(message) ? "Saved successfully." : message)
            : ActionResponse.Failed(
                string.IsNullOrWhiteSpace(message) ? "The operation could not be completed." : message, code));
    }

    // =======================================================================
    // Dependents - a one-to-many child list, loaded/saved independently of
    // both the Employee row and the Kuwait Compliance record. The grid slot
    // on the Dependents tab fetches _DependentsGrid.cshtml the same way the
    // Employees list fetches _EmployeesGrid.cshtml, and reloads it after
    // every add/edit/delete rather than manipulating rows in place.
    // =======================================================================

    /// <summary>
    /// The profile's panels in ONE call when the page opens (Dependents, Documents, the Kuwait
    /// Compliance images and thumbnails) instead of one call each. Takes the panels' own
    /// addresses; a panel that cannot be given here is left out and the page fetches it itself.
    /// </summary>
    [HttpPost("panels")]
    public async Task<IActionResult> Panels([FromForm(Name = "url")] string[]? urls)
    {
        var panels = new Dictionary<string, string>(StringComparer.Ordinal);
        urls = (urls ?? []).Distinct().Take(10).ToArray();

        // the reads the panels share start together before the panels are drawn one by one
        var ids = urls.Select(u => PanelUrl.Match(u ?? "")).Where(m => m.Success)
            .Select(m => long.TryParse(m.Groups["id"].Value, out var i) ? i : 0).Where(i => i > 0).Distinct().ToList();
        var access = Access;
        await Task.WhenAll(ids.SelectMany(i => access.ComplianceView && access.DocumentView
            ? new Task[] { OwnsEmployeeAsync(i), ComplianceGroupsAsync(i) }
            : new Task[] { OwnsEmployeeAsync(i) }));

        foreach (var url in urls)
        {
            var m = PanelUrl.Match(url ?? "");
            if (!m.Success || !long.TryParse(m.Groups["id"].Value, out var id)) continue;
            IActionResult result = m.Groups["kind"].Value switch
            {
                "dependents/" when m.Groups["rest"].Value == "grid" => await DependentsGrid(id),
                "documents/" when m.Groups["rest"].Value == "grid" =>
                    await DocumentsGrid(id, string.Equals(m.Groups["q"].Value, "exceptCompliance=true", StringComparison.OrdinalIgnoreCase)),
                "documents/" when m.Groups["rest"].Value == "compliance" => await ComplianceDocuments(id),
                "documents/" when m.Groups["rest"].Value == "compliance/thumbs" => await ComplianceThumbnails(id),
                _ => NotFound()
            };
            if (await RenderPartialAsync(result) is { } html) panels[url!] = html;
        }
        return Json(panels);
    }

    private static readonly Regex PanelUrl = new(
        @"^/employees/(?<kind>dependents/|documents/)(?<id>\d+)/(?<rest>grid|compliance|compliance/thumbs)(?:\?(?<q>[A-Za-z=]+))?$",
        RegexOptions.CultureInvariant, TimeSpan.FromMilliseconds(100));

    /// <summary>The HTML of a partial view result (null for anything else: forbidden, not found).</summary>
    private async Task<string?> RenderPartialAsync(IActionResult result)
    {
        if (result is not PartialViewResult partial || partial.ViewName is null) return null;
        var engine = HttpContext.RequestServices.GetRequiredService<ICompositeViewEngine>();
        var found = engine.GetView(executingFilePath: null, viewPath: partial.ViewName, isMainPage: false);
        if (!found.Success) return null;

        await using var writer = new StringWriter();
        var viewData = new ViewDataDictionary(partial.ViewData ?? ViewData) { Model = partial.Model };
        var context = new ViewContext(ControllerContext, found.View, viewData, TempData, writer, new HtmlHelperOptions());
        await found.View.RenderAsync(context);
        return writer.ToString();
    }

    [HttpGet("dependents/{employeeId:long}/grid")]
    public async Task<IActionResult> DependentsGrid(long employeeId)
    {
        if (!Access.DependentView) return Forbid();
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var dependents = await _dependents.ListAsync(employeeId, Ct);

        return PartialView(ViewsRoot + "Partials/_DependentsGrid.cshtml", dependents);
    }

    [HttpPost("dependents/save")]
    public async Task<IActionResult> SaveDependent()
    {
        var model = new EmployeeDependent();

        if (!await TryUpdateModelAsync(model))
        {
            return Json(ActionResponse.Invalid(CollectErrors()));
        }

        if (model.EmployeeId <= 0)
        {
            return Json(ActionResponse.Failed("Save the employee first, then add dependents."));
        }

        if (!Access.DependentEdit) return NoRight();
        if (!await OwnsEmployeeAsync(model.EmployeeId))
        {
            return NotYours();
        }

        var result = await _dependents.SaveAsync(model, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("dependents/delete")]
    public async Task<IActionResult> DeleteDependent(long id, long employeeId)
    {
        if (!Access.DependentDelete) return NoRight();
        if (!await OwnsEmployeeAsync(employeeId)) return NotYours();

        var result = await _dependents.DeleteAsync(id, employeeId, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    // =======================================================================
    // Documents - every active document type grouped by Document Section,
    // with one upload slot per type. Same grid-slot pattern as Dependents:
    // the tab fetches _DocumentsGrid.cshtml and reloads it after each
    // upload/remove. Files are stored on disk by IDocumentStorage (outside
    // wwwroot); only metadata goes through Documents.usp_EmployeeDocument_Manage.
    // =======================================================================

    [HttpGet("documents/{employeeId:long}/grid")]
    /// <param name="exceptCompliance">The profile shows the Kuwait Compliance documents (Civil ID, Passport,
    /// Residency, Work Permit) in their own panel above the list - leave them out of it.</param>
    public async Task<IActionResult> DocumentsGrid(long employeeId, bool exceptCompliance = false)
    {
        if (!Access.DocumentView) return Forbid();
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var rows = await _documents.ListAsync(employeeId, Ct);
        if (exceptCompliance && Access.ComplianceView)
        {
            var linked = (await _complianceDocuments.ListAsync(employeeId, Ct)).Select(r => r.DocumentTypeId).ToHashSet();
            rows = rows.Where(r => !linked.Contains(r.DocumentTypeId)).ToList();
        }

        return PartialView(ViewsRoot + "Partials/_DocumentsGrid.cshtml", new EmployeeDocumentsViewModel
        {
            EmployeeId = employeeId,
            Rows = rows,
            MaxFileSizeMb = (int)(_storage.MaxFileSizeBytes / 1024 / 1024)
        });
    }

    /// <summary>Uploads (or replaces) the file for one document type.</summary>
    [HttpPost("documents/upload")]
    [RequestSizeLimit(20 * 1024 * 1024)]
    [RequestFormLimits(MultipartBodyLengthLimit = 20 * 1024 * 1024)]
    public async Task<IActionResult> UploadDocument(long employeeId, int documentTypeId, IFormFile? file)
    {
        if (employeeId <= 0 || documentTypeId <= 0)
        {
            return Json(ActionResponse.Failed("Save the employee first, then upload documents."));
        }

        if (file is null)
        {
            return Json(ActionResponse.Failed("Choose a file to upload."));
        }

        if (!Access.DocumentUpload) return NoRight();
        if (!await OwnsEmployeeAsync(employeeId))
        {
            return NotYours();
        }

        var (stored, error) = await _storage.SaveAsync(employeeId, file, Ct);

        if (stored is null)
        {
            return Json(ActionResponse.Failed(error ?? "The file could not be saved."));
        }

        var result = await _documents.AddAsync(new EmployeeDocumentFile
        {
            EmployeeId = employeeId,
            DocumentTypeId = documentTypeId,
            OriginalFileName = stored.OriginalFileName,
            StoredFileName = stored.RelativePath,
            ContentType = stored.ContentType,
            FileSizeBytes = stored.SizeBytes
        }, _currentUser.UserId, Ct);

        if (!result.Success)
        {
            // Nothing points at the new file - don't leave it orphaned on disk.
            var orphan = _storage.Resolve(stored.RelativePath);
            if (orphan is not null)
            {
                System.IO.File.Delete(orphan);
            }

            _logger.LogInformation("Document upload rejected by the database with {Code}.", result.ErrorCode);
        }

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    /// <summary>Streams one uploaded file - inline to view, or as an attachment to download.</summary>
    [HttpGet("documents/{employeeId:long}/file/{attachmentId:long}")]
    public async Task<IActionResult> DocumentFile(long employeeId, long attachmentId, bool download = false)
    {
        if (!Access.DocumentView) return Forbid();
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        var file = await _documents.GetAsync(employeeId, attachmentId, Ct);
        var path = file is null ? null : _storage.Resolve(file.StoredFileName);

        if (file is null || path is null)
        {
            return NotFound();
        }

        // Uploaded content is not app markup: lock it down harder than a page,
        // and never let a browser or proxy keep a copy of an ID document.
        // Viewing inline: only this app may frame it (the document viewer popup shows a PDF in an
        // iframe); a download is never framed. Uploads are PDF / JPG / PNG only (checked on upload).
        Response.Headers["Content-Security-Policy"] =
            "default-src 'none'; img-src 'self'; style-src 'unsafe-inline'; object-src 'self'; frame-ancestors " + (download ? "'none'" : "'self'");
        Response.Headers["X-Frame-Options"] = download ? "DENY" : "SAMEORIGIN";
        Response.Headers.CacheControl = "private, no-store, max-age=0";

        return PhysicalFile(
            path,
            file.ContentType,
            fileDownloadName: download ? file.OriginalFileName : null,
            enableRangeProcessing: true);
    }

    // =======================================================================
    // Kuwait Compliance images (db/71) - Civil ID, Passport, Residency and
    // Work Permit images: on the Documents tab they are confirmed against the
    // expiry date, renewed, and their previous images listed; Kuwait
    // Compliance only shows a thumbnail before each number.
    // Uploads use documents/upload; a new image for a confirmed item waits
    // as a renewal until it is confirmed here.
    // =======================================================================

    /// <summary>The panel on the Documents tab: images, confirmation, renewals, previous images.</summary>
    [HttpGet("documents/{employeeId:long}/compliance")]
    public async Task<IActionResult> ComplianceDocuments(long employeeId)
    {
        var access = Access;
        if (!access.ComplianceView || !access.DocumentView) return Forbid();
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        return PartialView(ViewsRoot + "Partials/_ComplianceDocuments.cshtml", new ComplianceDocumentsViewModel
        {
            EmployeeId = employeeId,
            Groups = await ComplianceGroupsAsync(employeeId),
            // the images apply to the Kuwait Compliance dates: changing them takes the right to edit those
            CanUpload = access.DocumentUpload && access.ComplianceEdit,
            CanConfirm = access.ComplianceEdit,
            CanDiscard = access.DocumentDelete && access.ComplianceEdit,
            MaxFileSizeMb = (int)(_storage.MaxFileSizeBytes / 1024 / 1024)
        });
    }

    /// <summary>The thumbnails before the Civil ID / Passport / Residency / Work Permit numbers on Kuwait Compliance (view only).</summary>
    [HttpGet("documents/{employeeId:long}/compliance/thumbs")]
    public async Task<IActionResult> ComplianceThumbnails(long employeeId)
    {
        if (!Access.ComplianceView || !Access.DocumentView) return Forbid();
        if (!await OwnsEmployeeAsync(employeeId)) return NotFound();

        return PartialView(ViewsRoot + "Partials/_ComplianceThumbs.cshtml", new ComplianceDocumentsViewModel
        {
            EmployeeId = employeeId,
            Groups = await ComplianceGroupsAsync(employeeId)
        });
    }

    // read once per request (the images panel and the thumbnails show the same groups)
    private readonly Dictionary<long, Task<IReadOnlyList<ComplianceDocumentGroup>>> _groups = new();

    private Task<IReadOnlyList<ComplianceDocumentGroup>> ComplianceGroupsAsync(long employeeId)
    {
        if (!_groups.TryGetValue(employeeId, out var groups))
        {
            _groups[employeeId] = groups = ReadComplianceGroupsAsync(employeeId);
        }
        return groups;
    }

    private async Task<IReadOnlyList<ComplianceDocumentGroup>> ReadComplianceGroupsAsync(long employeeId)
    {
        var rowsTask = _complianceDocuments.ListAsync(employeeId, Ct);
        var complianceTask = _compliance.GetAsync(employeeId, Ct);
        await Task.WhenAll(rowsTask, complianceTask);
        return BuildComplianceGroups(rowsTask.Result, complianceTask.Result);
    }

    private static IReadOnlyList<ComplianceDocumentGroup> BuildComplianceGroups(
        IReadOnlyList<ComplianceDocumentRow> rows, EmployeeKuwaitCompliance? compliance)
    {
        return ComplianceDocumentKey.All.Select(key => new ComplianceDocumentGroup
        {
            Key = key,
            ExpiryDate = key switch
            {
                ComplianceDocumentKey.CivilId => compliance?.CivilIdExpiryDate,
                ComplianceDocumentKey.Passport => compliance?.PassportExpiryDate,
                ComplianceDocumentKey.Residency => compliance?.ResidencyExpiryDate,
                _ => compliance?.WorkPermitExpiryDate
            },
            Number = key switch
            {
                ComplianceDocumentKey.CivilId => compliance?.CivilIdNumber,
                ComplianceDocumentKey.Passport => compliance?.PassportNumber,
                ComplianceDocumentKey.Residency => compliance?.ResidencyNumber,
                _ => compliance?.WorkPermitNumber
            },
            Slots = rows.Where(r => r.ComplianceKey == key)
                .GroupBy(r => r.DocumentTypeId)
                .Select(g => new ComplianceDocumentSlot
                {
                    DocumentTypeId = g.Key,
                    Name = g.First().DocumentTypeName,
                    NameAr = g.First().DocumentTypeNameAr,
                    Current = g.FirstOrDefault(r => r.AttachmentId is > 0 && r.ImageState == ComplianceImageState.Current),
                    Renewal = g.FirstOrDefault(r => r.AttachmentId is > 0 && r.ImageState == ComplianceImageState.Renewal),
                    ArchivedCount = g.First().ArchivedCount
                })
                .ToList()
        }).ToList();
    }

    /// <summary>"Previous images": every image of one item - waiting, current and archived.</summary>
    [HttpGet("documents/{employeeId:long}/compliance/history")]
    public async Task<IActionResult> ComplianceDocumentHistory(long employeeId, string? key)
    {
        if (!Access.ComplianceView || !Access.DocumentView) return Forbid();
        if (!ComplianceDocumentKey.IsValid(key) || !await OwnsEmployeeAsync(employeeId)) return NotFound();

        return PartialView(ViewsRoot + "Partials/_ComplianceHistory.cshtml", new ComplianceHistoryViewModel
        {
            EmployeeId = employeeId,
            Key = key!,
            Images = await _complianceDocuments.HistoryAsync(employeeId, key!, Ct)
        });
    }

    /// <summary>Applies the item's new images to the expiry date (and number) - also saved on Kuwait Compliance.</summary>
    [HttpPost("documents/compliance/confirm")]
    public async Task<IActionResult> ConfirmComplianceDocuments(long employeeId, string? key, DateTime? expiryDate, string? number)
    {
        if (!Access.ComplianceEdit) return NoRight();
        if (!ComplianceDocumentKey.IsValid(key)) return Json(ActionResponse.Failed("Unknown compliance item.", "INVALID_REQUEST"));
        if (!await OwnsEmployeeAsync(employeeId)) return NotYours();

        var result = await _complianceDocuments.ConfirmAsync(employeeId, key!, expiryDate, number, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("documents/delete")]
    public async Task<IActionResult> DeleteDocument(long id, long employeeId)
    {
        if (!Access.DocumentDelete) return NoRight();
        if (!await OwnsEmployeeAsync(employeeId)) return NotYours();

        // Soft delete: the row and the file on disk are kept as history.
        var result = await _documents.DeleteAsync(employeeId, id, _currentUser.UserId, Ct);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("delete")]
    public async Task<IActionResult> Delete(long id)
    {
        if (!Access.Delete) return NoRight();
        if (!await OwnsEmployeeAsync(id)) return NotYours();

        var before = await _employees.GetByIdAsync(id, Ct);
        var result = await _employees.DeleteAsync(id, _currentUser.UserId, Ct);
        if (result.Success && before is not null) await _auditor.DeletedAsync(before);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    [HttpPost("toggle")]
    public async Task<IActionResult> Toggle(long id)
    {
        if (!Access.Delete) return NoRight();
        if (!await OwnsEmployeeAsync(id)) return NotYours();

        var result = await _employees.ToggleActiveAsync(id, _currentUser.UserId, Ct);
        if (result.Success && await _employees.GetByIdAsync(id, Ct) is { } now) await _auditor.ActiveChangedAsync(id, now.IsActive);

        return Json(result.Success
            ? ActionResponse.Ok(result.Id, result.Message)
            : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private const string Required = "This field is required.";

    /// <summary>The add-employee wizard posts _wizard=1: there the mandatory details may still be blank.</summary>
    private bool IsWizardPost() =>
        Request.HasFormContentType && Request.Form["_wizard"].ToString() == "1";

    /// <summary>A Kuwaiti national needs no residency, sponsor or work permit.</summary>
    private async Task<bool> IsKuwaitiAsync(long employeeId) =>
        await _employees.GetByIdAsync(employeeId, Ct) is { NationalityCountryId: { } countryId } && await IsKuwaitiCountryAsync(countryId);

    private async Task<bool> IsKuwaitiCountryAsync(int countryId)
    {
        var countries = await _lookups.GetAsync(LookupType.Country, includeInactive: true, cancellationToken: Ct);
        return countries.FirstOrDefault(c => c.Id == countryId)?.Code is { } code
            && (code.Equals("KW", StringComparison.OrdinalIgnoreCase) || code.Equals("KWT", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>The Kuwait Compliance details mandatory once the employee exists (same rules as db/95).</summary>
    private static Dictionary<string, string[]> ComplianceMissing(EmployeeKuwaitCompliance k, bool kuwaiti)
    {
        var missing = new Dictionary<string, string[]>();
        void Need(bool empty, string field) { if (empty) missing[field] = [Required]; }
        Need(string.IsNullOrWhiteSpace(k.CivilIdNumber), nameof(k.CivilIdNumber));
        Need(k.CivilIdExpiryDate is null, nameof(k.CivilIdExpiryDate));
        Need(string.IsNullOrWhiteSpace(k.PassportNumber), nameof(k.PassportNumber));
        Need(k.PassportCountryId is null, nameof(k.PassportCountryId));
        Need(k.PassportExpiryDate is null, nameof(k.PassportExpiryDate));
        if (!kuwaiti)
        {
            Need(string.IsNullOrWhiteSpace(k.ResidencyNumber), nameof(k.ResidencyNumber));
            Need(string.IsNullOrWhiteSpace(k.ResidencyType), nameof(k.ResidencyType));
            Need(k.ResidencyExpiryDate is null, nameof(k.ResidencyExpiryDate));
            Need(string.IsNullOrWhiteSpace(k.SponsorName), nameof(k.SponsorName));
            Need(k.WorkPermitSalary is null or <= 0, nameof(k.WorkPermitSalary));
            Need(string.IsNullOrWhiteSpace(k.WorkPermitDesignation), nameof(k.WorkPermitDesignation));
            Need(string.IsNullOrWhiteSpace(k.WorkPermitDesignationAr), nameof(k.WorkPermitDesignationAr));
        }
        return missing;
    }

    /// <summary>The details each saved employee must have (db/95) - a flag on the Employees list.</summary>
    private async Task<IReadOnlyDictionary<long, EmployeeCompleteness>> TryGetCompletenessAsync(IEnumerable<long> ids)
    {
        try
        {
            return await _employees.CompletenessAsync(ids, Ct);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Employee completeness could not be read (run db/95).");
            return new Dictionary<long, EmployeeCompleteness>();
        }
    }

    private Dictionary<string, string[]> CollectErrors() =>
        ModelState
            .Where(entry => entry.Value?.Errors.Count > 0)
            .ToDictionary(
                entry => entry.Key,
                entry => entry.Value!.Errors.Select(e => e.ErrorMessage).ToArray());
}
