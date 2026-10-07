namespace HRMS.Domain.Common;

/// <summary>
/// The action verbs understood by every <c>usp_*_Manage</c> stored procedure.
/// Kept as constants (not an enum) so the exact string sent to SQL Server is
/// visible and cannot drift from the procedure's CHECK on @Action.
/// </summary>
public static class DbAction
{
    public const string List   = "LIST";
    public const string Get    = "GET";
    public const string Insert = "INSERT";
    public const string Update = "UPDATE";
    public const string Delete = "DELETE";
    public const string Toggle = "TOGGLE";
}
