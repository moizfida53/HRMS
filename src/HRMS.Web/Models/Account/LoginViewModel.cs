using System.ComponentModel.DataAnnotations;

namespace HRMS.Web.Models.Account;

public sealed class LoginViewModel
{
    [Required(ErrorMessage = "Enter your username or company email.")]
    [StringLength(100, ErrorMessage = "That is longer than any valid username.")]
    [Display(Name = "Username or company email")]
    public string Username { get; set; } = string.Empty;

    [Required(ErrorMessage = "Enter your password.")]
    [DataType(DataType.Password)]
    [StringLength(256, MinimumLength = 1, ErrorMessage = "That password is too long.")]
    public string Password { get; set; } = string.Empty;

    [Display(Name = "Keep me signed in")]
    public bool RememberMe { get; set; }

    /// <summary>
    /// Where to go after a successful sign-in. Only ever used when
    /// Url.IsLocalUrl() accepts it, so it cannot become an open redirect.
    /// </summary>
    public string? ReturnUrl { get; set; }

    /// <summary>Set by the controller; shown above the form.</summary>
    public string? ErrorMessage { get; set; }

    /// <summary>Shown after signing out, or when a session expires.</summary>
    public string? InfoMessage { get; set; }
}
