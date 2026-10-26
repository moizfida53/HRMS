using System.Globalization;
using HRMS.Domain.Common;
using HRMS.Domain.Leave;
using HRMS.Web.Localization;

namespace HRMS.Web.Models.Leave;

/// <summary>What the signed-in user may do in Leave (Security > Create Roles, "LV.*").</summary>
public sealed class LeaveRights
{
    public bool CanView { get; init; }
    /// <summary>Enter / change / cancel requests for others, record returns (HR).</summary>
    public bool CanManage { get; init; }
    public bool CanAdjust { get; init; }
    public bool CanApproveL1 { get; init; }
    public bool CanApproveL2 { get; init; }
    public bool CanApproveOwn { get; init; }
    public bool CanSetupView { get; init; }
    public bool CanSetupEdit { get; init; }
    /// <summary>db/86: settles the leave salary of an approved leave (cash before the leave or the payroll).</summary>
    public bool CanSettle { get; init; }
    public long? UserId { get; init; }
    /// <summary>The employee the user is (My Leave).</summary>
    public long? EmployeeId { get; init; }

    public bool AnyApproval => CanApproveL1 || CanApproveL2;

    /// <summary>May act on the request's current step (line manager of the employee, or the right for the step).</summary>
    public bool CanDecide(LeaveRequest r) =>
        r.IsPending
        && (r.ApprovalLevel == 1 ? (r.ManagerUserId == UserId && UserId is not null) || CanApproveL1 : CanApproveL2)
        && (r.EmployeeId != EmployeeId || CanApproveOwn);

    public bool CanCancel(LeaveRequest r) =>
        (r.IsPending || r.IsApproved)
        && (CanManage || (r.EmployeeId == EmployeeId && (r.IsPending || r.StartDate.Date > DateTime.Today)));

    public bool CanEdit(LeaveRequest r) => r.IsPending && (CanManage || r.EmployeeId == EmployeeId);

    public bool CanRecordReturn(LeaveRequest r) => r.IsApproved && CanManage;

    public bool CanSettleRequest(LeaveRequest r) => r.IsApproved && CanSettle;
}

/// <summary>The leave salary settlement popup (db/86).</summary>
public sealed class LeaveSettlementModel
{
    public required LeaveRequest Request { get; init; }
    public required LeaveSettlement Settlement { get; init; }
    public IReadOnlyList<LeavePayItem> Items { get; init; } = Array.Empty<LeavePayItem>();
}

public sealed class LeavePageModel
{
    public required LeaveRights Rights { get; init; }
    public IReadOnlyList<LeaveEmployeeOption> Employees { get; init; } = Array.Empty<LeaveEmployeeOption>();
    public IReadOnlyList<LeaveTypeSetting> Types { get; init; } = Array.Empty<LeaveTypeSetting>();
    public string Status { get; init; } = "ALL";
    public bool ManyCompanies { get; init; }
}

/// <summary>A list of requests: HR's list, My Leave, or the team waiting for the user.</summary>
public sealed class LeaveRequestsGridModel
{
    public required PagedResult<LeaveRequest> Page { get; init; }
    public required LeaveRights Rights { get; init; }
    /// <summary>hr, my or team.</summary>
    public string Mode { get; init; } = "hr";
    public bool IsFiltered { get; init; }
    public bool ManyCompanies { get; init; }
}

public sealed class LeaveRequestFormModel
{
    public LeaveRequest? Request { get; init; }
    public required LeaveRights Rights { get; init; }
    /// <summary>hr: pick any employee in scope; my: the user's own.</summary>
    public string Mode { get; init; } = "hr";
    public IReadOnlyList<LeaveEmployeeOption> Employees { get; init; } = Array.Empty<LeaveEmployeeOption>();
    public long? EmployeeId { get; init; }
    public IReadOnlyList<LeaveTypeOption> Types { get; init; } = Array.Empty<LeaveTypeOption>();
    public long MaxFileBytes { get; init; }
}

public sealed class LeaveRequestDetailModel
{
    public required LeaveRequest Request { get; init; }
    public required LeaveRights Rights { get; init; }
    public IReadOnlyList<LeaveHistoryEntry> History { get; init; } = Array.Empty<LeaveHistoryEntry>();
    public LeaveBalance? Balance { get; init; }
}

public sealed class LeaveBalancesPageModel
{
    public required LeaveRights Rights { get; init; }
    public IReadOnlyList<LeaveTypeSetting> Types { get; init; } = Array.Empty<LeaveTypeSetting>();
    public IReadOnlyList<LeaveEmployeeOption> Employees { get; init; } = Array.Empty<LeaveEmployeeOption>();
}

public sealed class LeaveBalancesGridModel
{
    public required PagedResult<LeaveBalance> Page { get; init; }
    public required LeaveRights Rights { get; init; }
    public DateTime AsOf { get; init; }
    public bool IsFiltered { get; init; }
}

public sealed class LeaveLedgerModel
{
    public required LeaveBalance Balance { get; init; }
    public IReadOnlyList<LeaveLedgerLine> Lines { get; init; } = Array.Empty<LeaveLedgerLine>();
    public bool CanAdjust { get; init; }
}

public sealed class LeaveMyPageModel
{
    public required LeaveRights Rights { get; init; }
    public bool HasEmployee { get; init; }
    public IReadOnlyList<LeaveBalance> Balances { get; init; } = Array.Empty<LeaveBalance>();
    public int TeamPending { get; init; }
}

/// <summary>Balance cards: My Leave, the employee profile's Leave tab, the request popup.</summary>
public sealed class LeaveBalanceCardsModel
{
    public IReadOnlyList<LeaveBalance> Balances { get; init; } = Array.Empty<LeaveBalance>();
    public bool Compact { get; init; }
}

public sealed class LeaveEmployeePanelModel
{
    public long EmployeeId { get; init; }
    public IReadOnlyList<LeaveBalance> Balances { get; init; } = Array.Empty<LeaveBalance>();
    public IReadOnlyList<LeaveRequest> Requests { get; init; } = Array.Empty<LeaveRequest>();
    public bool CanOpenLeave { get; init; }
}

public sealed class LeaveSettingsPageModel
{
    public required LeaveRights Rights { get; init; }
    public IReadOnlyList<LeaveCompanySetting> Companies { get; init; } = Array.Empty<LeaveCompanySetting>();
    public bool AllCompaniesUser { get; init; }
    public int Year { get; init; } = DateTime.Today.Year;
}

public sealed class LeaveTypesGridModel
{
    public IReadOnlyList<LeaveTypeSetting> Types { get; init; } = Array.Empty<LeaveTypeSetting>();
    public bool CanEdit { get; init; }
    public bool ManyCompanies { get; init; }
}

public sealed class LeaveTypeFormModel
{
    public LeaveTypeSetting? Type { get; init; }
    public IReadOnlyList<LeaveCompanySetting> Companies { get; init; } = Array.Empty<LeaveCompanySetting>();
}

public sealed class LeaveHolidaysGridModel
{
    public IReadOnlyList<LeaveHoliday> Holidays { get; init; } = Array.Empty<LeaveHoliday>();
    public bool CanEdit { get; init; }
    public int Year { get; init; }
}

public sealed class LeaveHolidayFormModel
{
    public LeaveHoliday? Holiday { get; init; }
    public IReadOnlyList<LeaveCompanySetting> Companies { get; init; } = Array.Empty<LeaveCompanySetting>();
    public bool AllCompaniesUser { get; init; }
}

/// <summary>Text helpers shared by the Leave views.</summary>
public static class LeaveFormat
{
    private static readonly CultureInfo Inv = CultureInfo.InvariantCulture;

    public static string Name(IUiText L, string? english, string? arabic) =>
        L.IsArabic && !string.IsNullOrWhiteSpace(arabic) ? arabic! : english ?? string.Empty;

    /// <summary>12, 2.5, 0.5 - no trailing zeros.</summary>
    public static string Days(decimal? days) => days is { } d ? d.ToString("0.##", Inv) : "—";

    /// <summary>1,234.500 (KWD, three decimals).</summary>
    public static string Kwd(decimal? amount) => amount is { } a ? a.ToString("#,0.000", Inv) : "—";

    /// <summary>How the leave salary is paid (db/86).</summary>
    public static string SettlementLabel(IUiText L, string? mode) => mode switch
    {
        LeaveSettlementMode.Cash => L["lv.settle_cash"],
        LeaveSettlementMode.Payroll => L["lv.settle_payroll"],
        _ => L["lv.settle_not_yet"]
    };

    public static string DaysText(IUiText L, decimal days) =>
        days == 1 ? L["lv.1_day"] : L["lv.n_days", Days(days)];

    public static string Period(IUiText L, DateTime start, DateTime end, bool halfDay) =>
        start.Date == end.Date
            ? L.Date(start) + (halfDay ? " · " + L["lv.half_day"] : "")
            : L.DayMonth(start) + " – " + L.Date(end);

    public static string StatusLabel(IUiText L, LeaveRequest r) => r.Status switch
    {
        LeaveStatus.Pending when r.ApprovalLevel == 1 => L["lv.status_pending_manager"],
        LeaveStatus.Pending => L["lv.status_pending_hr"],
        LeaveStatus.Approved when r.ActualReturnDate is not null => L["lv.status_returned"],
        LeaveStatus.Approved when r.StartDate.Date <= DateTime.Today && r.LastDay.Date >= DateTime.Today => L["lv.status_on_leave"],
        LeaveStatus.Approved => L["lv.status_approved"],
        LeaveStatus.Rejected => L["lv.status_rejected"],
        _ => L["lv.status_cancelled"]
    };

    public static string ModeLabel(IUiText L, string? mode, string? accrual) => mode switch
    {
        LeaveBalanceMode.Accrue => accrual == "UPFRONT" ? L["lv.mode_accrue_upfront"] : L["lv.mode_accrue_monthly"],
        LeaveBalanceMode.Yearly => L["lv.mode_yearly"],
        LeaveBalanceMode.Once => L["lv.mode_once"],
        _ => L["lv.mode_unlimited"]
    };

    public static string PayLabel(IUiText L, string? pay) => pay switch
    {
        "TIERED" => L["lv.pay_tiered"],
        "UNPAID" => L["lv.pay_unpaid"],
        _ => L["lv.pay_full"]
    };

    public static string CategoryLabel(IUiText L, string? category) => category switch
    {
        "ANNUAL" => L["lv.cat_annual"],
        "SICK" => L["lv.cat_sick"],
        "EMERGENCY" => L["lv.cat_emergency"],
        "HAJJ" => L["lv.cat_hajj"],
        "MATERNITY" => L["lv.cat_maternity"],
        "BEREAVEMENT" => L["lv.cat_bereavement"],
        "UNPAID" => L["lv.cat_unpaid"],
        _ => L["lv.cat_other"]
    };

    public static string HistoryLabel(IUiText L, string code) => code switch
    {
        "SUBMITTED" => L["lv.h_submitted"],
        "EDITED" => L["lv.h_edited"],
        "MANAGER_APPROVED" => L["lv.h_manager_approved"],
        "APPROVED" => L["lv.h_approved"],
        "REJECTED" => L["lv.h_rejected"],
        "CANCELLED" => L["lv.h_cancelled"],
        "RETURNED" => L["lv.h_returned"],
        "UNPAID" => L["lv.h_unpaid"],
        "SETTLED" => L["lv.h_settled"],
        _ => code
    };

    public static string WeekdayName(IUiText L, int isoDay) =>
        L.Tr(CultureInfo.GetCultureInfo("en-GB").DateTimeFormat.GetDayName((DayOfWeek)(isoDay % 7)));

    public static string Swatch(string? color) =>
        color is { Length: 7 } c && c[0] == '#' && c[1..].All(Uri.IsHexDigit) ? c : "#64748b";
}
