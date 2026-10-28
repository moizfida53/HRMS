using HRMS.Data.Repositories;
using HRMS.Web.Localization;

namespace HRMS.Web.Services;

public interface IEmployeeNames
{
    /// <summary>
    /// Arabic mode: the Arabic names of these employees (one database call); employees
    /// without one are left out, so the page keeps their English name. English mode: empty.
    /// </summary>
    Task<IReadOnlyDictionary<long, string>> ArabicAsync(IEnumerable<long> employeeIds, CancellationToken cancellationToken = default);

    /// <summary>
    /// Arabic mode: puts each employee's Arabic name on the rows, for lists whose
    /// procedure returns only the English name. English mode: does nothing.
    /// </summary>
    Task LocalizeAsync<T>(IEnumerable<T>? rows, Func<T, long> employeeId, Action<T, string> setName, CancellationToken cancellationToken = default);
}

public sealed class EmployeeNames : IEmployeeNames
{
    private static readonly IReadOnlyDictionary<long, string> None = new Dictionary<long, string>();

    private readonly IEmployeeRepository _employees;
    private readonly IUiText _text;
    private readonly ILogger<EmployeeNames> _logger;

    public EmployeeNames(IEmployeeRepository employees, IUiText text, ILogger<EmployeeNames> logger)
    {
        _employees = employees;
        _text = text;
        _logger = logger;
    }

    public async Task<IReadOnlyDictionary<long, string>> ArabicAsync(IEnumerable<long> employeeIds, CancellationToken cancellationToken = default)
    {
        if (!_text.IsArabic) return None;
        try
        {
            return await _employees.ArabicNamesAsync(employeeIds, cancellationToken).ConfigureAwait(false);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            // the English names stay - the page still works
            _logger.LogWarning(ex, "The employees' Arabic names could not be read (run db/102).");
            return None;
        }
    }

    public async Task LocalizeAsync<T>(IEnumerable<T>? rows, Func<T, long> employeeId, Action<T, string> setName, CancellationToken cancellationToken = default)
    {
        if (!_text.IsArabic || rows is null) return;
        var list = rows as IReadOnlyList<T> ?? rows.ToList();
        if (list.Count == 0) return;

        var names = await ArabicAsync(list.Select(employeeId), cancellationToken).ConfigureAwait(false);
        foreach (var row in list)
        {
            if (names.TryGetValue(employeeId(row), out var arabic)) setName(row, arabic);
        }
    }
}
