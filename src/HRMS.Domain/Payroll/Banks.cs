using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Payroll;

/// <summary>Payroll.Banks - the bank master, shared by every company (db/29-30).</summary>
public sealed class Bank
{
    public int BankId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(20)]
    public string BankCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the name.")]
    [StringLength(150)]
    public string BankName { get; set; } = string.Empty;

    [StringLength(150)]
    public string? ArabicName { get; set; }

    [StringLength(30)]
    public string? ShortName { get; set; }

    [StringLength(11, MinimumLength = 8, ErrorMessage = "A SWIFT / BIC code is 8 or 11 letters and digits.")]
    [RegularExpression(@"^[A-Za-z0-9]{8}([A-Za-z0-9]{3})?$", ErrorMessage = "A SWIFT / BIC code is 8 or 11 letters and digits.")]
    public string? SwiftCode { get; set; }

    /// <summary>The 4 letters inside a Kuwait IBAN (KWkk BBBB ...).</summary>
    [StringLength(10)]
    public string? IbanBankCode { get; set; }

    /// <summary>The code the bank / PAM expects in the WPS salary file.</summary>
    [StringLength(20)]
    public string? WpsBankCode { get; set; }

    public int? CountryId { get; set; }
    public bool IsActive { get; set; } = true;

    public string? CountryName { get; set; }
    public int AccountCount { get; set; }
}

/// <summary>Payroll.CompanyBankAccounts - the company's own salary (debit) accounts.</summary>
public sealed class CompanyBankAccount
{
    public int CompanyBankAccountId { get; set; }

    [Range(1, int.MaxValue, ErrorMessage = "Select the company.")]
    public int CompanyId { get; set; }

    [Range(1, int.MaxValue, ErrorMessage = "Select the bank.")]
    public int BankId { get; set; }

    [Required(ErrorMessage = "Enter a code.")]
    [StringLength(30)]
    public string AccountCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter the account title.")]
    [StringLength(150)]
    public string AccountTitle { get; set; } = string.Empty;

    [StringLength(34)]
    public string? AccountNumber { get; set; }

    /// <summary>Typed with or without spaces; checked (mod-97) by the procedure.</summary>
    [StringLength(50)]
    public string? Iban { get; set; }

    public int? CurrencyId { get; set; }

    [StringLength(150)]
    public string? BranchName { get; set; }

    [StringLength(50)]
    public string? WpsEmployerCode { get; set; }

    [StringLength(50)]
    public string? PamFileNo { get; set; }

    public bool IsDefault { get; set; }
    public bool IsActive { get; set; } = true;

    public string? CompanyName { get; set; }
    public string? BankName { get; set; }
    public string? SwiftCode { get; set; }
    public string? WpsBankCode { get; set; }
    public string? CurrencyCode { get; set; }
}
