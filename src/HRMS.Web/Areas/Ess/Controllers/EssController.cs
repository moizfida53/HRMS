using System.Globalization;
using HRMS.Data.Repositories;
using HRMS.Domain.Attendance;
using HRMS.Domain.Leave;
using HRMS.Domain.Security;
using HRMS.Web.Areas.Ess.Models;
using HRMS.Web.Localization;
using HRMS.Web.Models.Leave;
using HRMS.Web.Models.Organization;
using HRMS.Web.Security;
using HRMS.Web.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.RateLimiting;
using Microsoft.Extensions.Options;

namespace HRMS.Web.Areas.Ess.Controllers;

/// <summary>
/// Employee Self Service - the mobile / installable web app at <c>/ess</c> (db/146).
/// <list type="bullet">
/// <item>Punch In / Out from the phone, only within the branch geofence (checked on the server).</item>
/// <item>The month's attendance: present, absent, short, leave, and the daily log.</item>
/// <item>Annual leave only: balance, history and a new request (the Leave module's own rules and approvals).</item>
/// <item>The employee's own profile, read-only.</item>
/// </list>
/// Everything is for the employee linked to the signed-in user (Security.Users.EmployeeId);
/// no employee id is ever taken from the browser.
/// </summary>
[Area("Ess")]
[Route("ess")]
public sealed class EssController : Controller
{
    private readonly ISelfServiceRepository _ess;
    private readonly ILeaveRepository _leave;
    private readonly IAttendanceService _attendance;
    private readonly ISignInService _signIn;
    private readonly ILocalizationRepository _localization;
    private readonly ICurrentUser _currentUser;
    private readonly IUiText _text;
    private readonly SelfServiceOptions _options;
    private readonly ILogger<EssController> _logger;

    public EssController(
        ISelfServiceRepository ess,
        ILeaveRepository leave,
        IAttendanceService attendance,
        ISignInService signIn,
        ILocalizationRepository localization,
        ICurrentUser currentUser,
        IUiText text,
        IOptions<SelfServiceOptions> options,
        ILogger<EssController> logger)
    {
        _ess = ess;
        _leave = leave;
        _attendance = attendance;
        _signIn = signIn;
        _localization = localization;
        _currentUser = currentUser;
        _text = text;
        _options = options.Value;
        _logger = logger;
    }

    private CancellationToken Ct => HttpContext.RequestAborted;

    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    /// <summary>Leave procedures as the employee themself (My Leave rules: notice days, line manager first).</summary>
    private LeaveScope SelfScope => new()
    {
        CompanyId = _currentUser.ActiveCompanyId,
        UserId = _currentUser.UserId,
        IsHr = false
    };

    // =======================================================================
    // Sign in / out
    // =======================================================================

    [AllowAnonymous]
    [HttpGet("login")]
    public IActionResult Login(string? returnUrl = null, string? reason = null)
    {
        if (User.Identity?.IsAuthenticated == true && _currentUser.EmployeeId is not null)
        {
            return LocalRedirect(SafeReturnUrl(returnUrl) ?? "~/ess/");
        }

        ModelState.Clear();
        return View(new EssLoginModel
        {
            ReturnUrl = SafeReturnUrl(returnUrl),
            InfoMessage = reason switch
            {
                "signedout" => "You have been signed out.",
                "timeout" => "Your session expired. Please sign in again.",
                _ => null
            }
        });
    }

    [AllowAnonymous]
    [HttpPost("login")]
    [ValidateAntiForgeryToken]
    [EnableRateLimiting("login")]
    public async Task<IActionResult> Login(EssLoginModel model)
    {
        model.ReturnUrl = SafeReturnUrl(model.ReturnUrl);

        if (string.IsNullOrWhiteSpace(model.Username) || string.IsNullOrWhiteSpace(model.Password))
        {
            model.ErrorMessage = "The username or password is incorrect.";
            model.Password = string.Empty;
            return View(model);
        }

        var result = await _signIn.PasswordSignInAsync(model.Username.Trim(), model.Password, model.RememberMe, Ct);
        model.Password = string.Empty;
        ModelState.Remove(nameof(EssLoginModel.Password));

        if (!result.Succeeded)
        {
            // the same wording as the main sign-in: never confirm that a username exists
            model.ErrorMessage = result.Outcome switch
            {
                LoginOutcome.AccountLockedOut => "This account is temporarily locked after too many failed attempts.",
                LoginOutcome.AccountInactive => "That account is not active. Contact your HR administrator.",
                _ => "The username or password is incorrect."
            };
            return View(model);
        }

        if (result.User?.EmployeeId is null)
        {
            // self service is for employees only - an admin account without an employee goes to the full system
            await _signIn.SignOutAsync();
            model.ErrorMessage = "Your account is not linked to an employee. Contact your HR administrator.";
            return View(model);
        }

        await ApplyPreferredLanguageAsync(result.User.UserId);
        return LocalRedirect(model.ReturnUrl ?? "~/ess/");
    }

    [HttpPost("logout")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Logout()
    {
        await _signIn.SignOutAsync();
        return RedirectToAction(nameof(Login), new { reason = "signedout" });
    }

    // =======================================================================
    // The app
    // =======================================================================

    [HttpGet("")]
    public async Task<IActionResult> Index()
    {
        if (_currentUser.UserId is not { } userId || _currentUser.EmployeeId is null)
        {
            return View("NotLinked");
        }

        var now = LocalClock.Now;
        var today = await _ess.TodayAsync(userId, now, Ct);
        if (today is null)
        {
            return View("NotLinked");
        }

        var model = new EssPageModel
        {
            Home = new EssHomeModel
            {
                Today = today,
                Month = await MonthModelAsync(userId, now, now),
                Leave = await LeaveModelAsync(today.EmployeeId),
                RadiusM = _options.PunchRadiusMeters
            },
            Profile = await _ess.ProfileAsync(userId, Ct),
            Initials = _currentUser.Initials,
            CanOpenDesktop = User.Claims.Any(c => c.Type == HrmsClaims.Permission)
        };
        return View(model);
    }

    /// <summary>The Punch tab again (after a punch).</summary>
    [HttpGet("home")]
    public async Task<IActionResult> Home()
    {
        if (_currentUser.UserId is not { } userId) return Unauthorized();
        var now = LocalClock.Now;
        var today = await _ess.TodayAsync(userId, now, Ct);
        if (today is null) return NotFound();
        return PartialView("_Home", new EssHomeModel
        {
            Today = today,
            Month = await MonthModelAsync(userId, now, now),
            Leave = await LeaveModelAsync(today.EmployeeId),
            RadiusM = _options.PunchRadiusMeters
        });
    }

    /// <summary>The places the employee may punch at (for the distance shown on the screen).</summary>
    [HttpGet("locations")]
    public async Task<IActionResult> Locations()
    {
        if (_currentUser.UserId is not { } userId) return Unauthorized();
        var locations = await _ess.LocationsAsync(userId, _options.PunchRadiusMeters, Ct);
        return Json(new
        {
            maxAccuracy = _options.MaxAccuracyMeters,
            locations = locations.Select(l => new { id = l.LocationId, name = l.LocationName, lat = l.Latitude, lng = l.Longitude, radius = l.RadiusM })
        });
    }

    public sealed class PunchInput
    {
        public string? Type { get; set; }
        public decimal? Lat { get; set; }
        public decimal? Lng { get; set; }
        public decimal? Accuracy { get; set; }
    }

    /// <summary>
    /// Punch In / Out. The phone sends where it is; the procedure finds the nearest branch
    /// location, refuses a punch outside its radius or with a poor GPS reading, and logs
    /// every attempt (Attendance.MobilePunches). The day is then worked out again (late,
    /// short hours) with the employee's attendance pattern.
    /// </summary>
    [HttpPost("punch")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Punch(PunchInput input)
    {
        if (_currentUser.UserId is not { } userId) return Unauthorized();

        var type = string.Equals(input.Type, "OUT", StringComparison.OrdinalIgnoreCase) ? "OUT" : "IN";
        var now = LocalClock.Now;
        var (result, row) = await _ess.PunchAsync(new EssPunchRequest(
            userId, type, now, input.Lat, input.Lng, input.Accuracy is { } a ? Math.Round(a, 2) : null,
            _options.PunchRadiusMeters, _options.MaxAccuracyMeters,
            HttpContext.Connection.RemoteIpAddress?.ToString(), Request.Headers.UserAgent.ToString()), Ct);

        if (!result.Success)
        {
            return Json(new
            {
                ok = false,
                code = result.ErrorCode,
                message = _text.Tr(result.Message, capture: true),
                distance = row?.DistanceM is { } d ? (int?)Math.Round(d) : null
            });
        }

        if (row is not null)
        {
            await RecalculateAsync(row);
        }

        return Json(new
        {
            ok = true,
            type,
            message = _text.Tr(result.Message, capture: true),
            clockIn = EssFormat.Time(row?.ClockIn),
            clockOut = row?.ClockOut is null ? null : EssFormat.Time(row.ClockOut)
        });
    }

    /// <summary>The Attendance tab for a month ("2026-11").</summary>
    [HttpGet("attendance")]
    public async Task<IActionResult> Attendance(string? month)
    {
        if (_currentUser.UserId is not { } userId) return Unauthorized();
        var now = LocalClock.Now;
        var m = DateTime.TryParseExact(month, "yyyy-MM", Inv, DateTimeStyles.None, out var parsed) ? parsed : now;
        if (m > now) m = now;
        return PartialView("_Attendance", await MonthModelAsync(userId, m, now));
    }

    /// <summary>The Leave tab again (after a request).</summary>
    [HttpGet("leave")]
    public async Task<IActionResult> Leave()
    {
        if (_currentUser.EmployeeId is not { } emp) return Unauthorized();
        return PartialView("_Leave", await LeaveModelAsync(emp));
    }

    public sealed class LeaveInput
    {
        public DateTime? StartDate { get; set; }
        public DateTime? EndDate { get; set; }
        public string? Reason { get; set; }
        public bool AcceptUnpaid { get; set; }
    }

    /// <summary>Days counted and the balance after - shown while the dates are picked.</summary>
    [HttpPost("leave/preview")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> LeavePreview(LeaveInput input)
    {
        if (_currentUser.EmployeeId is not { } emp) return Unauthorized();
        if (input.StartDate is null || input.EndDate is null) return Json(new { ready = false });

        var type = await AnnualTypeAsync(emp, input.StartDate);
        if (type is null) return Json(new { ready = true, ok = false, problems = new[] { _text["ess.no_annual"] } });

        var (preview, error) = await _leave.PreviewAsync(ToRequest(emp, type, input), SelfScope, Ct);
        if (error is not null) return Json(new { ready = true, ok = false, problems = new[] { _text.Tr(error.Message, capture: true) } });

        var problems = (preview?.Problems ?? string.Empty)
            .Split('|', StringSplitOptions.RemoveEmptyEntries)
            .Select(m => _text.Tr(m, capture: true))
            .ToArray();
        return Json(new
        {
            ready = true,
            ok = problems.Length == 0,
            days = LeaveFormat.Days(preview?.Days),
            after = preview?.After is { } after ? LeaveFormat.Days(after) : null,
            unpaidDays = preview?.UnpaidDays ?? 0,
            problems
        });
    }

    /// <summary>
    /// Sends an annual leave request. The leave type is always the employee's annual leave
    /// (found here, never sent by the browser); the request follows the Leave module's
    /// approval chain (line manager, then HR).
    /// </summary>
    [HttpPost("leave/submit")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> LeaveSubmit(LeaveInput input)
    {
        if (_currentUser.EmployeeId is not { } emp) return Unauthorized();
        if (input.StartDate is null || input.EndDate is null)
        {
            return Json(ActionResponse.Failed("Enter the first and last day of the leave.", "VALIDATION"));
        }

        var type = await AnnualTypeAsync(emp, input.StartDate);
        if (type is null) return Json(ActionResponse.Failed("Annual leave is not set up for your company yet.", "NO_TYPE"));
        if (type.RequiresDocument)
        {
            return Json(ActionResponse.Failed("This leave needs a supporting document. Please apply from the full HR system.", "DOCUMENT"));
        }

        var result = await _leave.SaveAsync(ToRequest(emp, type, input), null, SelfScope, Ct);
        if (!result.Success)
        {
            return Json(ActionResponse.Failed(result.Message, result.ErrorCode));
        }
        return Json(ActionResponse.Ok(result.Id, "Your leave request has been sent for approval."));
    }

    // =======================================================================
    // helpers
    // =======================================================================

    private async Task<EssMonthModel> MonthModelAsync(long userId, DateTime month, DateTime now)
    {
        var first = new DateTime(month.Year, month.Month, 1);
        var days = await _ess.MonthAsync(userId, first, now, Ct);
        var thisMonth = new DateTime(now.Year, now.Month, 1);
        return new EssMonthModel
        {
            Month = first,
            Today = now.Date,
            Days = days,
            Months = Enumerable.Range(0, 12).Select(i => thisMonth.AddMonths(-i)).ToList()
        };
    }

    private async Task<EssLeaveModel> LeaveModelAsync(long employeeId)
    {
        var balances = await _leave.EmployeeBalancesAsync(employeeId, LocalClock.Today, null, Ct);
        var annual = balances.FirstOrDefault(b => b.Category == "ANNUAL");
        if (annual is null) return new EssLeaveModel();

        var requests = await _leave.ListAsync(new LeaveRequestFilter
        {
            SelfEmployeeId = employeeId,
            LeaveTypeId = annual.LeaveTypeId,
            Status = "ALL",
            PageSize = 50
        }, SelfScope, Ct);

        return new EssLeaveModel
        {
            Annual = annual,
            Requests = requests.Items.Where(r => r.Category == "ANNUAL").ToList()
        };
    }

    private async Task<LeaveTypeOption?> AnnualTypeAsync(long employeeId, DateTime? onDate)
    {
        var types = await _leave.TypesForAsync(employeeId, onDate, Ct);
        return types.FirstOrDefault(t => t.Category == "ANNUAL");
    }

    private static LeaveRequestInput ToRequest(long employeeId, LeaveTypeOption type, LeaveInput input) => new()
    {
        EmployeeId = employeeId,
        LeaveTypeId = type.LeaveTypeId,
        StartDate = input.StartDate?.Date,
        EndDate = input.EndDate?.Date,
        Reason = string.IsNullOrWhiteSpace(input.Reason) ? null : input.Reason.Trim(),
        AcceptUnpaid = input.AcceptUnpaid,
        ApproveNow = false
    };

    /// <summary>
    /// Works the employee's day out again (late, short hours, absent days before it) - the same
    /// calculation as after a device import. The calendar month and the next are both done, so
    /// a payroll calendar that starts mid-month (e.g. on the 25th) is covered too. A failure
    /// here never undoes the punch: HR's next import or recalculation fixes the figures.
    /// </summary>
    private async Task RecalculateAsync(EssPunchRow row)
    {
        try
        {
            var month = new DateTime(row.WorkDate.Year, row.WorkDate.Month, 1);
            await _attendance.RecalculateAsync(
                [new AttMonth(row.CompanyId, month), new AttMonth(row.CompanyId, month.AddMonths(1))],
                row.EmployeeId, Ct);
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Self service: the attendance of employee {EmployeeId} could not be recalculated after a punch.", row.EmployeeId);
        }
    }

    private async Task ApplyPreferredLanguageAsync(long userId)
    {
        try
        {
            if (Request.Cookies.ContainsKey(Language.ChosenCookieName))
            {
                Response.Cookies.Delete(Language.ChosenCookieName);
                var chosen = Language.Normalize(Request.Cookies[Language.CookieName]);
                await _localization.SetUserLanguageAsync(userId, chosen, Ct);
                return;
            }

            var saved = await _localization.GetUserLanguageAsync(userId, Ct);
            if (!string.IsNullOrWhiteSpace(saved))
            {
                Language.WriteCookie(HttpContext, saved);
            }
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            _logger.LogWarning(ex, "Could not read the preferred language for user {UserId}.", userId);
        }
    }

    private string? SafeReturnUrl(string? returnUrl) =>
        !string.IsNullOrWhiteSpace(returnUrl) && Url.IsLocalUrl(returnUrl)
        && returnUrl.StartsWith("/ess", StringComparison.OrdinalIgnoreCase)
            ? returnUrl
            : null;
}
