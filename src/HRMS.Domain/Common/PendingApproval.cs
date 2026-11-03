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
    public bool PayItemL1 { get; init; }
    public bool PayItemL2 { get; init; }
    public bool PayItemSelf { get; init; }
    public bool SettlementL1 { get; init; }
    public bool SettlementL2 { get; init; }
    public bool SettlementSelf { get; init; }
    public bool LeaveL1 { get; init; }
    public bool LeaveL2 { get; init; }
    public bool LeaveSelf { get; init; }
}
