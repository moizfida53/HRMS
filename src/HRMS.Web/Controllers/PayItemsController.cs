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
/// Pay Items (db/37-38): one list of everything an employee is paid or has
/// deducted - salary, earnings, deductions, loans and advances - one line per
/// item with a comment. A payroll picks up every active item that applies to
/// its month. Salary and loan items are paid only after approval (HR, then
/// Finance); an item already paid by a payroll keeps its amount.
/// </summary>
[Route("payroll/pay-items")]
public sealed class PayItemsController : Controller
{
    private const string PermView = "PAYROLL_ITEM_VIEW";
    private const string PermCreate = "PAYROLL_ITEM_CREATE";
    private const string PermEdit = "PAYROLL_ITEM_EDIT";
    private const string PermDelete = "PAYROLL_ITEM_DELETE";
    // Approval rights of this process (Security > Create Roles > Approval rights)
    private const string PermApproveHr = "PAYROLL_ITEM_APPROVE_L1";
    private const string PermApproveFinance = "PAYROLL_ITEM_APPROVE_L2";
    private const string PermApproveSelf = "PAYROLL_ITEM_APPROVE_SELF";

    private const int MaxImportRows = 2000;
    private const long MaxImportBytes = 5 * 1024 * 1024;

    private readonly IPayItemRepository _items;
    private readonly ICurrentUser _currentUser;
    private readonly ICompanyFilter _companyFilter;
    private readonly IUiText _text;

    public PayItemsController(IPayItemRepository items, ICurrentUser currentUser, ICompanyFilter companyFilter, IUiText text)
    {
        _items = items;
        _currentUser = currentUser;
        _companyFilter = companyFilter;
        _text = text;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;
    private long? UserId => _currentUser.UserId;
    private int? OwnCompany => _currentUser.ActiveCompanyId;
    private string? CompanyCsv => _companyFilter.Csv;
    private bool Can(string permission) => _currentUser.HasPermission(permission);
    private bool IsSysAdmin => _currentUser.IsInRole("SYSADMIN") || Can("SYSTEM_ADMIN");
    /// <summary>May approve their own submissions (System Administrator, or the "approve own" right).</summary>
    private bool CanApproveOwn => IsSysAdmin || Can(PermApproveSelf);
    private static DateTime ThisMonth => new(DateTime.Today.Year, DateTime.Today.Month, 1);

    private PayItemRights Rights => new()
    {
        CanCreate = Can(PermCreate),
        CanEdit = Can(PermEdit),
        CanDelete = Can(PermDelete),
        CanApproveHr = Can(PermApproveHr),
        CanApproveFinance = Can(PermApproveFinance),
        UserId = UserId,
        CanApproveOwn = CanApproveOwn
    };

    // =======================================================================
    // Page and panels
    // =======================================================================

    [HttpGet("")]
    public async Task<IActionResult> Index(long? emp, string? status)
    {
        if (!Can(PermView)) return Forbid();
        var employees = await _items.EmployeesAsync(OwnCompany, CompanyCsv, Ct);
        return View(new PayItemsPageModel
        {
            Employees = employees,
            SelectedEmployeeId = emp is { } e && employees.Any(x => x.EmployeeId == e) ? e : null,
            SelectedStatus = status,
            Rights = Rights,
            ManyCompanies = employees.Select(x => x.CompanyId).Distinct().Count() > 1
        });
    }

    [HttpGet("grid")]
    public async Task<IActionResult> Grid(string? search, long? emp, string? cls, string? status, int page = 1)
    {
        if (!Can(PermView)) return Forbid();
        var result = await _items.ListAsync(Filter(search, emp, cls, status, page, 25), Ct);
        return PartialView("_PayItemsGrid", new PayItemsGridModel
        {
            Page = result,
            IsFiltered = !string.IsNullOrWhiteSpace(search) || emp is not null || !string.IsNullOrEmpty(cls) || (status ?? "OPEN") != "OPEN",
            Rights = Rights,
            ManyCompanies = _companyFilter.SelectedIds.Count != 1 && OwnCompany is null
        });
    }

    [HttpGet("kpis")]
    public async Task<IActionResult> Kpis()
    {
        if (!Can(PermView)) return Forbid();
        var summary = await _items.SummaryAsync(OwnCompany, CompanyCsv, ThisMonth, Ct) ?? new PayItemSummary { SummaryMonth = ThisMonth };
        return PartialView("_PayItemKpis", summary);
    }

    [HttpGet("employee/{id:long}")]
    public async Task<IActionResult> Employee(long id)
    {
        if (!Can(PermView)) return Forbid();
        var summary = await _items.EmployeeSummaryAsync(id, OwnCompany, ThisMonth, Ct);
        return summary is null ? Content(string.Empty) : PartialView("_PayItemEmployee", summary);
    }

    /// <summary>Figures for the loan checks of the form (monthly salary, balance, monthly deductions).</summary>
    [HttpGet("employee-figures/{id:long}")]
    public async Task<IActionResult> EmployeeFigures(long id)
    {
        if (!Can(PermView)) return Forbid();
        var s = await _items.EmployeeSummaryAsync(id, OwnCompany, ThisMonth, Ct);
        return Json(s is null ? null : new
        {
            monthlySalary = s.MonthlySalary,
            loanBalance = s.LoanBalance,
            loanPending = s.LoanPending,
            monthlyDeductions = s.MonthlyDeductions
        });
    }

    [HttpGet("form")]
    public async Task<IActionResult> Form(long id = 0, long? emp = null, string? cls = null)
    {
        PayItem? item = null;
        if (id > 0)
        {
            if (!Can(PermEdit)) return Forbid();
            item = await _items.GetAsync(id, OwnCompany, Ct);
            if (item is null || item.IsEnded) return NotFound();
        }
        else if (!Can(PermCreate))
        {
            return Forbid();
        }

        var mode = item switch
        {
            null => "new",
            { ItemClass: ItemClass.Salary, Status: PayItemStatus.Active } => "revise",
            { ItemClass: ItemClass.Loan, Status: PayItemStatus.Active } => "locked",
            { IsUsed: true } => "locked",
            _ => "edit"
        };

        var defaultMonth = mode == "revise" ? Max(ThisMonth.AddMonths(1), item!.StartMonth.AddMonths(1)) : ThisMonth;
        return PartialView("_PayItemForm", new PayItemFormModel
        {
            Item = item,
            EmployeeId = item?.EmployeeId ?? emp,
            ItemClass = item?.ItemClass ?? (ItemClass.All.Contains(cls ?? "") ? cls! : ItemClass.Earning),
            Employees = await _items.EmployeesAsync(OwnCompany, CompanyCsv, Ct),
            Types = await _items.TypesAsync(OwnCompany, CompanyCsv, Ct),
            Months = PayItemFormat.MonthOptions(DateTime.Today, item?.StartMonth, item?.EndMonth, defaultMonth),
            DefaultMonth = defaultMonth,
            Mode = mode
        });
    }

    [HttpGet("history/{id:long}")]
    public async Task<IActionResult> History(long id)
    {
        if (!Can(PermView)) return Forbid();
        var item = await _items.GetAsync(id, OwnCompany, Ct);
        if (item is null) return NotFound();
        return PartialView("_PayItemHistory", new PayItemHistoryModel
        {
            Item = item,
            Entries = await _items.HistoryAsync(id, OwnCompany, Ct)
        });
    }

    // =======================================================================
    // Changes
    // =======================================================================

    [HttpPost("save")]
    public async Task<IActionResult> Save(PayItemInput input)
    {
        if (!Can(input.EmployeePayItemId > 0 ? PermEdit : PermCreate)) return Denied();
        if (!ModelState.IsValid)
        {
            return Json(ActionResponse.Failed("Check the amounts and months - one of them is not a valid value.", "VALIDATION"));
        }
        return Result(await _items.SaveAsync(input, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("approve")]
    public async Task<IActionResult> Approve(long id, string? comment)
    {
        var item = await _items.GetAsync(id, OwnCompany, Ct);
        if (item is null) return Json(ActionResponse.Failed("This pay item no longer exists.", "NOT_FOUND"));
        if (!Rights.CanApprove(item)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _items.ActionAsync("APPROVE", id, OwnCompany, CompanyCsv, UserId, comment, allowSelfApproval: CanApproveOwn,
                                               expectedLevel: item.ApprovalLevel, cancellationToken: Ct));
    }

    [HttpPost("reject")]
    public async Task<IActionResult> Reject(long id, string? comment)
    {
        var item = await _items.GetAsync(id, OwnCompany, Ct);
        if (item is null) return Json(ActionResponse.Failed("This pay item no longer exists.", "NOT_FOUND"));
        if (!Rights.CanApprove(item)) return Json(ActionResponse.Failed("You are not an approver for this level.", "FORBIDDEN"));
        return Result(await _items.ActionAsync("REJECT", id, OwnCompany, CompanyCsv, UserId, comment, expectedLevel: item.ApprovalLevel, cancellationToken: Ct));
    }

    [HttpPost("end")]
    public async Task<IActionResult> End(long id, string? endMonth, string? comment)
    {
        if (!Can(PermEdit)) return Denied();
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
        if (!Can(PermDelete)) return Denied();
        return Result(await _items.ActionAsync("DELETE", id, OwnCompany, CompanyCsv, UserId, comment, cancellationToken: Ct));
    }

    // =======================================================================
    // Excel
    // =======================================================================

    [HttpGet("export")]
    public async Task<IActionResult> Export(string? search, long? emp, string? cls, string? status)
    {
        if (!Can(PermView)) return Forbid();
        var L = _text;
        var result = await _items.ListAsync(Filter(search, emp, cls, status, 1, 10000), Ct);

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
        var bytes = XlsxFile.Write(L.Tr("Pay Items"), headers, rows,
            [14, 26, 20, 14, 24, 14, 16, 12, 12, 12, 14, 14, 14, 12, 40, 18], rightToLeft: L.IsArabic);
        return File(bytes, XlsxFile.ContentType, $"pay-items-{DateTime.Today:yyyyMMdd}.xlsx");
    }

    [HttpGet("template")]
    public IActionResult Template()
    {
        if (!Can(PermCreate)) return Forbid();
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
        var bytes = XlsxFile.Write(L.Tr("Pay Items"), headers, examples, [14, 22, 14, 16, 12, 12, 12, 14, 40]);
        return File(bytes, XlsxFile.ContentType, "pay-items-template.xlsx");
    }

    /// <summary>
    /// Columns in template order: Employee No, Item type (code or name), Amount, Applies,
    /// From month, Until month, Instalments, Total (loans), Comment. The first row is the header.
    /// Every row is checked first; nothing is saved unless all rows are correct.
    /// </summary>
    [HttpPost("import")]
    [RequestSizeLimit(MaxImportBytes + 64 * 1024)]
    public async Task<IActionResult> Import(IFormFile? file)
    {
        if (!Can(PermCreate)) return Denied();
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

    private PayItemFilter Filter(string? search, long? emp, string? cls, string? status, int page, int size) => new()
    {
        CompanyId = OwnCompany,
        CompanyIds = CompanyCsv,
        EmployeeId = emp,
        ItemClass = ItemClass.All.Contains(cls ?? "") ? cls : null,
        Status = status is "ACTIVE" or "PENDING" or "ENDED" or "ALL" ? status : "OPEN",
        Search = search,
        PageNumber = Math.Max(1, page),
        PageSize = size
    };

    private object ImportFailed(string message) => new { success = false, imported = 0, message = _text.Tr(message), errors = Array.Empty<object>() };

    private static DateTime Max(DateTime a, DateTime b) => a > b ? a : b;

    private IActionResult Result(Domain.Common.SaveResult result) =>
        Json(result.Success ? ActionResponse.Ok(result.Id, result.Message) : ActionResponse.Failed(result.Message, result.ErrorCode));

    private IActionResult Denied() =>
        Json(ActionResponse.Failed("You do not have permission to do this.", "FORBIDDEN"));
}
