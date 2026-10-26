namespace HRMS.Web.Models.Organization;

/// <summary>
/// Everything the UI needs to know about one Organization Setup tab.
/// Adding a ninth master means adding one entry here, one repository, one
/// stored procedure and two partial views - nothing else changes.
/// </summary>
public sealed record OrgTab(
    string Key,
    string Title,
    string Singular,
    string Description,
    string Icon,
    string GridPartial,
    string FormPartial,
    string DuplicateEntity);

public static class OrganizationTabs
{
    public const string Companies    = "companies";
    public const string Branches     = "branches";
    public const string Departments  = "departments";
    public const string Sections     = "sections";
    public const string Designations = "designations";
    public const string JobPositions = "job-positions";
    public const string Locations    = "locations";
    public const string CostCenters  = "cost-centers";
    public const string DocumentTypes = "employee-documents";
    public const string OrgDocumentTypes = "organization-documents";
    public const string AssetTypes = "asset-types";

    public static readonly IReadOnlyList<OrgTab> All =
    [
        new(Companies, "Companies", "Company",
            "Group companies and legal entities",
            "building", "_CompaniesGrid", "_CompanyForm", "COMPANY"),

        new(Branches, "Branches", "Branch",
            "Offices, showrooms and satellite sites",
            "branch", "_BranchesGrid", "_BranchForm", "BRANCH"),

        new(Departments, "Departments", "Department",
            "Functional divisions and their reporting lines",
            "layers", "_DepartmentsGrid", "_DepartmentForm", "DEPARTMENT"),

        new(Sections, "Sections", "Section",
            "Teams within each department",
            "sections", "_SectionsGrid", "_SectionForm", "SECTION"),

        new(Designations, "Designations", "Designation",
            "Job titles as printed on Civil IDs and work permits",
            "badge", "_DesignationsGrid", "_DesignationForm", "DESIGNATION"),

        new(JobPositions, "Job Positions", "Job position",
            "Seats in the organisation chart",
            "briefcase", "_JobPositionsGrid", "_JobPositionForm", "JOBPOSITION"),

        new(Locations, "Locations", "Location",
            "Physical work sites for attendance and cost tracking",
            "pin", "_LocationsGrid", "_LocationForm", "LOCATION"),

        new(CostCenters, "Cost Centers", "Cost center",
            "Financial roll-up used by payroll reporting",
            "wallet", "_CostCentersGrid", "_CostCenterForm", "COSTCENTER"),

        // db/63: group-wide (no company); the "+" on the form adds a section in place
        new(DocumentTypes, "Employee Documents", "Document type",
            "Documents employees upload, their section and whether they are mandatory",
            "folder", "_DocumentTypesGrid", "_DocumentTypeForm", "DOCUMENTTYPE"),

        // db/73: group-wide; each company keeps them on Workforce > Organizations, with alerts on the expiry date
        new(OrgDocumentTypes, "Organization Documents", "Organization document type",
            "Legal and compliance documents each company keeps, and the alerts on their expiry date",
            "shield", "_OrgDocumentTypesGrid", "_OrgDocumentTypeForm", "ORGDOCUMENTTYPE"),

        // db/84: group-wide; the assets themselves are on Workforce > Assets, with alerts on the expiry date
        new(AssetTypes, "Asset Types", "Asset type",
            "Kinds of company asset - cars, motor bikes, phones - and the alerts on their expiry date",
            "box", "_AssetTypesGrid", "_AssetTypeForm", "ASSETTYPE")
    ];

    private static readonly Dictionary<string, OrgTab> Index =
        All.ToDictionary(t => t.Key, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// Resolves a tab key from the query string. An unknown key falls back to
    /// Companies rather than throwing, so a stale bookmark still opens the page.
    /// </summary>
    public static OrgTab Resolve(string? key) =>
        key is not null && Index.TryGetValue(key, out var tab) ? tab : All[0];

    public static bool IsKnown(string? key) =>
        key is not null && Index.ContainsKey(key);
}
