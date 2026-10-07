using System.ComponentModel.DataAnnotations;

namespace HRMS.Domain.Payroll;

/// <summary>
/// A pay group's schedule (Payroll.PayrollCalendars, db/29). Monthly calendars
/// use a cut-off day and a payment day; weekly / bi-weekly calendars use offsets
/// in days from the period end. Saved through Payroll.usp_PayrollCalendar_Manage.
/// </summary>
public sealed class PayrollCalendar
{
    public int PayrollCalendarId { get; set; }

    [Required(ErrorMessage = "Company is required.")]
    [Range(1, int.MaxValue, ErrorMessage = "Select a company.")]
    [Display(Name = "Company")]
    public int CompanyId { get; set; }

    [Required(ErrorMessage = "Calendar code is required.")]
    [StringLength(30)]
    [RegularExpression("^[A-Za-z0-9_-]+$", ErrorMessage = "Use letters, numbers, hyphen or underscore only.")]
    [Display(Name = "Calendar Code")]
    public string CalendarCode { get; set; } = string.Empty;

    [Required(ErrorMessage = "Calendar name is required.")]
    [StringLength(150)]
    [Display(Name = "Calendar Name")]
    public string CalendarName { get; set; } = string.Empty;

    [StringLength(150)]
    [Display(Name = "Arabic Name")]
    public string? ArabicName { get; set; }

    [Required(ErrorMessage = "Pay frequency is required.")]
    [Display(Name = "Pay Frequency")]
    public string PayFrequency { get; set; } = "MONTHLY";

    [Required(ErrorMessage = "First period start date is required.")]
    [Display(Name = "First Period Start")]
    public DateTime? FirstPeriodStartDate { get; set; }

    [Range(1, 31, ErrorMessage = "Enter a day between 1 and 31.")]
    [Display(Name = "Cut-off Day")]
    public int? CutOffDay { get; set; }

    [Range(1, 31, ErrorMessage = "Enter a day between 1 and 31.")]
    [Display(Name = "Payment Day")]
    public int? PaymentDay { get; set; }

    [Display(Name = "Paid the following month")]
    public bool PaymentNextMonth { get; set; }

    [Range(-60, 60, ErrorMessage = "Enter between -60 and 60 days.")]
    [Display(Name = "Cut-off (days from period end)")]
    public int? CutOffOffsetDays { get; set; }

    [Range(-60, 60, ErrorMessage = "Enter between -60 and 60 days.")]
    [Display(Name = "Payment (days from period end)")]
    public int? PaymentOffsetDays { get; set; }

    [Display(Name = "Days Basis")]
    public string WorkingDaysBasis { get; set; } = "FIXED";

    [Range(1, 31, ErrorMessage = "Enter between 1 and 31 days.")]
    [Display(Name = "Days per Month")]
    public int? FixedDaysPerMonth { get; set; } = 26;

    [Display(Name = "Currency")]
    public int? CurrencyId { get; set; }

    [StringLength(500)]
    public string? Description { get; set; }

    [Display(Name = "Default calendar")]
    public bool IsDefault { get; set; }

    [Display(Name = "Active")]
    public bool IsActive { get; set; } = true;

    // ---- LIST-only columns ----
    public string? CompanyName { get; set; }
    public string? CurrencyCode { get; set; }
    public int PeriodCount { get; set; }
    public string? CurrentPeriodName { get; set; }

    /// <summary>db column PaymentMonthOffset (0 / 1) - bound through <see cref="PaymentNextMonth"/>.</summary>
    public int PaymentMonthOffset
    {
        get => PaymentNextMonth ? 1 : 0;
        set => PaymentNextMonth = value == 1;
    }
}

/// <summary>Editable fields of a generated pay period (usp_PayrollPeriod_Manage UPDATE).</summary>
public sealed class PayrollPeriodEdit
{
    public int PayrollPeriodId { get; set; }

    [Required(ErrorMessage = "Start date is required.")]
    [Display(Name = "Start")]
    public DateTime? StartDate { get; set; }

    [Required(ErrorMessage = "End date is required.")]
    [Display(Name = "End")]
    public DateTime? EndDate { get; set; }

    [Display(Name = "Cut-off")]
    public DateTime? CutOffDate { get; set; }

    [Display(Name = "Pay date")]
    public DateTime? PaymentDate { get; set; }

    [StringLength(100)]
    [Display(Name = "Period Name")]
    public string? PeriodName { get; set; }

    [StringLength(500)]
    public string? Remarks { get; set; }

    public string? Status { get; set; }
}
