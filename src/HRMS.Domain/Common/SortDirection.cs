namespace HRMS.Domain.Common;

public static class SortDirection
{
    public const string Ascending  = "ASC";
    public const string Descending = "DESC";

    /// <summary>Returns ASC or DESC only. Any other input collapses to ASC.</summary>
    public static string Normalise(string? value) =>
        string.Equals(value, Descending, StringComparison.OrdinalIgnoreCase)
            ? Descending
            : Ascending;
}
