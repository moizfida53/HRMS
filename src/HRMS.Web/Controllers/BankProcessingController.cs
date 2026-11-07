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
[PayoutSync]
public sealed class BankProcessingController : PayrollFinanceControllerBase
{
    private const string PermView = "PAYROLL_BANK_VIEW";
    private const string PermProcess = "PAYROLL_BANK_PROCESS";

    private readonly IPayrollFinanceRepository _finance;
    private readonly IPayrollRulesRepository _rules;
    private readonly IBankRepository _banks;
    private readonly IUiText _l;
    private readonly IEmployeeNames _names;

    public BankProcessingController(IPayrollFinanceRepository finance, IPayrollRulesRepository rules, IBankRepository banks, IUiText l,
                                    IEmployeeNames names, ICurrentUser currentUser, ICompanyFilter companyFilter)
        : base(currentUser, companyFilter)
    {
        _names = names;
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

    // =======================================================================
    // db/123: the Bank transfer tab of a payroll's workspace - the bank file of that
    // payroll and its Payment Register (open once the payroll is approved)
    // =======================================================================

    [HttpGet("~/payroll/run/{id:long}/bank")]
    public async Task<IActionResult> RunTab(long id)
    {
        if (!Rights.CanView) return Forbid();
        if (await WorkspaceAsync(id, WorkspaceTab.Bank) is not { } nav) return RedirectToAction("Payrolls", "Payroll");
        if (!nav.Run.IsClosed) return LocalRedirect(Url.Content(WorkspaceNav.Path(WorkspaceTab.Overview, id)));
        return await FilePage(nav.Run.RunMonth.Year, FinancePeriod.Key(nav.Run.RunMonth), id);
    }

    [HttpGet("~/payroll/run/{id:long}/payments")]
    public async Task<IActionResult> RunPayments(long id, string? status, string? method, string? q, int page = 1)
    {
        if (!Rights.CanView) return Forbid();
        if (await WorkspaceAsync(id, WorkspaceTab.Payments) is not { } nav) return RedirectToAction("Payrolls", "Payroll");
        if (!nav.Run.IsClosed) return LocalRedirect(Url.Content(WorkspaceNav.Path(WorkspaceTab.Overview, id)));
        return await Register(null, null, status, method, q, id, null, page);
    }

    private async Task<WorkspaceNav?> WorkspaceAsync(long id, string tab)
    {
        var nav = await HttpContext.RequestServices.GetRequiredService<IPayrollWorkspace>().NavAsync(id, tab, Ct);
        ViewData["Workspace"] = nav;
        return nav;
    }

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
        BankStages? stages = null;
        IReadOnlyList<BankFileAuditEntry> audit = [];
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

            // db/116: the two-step process (Ministry Payroll, then Company Payroll) and the audit
            try
            {
                stages = await _finance.BankStagesAsync(selected.PayrollRunId, OwnCompany, CompanyCsv, Ct);
                audit = await _finance.BankAuditAsync(selected.PayrollRunId, OwnCompany, CompanyCsv, Ct);
            }
            catch (Exception ex) when (ex is not OperationCanceledException)
            {
                HttpContext.RequestServices.GetService<ILogger<BankProcessingController>>()?
                    .LogWarning(ex, "The two-step bank process could not be read (run db/116).");
            }
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
            Files = files,
            Stages = stages,
            Audit = audit,
            CanPostGl = Can("PAYROLL_GL_POST")
        });
    }

    /// <summary>Builds the file from the bank format and stores it; the page then downloads it.</summary>
    [HttpPost("file/generate")]
    public async Task<IActionResult> Generate(long run, string? kind, int? bank, int format, int account, DateTime? valueDate, string? reason)
    {
        if (!Can(PermProcess)) return Denied();
        // db/116: FULL (one file of the net pay), RETRY, or the two steps MINISTRY then COMPANY
        kind = kind is "RETRY" or BankStage.Ministry or BankStage.Company ? kind : BankStage.Full;
        if (format <= 0) return Invalid("Select an active bank format.");
        if (account <= 0) return Invalid("Select an active salary account of the payroll's company.");
        if (valueDate is null) return Invalid("Enter the value date.");

        var runs = await _finance.BankRunsAsync(OwnCompany, CompanyCsv, null, null, Ct);
        if (runs.FirstOrDefault(r => r.PayrollRunId == run) is not { } payroll) return Invalid("Select a closed payroll - salaries are paid only for a closed payroll.");

        var lines = await _finance.BankLinesAsync(run, kind, bank, OwnCompany, CompanyCsv, Ct);
        if (lines.Count == 0)
        {
            // a step with nobody to pay still says why (step 1 not done, a work permit salary missing ...)
            if (kind is BankStage.Ministry or BankStage.Company)
            {
                var check = await _finance.CreateBankFileAsync(new BankFileRequest
                {
                    RunId = run, Kind = kind, BankId = bank, BankFileFormatId = format, CompanyBankAccountId = account,
                    ValueDate = valueDate.Value.Date, FileName = "-", Content = string.Empty, RunEmployeeIds = [], Reason = reason
                }, OwnCompany, CompanyCsv, UserId, Ct);
                if (!check.Success && check.ErrorCode != "VALIDATION") return Result(check);
                if (kind == BankStage.Company) return Invalid("Nobody is left to pay in the Company Payroll - the Ministry Payroll transferred the full net pay.");
            }
            return Invalid("There is nobody to pay in this file.");
        }

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

    /// <summary>
    /// db/118: Post to GL - the payroll's journal is created when it has none and marked posted with
    /// the reference of the entry in the books; from then on its bank files cannot be generated again.
    /// </summary>
    [HttpPost("file/post-gl")]
    public async Task<IActionResult> PostGl(long run, string? reference)
    {
        if (!Can("PAYROLL_GL_POST")) return Denied();
        if (string.IsNullOrWhiteSpace(reference)) return Invalid("Enter the reference of the entry in the books.");
        var stages = await _finance.BankStagesAsync(run, OwnCompany, CompanyCsv, Ct);
        if (stages is null) return Invalid("Select a closed payroll - salaries are paid only for a closed payroll.");
        if (stages.IsGlPosted) return Invalid("This payroll is already posted to the GL.");
        if (!stages.FilesReady) return Invalid("Generate the bank file first (both steps in the two-step process).");

        var journalId = stages.JournalId ?? 0;
        if (journalId <= 0)
        {
            var made = await _finance.CreateJournalAsync(run, null, OwnCompany, CompanyCsv, UserId, Ct);
            if (!made.Success) return Result(made);
            journalId = made.Id;
        }
        var posted = await _finance.JournalActionAsync(journalId, "POSTED", reference, OwnCompany, CompanyCsv, UserId, Ct);
        if (!posted.Success) return Result(posted);
        var audit = await _finance.BankGlPostedAsync(run, OwnCompany, CompanyCsv, UserId, Ct);
        HttpContext.RequestServices.GetService<IPayrollNavCounts>()?.Invalidate();
        return Result(audit.Success ? audit : posted);
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
        await _names.LocalizeAsync(result.Items, p => p.EmployeeId, (p, name) => p.EmployeeName = name, Ct);
        var ws = ViewData["Workspace"] as WorkspaceNav;

        return View("~/Views/BankProcessing/Register.cshtml", new PaymentRegisterModel
        {
            Filters = new FinanceFilterBar
            {
                Action = ws is null ? Url.Action(nameof(Register))! : Url.Content(WorkspaceNav.Path(WorkspaceTab.Payments, ws.Run.PayrollRunId)),
                NoPeriod = ws is not null,
                Years = YearsOf(months), Months = months, Year = y, Month = m, AllYears = true,
                Selects =
                [
                    new FinanceSelect("status", _l["common.status"],
                        [("", _l["common.all_statuses"]), ("FAILED", _l["fin.pay_failed"]), ("PENDING", _l["fin.pay_pending"]),
                         ("IN_FILE", _l["fin.pay_in_file"]), ("PAID", _l["fin.pay_paid"])], status),
                    new FinanceSelect("method", _l["fin.method"],
                        [("", _l["fin.all_methods"]), ("BANK", _l["fin.method_bank"]), ("CASH", _l["fin.method_cash"])], method)
                ],
                Hidden = ws is not null ? new Dictionary<string, string?>() : new Dictionary<string, string?>
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
            IsFiltered = status is not null || method is not null || !string.IsNullOrWhiteSpace(q) || (ws is null && run is not null) || file is not null
        });
    }

    [HttpPost("payments/status")]
    public async Task<IActionResult> PaymentStatus([FromForm] string[]? ids, string? status, string? reference, string? reason, DateTime? paidDate)
    {
        if (!Can(PermProcess)) return Denied();
        var list = Ids(ids);
        if (list.Count == 0) return Invalid("Select the payments.");
        if (await IsCompletedAsync(null, list)) return Invalid("These payments belong to a completed payroll - it is read-only.");
        return Result(await _finance.SetPaymentStatusAsync(list, status == "FAILED" ? "FAILED" : "PAID", reference, reason, paidDate,
                                                           OwnCompany, CompanyCsv, UserId, Ct));
    }

    [HttpPost("payments/reissue")]
    public async Task<IActionResult> Reissue([FromForm] string[]? ids, string? method)
    {
        if (!Can(PermProcess)) return Denied();
        var list = Ids(ids);
        if (list.Count == 0) return Invalid("Select the payments.");
        if (await IsCompletedAsync(null, list)) return Invalid("These payments belong to a completed payroll - it is read-only.");
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
