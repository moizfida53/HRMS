namespace HRMS.Web.Security;

/// <summary>Access to a page or a function on Security > Create Roles. Each level includes the ones below it.</summary>
public enum AccessLevel
{
    None = 0,
    /// <summary>See it (read-only).</summary>
    Read = 1,
    /// <summary>Add, edit, process.</summary>
    Write = 2,
    /// <summary>Write plus delete, cancel, reopen.</summary>
    Full = 3
}

/// <summary>
/// A page, or a function inside a page, and the permission codes each level grants.
/// A level with no codes is not offered for that row (e.g. a function that is read
/// with its page has no Read of its own).
/// </summary>
public sealed record AccessItem(
    string Code,
    string TitleKey,
    string? HintKey,
    string[] Read,
    string[] Write,
    string[] Full,
    AccessItem[]? Functions = null)
{
    public IReadOnlyList<AccessItem> Children => Functions ?? [];

    public bool Offers(AccessLevel level) => level switch
    {
        AccessLevel.Read => Read.Length > 0,
        AccessLevel.Write => Write.Length > 0,
        AccessLevel.Full => Full.Length > 0,
        _ => true
    };

    /// <summary>The codes a level grants (cumulative: Full includes Write and Read).</summary>
    public IEnumerable<string> CodesFor(AccessLevel level)
    {
        if (level >= AccessLevel.Read) foreach (var c in Read) yield return c;
        if (level >= AccessLevel.Write) foreach (var c in Write) yield return c;
        if (level >= AccessLevel.Full) foreach (var c in Full) yield return c;
    }

    public IEnumerable<string> AllCodes => Read.Concat(Write).Concat(Full);

    /// <summary>The level a set of codes amounts to: the highest offered level whose codes (and those below) are all held.</summary>
    public AccessLevel LevelIn(ISet<string> codes)
    {
        var level = AccessLevel.None;
        foreach (var l in new[] { AccessLevel.Read, AccessLevel.Write, AccessLevel.Full })
        {
            var own = l switch { AccessLevel.Read => Read, AccessLevel.Write => Write, _ => Full };
            if (own.Length == 0) continue;            // not offered: no step at this level
            if (!own.All(codes.Contains)) break;
            level = l;
        }
        return level;
    }
}

/// <summary>A module: a group of pages (the sidebar groups).</summary>
public sealed record AccessModule(string Code, string TitleKey, string Icon, AccessItem[] Pages);

/// <summary>An approval process: who reviews at level 1 (HR), approves at level 2 (Finance), and may approve their own submissions.</summary>
public sealed record ApprovalItem(string Code, string TitleKey, string HintKey, string Level1, string Level2, string Self)
{
    public IEnumerable<string> AllCodes => [Level1, Level2, Self];
}

/// <summary>
/// The application's pages, their functions and approvals, and the permission codes the
/// code checks for each (db/57 seeds them). Create Roles shows this catalog; saving a role
/// turns the ticks into codes in Security.RolePermissions - the same codes sign-in loads and
/// every controller checks, so the screen and the enforcement cannot drift apart.
/// </summary>
public static class AccessCatalog
{
    private static string[] C(params string[] codes) => codes;
    private static readonly string[] No = [];

    public static readonly AccessModule[] Modules =
    [
        new("WF", "sec.mod_workforce", "users",
        [
            new("WF.EMPLOYEES", "sec.pg_employees", "sec.pg_employees_hint",
                C("EMPLOYEE_VIEW"), C("EMPLOYEE_CREATE"), C("EMPLOYEE_DELETE"),
            [
                new("WF.PERSONAL", "sec.fn_personal", "sec.fn_personal_hint", No, C("EMPLOYEE_EDIT"), No),
                new("WF.COMPLIANCE", "sec.fn_compliance", null, C("EMPLOYEE_COMPLIANCE_VIEW"), C("EMPLOYEE_COMPLIANCE_EDIT"), No),
                new("WF.DEPENDENTS", "sec.fn_dependents", null, C("EMPLOYEE_DEPENDENT_VIEW"), C("EMPLOYEE_DEPENDENT_EDIT"), C("EMPLOYEE_DEPENDENT_DELETE")),
                new("WF.DOCUMENTS", "sec.fn_documents", "sec.fn_documents_hint", C("EMPLOYEE_DOCUMENT_VIEW"), C("EMPLOYEE_DOCUMENT_UPLOAD"), C("EMPLOYEE_DOCUMENT_DELETE"))
            ])
        ]),
        new("ORG", "sec.mod_organization", "building",
        [
            new("ORG.SETUP", "sec.pg_organization", "sec.pg_organization_hint",
                C("ORGANIZATION_VIEW"), C("ORGANIZATION_CREATE", "ORGANIZATION_EDIT"), C("ORGANIZATION_DELETE"),
            [
                new("ORG.COMPANIES", "sec.fn_companies", "sec.fn_companies_hint", No, C("ORGANIZATION_COMPANY_EDIT"), C("ORGANIZATION_COMPANY_DELETE"))
            ])
        ]),
        new("PR", "sec.mod_payroll", "calculator",
        [
            new("PR.DASHBOARD", "sec.pg_payroll_dashboard", null, C("PAYROLL_DASHBOARD_VIEW"), No, No),
            new("PR.RUNS", "sec.pg_payrolls", "sec.pg_payrolls_hint",
                C("PAYROLL_RUN_VIEW"), C("PAYROLL_RUN_PROCESS"), No,
            [
                new("PR.RUN_EXCLUDE", "sec.fn_run_exclude", null, No, C("PAYROLL_RUN_EXCLUDE"), No),
                new("PR.RUN_CANCEL", "sec.fn_run_cancel", null, No, No, C("PAYROLL_RUN_CANCEL")),
                new("PR.RUN_REOPEN", "sec.fn_run_reopen", null, No, No, C("PAYROLL_RUN_REOPEN"))
            ]),
            new("PR.CALENDAR", "sec.pg_calendar", "sec.pg_calendar_hint",
                C("PAYROLL_CALENDAR_VIEW"), C("PAYROLL_CALENDAR_EDIT"), C("PAYROLL_CALENDAR_DELETE")),
            new("PR.PAYITEMS", "sec.pg_pay_items", "sec.pg_pay_items_hint",
                C("PAYROLL_ITEM_VIEW"), C("PAYROLL_ITEM_CREATE", "PAYROLL_ITEM_EDIT"), C("PAYROLL_ITEM_DELETE")),
            new("PR.SETTLEMENT", "sec.pg_settlement", null,
                C("PAYROLL_FS_VIEW"), C("PAYROLL_FS_PROCESS"), C("PAYROLL_FS_CANCEL"),
            [
                new("PR.FS_PAY", "sec.fn_fs_pay", null, No, C("PAYROLL_FS_PAY"), No)
            ])
        ]),
        new("PS", "sec.mod_payslips", "receipt",
        [
            new("PS.PAYSLIPS", "sec.pg_payslips", "sec.pg_payslips_hint",
                C("PAYROLL_SLIP_VIEW"), C("PAYROLL_SLIP_GENERATE"), No,
            [
                new("PS.EMAIL", "sec.fn_payslip_email", null, No, C("PAYROLL_SLIP_EMAIL"), No)
            ])
        ]),
        new("FIN", "sec.mod_finance", "bank",
        [
            new("FIN.BANK", "sec.pg_bank", "sec.pg_bank_hint", C("PAYROLL_BANK_VIEW"), C("PAYROLL_BANK_PROCESS"), No),
            new("FIN.ACCOUNTING", "sec.pg_accounting", "sec.pg_accounting_hint", C("PAYROLL_GL_VIEW"), C("PAYROLL_GL_POST"), No),
            new("FIN.REPORTS", "sec.pg_reports", null, C("PAYROLL_REPORT_VIEW"), No, No)
        ]),
        new("SET", "sec.mod_settings", "sliders",
        [
            new("SET.PAYROLL", "sec.pg_payroll_settings", "sec.pg_payroll_settings_hint",
                C("PAYROLL_SETUP_VIEW"), C("PAYROLL_SETUP_CREATE", "PAYROLL_SETUP_EDIT"), C("PAYROLL_SETUP_DELETE"))
        ]),
        new("SEC", "sec.mod_security", "shield",
        [
            new("SEC.ROLES", "sec.pg_roles", "sec.pg_roles_hint", C("SECURITY_ROLE_VIEW"), C("SECURITY_ROLE_EDIT"), C("SECURITY_ROLE_DELETE")),
            new("SEC.ASSIGN", "sec.pg_assign", "sec.pg_assign_hint", C("SECURITY_USER_VIEW"), C("SECURITY_USER_ASSIGN"), No)
        ])
    ];

    public static readonly ApprovalItem[] Approvals =
    [
        new("APR.PAYROLL", "sec.apr_payroll", "sec.apr_payroll_hint",
            "PAYROLL_RUN_APPROVE_HR", "PAYROLL_RUN_APPROVE_FINANCE", "PAYROLL_RUN_APPROVE_SELF"),
        new("APR.PAYITEM", "sec.apr_pay_items", "sec.apr_pay_items_hint",
            "PAYROLL_ITEM_APPROVE_L1", "PAYROLL_ITEM_APPROVE_L2", "PAYROLL_ITEM_APPROVE_SELF"),
        new("APR.SETTLEMENT", "sec.apr_settlement", "sec.apr_settlement_hint",
            "PAYROLL_FS_APPROVE_L1", "PAYROLL_FS_APPROVE_L2", "PAYROLL_FS_APPROVE_SELF")
    ];

    public static IEnumerable<AccessItem> Pages => Modules.SelectMany(m => m.Pages);

    public static IEnumerable<AccessItem> AllItems => Pages.SelectMany(p => p.Children.Prepend(p));

    /// <summary>Every code the role screen manages - saving a role replaces exactly these.</summary>
    public static readonly IReadOnlyList<string> ManagedCodes =
        AllItems.SelectMany(i => i.AllCodes).Concat(Approvals.SelectMany(a => a.AllCodes))
                .Distinct(StringComparer.Ordinal).OrderBy(c => c, StringComparer.Ordinal).ToList();

    public static AccessItem? Find(string code) => AllItems.FirstOrDefault(i => i.Code == code);

    /// <summary>
    /// The codes for the levels ticked per row (item code -> level) and the approvals ticked
    /// (approval code -> "L1"/"L2"/"SELF"). A function only counts while its page is readable.
    /// </summary>
    public static IReadOnlyCollection<string> CodesFor(IReadOnlyDictionary<string, AccessLevel> levels,
                                                       IReadOnlyDictionary<string, ISet<string>> approvals)
    {
        var codes = new HashSet<string>(StringComparer.Ordinal);
        foreach (var page in Pages)
        {
            var pageLevel = levels.GetValueOrDefault(page.Code, AccessLevel.None);
            if (pageLevel == AccessLevel.None) continue;   // no page, no functions
            codes.UnionWith(page.CodesFor(Cap(page, pageLevel)));
            foreach (var fn in page.Children)
                codes.UnionWith(fn.CodesFor(Cap(fn, levels.GetValueOrDefault(fn.Code, AccessLevel.None))));
        }
        foreach (var a in Approvals)
        {
            if (!approvals.TryGetValue(a.Code, out var cols)) continue;
            if (cols.Contains("L1")) codes.Add(a.Level1);
            if (cols.Contains("L2")) codes.Add(a.Level2);
            if (cols.Contains("SELF")) codes.Add(a.Self);
        }
        return codes;
    }

    /// <summary>A level the row does not offer counts as the highest one below it that it does.</summary>
    private static AccessLevel Cap(AccessItem item, AccessLevel level)
    {
        while (level > AccessLevel.None && !item.Offers(level)) level--;
        return level;
    }

    // ------------------------------------------------------- reading rights
    /// <summary>The codes that open each sidebar entry (any one is enough).</summary>
    public static readonly IReadOnlyDictionary<string, string[]> NavCodes = new Dictionary<string, string[]>(StringComparer.Ordinal)
    {
        ["employees"] = ["EMPLOYEE_VIEW"],
        ["organization"] = ["ORGANIZATION_VIEW"],
        ["payroll:dashboard"] = ["PAYROLL_DASHBOARD_VIEW"],
        ["payroll:processing"] = ["PAYROLL_RUN_VIEW", "PAYROLL_CALENDAR_VIEW"],
        ["payroll:payitems"] = ["PAYROLL_ITEM_VIEW"],
        ["payroll:settlement"] = ["PAYROLL_FS_VIEW"],
        ["payroll:payslips"] = ["PAYROLL_SLIP_VIEW", "PAYROLL_SLIP_GENERATE", "PAYROLL_SLIP_EMAIL"],
        ["payroll:bank"] = ["PAYROLL_BANK_VIEW"],
        ["payroll:accounting"] = ["PAYROLL_GL_VIEW"],
        ["payroll:reports"] = ["PAYROLL_REPORT_VIEW"],
        ["payroll:settings"] = ["PAYROLL_SETUP_VIEW"],
        ["tab:payrolls"] = ["PAYROLL_RUN_VIEW"],
        ["tab:history"] = ["PAYROLL_RUN_VIEW"],
        ["tab:calendars"] = ["PAYROLL_CALENDAR_VIEW"],
        ["tab:pay-periods"] = ["PAYROLL_CALENDAR_VIEW"],
        ["security:roles"] = ["SECURITY_ROLE_VIEW"],
        ["security:assign"] = ["SECURITY_USER_VIEW"]
    };

    /// <summary>The user may open a sidebar entry (unknown entries stay visible).</summary>
    public static bool CanOpen(this ICurrentUser user, string navKey) =>
        !NavCodes.TryGetValue(navKey, out var codes) || codes.Any(user.HasPermission);
}
