namespace HRMS.Web.Services;

/// <summary>
/// Employee Self Service (/ess) settings - appsettings.json "SelfService".
/// </summary>
public sealed class SelfServiceOptions
{
    public const string SectionName = "SelfService";

    /// <summary>
    /// The overall punch radius: how close (metres) the phone must be to the branch location to punch.
    /// A phone's GPS is rarely better than 10-25 m inside or beside a building, and the branch's own
    /// latitude / longitude is itself only as exact as it was typed - a radius under about 30 m turns
    /// away people who are standing in the building. 50 m keeps the punch to the building and its
    /// surroundings. A location can have its own radius (Core.Locations.PunchRadiusM, db/146).
    /// </summary>
    public int PunchRadiusMeters { get; set; } = 50;

    /// <summary>
    /// The worst GPS accuracy (metres) a punch is accepted with. Indoors a phone often reports
    /// 10-50 m; a reading worse than this is refused ("wait for a stronger signal"), since a
    /// 50 m fence means nothing with a 200 m reading.
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
