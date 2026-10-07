using HRMS.Domain.Common;
using HRMS.Domain.Workforce;

namespace HRMS.Web.Models.Workforce;

/// <summary>
/// Model for the Employees grid partial. Mirrors Organization Setup's
/// <c>GridViewModel&lt;T&gt;</c> in shape, but without the <c>OrgTab</c>
/// coupling - Employees is one master, not eight switched by a tab bar,
/// so it gets its own small, self-contained set of view models instead of
/// reusing the Organization ones.
/// </summary>
public sealed class EmployeeGridViewModel
{
    public required PagedResult<Employee> Page { get; init; }

    public required GridRequest Request { get; init; }

    public int TotalCount => Page.TotalCount;
    public int PageNumber => Page.PageNumber;
    public int PageSize => Page.PageSize;
    public int TotalPages => Page.TotalPages;
    public int FirstRowOnPage => Page.FirstRowOnPage;
    public int LastRowOnPage => Page.LastRowOnPage;

    /// <summary>True when a search or filter is active - changes the empty-state copy.</summary>
    public bool IsFiltered =>
        !string.IsNullOrWhiteSpace(Request.Search) || Request.IsActive.HasValue || Request.ParentId.HasValue;

    public bool IsSortedBy(string column) =>
        string.Equals(Request.SortColumn, column, StringComparison.OrdinalIgnoreCase);

    public bool IsDescending =>
        string.Equals(Request.SortDirection, "DESC", StringComparison.OrdinalIgnoreCase);

    /// <summary>The direction a header click should request next.</summary>
    public string NextDirection(string column) =>
        IsSortedBy(column) && !IsDescending ? "DESC" : "ASC";
}

/// <summary>Model for the shared sortable column-header partial on the Employees grid.</summary>
public sealed class EmployeeSortHeaderModel
{
    public required string Column { get; init; }
    public required string Label { get; init; }
    public required bool IsSorted { get; init; }
    public required bool IsDescending { get; init; }
    public required string NextDirection { get; init; }

    /// <summary>Extra class on the &lt;th&gt;, e.g. "col-p2" (column priority - see _responsive.scss).</summary>
    public string? CssClass { get; init; }

    public static EmployeeSortHeaderModel For(EmployeeGridViewModel grid, string column, string label, string? cssClass = null) => new()
    {
        Column = column,
        Label = label,
        CssClass = cssClass,
        IsSorted = grid.IsSortedBy(column),
        IsDescending = grid.IsSortedBy(column) && grid.IsDescending,
        NextDirection = grid.NextDirection(column)
    };
}

/// <summary>
/// Pagination state for the Employees grid, flattened for the shared
/// _Pagination partial - identical windowing logic to Organization
/// Setup's PaginationModel, kept as its own type to avoid the IGridView/
/// OrgTab coupling that model carries.
/// </summary>
public sealed class EmployeePaginationModel
{
    public required int PageNumber { get; init; }
    public required int TotalPages { get; init; }
    public required int TotalCount { get; init; }
    public required int FirstRow { get; init; }
    public required int LastRow { get; init; }

    public bool HasPrevious => PageNumber > 1;
    public bool HasNext => PageNumber < TotalPages;

    public static EmployeePaginationModel From(EmployeeGridViewModel grid) => new()
    {
        PageNumber = grid.PageNumber,
        TotalPages = grid.TotalPages,
        TotalCount = grid.TotalCount,
        FirstRow = grid.FirstRowOnPage,
        LastRow = grid.LastRowOnPage
    };

    /// <summary>Page numbers to render. -1 marks an ellipsis gap.</summary>
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

/// <summary>
/// Model for the Employee Profile screen - one page, tabbed sections
/// (Personal Info, Employment, Kuwait Compliance, Documents). Personal
/// Info and Employment are the same <see cref="Employee"/> row; Kuwait
/// Compliance is a separate 1:1 record that may not exist yet.
/// </summary>
public sealed class EmployeeDocumentsViewModel
{
    public required long EmployeeId { get; init; }

    public required IReadOnlyList<EmployeeDocumentRow> Rows { get; init; }

    public int MaxFileSizeMb { get; init; } = 5;

    /// <summary>
    /// Rows grouped by Document Section, in the order the procedure returned
    /// them (Seq_num). Document types with no section are grouped last under
    /// "Other Documents".
    /// </summary>
    public IReadOnlyList<DocumentSectionGroup> Groups =>
        Rows.GroupBy(r => r.SectionId)
            .Select(g => new DocumentSectionGroup(
                g.Key,
                g.Key is null || string.IsNullOrWhiteSpace(g.First().SectionNameEng) ? "Other Documents" : g.First().SectionNameEng!,
                g.Key is null ? "مستندات أخرى" : g.First().SectionNameArb,
                g.First().SectionSeq,
                g.ToList()))
            .ToList();

    public int TotalCount => Rows.Count;
    public int UploadedCount => Rows.Count(r => r.HasFile);
    public int MandatoryCount => Rows.Count(r => r.AttachmentMandatory);
    public int MandatoryMissingCount => Rows.Count(r => r.IsMissingRequired);

    public int MandatoryPercent =>
        MandatoryCount == 0 ? 100 : (int)Math.Round((MandatoryCount - MandatoryMissingCount) * 100d / MandatoryCount);
}

public sealed record DocumentSectionGroup(
    int? SectionId, string NameEng, string? NameArb, int? Seq, IReadOnlyList<EmployeeDocumentRow> Rows)
{
    public int UploadedCount => Rows.Count(r => r.HasFile);
    public bool MandatoryComplete => Rows.All(r => !r.IsMissingRequired);
}

public sealed class EmployeeProfileViewModel
{
    public required Employee Employee { get; init; }

    /// <summary>Null when the employee has no compliance record yet - a normal state, not an error.</summary>
    public EmployeeKuwaitCompliance? Compliance { get; init; }

    public required bool IsNew { get; init; }

    public string ActiveTab { get; init; } = "personal";

    /// <summary>
    /// Step-by-step mode (Previous / Next) over the same sections the tabs show.
    /// Used by Add Employee and by the steps that follow creating the employee.
    /// </summary>
    public bool Wizard { get; init; }

    /// <summary>Dropdown data keyed by <see cref="LookupType"/>.</summary>
    public IReadOnlyDictionary<string, IReadOnlyList<LookupItem>> Lookups { get; init; } =
        new Dictionary<string, IReadOnlyList<LookupItem>>();

    public IReadOnlyList<LookupItem> Lookup(string type) =>
        Lookups.TryGetValue(type, out var items) ? items : Array.Empty<LookupItem>();

    public string DisplayName =>
        IsNew
            ? "New Employee"
            : (string.IsNullOrWhiteSpace(Employee.FullName)
                ? $"{Employee.FirstName} {Employee.LastName}".Trim()
                : Employee.FullName);

    public string Initials
    {
        get
        {
            var first = Employee.FirstName?.Trim();
            var last = Employee.LastName?.Trim();
            var a = string.IsNullOrEmpty(first) ? "" : first[..1];
            var b = string.IsNullOrEmpty(last) ? "" : last[..1];
            var initials = (a + b).ToUpperInvariant();
            return string.IsNullOrEmpty(initials) ? "?" : initials;
        }
    }
}
