using HRMS.Domain.Common;
using HRMS.Domain.Workforce;
using HRMS.Web.Models.Workforce;

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
    /// <summary>One employee's audit (the profile popup): no employee / company columns.</summary>
    public bool OneEmployee { get; init; }
    public string Sort { get; init; } = AuditQuery.DefaultSort;
    public string Direction { get; init; } = "DESC";

    /// <summary>A sortable column header (same look as the employee grid's).</summary>
    public EmployeeSortHeaderModel Header(string column, string label, string? cssClass = null)
    {
        var sorted = string.Equals(Sort, column, StringComparison.Ordinal);
        var desc = sorted && Direction == "DESC";
        return new EmployeeSortHeaderModel
        {
            Column = column, Label = label, CssClass = cssClass, IsSorted = sorted, IsDescending = desc,
            // first click: newest first for the date, A-Z for text; then it flips
            NextDirection = sorted ? (desc ? "ASC" : "DESC") : (column == AuditQuery.DefaultSort ? "DESC" : "ASC")
        };
    }
}

/// <summary>The audit popup of one employee (profile page): search and date range only.</summary>
public sealed class EmployeeAuditPanelModel
{
    public long EmployeeId { get; init; }
    public string EmployeeName { get; init; } = string.Empty;
    public DateTime From { get; init; }
    public DateTime To { get; init; }
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
    /// <summary>Date (default) / Employee / Type / Field / ChangedBy.</summary>
    public string? Sort { get; set; }
    public string? Dir { get; set; }
    /// <summary>"employee" = the profile popup of one employee.</summary>
    public string? Mode { get; set; }

    public const string DefaultSort = "Date";
    public static readonly string[] SortColumns = ["Date", "Employee", "Type", "Field", "ChangedBy"];

    public string SortOrDefault => SortColumns.Contains(Sort) ? Sort! : DefaultSort;
    public string DirOrDefault => string.Equals(Dir, "ASC", StringComparison.OrdinalIgnoreCase) ? "ASC"
        : string.Equals(Dir, "DESC", StringComparison.OrdinalIgnoreCase) ? "DESC"
        : SortOrDefault == DefaultSort ? "DESC" : "ASC";
}
