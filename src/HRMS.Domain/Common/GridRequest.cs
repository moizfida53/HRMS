namespace HRMS.Domain.Common;

/// <summary>
/// Everything a grid needs to ask the database for a page of rows.
/// Shared by all eight Organization Setup masters.
/// </summary>
public sealed class GridRequest
{
    private const int MaxPageSize = 200;

    private int _pageNumber = 1;
    private int _pageSize = 25;

    /// <summary>Free-text search. Matched against code/name columns inside the procedure.</summary>
    public string? Search { get; set; }

    /// <summary>null = both active and inactive, true = active only, false = inactive only.</summary>
    public bool? IsActive { get; set; }

    /// <summary>Scopes the result to one company. Null means every company the user can see.</summary>
    public int? CompanyId { get; set; }

    /// <summary>
    /// Top-bar company filter: comma-separated CompanyIds, null = all.
    /// Always set by the controller from the filter cookie - never trusted from the query string.
    /// </summary>
    public string? CompanyIds { get; set; }

    /// <summary>Optional second-level filter, e.g. DepartmentId when listing Sections.</summary>
    public int? ParentId { get; set; }

    public int PageNumber
    {
        get => _pageNumber;
        set => _pageNumber = value < 1 ? 1 : value;
    }

    public int PageSize
    {
        get => _pageSize;
        set => _pageSize = value switch
        {
            < 1           => 25,
            > MaxPageSize => MaxPageSize,
            _             => value
        };
    }

    /// <summary>
    /// Logical sort key. Never concatenated into SQL - it is validated against a
    /// per-entity allowlist in the repository and resolved by a CASE expression
    /// inside the stored procedure.
    /// </summary>
    public string? SortColumn { get; set; }

    public string? SortDirection { get; set; }
}
