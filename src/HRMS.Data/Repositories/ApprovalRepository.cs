using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;
using HRMS.Domain.Common;

namespace HRMS.Data.Repositories;

/// <summary>What is waiting for a user's approval, across payrolls, pay items, settlements and leave (db/110).</summary>
public interface IApprovalRepository
{
    Task<IReadOnlyList<PendingApproval>> PendingAsync(PendingApprovalRights rights, CancellationToken cancellationToken = default);
}

public sealed class ApprovalRepository : IApprovalRepository
{
    private readonly ISqlExecutor _sql;

    public ApprovalRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<PendingApproval>> PendingAsync(PendingApprovalRights r, CancellationToken cancellationToken = default)
    {
        var p = new DynamicParameters();
        p.Add("@UserId", r.UserId, DbType.Int64);
        p.Add("@EmployeeId", r.EmployeeId, DbType.Int64);
        p.Add("@CompanyId", r.CompanyId, DbType.Int32);
        p.Add("@CompanyIds", string.IsNullOrWhiteSpace(r.CompanyIds) ? null : r.CompanyIds, DbType.String, size: 2000);
        p.Add("@PrL1", r.PayrollL1, DbType.Boolean);
        p.Add("@PrL2", r.PayrollL2, DbType.Boolean);
        p.Add("@PrSelf", r.PayrollSelf, DbType.Boolean);
        p.Add("@PiL1", r.PayItemL1, DbType.Boolean);
        p.Add("@PiL2", r.PayItemL2, DbType.Boolean);
        p.Add("@PiSelf", r.PayItemSelf, DbType.Boolean);
        p.Add("@FsL1", r.SettlementL1, DbType.Boolean);
        p.Add("@FsL2", r.SettlementL2, DbType.Boolean);
        p.Add("@FsSelf", r.SettlementSelf, DbType.Boolean);
        p.Add("@LvL1", r.LeaveL1, DbType.Boolean);
        p.Add("@LvL2", r.LeaveL2, DbType.Boolean);
        p.Add("@LvSelf", r.LeaveSelf, DbType.Boolean);
        return _sql.QueryAsync<PendingApproval>(StoredProcedure.PendingApprovals, p, cancellationToken);
    }
}
