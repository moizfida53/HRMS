using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Web.Models.Audit;

/// <summary>The Audit Report page (/audit): filters only - the grid loads as a partial.</summary>
public sealed class AuditPageModel
{
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public IReadOnlyList<LookupItem> Employees { get; init; } = Array.Empty<LookupItem>();
    public long? EmployeeId { get; init; }
    public string? EmployeeName { get; init; }
    public string? Type { get; init; }
    public DateTime From { get; init; }
    public DateTime To { get; init; }
}

/// <summary>One page of audit rows (partial _AuditGrid).</summary>
public sealed class AuditGridModel
{
    public required PagedResult<EmployeeAuditEntry> Page { get; init; }
    public bool IsFiltered { get; init; }
    /// <summary>Show the company column (the user sees more than one company).</summary>
    public bool ManyCompanies { get; init; }
}

/// <summary>The query string of the grid and the export (dates are the user's local days).</summary>
public sealed class AuditQuery
{
    public int? Company { get; set; }
    public long? Employee { get; set; }
    /// <summary>A transaction type, or a group: "g:calendar", "g:employee", "g:salary", "g:payroll".</summary>
    public string? Type { get; set; }
    public DateTime? From { get; set; }
    public DateTime? To { get; set; }
    public string? Search { get; set; }
    public int Page { get; set; } = 1;
}
