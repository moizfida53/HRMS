using System.ComponentModel.DataAnnotations;
using HRMS.Web.Security;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Models.Account;

/// <summary>
/// Change Password dialog (account menu, bottom-left of the sidebar).
/// The strength rules here are the server-side source of truth; site.js
/// shows the same checklist live while typing. With
/// Authentication:SimplePassword = true there are no strength rules -
/// only "required" and at most 50 characters (the [Password] column).
/// </summary>
public sealed class ChangePasswordViewModel : IValidatableObject
{
    public const int MinLength = 8;

    [Required(ErrorMessage = "Enter your current password.")]
    [DataType(DataType.Password)]
    [StringLength(256)]
    [Display(Name = "Current password")]
    public string CurrentPassword { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter a new password.")]
    [DataType(DataType.Password)]
    [StringLength(128, ErrorMessage = "Use at most 128 characters.")]
    [Display(Name = "New password")]
    public string NewPassword { get; set; } = string.Empty;

    [Required(ErrorMessage = "Re-enter the new password.")]
    [DataType(DataType.Password)]
    [Compare(nameof(NewPassword), ErrorMessage = "The two new passwords don't match.")]
    [Display(Name = "Confirm new password")]
    public string ConfirmPassword { get; set; } = string.Empty;

    public IEnumerable<ValidationResult> Validate(ValidationContext validationContext)
    {
        var p = NewPassword ?? string.Empty;
        var simple = validationContext.GetService<IOptions<AuthenticationPolicyOptions>>()?.Value.SimplePassword ?? false;

        if (simple)
        {
            if (p.Length > AuthenticationPolicyOptions.SimplePasswordMaxLength)
            {
                yield return new ValidationResult(
                    $"Use at most {AuthenticationPolicyOptions.SimplePasswordMaxLength} characters.",
                    [nameof(NewPassword)]);
            }
        }
        else if (p.Length > 0 && p.Length < MinLength)
        {
            yield return new ValidationResult("Use at least 8 characters.", [nameof(NewPassword)]);
        }
        else if (p.Length >= MinLength &&
            (!p.Any(char.IsUpper) || !p.Any(char.IsLower) || !p.Any(char.IsDigit)))
        {
            yield return new ValidationResult(
                "Use upper- and lower-case letters and at least one number.",
                [nameof(NewPassword)]);
        }

        if (!string.IsNullOrEmpty(p) && p == CurrentPassword)
        {
            yield return new ValidationResult(
                "The new password must be different from the current one.",
                [nameof(NewPassword)]);
        }
    }
}
