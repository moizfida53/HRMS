namespace HRMS.Domain.Common;

/// <summary>
/// The outcome of an INSERT / UPDATE / DELETE / TOGGLE, as reported by the
/// stored procedure's output parameters. Business failures (duplicate code,
/// row still referenced) come back here as Success=false with a message that is
/// safe to show the user - they are not exceptions.
/// </summary>
public sealed class SaveResult
{
    public bool Success { get; init; }

    /// <summary>Identity of the affected row. Populated on INSERT.</summary>
    public long Id { get; init; }

    public string Message { get; init; } = string.Empty;

    /// <summary>Machine-readable reason, e.g. DUPLICATE_CODE or IN_USE.</summary>
    public string? ErrorCode { get; init; }

    public static SaveResult Ok(long id, string message) =>
        new() { Success = true, Id = id, Message = message };

    public static SaveResult Fail(string message, string? errorCode = null) =>
        new() { Success = false, Message = message, ErrorCode = errorCode };
}
