using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Helpers;
using HRMS.Web.Localization;
using HRMS.Web.Models.Organization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll Components (db/37-38, db/111) - formerly Pay Items. The salary of the employment
/// contract (Basic Salary + Allowances on the employee profile) is the default component: no
/// approval, always paid (db/107). The exceptions are on four pages, each with its own rights
/// and approval (Security > Create Roles > Payroll Components), and a role can be limited to
/// chosen item types of a page (e.g. only Overtime):
///   /payroll/components/salary      Salary Revisions - increments and decrements; an approved
///                                   revision is applied to the employee profile
///   /payroll/components/earnings    Earnings &amp; Allowances
///   /payroll/components/deductions  Deductions
///   /payroll/components/loans       Loans &amp; Advances - a loan cannot exceed the Basic Salary,
///                                   an instalment over 50% of it is flagged for the approvers
/// The list, form and actions below (payroll/pay-items/...) serve all four pages.
/// </summary>
[Route("payroll/pay-items")]
public sealed class PayItemsController : Controller
{
    private const int MaxImportRows = 2000;
    private const long MaxImportBytes = 5 * 1024 * 1024;
    /// <summary>Loans &amp; Advances: the instalment (with the other monthly deductions) above this share of the Basic Salary is flagged.</summary>
    private const decimal MaxLoanSharePercent = 50m;

    private readonly IPayItemRepository _items;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;
    private readonly IComponentAccess _access;
    private readonly IComponentRightsRepository _componentRights;
    private readonly IEmployeeRepository _employees;

    public PayItemsController(IPayItemRepository items, ICurrentUser currentUser, ICompanyFilter companyFilter, IUiText text,
                              IComponentAccess access, IComponentRightsRepository componentRights, IEmployeeRepository employees)
    {
        _items = items;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
        _access = access;
        _componentRights = componentRights;
        _employees = employees;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;
    /// <summary>Rows per page offered on the list.</summary>
    private static readonly int[] PageSizes = [10, 25, 50];

    private static DateTime ThisMonth => new(DateTime.Today.Year, DateTime.Today.Month, 1);

    /// <summary>The user's rights on the page of an item class (null = not a page).</summary>
    private async Task<ComponentScope?> ScopeAsync(string? cls) =>
        PayrollComponents.ForClass(cls) is { } page ? await _access.ForAsync(page.ItemClass, Ct) : null;

    /// <summary>May open at least one Payroll Components page (the shared panels: employee card, figures).</summary>
    private bool CanViewAny => PayrollComponents.Pages.Any(p => _currentUser.HasPermission(p.View));

    private static PayItemRights RightsOf(ComponentScope s, long? userId) => new()
    {
        CanCreate = s.CanEdit,
        CanEdit = s.CanEdit,
        CanDelete = s.CanDelete,
        CanApproveHr = s.CanApproveL1,
        CanApproveFinance = s.CanApproveL2,
        UserId = userId,
        CanApproveOwn = s.CanApproveOwn,
        AllowedCodes = s.AllowedCodes,
        ItemClass = s.Page.ItemClass
    };

    /// <summary>The item and the user's rights on its page - null when the item is gone or not theirs to see.</summary>
    private async Task<(PayItem Item, ComponentScope Scope)?> ItemScopeAsync(long id)
    {
        var item = await _items.GetAsync(id, OwnCompany, Ct);
        if (item is null || await ScopeAsync(item.ItemClass) is not { } scope || !scope.CanView || !scope.Allows(item.ComponentCode)) return null;
        return (item, scope);
    }

    // =======================================================================
    // Pages
    // =======================================================================

    /// <summary>The old Pay Items address: the first Payroll Components page the user may open.</summary>
    [HttpGet("")]
    public async Task<IActionResult> Index(long? emp, string? status, string? cls)
    {
        var page = PayrollComponents.ForClass(cls) is { } p && _currentUser.HasPermission(p.View) ? p : await _access.FirstPageAsync(Ct);
        if (page is null) return Forbid();
        var query = new List<string>();
        if (emp is { } e) query.Add("emp=" + e.ToString(CultureInfo.InvariantCulture));
        if (!string.IsNullOrEmpty(status)) query.Add("status=" + Uri.EscapeDataString(status));
        return Redirect(page.Url + (query.Count > 0 ? "?" + string.Join("&", query) : ""));
    }

    [HttpGet("/payroll/components/{route}")]
    public async Task<IActionResult> Components(string route, long? emp, string? status)
    {
        if (PayrollComponents.ForRoute(route) is not { } page) return NotFound();
        var scope = await _access.ForAsync(page.ItemClass, Ct);
        if (!scope.CanView) return Forbid();
        var employees = await _items.EmployeesAsync(OwnCompany, CompanyCsv, Ct);
        return View("Index", new PayItemsPageModel
        {
            Employees = employees,
            SelectedEmployeeId = emp is { } e && employees.Any(x => x.EmployeeId == e) ? e : null,
            SelectedStatus = status,
            Rights = RightsOf(scope, UserId),
            ManyCompanies = employees.Select(x => x.CompanyId).Distinct().Count() > 1,
            Page = page
        });
    }

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(string? search, long? emp, string? cls, string? status, int page = 1, int size = 25)
    {
        var scope = await ScopeAsync(cls);
        if (scope is null || !scope.CanView) return Forbid();
        size = PageSizes.Contains(size) ? size : 25;
        var result = await _items.ListAsync(Filter(search, emp, scope, status, page, size), Ct);

        // Salary Revisions: the history icon only for employees whose salary has changed (a salary
        // component with more than one amount - the contract amount and at least one revision)
        IReadOnlySet<long>? withHistory = null;
        if (scope.Page.ItemClass == ItemClass.Salary && result.Items.Count > 0)
        {
            var all = await _items.ListAsync(Filter(null, emp, scope, "ALL", 1, 10000), Ct);
            var onPage = result.Items.Select(i => i.EmployeeId).ToHashSet();
            withHistory = all.Items.Where(i => onPage.Contains(i.EmployeeId))
                                   .GroupBy(i => (i.EmployeeId, i.PayComponentId))
                                   .Where(g => g.Count() > 1)
                                   .Select(g => g.Key.EmployeeId)
                                   .ToHashSet();
        }

        return PartialView(scope.Page.ItemClass == ItemClass.Salary ? "_SalaryRevisionsGrid" : "_PayItemsGrid", new PayItemsGridModel
        {
            WithSalaryHistory = withHistory,
            Page = result,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || emp is not null || (status ?? "OPEN") != "OPEN",
            Rights = RightsOf(scope, UserId),
            ManyCompanies = _companyFilter.SelectedIds.Count != 1 && OwnCompany is null,
            PageSize = size,
            PageSizes = PageSizes,
            ItemClass = scope.Page.ItemClass
        });
    }

    [HttpGet("kpis")]
    public async Task<IActionResult> Kpis(string? cls)
    {
        if (!CanViewAny) return Forbid();
        var summary = await _items.SummaryAsync(OwnCompany, CompanyCsv, ThisMonth, Ct) ?? new PayItemSummary { SummaryMonth = ThisMonth };

        // Salary Revisions: the monthly salary, and this month's increments and decrements
        if (PayrollComponents.ForClass(cls)?.ItemClass == ItemClass.Salary)
        {
            var scope = await _access.ForAsync(ItemClass.Salary, Ct);
            if (!scope.CanView) return Forbid();
            var all = await _items.ListAsync(Filter(null, null, scope, "ALL", 1, 10000), Ct);
            var revisions = all.Items
                .Where(i => i.ReplacedAmount is not null && i.StartMonth == ThisMonth && !i.IsEnded
                            && i.Status is PayItemStatus.Active or PayItemStatus.Pending)
                .Select(i => i.Amount - i.ReplacedAmount!.Value)
                .ToList();
            return PartialView("_SalaryKpis", new SalaryKpisModel
            {
                Summary = summary,
                Month = ThisMonth,
                IncrementCount = revisions.Count(d => d > 0),
                IncrementAmount = revisions.Where(d => d > 0).Sum(),
                DecrementCount = revisions.Count(d => d < 0),
                DecrementAmount = -revisions.Where(d => d < 0).Sum(),
                PendingCount = all.Items.Count(i => i.IsPending)
            });
        }

        ViewData["ItemClass"] = PayrollComponents.ForClass(cls)?.ItemClass;
        return PartialView("_PayItemKpis", summary);
    }

    [HttpGet("employee/{id:long}")]
    public async Task<IActionResult> Employee(long id)
    {
        if (!CanViewAny) return Forbid();
        var summary = await _items.EmployeeSummaryAsync(id, OwnCompany, ThisMonth, Ct);
        return summary is null ? Content(string.Empty) : PartialView("_PayItemEmployee", summary);
    }

    /// <summary>
    /// The form's reference panel: what the employee has now (salary, allowances, earnings,
    /// deductions, loans) with the amounts paid and still due - of the pages and item types
    /// the user may see.
    /// </summary>
    [HttpGet("employee-items/{id:long}")]
    public async Task<IActionResult> EmployeeItems(long id)
    {
        if (!CanViewAny) return Forbid();
        var summary = await _items.EmployeeSummaryAsync(id, OwnCompany, ThisMonth, Ct);
        if (summary is null) return Content(string.Empty);
        var scopes = new Dictionary<string, ComponentScope>();
        foreach (var p in PayrollComponents.Pages) scopes[p.ItemClass] = await _access.ForAsync(p.ItemClass, Ct);
        var list = await _items.ListAsync(Filter(null, id, null, "ALL", 1, 500), Ct);
        return PartialView("_PayItemReference", new PayItemReferenceModel
        {
            Summary = summary,
            Items = list.Items.Where(x => x.EmployeeId == id && scopes.TryGetValue(x.ItemClass, out var s) && s.CanView && s.Allows(x.ComponentCode)).ToList(),
            Month = ThisMonth
        });
    }

    /// <summary>Figures for the loan checks of the form (basic and monthly salary, balance, monthly deductions).</summary>
    [HttpGet("employee-figures/{id:long}")]
    public async Task<IActionResult> EmployeeFigures(long id)
    {
        if (!CanViewAny) return Forbid();
        var s = await _items.EmployeeSummaryAsync(id, OwnCompany, ThisMonth, Ct);
        if (s is null) return Json(null);
        var latest = await LatestBasicAsync(id);
        return Json(new
        {
            monthlySalary = s.MonthlySalary,
            basicSalary = await BasicSalaryAsync(id),
            // Salary Revisions: a new revision follows the latest approved Basic Salary (it may start later than now)
            latestBasic = latest?.Amount ?? await BasicSalaryAsync(id),
            latestBasicFrom = latest is null ? null : PayItemFormat.MonthValue(latest.StartMonth),
            loanBalance = s.LoanBalance,
            loanPending = s.LoanPending,
            monthlyDeductions = s.MonthlyDeductions,
            maxSharePercent = MaxLoanSharePercent
        });
    }

    /// <summary>Salary Revisions: every amount of the employee's salary - contract and revisions - by month.</summary>
    [HttpGet("salary-history/{employeeId:long}")]
    public async Task<IActionResult> SalaryHistory(long employeeId)
    {
        var scope = await _access.ForAsync(ItemClass.Salary, Ct);
        if (!scope.CanView) return Forbid();
        var summary = await _items.EmployeeSummaryAsync(employeeId, OwnCompany, ThisMonth, Ct);
        if (summary is null) return NotFound();
        var list = await _items.ListAsync(Filter(null, employeeId, scope, "ALL", 1, 500), Ct);
        return PartialView("_SalaryHistory", new SalaryHistoryModel
        {
            Employee = summary,
            Items = list.Items.Where(x => x.EmployeeId == employeeId && x.ItemClass == ItemClass.Salary).ToList(),
            Month = ThisMonth
        });
    }

    [HttpGet("form")]
    public async Task<IActionResult> Form(long id = 0, long? emp = null, string? cls = null)
    {
        PayItem? item = null;
        ComponentScope? scope;
        if (id > 0)
        {
            if (await ItemScopeAsync(id) is not { } found || !found.Scope.CanEdit) return Forbid();
            (item, scope) = found;
            if (item.IsEnded) return NotFound();
        }
        else
        {
            scope = await ScopeAsync(cls);
            if (scope is null || !scope.CanEdit) return Forbid();
        }

        var mode = item switch
        {
            null => "new",
            { ItemClass: ItemClass.Salary, Status: PayItemStatus.Active } => "revise",
            { ItemClass: ItemClass.Loan, Status: PayItemStatus.Active } => "locked",
            { IsUsed: true } => "locked",
            _ => "edit"
        };

        // a salary revision applies from a later month than the current amount: next month by default
        var defaultMonth = mode == "revise" ? Max(ThisMonth.AddMonths(1), item!.StartMonth.AddMonths(1))
                         : scope.Page.ItemClass == ItemClass.Salary ? ThisMonth.AddMonths(1) : ThisMonth;
        var types = await _items.TypesAsync(OwnCompany, CompanyCsv, Ct);
        return PartialView("_PayItemForm", new PayItemFormModel
        {
            Item = item,
            EmployeeId = item?.EmployeeId ?? emp,
            ItemClass = scope.Page.ItemClass,
            FixedClass = true,
            Employees = await _items.EmployeesAsync(OwnCompany, CompanyCsv, Ct),
            // the page's item types the user may work with (the item's own type stays offered)
            Types = types.Where(t => t.ItemClass == scope.Page.ItemClass && (scope.Allows(t.ComponentCode) || t.PayComponentId == item?.PayComponentId)).ToList(),
            Months = PayItemFormat.MonthOptions(DateTime.Today, item?.StartMonth, item?.EndMonth, defaultMonth),
            DefaultMonth = defaultMonth,
            Mode = mode
        });
    }

    [HttpGet("history/{id:long}")]
    public async Task<IActionResult> History(long id)
    {
        if (await ItemScopeAsync(id) is not { } found) return Forbid();
        return PartialView("_PayItemHistory", new PayItemHistoryModel
        {
            Item = found.Item,
            Entries = await _items.HistoryAsync(id, OwnCompany, Ct)
        });
    }

    // =======================================================================
    // Changes
    // =======================================================================

    [HttpPost("save")]
    public async Task<IActionResult> Save(PayItemInput input)
    {
        if (!ModelState.IsValid)
        {
            return Json(ActionResponse.Failed("Check the amounts and months - one of them is not a valid value.", "VALIDATION"));
        }

        // the item type decides the page, and so the rights
        var type = (await _items.TypesAsync(OwnCompany, CompanyCsv, Ct)).FirstOrDefault(t => t.PayComponentId == input.PayComponentId);
        if (type is null) return Json(ActionResponse.Failed("Select an item type.", "VALIDATION"));
        if (await ScopeAsync(type.ItemClass) is not { } scope || !scope.CanEdit || !scope.Allows(type.ComponentCode)) return Denied();
        if (input.EmployeePayItemId > 0 && await ItemScopeAsync(input.EmployeePayItemId) is not { Scope.CanEdit: true }) return Denied();

        // Loans & Advances: never more than the Basic Salary; an instalment over 50% of it is flagged
        string? warning = null;
        if (type.ItemClass == ItemClass.Loan && input.EmployeePayItemId == 0)
        {
            var check = await LoanCheckAsync(input);
            if (check.Error is not null) return Json(ActionResponse.Failed(check.Error, "LOAN_LIMIT"));
            warning = check.Warning;
        }

        var result = await _items.SaveAsync(input, OwnCompany, CompanyCsv, UserId, Ct);
        if (result.Success && warning is not null)
        {
            result = new Domain.Common.SaveResult { Success = true, Id = result.Id, Message = $"{_text.Tr(result.Message)} {warning}" };
        }
        return Result(result);
    }

    [HttpPost("approve")]
    public async Task<IActionResult> Approve(long id, string? comment)
    {
        if (await ItemScopeAsync(id) is not { } found) return Json(ActionResponse.Failed("This pay item no longer exists.", "NOT_FOUND"));
        var (item, scope) = found;
        if (!RightsOf(scope, UserId).CanApprove(item)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        var result = await _items.ActionAsync("APPROVE", id, OwnCompany, CompanyCsv, UserId, comment, allowSelfApproval: scope.CanApproveOwn,
                                              expectedLevel: item.ApprovalLevel, cancellationToken: Ct);

        // Salary Revisions: once fully approved, the revision is the employee's salary on their profile
        if (result.Success && item.ItemClass == ItemClass.Salary)
        {
            try
            {
                if (await _componentRights.ApplySalaryRevisionAsync(id, UserId, Ct))
                {
                    result = new Domain.Common.SaveResult
                    {
                        Success = true, Id = result.Id,
                        Message = $"{_text.Tr(result.Message)} {_text.Tr("The employee profile now shows the new salary.")}"
                    };
                }
            }
            catch (Exception)
            {
                // db/111 not run yet: the revision is approved and paid; the profile keeps its figure
            }
        }
        return Result(result);
    }

    [HttpPost("reject")]
    public async Task<IActionResult> Reject(long id, string? comment)
    {
        if (await ItemScopeAsync(id) is not { } found) return Json(ActionResponse.Failed("This pay item no longer exists.", "NOT_FOUND"));
        var (item, scope) = found;
        if (!RightsOf(scope, UserId).CanApprove(item)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _items.ActionAsync("REJECT", id, OwnCompany, CompanyCsv, UserId, comment, expectedLevel: item.ApprovalLevel, cancellationToken: Ct));
    }

    [HttpPost("end")]
    public async Task<IActionResult> End(long id, string? endMonth, string? comment)
    {
        if (await ItemScopeAsync(id) is not { Scope.CanEdit: true }) return Denied();
        DateTime? month = null;
        if (!string.IsNullOrWhiteSpace(endMonth))
        {
            if (!DateTime.TryParseExact(endMonth, "yyyy-MM", CultureInfo.InvariantCulture, DateTimeStyles.None, out var m))
            {
                return Json(ActionResponse.Failed("Select the last month.", "VALIDATION"));
            }
            month = m;
        }
        return Result(await _items.ActionAsync("END", id, OwnCompany, CompanyCsv, UserId, comment, month, cancellationToken: Ct));
    }

    [HttpPost("delete")]
    public async Task<IActionResult> Delete(long id, string? comment)
    {
        if (await ItemScopeAsync(id) is not { Scope.CanDelete: true }) return Denied();
        return Result(await _items.ActionAsync("DELETE", id, OwnCompany, CompanyCsv, UserId, comment, cancellationToken: Ct));
    }

    // =======================================================================
    // Loans & Advances
    // =======================================================================

    /// <summary>The latest approved Basic Salary amount (the one a new revision replaces), whatever month it starts.</summary>
    private async Task<PayItem?> LatestBasicAsync(long employeeId)
    {
        var salary = await _items.ListAsync(new PayItemFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, EmployeeId = employeeId, ItemClass = ItemClass.Salary,
            Status = "ACTIVE", PageNumber = 1, PageSize = 200
        }, Ct);
        return salary.Items
            .Where(i => i.EmployeeId == employeeId && string.Equals(i.ComponentCode, "BASIC", StringComparison.OrdinalIgnoreCase)
                        && i.AppliesMode == AppliesMode.Monthly && i.EndMonth is null)
            .OrderByDescending(i => i.StartMonth).ThenByDescending(i => i.EmployeePayItemId).FirstOrDefault();
    }

    /// <summary>The employee's Basic Salary now: the Basic Salary component in force, else the profile.</summary>
    private async Task<decimal> BasicSalaryAsync(long employeeId)
    {
        var salary = await _items.ListAsync(new PayItemFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, EmployeeId = employeeId, ItemClass = ItemClass.Salary,
            Status = "ACTIVE", PageNumber = 1, PageSize = 200
        }, Ct);
        var basic = salary.Items
            .Where(i => i.EmployeeId == employeeId && string.Equals(i.ComponentCode, "BASIC", StringComparison.OrdinalIgnoreCase)
                        && i.AppliesMode == AppliesMode.Monthly && i.StartMonth <= ThisMonth && (i.EndMonth is null || i.EndMonth >= ThisMonth))
            .OrderByDescending(i => i.StartMonth).FirstOrDefault();
        if (basic is not null) return basic.Amount;
        return (await _employees.GetByIdAsync(employeeId, Ct))?.BasicSalary ?? 0m;
    }

    /// <summary>
    /// A new loan or advance: the total may not exceed the Basic Salary (refused); the monthly
    /// instalment with the employee's other monthly deductions over 50% of it is allowed but
    /// flagged - the approvers decide.
    /// </summary>
    private async Task<(string? Error, string? Warning)> LoanCheckAsync(PayItemInput input)
    {
        var basic = await BasicSalaryAsync(input.EmployeeId);
        if (basic <= 0) return (_text.Tr("The employee has no Basic Salary - a loan or advance cannot be given."), null);

        var total = input.TotalAmount ?? (input.Amount ?? 0) * (input.InstalmentCount ?? 1);
        if (total > basic)
        {
            return (string.Format(CultureInfo.InvariantCulture, _text.Tr("The loan ({0} KWD) cannot be more than the Basic Salary ({1} KWD)."),
                                  PayrollFormat.Money(total), PayrollFormat.Money(basic)), null);
        }

        var count = Math.Max(1, input.InstalmentCount ?? 1);
        var monthly = Math.Round(total / count, 3);
        var other = (await _items.EmployeeSummaryAsync(input.EmployeeId, OwnCompany, ThisMonth, Ct))?.MonthlyDeductions ?? 0m;
        var share = Math.Round((monthly + other) / basic * 100m, 1);
        return share > MaxLoanSharePercent
            ? (null, string.Format(CultureInfo.InvariantCulture,
                                   _text.Tr("Note for the approvers: the instalment with the other monthly deductions is {0}% of the Basic Salary (more than 50%)."),
                                   share.ToString("0.#", CultureInfo.InvariantCulture)))
            : (null, null);
    }

    // =======================================================================
    // Excel
    // =======================================================================

    [HttpGet("export")]
    public async Task<IActionResult> Export(string? search, long? emp, string? cls, string? status)
    {
        var scope = await ScopeAsync(cls);
        if (scope is null || !scope.CanView) return Forbid();
        var L = _text;
        var result = await _items.ListAsync(Filter(search, emp, scope, status, 1, 10000), Ct);

        string[] headers =
        [
            L.Tr("Employee No"), L.Tr("Employee"), L.Tr("Company"), L.Tr("Class"), L.Tr("Item type"), L.Tr("Amount (KWD)"),
            L.Tr("Applies"), L.Tr("From month"), L.Tr("Until month"), L.Tr("Instalments"), L.Tr("Total (loans)"),
            L.Tr("Paid so far"), L.Tr("Balance"), L.Tr("Reference"), L.Tr("Comment"), L.Tr("Status")
        ];
        var rows = result.Items.Select(i => (IReadOnlyList<object?>)new object?[]
        {
            i.EmployeeNo,
            PayItemFormat.EmployeeName(L, i.EmployeeName, i.EmployeeArabicName),
            i.CompanyName,
            PayItemFormat.ClassLabel(L, i.ItemClass),
            PayItemFormat.TypeName(L, i.ComponentName, i.ComponentArabicName),
            i.SignedAmount,
            PayItemFormat.AppliesPlain(L, i.AppliesMode),
            PayItemFormat.MonthValue(i.StartMonth),
            i.EndMonth is { } e ? PayItemFormat.MonthValue(e) : null,
            i.InstalmentCount,
            i.TotalAmount,
            i.PaidAmount,
            i.Balance,
            i.SourceRef,
            i.Comment,
            PayItemFormat.StatusLabel(L, i)
        });
        var bytes = XlsxFile.Write(L.Tr(scope.Page.Title), headers, rows,
            [14, 26, 20, 14, 24, 14, 16, 12, 12, 12, 14, 14, 14, 12, 40, 18], rightToLeft: L.IsArabic);
        return File(bytes, XlsxFile.ContentType, $"{scope.Page.Route}-{DateTime.Today:yyyyMMdd}.xlsx");
    }

    [HttpGet("template")]
    public async Task<IActionResult> Template(string? cls)
    {
        var scope = await ScopeAsync(cls);
        if (scope is null || !scope.CanEdit) return Forbid();
        var L = _text;
        var next = ThisMonth.AddMonths(1);
        string[] headers =
        [
            L.Tr("Employee No"), L.Tr("Item type"), L.Tr("Amount (KWD)"), L.Tr("Applies"), L.Tr("From month"),
            L.Tr("Until month"), L.Tr("Instalments"), L.Tr("Total (loans)"), L.Tr("Comment")
        ];
        var examples = new List<IReadOnlyList<object?>>
        {
            new object?[] { "E1001", "BONUS", 150m, "One time", PayItemFormat.MonthValue(next), null, null, null, L.Tr("Example - delete this row") },
            new object?[] { "E1001", "OVERTIME", 45.5m, "One time", PayItemFormat.MonthValue(next), null, null, null, L.Tr("Example - delete this row") },
            new object?[] { "E1002", "LOAN", null, "Instalments", PayItemFormat.MonthValue(next), null, 12, 1200m, L.Tr("Example - delete this row") }
        };
        var bytes = XlsxFile.Write(L.Tr(scope.Page.Title), headers, examples, [14, 22, 14, 16, 12, 12, 12, 14, 40]);
        return File(bytes, XlsxFile.ContentType, $"{scope.Page.Route}-template.xlsx");
    }

    /// <summary>
    /// Columns in template order: Employee No, Item type (code or name), Amount, Applies,
    /// From month, Until month, Instalments, Total (loans), Comment. The first row is the header.
    /// Every row is checked first; nothing is saved unless all rows are correct.
    /// </summary>
    [HttpPost("import")]
    [RequestSizeLimit(MaxImportBytes + 64 * 1024)]
    public async Task<IActionResult> Import(IFormFile? file, string? cls)
    {
        var scope = await ScopeAsync(cls);
        if (scope is null || !scope.CanEdit) return Denied();
        if (file is null || file.Length == 0) return Json(ImportFailed("Choose an Excel file (.xlsx) to import."));
        if (file.Length > MaxImportBytes) return Json(ImportFailed("The file is larger than 5 MB."));

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant();
        List<string[]> table;
        var decimalComma = false;
        try
        {
            await using var stream = file.OpenReadStream();
            using var buffer = new MemoryStream();
            await stream.CopyToAsync(buffer, Ct);
            buffer.Position = 0;
            table = ext switch
            {
                ".xlsx" => XlsxFile.Read(buffer),
                ".csv" => XlsxFile.ReadCsv(buffer, out decimalComma),
                _ => throw new InvalidDataException()
            };
        }
        catch (Exception ex) when (ex is InvalidDataException or System.Xml.XmlException or IOException)
        {
            return Json(ImportFailed("The file could not be read. Use the template (.xlsx) or a .csv file."));
        }

        // table[i] is sheet row i + 1 (blank rows kept as empty), so the row numbers match the file
        string Number(string v) => decimalComma ? v.Replace(".", string.Empty).Replace(',', '.') : v;
        var rows = new List<PayItemImportRow>();
        for (var i = 1; i < table.Count; i++)
        {
            if (table[i].All(string.IsNullOrWhiteSpace)) continue;
            string Cell(int c) => c < table[i].Length ? table[i][c] : string.Empty;
            rows.Add(new PayItemImportRow
            {
                Row = i + 1,
                EmployeeNo = Cell(0),
                ItemType = Cell(1),
                Amount = Number(Cell(2)),
                Applies = Cell(3),
                FromMonth = XlsxFile.MonthText(Cell(4)),
                UntilMonth = XlsxFile.MonthText(Cell(5)),
                Instalments = Cell(6),
                Total = Number(Cell(7)),
                Comment = Cell(8)
            });
        }
        if (rows.Count == 0) return Json(ImportFailed("The file has no rows to import."));
        if (rows.Count > MaxImportRows) return Json(ImportFailed("A file can hold up to 2000 rows - split it into smaller files."));

        // db/111: a page imports its own item types only (and only those the user may work with)
        var types = await _items.TypesAsync(OwnCompany, CompanyCsv, Ct);
        var refused = rows.Where(r =>
        {
            var t = types.FirstOrDefault(x => string.Equals(x.ComponentCode, r.ItemType?.Trim(), StringComparison.OrdinalIgnoreCase)
                                             || string.Equals(x.ComponentName, r.ItemType?.Trim(), StringComparison.OrdinalIgnoreCase));
            return t is not null && (t.ItemClass != scope.Page.ItemClass || !scope.Allows(t.ComponentCode));
        }).ToList();
        if (refused.Count > 0)
        {
            return Json(new
            {
                success = false, imported = 0,
                message = _text.Tr("Some rows are not item types of this page (or not ones you may add). Nothing was imported."),
                errors = refused.Select(r => new { row = r.Row, message = _text.Tr("Item type not on this page or not allowed for you.") })
            });
        }

        var result = await _items.ImportAsync(rows, OwnCompany, CompanyCsv, UserId, Ct);
        return Json(new
        {
            success = result.Success,
            imported = result.Imported,
            message = _text.Tr(result.Message),
            errors = result.Errors.Select(e => new { row = e.RowNo, message = _text.Tr(e.Message) })
        });
    }

    // =======================================================================
    // Helpers
    // =======================================================================

    private PayItemFilter Filter(string? search, long? emp, ComponentScope? scope, string? status, int page, int size) => new()
    {
        CompanyId = OwnCompany,
        CompanyIds = CompanyCsv,
        EmployeeId = emp,
        ItemClass = scope?.Page.ItemClass,
        ComponentCodes = scope?.AllowedCodes,
        Status = status is "ACTIVE" or "PENDING" or "ENDED" or "ALL" ? status : "OPEN",
        Search = search,
        PageNumber = Math.Max(1, page),
        PageSize = size
    };

    private object ImportFailed(string message) => new { success = false, imported = 0, message = _text.Tr(message), errors = Array.Empty<object>() };

    private static DateTime Max(DateTime a, DateTime b) => a > b ? a : b;

    private IActionResult Result(Domain.Common.SaveResult result)
    {
        // a change may add or clear an approval: refresh the sidebar badges and the bell (db/110)
        if (result.Success) HttpContext.RequestServices.GetService<HRMS.Web.Services.IPayrollNavCounts>()?.Invalidate();
        return Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));
    }

    private IActionResult Denied() =>
        Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
}
