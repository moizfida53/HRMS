namespace HRMS.Domain.Payroll;

/// <summary>
/// db/123: what happens after approval. The stage stays CLOSED and the pay-out has three
/// statuses (Payroll.PayrollRuns.PayoutStatus): Approved, Execution (paying out), Completed.
/// </summary>
public static class PayoutStatus
{
    public const string Approved = "APPROVED";
    public const string Execution = "EXECUTION";
    public const string Completed = "COMPLETED";

    public static string Label(string? status) => status switch
    {
        Execution => "Execution",
        Completed => "Completed",
        _ => "Approved"
    };

    public static string Badge(string? status) => status switch
    {
        Execution => "warning",
        Completed => "success",
        _ => "info"
    };

    /// <summary>The stage as shown: Registered … Awaiting Approval, then Approved / Execution / Completed.</summary>
    public static string StageLabel(string? stage, string? payout) =>
        stage == RunStage.Closed ? Label(payout) : RunStage.Label(stage);

    public static string StageBadge(string? stage, string? payout) =>
        stage == RunStage.Closed ? Badge(payout) : RunStage.Badge(stage);

    /// <summary>0 Registered · 1 Validation · 2 Awaiting Approval · 3 Approved · 4 Execution · 5 Completed (-1 cancelled).</summary>
    public static int Index(string? stage, string? payout) => stage switch
    {
        RunStage.Closed => payout switch { Completed => 5, Execution => 4, _ => 3 },
        _ => RunStage.Index(stage)
    };

    public static bool Matches(string? filter) => filter is Approved or Execution or Completed;
}

/// <summary>LIST of Payroll.usp_PayrollRun_Payout: where the pay-out of one payroll stands.</summary>
public sealed class RunPayout
{
    public long PayrollRunId { get; init; }
    /// <summary>NULL until the payroll is approved.</summary>
    public string? PayoutStatus { get; init; }
    public DateTime? ExecutionDate { get; init; }
    public DateTime? CompletedDate { get; init; }
    public string? CompletedByName { get; init; }

    public int EmployeeCount { get; init; }
    public int PayeeCount { get; init; }
    public decimal NetPayable { get; init; }
    public int UnpaidPayeeCount { get; init; }

    public int PayslipCount { get; init; }
    public int EmailedCount { get; init; }
    public int EmailQueuedCount { get; init; }
    public int EmailFailedCount { get; init; }

    public int PaymentCount { get; init; }
    public int PaidCount { get; init; }
    public int FailedCount { get; init; }
    public int OpenPaymentCount { get; init; }
    public decimal PaidAmount { get; init; }

    public int BankFileCount { get; init; }
    public int SentFileCount { get; init; }

    public int CollectionCount { get; init; }
    public int CollectionPendingCount { get; init; }
    public decimal CollectionPendingAmount { get; init; }
    public decimal CollectedAmount { get; init; }

    public long? JournalId { get; init; }
    public string? JournalNo { get; init; }
    public string? JournalStatus { get; init; }
    public DateTime? GlPostedDate { get; init; }
    public string? GlReference { get; init; }

    public bool IsCompleted => PayoutStatus == Payroll.PayoutStatus.Completed;
    public int PayslipsMissing => Math.Max(0, EmployeeCount - PayslipCount);
    public bool PayslipsDone => EmployeeCount > 0 && PayslipsMissing == 0;
    public bool EmailDone => PayslipCount > 0 && EmailedCount >= PayslipCount;
    public bool PaymentsDone => UnpaidPayeeCount == 0 && OpenPaymentCount == 0 && (PaymentCount > 0 || PayeeCount == 0);
    public bool GlPosted => JournalStatus == "POSTED";
    public bool CollectionsDone => CollectionPendingCount == 0;

    /// <summary>The three things that complete a payroll.</summary>
    public int StepsDone => (PayslipsDone ? 1 : 0) + (PaymentsDone ? 1 : 0) + (GlPosted ? 1 : 0);

    /// <summary>The next pay-out action (a label key and the workspace tab that does it); null when completed.</summary>
    public (string Key, string Tab)? NextAction
    {
        get
        {
            if (!PayslipsDone) return ("ws.next_generate_payslips", WorkspaceTab.Payslips);
            if (!PaymentsDone)
            {
                if (FailedCount > 0) return ("ws.next_reissue_failed", WorkspaceTab.Payments);
                if (OpenPaymentCount > 0) return ("ws.next_mark_paid", WorkspaceTab.Payments);
                return ("ws.next_generate_bank_file", WorkspaceTab.Bank);
            }
            if (!GlPosted) return (JournalId is null ? "ws.next_create_journal" : "ws.next_post_gl", WorkspaceTab.Accounting);
            return null;
        }
    }
}

/// <summary>COUNTS of Payroll.usp_PayrollRun_Payout: the approved payrolls in scope by pay-out status.</summary>
public sealed class PayoutCounts
{
    public int ApprovedCount { get; init; }
    public int ExecutionCount { get; init; }
    public int CompletedCount { get; init; }
    /// <summary>Approved or paying out - still to finish.</summary>
    public int OpenCount => ApprovedCount + ExecutionCount;
}

/// <summary>The tabs of a payroll's workspace.</summary>
public static class WorkspaceTab
{
    public const string Overview = "overview";
    public const string Register = "register";
    public const string Validation = "validation";
    public const string Approval = "approval";
    public const string Payslips = "payslips";
    public const string Bank = "bank";
    public const string Payments = "payments";
    public const string Collections = "collections";
    public const string Accounting = "accounting";
    public const string History = "history";
}
