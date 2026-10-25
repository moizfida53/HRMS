using HRMS.Domain.Organization;

namespace HRMS.Web.Models.Organization;

/// <summary>What the user may do on Workforce > Organizations (Security > Create Roles, "ORG.DOCUMENTS").</summary>
public sealed record OrgDocumentRights(bool CanView, bool CanEdit, bool CanDelete);

public sealed class OrgDocumentsPageModel
{
    public required OrgDocumentRights Rights { get; init; }
    public IReadOnlyList<OrgCompanySummary> Companies { get; init; } = Array.Empty<OrgCompanySummary>();
    /// <summary>The company to open first (from the address, e.g. a Dashboard alert).</summary>
    public int? SelectedCompanyId { get; init; }

    public int ExpiredTotal => Companies.Sum(c => c.ExpiredCount);
    public int DueTotal => Companies.Sum(c => c.DueCount);
    public int MissingTotal => Companies.Sum(c => c.MissingCount);
}

public sealed class OrgCompanyListModel
{
    public IReadOnlyList<OrgCompanySummary> Companies { get; init; } = Array.Empty<OrgCompanySummary>();
}

/// <summary>One company's Legal & Compliance Documents.</summary>
public sealed class OrgCompanyDocumentsModel
{
    public required OrgCompanySummary Company { get; init; }
    public required IReadOnlyList<OrgDocumentRow> Rows { get; init; }
    public required OrgDocumentRights Rights { get; init; }
}

public sealed class OrgDocumentFormModel
{
    public required OrgCompanySummary Company { get; init; }
    public required OrgDocumentRow Row { get; init; }
    /// <summary>A renewal: a new version that archives the current one.</summary>
    public bool Renew { get; init; }
    public int MaxFileSizeMb { get; init; } = 5;
}

public sealed class OrgDocumentHistoryModel
{
    public required OrgDocumentRow Row { get; init; }
    public required IReadOnlyList<OrgDocumentVersion> Versions { get; init; }
}
