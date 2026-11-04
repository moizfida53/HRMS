namespace HRMS.Domain.Common;

/// <summary>One kind of record waiting for the user's approval (db/110, Core.usp_PendingApprovals).</summary>
public sealed class PendingApproval
{
    /// <summary>PAYROLL, PAYITEM, SETTLEMENT or LEAVE.</summary>
    public string Kind { get; init; } = string.Empty;
    public int Count { get; init; }
    /// <summary>When the oldest of them was submitted.</summary>
    public DateTime? Oldest { get; init; }
}

/// <summary>The approval rights the count is made for (Security > Create Roles > Approval rights).</summary>
public sealed class PendingApprovalRights
{
    public long UserId { get; init; }
    public long? EmployeeId { get; init; }
    public int? CompanyId { get; init; }
    public string? CompanyIds { get; init; }
    public bool PayrollL1 { get; init; }
    public bool PayrollL2 { get; init; }
    public bool PayrollSelf { get; init; }
    /// <summary>db/111 Payroll Components: Salary Revisions, Earnings, Deductions, Loans (L1 / L2 / own).</summary>
    public bool SalRevL1 { get; init; }
    public bool SalRevL2 { get; init; }
    public bool SalRevSelf { get; init; }
    public bool EarnL1 { get; init; }
    public bool EarnL2 { get; init; }
    public bool EarnSelf { get; init; }
    public bool DedL1 { get; init; }
    public bool DedL2 { get; init; }
    public bool DedSelf { get; init; }
    public bool LoanL1 { get; init; }
    public bool LoanL2 { get; init; }
    public bool LoanSelf { get; init; }
    public bool IsAdmin { get; init; }
    public bool SettlementL1 { get; init; }
    public bool SettlementL2 { get; init; }
    public bool SettlementSelf { get; init; }
    public bool LeaveL1 { get; init; }
    public bool LeaveL2 { get; init; }
    public bool LeaveSelf { get; init; }
}
