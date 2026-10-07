namespace HRMS.Domain.Common;

public sealed class PagedResult<T>
{
    public IReadOnlyList<T> Items { get; init; } = Array.Empty<T>();

    public int TotalCount { get; init; }

    public int PageNumber { get; init; } = 1;

    public int PageSize { get; init; } = 25;

    public int TotalPages =>
        PageSize <= 0 ? 0 : (int)Math.Ceiling(TotalCount / (double)PageSize);

    public bool HasPrevious => PageNumber > 1;

    public bool HasNext => PageNumber < TotalPages;

    public int FirstRowOnPage => TotalCount == 0 ? 0 : ((PageNumber - 1) * PageSize) + 1;

    public int LastRowOnPage => Math.Min(PageNumber * PageSize, TotalCount);

    public static PagedResult<T> Empty(int pageSize = 25) => new() { PageSize = pageSize };
}
