using System.Globalization;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Models.Payroll;

/// <summary>One tab of a payroll's workspace.</summary>
public sealed record WorkspaceTabItem(string Slug, string LabelKey, string Icon, string Group, string Href, bool Locked, string? LockKey,
                                      bool Done, string? Badge, string? BadgeTone);

/// <summary>
/// db/123: the header of every page of a payroll - Register, Validation, Approval and the
/// pay-out tabs (Payslips, Bank transfer, Collections, Accounting) - with the tabs open at
/// the payroll's stage. Preparation tabs open as the payroll reaches them; the pay-out
/// tabs once it is approved.
/// </summary>
public sealed class WorkspaceNav
{
    public const string GroupPrepare = "prepare";
    public const string GroupPayout = "payout";
    public const string GroupRecord = "record";

    public required PayrollRun Run { get; init; }
    public required IReadOnlyList<PayrollRun> Runs { get; init; }
    /// <summary>The tab shown (WorkspaceTab).</summary>
    public required string Tab { get; init; }
    public RunPayout? Payout { get; init; }
    public bool CanCancel { get; init; }
    public bool CanSlips { get; init; }
    public bool CanBank { get; init; }
    public bool CanCollections { get; init; }
    public bool CanGl { get; init; }

    public bool IsApproved => Run.IsClosed;
    /// <summary>Collections are recorded for regular payrolls only.</summary>
    public bool HasCollections => Run.RunType == RunType.Regular;

    /// <summary>The address of a tab of a payroll (relative to the application root, "~/...").</summary>
    public static string Path(string tab, long runId)
    {
        var id = runId.ToString(CultureInfo.InvariantCulture);
        return tab switch
        {
            WorkspaceTab.Register => "~/payroll/register?run=" + id,
            WorkspaceTab.Validation => "~/payroll/validation?run=" + id,
            WorkspaceTab.Approval => "~/payroll/approval?run=" + id,
            _ => "~/payroll/run/" + id + "/" + tab
        };
    }

    /// <summary>Whether a tab is open for a payroll at its stage (and the reason when it is not).</summary>
    public static (bool Open, string? LockKey) Availability(string tab, PayrollRun run)
    {
        var stage = run.IsCancelled ? 0 : run.StageIndex;
        return tab switch
        {
            WorkspaceTab.Validation => stage >= 1 ? (true, null) : (false, "ws.lock_validation"),
            WorkspaceTab.Approval => stage >= 2 ? (true, null) : (false, "ws.lock_approval"),
            WorkspaceTab.Payslips or WorkspaceTab.Bank or WorkspaceTab.Payments or WorkspaceTab.Collections or WorkspaceTab.Accounting =>
                run.IsClosed ? (true, null) : (false, run.IsCancelled ? "ws.lock_cancelled" : "ws.lock_payout"),
            _ => (true, null)
        };
    }

    /// <summary>The same tab of another payroll, else its overview.</summary>
    public string SwitchPath(PayrollRun other)
    {
        var tab = Tab == WorkspaceTab.Collections && other.RunType != RunType.Regular ? WorkspaceTab.Overview : Tab;
        return Availability(tab, other).Open ? Path(tab, other.PayrollRunId) : Path(WorkspaceTab.Overview, other.PayrollRunId);
    }

    /// <summary>The tab that is highlighted (Payment Register belongs to Bank transfer).</summary>
    public string ActiveTab => Tab == WorkspaceTab.Payments ? WorkspaceTab.Bank : Tab;

    public IReadOnlyList<WorkspaceTabItem> Tabs
    {
        get
        {
            var run = Run;
            var id = run.PayrollRunId;
            var p = Payout;
            var stage = run.IsCancelled ? -1 : run.StageIndex;
            var list = new List<WorkspaceTabItem>();

            void Add(string slug, string label, string icon, string group, bool done, string? badge = null, string? tone = null)
            {
                var (open, lockKey) = Availability(slug, run);
                list.Add(new WorkspaceTabItem(slug, label, icon, group, Path(slug, id), !open, lockKey, open && done, open ? badge : null, tone));
            }

            Add(WorkspaceTab.Overview, "ws.tab_overview", "grid", GroupPrepare, false);
            Add(WorkspaceTab.Register, "ws.tab_register", "users", GroupPrepare, stage >= 1);
            Add(WorkspaceTab.Validation, "ws.tab_validation", "step-check", GroupPrepare, stage >= 2,
                stage == 1 && run.ErrorCount > 0 ? run.ErrorCount.ToString(CultureInfo.InvariantCulture) : null, "danger");
            Add(WorkspaceTab.Approval, "ws.tab_approval", "shield", GroupPrepare, run.IsClosed);
            if (CanSlips)
            {
                Add(WorkspaceTab.Payslips, "ws.tab_payslips", "receipt", GroupPayout, p?.PayslipsDone == true,
                    p is null || p.PayslipsDone ? null : string.Create(CultureInfo.InvariantCulture, $"{p.PayslipCount}/{p.EmployeeCount}"), "warning");
            }
            if (CanBank)
            {
                Add(WorkspaceTab.Bank, "ws.tab_bank", "bank", GroupPayout, p?.PaymentsDone == true,
                    p is { FailedCount: > 0 } ? p.FailedCount.ToString(CultureInfo.InvariantCulture) : null, "danger");
            }
            if (CanCollections && HasCollections)
            {
                Add(WorkspaceTab.Collections, "ws.tab_collections", "wallet", GroupPayout, p is { CollectionPendingCount: 0 },
                    p is { CollectionPendingCount: > 0 } ? p.CollectionPendingCount.ToString(CultureInfo.InvariantCulture) : null, "warning");
            }
            if (CanGl)
            {
                Add(WorkspaceTab.Accounting, "ws.tab_accounting", "book", GroupPayout, p?.GlPosted == true);
            }
            Add(WorkspaceTab.History, "ws.tab_history", "clock", GroupRecord, false);
            return list;
        }
    }
}

/// <summary>The Overview tab of a payroll.</summary>
public sealed class WorkspaceOverviewModel
{
    public required WorkspaceNav Nav { get; init; }
    public PayrollRunSummary Summary { get; init; } = new();
    public PayrollFunding? Funding { get; init; }
    public IReadOnlyList<PayrollRunHistoryEntry> History { get; init; } = Array.Empty<PayrollRunHistoryEntry>();
}

/// <summary>The History tab of a payroll.</summary>
public sealed class WorkspaceHistoryModel
{
    public required WorkspaceNav Nav { get; init; }
    public IReadOnlyList<PayrollRunHistoryEntry> History { get; init; } = Array.Empty<PayrollRunHistoryEntry>();
    public IReadOnlyList<BankFileAuditEntry> BankAudit { get; init; } = Array.Empty<BankFileAuditEntry>();
}

/// <summary>The Accounting tab of a payroll: its journal (or the preview of the one it would get).</summary>
public sealed class WorkspaceAccountingModel
{
    public required WorkspaceNav Nav { get; init; }
    public JournalDetailsModel? Journal { get; init; }
    public bool CanPost { get; init; }
}
