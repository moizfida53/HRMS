#nullable disable
//==============================================================================
//  Areas/POS/Models/DashboardModels.cs
//------------------------------------------------------------------------------
//  The two shapes the Dashboard passes between the controller and its views.
//  They came from the Call Centre project as CoffeeShop.Models types; there is
//  nothing in them worth inventing differently, so they are reproduced here
//  under this project's namespace.
//
//  Add to the .csproj:
//      <Compile Include="Areas\POS\Models\DashboardModels.cs" />
//==============================================================================

using System;
using System.Web;
using System.Collections.Generic;
using System.Globalization;
using System.Linq;
using System.Text;
namespace HRMS.Web.Areas.POS.Models
{
    /// <summary>
    /// One cell of the sales pivot: a branch, a day, a measure and its value.
    /// SalesReportDetailsView.cshtml is typed on IEnumerable of this.
    /// </summary>
    public class PivotTotalSalesData
    {
        public string BranchName { get; set; }
        public string OrderSales { get; set; }        // the measure name  (keyName)
        public decimal OrderSalesValues { get; set; } // the measure value (KeyValue)
        public string InvoiceDate { get; set; }       // already formatted by SQL
    }

    /// <summary>
    /// Turns the flat (BranchName, keyName, KeyValue, InvoiceDate) rows that
    /// sp_DashbordSalesData's SalesPivot result set produces into the grid the
    /// "Sales Data" drill-down shows: one row per invoice date, one column
    /// group per branch plus a grand-total group, three measures under each
    /// group (Sales, Orders, Avg Per cheque), and a grand-total row at the
    /// bottom.
    ///
    /// SalesReportDetailsView.cshtml used to call `Model.ReportWithPivot(...)`
    /// - an extension method that does not exist anywhere in this codebase
    /// (ported from the Call Centre project's UI library, which was never
    /// brought over). That view could not have rendered; this replaces it with
    /// a small purpose-built table builder instead of chasing down and adding
    /// a third-party pivot library for three columns.
    ///
    /// The class name matches what download_table_as_csv() in Dashboard.js
    /// already expects to find: a table with class "totalSalesPivotTable",
    /// a two-row &lt;thead&gt; (branch name spanning its three measures via
    /// colspan, InvoiceDate spanning both header rows via rowspan), and a
    /// &lt;tbody&gt; the export code walks by colSpan/rowSpan. That JS was
    /// clearly written against this exact shape; this builder is what was
    /// missing to produce it.
    /// </summary>
    public static class SalesPivotBuilder
    {
        // Order fixed rather than discovered from the data, so the three
        // sub-columns always read Sales / Orders / Avg Per cheque left to
        // right regardless of which measure the query happens to emit first.
        private static readonly string[] Measures = { "Sales", "Orders", "AvgPerCheque" };

        private static readonly Dictionary<string, string> MeasureLabels =
            new Dictionary<string, string>
        {
            { "Sales",        "Sales" },
            { "Orders",       "Orders" },
            { "AvgPerCheque", "Avg Per cheque" }
        };

        public static string Build(IEnumerable<PivotTotalSalesData> rows)
        {
            var list = (rows ?? Enumerable.Empty<PivotTotalSalesData>()).ToList();
            if (list.Count == 0)
                return "<p class=\"pos-muted\">No data for the selected filters.</p>";

            var branches = list.Select(r => r.BranchName)
                                .Distinct()
                                .OrderBy(b => b, StringComparer.OrdinalIgnoreCase)
                                .ToList();

            // InvoiceDate arrives from SQL as yyyy-MM-dd (see the SalesPivot
            // result set), which sorts correctly as plain text too - no need
            // to parse before ordering.
            var dates = list.Select(r => r.InvoiceDate).Distinct().OrderBy(d => d, StringComparer.Ordinal).ToList();

            // cell[date][branch][measure] = value. The Total column is not
            // stored here - colTotal() below sums the real branches on demand,
            // so the query does not need to know a "Total" branch exists.
            var cell = new Dictionary<string, Dictionary<string, Dictionary<string, decimal>>>();
            foreach (var r in list)
            {
                Dictionary<string, Dictionary<string, decimal>> byBranch;
                if (!cell.TryGetValue(r.InvoiceDate, out byBranch))
                    cell[r.InvoiceDate] = byBranch = new Dictionary<string, Dictionary<string, decimal>>();

                Dictionary<string, decimal> byMeasure;
                if (!byBranch.TryGetValue(r.BranchName, out byMeasure))
                    byBranch[r.BranchName] = byMeasure = new Dictionary<string, decimal>();

                byMeasure[r.OrderSales] = r.OrderSalesValues;
            }

            Func<string, string, string, decimal> val = (date, branch, measure) =>
            {
                Dictionary<string, Dictionary<string, decimal>> byBranch;
                Dictionary<string, decimal> byMeasure;
                decimal v;
                if (cell.TryGetValue(date, out byBranch)
                    && byBranch.TryGetValue(branch, out byMeasure)
                    && byMeasure.TryGetValue(measure, out v))
                    return v;
                return 0m;
            };

            // The Total column is a straight sum across branches for every
            // measure, Avg Per cheque included. That makes its Avg Per cheque
            // the sum of the branches' averages rather than a recomputed
            // (total sales / total orders) - the same thing the grand-total
            // row below does, kept consistent on purpose rather than "fixed"
            // in one direction and not the other.
            Func<string, string, decimal> colTotal = (date, measure) =>
                branches.Sum(b => val(date, b, measure));

            var sb = new StringBuilder();
            sb.Append("<table class=\"table table-hover totalSalesPivotTable\">");

            // ---- header ----
            sb.Append("<thead><tr><th rowspan=\"2\">InvoiceDate</th>");
            foreach (var b in branches)
                sb.Append("<th colspan=\"3\">").Append(HttpUtility.HtmlEncode(b)).Append("</th>");
            sb.Append("<th colspan=\"3\" class=\"col-total\">Total</th></tr><tr>");
            foreach (var b in branches)
                foreach (var m in Measures)
                    sb.Append("<th>").Append(MeasureLabels[m]).Append("</th>");
            foreach (var m in Measures)
                sb.Append("<th class=\"col-total\">").Append(MeasureLabels[m]).Append("</th>");
            sb.Append("</tr></thead>");

            // ---- body: one row per invoice date ----
            sb.Append("<tbody>");
            foreach (var d in dates)
            {
                sb.Append("<tr><td>").Append(FormatDate(d)).Append("</td>");
                foreach (var b in branches)
                    foreach (var m in Measures)
                        sb.Append("<td>").Append(Fmt(val(d, b, m), m)).Append("</td>");
                foreach (var m in Measures)
                    sb.Append("<td class=\"col-total\">").Append(Fmt(colTotal(d, m), m)).Append("</td>");
                sb.Append("</tr>");
            }

            // ---- grand-total row ----
            sb.Append("<tr class=\"row-total\"><td>Total</td>");
            foreach (var b in branches)
                foreach (var m in Measures)
                {
                    decimal sum = dates.Sum(d => val(d, b, m));
                    sb.Append("<td>").Append(Fmt(sum, m)).Append("</td>");
                }
            foreach (var m in Measures)
            {
                decimal grand = dates.Sum(d => colTotal(d, m));
                sb.Append("<td class=\"col-total\">").Append(Fmt(grand, m)).Append("</td>");
            }
            sb.Append("</tr></tbody></table>");

            return sb.ToString();
        }

        // Orders is a count - no decimal places belong on it even though it is
        // carried as decimal end to end (the SQL casts every measure the same
        // way so a mixed-type result set does not throw). Sales and Avg Per
        // cheque are money, three places, matching every other figure on this
        // dashboard.
        private static string Fmt(decimal v, string measure)
        {
            return measure == "Orders"
                ? v.ToString("0", CultureInfo.InvariantCulture)
                : v.ToString("0.000", CultureInfo.InvariantCulture);
        }

        private static string FormatDate(string isoDate)
        {
            DateTime dt;
            return DateTime.TryParseExact(isoDate, "yyyy-MM-dd", CultureInfo.InvariantCulture,
                                           DateTimeStyles.None, out dt)
                ? dt.ToString("dd-MMM-yy", CultureInfo.InvariantCulture)
                : HttpUtility.HtmlEncode(isoDate);
        }
    }

    /// <summary>
    /// One operating day for the date-range dropdown.
    ///
    /// EndDateForValProperty is named to match what Dashboard.js reads when it
    /// builds the option value. The original class called it EndDateVal and the
    /// JS asked for EndDateForValProperty, so every option came out with
    /// value="undefined" - and the "operating days" filter silently did
    /// nothing. Renaming the property here fixes it without touching the JS.
    /// </summary>
    public class tmpclsEndDate
    {
        public string StartDateName { get; set; }

        // A STRING, not a DateTime, and formatted yyyy-MM-dd.
        //
        // This value becomes the <option value>, is posted back as @EndDates,
        // and is read by TRY_CAST(value AS DATE) in sp_DashbordSalesData. An
        // MVC JsonResult serialises a DateTime as "/Date(1755...)/", which
        // TRY_CAST cannot read - so the operating-day filter would return no
        // rows while looking like it had been applied.
        public string EndDateForValProperty { get; set; }
    }
}
