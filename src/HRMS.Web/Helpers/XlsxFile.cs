using System.Globalization;
using System.IO.Compression;
using System.Security;
using System.Text;
using System.Xml.Linq;

namespace HRMS.Web.Helpers;

/// <summary>
/// A minimal Excel (.xlsx) writer and reader for exports, templates and
/// imports - one sheet, text and numbers only - so no third-party package is
/// needed. CSV files can be read as well (<see cref="ReadCsv"/>).
/// </summary>
public static class XlsxFile
{
    public const string ContentType = "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet";

    private static readonly XNamespace Main = "http://schemas.openxmlformats.org/spreadsheetml/2006/main";
    private static readonly XNamespace Rel = "http://schemas.openxmlformats.org/officeDocument/2006/relationships";
    private static readonly XNamespace PkgRel = "http://schemas.openxmlformats.org/package/2006/relationships";

    /// <summary>
    /// Writes one sheet. Cell values: decimal/int/double are written as numbers
    /// (decimals with 3 places), everything else as text. The first row is bold.
    /// </summary>
    public static byte[] Write(string sheetName, IReadOnlyList<string> headers, IEnumerable<IReadOnlyList<object?>> rows,
                               IReadOnlyList<double>? widths = null, bool rightToLeft = false)
    {
        var sheet = new StringBuilder();
        sheet.Append("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>");
        sheet.Append("<worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">");
        sheet.Append("<sheetViews><sheetView workbookViewId=\"0\"").Append(rightToLeft ? " rightToLeft=\"1\"" : "")
             .Append("><pane ySplit=\"1\" topLeftCell=\"A2\" activePane=\"bottomLeft\" state=\"frozen\"/></sheetView></sheetViews>");
        if (widths is { Count: > 0 })
        {
            sheet.Append("<cols>");
            for (var i = 0; i < widths.Count; i++)
            {
                sheet.Append(CultureInfo.InvariantCulture, $"<col min=\"{i + 1}\" max=\"{i + 1}\" width=\"{widths[i]}\" customWidth=\"1\"/>");
            }
            sheet.Append("</cols>");
        }
        sheet.Append("<sheetData>");
        var r = 1;
        AppendRow(sheet, r++, headers.Cast<object?>().ToList(), header: true);
        foreach (var row in rows)
        {
            AppendRow(sheet, r++, row, header: false);
        }
        sheet.Append("</sheetData></worksheet>");

        using var ms = new MemoryStream();
        using (var zip = new ZipArchive(ms, ZipArchiveMode.Create, leaveOpen: true))
        {
            Add(zip, "[Content_Types].xml",
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">" +
                "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>" +
                "<Default Extension=\"xml\" ContentType=\"application/xml\"/>" +
                "<Override PartName=\"/xl/workbook.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml\"/>" +
                "<Override PartName=\"/xl/worksheets/sheet1.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml\"/>" +
                "<Override PartName=\"/xl/styles.xml\" ContentType=\"application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml\"/>" +
                "</Types>");
            Add(zip, "_rels/.rels",
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" Target=\"xl/workbook.xml\"/>" +
                "</Relationships>");
            Add(zip, "xl/workbook.xml",
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\">" +
                $"<sheets><sheet name=\"{Escape(SheetName(sheetName))}\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>");
            Add(zip, "xl/_rels/workbook.xml.rels",
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">" +
                "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/>" +
                "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles\" Target=\"styles.xml\"/>" +
                "</Relationships>");
            Add(zip, "xl/styles.xml",
                "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>" +
                "<styleSheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\">" +
                "<numFmts count=\"1\"><numFmt numFmtId=\"164\" formatCode=\"#,##0.000\"/></numFmts>" +
                "<fonts count=\"2\"><font><sz val=\"11\"/><name val=\"Calibri\"/></font><font><b/><sz val=\"11\"/><name val=\"Calibri\"/></font></fonts>" +
                "<fills count=\"2\"><fill><patternFill patternType=\"none\"/></fill><fill><patternFill patternType=\"gray125\"/></fill></fills>" +
                "<borders count=\"1\"><border><left/><right/><top/><bottom/><diagonal/></border></borders>" +
                "<cellStyleXfs count=\"1\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\"/></cellStyleXfs>" +
                "<cellXfs count=\"3\"><xf numFmtId=\"0\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\"/>" +
                "<xf numFmtId=\"0\" fontId=\"1\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyFont=\"1\"/>" +
                "<xf numFmtId=\"164\" fontId=\"0\" fillId=\"0\" borderId=\"0\" xfId=\"0\" applyNumberFormat=\"1\"/></cellXfs>" +
                "</styleSheet>");
            Add(zip, "xl/worksheets/sheet1.xml", sheet.ToString());
        }
        return ms.ToArray();
    }

    /// <summary>
    /// Reads the first sheet as rows of text (empty cells as ""). Numbers come back in invariant format.
    /// Item i is sheet row i + 1: blank or missing rows are kept as empty arrays so row numbers can be reported.
    /// </summary>
    public static List<string[]> Read(Stream stream)
    {
        using var zip = new ZipArchive(stream, ZipArchiveMode.Read, leaveOpen: true);

        var shared = new List<string>();
        var sst = zip.GetEntry("xl/sharedStrings.xml");
        if (sst is not null)
        {
            using var s = sst.Open();
            var doc = XDocument.Load(s);
            foreach (var si in doc.Root!.Elements(Main + "si"))
            {
                shared.Add(string.Concat(si.Descendants(Main + "t").Select(t => t.Value)));
            }
        }

        var sheetPath = FirstSheetPath(zip) ?? "xl/worksheets/sheet1.xml";
        var entry = zip.GetEntry(sheetPath) ?? throw new InvalidDataException("The workbook has no sheet.");
        using var stream2 = entry.Open();
        var sheet = XDocument.Load(stream2);

        var rows = new List<string[]>();
        foreach (var row in sheet.Descendants(Main + "row"))
        {
            if (int.TryParse((string?)row.Attribute("r"), NumberStyles.Integer, CultureInfo.InvariantCulture, out var rowNumber))
            {
                while (rows.Count < rowNumber - 1) rows.Add([]);
            }
            var cells = new SortedDictionary<int, string>();
            var next = 0;
            foreach (var c in row.Elements(Main + "c"))
            {
                var reference = (string?)c.Attribute("r");
                var col = reference is null ? next : ColumnIndex(reference);
                next = col + 1;
                var type = (string?)c.Attribute("t");
                var v = c.Element(Main + "v")?.Value;
                string text = type switch
                {
                    "s" when int.TryParse(v, NumberStyles.Integer, CultureInfo.InvariantCulture, out var i) && i >= 0 && i < shared.Count => shared[i],
                    "inlineStr" => string.Concat(c.Descendants(Main + "t").Select(t => t.Value)),
                    "b" => v == "1" ? "TRUE" : "FALSE",
                    _ => v ?? string.Empty
                };
                cells[col] = text.Trim();
            }
            var width = cells.Count == 0 ? 0 : cells.Keys.Max() + 1;
            var arr = new string[width];
            for (var i = 0; i < width; i++) arr[i] = cells.TryGetValue(i, out var t) ? t : string.Empty;
            rows.Add(arr);
        }
        while (rows.Count > 0 && rows[^1].All(string.IsNullOrEmpty)) rows.RemoveAt(rows.Count - 1);
        return rows;
    }

    /// <summary>
    /// Reads a comma- or semicolon-separated file (UTF-8, quotes allowed). Item i is line i + 1.
    /// A semicolon file uses the comma as decimal mark (<paramref name="decimalComma"/>).
    /// </summary>
    public static List<string[]> ReadCsv(Stream stream, out bool decimalComma)
    {
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);
        var text = reader.ReadToEnd();
        var firstLine = text.Split('\n', 2)[0];
        var sep = firstLine.Count(ch => ch == ';') > firstLine.Count(ch => ch == ',') ? ';' : ',';
        decimalComma = sep == ';';

        var rows = new List<string[]>();
        var row = new List<string>();
        var cell = new StringBuilder();
        var quoted = false;
        for (var i = 0; i < text.Length; i++)
        {
            var ch = text[i];
            if (quoted)
            {
                if (ch == '"' && i + 1 < text.Length && text[i + 1] == '"') { cell.Append('"'); i++; }
                else if (ch == '"') quoted = false;
                else cell.Append(ch);
                continue;
            }
            if (ch == '"') quoted = true;
            else if (ch == sep) { row.Add(cell.ToString().Trim()); cell.Clear(); }
            else if (ch == '\n')
            {
                row.Add(cell.ToString().Trim()); cell.Clear();
                rows.Add(row.ToArray());
                row = new List<string>();
            }
            else if (ch != '\r') cell.Append(ch);
        }
        row.Add(cell.ToString().Trim());
        if (row.Any(x => x.Length > 0)) rows.Add(row.ToArray());
        return rows;
    }

    /// <summary>"yyyy-MM" from a cell that holds a month as text ("2026-11", "11/2026") or an Excel date serial.</summary>
    public static string MonthText(string? cell)
    {
        if (string.IsNullOrWhiteSpace(cell)) return string.Empty;
        var value = cell.Trim();
        if (double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out var serial) && serial > 20000 && serial < 80000)
        {
            return DateTime.FromOADate(serial).ToString("yyyy-MM", CultureInfo.InvariantCulture);
        }
        string[] formats = ["yyyy-MM", "yyyy-M", "yyyy-MM-dd", "MM/yyyy", "M/yyyy", "dd/MM/yyyy", "MMM yyyy", "MMMM yyyy", "MMM-yy", "yyyy/MM"];
        return DateTime.TryParseExact(value, formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
            ? d.ToString("yyyy-MM", CultureInfo.InvariantCulture)
            : value;
    }

    // ------------------------------------------------------------ helpers

    private static void AppendRow(StringBuilder sb, int r, IReadOnlyList<object?> values, bool header)
    {
        sb.Append(CultureInfo.InvariantCulture, $"<row r=\"{r}\">");
        for (var c = 0; c < values.Count; c++)
        {
            var reference = ColumnName(c) + r.ToString(CultureInfo.InvariantCulture);
            switch (values[c])
            {
                case null:
                    break;
                case decimal d:
                    sb.Append(CultureInfo.InvariantCulture, $"<c r=\"{reference}\" s=\"2\"><v>{d.ToString(CultureInfo.InvariantCulture)}</v></c>");
                    break;
                case int or long or short:
                    sb.Append(CultureInfo.InvariantCulture, $"<c r=\"{reference}\"><v>{Convert.ToString(values[c], CultureInfo.InvariantCulture)}</v></c>");
                    break;
                case double db:
                    sb.Append(CultureInfo.InvariantCulture, $"<c r=\"{reference}\"><v>{db.ToString("R", CultureInfo.InvariantCulture)}</v></c>");
                    break;
                default:
                    var text = Convert.ToString(values[c], CultureInfo.InvariantCulture) ?? string.Empty;
                    sb.Append(CultureInfo.InvariantCulture, $"<c r=\"{reference}\" t=\"inlineStr\"{(header ? " s=\"1\"" : "")}><is><t xml:space=\"preserve\">{Escape(Clean(text))}</t></is></c>");
                    break;
            }
        }
        sb.Append("</row>");
    }

    private static string? FirstSheetPath(ZipArchive zip)
    {
        var wb = zip.GetEntry("xl/workbook.xml");
        var rels = zip.GetEntry("xl/_rels/workbook.xml.rels");
        if (wb is null || rels is null) return null;
        string? id;
        using (var s = wb.Open())
        {
            id = (string?)XDocument.Load(s).Descendants(Main + "sheet").FirstOrDefault()?.Attribute(Rel + "id");
        }
        if (id is null) return null;
        using var r = rels.Open();
        var target = (string?)XDocument.Load(r).Descendants(PkgRel + "Relationship")
            .FirstOrDefault(x => (string?)x.Attribute("Id") == id)?.Attribute("Target");
        if (target is null) return null;
        return target.StartsWith('/') ? target.TrimStart('/') : "xl/" + target;
    }

    private static int ColumnIndex(string reference)
    {
        var n = 0;
        foreach (var ch in reference)
        {
            if (!char.IsLetter(ch)) break;
            n = n * 26 + (char.ToUpperInvariant(ch) - 'A' + 1);
        }
        return Math.Max(0, n - 1);
    }

    private static string ColumnName(int index)
    {
        var name = string.Empty;
        index++;
        while (index > 0)
        {
            var m = (index - 1) % 26;
            name = (char)('A' + m) + name;
            index = (index - 1) / 26;
        }
        return name;
    }

    private static void Add(ZipArchive zip, string path, string content)
    {
        var entry = zip.CreateEntry(path, CompressionLevel.Fastest);
        using var w = new StreamWriter(entry.Open(), new UTF8Encoding(false));
        w.Write(content);
    }

    private static string SheetName(string name)
    {
        var clean = new string(name.Where(ch => ch is not ('\\' or '/' or '?' or '*' or '[' or ']' or ':')).ToArray());
        return clean.Length switch { 0 => "Sheet1", > 31 => clean[..31], _ => clean };
    }

    /// <summary>Inline text cells are never evaluated as formulas; only control characters are removed (invalid in XML).</summary>
    private static string Clean(string text) => new(text.Where(ch => ch == '\t' || ch == '\n' || ch >= ' ').ToArray());

    private static string Escape(string text) => SecurityElement.Escape(text) ?? string.Empty;
}
