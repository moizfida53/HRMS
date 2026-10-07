namespace HRMS.Domain.Common;

/// <summary>
/// One row of any dropdown in the application. Every lookup in the system is
/// served by the single Core.usp_Lookup_Get procedure.
/// </summary>
public sealed class LookupItem
{
    public int Id { get; set; }

    public string Code { get; set; } = string.Empty;

    public string Text { get; set; } = string.Empty;

    /// <summary>Set for cascading lookups, e.g. a Section's owning DepartmentId.</summary>
    public int? ParentId { get; set; }
}
