/* =====================================================================
   140_Attendance_To_Payroll.sql  -  Attendance deductions in every payroll
   ---------------------------------------------------------------------
   Run after db/137 (and db/119). Safe to re-run.

   Before: the attendance deductions / overtime reached a payroll only when
   someone pressed Post on Time & Attendance > Monthly Summary BEFORE the
   payroll was calculated - a payroll created first, or a month not
   posted, had no attendance in it.

   Now: every calculation of a regular payroll (Create Payroll, Recalculate,
   including / excluding an employee) first brings in the attendance of the
   payroll month (Attendance.usp_AttPayroll_Sync):
     - per employee, the month's deduction and overtime from the days
       (Attendance.Records, the payroll month of the calendar's start day)
     - as one-time pay items "Attendance deduction" / "Overtime
       (attendance)" (SourceRef ATT:yyyy-MM) - the same items Post makes
     - unchanged amounts are left alone; an item a payroll has already
       used (closed) is never replaced; an employee with nothing left has
       the items taken away
     - a manual posting (Monthly Summary) is kept up to date, none is made
       (a posted month locks the Attendance Sheet's marks)

   Payroll.usp_PayrollRun_Calculate is the db/119 procedure with that call
   added before it works the payroll out.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[ufn_MonthFrom]', N'FN') IS NULL OR OBJECT_ID(N'[Payroll].[usp_PayrollRun_Calculate]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/119 and db/137 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttPayroll_Sync]
    @CompanyId    INT,
    @RunMonth     DATE,
    @EmployeeIds  NVARCHAR(MAX) = NULL,      -- CSV; NULL = every employee of the company
    @UserId       BIGINT        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF @CompanyId IS NULL OR @RunMonth IS NULL RETURN;

    DECLARE @M DATE = DATEFROMPARTS(YEAR(@RunMonth), MONTH(@RunMonth), 1);
    DECLARE @From DATE = [Attendance].[ufn_MonthFrom](@CompanyId, @M), @To DATE = [Attendance].[ufn_MonthTo](@CompanyId, @M);
    DECLARE @Ref NVARCHAR(50) = N'ATT:' + FORMAT(@M, 'yyyy-MM', 'en-US');
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Only TABLE (EmployeeId BIGINT PRIMARY KEY);
    IF @EmployeeIds IS NOT NULL
        INSERT INTO @Only SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@EmployeeIds, ',') WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

    /* the month's attendance per employee */
    DECLARE @A TABLE (EmployeeId BIGINT PRIMARY KEY, Deduction DECIMAL(12,3) NOT NULL, Overtime DECIMAL(12,3) NOT NULL);
    INSERT INTO @A (EmployeeId, Deduction, Overtime)
    SELECT  r.EmployeeId, ROUND(SUM(r.DeductionAmount), 3), ROUND(SUM(r.OvertimeAmount), 3)
    FROM    [Attendance].[Records] AS r
    WHERE   r.Deleted = 0 AND r.CompanyId = @CompanyId AND r.WorkDate BETWEEN @From AND @To
      AND  (@EmployeeIds IS NULL OR r.EmployeeId IN (SELECT EmployeeId FROM @Only))
    GROUP BY r.EmployeeId;

    /* items of the month for employees with no day left: taken away */
    INSERT INTO @A (EmployeeId, Deduction, Overtime)
    SELECT DISTINCT i.EmployeeId, 0, 0
    FROM   [Payroll].[EmployeePayItems] AS i
    JOIN   [Employee].[Employees] AS e ON e.EmployeeId = i.EmployeeId AND e.CompanyId = @CompanyId
    WHERE  i.Deleted = 0 AND i.SourceRef = @Ref AND i.PayrollRunId IS NULL
      AND  NOT EXISTS (SELECT 1 FROM @A AS a WHERE a.EmployeeId = i.EmployeeId)
      AND (@EmployeeIds IS NULL OR i.EmployeeId IN (SELECT EmployeeId FROM @Only));

    /* an item a payroll has already used (closed) stays as it is */
    DELETE a
    FROM   @A AS a
    WHERE EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] AS i
                  WHERE i.Deleted = 0 AND i.SourceRef = @Ref AND i.EmployeeId = a.EmployeeId AND i.PayrollRunId IS NOT NULL);

    /* unchanged: left alone */
    DELETE a
    FROM   @A AS a
    CROSS APPLY (SELECT ISNULL(SUM(CASE WHEN c.ComponentCode = N'ATT_DEDUCTION' THEN i.Amount END), 0) AS Ded,
                        ISNULL(SUM(CASE WHEN c.ComponentCode = N'ATT_OVERTIME'  THEN i.Amount END), 0) AS Ot
                 FROM   [Payroll].[EmployeePayItems] AS i
                 JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
                 WHERE  i.Deleted = 0 AND i.SourceRef = @Ref AND i.EmployeeId = a.EmployeeId) AS x
    WHERE x.Ded = a.Deduction AND x.Ot = a.Overtime;

    IF NOT EXISTS (SELECT 1 FROM @A) RETURN;

    /* the item types (added to the company when missing - as Post does) */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND ComponentCode = N'ATT_DEDUCTION' AND Deleted = 0)
        INSERT INTO [Payroll].[PayComponents] (CompanyId, ComponentCode, ComponentName, ArabicName, ComponentType, ValueType,
            CalculationMethod, IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, Description, CreatedBy)
        VALUES (@CompanyId, N'ATT_DEDUCTION', N'Attendance deduction', N'خصم الحضور', 'DEDUCTION', 'VARIABLE', 'AMOUNT', 0, 0, 1, 300,
                N'Late arrival, short hours and absence - from Time & Attendance.', @UserId);
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND ComponentCode = N'ATT_OVERTIME' AND Deleted = 0)
        INSERT INTO [Payroll].[PayComponents] (CompanyId, ComponentCode, ComponentName, ArabicName, ComponentType, ValueType,
            CalculationMethod, IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, Description, CreatedBy)
        VALUES (@CompanyId, N'ATT_OVERTIME', N'Overtime (attendance)', N'العمل الإضافي (الحضور)', 'EARNING', 'VARIABLE', 'AMOUNT', 0, 0, 1, 210,
                N'Overtime worked - from Time & Attendance.', @UserId);
    DECLARE @DedType INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND ComponentCode = N'ATT_DEDUCTION' AND Deleted = 0);
    DECLARE @OtType  INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND ComponentCode = N'ATT_OVERTIME' AND Deleted = 0);

    DECLARE @Items TABLE (ItemId BIGINT, EmployeeId BIGINT, Kind CHAR(1));
    BEGIN TRANSACTION;
        UPDATE i SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Payroll].[EmployeePayItems] AS i
        JOIN   @A AS a ON a.EmployeeId = i.EmployeeId
        WHERE  i.Deleted = 0 AND i.SourceRef = @Ref AND i.PayrollRunId IS NULL;

        INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, SourceRef, CreatedBy)
        OUTPUT inserted.EmployeePayItemId, inserted.EmployeeId, CASE WHEN inserted.PayComponentId = @DedType THEN 'D' ELSE 'O' END INTO @Items
        SELECT @CompanyId, a.EmployeeId, v.TypeId, v.Amount, 'ONCE', @M,
               CONCAT(N'Time & Attendance - ', FORMAT(@M, 'MMMM yyyy', 'en-US'), N' (', FORMAT(@From, 'dd MMM', 'en-US'), N' - ', FORMAT(@To, 'dd MMM', 'en-US'), N')'),
               'ACTIVE', @Ref, @UserId
        FROM   @A AS a
        CROSS APPLY (VALUES (@DedType, a.Deduction), (@OtType, a.Overtime)) AS v(TypeId, Amount)
        WHERE  v.Amount > 0;

        /* a manual posting (Monthly Summary) follows the new amounts */
        UPDATE s
        SET    DeductionAmount = a.Deduction, OvertimeAmount = a.Overtime,
               DeductionItemId = (SELECT TOP (1) ItemId FROM @Items AS x WHERE x.EmployeeId = a.EmployeeId AND x.Kind = 'D'),
               OvertimeItemId  = (SELECT TOP (1) ItemId FROM @Items AS x WHERE x.EmployeeId = a.EmployeeId AND x.Kind = 'O')
        FROM   [Attendance].[Postings] AS s
        JOIN   @A AS a ON a.EmployeeId = s.EmployeeId
        WHERE  s.Deleted = 0 AND s.CompanyId = @CompanyId AND s.RunMonth = @M;
    COMMIT TRANSACTION;
END;
GO

CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Calculate]
    @RunId        BIGINT,
    @EmployeeIds  NVARCHAR(MAX) = NULL,   -- CSV; NULL = whole run (also re-syncs who is in it)
    @UserId       BIGINT        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CompanyId INT, @Start DATE, @End DATE, @RunMonth DATE, @RunType VARCHAR(10), @Stage VARCHAR(20),
            @Freq VARCHAR(10), @Dept INT, @Loc INT, @EmpType NVARCHAR(20), @Nat VARCHAR(12), @CalendarId INT, @PeriodId INT;

    SELECT  @CompanyId = r.CompanyId, @Start = p.StartDate, @End = p.EndDate, @RunMonth = r.RunMonth,
            @RunType = r.RunType, @Stage = r.Stage, @Freq = pc.PayFrequency, @CalendarId = r.PayrollCalendarId, @PeriodId = r.PayrollPeriodId,
            @Dept = r.ScopeDepartmentId, @Loc = r.ScopeWorkLocationId, @EmpType = r.ScopeEmploymentType, @Nat = r.ScopeNationality
    FROM    [Payroll].[PayrollRuns]      AS r
    JOIN    [Payroll].[PayrollPeriods]   AS p  ON p.PayrollPeriodId    = r.PayrollPeriodId
    JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0;

    /* in Validation only one employee's exclude / include recalculates */
    IF @CompanyId IS NULL OR NOT (@Stage IN ('DRAFT', 'REGISTERED') OR (@Stage = 'VALIDATION' AND @EmployeeIds IS NOT NULL))
        RETURN;

    /* db/140: Time & Attendance - the attendance of the payroll month (late, short hours, absence, overtime) is
       brought in as one-time pay items before the calculation, so every payroll reflects the attendance as it is */
    IF @RunType = 'REGULAR' AND OBJECT_ID(N'[Attendance].[usp_AttPayroll_Sync]', N'P') IS NOT NULL
        EXEC [Attendance].[usp_AttPayroll_Sync] @CompanyId = @CompanyId, @RunMonth = @RunMonth, @EmployeeIds = @EmployeeIds, @UserId = @UserId;

    /* the profile salary is paid through the company's Basic Salary / Other Allowances
       pay components: a company set up after the payroll seed (db/32) gets the defaults now */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND Deleted = 0 AND ComponentCode = N'BASIC')
       AND OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @CompanyId, @UserId = @UserId;

    /* db/119: the salary is paid from the employment contract (step 5a) - no salary pay items
       are made for it any more */

    /* db/115: the company's Work Permit Collection item type (type COLLECTION) */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0)
        EXEC [Payroll].[usp_PayComponent_SeedCollection] @CompanyId = @CompanyId, @UserId = @UserId;

    DECLARE @PeriodDays INT = DATEDIFF(DAY, @Start, @End) + 1;
    DECLARE @BasisDays  INT = CASE WHEN @Freq = 'MONTHLY' THEN @PeriodDays ELSE DAY(EOMONTH(@RunMonth)) END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRANSACTION;

    /* ---- 1. who is in the run (whole-run calculation only) ----------- */
    IF @EmployeeIds IS NULL
    BEGIN
        /* a payroll pays the employees of ITS calendar (db/60); an employee with no
           calendar yet is paid by the company's default calendar */
        /* db/80: a company with no active default calendar uses its first active
           monthly calendar as the default (Kuwait pays monthly) */
        DECLARE @DefaultCal BIT = CASE
            WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                         WHERE PayrollCalendarId = @CalendarId AND IsDefault = 1) THEN 1
            WHEN NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                             WHERE CompanyId = @CompanyId AND IsDefault = 1 AND IsActive = 1 AND Deleted = 0)
                 AND @CalendarId = (SELECT TOP (1) PayrollCalendarId FROM [Payroll].[PayrollCalendars]
                                    WHERE CompanyId = @CompanyId AND PayFrequency = 'MONTHLY' AND IsActive = 1 AND Deleted = 0
                                    ORDER BY PayrollCalendarId) THEN 1
            ELSE 0 END;
        DECLARE @Eligible TABLE (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO @Eligible (EmployeeId)
        SELECT e.EmployeeId
        FROM   [Employee].[Employees] AS e
        LEFT JOIN [Core].[Countries]  AS n ON n.CountryId = e.NationalityCountryId
        WHERE  e.CompanyId = @CompanyId AND e.Deleted = 0 AND e.IsDeleted = 0
          /* db/80: the default calendar also pays an employee whose calendar was
             deactivated or removed, or is another company's - nobody is left out */
          AND  (e.PayrollCalendarId = @CalendarId
                OR (@DefaultCal = 1 AND (e.PayrollCalendarId IS NULL
                     OR NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] AS ec
                                    WHERE ec.PayrollCalendarId = e.PayrollCalendarId AND ec.CompanyId = e.CompanyId
                                      AND ec.Deleted = 0 AND ec.IsActive = 1))))
          AND  (e.HireDate IS NULL OR e.HireDate <= @End)
          AND  (e.TerminationDate IS NULL OR e.TerminationDate >= @Start)
          AND  NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)
          AND  (@Dept    IS NULL OR e.DepartmentId   = @Dept)
          AND  (@Loc     IS NULL OR e.WorkLocationId = @Loc)
          AND  (@EmpType IS NULL OR e.EmploymentType = @EmpType)
          AND  (@Nat     IS NULL OR (@Nat = 'KUWAITI' AND n.CountryCode IN ('KW', 'KWT'))
                                 OR (@Nat = 'NON_KUWAITI' AND ISNULL(n.CountryCode, '') NOT IN ('KW', 'KWT')));

        /* an employee's final settlement (draft to paid) pays the salary from its
           "Salary unpaid from" day - no payroll pays those days again (db/39-40) */
        IF OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NOT NULL
            DELETE x
            FROM   @Eligible AS x
            WHERE  EXISTS (SELECT 1 FROM [Payroll].[FinalSettlements] AS fs
                           WHERE fs.EmployeeId = x.EmployeeId AND fs.Deleted = 0 AND fs.SettlementType <> 'ENCASHMENT'
                             AND fs.Status <> 'CANCELLED' AND fs.SalaryFrom <= @End);

        /* db/80: one regular payroll per employee per month - an employee already in
           another created regular payroll of the same month (any calendar; drafts
           do not count - Create recalculates, so the second one leaves them out)
           is not paid again here. The periods of one
           weekly / bi-weekly calendar inside a month are each paid. */
        IF @RunType = 'REGULAR'
            DELETE x
            FROM   @Eligible AS x
            WHERE  EXISTS (SELECT 1
                           FROM   [Payroll].[PayrollRunEmployees] AS oe
                           JOIN   [Payroll].[PayrollRuns]         AS o ON o.PayrollRunId = oe.PayrollRunId
                           WHERE  oe.EmployeeId = x.EmployeeId AND oe.Deleted = 0 AND o.Deleted = 0
                             AND  o.PayrollRunId <> @RunId AND o.RunType = 'REGULAR'
                             AND  o.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
                             AND  o.RunMonth = @RunMonth
                             AND  NOT (o.PayrollCalendarId = @CalendarId AND o.PayrollPeriodId <> @PeriodId));

        /* leave: no longer in scope */
        UPDATE l SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = l.RunEmployeeId
        WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND l.Deleted = 0
          AND  NOT EXISTS (SELECT 1 FROM @Eligible x WHERE x.EmployeeId = re.EmployeeId);

        UPDATE re SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Payroll].[PayrollRunEmployees] AS re
        WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0
          AND  NOT EXISTS (SELECT 1 FROM @Eligible x WHERE x.EmployeeId = re.EmployeeId);

        /* join: newly in scope (an off-cycle payroll only takes new people while it is a draft) */
        INSERT INTO [Payroll].[PayrollRunEmployees] (PayrollRunId, EmployeeId)
        SELECT @RunId, x.EmployeeId
        FROM   @Eligible AS x
        WHERE  (@RunType = 'REGULAR' OR @Stage = 'DRAFT')
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] re
                           WHERE re.PayrollRunId = @RunId AND re.EmployeeId = x.EmployeeId AND re.Deleted = 0);

        /* db/107: on leave for the WHOLE period, the leave salary already paid in cash and not
           back yet -> excluded (nothing to pay; the leave-salary recovery of the month is not
           taken either). HR can include them and add pay items. Once HR includes or excludes
           someone by hand (AutoExcluded stays 1 / ExcludedBy is set), the payroll leaves them be;
           an auto-exclusion that no longer applies (early return, leave changed) is undone. */
        IF @RunType = 'REGULAR' AND COL_LENGTH(N'Leave.LeaveRequests', N'SettlementMode') IS NOT NULL
        BEGIN
            UPDATE re
               SET IsExcluded = 0, AutoExcluded = 0, ExcludeReason = NULL, ExcludedDate = NULL
            FROM   [Payroll].[PayrollRunEmployees] AS re
            WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 1 AND re.AutoExcluded = 1 AND re.ExcludedBy IS NULL
              AND  NOT EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] AS r
                               WHERE r.EmployeeId = re.EmployeeId AND r.Deleted = 0 AND r.Status = 'APPROVED' AND r.SettlementMode = 'CASH'
                                 AND r.StartDate <= @Start AND ISNULL(r.ActualEndDate, r.EndDate) >= @End);

            UPDATE re
               SET IsExcluded = 1, AutoExcluded = 1, ExcludedBy = NULL, ExcludedDate = @Now,
                   ExcludeReason = LEFT(CONCAT(N'On leave all period (', lv.RequestNo, N', ', FORMAT(lv.StartDate, 'dd MMM yyyy', 'en-US'),
                                               N' - ', FORMAT(lv.LastDay, 'dd MMM yyyy', 'en-US'),
                                               N'); leave salary already paid in cash. Include to pay anything else.'), 500)
            FROM   [Payroll].[PayrollRunEmployees] AS re
            CROSS APPLY (SELECT TOP (1) r.RequestNo, r.StartDate, ISNULL(r.ActualEndDate, r.EndDate) AS LastDay
                         FROM   [Leave].[LeaveRequests] AS r
                         WHERE  r.EmployeeId = re.EmployeeId AND r.Deleted = 0 AND r.Status = 'APPROVED' AND r.SettlementMode = 'CASH'
                           AND  r.StartDate <= @Start AND ISNULL(r.ActualEndDate, r.EndDate) >= @End
                         ORDER BY r.StartDate DESC) AS lv
            WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0 AND re.AutoExcluded = 0;
        END;
    END;

    /* ---- 2. target employees ----------------------------------------- */
    DECLARE @T TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, IsExcluded BIT NOT NULL, CatchUp BIT NOT NULL DEFAULT (0));
    INSERT INTO @T (RunEmployeeId, EmployeeId, IsExcluded)
    SELECT re.RunEmployeeId, re.EmployeeId, re.IsExcluded
    FROM   [Payroll].[PayrollRunEmployees] AS re
    WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0
      AND  (@EmployeeIds IS NULL OR re.EmployeeId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@EmployeeIds, ',')));

    /* catch-up (off-cycle): excluded from the closed regular payroll of this period
       and not paid by another off-cycle payroll of the period */
    IF @RunType = 'OFFCYCLE'
        UPDATE t SET CatchUp = 1
        FROM   @T AS t
        WHERE  t.IsExcluded = 0
          AND  EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] AS x
                       JOIN   [Payroll].[PayrollRuns] AS g ON g.PayrollRunId = x.PayrollRunId
                       WHERE  g.PayrollPeriodId = @PeriodId AND g.RunType = 'REGULAR' AND g.Stage = 'CLOSED' AND g.Deleted = 0
                         AND  x.EmployeeId = t.EmployeeId AND x.Deleted = 0 AND x.IsExcluded = 1)
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] AS y
                           JOIN   [Payroll].[PayrollRuns] AS o ON o.PayrollRunId = y.PayrollRunId
                           WHERE  o.PayrollPeriodId = @PeriodId AND o.RunType = 'OFFCYCLE' AND o.PayrollRunId <> @RunId
                             AND  o.Deleted = 0 AND o.Stage <> 'CANCELLED'
                             AND  y.EmployeeId = t.EmployeeId AND y.Deleted = 0 AND y.IsExcluded = 0 AND y.SalaryTotal > 0);

    /* ---- 3. snapshot of the employee -------------------------------- */
    UPDATE re
       SET EmployeeNo       = ISNULL(e.EmployeeCode, e.EmployeeNo),
           EmployeeName     = LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))),
           ArabicName       = e.ArabicName,
           DepartmentId     = e.DepartmentId,
           DepartmentName   = d.DepartmentName,
           CostCenterId     = COALESCE(e.CostCenterId, d.CostCenterId),
           IsKuwaiti        = CASE WHEN n.CountryCode IN ('KW', 'KWT') THEN 1 ELSE 0 END,
           EmploymentStatus = e.EmploymentStatus,
           HireDate         = e.HireDate,
           TerminationDate  = e.TerminationDate,
           PeriodDays       = @BasisDays,
           PaidDays         = CASE WHEN x.PaidTo < x.PaidFrom THEN 0 ELSE DATEDIFF(DAY, x.PaidFrom, x.PaidTo) + 1 END,
           HasBankAccount   = CASE WHEN NULLIF(LTRIM(RTRIM(ep.Iban)), N'') IS NULL THEN 0 ELSE 1 END
    FROM   [Payroll].[PayrollRunEmployees] AS re
    JOIN   @T AS t ON t.RunEmployeeId = re.RunEmployeeId
    JOIN   [Employee].[Employees] AS e ON e.EmployeeId = re.EmployeeId
    LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
    LEFT JOIN [Core].[Countries]   AS n ON n.CountryId = e.NationalityCountryId
    LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId AND ep.Deleted = 0
    CROSS APPLY (SELECT CASE WHEN e.HireDate > @Start THEN e.HireDate ELSE @Start END AS PaidFrom,
                        CASE WHEN e.TerminationDate < @End THEN e.TerminationDate ELSE @End END AS PaidTo) AS x;

    /* weekly / bi-weekly: paid days are the days of THIS period, the basis the month */
    /* (PaidDays above is already limited to the period, so nothing else to do) */

    /* ---- 4. clear the old lines of the target employees -------------- */
    UPDATE l SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
    FROM   [Payroll].[PayrollRunLines] AS l
    JOIN   @T AS t ON t.RunEmployeeId = l.RunEmployeeId
    WHERE  l.Deleted = 0;

    /* lines of other live payrolls - an item is paid by one payroll a month */
    DECLARE @Used TABLE (EmployeePayItemId BIGINT PRIMARY KEY, PaidCount INT NOT NULL, PaidAmount DECIMAL(14,3) NOT NULL, ThisMonth BIT NOT NULL);
    INSERT INTO @Used (EmployeePayItemId, PaidCount, PaidAmount, ThisMonth)
    SELECT l.EmployeePayItemId, COUNT(1), SUM(ABS(l.Amount)), MAX(CASE WHEN r.RunMonth = @RunMonth THEN 1 ELSE 0 END)
    FROM   [Payroll].[PayrollRunLines] AS l
    JOIN   [Payroll].[PayrollRuns]     AS r ON r.PayrollRunId = l.PayrollRunId
    JOIN   @T AS t ON t.EmployeeId = l.EmployeeId
    WHERE  l.Deleted = 0 AND r.Deleted = 0 AND l.EmployeePayItemId IS NOT NULL
      AND  r.PayrollRunId <> @RunId AND r.Stage NOT IN ('DRAFT', 'CANCELLED')
    GROUP BY l.EmployeePayItemId;

    /* ---- 5a. db/119: the salary of the employment contract -----------
       Basic Salary and Allowances of the employee profile (Employee.EmployeePayroll)
       are the default lines of every regular payroll - not salary pay items. An
       approved salary revision updates the profile (db/111). The hire and
       termination dates decide the days paid (PaidDays, step 3): someone hired after
       the period is not in the payroll, a joiner / leaver of the month is paid the
       days worked when the pay component is prorated. */
    IF @RunType = 'REGULAR' OR EXISTS (SELECT 1 FROM @T WHERE CatchUp = 1)
    BEGIN
        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, re.RunEmployeeId, re.EmployeeId, c.PayComponentId, 'SALARY', c.ComponentName, c.ArabicName,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN CONCAT(N'Prorated ', re.PaidDays, N' of ', re.PeriodDays, N' days (hire / termination date)')
                     ELSE N'Monthly salary (employment contract)' END,
                'PROFILE', v.Amount,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN ROUND(v.Amount * re.PaidDays / NULLIF(re.PeriodDays, 0), 3) ELSE v.Amount END,
                c.DisplayOrder
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    @T AS t ON t.RunEmployeeId = re.RunEmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
        JOIN    [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = re.EmployeeId AND ep.Deleted = 0
        CROSS APPLY (VALUES ('BASIC', ep.BasicSalary), ('OTHER_ALW', ep.Allowances)) AS v(Code, Amount)
        JOIN    [Payroll].[PayComponents] AS c ON c.CompanyId = @CompanyId AND c.ComponentCode = v.Code AND c.Deleted = 0
        WHERE   v.Amount > 0 AND re.PaidDays > 0;
    END;

    /* ---- 5b. earnings, deductions, loans ----------------------------- */
    ;WITH it AS (
        SELECT  i.EmployeePayItemId, i.EmployeeId, i.PayComponentId, i.Amount, i.AppliesMode, i.InstalmentCount, i.TotalAmount,
                i.Comment, i.PayrollRunId, c.ItemClass, c.ComponentName, c.ArabicName AS CompArabic, c.DisplayOrder,
                ISNULL(u.PaidCount, 0) AS PaidCount, ISNULL(u.PaidAmount, 0) AS PaidAmount, ISNULL(u.ThisMonth, 0) AS ThisMonth
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        JOIN    @T AS t ON t.EmployeeId = i.EmployeeId AND t.IsExcluded = 0
        LEFT JOIN @Used AS u ON u.EmployeePayItemId = i.EmployeePayItemId
        WHERE   i.Deleted = 0 AND i.Status = 'ACTIVE'
          AND   c.ItemClass IN ('EARNING', 'DEDUCTION', 'LOAN')
          AND   (   i.PayrollRunId = @RunId
                 OR ((@RunType = 'REGULAR' OR t.CatchUp = 1) AND i.PayrollRunId IS NULL AND ISNULL(u.ThisMonth, 0) = 0 AND (
                        (i.AppliesMode = 'MONTHLY'    AND i.StartMonth <= @RunMonth AND (i.EndMonth IS NULL OR i.EndMonth >= @RunMonth))
                     OR (i.AppliesMode = 'ONCE'       AND i.StartMonth = @RunMonth)
                     OR (i.AppliesMode = 'INSTALMENT' AND i.StartMonth <= @RunMonth AND ISNULL(u.PaidCount, 0) < i.InstalmentCount))))
    )
    INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                             Comment, Source, EmployeePayItemId, InstalmentNo, FullAmount, Amount, DisplayOrder)
    SELECT  @RunId, re.RunEmployeeId, it.EmployeeId, it.PayComponentId, it.ItemClass, it.ComponentName, it.CompArabic,
            it.Comment,
            CASE WHEN it.PayrollRunId = @RunId THEN 'RUN' WHEN it.ItemClass = 'LOAN' THEN 'LOAN' ELSE 'PAY_ITEM' END,
            it.EmployeePayItemId,
            CASE WHEN it.AppliesMode = 'INSTALMENT' THEN it.PaidCount + 1 END,
            a.Amt,
            CASE WHEN it.ItemClass = 'EARNING' THEN a.Amt ELSE -a.Amt END,
            it.DisplayOrder
    FROM    it
    JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = @RunId AND re.EmployeeId = it.EmployeeId AND re.Deleted = 0
    CROSS APPLY (SELECT CASE WHEN it.AppliesMode = 'INSTALMENT' AND it.TotalAmount IS NOT NULL AND it.PaidCount + 1 >= it.InstalmentCount
                             THEN CASE WHEN it.TotalAmount - it.PaidAmount > 0 THEN it.TotalAmount - it.PaidAmount ELSE 0 END
                             ELSE it.Amount END AS Amt) AS a
    WHERE   a.Amt > 0;

    /* ---- 5c. PIFSS employee share (Kuwaiti, regular runs, catch-up) -- */
    IF @RunType = 'REGULAR' OR EXISTS (SELECT 1 FROM @T WHERE CatchUp = 1)
    BEGIN
        DECLARE @PifssId INT, @PifssName NVARCHAR(150), @PifssArabic NVARCHAR(150), @PifssOrder SMALLINT;
        SELECT TOP 1 @PifssId = PayComponentId, @PifssName = ComponentName, @PifssArabic = ArabicName, @PifssOrder = DisplayOrder
        FROM   [Payroll].[PayComponents]
        WHERE  CompanyId = @CompanyId AND SystemCode = 'PIFSS_EE' AND Deleted = 0 AND IsActive = 1;

        IF @PifssId IS NOT NULL
        BEGIN
            ;WITH b AS (
                SELECT  l.RunEmployeeId, l.EmployeeId, SUM(l.Amount) AS Base
                FROM    [Payroll].[PayrollRunLines] AS l
                JOIN    [Payroll].[PayComponents]   AS c ON c.PayComponentId = l.PayComponentId
                JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = l.RunEmployeeId
                JOIN    @T AS t ON t.RunEmployeeId = l.RunEmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
                WHERE   l.PayrollRunId = @RunId AND l.Deleted = 0 AND l.ItemClass = 'SALARY'
                  AND   c.IsPifssApplicable = 1 AND re.IsKuwaiti = 1
                GROUP BY l.RunEmployeeId, l.EmployeeId
            ), share AS (
                SELECT  b.RunEmployeeId, b.EmployeeId,
                        SUM(ROUND(CASE WHEN r.SalaryCeiling IS NOT NULL AND b.Base > r.SalaryCeiling THEN r.SalaryCeiling ELSE b.Base END
                                  * r.EmployeeRate / 100.0, 3)) AS Amt
                FROM    b
                JOIN    [Payroll].[PifssContributionRates] AS r
                        ON r.Deleted = 0 AND r.IsActive = 1 AND r.ApplicableTo = 'KUWAITI'
                       AND r.EffectiveFrom <= @End AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @End)
                WHERE   b.Base > 0
                GROUP BY b.RunEmployeeId, b.EmployeeId
            )
            INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                     Comment, Source, FullAmount, Amount, DisplayOrder)
            SELECT  @RunId, s.RunEmployeeId, s.EmployeeId, @PifssId, 'STATUTORY', @PifssName, @PifssArabic,
                    N'Employee share, Kuwaiti', 'STATUTORY', s.Amt, -s.Amt, @PifssOrder
            FROM    share AS s
            WHERE   s.Amt > 0;
        END;
    END;

    /* db/119: Work Permit Collections are recorded once the payroll is approved (closed) -
       Payroll.usp_Collection_FromPayroll - not while it is calculated */

    /* ---- 6. employee totals ------------------------------------------ */
    UPDATE re
       SET SalaryTotal     = ISNULL(x.Sal, 0),
           EarningsTotal   = ISNULL(x.Ern, 0),
           DeductionsTotal = ISNULL(x.Ded, 0),
           NetPay          = ISNULL(x.Sal, 0) + ISNULL(x.Ern, 0) + ISNULL(x.Ded, 0),
           LineCount       = ISNULL(x.Cnt, 0),
           AddedLineCount  = ISNULL(x.Added, 0),
           HasSalary       = CASE WHEN ISNULL(x.SalCnt, 0) > 0 THEN 1 ELSE 0 END,
           PreviousNet     = prev.NetPay
    FROM   [Payroll].[PayrollRunEmployees] AS re
    JOIN   @T AS t ON t.RunEmployeeId = re.RunEmployeeId
    OUTER APPLY (
        SELECT  SUM(CASE WHEN l.ItemClass = 'SALARY' THEN l.Amount END)                     AS Sal,
                SUM(CASE WHEN l.ItemClass = 'EARNING' THEN l.Amount END)                    AS Ern,
                SUM(CASE WHEN l.ItemClass IN ('DEDUCTION', 'LOAN', 'STATUTORY') THEN l.Amount END) AS Ded,
                COUNT(1)                                                                    AS Cnt,
                SUM(CASE WHEN l.Source = 'RUN' THEN 1 ELSE 0 END)                           AS Added,
                SUM(CASE WHEN l.ItemClass = 'SALARY' THEN 1 ELSE 0 END)                     AS SalCnt
        FROM    [Payroll].[PayrollRunLines] AS l
        WHERE   l.RunEmployeeId = re.RunEmployeeId AND l.Deleted = 0
    ) AS x
    OUTER APPLY (
        SELECT TOP 1 pe.NetPay
        FROM   [Payroll].[PayrollRunEmployees] AS pe
        JOIN   [Payroll].[PayrollRuns]         AS pr ON pr.PayrollRunId = pe.PayrollRunId
        WHERE  pe.EmployeeId = re.EmployeeId AND pe.Deleted = 0 AND pe.IsExcluded = 0
          AND  pr.Deleted = 0 AND pr.Stage = 'CLOSED' AND pr.RunType = 'REGULAR'
          AND  pr.CompanyId = @CompanyId AND pr.RunMonth < @RunMonth AND pr.PayrollRunId <> @RunId
        ORDER BY pr.RunMonth DESC, pr.PayrollRunId DESC
    ) AS prev;

    /* ---- 7. run totals ----------------------------------------------- */
    UPDATE r
       SET EmployeeCount   = ISNULL(x.Cnt, 0),
           ExcludedCount   = ISNULL(x.Excl, 0),
           TotalSalary     = ISNULL(x.Sal, 0),
           TotalEarnings   = ISNULL(x.Ern, 0),
           TotalDeductions = ISNULL(x.Ded, 0),
           TotalNet        = ISNULL(x.Net, 0),
           CalculatedBy    = @UserId,
           CalculatedDate  = @Now
    FROM   [Payroll].[PayrollRuns] AS r
    OUTER APPLY (
        SELECT  SUM(CASE WHEN re.IsExcluded = 0 AND (@RunType = 'REGULAR' OR re.LineCount > 0) THEN 1 ELSE 0 END) AS Cnt,
                SUM(CASE WHEN re.IsExcluded = 1 THEN 1 ELSE 0 END) AS Excl,
                SUM(re.SalaryTotal) AS Sal, SUM(re.EarningsTotal) AS Ern, SUM(re.DeductionsTotal) AS Ded, SUM(re.NetPay) AS Net
        FROM    [Payroll].[PayrollRunEmployees] AS re
        WHERE   re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0
    ) AS x
    WHERE  r.PayrollRunId = @RunId;

    COMMIT TRANSACTION;
END;
GO
