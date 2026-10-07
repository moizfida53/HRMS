using HRMS.Domain.Common;

namespace HRMS.Web.Models.Organization;

/// <summary>Model for the Organization Setup shell page.</summary>
public sealed class OrganizationIndexViewModel
{
    public required OrgTab ActiveTab { get; init; }

    public IReadOnlyList<OrgTab> Tabs => OrganizationTabs.All;
}

/// <summary>
/// The non-generic face of <see cref="GridViewModel{T}"/>, so the shared toolbar
/// and pagination partials can be written once instead of eight times.
/// </summary>
public interface IGridView
{
    OrgTab Tab { get; }
    GridRequest Request { get; }
    int TotalCount { get; }
    int PageNumber { get; }
    int PageSize { get; }
    int TotalPages { get; }
    int FirstRowOnPage { get; }
    int LastRowOnPage { get; }
    bool IsFiltered { get; }
}

/// <summary>Model for one tab's grid partial.</summary>
public sealed class GridViewModel<T> : IGridView where T : class
{
    public required OrgTab Tab { get; init; }

    public required PagedResult<T> Page { get; init; }

    public required GridRequest Request { get; init; }

    public int TotalCount => Page.TotalCount;
    public int PageNumber => Page.PageNumber;
    public int PageSize => Page.PageSize;
    public int TotalPages => Page.TotalPages;
    public int FirstRowOnPage => Page.FirstRowOnPage;
    public int LastRowOnPage => Page.LastRowOnPage;

    /// <summary>True when a search or filter is active - changes the empty-state copy.</summary>
    public bool IsFiltered =>
        !string.IsNullOrWhiteSpace(Request.Search) || Request.IsActive.HasValue;

    /// <summary>Renders the aria-sort value and the sort arrow direction for a column header.</summary>
    public bool IsSortedBy(string column) =>
        string.Equals(Request.SortColumn, column, StringComparison.OrdinalIgnoreCase);

    public bool IsDescending =>
        string.Equals(Request.SortDirection, "DESC", StringComparison.OrdinalIgnoreCase);

    /// <summary>The direction a header click should request next.</summary>
    public string NextDirection(string column) =>
        IsSortedBy(column) && !IsDescending ? "DESC" : "ASC";
}

/// <summary>Model for one tab's add/edit form partial.</summary>
public sealed class FormViewModel<T> where T : class
{
    public required OrgTab Tab { get; init; }

    public required T Model { get; init; }

    public required bool IsNew { get; init; }

    /// <summary>Dropdown data keyed by <see cref="LookupType"/>.</summary>
    public IReadOnlyDictionary<string, IReadOnlyList<LookupItem>> Lookups { get; init; } =
        new Dictionary<string, IReadOnlyList<LookupItem>>();

    public IReadOnlyList<LookupItem> Lookup(string type) =>
        Lookups.TryGetValue(type, out var items) ? items : Array.Empty<LookupItem>();

    public string Title => IsNew ? $"Add {Tab.Singular}" : $"Edit {Tab.Singular}";
}

/// <summary>Uniform JSON envelope returned by every write action.</summary>
public sealed class ActionResponse
{
    public bool Success { get; init; }

    public string Message { get; init; } = string.Empty;

    public long Id { get; init; }

    public string? ErrorCode { get; init; }

    /// <summary>Field-level validation errors, keyed by property name.</summary>
    public IDictionary<string, string[]>? Errors { get; init; }

    public static ActionResponse Ok(long id, string message) =>
        new() { Success = true, Id = id, Message = message };

    public static ActionResponse Failed(string message, string? errorCode = null) =>
        new() { Success = false, Message = message, ErrorCode = errorCode };

    public static ActionResponse Invalid(IDictionary<string, string[]> errors) =>
        new()
        {
            Success = false,
            Message = "Please correct the highlighted fields.",
            ErrorCode = "VALIDATION",
            Errors = errors
        };
}

/// <summary>
/// Pagination state, flattened for the shared _Pagination partial.
/// Builds a compact window of page numbers with ellipses rather than
/// rendering hundreds of links for a large master.
/// </summary>
public sealed class PaginationModel
{
    public required int PageNumber { get; init; }
    public required int TotalPages { get; init; }
    public required int TotalCount { get; init; }
    public required int FirstRow { get; init; }
    public required int LastRow { get; init; }

    public bool HasPrevious => PageNumber > 1;
    public bool HasNext => PageNumber < TotalPages;

    public static PaginationModel From(IGridView view) => new()
    {
        PageNumber = view.PageNumber,
        TotalPages = view.TotalPages,
        TotalCount = view.TotalCount,
        FirstRow = view.FirstRowOnPage,
        LastRow = view.LastRowOnPage
    };

    /// <summary>
    /// Page numbers to render. -1 marks an ellipsis gap.
    /// Always shows the first page, the last page, and a window around the
    /// current one - so the control stays the same width at page 2 or page 240.
    /// </summary>
    public IEnumerable<int> Window(int radius = 1)
    {
        if (TotalPages <= 1)
        {
            yield break;
        }

        var last = -2;

        for (var page = 1; page <= TotalPages; page++)
        {
            var isEdge = page == 1 || page == TotalPages;
            var isNear = Math.Abs(page - PageNumber) <= radius;

            if (!isEdge && !isNear)
            {
                continue;
            }

            if (last >= 0 && page - last > 1)
            {
                yield return -1;
            }

            yield return page;
            last = page;
        }
    }
}

/// <summary>Model for the shared sortable column-header partial.</summary>
public sealed class SortHeaderModel
{
    public required string Column { get; init; }
    public required string Label { get; init; }
    public required bool IsSorted { get; init; }
    public required bool IsDescending { get; init; }
    public required string NextDirection { get; init; }

    /// <summary>Extra class on the &lt;th&gt;, e.g. "col-p2" (column priority - see _responsive.scss).</summary>
    public string? CssClass { get; init; }

    public static SortHeaderModel For(IGridView view, string column, string label, string? cssClass = null) => new()
    {
        Column = column,
        Label = label,
        CssClass = cssClass,
        IsSorted = string.Equals(view.Request.SortColumn, column, StringComparison.OrdinalIgnoreCase),
        IsDescending = string.Equals(view.Request.SortDirection, "DESC", StringComparison.OrdinalIgnoreCase),
        NextDirection =
            string.Equals(view.Request.SortColumn, column, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(view.Request.SortDirection, "DESC", StringComparison.OrdinalIgnoreCase)
                ? "DESC"
                : "ASC"
    };
}
