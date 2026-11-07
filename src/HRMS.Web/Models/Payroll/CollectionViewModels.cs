using HRMS.Domain.Common;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Models.Payroll;

/// <summary>Payroll Components &gt; Collection (db/115): the page.</summary>
public sealed class CollectionPageModel
{
    public IReadOnlyList<LookupItem> Companies { get; init; } = Array.Empty<LookupItem>();
    public int? SelectedCompanyId { get; init; }
    public bool CanEdit { get; init; }
    /// <summary>db/123: the Collections tab of a payroll's workspace (its company and month, fixed).</summary>
    public WorkspaceNav? Workspace { get; init; }
}

/// <summary>The key figures and the list of one company's payroll month.</summary>
public sealed class CollectionGridModel
{
    /// <summary>The company has no payroll yet - nothing to pick.</summary>
    public bool NoMonth { get; init; }
    public DateTime Month { get; init; }
    public CollectionSummary Summary { get; init; } = new();
    public IReadOnlyList<CollectionItem> Items { get; init; } = Array.Empty<CollectionItem>();
    public string? Status { get; init; }
    public bool IsFiltered { get; init; }
    public bool CanEdit { get; init; }
}

public static class CollectionFormat
{
    public static string StatusKey(string? status) => status == CollectionStatus.Collected ? "col.status_collected" : "col.status_pending";
    public static string StatusBadge(string? status) => status == CollectionStatus.Collected ? "success" : "warning";

    public static string ActionKey(string? action) => action switch
    {
        "CREATED" => "col.h_created",
        "UPDATED" => "col.h_updated",
        "COLLECTED" => "col.h_collected",
        "REOPENED" => "col.h_reopened",
        "REMOVED" => "col.h_removed",
        _ => "col.h_changed"
    };
}
