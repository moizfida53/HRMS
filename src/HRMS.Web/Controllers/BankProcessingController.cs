using System.Text;
using HRMS.Data.Repositories;
using HRMS.Domain.Payroll;
using HRMS.Web.Localization;
using HRMS.Web.Models.Payroll;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Mvc;

namespace HRMS.Web.Controllers;

/// <summary>
/// Payroll > Bank Processing (db/49-50), three sub-sections with Year / Month
/// filters: Bank File (generate the salary / WPS file of a closed payroll from
/// its bank format, regenerate with a reason, re-issue failed payments),
/// Payment Register (every payment: paid / failed / re-issue, cash and
/// cheque) and Payment History (the files: download, sent to the bank, paid).
/// </summary>
[Route("payroll/bank")]
public sealed class BankProcessingController : PayrollFinanceControllerBase
{
    private const string PermView = "PAYROLL_BANK_VIEW";
    private const string PermProcess = "PAYROLL_BANK_PROCESS";

    private readonly IPayrollFinanceRepository _finance;
    private readonly IPayrollRulesRepository _rules;
    private readonly IBankRepository _banks;
    private readonly IUiText _l;

    public BankProcessingController(IPayrollFinanceRepository finance, IPayrollRulesRepository rules, IBankRepository banks, IUiText l,
                                    ICurrentUser currentUser, ICompanyFilter companyFilter)
        : base(currentUser, companyFilter)
    {
        _finance = finance;
        _rules = rules;
        _banks = banks;
        _l = l;
    }

    private FinanceRights Rights => new() { CanView = Can(PermView) || Can(PermProcess), CanAct = Can(PermProcess) };

    [HttpGet("")]
    public IActionResult Index() => RedirectToAction(nameof(FilePage));

    // =======================================================================
    // Bank File
    // =======================================================================

    [HttpGet("file")]
    public async Task<IActionResult> FilePage(int? year, string? month, long? run)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var all = await _finance.BankRunsAsync(OwnCompany, CompanyCsv, null, null, Ct);
        var months = MonthsOf(all);
        var (y, m) = PickPeriod(months, year, month, defaultToLatest: true);
        var runs = all.Where(r => (y is null || r.RunMonth.Year == y) && (m is null || r.RunMonth == m)).ToList();
        var selected = runs.FirstOrDefault(r => r.PayrollRunId == run)
                       ?? runs.FirstOrDefault(r => r.FileCount == 0 && r.TotalNet > 0) ?? runs.FirstOrDefault();

        IReadOnlyList<BankReviewRow> review = [], retry = [];
        IReadOnlyList<CompanyBankAccount> accounts = [];
        IReadOnlyList<BankFile> files = [];
        IReadOnlyList<BankFileFormat> formats = [];
        if (selected is not null)
        {
            review = await _finance.BankReviewAsync(selected.PayrollRunId, "FULL", null, OwnCompany, CompanyCsv, Ct);
            if (selected.RetryCount > 0)
            {
                retry = await _finance.BankReviewAsync(selected.PayrollRunId, "RETRY", null, OwnCompany, CompanyCsv, Ct);
            }
            accounts = (await _banks.AccountsAsync(selected.CompanyId, null, null, true, 1, Ct)).Items;
            formats = (await _rules.BankFileFormatsAsync(new RuleListFilter { IsActive = true, Page = 1 }, Ct)).Items;
            files = (await _finance.BankFilesAsync(new FinanceFilter
            {
                CompanyId = OwnCompany, CompanyIds = CompanyCsv, RunId = selected.PayrollRunId, PageSize = 50
            }, Ct)).Items;
        }

        return View("~/Views/BankProcessing/File.cshtml", new BankFilePageModel
        {
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(FilePage))!,
                Years = YearsOf(months),
                Months = months,
                Year = y,
                Month = m,
                Selects =
                [
                    new FinanceSelect("run", _l["fin.payroll"],
                        runs.Select(r => (r.PayrollRunId.ToString(System.Globalization.CultureInfo.InvariantCulture),
                                          r.RunCode + " · " + _l.MonthYear(r.RunMonth) + (ManyCompanies ? " · " + r.CompanyName : ""))).ToList(),
                        selected?.PayrollRunId.ToString(System.Globalization.CultureInfo.InvariantCulture))
                ],
                CountText = runs.Count == 1 ? _l["fin.1_payroll"] : _l["fin.0_payrolls", PayrollFormat.Count(runs.Count)]
            },
            Rights = rights,
            Runs = runs,
            Run = selected,
            Review = review,
            RetryReview = retry,
            Accounts = accounts,
            Formats = formats,
            Files = files
        });
    }

    /// <summary>Builds the file from the bank format and stores it; the page then downloads it.</summary>
    [HttpPost("file/generate")]
    public async Task<IActionResult> Generate(long run, string? kind, int? bank, int format, int account, DateTime? valueDate, string? reason)
    {
        if (!Can(PermProcess)) return Denied();
        kind = kind == "RETRY" ? "RETRY" : "FULL";
        if (format <= 0) return Invalid("Select an active bank format.");
        if (account <= 0) return Invalid("Select an active salary account of the payroll's company.");
        if (valueDate is null) return Invalid("Enter the value date.");

        var runs = await _finance.BankRunsAsync(OwnCompany, CompanyCsv, null, null, Ct);
        if (runs.FirstOrDefault(r => r.PayrollRunId == run) is not { } payroll) return Invalid("Select a closed payroll - salaries are paid only for a closed payroll.");

        var lines = await _finance.BankLinesAsync(run, kind, bank, OwnCompany, CompanyCsv, Ct);
        if (lines.Count == 0) return Invalid("There is nobody to pay in this file.");

        var bankFormat = await _rules.BankFileFormatAsync(format, Ct);
        if (bankFormat is null || !bankFormat.IsActive || bankFormat.Fields.Count == 0) return Invalid("Select an active bank format.");
        var debit = await _banks.AccountAsync(account, Ct);
        if (debit is null || debit.CompanyId != payroll.CompanyId || !debit.IsActive) return Invalid("Select an active salary account of the payroll's company.");

        var built = BankFileBuilder.Build(bankFormat, debit, lines, valueDate.Value.Date, payroll.RunMonth);
        return Result(await _finance.CreateBankFileAsync(new BankFileRequest
        {
            RunId = run,
            Kind = kind,
            BankId = bank,
            BankFileFormatId = format,
            CompanyBankAccountId = account,
            ValueDate = valueDate.Value.Date,
            FileName = built.FileName,
            Content = built.Content,
            RunEmployeeIds = lines.Select(l => l.RunEmployeeId).ToList(),
            Reason = reason
        }, OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpGet("file/{id:long}/download")]
    public async Task<IActionResult> Download(long id)
    {
        if (!Rights.CanView) return Forbid();
        var file = await _finance.BankFileAsync(id, OwnCompany, CompanyCsv, download: true, Ct);
        if (file?.Content is null) return NotFound();
        var bytes = new UTF8Encoding(encoderShouldEmitUTF8Identifier: false).GetBytes(file.Content);
        return File(bytes, file.FileName.EndsWith(".csv", StringComparison.OrdinalIgnoreCase) ? "text/csv" : "text/plain", file.FileName);
    }

    [HttpPost("file/{id:long}/sent")]
    public async Task<IActionResult> MarkSent(long id, string? reference) =>
        Can(PermProcess) ? Result(await _finance.MarkFileSentAsync(id, reference, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    [HttpPost("file/{id:long}/paid")]
    public async Task<IActionResult> MarkFilePaid(long id, DateTime? paidDate) =>
        Can(PermProcess) ? Result(await _finance.MarkFilePaidAsync(id, paidDate, OwnCompany, CompanyCsv, UserId, Ct)) : Denied();

    // =======================================================================
    // Payment Register
    // =======================================================================

    [HttpGet("register")]
    public async Task<IActionResult> Register(int? year, string? month, string? status, string? method, string? q, long? run, long? file, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var months = MonthsOf(await _finance.BankRunsAsync(OwnCompany, CompanyCsv, null, null, Ct));
        var (y, m) = PickPeriod(months, year, month, defaultToLatest: false);
        status = status is "PENDING" or "IN_FILE" or "PAID" or "FAILED" ? status : null;
        method = method is "BANK" or "CASH" ? method : null;
        var filter = new FinanceFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, Year = y, RunMonth = m, Status = status, Method = method,
            RunId = run, FileId = file, Search = q, Page = Math.Max(1, page), PageSize = 25
        };
        var result = await _finance.PaymentsAsync(filter, Ct);

        return View("~/Views/BankProcessing/Register.cshtml", new PaymentRegisterModel
        {
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(Register))!,
                Years = YearsOf(months), Months = months, Year = y, Month = m, AllYears = true,
                Selects =
                [
                    new FinanceSelect("status", _l["common.status"],
                        [("", _l["common.all_statuses"]), ("FAILED", _l["fin.pay_failed"]), ("PENDING", _l["fin.pay_pending"]),
                         ("IN_FILE", _l["fin.pay_in_file"]), ("PAID", _l["fin.pay_paid"])], status),
                    new FinanceSelect("method", _l["fin.method"],
                        [("", _l["fin.all_methods"]), ("BANK", _l["fin.method_bank"]), ("CASH", _l["fin.method_cash"])], method)
                ],
                Hidden = new Dictionary<string, string?>
                {
                    ["run"] = run?.ToString(System.Globalization.CultureInfo.InvariantCulture),
                    ["file"] = file?.ToString(System.Globalization.CultureInfo.InvariantCulture)
                },
                Search = q,
                SearchPlaceholder = _l["fin.search_payments"],
                CountText = result.TotalCount == 1 ? _l["fin.1_payment"] : _l["fin.0_payments", PayrollFormat.Count(result.TotalCount)]
            },
            Rights = rights,
            Page = result,
            Summary = await _finance.PaymentSummaryAsync(filter, Ct),
            ManyCompanies = ManyCompanies,
            IsFiltered = status is not null || method is not null || !string.IsNullOrWhiteSpace(q) || run is not null || file is not null
        });
    }

    [HttpPost("payments/status")]
    public async Task<IActionResult> PaymentStatus([FromForm] string[]? ids, string? status, string? reference, string? reason, DateTime? paidDate)
    {
        if (!Can(PermProcess)) return Denied();
        var list = Ids(ids);
        if (list.Count == 0) return Invalid("Select the payments.");
        return Result(await _finance.SetPaymentStatusAsync(list, status == "FAILED" ? "FAILED" : "PAID", reference, reason, paidDate,
                                                           OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("payments/reissue")]
    public async Task<IActionResult> Reissue([FromForm] string[]? ids, string? method)
    {
        if (!Can(PermProcess)) return Denied();
        var list = Ids(ids);
        if (list.Count == 0) return Invalid("Select the payments.");
        return Result(await _finance.ReissuePaymentsAsync(list, method == "CASH" ? "CASH" : "BANK", OwnCompany, CompanyCsv, UserId, Ct));
    }

    // =======================================================================
    // Payment History (the files)
    // =======================================================================

    [HttpGet("history")]
    public async Task<IActionResult> History(int? year, string? month, string? status, string? q, int page = 1)
    {
        var rights = Rights;
        if (!rights.CanView) return Forbid();

        var months = MonthsOf(await _finance.BankRunsAsync(OwnCompany, CompanyCsv, null, null, Ct));
        var (y, m) = PickPeriod(months, year, month, defaultToLatest: false);
        status = status is "GENERATED" or "SENT" or "SUPERSEDED" ? status : null;
        var result = await _finance.BankFilesAsync(new FinanceFilter
        {
            CompanyId = OwnCompany, CompanyIds = CompanyCsv, Year = y, RunMonth = m, Status = status, Search = q, Page = Math.Max(1, page), PageSize = 25
        }, Ct);

        return View("~/Views/BankProcessing/History.cshtml", new PaymentHistoryModel
        {
            Filters = new FinanceFilterBar
            {
                Action = Url.Action(nameof(History))!,
                Years = YearsOf(months), Months = months, Year = y, Month = m, AllYears = true,
                Selects =
                [
                    new FinanceSelect("status", _l["common.status"],
                        [("", _l["common.all_statuses"]), ("GENERATED", _l["fin.file_generated"]), ("SENT", _l["fin.file_sent"]),
                         ("SUPERSEDED", _l["fin.file_superseded"])], status)
                ],
                Search = q,
                SearchPlaceholder = _l["fin.search_files"],
                CountText = result.TotalCount == 1 ? _l["fin.1_file"] : _l["prv.0_files", PayrollFormat.Count(result.TotalCount)]
            },
            Rights = rights,
            Page = result,
            ManyCompanies = ManyCompanies,
            IsFiltered = status is not null || !string.IsNullOrWhiteSpace(q)
        });
    }
}
