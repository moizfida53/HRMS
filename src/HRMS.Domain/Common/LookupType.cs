namespace HRMS.Domain.Common;

/// <summary>
/// Valid @LookupType values for Core.usp_Lookup_Get. The procedure rejects
/// anything not on this list, so the two must stay in step.
/// </summary>
public static class LookupType
{
    public const string Company     = "COMPANY";
    public const string Branch      = "BRANCH";
    public const string Department  = "DEPARTMENT";
    public const string Section     = "SECTION";
    public const string Designation = "DESIGNATION";
    public const string JobPosition = "JOBPOSITION";
    public const string Location    = "LOCATION";
    public const string CostCenter  = "COSTCENTER";
    public const string Grade       = "GRADE";
    public const string Country     = "COUNTRY";
    public const string Currency    = "CURRENCY";
    public const string Governorate = "GOVERNORATE";
    public const string Employee    = "EMPLOYEE";
}
