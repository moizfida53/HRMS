namespace HRMS.Web.Services;

/// <summary>
/// Employee Self Service (/ess) settings - appsettings.json "SelfService".
/// </summary>
public sealed class SelfServiceOptions
{
    public const string SectionName = "SelfService";

    /// <summary>
    /// How close (metres) the phone must be to the branch location to punch. A location can
    /// have its own radius (Core.Locations.PunchRadiusM, db/146); this is the default.
    /// </summary>
    public int PunchRadiusMeters { get; set; } = 15;

    /// <summary>
    /// The worst GPS accuracy (metres) a punch is accepted with. Indoors a phone often reports
    /// 10-50 m; a reading worse than this is refused ("wait for a stronger signal"), since a
    /// 15 m fence means nothing with a 200 m reading.
    /// </summary>
    public int MaxAccuracyMeters { get; set; } = 50;

    /// <summary>
    /// The time zone of the punch times (they are stored as local time, like the device
    /// import). IANA or Windows id; Kuwait has no daylight saving.
    /// </summary>
    public string TimeZone { get; set; } = "Asia/Kuwait";
}

/// <summary>
/// "Now" in the company's time zone. The server may run in UTC; attendance days and the
/// clock in / out are local (Kuwait) times, as the fingerprint device writes them.
/// </summary>
public static class LocalClock
{
    private static TimeZoneInfo _zone = Resolve("Asia/Kuwait");

    public static void Configure(string? timeZone) => _zone = Resolve(timeZone);

    public static DateTime Now => TrimToSeconds(TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, _zone));

    public static DateTime Today => Now.Date;

    private static DateTime TrimToSeconds(DateTime d) => new(d.Ticks - d.Ticks % TimeSpan.TicksPerSecond, DateTimeKind.Unspecified);

    private static TimeZoneInfo Resolve(string? id)
    {
        foreach (var candidate in new[] { id, "Asia/Kuwait", "Arab Standard Time" })
        {
            if (string.IsNullOrWhiteSpace(candidate)) continue;
            try
            {
                return TimeZoneInfo.FindSystemTimeZoneById(candidate);
            }
            catch (Exception ex) when (ex is TimeZoneNotFoundException or InvalidTimeZoneException)
            {
                // try the next one
            }
        }
        // Kuwait: UTC+3 all year
        return TimeZoneInfo.CreateCustomTimeZone("UTC+03", TimeSpan.FromHours(3), "UTC+03", "UTC+03");
    }
}
