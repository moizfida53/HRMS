/* =====================================================================
   106_Actual_Working_Months.sql  -  Leave and indemnity on actual working months
   ---------------------------------------------------------------------
   Run after db/98 and db/40 (and db/105). CREATE OR ALTER / IF NOT EXISTS
   everywhere - safe to re-run. It replaces Leave.tvf_Balances and
   Leave.usp_LeaveBalance_Manage (db/98) and Payroll.usp_FinalSettlement_
   Calculate / usp_FinalSettlement_Manage (db/40): run this script again
   whenever db/98 or db/40 is run.

   The rule
     An unpaid absence of MORE THAN ONE MONTH (31 calendar days or more -
     Leave.ufn_ServiceRules) is not service. No salary is paid for those
     months, so they earn neither annual leave nor indemnity. Shorter unpaid
     absences still count.

     Unpaid absence = approved leave requests: every day of a leave type paid
     "Unpaid", and the unpaid days of a paid leave taken over the balance
     (UnpaidDays - the last days of the leave, as the payroll deducts them).
     Back-to-back unpaid leaves form one absence (Leave.tvf_UnpaidSpells).

     Example: joined 1 Jan, worked to 30 Jun, 15 days paid leave, then six
     months unpaid, back on 1 Jan the next year. On 31 Dec: work period 12
     months, actual working months about 6 - indemnity counts about half a
     year of service and annual leave about half a year's days.

   Where it applies
     Indemnity  Final Settlement: service = the actual working days since
                the hire date (work period - excluded days). Both are kept on
                the settlement (WorkPeriodDays, UnpaidExcludedDays) and shown.
     Leave      annual leave earned (Leave.tvf_Balances) = days per year x the
                months worked, less days per year x excluded days / 365.
                The balance shows the work period vs actual working months
                since the last paid annual leave (Leave.tvf_LeaveServiceSince),
                and so does the settlement.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NULL OR COL_LENGTH(N'Leave.LeaveRequests', N'UnpaidDays') IS NULL
   OR OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/40, db/86 and db/98 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the settlement keeps both periods ------------------------------ */
IF COL_LENGTH(N'Payroll.FinalSettlements', N'WorkPeriodDays') IS NULL
    ALTER TABLE [Payroll].[FinalSettlements] ADD
        WorkPeriodDays      INT   NULL,     -- hire date to last working day (calendar days)
        UnpaidExcludedDays  INT   NULL,     -- unpaid absences over a month in that period (ServiceDays = WorkPeriodDays - this)
        LeaveSinceDate      DATE  NULL,     -- the day after the last paid annual leave (else the hire date)
        LeaveWorkDays       INT   NULL,     -- since then: the work period ...
        LeaveActualDays     INT   NULL;     -- ... and the actual working days
GO

/* ---- 2. the functions --------------------------------------------------- */

/* The rule's threshold: an unpaid absence longer than this is not service. */
CREATE OR ALTER FUNCTION [Leave].[ufn_ServiceRules] ()
RETURNS TABLE
AS
RETURN
    SELECT CAST(30 AS INT) AS ExcludeUnpaidOverDays;
GO

/* The unpaid absences of an employee (NULL = everyone): approved unpaid leave days merged into
   continuous spells. IsExcluded = longer than the threshold; DaysInPeriod = the part inside
   @From..@To (the length that decides IsExcluded is the whole spell). */
CREATE OR ALTER FUNCTION [Leave].[tvf_UnpaidSpells] (@EmployeeId BIGINT, @From DATE, @To DATE)
RETURNS TABLE
AS
RETURN
WITH lv AS (
    SELECT  r.EmployeeId, r.StartDate, ISNULL(r.ActualEndDate, r.EndDate) AS LastDay, r.Days, r.UnpaidDays, t.PayType
    FROM    [Leave].[LeaveRequests] AS r
    JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
    WHERE   r.Deleted = 0 AND r.Status = 'APPROVED'
      AND   (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId)
      AND   (t.PayType = 'UNPAID' OR r.UnpaidDays > 0)
), u AS (
    /* the calendar days unpaid: the whole leave, or its last days (in proportion to the unpaid share) */
    SELECT  lv.EmployeeId,
            CASE WHEN lv.PayType = 'UNPAID' OR lv.Days <= 0 OR lv.UnpaidDays >= lv.Days THEN lv.StartDate
                 ELSE DATEADD(DAY, 1 - CAST(CEILING((DATEDIFF(DAY, lv.StartDate, lv.LastDay) + 1) * lv.UnpaidDays / lv.Days) AS INT), lv.LastDay)
            END AS UFrom,
            lv.LastDay AS UTo
    FROM    lv
    WHERE   lv.LastDay >= lv.StartDate
), o AS (
    SELECT  u.*, MAX(u.UTo) OVER (PARTITION BY u.EmployeeId ORDER BY u.UFrom, u.UTo ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING) AS PrevTo
    FROM    u
), g AS (
    SELECT  o.*, SUM(CASE WHEN o.PrevTo IS NOT NULL AND o.UFrom <= DATEADD(DAY, 1, o.PrevTo) THEN 0 ELSE 1 END)
                 OVER (PARTITION BY o.EmployeeId ORDER BY o.UFrom, o.UTo ROWS UNBOUNDED PRECEDING) AS Grp
    FROM    o
), s AS (
    SELECT  EmployeeId, MIN(UFrom) AS SpellFrom, MAX(UTo) AS SpellTo
    FROM    g
    GROUP BY EmployeeId, Grp
)
SELECT  s.EmployeeId, s.SpellFrom, s.SpellTo, d.SpellDays,
        CAST(CASE WHEN d.SpellDays > ru.ExcludeUnpaidOverDays THEN 1 ELSE 0 END AS BIT) AS IsExcluded,
        CASE WHEN @From IS NULL OR @To IS NULL OR s.SpellTo < @From OR s.SpellFrom > @To THEN 0
             ELSE DATEDIFF(DAY, CASE WHEN s.SpellFrom > @From THEN s.SpellFrom ELSE @From END,
                                CASE WHEN s.SpellTo < @To THEN s.SpellTo ELSE @To END) + 1 END AS DaysInPeriod
FROM    s
CROSS APPLY (SELECT DATEDIFF(DAY, s.SpellFrom, s.SpellTo) + 1 AS SpellDays) AS d
CROSS JOIN [Leave].[ufn_ServiceRules]() AS ru;
GO

/* One employee's period @From..@To: the work period, the excluded unpaid days and the actual
   working days, in days and months (30.4375 days a month). */
CREATE OR ALTER FUNCTION [Leave].[tvf_ServicePeriod] (@EmployeeId BIGINT, @From DATE, @To DATE)
RETURNS TABLE
AS
RETURN
SELECT  p.WorkDays, x.ExcludedDays, p.WorkDays - x.ExcludedDays AS ActualDays,
        CAST(ROUND(p.WorkDays / 30.4375, 2) AS DECIMAL(9, 2)) AS WorkMonths,
        CAST(ROUND((p.WorkDays - x.ExcludedDays) / 30.4375, 2) AS DECIMAL(9, 2)) AS ActualMonths,
        x.ExcludedSpells, x.ShortUnpaidDays
FROM   (SELECT CASE WHEN @From IS NULL OR @To IS NULL OR @From > @To THEN 0 ELSE DATEDIFF(DAY, @From, @To) + 1 END AS WorkDays) AS p
CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN u.IsExcluded = 1 THEN u.DaysInPeriod END), 0) AS ExcludedDays,
                    COUNT(CASE WHEN u.IsExcluded = 1 AND u.DaysInPeriod > 0 THEN 1 END) AS ExcludedSpells,
                    ISNULL(SUM(CASE WHEN u.IsExcluded = 0 THEN u.DaysInPeriod END), 0) AS ShortUnpaidDays
             FROM   [Leave].[tvf_UnpaidSpells](@EmployeeId, @From, @To) AS u
             WHERE  @EmployeeId IS NOT NULL) AS x;
GO

/* Leave: the period since the last paid annual leave (the day after its paid days; no paid
   leave yet = the hire date) up to @AsOf - work period vs actual working. */
CREATE OR ALTER FUNCTION [Leave].[tvf_LeaveServiceSince] (@EmployeeId BIGINT, @AsOf DATE)
RETURNS TABLE
AS
RETURN
WITH lp AS (
    SELECT TOP (1) pd.PaidTo
    FROM   [Leave].[LeaveRequests] AS r
    JOIN   [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
    CROSS APPLY (SELECT ISNULL(r.ActualEndDate, r.EndDate) AS LastDay) AS l
    CROSS APPLY (SELECT CASE WHEN r.UnpaidDays > 0 AND r.Days > 0
                             THEN DATEADD(DAY, -CAST(CEILING((DATEDIFF(DAY, r.StartDate, l.LastDay) + 1) * r.UnpaidDays / r.Days) AS INT), l.LastDay)
                             ELSE l.LastDay END AS PaidTo) AS pd
    WHERE  r.EmployeeId = @EmployeeId AND r.Deleted = 0 AND r.Status = 'APPROVED'
      AND  t.Category = 'ANNUAL' AND t.PayType <> 'UNPAID' AND r.Days - r.UnpaidDays > 0 AND r.StartDate <= @AsOf
    ORDER BY pd.PaidTo DESC
), f AS (
    SELECT lp.PaidTo AS LastPaidLeaveTo, COALESCE(DATEADD(DAY, 1, lp.PaidTo), e.HireDate) AS SinceDate
    FROM   [Employee].[Employees] AS e
    OUTER APPLY (SELECT PaidTo FROM lp) AS lp
    WHERE  e.EmployeeId = @EmployeeId
)
SELECT  f.LastPaidLeaveTo, f.SinceDate, sp.WorkDays, sp.ExcludedDays, sp.ActualDays, sp.WorkMonths, sp.ActualMonths
FROM    f
CROSS APPLY [Leave].[tvf_ServicePeriod](@EmployeeId, f.SinceDate, @AsOf) AS sp;
GO

/* ---- 3. Leave.tvf_Balances (db/98) - annual leave earned less the excluded months ---- */
CREATE OR ALTER FUNCTION [Leave].[tvf_Balances]
(
    @AsOf        DATE,
    @EmployeeId  BIGINT        -- NULL = every employee
)
RETURNS TABLE
AS
RETURN
/* db/106: an unpaid absence of more than a month (Leave.tvf_UnpaidSpells) is left out of the
   annual leave earned: Earned - days per year x excluded days / 365 (ExcludedDays, ExcludedEarned).
   db/98: eliminated days (ELIMINATE) count with the adjustments.
   db/86: Taken / Pending count the paid days only - the days over the balance
   that the employee took unpaid (UnpaidDays) do not reduce it */
WITH et AS (
    SELECT  e.EmployeeId, e.CompanyId, e.HireDate,
            t.LeaveTypeId, t.BalanceMode, t.Category,
            /* db/82: the employee's own annual leave (Employment Terms) replaces the
               type's days per year for annual leave; blank = the type's */
            CASE WHEN t.Category = 'ANNUAL' AND e.AnnualLeaveDays IS NOT NULL THEN e.AnnualLeaveDays
                 ELSE t.DaysPerYear END AS DaysPerYear,
            t.AccrualMethod,
            op.OpeningDate, ISNULL(op.OpeningDays, 0) AS OpeningDays,
            CASE t.BalanceMode
                 WHEN 'ACCRUE' THEN COALESCE(op.OpeningDate, e.HireDate, DATEFROMPARTS(YEAR(@AsOf), 1, 1))
                 WHEN 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 1, 1)
                 ELSE CAST('19000101' AS DATE) END AS WinStart,
            CASE WHEN t.BalanceMode = 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 12, 31)
                 ELSE CAST('99991231' AS DATE) END AS WinEnd
    FROM    [Employee].[Employees] AS e
    JOIN    [Leave].[LeaveTypes] AS t
            ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
           AND (t.Gender IS NULL OR t.Gender = e.Gender)
    OUTER APPLY (SELECT TOP (1) l.EntryDate AS OpeningDate, l.Days AS OpeningDays
                 FROM   [Leave].[LeaveLedger] AS l
                 WHERE  l.EmployeeId = e.EmployeeId AND l.LeaveTypeId = t.LeaveTypeId AND l.EntryType = 'OPENING'
                   AND  l.Deleted = 0 AND l.EntryDate <= @AsOf
                 ORDER BY l.EntryDate DESC, l.EntryId DESC) AS op
    WHERE   e.Deleted = 0 AND (@EmployeeId IS NULL OR e.EmployeeId = @EmployeeId)
),
calc AS (
    SELECT  et.*,
            CAST(CASE et.BalanceMode
                 WHEN 'ACCRUE' THEN
                      CASE WHEN et.WinStart > @AsOf THEN 0
                           WHEN et.AccrualMethod = 'UPFRONT'
                                THEN ISNULL(et.DaysPerYear, 0) * ((YEAR(@AsOf) - YEAR(et.WinStart)) + (13 - MONTH(et.WinStart)) / 12.0)
                           ELSE ISNULL(et.DaysPerYear, 0) / 12.0
                                * (DATEDIFF(MONTH, et.WinStart, @AsOf) - CASE WHEN DAY(@AsOf) < DAY(et.WinStart) THEN 1 ELSE 0 END)
                      END
                 WHEN 'UNLIMITED' THEN 0
                 ELSE ISNULL(et.DaysPerYear, 0) END AS DECIMAL(9, 2)) AS RawEarned,
            ISNULL(x.ExcludedDays, 0) AS ExcludedDays,
            ISNULL((SELECT SUM(a.Days) FROM [Leave].[LeaveLedger] AS a
                    WHERE a.EmployeeId = et.EmployeeId AND a.LeaveTypeId = et.LeaveTypeId AND a.EntryType IN ('ADJUST', 'ELIMINATE')   -- db/98: an elimination takes days off
                      AND a.Deleted = 0 AND a.EntryDate BETWEEN et.WinStart AND et.WinEnd AND a.EntryDate <= @AsOf), 0) AS Adjusted,
            ISNULL((SELECT SUM(r.Days - r.UnpaidDays) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'APPROVED' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Taken,
            ISNULL((SELECT SUM(r.Days - r.UnpaidDays) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'PENDING' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Pending
    FROM    et
    /* db/106: unpaid leave of more than a month earns no annual leave */
    OUTER APPLY (SELECT sp.ExcludedDays FROM [Leave].[tvf_ServicePeriod](et.EmployeeId, et.WinStart, @AsOf) AS sp
                 WHERE et.Category = 'ANNUAL' AND et.BalanceMode = 'ACCRUE' AND et.WinStart <= @AsOf) AS x
),
calc2 AS (
    SELECT  c.*,
            CAST(CASE WHEN c.ExcludedDays > 0 AND c.RawEarned - ISNULL(c.DaysPerYear, 0) * c.ExcludedDays / 365.0 < 0 THEN 0
                      WHEN c.ExcludedDays > 0 THEN c.RawEarned - ISNULL(c.DaysPerYear, 0) * c.ExcludedDays / 365.0
                      ELSE c.RawEarned END AS DECIMAL(9, 2)) AS Earned
    FROM    calc AS c
)
SELECT  EmployeeId, CompanyId, LeaveTypeId, BalanceMode, WinStart, WinEnd, OpeningDate,
        CAST(OpeningDays AS DECIMAL(9, 2)) AS OpeningDays, Earned, CAST(Adjusted AS DECIMAL(9, 2)) AS Adjusted,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted END AS DECIMAL(9, 2)) AS Entitled,
        CAST(Taken AS DECIMAL(9, 2)) AS Taken,
        CAST(Pending AS DECIMAL(9, 2)) AS Pending,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted - Taken END AS DECIMAL(9, 2)) AS Available,
        ExcludedDays,
        CAST(RawEarned - Earned AS DECIMAL(9, 2)) AS ExcludedEarned
FROM    calc2;
GO

/* ---- 4. Leave.usp_LeaveBalance_Manage (db/98) - EMPLOYEE / LIST return the flags ---- */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveBalance_Manage]
    @Action        VARCHAR(20),
    @Id            BIGINT          = NULL,
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL,
    @AsOf          DATE            = NULL,
    @EmployeeId    BIGINT          = NULL,
    @LeaveTypeId   INT             = NULL,
    @Category      VARCHAR(12)     = NULL,
    @Search        NVARCHAR(200)   = NULL,
    @SelfOnly      BIT             = 0,
    @EntryType     VARCHAR(10)     = NULL,
    @EntryDate     DATE            = NULL,
    @Days          DECIMAL(7, 2)   = NULL,
    @Comment       NVARCHAR(500)   = NULL,
    @MinDays       DECIMAL(7, 2)   = NULL,      -- db/98 ANNUAL: only balances over this
    @PageNumber    INT             = 1,
    @PageSize      INT             = 25,
    @UserId        BIGINT          = NULL,

    @TotalCount    INT             = NULL OUTPUT,
    @NewId         BIGINT          = NULL OUTPUT,
    @ResultCode    VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    SET @AsOf = ISNULL(@AsOf, @Today);
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* the employee is in the user's companies (My Leave: the user's own employee, checked by the caller) */
    DECLARE @EmpOk BIT = CASE WHEN @EmployeeId IS NULL THEN 1
                              WHEN @SelfOnly = 1 THEN 1
                              WHEN EXISTS (SELECT 1 FROM [Employee].[Employees] e WHERE e.EmployeeId = @EmployeeId AND e.Deleted = 0
                                             AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                                             AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)) THEN 1
                              ELSE 0 END;
    IF @EmpOk = 0
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee.'; RETURN; END;

    /* ======================= LIST - employee x type ============== */
    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN @PageSize < 1 THEN 25 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;
        SELECT  b.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                co.CompanyName, d.DepartmentName, e.HireDate,
                b.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted, b.Entitled, b.Taken, b.Pending, b.Available,
                b.ExcludedDays, b.ExcludedEarned,
                COUNT(1) OVER () AS TotalRows
        INTO    #B
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = b.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        WHERE   e.IsDeleted = 0 AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND   (@LeaveTypeId IS NULL OR b.LeaveTypeId = @LeaveTypeId)
          AND   (@Category IS NULL OR t.Category = @Category)
          AND   (@Search IS NULL OR e.FirstName LIKE N'%' + @Search + N'%' OR e.LastName LIKE N'%' + @Search + N'%'
                 OR e.EmployeeCode LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%');

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #B;
        SELECT * FROM #B
        ORDER BY EmployeeName, LeaveTypeId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= EMPLOYEE - one employee's balances ==== */
    IF @Action = 'EMPLOYEE'
    BEGIN
        SELECT  b.EmployeeId, b.LeaveTypeId, t.TypeCode, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                t.AccrualMethod, t.DaysPerYear, t.PayType, b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted,
                b.Entitled, b.Taken, b.Pending, b.Available,
                /* db/106: excluded unpaid days, and the work period vs actual working since the last paid leave */
                b.ExcludedDays, b.ExcludedEarned,
                ls.SinceDate, ls.LastPaidLeaveTo, ls.WorkDays AS SinceWorkDays, ls.ExcludedDays AS SinceExcludedDays,
                ls.ActualDays AS SinceActualDays, ls.WorkMonths AS SinceWorkMonths, ls.ActualMonths AS SinceActualMonths
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        OUTER APPLY (SELECT * FROM [Leave].[tvf_LeaveServiceSince](b.EmployeeId, @AsOf) WHERE t.Category = 'ANNUAL') AS ls
        WHERE   @EmployeeId IS NOT NULL
        ORDER BY t.SortOrder, t.TypeName;
        RETURN;
    END;

    /* ======================= LEDGER - how a balance is made up ===== */
    IF @Action = 'LEDGER'
    BEGIN
        SELECT  'ENTRY' AS Kind, l.EntryId AS RefId, l.EntryType AS Code, l.EntryDate AS OnDate, NULL AS ToDate, l.Days, l.Comment,
                u.Username AS ByName, l.CreatedDate, NULL AS RequestNo, NULL AS Status,
                CAST(NULL AS VARCHAR(10)) AS SettlementMode, CAST(NULL AS DECIMAL(12, 3)) AS SettlementAmount
        FROM    [Leave].[LeaveLedger] AS l
        LEFT JOIN [Security].[Users] AS u ON u.UserId = l.CreatedBy
        WHERE   l.EmployeeId = @EmployeeId AND l.LeaveTypeId = @LeaveTypeId AND l.Deleted = 0
        UNION ALL
        SELECT  'REQUEST', r.LeaveRequestId, 'TAKEN', r.StartDate, ISNULL(r.ActualEndDate, r.EndDate), -(r.Days - r.UnpaidDays),
                CASE WHEN r.UnpaidDays > 0   -- db/86: the unpaid days are not taken from the balance
                     THEN CONCAT(r.Reason, CASE WHEN r.Reason IS NULL THEN N'' ELSE N' - ' END,
                                 N'+ ', FORMAT(r.UnpaidDays, '0.##', 'en-US'), N' unpaid days')
                     ELSE r.Reason END,
                u.Username, r.CreatedDate, r.RequestNo, r.Status,
                r.SettlementMode, r.SettlementAmount     -- db/98: how its leave salary was paid (cash / payroll)
        FROM    [Leave].[LeaveRequests] AS r
        LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
        WHERE   r.EmployeeId = @EmployeeId AND r.LeaveTypeId = @LeaveTypeId AND r.Deleted = 0 AND r.Status IN ('APPROVED', 'PENDING')
        ORDER BY OnDate DESC, CreatedDate DESC;
        RETURN;
    END;

    /* ======================= ANNUAL - each employee's annual leave balance (db/98) ==
       the balance left to take (approved and waiting requests off); @MinDays = only those over it.
       The dashboard counts those over 30 days; the Employees list shows and filters them. */
    IF @Action = 'ANNUAL'
    BEGIN
        SELECT  b.EmployeeId, b.LeaveTypeId, b.Available, b.Pending,
                CAST(b.Available - b.Pending AS DECIMAL(9, 2)) AS Balance
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = b.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        WHERE   t.Category = 'ANNUAL' AND b.Available IS NOT NULL
          AND   e.IsDeleted = 0 AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND   (@MinDays IS NULL OR b.Available - b.Pending > @MinDays);
        RETURN;
    END;

    /* ======================= ELIMINATE - force days off a large annual balance (db/98) ==
       only a balance over 60 days; at least 30 days always stay: 70 -> up to 40 eliminated.
       Kept in the ledger as ELIMINATE (minus days) with the remark. */
    IF @Action = 'ELIMINATE'
    BEGIN
        DECLARE @MinKeep DECIMAL(9, 2) = 30, @EliminateOver DECIMAL(9, 2) = 60;
        DECLARE @xCo INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @xCo IS NULL OR NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND CompanyId = @xCo
                                         AND Deleted = 0 AND Category = 'ANNUAL')
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee and annual leave.'; RETURN; END;

        DECLARE @Bal DECIMAL(9, 2) = (SELECT b.Available - b.Pending FROM [Leave].[tvf_Balances](@Today, @EmployeeId) AS b
                                      WHERE b.LeaveTypeId = @LeaveTypeId);
        IF @Bal IS NULL OR @Bal <= @EliminateOver
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Leave can be eliminated only from a balance over 60 days.'; RETURN; END;
        IF @Days IS NULL OR @Days <= 0
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days to eliminate.'; RETURN; END;
        IF @Days > @Bal - @MinKeep
        BEGIN
            SELECT @ResultCode = 'VALIDATION',
                   @ResultMessage = CONCAT(N'At most ', FORMAT(@Bal - @MinKeep, '0.##', 'en-US'), N' days can be eliminated - 30 days must remain.');
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the remarks for the elimination.'; RETURN; END;

        INSERT INTO [Leave].[LeaveLedger] (CompanyId, EmployeeId, LeaveTypeId, EntryType, EntryDate, Days, Comment, CreatedBy)
        VALUES (@xCo, @EmployeeId, @LeaveTypeId, 'ELIMINATE', @Today, -@Days, @Comment, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CONCAT(FORMAT(@Days, '0.##', 'en-US'), N' days eliminated.');
        RETURN;
    END;

    /* ======================= ADJUST / OPENING ===================== */
    IF @Action = 'ADJUST'
    BEGIN
        DECLARE @eCo INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @eCo IS NULL OR NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND CompanyId = @eCo AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee and leave type.'; RETURN; END;
        IF @EntryType NOT IN ('OPENING', 'ADJUST') OR @Days IS NULL OR @Days NOT BETWEEN -999 AND 999
           OR (@EntryType = 'OPENING' AND @Days < 0) OR (@EntryType = 'ADJUST' AND @Days = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days (an opening balance cannot be negative).'; RETURN; END;
        IF @EntryType = 'ADJUST' AND @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for the adjustment.'; RETURN; END;
        SET @EntryDate = ISNULL(@EntryDate, @Today);

        INSERT INTO [Leave].[LeaveLedger] (CompanyId, EmployeeId, LeaveTypeId, EntryType, EntryDate, Days, Comment, CreatedBy)
        VALUES (@eCo, @EmployeeId, @LeaveTypeId, @EntryType, @EntryDate, @Days, @Comment, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CASE WHEN @EntryType = 'OPENING' THEN N'Opening balance saved.' ELSE N'Balance adjusted.' END;
        RETURN;
    END;

    IF @Action = 'DELETE_ENTRY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Leave].[LeaveLedger] l JOIN [Employee].[Employees] e ON e.EmployeeId = l.EmployeeId
                       WHERE l.EntryId = @Id AND l.Deleted = 0
                         AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                         AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        UPDATE [Leave].[LeaveLedger] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EntryId = @Id;
        SELECT @NewId = @Id, @ResultMessage = N'Balance entry removed.';
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ---- 5. Payroll.usp_FinalSettlement_Calculate (db/40) - indemnity on actual working days ---- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_FinalSettlement_Calculate]
    @Id      BIGINT,
    @UserId  BIGINT = NULL,
    @Force   BIT    = 0         -- 1: also a pending settlement (the approval re-check)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CompanyId INT, @EmpId BIGINT, @Type VARCHAR(20), @Status VARCHAR(10), @LWD DATE, @SalaryFrom DATE,
            @Encash DECIMAL(7,2), @Now DATETIME2(0) = SYSUTCDATETIME();

    SELECT  @CompanyId = s.CompanyId, @EmpId = s.EmployeeId, @Type = s.SettlementType, @Status = s.Status,
            @LWD = s.LastWorkingDay, @SalaryFrom = s.SalaryFrom, @Encash = s.EncashDays
    FROM    [Payroll].[FinalSettlements] AS s
    WHERE   s.FinalSettlementId = @Id AND s.Deleted = 0;

    IF @Status IS NULL OR NOT (@Status = 'DRAFT' OR (@Force = 1 AND @Status = 'PENDING'))
        RETURN;

    DECLARE @IsExit BIT = CASE WHEN @Type = 'ENCASHMENT' THEN 0 ELSE 1 END;
    DECLARE @LwdMonth DATE = DATEFROMPARTS(YEAR(@LWD), MONTH(@LWD), 1);

    /* ---- employee and service ---------------------------------------- */
    DECLARE @Hire DATE, @IsKw BIT = 0;
    SELECT  @Hire = e.HireDate,
            @IsKw = CASE WHEN n.CountryCode IN ('KW', 'KWT') THEN 1 ELSE 0 END
    FROM    [Employee].[Employees] AS e
    LEFT JOIN [Core].[Countries]   AS n ON n.CountryId = e.NationalityCountryId
    WHERE   e.EmployeeId = @EmpId;

    DECLARE @SvcDays INT = CASE WHEN @Hire IS NULL OR @Hire > @LWD THEN 0 ELSE DATEDIFF(DAY, @Hire, @LWD) + 1 END;
    /* db/106: indemnity counts the actual working days - the work period (hire to last day) less
       every unpaid absence of more than a month (Leave.tvf_UnpaidSpells) */
    DECLARE @WorkDays INT = @SvcDays, @ExclDays INT = 0;
    IF @SvcDays > 0
        SELECT @ExclDays = ISNULL(sp.ExcludedDays, 0) FROM [Leave].[tvf_ServicePeriod](@EmpId, @Hire, @LWD) AS sp;
    SET @SvcDays = @WorkDays - ISNULL(@ExclDays, 0);
    /* leave: the work period vs actual working since the last paid leave (shown, for reference) */
    DECLARE @LvSince DATE, @LvWork INT, @LvActual INT;
    SELECT @LvSince = ls.SinceDate, @LvWork = ls.WorkDays, @LvActual = ls.ActualDays FROM [Leave].[tvf_LeaveServiceSince](@EmpId, @LWD) AS ls;
    DECLARE @SvcYears DECIMAL(9,4) = ROUND(@SvcDays / 365.0, 4);

    /* ---- salary in the month of the last working day ------------------ */
    DECLARE @Sal TABLE (PayComponentId INT PRIMARY KEY, Amount DECIMAL(12,3), IsInd BIT, IsLeave BIT, FromProfile BIT);
    INSERT INTO @Sal (PayComponentId, Amount, IsInd, IsLeave, FromProfile)
    SELECT f.PayComponentId, f.Amount, f.IsIndemnityApplicable, f.IsLeaveSalaryApplicable, f.FromProfile
    FROM   [Payroll].[ufn_FinalSettlement_Salary](@EmpId, @LwdMonth) AS f;

    DECLARE @Monthly DECIMAL(12,3) = ISNULL((SELECT SUM(Amount) FROM @Sal), 0);
    DECLARE @IndBase DECIMAL(12,3) = ISNULL((SELECT SUM(Amount) FROM @Sal WHERE IsInd = 1), 0);
    DECLARE @LeaveBase DECIMAL(12,3) = ISNULL((SELECT SUM(Amount) FROM @Sal WHERE IsLeave = 1), 0);
    DECLARE @FromProfile BIT = CASE WHEN EXISTS (SELECT 1 FROM @Sal WHERE FromProfile = 1) THEN 1 ELSE 0 END;
    IF @IndBase = 0 SET @IndBase = @Monthly;
    IF @LeaveBase = 0 SET @LeaveBase = @Monthly;

    /* ---- indemnity rule set in force on the last working day ---------- */
    DECLARE @Rs INT, @Div DECIMAL(5,2) = 26, @CapMonths DECIMAL(6,2), @MinSvc DECIMAL(6,2), @Verified BIT = 0;
    SELECT TOP (1) @Rs = r.IndemnityRuleSetId, @Div = r.DailyWageDivisor, @CapMonths = r.MaxIndemnityMonths,
                   @MinSvc = r.MinServiceMonths, @Verified = r.IsVerified
    FROM   [Payroll].[IndemnityRuleSets] AS r
    WHERE  r.Deleted = 0 AND r.IsActive = 1 AND r.EffectiveFrom <= @LWD AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @LWD)
    ORDER BY r.EffectiveFrom DESC, r.IndemnityRuleSetId DESC;
    IF ISNULL(@Div, 0) <= 0 SET @Div = 26;

    /* ---- old automatic lines go; waived ones are remembered ----------- */
    DECLARE @Waived TABLE (LineCode VARCHAR(10), EmployeePayItemId BIGINT, PeriodFrom DATE);
    INSERT INTO @Waived (LineCode, EmployeePayItemId, PeriodFrom)
    SELECT LineCode, EmployeePayItemId, PeriodFrom
    FROM   [Payroll].[FinalSettlementLines]
    WHERE  FinalSettlementId = @Id AND Deleted = 0 AND IsManual = 0 AND IsIncluded = 0;

    UPDATE [Payroll].[FinalSettlementLines]
       SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
    WHERE  FinalSettlementId = @Id AND Deleted = 0 AND IsManual = 0;

    /* what payrolls have paid of each pay item */
    DECLARE @Paid TABLE (EmployeePayItemId BIGINT PRIMARY KEY, PaidCount INT, PaidAmount DECIMAL(14,3));
    INSERT INTO @Paid (EmployeePayItemId, PaidCount, PaidAmount)
    SELECT l.EmployeePayItemId, COUNT(1), SUM(ABS(l.Amount))
    FROM   [Payroll].[PayrollRunLines] AS l
    JOIN   [Payroll].[PayrollRuns]     AS r ON r.PayrollRunId = l.PayrollRunId
    WHERE  l.EmployeeId = @EmpId AND l.Deleted = 0 AND r.Deleted = 0 AND l.EmployeePayItemId IS NOT NULL
      AND  r.Stage NOT IN ('DRAFT', 'CANCELLED')
    GROUP BY l.EmployeePayItemId;

    /* the months of the pending salary */
    DECLARE @Months TABLE (MonthStart DATE PRIMARY KEY, DaysInMonth INT NOT NULL, FromD DATE NOT NULL, ToD DATE NOT NULL);
    IF @IsExit = 1 AND @SalaryFrom IS NOT NULL AND @SalaryFrom <= @LWD
    BEGIN
        DECLARE @m DATE = DATEFROMPARTS(YEAR(@SalaryFrom), MONTH(@SalaryFrom), 1);
        WHILE @m <= @LwdMonth
        BEGIN
            INSERT INTO @Months (MonthStart, DaysInMonth, FromD, ToD)
            VALUES (@m, DAY(EOMONTH(@m)),
                    CASE WHEN @SalaryFrom > @m THEN @SalaryFrom ELSE @m END,
                    CASE WHEN @LWD < EOMONTH(@m) THEN @LWD ELSE EOMONTH(@m) END);
            SET @m = DATEADD(MONTH, 1, @m);
        END;
    END;

    IF @IsExit = 1
    BEGIN
        /* ---- 1. pending salary ---------------------------------------- */
        INSERT INTO [Payroll].[FinalSettlementLines]
            (FinalSettlementId, Section, LineCode, Description, ArabicDescription, PayComponentId, EmployeePayItemId,
             PeriodFrom, PeriodTo, Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
        SELECT  @Id, 'SALARY', 'SALARY', f.ComponentName, f.ArabicName, f.PayComponentId, f.EmployeePayItemId,
                m.FromD, m.ToD, d.Days, m.DaysInMonth, f.Amount,
                CASE WHEN f.IsProrated = 1 AND d.Days < m.DaysInMonth THEN ROUND(f.Amount * d.Days / m.DaysInMonth, 3) ELSE f.Amount END,
                f.DisplayOrder, @UserId
        FROM    @Months AS m
        CROSS APPLY (SELECT DATEDIFF(DAY, m.FromD, m.ToD) + 1 AS Days) AS d
        CROSS APPLY [Payroll].[ufn_FinalSettlement_Salary](@EmpId, m.MonthStart) AS f
        WHERE   f.Amount > 0;

        /* ---- 2. pay items of those months no payroll has paid --------- */
        INSERT INTO [Payroll].[FinalSettlementLines]
            (FinalSettlementId, Section, LineCode, Description, ArabicDescription, PayComponentId, EmployeePayItemId, SourceRef,
             PeriodFrom, PeriodTo, Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
        SELECT  @Id, CASE WHEN c.ItemClass = 'EARNING' THEN 'EARNING' ELSE 'RECOVERY' END, 'PAY_ITEM',
                c.ComponentName, c.ArabicName, c.PayComponentId, i.EmployeePayItemId, i.Comment,
                x.FromD, x.ToD, x.Days, x.DaysInMonth, i.Amount,
                CASE WHEN c.ItemClass = 'EARNING' THEN 1 ELSE -1 END * x.Amt,
                c.DisplayOrder, @UserId
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        CROSS APPLY (
            /* one time: the whole amount, in its month */
            SELECT m.FromD, m.ToD, NULL AS Days, NULL AS DaysInMonth, i.Amount AS Amt
            FROM   @Months AS m
            WHERE  i.AppliesMode = 'ONCE' AND i.StartMonth = m.MonthStart AND NOT EXISTS (SELECT 1 FROM @Paid p WHERE p.EmployeePayItemId = i.EmployeePayItemId)
            UNION ALL
            /* every month: prorated like salary */
            SELECT m.FromD, m.ToD, DATEDIFF(DAY, m.FromD, m.ToD) + 1, m.DaysInMonth,
                   CASE WHEN c.IsProrated = 1 AND DATEDIFF(DAY, m.FromD, m.ToD) + 1 < m.DaysInMonth
                        THEN ROUND(i.Amount * (DATEDIFF(DAY, m.FromD, m.ToD) + 1) / m.DaysInMonth, 3) ELSE i.Amount END
            FROM   @Months AS m
            WHERE  i.AppliesMode = 'MONTHLY' AND i.StartMonth <= m.MonthStart AND (i.EndMonth IS NULL OR i.EndMonth >= m.MonthStart)
        ) AS x
        WHERE   i.EmployeeId = @EmpId AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
          AND   c.ItemClass IN ('EARNING', 'DEDUCTION') AND x.Amt > 0;

        /* ---- 3. loans, advances and instalment deductions: the balance -- */
        INSERT INTO [Payroll].[FinalSettlementLines]
            (FinalSettlementId, Section, LineCode, Description, ArabicDescription, PayComponentId, EmployeePayItemId, SourceRef,
             Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
        SELECT  @Id, 'RECOVERY', CASE WHEN c.ItemClass = 'LOAN' THEN 'LOAN' ELSE 'PAY_ITEM' END,
                c.ComponentName, c.ArabicName, c.PayComponentId, i.EmployeePayItemId,
                CASE WHEN c.ItemClass = 'LOAN' THEN ISNULL(i.SourceRef, i.Comment) ELSE i.Comment END,
                i.InstalmentCount - ISNULL(p.PaidCount, 0), i.InstalmentCount, b.Total,
                -(b.Total - ISNULL(p.PaidAmount, 0)),
                c.DisplayOrder, @UserId
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
        CROSS APPLY (SELECT ISNULL(i.TotalAmount, i.Amount * i.InstalmentCount) AS Total) AS b
        WHERE   i.EmployeeId = @EmpId AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
          AND   i.AppliesMode = 'INSTALMENT' AND c.ItemClass IN ('LOAN', 'DEDUCTION')
          AND   b.Total - ISNULL(p.PaidAmount, 0) > 0;

        /* ---- 4. salary a closed payroll paid after the last working day - */
        INSERT INTO [Payroll].[FinalSettlementLines]
            (FinalSettlementId, Section, LineCode, Description, SourceRef, PeriodFrom, PeriodTo, Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
        SELECT  @Id, 'RECOVERY', 'SALARY', N'Salary paid after the last working day', r.RunCode,
                o.OverFrom, o.PaidTo, o.OverDays, re.PaidDays, sp.SalaryPaid,
                -ROUND(sp.SalaryPaid * o.OverDays / re.PaidDays, 3), 5, @UserId
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
        JOIN    [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
        CROSS APPLY (SELECT SUM(l.Amount) AS SalaryPaid FROM [Payroll].[PayrollRunLines] AS l
                     WHERE l.RunEmployeeId = re.RunEmployeeId AND l.Deleted = 0 AND l.ItemClass = 'SALARY') AS sp
        CROSS APPLY (SELECT CASE WHEN re.TerminationDate IS NOT NULL AND re.TerminationDate < p.EndDate THEN re.TerminationDate ELSE p.EndDate END AS PaidTo,
                            CASE WHEN DATEADD(DAY, 1, @LWD) > p.StartDate THEN DATEADD(DAY, 1, @LWD) ELSE p.StartDate END AS OverFrom) AS t
        CROSS APPLY (SELECT t.OverFrom, t.PaidTo, DATEDIFF(DAY, t.OverFrom, t.PaidTo) + 1 AS OverDays) AS o
        WHERE   re.EmployeeId = @EmpId AND re.Deleted = 0 AND re.IsExcluded = 0 AND re.PaidDays > 0
          AND   r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR'
          AND   o.OverDays > 0 AND sp.SalaryPaid > 0;

        /* ---- 5. indemnity --------------------------------------------- */
        IF @Rs IS NOT NULL AND @SvcDays > 0
            INSERT INTO [Payroll].[FinalSettlementLines]
                (FinalSettlementId, Section, LineCode, IsInfo, FromYears, ToYears, Unit, Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
            SELECT  @Id, 'INDEMNITY', 'IND_SLAB', 1, sl.FromYears, sl.ToYears, sl.EntitlementUnit, y.Yrs, sl.EntitlementValue, @IndBase,
                    CASE WHEN sl.EntitlementUnit = 'DAYS'
                         THEN ROUND(y.Yrs * sl.EntitlementValue * @IndBase / @Div, 3)
                         ELSE ROUND(y.Yrs * sl.EntitlementValue * @IndBase, 3) END,
                    sl.DisplayOrder, @UserId
            FROM    [Payroll].[IndemnityServiceSlabs] AS sl
            CROSS APPLY (SELECT CASE WHEN @SvcYears <= sl.FromYears THEN 0
                                     ELSE (CASE WHEN sl.ToYears IS NULL OR @SvcYears < sl.ToYears THEN @SvcYears ELSE sl.ToYears END) - sl.FromYears
                                END AS Yrs) AS y
            WHERE   sl.IndemnityRuleSetId = @Rs AND sl.Deleted = 0 AND y.Yrs > 0;

        /* ---- 6. PIFSS employee share on the pending salary (Kuwaiti) ---- */
        IF @IsKw = 1
        BEGIN
            DECLARE @PifssName NVARCHAR(150), @PifssArabic NVARCHAR(150), @PifssId INT;
            SELECT TOP (1) @PifssId = PayComponentId, @PifssName = ComponentName, @PifssArabic = ArabicName
            FROM   [Payroll].[PayComponents]
            WHERE  CompanyId = @CompanyId AND SystemCode = 'PIFSS_EE' AND Deleted = 0;

            ;WITH b AS (
                SELECT  l.PeriodFrom, l.PeriodTo, SUM(l.Amount) AS Base
                FROM    [Payroll].[FinalSettlementLines] AS l
                JOIN    [Payroll].[PayComponents]        AS c ON c.PayComponentId = l.PayComponentId
                WHERE   l.FinalSettlementId = @Id AND l.Deleted = 0 AND l.Section = 'SALARY' AND c.IsPifssApplicable = 1
                GROUP BY l.PeriodFrom, l.PeriodTo
            ), share AS (
                SELECT  b.PeriodFrom, b.PeriodTo, b.Base,
                        SUM(ROUND(CASE WHEN r.SalaryCeiling IS NOT NULL AND b.Base > r.SalaryCeiling THEN r.SalaryCeiling ELSE b.Base END
                                  * r.EmployeeRate / 100.0, 3)) AS Amt,
                        SUM(r.EmployeeRate) AS Pct
                FROM    b
                JOIN    [Payroll].[PifssContributionRates] AS r
                        ON r.Deleted = 0 AND r.IsActive = 1 AND r.ApplicableTo = 'KUWAITI'
                       AND r.EffectiveFrom <= b.PeriodTo AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= b.PeriodTo)
                WHERE   b.Base > 0
                GROUP BY b.PeriodFrom, b.PeriodTo, b.Base
            )
            INSERT INTO [Payroll].[FinalSettlementLines]
                (FinalSettlementId, Section, LineCode, Description, ArabicDescription, PayComponentId, PeriodFrom, PeriodTo, Rate, Basis, Amount, DisplayOrder, CreatedBy)
            SELECT  @Id, 'RECOVERY', 'PIFSS', ISNULL(@PifssName, N'PIFSS employee share'), @PifssArabic, @PifssId,
                    s.PeriodFrom, s.PeriodTo, s.Pct, s.Base, -s.Amt, 900, @UserId
            FROM    share AS s
            WHERE   s.Amt > 0;
        END;
    END;

    /* ---- 7. leave encashment (every type) ------------------------------- */
    IF @Encash > 0 AND @LeaveBase > 0
        INSERT INTO [Payroll].[FinalSettlementLines]
            (FinalSettlementId, Section, LineCode, Quantity, Rate, Basis, Amount, DisplayOrder, CreatedBy)
        VALUES (@Id, 'LEAVE', 'LEAVE', @Encash, @Div, @LeaveBase, ROUND(@LeaveBase * @Encash / @Div, 3), 1, @UserId);

    /* ---- waived lines stay waived ---------------------------------------- */
    UPDATE l SET IsIncluded = 0
    FROM   [Payroll].[FinalSettlementLines] AS l
    WHERE  l.FinalSettlementId = @Id AND l.Deleted = 0 AND l.IsManual = 0
      AND  EXISTS (SELECT 1 FROM @Waived AS w
                   WHERE w.LineCode = l.LineCode AND w.EmployeePayItemId = l.EmployeePayItemId
                     AND (w.PeriodFrom = l.PeriodFrom OR (w.PeriodFrom IS NULL AND l.PeriodFrom IS NULL)));

    /* ---- indemnity payable ------------------------------------------------ */
    DECLARE @IndGross DECIMAL(12,3) = 0, @Cap DECIMAL(12,3) = NULL, @Pct DECIMAL(7,4) = 0, @IndAmount DECIMAL(12,3) = 0, @BelowMin BIT = 0;
    IF @IsExit = 1 AND @Rs IS NOT NULL
    BEGIN
        SELECT @IndGross = ISNULL(SUM(Amount), 0)
        FROM   [Payroll].[FinalSettlementLines]
        WHERE  FinalSettlementId = @Id AND Deleted = 0 AND LineCode = 'IND_SLAB';

        SET @Cap = CASE WHEN @CapMonths IS NULL THEN NULL ELSE ROUND(@CapMonths * @IndBase, 3) END;

        SELECT TOP (1) @Pct = f.EntitlementPercent
        FROM   [Payroll].[IndemnityEntitlementFactors] AS f
        WHERE  f.IndemnityRuleSetId = @Rs AND f.Deleted = 0 AND f.SeparationType = @Type
          AND  f.FromYears <= @SvcYears AND (f.ToYears IS NULL OR @SvcYears < f.ToYears)
        ORDER BY f.FromYears DESC;
        IF @@ROWCOUNT = 0 SET @Pct = 100;

        IF @MinSvc IS NOT NULL AND @SvcDays < @MinSvc * 30.4375 SET @BelowMin = 1;

        SET @IndAmount = CASE WHEN @BelowMin = 1 THEN 0
                              ELSE ROUND(CASE WHEN @Cap IS NOT NULL AND @IndGross > @Cap THEN @Cap ELSE @IndGross END * @Pct / 100.0, 3) END;
    END;

    /* ---- totals ----------------------------------------------------------- */
    DECLARE @PendingAmt DECIMAL(12,3), @EarnAmt DECIMAL(12,3), @LeaveAmt DECIMAL(12,3), @RecAmt DECIMAL(12,3);
    SELECT  @PendingAmt = ISNULL(SUM(CASE WHEN Section = 'SALARY'   THEN Amount END), 0),
            @EarnAmt    = ISNULL(SUM(CASE WHEN Section = 'EARNING'  THEN Amount END), 0),
            @LeaveAmt   = ISNULL(SUM(CASE WHEN Section = 'LEAVE'    THEN Amount END), 0),
            @RecAmt     = ISNULL(SUM(CASE WHEN Section = 'RECOVERY' THEN Amount END), 0)
    FROM    [Payroll].[FinalSettlementLines]
    WHERE   FinalSettlementId = @Id AND Deleted = 0 AND IsInfo = 0 AND IsIncluded = 1;

    UPDATE [Payroll].[FinalSettlements]
       SET HireDate            = @Hire,
           ServiceDays         = @SvcDays,
           ServiceYears        = @SvcYears,
           WorkPeriodDays      = @WorkDays,
           UnpaidExcludedDays  = ISNULL(@ExclDays, 0),
           LeaveSinceDate      = @LvSince,
           LeaveWorkDays       = @LvWork,
           LeaveActualDays     = @LvActual,
           IsKuwaiti           = @IsKw,
           MonthlySalary       = @Monthly,
           IndemnityBase       = CASE WHEN @IsExit = 1 THEN @IndBase ELSE 0 END,
           LeaveBase           = @LeaveBase,
           DailyDivisor        = @Div,
           SalaryFromProfile   = @FromProfile,
           IndemnityRuleSetId  = CASE WHEN @IsExit = 1 THEN @Rs END,
           RuleSetVerified     = CASE WHEN @IsExit = 1 THEN ISNULL(@Verified, 0) ELSE 1 END,
           IndemnityGross      = @IndGross,
           IndemnityCap        = @Cap,
           IndemnityPercent    = ISNULL(@Pct, 0),
           BelowMinService     = @BelowMin,
           PendingSalaryAmount = @PendingAmt,
           OtherEarningsAmount = @EarnAmt,
           LeaveAmount         = @LeaveAmt,
           IndemnityAmount     = @IndAmount,
           RecoveryAmount      = @RecAmt,
           NetPayable          = @PendingAmt + @EarnAmt + @LeaveAmt + @IndAmount + @RecAmt,
           CalculatedDate      = @Now
    WHERE  FinalSettlementId = @Id;
END;
GO

/* ---- 6. Payroll.usp_FinalSettlement_Manage (db/40) - the form's defaults show both ---- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_FinalSettlement_Manage]
    @Action             VARCHAR(20),
    @Id                 BIGINT          = NULL,

    /* scope and filters */
    @CompanyId          INT             = NULL,     -- the user's own company (company users)
    @CompanyIds         NVARCHAR(2000)  = NULL,     -- the company filter of the top bar
    @TypeFilter         VARCHAR(20)     = NULL,     -- EXIT (every type but ENCASHMENT), ENCASHMENT or one type
    @StatusFilter       VARCHAR(10)     = NULL,     -- OPEN (draft + pending + approved), DRAFT, PENDING, APPROVED, PAID, CANCELLED, ALL
    @Search             NVARCHAR(200)   = NULL,
    @PageNumber         INT             = 1,
    @PageSize           INT             = 25,

    /* settlement */
    @EmployeeId         BIGINT          = NULL,
    @SettlementType     VARCHAR(20)     = NULL,
    @LastWorkingDay     DATE            = NULL,
    @NoticeDate         DATE            = NULL,
    @Reason             NVARCHAR(500)   = NULL,
    @SalaryFrom         DATE            = NULL,
    @LeaveBalanceDays   DECIMAL(7,2)    = NULL,
    @EncashDays         DECIMAL(7,2)    = NULL,
    @PayMonth           DATE            = NULL,

    /* lines */
    @LineId             BIGINT          = NULL,
    @Section            VARCHAR(10)     = NULL,
    @Description        NVARCHAR(300)   = NULL,
    @Amount             DECIMAL(12,3)   = NULL,

    /* workflow */
    @Comment            NVARCHAR(500)   = NULL,
    @AckUnverified      BIT             = 0,
    @AllowSelfApproval  BIT             = 0,
    @ExpectedLevel      TINYINT         = NULL,
    @PaidDate           DATE            = NULL,
    @PaymentMethod      VARCHAR(10)     = NULL,
    @PaymentRef         NVARCHAR(100)   = NULL,
    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    SET @Search        = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @CompanyIds    = NULLIF(LTRIM(RTRIM(@CompanyIds)), N'');
    SET @TypeFilter    = NULLIF(UPPER(LTRIM(RTRIM(@TypeFilter))), '');
    SET @StatusFilter  = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@StatusFilter))), ''), 'ALL');
    SET @SettlementType = NULLIF(UPPER(LTRIM(RTRIM(@SettlementType))), '');
    SET @Reason        = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @Comment       = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Description   = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @PaymentRef    = NULLIF(LTRIM(RTRIM(@PaymentRef)), N'');
    SET @PaymentMethod = NULLIF(UPPER(LTRIM(RTRIM(@PaymentMethod))), '');
    SET @Section       = NULLIF(UPPER(LTRIM(RTRIM(@Section))), '');
    SET @PageNumber    = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 10000 THEN 10000 ELSE @PageSize END;
    IF @PayMonth IS NOT NULL SET @PayMonth = DATEFROMPARTS(YEAR(@PayMonth), MONTH(@PayMonth), 1);

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @CompanyCsv NVARCHAR(2002) = CASE WHEN @CompanyIds IS NULL THEN NULL ELSE ',' + REPLACE(@CompanyIds, ' ', '') + ',' END;

    IF @Action NOT IN ('LIST', 'GET', 'LINES', 'HISTORY', 'SUMMARY', 'EMPLOYEES', 'DEFAULTS', 'SAVE', 'RECALC', 'ADD_LINE', 'REMOVE_LINE',
                       'TOGGLE_LINE', 'SUBMIT', 'APPROVE', 'RETURN', 'REJECT', 'PAY', 'CANCEL')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
        SELECT  s.FinalSettlementId, s.SettlementNo, s.CompanyId, co.CompanyName, s.EmployeeId, e.EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                d.DepartmentName, s.SettlementType, s.Status, s.ApprovalLevel, s.LastWorkingDay, s.ServiceDays, s.ServiceYears,
                s.EncashDays, s.PayMonth, s.NetPayable, s.PaidDate, s.PaymentMethod, s.SubmittedBy, s.CreatedDate, s.RuleSetVerified
        INTO    #L
        FROM    [Payroll].[FinalSettlements] AS s
        JOIN    [Employee].[Employees]       AS e  ON e.EmployeeId = s.EmployeeId
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = s.CompanyId
        LEFT JOIN [Core].[Departments]       AS d  ON d.DepartmentId = e.DepartmentId
        WHERE   s.Deleted = 0
          AND   (@CompanyId  IS NULL OR s.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(s.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0)
          AND   (@EmployeeId IS NULL OR s.EmployeeId = @EmployeeId)
          AND   (@TypeFilter IS NULL OR (@TypeFilter = 'EXIT' AND s.SettlementType <> 'ENCASHMENT') OR s.SettlementType = @TypeFilter)
          AND   (@StatusFilter = 'ALL' OR (@StatusFilter = 'OPEN' AND s.Status IN ('DRAFT', 'PENDING', 'APPROVED')) OR s.Status = @StatusFilter)
          AND   (@Pattern IS NULL OR s.SettlementNo LIKE @Pattern ESCAPE '\' OR e.EmployeeNo LIKE @Pattern ESCAPE '\'
                 OR CONCAT(e.FirstName, N' ', e.LastName) LIKE @Pattern ESCAPE '\' OR e.ArabicName LIKE @Pattern ESCAPE '\');

        SELECT @TotalCount = COUNT(1) FROM #L;
        SELECT * FROM #L
        ORDER BY CASE Status WHEN 'PENDING' THEN 0 WHEN 'DRAFT' THEN 1 WHEN 'APPROVED' THEN 2 ELSE 3 END,
                 LastWorkingDay DESC, FinalSettlementId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= SUMMARY (KPIs) ====================== */
    IF @Action = 'SUMMARY'
    BEGIN
        DECLARE @YearStart DATE = DATEFROMPARTS(YEAR(@Today), 1, 1);
        SELECT  COUNT(CASE WHEN s.Status = 'DRAFT' THEN 1 END)                                          AS DraftCount,
                COUNT(CASE WHEN s.Status = 'PENDING' THEN 1 END)                                        AS PendingCount,
                COUNT(CASE WHEN s.Status = 'PENDING' AND s.ApprovalLevel = 0 THEN 1 END)                AS PendingHrCount,
                COUNT(CASE WHEN s.Status = 'PENDING' AND s.ApprovalLevel = 1 THEN 1 END)                AS PendingFinanceCount,
                COUNT(CASE WHEN s.Status = 'APPROVED' THEN 1 END)                                       AS ApprovedCount,
                ISNULL(SUM(CASE WHEN s.Status = 'APPROVED' THEN s.NetPayable END), 0)                   AS ApprovedAmount,
                COUNT(CASE WHEN s.Status = 'PAID' AND s.PaidDate >= @YearStart THEN 1 END)              AS PaidCount,
                ISNULL(SUM(CASE WHEN s.Status = 'PAID' AND s.PaidDate >= @YearStart THEN s.NetPayable END), 0) AS PaidAmount,
                ISNULL(SUM(CASE WHEN s.Status IN ('DRAFT', 'PENDING', 'APPROVED') THEN s.IndemnityAmount END), 0) AS OpenIndemnity
        FROM    [Payroll].[FinalSettlements] AS s
        WHERE   s.Deleted = 0
          AND   (@CompanyId  IS NULL OR s.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(s.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);
        RETURN;
    END;

    /* ======================= EMPLOYEES (wizard picker) =========== */
    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName,
                e.ArabicName AS EmployeeArabicName, e.CompanyId, e.EmploymentStatus, e.HireDate,
                x.SettlementNo AS OpenSettlementNo, x.FinalSettlementId AS OpenSettlementId
        FROM    [Employee].[Employees] AS e
        OUTER APPLY (SELECT TOP (1) s.SettlementNo, s.FinalSettlementId FROM [Payroll].[FinalSettlements] AS s
                     WHERE s.EmployeeId = e.EmployeeId AND s.Deleted = 0 AND s.SettlementType <> 'ENCASHMENT' AND s.Status <> 'CANCELLED') AS x
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0
          AND   (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0)
        ORDER BY e.FirstName, e.LastName, e.EmployeeNo;
        RETURN;
    END;

    /* ======================= DEFAULTS (wizard step 1) ============ */
    IF @Action = 'DEFAULTS'
    BEGIN
        DECLARE @dHire DATE, @dComp INT, @dLwd DATE = ISNULL(@LastWorkingDay, @Today);
        SELECT  @dHire = e.HireDate, @dComp = e.CompanyId
        FROM    [Employee].[Employees] AS e
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
          AND   (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);
        IF @dComp IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select an employee.';
            RETURN;
        END;

        DECLARE @dPaidTo DATE, @dRun NVARCHAR(40);
        SELECT TOP (1) @dPaidTo = p.EndDate, @dRun = r.RunCode
        FROM   [Payroll].[PayrollRunEmployees] AS re
        JOIN   [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
        JOIN   [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
        WHERE  re.EmployeeId = @EmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
          AND  r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR'
        ORDER BY p.EndDate DESC;

        DECLARE @dLwdMonth DATE = DATEFROMPARTS(YEAR(@dLwd), MONTH(@dLwd), 1);
        DECLARE @dFrom DATE = CASE WHEN @dPaidTo IS NOT NULL THEN DATEADD(DAY, 1, @dPaidTo)
                                   WHEN @dHire > @dLwdMonth THEN @dHire ELSE @dLwdMonth END;
        IF @dHire IS NOT NULL AND @dFrom < @dHire SET @dFrom = @dHire;
        IF @dFrom > DATEADD(DAY, 1, @dLwd) SET @dFrom = DATEADD(DAY, 1, @dLwd);

        DECLARE @dRs NVARCHAR(30), @dVerified BIT;
        SELECT TOP (1) @dRs = r.RuleSetCode, @dVerified = r.IsVerified
        FROM   [Payroll].[IndemnityRuleSets] AS r
        WHERE  r.Deleted = 0 AND r.IsActive = 1 AND r.EffectiveFrom <= @dLwd AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @dLwd)
        ORDER BY r.EffectiveFrom DESC, r.IndemnityRuleSetId DESC;

        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.HireDate, e.EmploymentStatus, e.NoticePeriodDays, d.DepartmentName, ds.DesignationName,
                /* db/106: actual working days (unpaid absences over a month left out) vs the work period */
                ISNULL(sp.ActualDays, 0) AS ServiceDays, ISNULL(sp.WorkDays, 0) AS WorkPeriodDays, ISNULL(sp.ExcludedDays, 0) AS UnpaidExcludedDays,
                ls.SinceDate AS LeaveSinceDate, ls.WorkDays AS LeaveWorkDays, ls.ActualDays AS LeaveActualDays, lb.AnnualBalance,
                sal.MonthlySalary, sal.IndemnityBase, sal.LeaveBase,
                @dPaidTo AS PaidThrough, @dRun AS PaidByRun, @dFrom AS DefaultSalaryFrom,
                @dRs AS RuleSetCode, ISNULL(@dVerified, 0) AS RuleSetVerified,
                x.SettlementNo AS OpenSettlementNo, x.FinalSettlementId AS OpenSettlementId
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Core].[Departments]  AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Core].[Designations] AS ds ON ds.DesignationId = e.DesignationId
        OUTER APPLY (SELECT ISNULL(SUM(f.Amount), 0) AS MonthlySalary,
                            ISNULL(NULLIF(SUM(CASE WHEN f.IsIndemnityApplicable = 1 THEN f.Amount END), 0), ISNULL(SUM(f.Amount), 0)) AS IndemnityBase,
                            ISNULL(NULLIF(SUM(CASE WHEN f.IsLeaveSalaryApplicable = 1 THEN f.Amount END), 0), ISNULL(SUM(f.Amount), 0)) AS LeaveBase
                     FROM [Payroll].[ufn_FinalSettlement_Salary](@EmployeeId, @dLwdMonth) AS f) AS sal
        OUTER APPLY (SELECT TOP (1) s.SettlementNo, s.FinalSettlementId FROM [Payroll].[FinalSettlements] AS s
                     WHERE s.EmployeeId = e.EmployeeId AND s.Deleted = 0 AND s.SettlementType <> 'ENCASHMENT' AND s.Status <> 'CANCELLED') AS x
        OUTER APPLY (SELECT * FROM [Leave].[tvf_ServicePeriod](e.EmployeeId, e.HireDate, @dLwd) WHERE e.HireDate IS NOT NULL AND e.HireDate <= @dLwd) AS sp
        OUTER APPLY (SELECT * FROM [Leave].[tvf_LeaveServiceSince](e.EmployeeId, @dLwd)) AS ls
        OUTER APPLY (SELECT SUM(b.Available) AS AnnualBalance
                     FROM   [Leave].[tvf_Balances](@dLwd, e.EmployeeId) AS b
                     JOIN   [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
                     WHERE  t.Category = 'ANNUAL') AS lb
        WHERE   e.EmployeeId = @EmployeeId;
        RETURN;
    END;

    /* ---------------- the settlement being worked on ---------------- */
    DECLARE @sComp INT, @sEmp BIGINT, @sNo NVARCHAR(30), @sType VARCHAR(20), @sStatus VARCHAR(10), @sLevel TINYINT,
            @sLwd DATE, @sFrom DATE, @sNet DECIMAL(12,3), @sSubmittedBy BIGINT, @sSubmittedDate DATETIME2(0),
            @sVerified BIT, @sRs INT, @sPayMonth DATE, @sEncash DECIMAL(7,2);
    IF @Id IS NOT NULL AND @Id > 0
        SELECT  @sComp = s.CompanyId, @sEmp = s.EmployeeId, @sNo = s.SettlementNo, @sType = s.SettlementType, @sStatus = s.Status,
                @sLevel = s.ApprovalLevel, @sLwd = s.LastWorkingDay, @sFrom = s.SalaryFrom, @sNet = s.NetPayable,
                @sSubmittedBy = s.SubmittedBy, @sSubmittedDate = s.SubmittedDate, @sVerified = s.RuleSetVerified,
                @sRs = s.IndemnityRuleSetId, @sPayMonth = s.PayMonth, @sEncash = s.EncashDays
        FROM    [Payroll].[FinalSettlements] AS s
        WHERE   s.FinalSettlementId = @Id AND s.Deleted = 0
          AND   (@CompanyId  IS NULL OR s.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(s.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);

    IF @Action <> 'SAVE' OR ISNULL(@Id, 0) > 0
    BEGIN
        IF @sStatus IS NULL
        BEGIN
            IF @Action IN ('GET', 'LINES', 'HISTORY') RETURN;
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This settlement no longer exists.';
            RETURN;
        END;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  s.*, co.CompanyName, CAST(NULL AS NVARCHAR(200)) AS CompanyArabicName, co.CompanyCode,   -- Core.Companies has no Arabic name column
                e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.EmploymentStatus, e.NoticePeriodDays, d.DepartmentName, CAST(NULL AS NVARCHAR(200)) AS DepartmentArabicName,   -- nor Core.Departments
                ds.DesignationName, ds.ArabicName AS DesignationArabicName, n.CountryName AS NationalityName,
                rs.RuleSetCode, rs.RuleSetName, pi.StartMonth AS PayItemMonth,
                paid.PaidThrough, paid.PaidByRun,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue1.FirstName, N' ', ue1.LastName))), N''), u1.Username) AS SubmittedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue2.FirstName, N' ', ue2.LastName))), N''), u2.Username) AS ApprovedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue3.FirstName, N' ', ue3.LastName))), N''), u3.Username) AS PaidByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue4.FirstName, N' ', ue4.LastName))), N''), u4.Username) AS CreatedByName
        FROM    [Payroll].[FinalSettlements] AS s
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = s.CompanyId
        JOIN    [Employee].[Employees]       AS e  ON e.EmployeeId = s.EmployeeId
        LEFT JOIN [Core].[Departments]       AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Core].[Designations]      AS ds ON ds.DesignationId = e.DesignationId
        LEFT JOIN [Core].[Countries]         AS n  ON n.CountryId = e.NationalityCountryId
        LEFT JOIN [Payroll].[IndemnityRuleSets] AS rs ON rs.IndemnityRuleSetId = s.IndemnityRuleSetId
        LEFT JOIN [Payroll].[EmployeePayItems]  AS pi ON pi.EmployeePayItemId = s.PayItemId
        LEFT JOIN [Security].[Users] AS u1 ON u1.UserId = s.SubmittedBy LEFT JOIN [Employee].[Employees] AS ue1 ON ue1.EmployeeId = u1.EmployeeId
        LEFT JOIN [Security].[Users] AS u2 ON u2.UserId = s.ApprovedBy  LEFT JOIN [Employee].[Employees] AS ue2 ON ue2.EmployeeId = u2.EmployeeId
        LEFT JOIN [Security].[Users] AS u3 ON u3.UserId = s.PaidBy      LEFT JOIN [Employee].[Employees] AS ue3 ON ue3.EmployeeId = u3.EmployeeId
        LEFT JOIN [Security].[Users] AS u4 ON u4.UserId = s.CreatedBy   LEFT JOIN [Employee].[Employees] AS ue4 ON ue4.EmployeeId = u4.EmployeeId
        OUTER APPLY (SELECT TOP (1) p.EndDate AS PaidThrough, r.RunCode AS PaidByRun
                     FROM   [Payroll].[PayrollRunEmployees] AS re
                     JOIN   [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
                     JOIN   [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
                     WHERE  re.EmployeeId = s.EmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
                       AND  r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR'
                     ORDER BY p.EndDate DESC) AS paid
        WHERE   s.FinalSettlementId = @Id;
        RETURN;
    END;

    /* ======================= LINES =============================== */
    IF @Action = 'LINES'
    BEGIN
        SELECT  l.SettlementLineId, l.FinalSettlementId, l.Section, l.LineCode, l.IsManual, l.IsInfo, l.IsIncluded,
                l.Description, l.ArabicDescription, l.PayComponentId, l.EmployeePayItemId, l.SourceRef,
                l.PeriodFrom, l.PeriodTo, l.Quantity, l.Rate, l.Basis, l.FromYears, l.ToYears, l.Unit, l.Amount, l.DisplayOrder
        FROM    [Payroll].[FinalSettlementLines] AS l
        WHERE   l.FinalSettlementId = @Id AND l.Deleted = 0
        ORDER BY CASE l.Section WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'LEAVE' THEN 3 WHEN 'INDEMNITY' THEN 4 ELSE 5 END,
                 l.IsManual, l.PeriodFrom, l.DisplayOrder, l.FromYears, l.SettlementLineId;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT  h.SettlementHistoryId, h.FinalSettlementId, h.ActionCode, h.ApprovalLevel, h.NetPayable, h.Comment, h.ActionBy, h.ActionDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Payroll].[FinalSettlementHistory] AS h
        LEFT JOIN [Security].[Users]     AS u  ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   h.FinalSettlementId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate DESC, h.SettlementHistoryId DESC;
        RETURN;
    END;

    /* =============================================================
       Changes
       ============================================================= */

    /* only a draft can be changed */
    IF @Action IN ('RECALC', 'ADD_LINE', 'REMOVE_LINE', 'TOGGLE_LINE', 'SUBMIT') AND @sStatus <> 'DRAFT'
    BEGIN
        SELECT @ResultCode = 'NOT_DRAFT', @ResultMessage = N'Only a draft settlement can be changed. Return it to draft first.';
        RETURN;
    END;

    /* ======================= SAVE ================================ */
    IF @Action = 'SAVE'
    BEGIN
        DECLARE @New BIT = CASE WHEN ISNULL(@Id, 0) > 0 THEN 0 ELSE 1 END;
        IF @New = 0
        BEGIN
            IF @sStatus <> 'DRAFT'
            BEGIN
                SELECT @ResultCode = 'NOT_DRAFT', @ResultMessage = N'Only a draft settlement can be changed. Return it to draft first.';
                RETURN;
            END;
            IF @EmployeeId IS NOT NULL AND @EmployeeId <> @sEmp
            BEGIN
                SELECT @ResultCode = 'EMPLOYEE_LOCKED', @ResultMessage = N'The employee of a settlement cannot be changed. Cancel it and start a new one.';
                RETURN;
            END;
            SET @EmployeeId = @sEmp;
            IF @SettlementType IS NULL SET @SettlementType = @sType;
            IF (@SettlementType = 'ENCASHMENT' AND @sType <> 'ENCASHMENT') OR (@SettlementType <> 'ENCASHMENT' AND @sType = 'ENCASHMENT')
            BEGIN
                SELECT @ResultCode = 'TYPE_LOCKED', @ResultMessage = N'A leave encashment cannot be turned into an exit settlement (or back). Cancel it and start a new one.';
                RETURN;
            END;
        END;

        /* ---- employee ---- */
        DECLARE @eComp INT, @eHire DATE, @eStatus NVARCHAR(20), @eTerm DATE;
        SELECT  @eComp = e.CompanyId, @eHire = e.HireDate, @eStatus = e.EmploymentStatus, @eTerm = e.TerminationDate
        FROM    [Employee].[Employees] AS e
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
          AND   (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyCsv IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', @CompanyCsv) > 0);
        IF @eComp IS NULL
        BEGIN
            SELECT @ResultCode = 'EMPLOYEE_REQUIRED', @ResultMessage = N'Select an employee.';
            RETURN;
        END;
        IF @eHire IS NULL
        BEGIN
            SELECT @ResultCode = 'NO_HIRE_DATE', @ResultMessage = N'The employee has no hire date. Enter it on the Employment tab of the employee profile first.';
            RETURN;
        END;

        /* ---- type and dates ---- */
        IF @SettlementType IS NULL OR @SettlementType NOT IN ('RESIGNATION', 'TERMINATION', 'CONTRACT_END', 'RETIREMENT', 'DEATH', 'DISABILITY', 'ENCASHMENT')
        BEGIN
            SELECT @ResultCode = 'TYPE_REQUIRED', @ResultMessage = N'Select the separation type.';
            RETURN;
        END;
        DECLARE @IsExit BIT = CASE WHEN @SettlementType = 'ENCASHMENT' THEN 0 ELSE 1 END;
        IF @IsExit = 0 SET @LastWorkingDay = ISNULL(@LastWorkingDay, @Today);
        IF @LastWorkingDay IS NULL
        BEGIN
            SELECT @ResultCode = 'LWD_REQUIRED', @ResultMessage = N'Enter the last working day.';
            RETURN;
        END;
        IF @LastWorkingDay < @eHire
        BEGIN
            SELECT @ResultCode = 'LWD_BEFORE_HIRE', @ResultMessage = N'The last working day cannot be before the hire date.';
            RETURN;
        END;
        IF @LastWorkingDay > DATEADD(YEAR, 1, @Today)
        BEGIN
            SELECT @ResultCode = 'LWD_TOO_FAR', @ResultMessage = N'The last working day cannot be more than a year ahead.';
            RETURN;
        END;
        IF @NoticeDate IS NOT NULL AND @NoticeDate > @LastWorkingDay
        BEGIN
            SELECT @ResultCode = 'NOTICE_AFTER_LWD', @ResultMessage = N'The notice date cannot be after the last working day.';
            RETURN;
        END;
        IF @IsExit = 0 SET @NoticeDate = NULL;

        /* ---- one live exit settlement per employee ---- */
        IF @IsExit = 1 AND EXISTS (SELECT 1 FROM [Payroll].[FinalSettlements] AS x
                                   WHERE x.EmployeeId = @EmployeeId AND x.Deleted = 0 AND x.SettlementType <> 'ENCASHMENT'
                                     AND x.Status <> 'CANCELLED' AND x.FinalSettlementId <> ISNULL(@Id, 0))
        BEGIN
            SELECT @ResultCode = 'EXISTS', @ResultMessage = N'This employee already has a final settlement. Open it from the list, or cancel it to start again.';
            RETURN;
        END;
        IF @IsExit = 0 AND @eStatus IN (N'Terminated', N'Resigned')
        BEGIN
            SELECT @ResultCode = 'EMPLOYEE_LEFT', @ResultMessage = N'This employee has left. Encash the leave in the final settlement instead.';
            RETURN;
        END;

        /* ---- leave ---- */
        SET @LeaveBalanceDays = ISNULL(@LeaveBalanceDays, 0);
        SET @EncashDays = ISNULL(@EncashDays, CASE WHEN @IsExit = 1 THEN @LeaveBalanceDays ELSE 0 END);
        IF @LeaveBalanceDays < 0 OR @LeaveBalanceDays > 999 OR @EncashDays < 0
        BEGIN
            SELECT @ResultCode = 'LEAVE_INVALID', @ResultMessage = N'Enter a leave balance between 0 and 999 days.';
            RETURN;
        END;
        IF @EncashDays > @LeaveBalanceDays
        BEGIN
            SELECT @ResultCode = 'ENCASH_ABOVE_BALANCE', @ResultMessage = N'The days to encash cannot be more than the leave balance.';
            RETURN;
        END;

        /* ---- encashment: the payroll month that pays it ---- */
        IF @IsExit = 0
        BEGIN
            IF @EncashDays <= 0
            BEGIN
                SELECT @ResultCode = 'ENCASH_REQUIRED', @ResultMessage = N'Enter the number of days to encash.';
                RETURN;
            END;
            IF @PayMonth IS NULL
            BEGIN
                SELECT @ResultCode = 'PAY_MONTH_REQUIRED', @ResultMessage = N'Select the payroll month that pays the encashment.';
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r
                       WHERE r.CompanyId = @eComp AND r.Deleted = 0 AND r.RunType = 'REGULAR' AND r.Stage = 'CLOSED' AND r.RunMonth = @PayMonth)
            BEGIN
                SELECT @ResultCode = 'MONTH_CLOSED', @ResultMessage = N'The payroll of that month is already closed. Choose a later month.';
                RETURN;
            END;
            SET @SalaryFrom = NULL;
        END
        ELSE
        BEGIN
            SET @PayMonth = NULL;

            /* ---- salary unpaid from: after the last closed payroll that paid the employee ---- */
            DECLARE @PaidTo DATE, @PaidRun NVARCHAR(40);
            SELECT TOP (1) @PaidTo = p.EndDate, @PaidRun = r.RunCode
            FROM   [Payroll].[PayrollRunEmployees] AS re
            JOIN   [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
            JOIN   [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
            WHERE  re.EmployeeId = @EmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
              AND  r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR'
            ORDER BY p.EndDate DESC;

            DECLARE @LwdMonth DATE = DATEFROMPARTS(YEAR(@LastWorkingDay), MONTH(@LastWorkingDay), 1);
            DECLARE @NextDay DATE = DATEADD(DAY, 1, @LastWorkingDay);
            DECLARE @MinFrom DATE = CASE WHEN @PaidTo IS NOT NULL AND DATEADD(DAY, 1, @PaidTo) > @eHire THEN DATEADD(DAY, 1, @PaidTo) ELSE @eHire END;
            IF @MinFrom > @NextDay SET @MinFrom = @NextDay;

            IF @SalaryFrom IS NULL
            BEGIN
                SET @SalaryFrom = CASE WHEN @PaidTo IS NOT NULL THEN @MinFrom
                                       WHEN @eHire > @LwdMonth THEN @eHire ELSE @LwdMonth END;
                IF @SalaryFrom > @NextDay SET @SalaryFrom = @NextDay;
            END;
            IF @SalaryFrom < @MinFrom
            BEGIN
                SET @ResultCode = 'SALARY_ALREADY_PAID';
                SET @ResultMessage = CASE WHEN @PaidTo IS NOT NULL AND @SalaryFrom > @PaidTo THEN N'Salary unpaid from cannot be before the hire date.'
                                          WHEN @PaidTo IS NOT NULL
                                          THEN CONCAT(N'Salary is already paid up to ', FORMAT(@PaidTo, 'dd MMM yyyy', 'en-US'), N' by payroll ', @PaidRun, N'. Salary unpaid from must be after it.')
                                          ELSE N'Salary unpaid from cannot be before the hire date.' END;
                RETURN;
            END;
            IF @SalaryFrom > @NextDay
            BEGIN
                SELECT @ResultCode = 'SALARY_FROM_AFTER_LWD', @ResultMessage = N'Salary unpaid from cannot be after the day following the last working day.';
                RETURN;
            END;
            IF @SalaryFrom < DATEADD(YEAR, -1, @LastWorkingDay)
            BEGIN
                SELECT @ResultCode = 'SALARY_FROM_TOO_EARLY', @ResultMessage = N'Salary unpaid from cannot be more than 12 months before the last working day.';
                RETURN;
            END;
        END;

        BEGIN TRANSACTION;
            IF @New = 1
            BEGIN
                /* FS-YYYY-MM-NNN, numbered per company and month of the last working day */
                DECLARE @Seq SMALLINT, @Prefix NVARCHAR(20) = CONCAT(N'FS-', FORMAT(@LastWorkingDay, 'yyyy-MM', 'en-US'), N'-');
                SELECT @Seq = ISNULL(MAX(x.SettlementSeq), 0) + 1
                FROM   [Payroll].[FinalSettlements] AS x WITH (UPDLOCK, HOLDLOCK)
                WHERE  x.CompanyId = @eComp AND x.SettlementNo LIKE @Prefix + N'%';

                INSERT INTO [Payroll].[FinalSettlements]
                    (CompanyId, EmployeeId, SettlementNo, SettlementSeq, SettlementType, Status, LastWorkingDay, NoticeDate, Reason, SalaryFrom,
                     LeaveBalanceDays, EncashDays, PayMonth, HireDate, CreatedBy)
                VALUES (@eComp, @EmployeeId, CONCAT(@Prefix, RIGHT(CONCAT(N'00', @Seq), 3)), @Seq, @SettlementType, 'DRAFT', @LastWorkingDay,
                        @NoticeDate, @Reason, @SalaryFrom, @LeaveBalanceDays, @EncashDays, @PayMonth, @eHire, @UserId);
                SET @Id = SCOPE_IDENTITY();
            END
            ELSE
                UPDATE [Payroll].[FinalSettlements]
                   SET SettlementType = @SettlementType, LastWorkingDay = @LastWorkingDay, NoticeDate = @NoticeDate, Reason = @Reason,
                       SalaryFrom = @SalaryFrom, LeaveBalanceDays = @LeaveBalanceDays, EncashDays = @EncashDays, PayMonth = @PayMonth,
                       ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  FinalSettlementId = @Id AND Status = 'DRAFT';

            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId;

            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, NetPayable, Comment, ActionBy)
            SELECT @Id, CASE WHEN @New = 1 THEN 'CREATED' ELSE 'CHANGED' END, NetPayable, @Reason, @UserId
            FROM   [Payroll].[FinalSettlements] WHERE FinalSettlementId = @Id;
        COMMIT TRANSACTION;

        SELECT @NewId = @Id, @ResultMessage = CASE WHEN @New = 1 THEN N'Settlement created and calculated.' ELSE N'Settlement saved and recalculated.' END;
        RETURN;
    END;

    /* ======================= RECALC ============================== */
    IF @Action = 'RECALC'
    BEGIN
        BEGIN TRANSACTION;
            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Settlement recalculated.';
        RETURN;
    END;

    /* ======================= ADD_LINE / REMOVE_LINE / TOGGLE_LINE == */
    IF @Action = 'ADD_LINE'
    BEGIN
        IF @Section NOT IN ('EARNING', 'RECOVERY') OR @Section IS NULL
        BEGIN
            SELECT @ResultCode = 'SECTION_REQUIRED', @ResultMessage = N'Choose whether the line is paid to the employee or recovered.';
            RETURN;
        END;
        IF @Description IS NULL
        BEGIN
            SELECT @ResultCode = 'DESCRIPTION_REQUIRED', @ResultMessage = N'Enter a description - what is paid or recovered and why.';
            RETURN;
        END;
        IF @Amount IS NULL OR @Amount <= 0 OR @Amount > 999999.999
        BEGIN
            SELECT @ResultCode = 'AMOUNT_INVALID', @ResultMessage = N'Enter an amount greater than zero.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[FinalSettlementLines] (FinalSettlementId, Section, LineCode, IsManual, Description, Amount, DisplayOrder, CreatedBy)
            VALUES (@Id, @Section, 'MANUAL', 1, @Description, CASE WHEN @Section = 'RECOVERY' THEN -@Amount ELSE @Amount END, 500, @UserId);
            SET @NewId = SCOPE_IDENTITY();
            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId;
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, NetPayable, Comment, ActionBy)
            SELECT @Id, 'LINE_ADDED', NetPayable, CONCAT(@Description, N' (', FORMAT(CASE WHEN @Section = 'RECOVERY' THEN -@Amount ELSE @Amount END, 'N3', 'en-US'), N')'), @UserId
            FROM   [Payroll].[FinalSettlements] WHERE FinalSettlementId = @Id;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Line added.';
        RETURN;
    END;

    IF @Action IN ('REMOVE_LINE', 'TOGGLE_LINE')
    BEGIN
        DECLARE @lManual BIT, @lCode VARCHAR(10), @lIncluded BIT, @lDesc NVARCHAR(300), @lAmount DECIMAL(12,3);
        SELECT  @lManual = l.IsManual, @lCode = l.LineCode, @lIncluded = l.IsIncluded, @lDesc = l.Description, @lAmount = l.Amount
        FROM    [Payroll].[FinalSettlementLines] AS l
        WHERE   l.SettlementLineId = @LineId AND l.FinalSettlementId = @Id AND l.Deleted = 0;
        IF @lCode IS NULL
        BEGIN
            SELECT @ResultCode = 'LINE_NOT_FOUND', @ResultMessage = N'This line no longer exists.';
            RETURN;
        END;
        IF @Action = 'REMOVE_LINE' AND @lManual = 0
        BEGIN
            SELECT @ResultCode = 'LINE_AUTOMATIC', @ResultMessage = N'Calculated lines cannot be removed. Change the inputs, or waive a pay item or loan line.';
            RETURN;
        END;
        IF @Action = 'TOGGLE_LINE' AND (@lManual = 1 OR @lCode NOT IN ('PAY_ITEM', 'LOAN'))
        BEGIN
            SELECT @ResultCode = 'LINE_NOT_WAIVABLE', @ResultMessage = N'Only pay item and loan lines can be waived.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            IF @Action = 'REMOVE_LINE'
                UPDATE [Payroll].[FinalSettlementLines] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE SettlementLineId = @LineId;
            ELSE
                UPDATE [Payroll].[FinalSettlementLines] SET IsIncluded = 1 - IsIncluded WHERE SettlementLineId = @LineId;
            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId;
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, NetPayable, Comment, ActionBy)
            SELECT @Id, CASE WHEN @Action = 'REMOVE_LINE' THEN 'LINE_REMOVED' WHEN @lIncluded = 1 THEN 'LINE_WAIVED' ELSE 'LINE_RESTORED' END,
                   NetPayable, CONCAT(@lDesc, N' (', FORMAT(@lAmount, 'N3', 'en-US'), N')'), @UserId
            FROM   [Payroll].[FinalSettlements] WHERE FinalSettlementId = @Id;
        COMMIT TRANSACTION;
        SET @ResultMessage = CASE WHEN @Action = 'REMOVE_LINE' THEN N'Line removed.' WHEN @lIncluded = 1 THEN N'Line waived - it is not recovered or paid.' ELSE N'Line included again.' END;
        RETURN;
    END;

    /* payrolls that pay the employee for days this settlement pays (double payment guard) */
    DECLARE @LiveRun NVARCHAR(40), @ClosedRun NVARCHAR(40);
    IF @Action IN ('SUBMIT', 'APPROVE') AND @sType <> 'ENCASHMENT' AND @sFrom IS NOT NULL AND @sFrom <= @sLwd
    BEGIN
        SELECT TOP (1) @LiveRun = r.RunCode
        FROM   [Payroll].[PayrollRunEmployees] AS re
        JOIN   [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
        JOIN   [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
        WHERE  re.EmployeeId = @sEmp AND re.Deleted = 0 AND re.IsExcluded = 0
          AND  r.Deleted = 0 AND r.RunType = 'REGULAR' AND r.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')
          AND  p.EndDate >= @sFrom
        ORDER BY p.StartDate;

        SELECT TOP (1) @ClosedRun = r.RunCode
        FROM   [Payroll].[PayrollRunEmployees] AS re
        JOIN   [Payroll].[PayrollRuns]         AS r ON r.PayrollRunId = re.PayrollRunId
        JOIN   [Payroll].[PayrollPeriods]      AS p ON p.PayrollPeriodId = r.PayrollPeriodId
        WHERE  re.EmployeeId = @sEmp AND re.Deleted = 0 AND re.IsExcluded = 0 AND re.PaidDays > 0
          AND  r.Deleted = 0 AND r.RunType = 'REGULAR' AND r.Stage = 'CLOSED'
          AND  p.EndDate >= @sFrom
        ORDER BY p.StartDate;

        IF @ClosedRun IS NOT NULL
        BEGIN
            SELECT @ResultCode = 'SALARY_PAID_BY_PAYROLL',
                   @ResultMessage = CONCAT(N'Payroll ', @ClosedRun, N' has already paid salary for days this settlement pays. Change Salary unpaid from and recalculate.');
            RETURN;
        END;
    END;

    /* ======================= SUBMIT ============================== */
    IF @Action = 'SUBMIT'
    BEGIN
        BEGIN TRANSACTION;
            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId;
            SELECT @sVerified = RuleSetVerified, @sRs = IndemnityRuleSetId, @sNet = NetPayable
            FROM   [Payroll].[FinalSettlements] WHERE FinalSettlementId = @Id;

            IF @sType <> 'ENCASHMENT' AND @sRs IS NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'NO_RULE_SET',
                       @ResultMessage = N'No indemnity rule set is in force on the last working day. Add one in Payroll Settings first.';
                RETURN;
            END;
            IF @sVerified = 0 AND ISNULL(@AckUnverified, 0) = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'UNVERIFIED',
                       @ResultMessage = N'The indemnity rule set is not verified yet. Confirm that you have checked the indemnity, then submit again.';
                RETURN;
            END;

            IF @LiveRun IS NOT NULL
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'LIVE_PAYROLL',
                       @ResultMessage = CONCAT(N'Payroll ', @LiveRun, N' still includes this employee for days this settlement pays. Recalculate it on the Payroll Register (or cancel it) first.');
                RETURN;
            END;

            UPDATE [Payroll].[FinalSettlements]
               SET Status = 'PENDING', ApprovalLevel = 0, SubmittedBy = @UserId, SubmittedDate = @Now,
                   AckUnverified = CASE WHEN RuleSetVerified = 0 THEN 1 ELSE 0 END, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  FinalSettlementId = @Id AND Status = 'DRAFT';

            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, ApprovalLevel, NetPayable, Comment, ActionBy)
            VALUES (@Id, 'SUBMITTED', 0, @sNet, @Comment, @UserId);
        COMMIT TRANSACTION;

        SET @ResultMessage = N'Sent for approval to the HR Manager.';
        RETURN;
    END;

    /* ======================= APPROVE ============================= */
    IF @Action = 'APPROVE'
    BEGIN
        IF @sStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This settlement is not waiting for approval.';
            RETURN;
        END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @sLevel
        BEGIN
            SELECT @ResultCode = 'STALE', @ResultMessage = N'This settlement was approved by someone else meanwhile. The page has been refreshed.';
            RETURN;
        END;
        DECLARE @aLevel TINYINT = @sLevel + 1;
        IF @AllowSelfApproval = 0 AND (
               @UserId = @sSubmittedBy
            OR (@aLevel = 2 AND EXISTS (SELECT 1 FROM [Payroll].[FinalSettlementHistory] WHERE FinalSettlementId = @Id AND Deleted = 0
                                        AND ActionCode = 'APPROVED' AND ApprovalLevel = 1 AND ActionBy = @UserId
                                        AND ActionDate >= ISNULL(@sSubmittedDate, '19000101'))))
        BEGIN
            SELECT @ResultCode = 'SEGREGATION',
                   @ResultMessage = N'You cannot approve a settlement you sent for approval or already approved at the previous level.';
            RETURN;
        END;

        /* the amounts must still be the ones sent for approval (a payroll, a pay item
           or a salary change may have moved since) */
        DECLARE @Recheck DECIMAL(12,3);
        BEGIN TRANSACTION;
            EXEC [Payroll].[usp_FinalSettlement_Calculate] @Id = @Id, @UserId = @UserId, @Force = 1;
            SELECT @Recheck = NetPayable FROM [Payroll].[FinalSettlements] WHERE FinalSettlementId = @Id;
            IF @Recheck <> @sNet
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'AMOUNTS_CHANGED',
                       @ResultMessage = CONCAT(N'The settlement now calculates to ', FORMAT(@Recheck, 'N3', 'en-US'), N' instead of ',
                                               FORMAT(@sNet, 'N3', 'en-US'), N' (payroll or pay items changed since it was submitted). Return it to draft, check it and submit it again.');
                RETURN;
            END;
        COMMIT TRANSACTION;

        IF @aLevel < 2
        BEGIN
            BEGIN TRANSACTION;
                UPDATE [Payroll].[FinalSettlements] SET ApprovalLevel = @aLevel, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  FinalSettlementId = @Id AND Status = 'PENDING' AND ApprovalLevel = @sLevel;
                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT @ResultCode = 'STALE', @ResultMessage = N'This settlement was approved by someone else meanwhile. The page has been refreshed.';
                    RETURN;
                END;
                INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, ApprovalLevel, NetPayable, Comment, ActionBy)
                VALUES (@Id, 'APPROVED', @aLevel, @sNet, @Comment, @UserId);
            COMMIT TRANSACTION;
            SELECT @NewId = @aLevel, @ResultMessage = N'Approved. Waiting for the Finance Manager.';
            RETURN;
        END;

        /* ---- final approval ---- */
        IF @LiveRun IS NOT NULL
        BEGIN
            SELECT @ResultCode = 'LIVE_PAYROLL',
                   @ResultMessage = CONCAT(N'Payroll ', @LiveRun, N' still includes this employee for days this settlement pays. Recalculate it on the Payroll Register (or cancel it) first.');
            RETURN;
        END;

        DECLARE @EncComp INT;
        IF @sType = 'ENCASHMENT'
        BEGIN
            IF EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r
                       WHERE r.CompanyId = @sComp AND r.Deleted = 0 AND r.RunType = 'REGULAR' AND r.Stage = 'CLOSED' AND r.RunMonth = @sPayMonth)
            BEGIN
                SELECT @ResultCode = 'MONTH_CLOSED',
                       @ResultMessage = N'The payroll of the month chosen for the encashment is already closed. Return the settlement and choose a later month.';
                RETURN;
            END;
            SELECT TOP (1) @EncComp = PayComponentId FROM [Payroll].[PayComponents]
            WHERE  CompanyId = @sComp AND Deleted = 0 AND (SystemCode = 'LEAVE_ENCASH' OR ComponentCode = N'LEAVE_ENC')
            ORDER BY CASE WHEN SystemCode = 'LEAVE_ENCASH' THEN 0 ELSE 1 END;
        END;

        BEGIN TRANSACTION;
            UPDATE [Payroll].[FinalSettlements]
               SET Status = 'APPROVED', ApprovalLevel = 2, ApprovedBy = @UserId, ApprovedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  FinalSettlementId = @Id AND Status = 'PENDING' AND ApprovalLevel = @sLevel;
            IF @@ROWCOUNT = 0
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'STALE', @ResultMessage = N'This settlement was approved by someone else meanwhile. The page has been refreshed.';
                RETURN;
            END;
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, ApprovalLevel, NetPayable, Comment, ActionBy)
            VALUES (@Id, 'APPROVED', 2, @sNet, @Comment, @UserId);

            IF @sType = 'ENCASHMENT'
            BEGIN
                /* the company has no leave encashment item type yet (added after db/39) */
                IF @EncComp IS NULL
                BEGIN
                    INSERT INTO [Payroll].[PayComponents]
                        (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod,
                         IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable, IsRecurring, IsProrated,
                         ShowOnPayslip, DisplayOrder, SystemCode, IsSystem, Description, IsActive, CreatedBy)
                    VALUES (@sComp, N'LEAVE_ENC', N'Leave Encashment', N'بدل رصيد الإجازات', N'Leave Encashment', 'EARNING', 'VARIABLE', 'AMOUNT',
                            0, 0, 0, 0, 0, 0, 0, 1, 180, 'LEAVE_ENCASH', 1, N'Paid when a leave encashment (Final Settlement) is approved.', 1, @UserId);
                    SET @EncComp = SCOPE_IDENTITY();
                END;

                DECLARE @EncItem BIGINT, @EncComment NVARCHAR(500) =
                    CONCAT(N'Leave encashment ', FORMAT(@sEncash, '0.##', 'en-US'), N' days - ', @sNo);
                INSERT INTO [Payroll].[EmployeePayItems]
                    (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, ApprovalLevel, SourceRef,
                     SubmittedBy, SubmittedDate, CreatedBy)
                VALUES (@sComp, @sEmp, @EncComp, @sNet, 'ONCE', @sPayMonth, @EncComment, 'ACTIVE', 2, @sNo, @sSubmittedBy, @sSubmittedDate, @UserId);
                SET @EncItem = SCOPE_IDENTITY();
                INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, NewAmount, Comment, ActionBy)
                VALUES (@EncItem, @sEmp, 'CREATED', 2, @sNet, @EncComment, @UserId);

                UPDATE [Payroll].[FinalSettlements] SET PayItemId = @EncItem, PaymentMethod = 'PAYROLL' WHERE FinalSettlementId = @Id;
                SET @ResultMessage = N'Approved. The encashment is paid by the payroll of the month chosen.';
            END
            ELSE
            BEGIN
                DECLARE @LwdM DATE = DATEFROMPARTS(YEAR(@sLwd), MONTH(@sLwd), 1);
                DECLARE @EndNote NVARCHAR(500) = CONCAT(N'Settled in final settlement ', @sNo);

                /* the employee leaves on the last working day */
                UPDATE [Employee].[Employees]
                   SET EmploymentStatus = CASE WHEN @sType = 'RESIGNATION' THEN N'Resigned' ELSE N'Terminated' END,
                       TerminationDate  = @sLwd, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  EmployeeId = @sEmp;

                /* pay items and loans the settlement paid or recovered: ended */
                DECLARE @Ended TABLE (EmployeePayItemId BIGINT PRIMARY KEY, Amount DECIMAL(12,3));
                UPDATE i SET Status = 'ENDED', ModifiedBy = @UserId, ModifiedDate = @Now
                OUTPUT inserted.EmployeePayItemId, inserted.Amount INTO @Ended
                FROM   [Payroll].[EmployeePayItems] AS i
                WHERE  i.EmployeeId = @sEmp AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
                  AND  (   EXISTS (SELECT 1 FROM [Payroll].[FinalSettlementLines] AS l
                                   WHERE l.FinalSettlementId = @Id AND l.Deleted = 0 AND l.IsIncluded = 1
                                     AND l.EmployeePayItemId = i.EmployeePayItemId AND l.LineCode IN ('PAY_ITEM', 'LOAN')
                                     AND i.AppliesMode IN ('ONCE', 'INSTALMENT'))
                        OR i.StartMonth > @LwdM);

                /* monthly items stop after the month of the last working day */
                UPDATE i SET EndMonth = @LwdM, ModifiedBy = @UserId, ModifiedDate = @Now
                OUTPUT inserted.EmployeePayItemId, inserted.Amount INTO @Ended
                FROM   [Payroll].[EmployeePayItems] AS i
                WHERE  i.EmployeeId = @sEmp AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
                  AND  i.AppliesMode = 'MONTHLY' AND i.StartMonth <= @LwdM AND (i.EndMonth IS NULL OR i.EndMonth > @LwdM);

                INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                SELECT EmployeePayItemId, @sEmp, 'ENDED', Amount, @EndNote, @UserId FROM @Ended;

                SET @ResultMessage = N'Approved. The employee is marked as left and the settlement is ready to be paid.';
            END;
        COMMIT TRANSACTION;
        SET @NewId = 2;
        RETURN;
    END;

    /* ======================= RETURN / REJECT ===================== */
    IF @Action IN ('RETURN', 'REJECT')
    BEGIN
        IF @sStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This settlement is not waiting for approval.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED',
                   @ResultMessage = CASE WHEN @Action = 'RETURN' THEN N'Enter a comment explaining what needs to be corrected.' ELSE N'Enter the reason for rejecting it.' END;
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Payroll].[FinalSettlements]
               SET Status = CASE WHEN @Action = 'RETURN' THEN 'DRAFT' ELSE 'CANCELLED' END, ApprovalLevel = 0,
                   CancelledBy = CASE WHEN @Action = 'REJECT' THEN @UserId END,
                   CancelledDate = CASE WHEN @Action = 'REJECT' THEN @Now END,
                   CancelReason = CASE WHEN @Action = 'REJECT' THEN @Comment END,
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  FinalSettlementId = @Id AND Status = 'PENDING';
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, ApprovalLevel, NetPayable, Comment, ActionBy)
            VALUES (@Id, CASE WHEN @Action = 'RETURN' THEN 'RETURNED' ELSE 'REJECTED' END, @sLevel, @sNet, @Comment, @UserId);
        COMMIT TRANSACTION;
        SET @ResultMessage = CASE WHEN @Action = 'RETURN' THEN N'Returned to draft with your comment.' ELSE N'Settlement rejected and cancelled.' END;
        RETURN;
    END;

    /* ======================= PAY ================================= */
    IF @Action = 'PAY'
    BEGIN
        IF @sStatus <> 'APPROVED'
        BEGIN
            SELECT @ResultCode = 'NOT_APPROVED', @ResultMessage = N'Only an approved settlement can be marked as paid.';
            RETURN;
        END;
        IF @PaidDate IS NULL OR @PaidDate > @Today
        BEGIN
            SELECT @ResultCode = 'PAID_DATE_INVALID', @ResultMessage = N'Enter the payment date (today or earlier).';
            RETURN;
        END;
        IF @PaymentMethod IS NULL OR @PaymentMethod NOT IN ('BANK', 'CHEQUE', 'CASH', 'PAYROLL')
        BEGIN
            SELECT @ResultCode = 'METHOD_REQUIRED', @ResultMessage = N'Select how it was paid.';
            RETURN;
        END;
        IF @PaymentMethod IN ('BANK', 'CHEQUE') AND @PaymentRef IS NULL
        BEGIN
            SELECT @ResultCode = 'REF_REQUIRED', @ResultMessage = N'Enter the bank transfer or cheque reference.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Payroll].[FinalSettlements]
               SET Status = 'PAID', PaidDate = @PaidDate, PaymentMethod = @PaymentMethod, PaymentRef = @PaymentRef, PaidBy = @UserId,
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  FinalSettlementId = @Id AND Status = 'APPROVED';
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, NetPayable, Comment, ActionBy)
            VALUES (@Id, 'PAID', @sNet, CONCAT_WS(N' · ', @PaymentMethod, @PaymentRef, @Comment), @UserId);
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Payment recorded. The settlement is closed.';
        RETURN;
    END;

    /* ======================= CANCEL ============================== */
    IF @Action = 'CANCEL'
    BEGIN
        IF @sStatus NOT IN ('DRAFT', 'PENDING')
        BEGIN
            SELECT @ResultCode = 'NOT_CANCELLABLE', @ResultMessage = N'An approved or paid settlement cannot be cancelled.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for cancelling this settlement.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Payroll].[FinalSettlements]
               SET Status = 'CANCELLED', ApprovalLevel = 0, CancelledBy = @UserId, CancelledDate = @Now, CancelReason = @Comment,
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  FinalSettlementId = @Id AND Status IN ('DRAFT', 'PENDING');
            INSERT INTO [Payroll].[FinalSettlementHistory] (FinalSettlementId, ActionCode, NetPayable, Comment, ActionBy)
            VALUES (@Id, 'CANCELLED', @sNet, @Comment, @UserId);
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Settlement cancelled. It keeps its number.';
        RETURN;
    END;
END;
GO

/* ---- 7. labels (English + Arabic) ---------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('lv.work_since_leave', 'lv', N'Since last paid leave ({0})', N'منذ آخر إجازة مدفوعة ({0})', NULL),
        ('lv.work_since_joining', 'lv', N'Since joining ({0})', N'منذ الالتحاق ({0})', NULL),
        ('lv.work_vs_actual', 'lv', N'Work period {0} months · actual working {1} months', N'فترة العمل {0} شهر · العمل الفعلي {1} شهر', NULL),
        ('lv.unpaid_excluded', 'lv', N'{0} days of unpaid leave over a month left out ({1} days less earned)', N'استُبعد {0} يوم إجازة بدون راتب تزيد عن شهر ({1} يوم أقل في الاستحقاق)', NULL),
        ('fs.work_period', 'fs', N'Work period', N'فترة العمل', NULL),
        ('fs.actual_working', 'fs', N'Actual working', N'العمل الفعلي', NULL),
        ('fs.unpaid_excluded_n', 'fs', N'{0} days of unpaid leave over a month left out', N'استُبعد {0} يوم إجازة بدون راتب تزيد عن شهر', NULL),
        ('fs.indemnity_on_actual', 'fs', N'Indemnity counts the actual working months: unpaid leave of more than a month is not service.', N'تُحتسب مكافأة نهاية الخدمة على أشهر العمل الفعلي: الإجازة بدون راتب لأكثر من شهر لا تُعد خدمة.', NULL),
        ('fs.leave_since_n', 'fs', N'Since last paid leave ({0})', N'منذ آخر إجازة مدفوعة ({0})', NULL),
        ('fs.leave_since', 'fs', N'Leave: since last paid leave', N'الإجازة: منذ آخر إجازة مدفوعة', NULL),
        ('fs.months_n', 'fs', N'{0} months', N'{0} شهر', NULL),
        ('fs.st_work_period', 'fs', N'Work period', N'فترة العمل', NULL),
        ('fs.st_actual_working', 'fs', N'Actual working (indemnity)', N'العمل الفعلي (المكافأة)', NULL),
        ('js.fs_actual_service', 'js', N'{0} actual working · {1} excluded (unpaid over a month)', N'{0} عمل فعلي · {1} مستبعد (بدون راتب أكثر من شهر)', NULL),
        ('js.fs_leave_since', 'js', N'Since {0}: {1} months worked of {2}', N'منذ {0}: {1} شهر عمل فعلي من {2}', NULL),
        ('js.fs_annual_balance', 'js', N'Annual leave balance on that day: {0} days', N'رصيد الإجازة السنوية في ذلك اليوم: {0} يوم', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Actual working months labels inserted: ', @LabelsInserted);
GO
