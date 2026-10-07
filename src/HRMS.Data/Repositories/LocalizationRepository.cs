using System.Data;
using Dapper;
using HRMS.Data.Abstractions;
using HRMS.Data.Infrastructure;

namespace HRMS.Data.Repositories;

/// <summary>One UI label: English + Arabic text, keyed by a stable LabelKey.</summary>
public sealed class UiLabel
{
    public string LabelKey { get; set; } = string.Empty;
    public string Module { get; set; } = string.Empty;
    public string EnglishText { get; set; } = string.Empty;
    public string? ArabicText { get; set; }

    /// <summary>
    /// The exact English wording the code or a stored procedure produces, when it
    /// is not referenced by key (procedure result messages, validation messages).
    /// May contain {0}, {1} placeholders for the variable parts.
    /// </summary>
    public string? SourceText { get; set; }
}

public interface ILocalizationRepository
{
    /// <summary>Every active, non-deleted label.</summary>
    Task<IReadOnlyList<UiLabel>> GetAllLabelsAsync(CancellationToken cancellationToken = default);

    /// <summary>A checksum of the label table; changes whenever any label is edited.</summary>
    Task<string?> GetLabelsVersionAsync(CancellationToken cancellationToken = default);

    /// <summary>'en' or 'ar'; null when the user does not exist.</summary>
    Task<string?> GetUserLanguageAsync(long userId, CancellationToken cancellationToken = default);

    Task SetUserLanguageAsync(long userId, string language, CancellationToken cancellationToken = default);

    /// <summary>
    /// Records UI text the application asked for but did not find (a label key
    /// not yet in the table, or an English message with no translation), so it
    /// shows up in Core.UiLabels with an empty ArabicText, ready to be filled in.
    /// <paramref name="itemsJson"/>: [{"key":"..."|null,"text":"..."}].
    /// </summary>
    Task CaptureMissingAsync(string itemsJson, CancellationToken cancellationToken = default);
}

public sealed class LocalizationRepository : ILocalizationRepository
{
    private readonly ISqlExecutor _sql;

    public LocalizationRepository(ISqlExecutor sql) => _sql = sql;

    public Task<IReadOnlyList<UiLabel>> GetAllLabelsAsync(CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", "ALL", DbType.AnsiString, size: 20);
        return _sql.QueryAsync<UiLabel>(StoredProcedure.UiLabelGet, parameters, cancellationToken);
    }

    public Task<string?> GetLabelsVersionAsync(CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", "VERSION", DbType.AnsiString, size: 20);
        return _sql.ExecuteScalarAsync<string>(StoredProcedure.UiLabelGet, parameters, cancellationToken);
    }

    public Task<string?> GetUserLanguageAsync(long userId, CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", "GET", DbType.AnsiString, size: 10);
        parameters.Add("@UserId", userId, DbType.Int64);
        return _sql.ExecuteScalarAsync<string>(StoredProcedure.UserLanguage, parameters, cancellationToken);
    }

    public async Task SetUserLanguageAsync(long userId, string language, CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", "SET", DbType.AnsiString, size: 10);
        parameters.Add("@UserId", userId, DbType.Int64);
        parameters.Add("@Language", language, DbType.AnsiString, size: 2);
        await _sql.ExecuteAsync(StoredProcedure.UserLanguage, parameters, cancellationToken).ConfigureAwait(false);
    }

    public async Task CaptureMissingAsync(string itemsJson, CancellationToken cancellationToken = default)
    {
        var parameters = new DynamicParameters();
        parameters.Add("@Action", "CAPTURE", DbType.AnsiString, size: 20);
        parameters.Add("@ItemsJson", itemsJson, DbType.String, size: -1);
        parameters.Add("@UserId", null, DbType.Int64);
        parameters.Add("@TotalCount", dbType: DbType.Int32, direction: ParameterDirection.Output);
        parameters.Add("@NewId", dbType: DbType.Int64, direction: ParameterDirection.Output);
        parameters.Add("@ResultCode", dbType: DbType.AnsiString, direction: ParameterDirection.Output, size: 40);
        parameters.Add("@ResultMessage", dbType: DbType.String, direction: ParameterDirection.Output, size: 400);
        await _sql.ExecuteAsync(StoredProcedure.UiLabelManage, parameters, cancellationToken).ConfigureAwait(false);
    }
}
