using System.Globalization;
using System.Text;
using System.Text.RegularExpressions;

namespace HRMS.Domain.Attendance;

/// <summary>What a column of a device report holds.</summary>
public enum AttColumn
{
    None,
    EmployeeId,
    Name,
    Date,
    /// <summary>A date and a time in one cell (one row per punch).</summary>
    DateTime,
    /// <summary>A time with a separate Date column (one row per punch).</summary>
    Time,
    ClockIn,
    ClockOut,
    /// <summary>Check-in / check-out of a punch.</summary>
    State,
    Weekday,
    Department,
    /// <summary>Worked hours the device worked out (not used: the hours are worked out again).</summary>
    Total
}

/// <summary>One column as found: its header, what it holds and how sure the guess is.</summary>
public sealed class AttColumnGuess
{
    public int Index { get; init; }
    public string Header { get; init; } = string.Empty;
    public AttColumn Role { get; set; }
    /// <summary>header (from its title), data (from its values), or none.</summary>
    public string Basis { get; set; } = "none";
    public string Sample { get; init; } = string.Empty;
    /// <summary>What its values look like: id, text, date, time, datetime, weekday, state, number, empty.</summary>
    public string DataKind { get; init; } = "empty";
}

/// <summary>The layout of a device report: where its header is, what each column holds and the format.</summary>
public sealed class AttLayout
{
    /// <summary>Index of the header row (-1: no header).</summary>
    public int HeaderRow { get; init; } = -1;
    public List<AttColumnGuess> Columns { get; init; } = [];
    /// <summary>PAIRED (a row per day: date, in, out) or PUNCH (a row per punch).</summary>
    public string Format { get; set; } = "PAIRED";
    /// <summary>dd/MM (day first) or MM/dd, when the dates are written with slashes.</summary>
    public bool DayFirst { get; set; } = true;
    public List<string> Warnings { get; } = [];

    public int? IndexOf(AttColumn role) => Columns.FirstOrDefault(c => c.Role == role)?.Index;

    /// <summary>The roles were enough to read the file.</summary>
    public string? Problem
    {
        get
        {
            if (IndexOf(AttColumn.EmployeeId) is null) return "No column with the employee number / ID was found.";
            var paired = IndexOf(AttColumn.ClockIn) is not null || IndexOf(AttColumn.ClockOut) is not null;
            var punch = IndexOf(AttColumn.DateTime) is not null || (IndexOf(AttColumn.Date) is not null && IndexOf(AttColumn.Time) is not null);
            if (!paired && !punch) return "No clock-in / clock-out or punch time column was found.";
            if (paired && IndexOf(AttColumn.Date) is null && !Columns.Any(c => c.Role is AttColumn.ClockIn or AttColumn.ClockOut && c.DataKind == "datetime"))
                return "No date column was found.";
            return null;
        }
    }

    /// <summary>"Employee ID: رقم الموظف · Date: التاريخ · …" - kept with the import.</summary>
    public string Describe() => string.Join(" · ", Columns.Where(c => c.Role is not AttColumn.None and not AttColumn.Total)
                                                          .Select(c => $"{c.Role}: {(string.IsNullOrWhiteSpace(c.Header) ? "col " + (c.Index + 1) : c.Header)}"));
}

/// <summary>One employee's day read from the file.</summary>
public sealed class AttParsedDay
{
    public string DeviceId { get; init; } = string.Empty;
    public string? Name { get; set; }
    public DateOnly Date { get; init; }
    public DateTime? ClockIn { get; set; }
    public DateTime? ClockOut { get; set; }
    public int Punches { get; set; }
    public int Row { get; set; }
}

public sealed class AttParseResult
{
    public List<AttParsedDay> Days { get; } = [];
    public int DataRows { get; set; }
    public int Skipped { get; set; }
    /// <summary>The first rows skipped and why (row numbers as in Excel).</summary>
    public List<string> SkipReasons { get; } = [];
    public DateOnly? From => Days.Count == 0 ? null : Days.Min(d => d.Date);
    public DateOnly? To => Days.Count == 0 ? null : Days.Max(d => d.Date);
}

/// <summary>
/// Reads a fingerprint device report. Most devices (ZKTeco, Hikvision, Suprema, Anviz ...) export
/// either a row per employee and day (number, name, date, clock in, clock out ...) or a row per
/// punch (number, date-time, check-in / check-out). The columns are found from their titles
/// (English or Arabic) and checked against their values; a file with no title row is read from the
/// values alone. The guess can be corrected before the file is imported.
/// </summary>
public static partial class AttendanceFileParser
{
    // the titles, most specific first (a title is matched against each list in this order)
    private static readonly (AttColumn Role, string[] Words)[] Titles =
    [
        (AttColumn.Total, ["total", "worked hours", "work hours", "working hours", "duration", "hours worked", "إجمالي", "اجمالي", "مجموع", "المدة", "ساعات العمل", "عدد الساعات", "late", "early", "short", "deduction", "deadline", "minutes", "تأخير", "التأخير", "النقص", "خصم", "دقائق"]),
        (AttColumn.ClockIn, ["clock in", "clock-in", "clockin", "check in", "check-in", "checkin", "time in", "in time", "first in", "first punch", "arrival", "on duty", "start time", "punch in", "الدخول", "دخول", "الحضور", "حضور", "وقت الدخول"]),
        (AttColumn.ClockOut, ["clock out", "clock-out", "clockout", "check out", "check-out", "checkout", "time out", "out time", "last out", "last punch", "departure", "off duty", "end time", "punch out", "الخروج", "خروج", "الانصراف", "انصراف", "وقت الخروج"]),
        (AttColumn.DateTime, ["date time", "datetime", "date/time", "date & time", "punch time", "check time", "clock time", "log time", "record time", "verify time", "التاريخ والوقت", "وقت البصمة"]),
        (AttColumn.Department, ["department", "dept", "section", "القسم", "الإدارة", "الادارة"]),
        (AttColumn.Name, ["employee name", "full name", "name", "staff name", "اسم الموظف", "الاسم", "اسم"]),
        (AttColumn.EmployeeId, ["employee no", "employee number", "emp no", "emp. no", "employee id", "emp id", "empid", "staff id", "staff no", "ac-no", "ac no", "acno", "user id", "userid", "person id", "badge", "enroll", "card no", "pin", "code", "no.", "id", "رقم الموظف", "الرقم الوظيفي", "الرقم", "رقم", "كود", "الكود"]),
        (AttColumn.Weekday, ["weekday", "day name", "day", "اليوم"]),
        (AttColumn.Date, ["date", "work date", "التاريخ", "تاريخ", "اليوم والتاريخ"]),
        (AttColumn.State, ["state", "status", "check type", "in/out", "punch type", "type", "event", "الحالة", "النوع"]),
        (AttColumn.Time, ["time", "الوقت", "وقت"])
    ];

    private static readonly string[] DayNames =
    [
        "sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday",
        "sun", "mon", "tue", "wed", "thu", "fri", "sat",
        "الأحد", "الاحد", "الاثنين", "الإثنين", "الثلاثاء", "الأربعاء", "الاربعاء", "الخميس", "الجمعة", "السبت"
    ];

    private static readonly string[] InWords = ["in", "c/in", "checkin", "check in", "check-in", "clock in", "i", "0", "دخول", "حضور", "in1", "on duty", "duty on"];
    private static readonly string[] OutWords = ["out", "c/out", "checkout", "check out", "check-out", "clock out", "o", "1", "خروج", "انصراف", "out1", "off duty", "duty off"];

    [GeneratedRegex(@"^\s*(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm|a\.m\.|p\.m\.|ص|م)?\s*$", RegexOptions.IgnoreCase)]
    private static partial Regex TimeRx();

    [GeneratedRegex(@"\d{1,4}[-/.]\d{1,2}[-/.]\d{1,4}|\d{1,2}[- ][A-Za-z]{3,9}[- ]\d{2,4}")]
    private static partial Regex DatePartRx();

    // ------------------------------------------------------------------ detection

    /// <summary>Works out the layout of the rows (the first sheet of the workbook).</summary>
    public static AttLayout Detect(IReadOnlyList<string[]> rows)
    {
        var headerRow = FindHeaderRow(rows);
        var width = rows.Count == 0 ? 0 : rows.Max(r => r.Length);
        var data = rows.Skip(headerRow + 1).Where(r => r.Any(c => !string.IsNullOrWhiteSpace(c))).Take(300).ToList();

        var columns = new List<AttColumnGuess>();
        for (var c = 0; c < width; c++)
        {
            var header = headerRow >= 0 && c < rows[headerRow].Length ? rows[headerRow][c].Trim() : string.Empty;
            var values = data.Select(r => c < r.Length ? Normalize(r[c]) : string.Empty).Where(v => v.Length > 0).ToList();
            var kind = Kind(values, data.Count);
            var digitsOnly = values.Count > 0 && values.All(v => Regex.IsMatch(v, @"^\d+(\.0+)?$"));
            var guess = new AttColumnGuess
            {
                Index = c,
                Header = header,
                DataKind = kind,
                Sample = values.FirstOrDefault() ?? string.Empty
            };
            if (TitleRole(header) is { } role && Fits(role, kind, digitsOnly))
            {
                guess.Role = role;
                guess.Basis = "header";
            }
            columns.Add(guess);
        }

        // one column per role (the first one wins; a second is left out)
        foreach (var dup in columns.Where(c => c.Role != AttColumn.None).GroupBy(c => c.Role).Where(g => g.Count() > 1 && g.Key != AttColumn.Total))
        {
            foreach (var extra in dup.Skip(1)) { extra.Role = AttColumn.None; extra.Basis = "none"; }
        }

        // fill what the titles did not say, from the values
        AttColumnGuess? Free(Func<AttColumnGuess, bool> test) => columns.FirstOrDefault(c => c.Role == AttColumn.None && test(c));
        void Set(AttColumnGuess? c, AttColumn role) { if (c is not null) { c.Role = role; c.Basis = "data"; } }
        bool Has(AttColumn role) => columns.Any(c => c.Role == role);

        // a "Time" column holding a date and a time (ZKTeco and others) is the punch date-time
        foreach (var c in columns.Where(c => c.Role == AttColumn.Time && c.DataKind == "datetime"))
        {
            if (!Has(AttColumn.Date) && !Has(AttColumn.DateTime)) c.Role = AttColumn.DateTime;
        }
        if (!Has(AttColumn.EmployeeId)) Set(Free(c => c.DataKind == "id"), AttColumn.EmployeeId);
        if (!Has(AttColumn.Name)) Set(Free(c => c.DataKind == "text"), AttColumn.Name);
        if (!Has(AttColumn.Weekday)) Set(Free(c => c.DataKind == "weekday"), AttColumn.Weekday);
        if (!Has(AttColumn.ClockIn) && !Has(AttColumn.ClockOut) && !Has(AttColumn.Time))
        {
            var times = columns.Where(c => c.Role == AttColumn.None && c.DataKind == "time").ToList();
            if (times.Count >= 2) { Set(times[0], AttColumn.ClockIn); Set(times[1], AttColumn.ClockOut); }
            else if (times.Count == 1) Set(times[0], AttColumn.Time);
        }
        if (!Has(AttColumn.Date)) Set(Free(c => c.DataKind == "date"), AttColumn.Date);
        if (!Has(AttColumn.DateTime) && !Has(AttColumn.ClockIn) && !Has(AttColumn.ClockOut))
        {
            var dts = columns.Where(c => c.Role == AttColumn.None && c.DataKind == "datetime").ToList();
            if (dts.Count >= 2 && !Has(AttColumn.Time)) { Set(dts[0], AttColumn.ClockIn); Set(dts[1], AttColumn.ClockOut); }
            else if (dts.Count == 1) Set(dts[0], AttColumn.DateTime);
        }
        if (!Has(AttColumn.State)) Set(Free(c => c.DataKind == "state"), AttColumn.State);

        var layout = new AttLayout { HeaderRow = headerRow, Columns = columns };
        layout.Format = layout.IndexOf(AttColumn.ClockIn) is not null || layout.IndexOf(AttColumn.ClockOut) is not null ? "PAIRED" : "PUNCH";
        if (layout.IndexOf(AttColumn.Date) is { } di) layout.DayFirst = DayFirst(data.Select(r => di < r.Length ? Normalize(r[di]) : string.Empty));
        else if (layout.IndexOf(AttColumn.DateTime) is { } dti) layout.DayFirst = DayFirst(data.Select(r => dti < r.Length ? Normalize(r[dti]) : string.Empty));
        if (headerRow < 0) layout.Warnings.Add("The file has no title row - the columns were worked out from their values.");
        return layout;
    }

    /// <summary>Sets the roles chosen on the preview (column index -> role); the format follows.</summary>
    public static void Apply(AttLayout layout, IReadOnlyDictionary<int, AttColumn> roles)
    {
        foreach (var c in layout.Columns)
        {
            if (!roles.TryGetValue(c.Index, out var role)) continue;
            if (c.Role != role) { c.Role = role; c.Basis = "chosen"; }
        }
        layout.Format = layout.IndexOf(AttColumn.ClockIn) is not null || layout.IndexOf(AttColumn.ClockOut) is not null ? "PAIRED" : "PUNCH";
    }

    private static int FindHeaderRow(IReadOnlyList<string[]> rows)
    {
        var best = -1;
        var bestScore = 1;
        for (var r = 0; r < Math.Min(rows.Count, 25); r++)
        {
            var row = rows[r];
            var score = row.Count(c => !string.IsNullOrWhiteSpace(c) && TitleRole(c) is not null && !LooksLikeValue(Normalize(c)));
            if (score > bestScore) { best = r; bestScore = score; }
        }
        return best;
    }

    private static bool LooksLikeValue(string v) =>
        IsTime(v) || TryDate(v, true, out _) || TryDateTime(v, true, out _) || IsNumber(v);

    private static AttColumn? TitleRole(string? header)
    {
        if (string.IsNullOrWhiteSpace(header)) return null;
        var h = " " + Regex.Replace(header.ToLowerInvariant().Replace('_', ' '), @"\s+", " ").Trim() + " ";
        foreach (var (role, words) in Titles)
        {
            foreach (var w in words)
            {
                // short words ("id", "in", "day") must stand alone; longer ones may be part of the title
                if (w.Length <= 3 ? Regex.IsMatch(h, @"(^|[\s\(\)\[\]/:.#-])" + Regex.Escape(w) + @"($|[\s\(\)\[\]/:.#-])")
                                  : h.Contains(w, StringComparison.Ordinal))
                {
                    return role;
                }
            }
        }
        return null;
    }

    /// <summary>A role suits what the column holds (an empty column takes any role from its title).</summary>
    private static bool Fits(AttColumn role, string kind, bool digitsOnly) => kind == "empty" || role switch
    {
        // whole numbers between 20000 and 80000 also read as Excel dates: the title decides
        AttColumn.EmployeeId => kind is "id" or "number" or "text" || digitsOnly,
        AttColumn.Name => kind is "text",
        AttColumn.Date => kind is "date" or "datetime",
        AttColumn.DateTime => kind is "datetime",
        AttColumn.Time => kind is "time" or "datetime",
        AttColumn.ClockIn or AttColumn.ClockOut => kind is "time" or "datetime",
        AttColumn.Weekday => kind is "weekday" or "text",
        AttColumn.State => kind is "state" or "text",
        AttColumn.Total => true,
        _ => kind is "text"
    };

    private static string Kind(IReadOnlyList<string> values, int rows)
    {
        if (values.Count == 0) return "empty";
        int Count(Func<string, bool> test) => values.Count(test);
        var need = Math.Max(1, (int)Math.Ceiling(values.Count * 0.8));
        if (Count(v => DayNames.Contains(v.ToLowerInvariant())) >= need) return "weekday";
        if (Count(IsTime) >= need) return "time";
        if (Count(v => TryDateTime(v, true, out _)) >= need) return "datetime";
        if (Count(v => TryDate(v, true, out _)) >= need) return "date";
        if (Count(v => InWords.Contains(v.ToLowerInvariant()) || OutWords.Contains(v.ToLowerInvariant())) >= need
            && values.Distinct(StringComparer.OrdinalIgnoreCase).Count() <= 6 && !values.All(v => v is "0" or "1")) return "state";
        if (Count(v => Regex.IsMatch(v, @"^[A-Za-z]{0,4}-?\d{1,12}$")) >= need)
        {
            // an ID repeats (one row per day) or is a whole number that is not a fraction / amount
            return values.All(v => !v.Contains('.')) ? "id" : "number";
        }
        if (Count(IsNumber) >= need) return "number";
        if (Count(v => v.Any(char.IsLetter)) >= need) return "text";
        return "mixed";
    }

    private static bool DayFirst(IEnumerable<string> values)
    {
        foreach (var v in values)
        {
            var m = Regex.Match(v, @"^(\d{1,2})[/.-](\d{1,2})[/.-](\d{2,4})");
            if (!m.Success) continue;
            var a = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            var b = int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
            if (a > 12) return true;
            if (b > 12) return false;
        }
        return true;   // Kuwait: day first
    }

    // ------------------------------------------------------------------ reading

    /// <summary>The employees' days, read with the layout.</summary>
    public static AttParseResult Parse(IReadOnlyList<string[]> rows, AttLayout layout)
    {
        var result = new AttParseResult();
        var idCol = layout.IndexOf(AttColumn.EmployeeId);
        if (idCol is null) return result;
        var nameCol = layout.IndexOf(AttColumn.Name);
        var dateCol = layout.IndexOf(AttColumn.Date);
        var inCol = layout.IndexOf(AttColumn.ClockIn);
        var outCol = layout.IndexOf(AttColumn.ClockOut);
        var dtCol = layout.IndexOf(AttColumn.DateTime);
        var timeCol = layout.IndexOf(AttColumn.Time);
        var stateCol = layout.IndexOf(AttColumn.State);
        var dayFirst = layout.DayFirst;
        var days = new Dictionary<(string, DateOnly), AttParsedDay>();
        var punches = new Dictionary<(string, DateOnly), List<(DateTime At, int State)>>();

        string Cell(string[] row, int? col) => col is { } c && c < row.Length ? Normalize(row[c]) : string.Empty;
        void Skip(int rowNumber, string why)
        {
            result.Skipped++;
            if (result.SkipReasons.Count < 15) result.SkipReasons.Add($"Row {rowNumber}: {why}");
        }

        for (var r = layout.HeaderRow + 1; r < rows.Count; r++)
        {
            var row = rows[r];
            if (row.All(string.IsNullOrWhiteSpace)) continue;
            result.DataRows++;
            var id = CleanId(Cell(row, idCol));
            if (id.Length == 0) { Skip(r + 1, "no employee number"); continue; }
            if (!Regex.IsMatch(id, @"\d") && id.Length > 12) { Skip(r + 1, "not an employee row (" + id + ")"); continue; }
            var name = nameCol is null ? null : Cell(row, nameCol);

            if (layout.Format == "PAIRED")
            {
                var inText = Cell(row, inCol);
                var outText = Cell(row, outCol);
                DateOnly date;
                if (dateCol is not null && TryDate(Cell(row, dateCol), dayFirst, out var d)) date = d;
                else if (TryDateTime(inText, dayFirst, out var din)) date = DateOnly.FromDateTime(din);
                else if (TryDateTime(outText, dayFirst, out var dout)) date = DateOnly.FromDateTime(dout);
                else { Skip(r + 1, "no date"); continue; }

                var clockIn = At(date, inText, dayFirst);
                var clockOut = At(date, outText, dayFirst);
                if (clockIn is null && clockOut is null) { Skip(r + 1, "no clock in or out (absent)"); continue; }
                // a shift past midnight: the clock out is the next day
                if (clockIn is { } ci && clockOut is { } co && co <= ci) clockOut = co.AddDays(1);

                var key = (id, date);
                if (days.TryGetValue(key, out var day))
                {
                    if (clockIn is { } i2 && (day.ClockIn is null || i2 < day.ClockIn)) day.ClockIn = i2;
                    if (clockOut is { } o2 && (day.ClockOut is null || o2 > day.ClockOut)) day.ClockOut = o2;
                    day.Punches += (clockIn is null ? 0 : 1) + (clockOut is null ? 0 : 1);
                }
                else
                {
                    days[key] = new AttParsedDay
                    {
                        DeviceId = id, Name = name, Date = date, ClockIn = clockIn, ClockOut = clockOut,
                        Punches = (clockIn is null ? 0 : 1) + (clockOut is null ? 0 : 1), Row = r + 1
                    };
                }
            }
            else
            {
                DateTime at;
                if (dtCol is not null && TryDateTime(Cell(row, dtCol), dayFirst, out var dt)) at = dt;
                else if (dateCol is not null && TryDate(Cell(row, dateCol), dayFirst, out var d2) && At(d2, Cell(row, timeCol), dayFirst) is { } t2) at = t2;
                else { Skip(r + 1, "no punch date / time"); continue; }
                var stateText = Cell(row, stateCol).ToLowerInvariant();
                var state = InWords.Contains(stateText) ? 1 : OutWords.Contains(stateText) ? 2 : 0;
                var key = (id, DateOnly.FromDateTime(at));
                if (!punches.TryGetValue(key, out var list)) { punches[key] = list = []; }
                list.Add((at, state));
                if (!days.ContainsKey(key)) days[key] = new AttParsedDay { DeviceId = id, Name = name, Date = key.Item2, Row = r + 1 };
            }
        }

        // punches: the first is the clock in, the last the clock out (a check-in / out state is used when the device gives it)
        foreach (var (key, list) in punches)
        {
            var day = days[key];
            var ordered = list.OrderBy(p => p.At).ToList();
            var ins = ordered.Where(p => p.State == 1).ToList();
            var outs = ordered.Where(p => p.State == 2).ToList();
            day.ClockIn = ins.Count > 0 ? ins[0].At : ordered[0].At;
            day.ClockOut = outs.Count > 0 ? outs[^1].At : ordered.Count > 1 ? ordered[^1].At : null;
            if (day.ClockOut is { } o && day.ClockIn is { } i && o <= i) day.ClockOut = null;
            day.Punches = ordered.Count;
        }

        result.Days.AddRange(days.Values.OrderBy(d => d.DeviceId, StringComparer.Ordinal).ThenBy(d => d.Date));
        return result;
    }

    // ------------------------------------------------------------------ values

    /// <summary>Arabic-Indic digits to 0-9, trimmed.</summary>
    public static string Normalize(string? value)
    {
        if (string.IsNullOrWhiteSpace(value)) return string.Empty;
        var sb = new StringBuilder(value.Length);
        foreach (var ch in value.Trim())
        {
            sb.Append(ch switch
            {
                >= '٠' and <= '٩' => (char)('0' + (ch - '٠')),
                >= '۰' and <= '۹' => (char)('0' + (ch - '۰')),
                '٫' => '.',
                _ => ch
            });
        }
        return sb.ToString();
    }

    /// <summary>"1003", "1003.0", "001003" -> "1003" (an ID is compared without leading zeros).</summary>
    public static string CleanId(string value)
    {
        var v = Normalize(value);
        if (Regex.IsMatch(v, @"^\d+\.0+$")) v = v[..v.IndexOf('.')];
        return v;
    }

    public static string IdKey(string? value)
    {
        var v = CleanId(value ?? string.Empty).ToUpperInvariant();
        return Regex.IsMatch(v, @"^\d+$") ? v.TrimStart('0').PadLeft(1, '0') : v;
    }

    private static bool IsNumber(string v) => double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out _);

    private static bool IsTime(string v) =>
        TimeRx().IsMatch(v) || (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) && d is > 0 and < 1 && v.Contains('.'));

    private static TimeSpan? ParseTime(string v)
    {
        var m = TimeRx().Match(v);
        if (m.Success)
        {
            var h = int.Parse(m.Groups[1].Value, CultureInfo.InvariantCulture);
            var min = int.Parse(m.Groups[2].Value, CultureInfo.InvariantCulture);
            var s = m.Groups[3].Success ? int.Parse(m.Groups[3].Value, CultureInfo.InvariantCulture) : 0;
            var ampm = m.Groups[4].Value.ToLowerInvariant();
            if (ampm is "pm" or "p.m." or "م" && h < 12) h += 12;
            if (ampm is "am" or "a.m." or "ص" && h == 12) h = 0;
            if (h > 23 || min > 59 || s > 59) return null;
            return new TimeSpan(h, min, s);
        }
        if (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var d) && d is >= 0 and < 1)
        {
            return TimeSpan.FromMinutes(Math.Round(d * 1440));
        }
        return null;
    }

    private static readonly string[] DateFormatsDayFirst =
        ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "dd/MM/yyyy", "d/M/yyyy", "dd-MM-yyyy", "d-M-yyyy", "dd.MM.yyyy", "d.M.yyyy", "dd/MM/yy", "d/M/yy",
         "dd-MMM-yyyy", "d-MMM-yyyy", "dd MMM yyyy", "d MMM yyyy", "dd-MMM-yy", "MMM d, yyyy", "MMMM d, yyyy", "yyyyMMdd"];
    private static readonly string[] DateFormatsMonthFirst =
        ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "MM/dd/yyyy", "M/d/yyyy", "MM-dd-yyyy", "M-d-yyyy", "MM.dd.yyyy", "M.d.yyyy", "MM/dd/yy", "M/d/yy",
         "dd-MMM-yyyy", "d-MMM-yyyy", "dd MMM yyyy", "d MMM yyyy", "dd-MMM-yy", "MMM d, yyyy", "MMMM d, yyyy", "yyyyMMdd"];

    public static bool TryDate(string v, bool dayFirst, out DateOnly date)
    {
        date = default;
        if (string.IsNullOrWhiteSpace(v)) return false;
        // an Excel date (a whole day number)
        if (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var serial))
        {
            if (serial is > 20000 and < 80000 && Math.Abs(serial - Math.Floor(serial)) < 0.0000001)
            {
                date = DateOnly.FromDateTime(System.DateTime.FromOADate(serial));
                return true;
            }
            if (v.Length != 8) return false;
        }
        var text = v.Trim();
        // "2026-09-25 00:00:00" (a date with a zero time) is a date
        if (text.Length > 10 && Regex.IsMatch(text, @"\s0?0:00(:00)?$")) text = Regex.Replace(text, @"\s0?0:00(:00)?$", "");
        return DateOnly.TryParseExact(text, dayFirst ? DateFormatsDayFirst : DateFormatsMonthFirst, CultureInfo.InvariantCulture, DateTimeStyles.AllowWhiteSpaces, out date);
    }

    public static bool TryDateTime(string v, bool dayFirst, out DateTime value)
    {
        value = default;
        if (string.IsNullOrWhiteSpace(v)) return false;
        if (double.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out var serial))
        {
            if (serial is > 20000 and < 80000 && serial - Math.Floor(serial) > 0.0000001)
            {
                value = System.DateTime.FromOADate(serial);
                value = new DateTime(value.Year, value.Month, value.Day, value.Hour, value.Minute, 0);
                return true;
            }
            return false;
        }
        var dm = DatePartRx().Match(v);
        if (!dm.Success) return false;
        var rest = (v[..dm.Index] + " " + v[(dm.Index + dm.Length)..]).Replace("T", " ").Trim();
        if (rest.Length == 0) return false;
        if (!TryDate(dm.Value, dayFirst, out var d)) return false;
        if (ParseTime(Regex.Replace(rest, @"\s+", " ").Trim()) is not { } t) return false;
        value = d.ToDateTime(TimeOnly.MinValue).Add(t);
        return true;
    }

    /// <summary>A clock time on the date (a full date-time cell keeps its own date).</summary>
    private static DateTime? At(DateOnly date, string v, bool dayFirst)
    {
        if (string.IsNullOrWhiteSpace(v) || v is "-" or "--" or "—") return null;
        if (TryDateTime(v, dayFirst, out var dt)) return dt;
        return ParseTime(v) is { } t ? date.ToDateTime(TimeOnly.MinValue).Add(t) : null;
    }
}
