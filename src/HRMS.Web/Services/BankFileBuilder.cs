using System.Globalization;
using System.Text;
using HRMS.Domain.Payroll;

namespace HRMS.Web.Services;

/// <summary>
/// Builds the text of a salary (WPS) file from a bank format (Payroll Settings >
/// Bank Formats): the fields in order, CSV / delimited text (values with the
/// delimiter or a quote are quoted) or fixed width (padded and cut to the width),
/// with an optional header row (the field names) and trailer row (record count
/// and total). Amounts have three decimals, dates are yyyy-MM-dd.
/// </summary>
public static class BankFileBuilder
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public sealed record Result(string FileName, string Content, decimal Total, int Count);

    public static Result Build(BankFileFormat format, CompanyBankAccount account, IReadOnlyList<BankFileLine> lines,
                               DateTime valueDate, DateTime runMonth)
    {
        var fixedWidth = format.FileType == "FIXED";
        var delimiter = fixedWidth ? string.Empty : string.IsNullOrEmpty(format.Delimiter) ? "," : format.Delimiter;
        var fields = format.Fields;
        var rows = new List<string>(lines.Count + 2);

        if (format.HasHeader)
        {
            rows.Add(string.Join(delimiter, fields.Select(f => Cell(f.FieldName, f, fixedWidth, delimiter, isAmount: false))));
        }

        foreach (var line in lines)
        {
            rows.Add(string.Join(delimiter, fields.Select(f =>
                Cell(Value(f, line, account, valueDate, runMonth), f, fixedWidth, delimiter, IsAmount(f.SourceCode)))));
        }

        var total = lines.Sum(l => l.NetPay);
        if (format.HasTrailer)
        {
            rows.Add(fixedWidth
                ? "T" + lines.Count.ToString(Inv).PadLeft(6, '0') + Amount(total).Replace(".", string.Empty, StringComparison.Ordinal).PadLeft(15, '0')
                : string.Join(delimiter, "TOTAL", lines.Count.ToString(Inv), Amount(total)));
        }

        return new Result(FileName(format, account, valueDate, runMonth), string.Join("\r\n", rows) + "\r\n", total, lines.Count);
    }

    private static bool IsAmount(string source) => source is "NET_AMOUNT" or "BASIC_AMOUNT" or "ALLOWANCES" or "DEDUCTIONS";

    private static string Amount(decimal value) => value.ToString("0.000", Inv);

    private static string? Value(BankFileField f, BankFileLine l, CompanyBankAccount account, DateTime valueDate, DateTime runMonth) => f.SourceCode switch
    {
        "EMPLOYER_CODE" => account.WpsEmployerCode,
        "PAM_FILE_NO" => account.PamFileNo,
        "EMPLOYEE_CODE" => l.EmployeeNo,
        "CIVIL_ID" => l.CivilId,
        "EMPLOYEE_NAME" => l.EmployeeName,
        "BANK_WPS_CODE" => l.WpsBankCode,
        "BANK_SWIFT" => l.SwiftCode,
        "IBAN" => l.Iban,
        // the account number inside a Kuwait IBAN: after KWkk + the 4-letter bank code
        "ACCOUNT_NO" => l.Iban is { Length: > 8 } iban ? iban[8..].TrimStart('0') : l.Iban,
        "NET_AMOUNT" => Amount(l.NetPay),
        "BASIC_AMOUNT" => Amount(l.SalaryTotal),
        "ALLOWANCES" => Amount(l.EarningsTotal),
        "DEDUCTIONS" => Amount(l.DeductionsTotal),
        "PERIOD_YYYYMM" => runMonth.ToString("yyyyMM", Inv),
        "PAY_DATE" => valueDate.ToString("yyyy-MM-dd", Inv),
        "DEBIT_IBAN" => account.Iban?.Replace(" ", string.Empty, StringComparison.Ordinal),
        "CONSTANT" => f.ConstantValue,
        _ => null
    };

    private static string Cell(string? value, BankFileField f, bool fixedWidth, string delimiter, bool isAmount)
    {
        var text = (value ?? string.Empty).Replace('\r', ' ').Replace('\n', ' ');
        if (f.Width is { } width and > 0)
        {
            if (text.Length > width)
            {
                text = text[..width];
            }
            else if (fixedWidth || !string.IsNullOrEmpty(f.PadChar))
            {
                var pad = string.IsNullOrEmpty(f.PadChar) ? (isAmount ? '0' : ' ') : f.PadChar[0];
                text = f.AlignRight || (isAmount && string.IsNullOrEmpty(f.PadChar)) ? text.PadLeft(width, pad) : text.PadRight(width, pad);
            }
        }

        if (!fixedWidth && (text.Contains(delimiter, StringComparison.Ordinal) || text.Contains('"')))
        {
            text = "\"" + text.Replace("\"", "\"\"", StringComparison.Ordinal) + "\"";
        }
        return text;
    }

    private static string FileName(BankFileFormat format, CompanyBankAccount account, DateTime valueDate, DateTime runMonth)
    {
        var ext = format.FileType == "CSV" ? ".csv" : ".txt";
        var pattern = string.IsNullOrWhiteSpace(format.FileNamePattern) ? "SAL_{EMPLOYER}_{PERIOD}" + ext : format.FileNamePattern!;
        var name = pattern
            .Replace("{EMPLOYER}", string.IsNullOrWhiteSpace(account.WpsEmployerCode) ? account.AccountCode : account.WpsEmployerCode, StringComparison.OrdinalIgnoreCase)
            .Replace("{PERIOD}", runMonth.ToString("yyyyMM", Inv), StringComparison.OrdinalIgnoreCase)
            .Replace("{DATE}", valueDate.ToString("yyyyMMdd", Inv), StringComparison.OrdinalIgnoreCase);

        var clean = new StringBuilder(name.Length);
        foreach (var c in name)
        {
            clean.Append(Path.GetInvalidFileNameChars().Contains(c) || char.IsWhiteSpace(c) ? '_' : c);
        }
        var result = clean.ToString();
        if (!Path.HasExtension(result)) result += ext;
        return result.Length > 150 ? result[..150] : result;
    }
}
