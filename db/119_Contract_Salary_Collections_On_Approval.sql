/* =====================================================================
   119_Contract_Salary_Collections_On_Approval.sql
   ---------------------------------------------------------------------
   Run after db/35, db/107 and db/115. Safe to re-run. It replaces
   Payroll.usp_PayrollRun_Calculate (db/115), Payroll.usp_PayrollRun_Validate
   (db/35) and Payroll.usp_Collection_Manage (db/115): run this script again
   whenever one of those is run.

   1. The salary of every regular payroll is the employment contract on the
      employee profile - Basic Salary and Allowances - not salary pay items.
      Every employee in the payroll gets those lines for the payroll month;
      the hire and termination dates decide whether (and for how many days)
      they are paid: hired after the period = not in the payroll, a joiner /
      leaver of the month is paid the days worked (prorated components). An
      approved salary revision updates the profile (db/111), so it is paid
      from its approval on. No salary pay items are made from the contract
      when a payroll is calculated any more. Validation V01 now points to the
      profile; V02 ("salary taken from the employee profile") is gone.

   2. Work Permit Collections are recorded only once the payroll is
      approved (closed) - Payroll.usp_Collection_FromPayroll, run by the
      final approval - not while it is calculated. The Collection page and the
      Payroll Dashboard show the collections of approved payrolls only.
      First run: the pending collections of payrolls not approved yet are
      removed (history kept), and the approved payrolls get theirs.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[Collections]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[usp_PayrollRun_Validate]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/35, db/107 and db/115 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the payroll engine: the contract salary; no collections while calculating */
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


/* ---- 2. Payroll.usp_PayrollRun_Validate (db/35): V01 points to the profile, no V02 */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Validate]
    @RunId   BIGINT,
    @UserId  BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RunType VARCHAR(10), @End DATE, @PayDate DATE, @Now DATETIME2(0) = SYSUTCDATETIME();
    SELECT  @RunType = r.RunType, @End = p.EndDate, @PayDate = ISNULL(p.PaymentDate, p.EndDate)
    FROM    [Payroll].[PayrollRuns] r JOIN [Payroll].[PayrollPeriods] p ON p.PayrollPeriodId = r.PayrollPeriodId
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0;
    IF @RunType IS NULL RETURN;

    DECLARE @Old TABLE (RuleCode VARCHAR(10), EmployeeId BIGINT, AckBy BIGINT, AckDate DATETIME2(0), AckReason NVARCHAR(500));
    INSERT INTO @Old SELECT RuleCode, EmployeeId, AcknowledgedBy, AcknowledgedDate, AcknowledgeReason
    FROM [Payroll].[PayrollRunIssues] WHERE PayrollRunId = @RunId AND Deleted = 0 AND IsAcknowledged = 1;

    DECLARE @New TABLE (EmployeeId BIGINT NULL, RuleCode VARCHAR(10), Severity VARCHAR(10), Message NVARCHAR(400));

    /* employees in the run, included only */
    DECLARE @E TABLE (EmployeeId BIGINT PRIMARY KEY, Sal DECIMAL(12,3), Ern DECIMAL(12,3), Ded DECIMAL(12,3), Net DECIMAL(12,3), Prev DECIMAL(12,3),
                      HasSalary BIT, HasBank BIT, CostCenterId INT, Status NVARCHAR(20), Lines INT);
    INSERT INTO @E
    SELECT re.EmployeeId, re.SalaryTotal, re.EarningsTotal, re.DeductionsTotal, re.NetPay, re.PreviousNet,
           re.HasSalary, re.HasBankAccount, re.CostCenterId, re.EmploymentStatus, re.LineCount
    FROM   [Payroll].[PayrollRunEmployees] re
    WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0
      AND  (@RunType = 'REGULAR' OR re.LineCount > 0);

    IF NOT EXISTS (SELECT 1 FROM @E)
        INSERT INTO @New VALUES (NULL, 'V20', 'ERROR', N'No employees in this payroll');

    IF @RunType = 'REGULAR'
    BEGIN
        /* V01 (db/119): the salary comes from the employment contract on the employee profile */
        INSERT INTO @New
        SELECT e.EmployeeId, 'V01', 'ERROR',
               CASE WHEN ISNULL(ep.BasicSalary, 0) + ISNULL(ep.Allowances, 0) > 0
                        THEN N'Salary on the employee profile could not be paid - the company has no Basic Salary pay component (Payroll Settings > Pay item types)'
                    ELSE N'No Basic Salary on the employee profile (Employee > Employment > Payroll & Bank)' END
        FROM   @E AS e
        OUTER APPLY (SELECT TOP 1 ep.BasicSalary, ep.Allowances FROM [Employee].[EmployeePayroll] AS ep
                     WHERE ep.EmployeeId = e.EmployeeId AND ep.Deleted = 0) AS ep
        WHERE  e.HasSalary = 0;
        /* (V02 "salary taken from the employee profile" is gone: that is the rule now) */
        INSERT INTO @New SELECT EmployeeId, 'V11', 'WARNING', N'No cost center on employee or department' FROM @E WHERE CostCenterId IS NULL;
        INSERT INTO @New
        SELECT EmployeeId, 'V15', 'WARNING',
               CONCAT(N'Net changed ', CASE WHEN Net >= Prev THEN N'+' ELSE N'' END,
                      FORMAT((Net - Prev) * 100.0 / Prev, '0.0', 'en-US'), N'% vs last month')
        FROM @E WHERE Prev > 0 AND Net > 0 AND ABS(Net - Prev) * 100.0 / Prev > 25;
        IF EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates] r
                   WHERE r.Deleted = 0 AND r.IsActive = 1 AND r.IsVerified = 0
                     AND r.EffectiveFrom <= @End AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @End))
           AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @RunId AND l.Deleted = 0 AND l.Source = 'STATUTORY')
            INSERT INTO @New VALUES (NULL, 'V10', 'WARNING', N'PIFSS rates in force are not verified yet (Payroll Settings)');
    END;

    INSERT INTO @New SELECT EmployeeId, 'V03', 'ERROR', CONCAT(N'Negative net salary (', FORMAT(Net, 'N3', 'en-US'), N')') FROM @E WHERE Net < 0;
    INSERT INTO @New SELECT EmployeeId, 'V18', 'WARNING', N'Net pay is zero' FROM @E WHERE Net = 0 AND Lines > 0;
    INSERT INTO @New SELECT EmployeeId, 'V07', 'WARNING', N'No bank account (IBAN) on the employee' FROM @E WHERE HasBank = 0 AND Net > 0;
    INSERT INTO @New SELECT EmployeeId, 'V12', 'WARNING', N'Deductions above 50% of gross'
    FROM @E WHERE (Sal + Ern) > 0 AND -Ded > (Sal + Ern) * 0.5;
    INSERT INTO @New SELECT EmployeeId, 'V19', 'WARNING', CONCAT(N'Employee status is ', Status)
    FROM @E WHERE Status IN (N'Suspended', N'OnLeave');
    INSERT INTO @New
    SELECT e.EmployeeId, 'V17', 'WARNING',
           CONCAT(CASE WHEN k.WorkPermitExpiryDate <= DATEADD(DAY, 30, @PayDate) THEN N'Work permit expires ' ELSE N'Residency expires ' END,
                  FORMAT(CASE WHEN k.WorkPermitExpiryDate <= DATEADD(DAY, 30, @PayDate) THEN k.WorkPermitExpiryDate ELSE k.ResidencyExpiryDate END, 'dd/MM/yyyy', 'en-US'))
    FROM @E e JOIN [Kuwait].[EmployeeCompliance] k ON k.EmployeeId = e.EmployeeId AND k.Deleted = 0
    WHERE k.WorkPermitExpiryDate <= DATEADD(DAY, 30, @PayDate) OR k.ResidencyExpiryDate <= DATEADD(DAY, 30, @PayDate);

    BEGIN TRANSACTION;
        UPDATE [Payroll].[PayrollRunIssues] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        WHERE PayrollRunId = @RunId AND Deleted = 0;

        INSERT INTO [Payroll].[PayrollRunIssues] (PayrollRunId, EmployeeId, RuleCode, Severity, Message, IsAcknowledged, AcknowledgedBy, AcknowledgedDate, AcknowledgeReason)
        SELECT @RunId, n.EmployeeId, n.RuleCode, n.Severity, n.Message,
               CASE WHEN o.RuleCode IS NOT NULL AND n.Severity = 'WARNING' THEN 1 ELSE 0 END,
               CASE WHEN n.Severity = 'WARNING' THEN o.AckBy END, CASE WHEN n.Severity = 'WARNING' THEN o.AckDate END,
               CASE WHEN n.Severity = 'WARNING' THEN o.AckReason END
        FROM @New n
        OUTER APPLY (SELECT TOP 1 * FROM @Old o WHERE o.RuleCode = n.RuleCode AND ISNULL(o.EmployeeId, 0) = ISNULL(n.EmployeeId, 0)) AS o;

        UPDATE [Payroll].[PayrollRuns]
           SET ErrorCount   = (SELECT COUNT(1) FROM @New WHERE Severity = 'ERROR'),
               WarningCount = (SELECT COUNT(1) FROM @New WHERE Severity = 'WARNING'),
               ValidatedDate = @Now
        WHERE PayrollRunId = @RunId;
    COMMIT TRANSACTION;
END;
GO


/* ---- 3. Payroll.usp_Collection_Manage (db/115): approved payrolls only */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_Manage]
    @Action         VARCHAR(20),
    @CompanyId      INT             = NULL,     -- the company picked on the page (DASHBOARD: NULL = every company in scope)
    @CompanyIds     NVARCHAR(2000)  = NULL,     -- the companies the user may open (CSV; NULL = any)
    @Month          DATE            = NULL,     -- the payroll month (any day of it)
    @Status         VARCHAR(10)     = NULL,     -- LIST: PENDING / COLLECTED / NULL = both (pending first)
    @Search         NVARCHAR(200)   = NULL,
    @Id             BIGINT          = NULL,
    @Ids            NVARCHAR(MAX)   = NULL,     -- COLLECT: CSV of collection ids
    @CollectedDate  DATE            = NULL,
    @Reference      NVARCHAR(100)   = NULL,
    @Comment        NVARCHAR(500)   = NULL,
    @UserId         BIGINT          = NULL,
    @TotalCount     INT             = NULL OUTPUT,
    @NewId          BIGINT          = NULL OUTPUT,
    @ResultCode     VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = NULL, @TotalCount = 0, @NewId = NULL;

    IF @Action NOT IN ('MONTHS', 'LIST', 'SUMMARY', 'DASHBOARD', 'COLLECT', 'REOPEN', 'HISTORY')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @Month   = CASE WHEN @Month IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) END;
    SET @Status  = NULLIF(UPPER(LTRIM(RTRIM(@Status))), '');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Reference = NULLIF(LTRIM(RTRIM(@Reference)), N'');
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    DECLARE @Allowed TABLE (CompanyId INT PRIMARY KEY);
    IF NULLIF(LTRIM(RTRIM(@CompanyIds)), N'') IS NOT NULL
        INSERT INTO @Allowed (CompanyId)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@CompanyIds, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
    DECLARE @AnyCompany BIT = CASE WHEN EXISTS (SELECT 1 FROM @Allowed) THEN 0 ELSE 1 END;

    /* the collections of live payrolls (not cancelled, not deleted) the user may see */
    DECLARE @Live TABLE (CollectionId BIGINT PRIMARY KEY);
    INSERT INTO @Live (CollectionId)
    SELECT  c.CollectionId
    FROM    [Payroll].[Collections] AS c
    JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
    WHERE   c.Deleted = 0 AND r.Deleted = 0 AND r.Stage = 'CLOSED'      -- db/119: approved payrolls only
      AND   (@AnyCompany = 1 OR c.CompanyId IN (SELECT CompanyId FROM @Allowed))
      AND   (@Action IN ('COLLECT', 'REOPEN', 'HISTORY')
             OR ((c.CompanyId = @CompanyId OR (@Action = 'DASHBOARD' AND @CompanyId IS NULL)) AND (@Month IS NULL OR c.RunMonth = @Month)));

    /* ======================= MONTHS ============================== */
    /* the payroll months of the company (regular payrolls), newest first, with how much is due */
    IF @Action = 'MONTHS'
    BEGIN
        IF @AnyCompany = 0 AND NOT EXISTS (SELECT 1 FROM @Allowed WHERE CompanyId = @CompanyId) RETURN;
        SELECT  m.RunMonth,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN c.Amount END), 0) AS PendingAmount,
                COUNT(c.CollectionId) AS CollectionCount
        FROM   (SELECT DISTINCT r.RunMonth FROM [Payroll].[PayrollRuns] AS r
                WHERE r.CompanyId = @CompanyId AND r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR') AS m
        LEFT JOIN [Payroll].[Collections] AS c ON c.RunMonth = m.RunMonth AND c.CompanyId = @CompanyId
                                               AND c.CollectionId IN (SELECT CollectionId FROM @Live)
        GROUP BY m.RunMonth
        ORDER BY m.RunMonth DESC;
        RETURN;
    END;

    /* ======================= SUMMARY / DASHBOARD ================= */
    /* DASHBOARD: the Payroll Dashboard's month - every company in scope, or the one given */
    IF @Action IN ('SUMMARY', 'DASHBOARD')
    BEGIN
        SELECT  ISNULL(SUM(c.Amount), 0)                                              AS TotalAmount,
                COUNT(c.CollectionId)                                                 AS TotalCount,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN c.Amount END), 0)      AS PendingAmount,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN 1 ELSE 0 END), 0)      AS PendingCount,
                ISNULL(SUM(CASE WHEN c.Status = 'COLLECTED' THEN c.Amount END), 0)    AS CollectedAmount,
                ISNULL(SUM(CASE WHEN c.Status = 'COLLECTED' THEN 1 ELSE 0 END), 0)    AS CollectedCount
        FROM    [Payroll].[Collections] AS c
        WHERE   c.CollectionId IN (SELECT CollectionId FROM @Live);
        RETURN;
    END;

    /* ======================= LIST ================================ */
    /* not collected first, then by employee */
    IF @Action = 'LIST'
    BEGIN
        SELECT  c.CollectionId, c.CompanyId, c.PayrollRunId, r.RunCode, r.Stage AS RunStage, c.RunMonth,
                c.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName AS EmployeeArabicName, re.DepartmentName,
                c.GrossMonthly, c.WorkPermitSalary, c.Amount, c.Status,
                c.CollectedDate, c.Reference, c.Comment, c.CollectedOn,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS CollectedByName
        FROM    [Payroll].[Collections] AS c
        JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
        LEFT JOIN [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = c.RunEmployeeId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = c.CollectedBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   c.CollectionId IN (SELECT CollectionId FROM @Live)
          AND   (@Status IS NULL OR c.Status = @Status)
          AND   (@Pattern IS NULL OR re.EmployeeName LIKE @Pattern ESCAPE '\' OR re.ArabicName LIKE @Pattern ESCAPE '\'
                 OR re.EmployeeNo LIKE @Pattern ESCAPE '\' OR c.Reference LIKE @Pattern ESCAPE '\')
        ORDER BY CASE WHEN c.Status = 'PENDING' THEN 0 ELSE 1 END, re.EmployeeName, c.CollectionId;
        SET @TotalCount = @@ROWCOUNT;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Live WHERE CollectionId = @Id) RETURN;
        SELECT  h.CollectionHistoryId, h.ActionCode, h.OldAmount, h.NewAmount, h.CollectedDate, h.Reference, h.Comment, h.ActionDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Payroll].[CollectionHistory] AS h
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   h.CollectionId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate DESC, h.CollectionHistoryId DESC;
        RETURN;
    END;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    /* ======================= COLLECT ============================= */
    /* mark one or more pending collections as received (with the date and an optional
       receipt reference); only once the payroll is created - a draft can still change */
    IF @Action = 'COLLECT'
    BEGIN
        DECLARE @Pick TABLE (CollectionId BIGINT PRIMARY KEY);
        INSERT INTO @Pick (CollectionId)
        SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@Ids, CAST(@Id AS NVARCHAR(30))), ',')
        WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

        IF NOT EXISTS (SELECT 1 FROM @Pick)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the collections that were received.';
            RETURN;
        END;
        SET @CollectedDate = ISNULL(@CollectedDate, @Today);
        IF @CollectedDate > @Today
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The date received cannot be in the future.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Pick p WHERE NOT EXISTS (SELECT 1 FROM @Live l WHERE l.CollectionId = p.CollectionId))
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'A selected collection no longer exists. The list has been refreshed.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Pick p JOIN [Payroll].[Collections] c ON c.CollectionId = p.CollectionId WHERE c.Status <> 'PENDING')
        BEGIN
            SELECT @ResultCode = 'ALREADY', @ResultMessage = N'A selected collection was already marked as received. The list has been refreshed.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE c
               SET Status = 'COLLECTED', CollectedDate = @CollectedDate, Reference = @Reference, Comment = @Comment,
                   CollectedBy = @UserId, CollectedOn = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            FROM   [Payroll].[Collections] AS c
            JOIN   @Pick AS p ON p.CollectionId = c.CollectionId;
            SET @TotalCount = @@ROWCOUNT;

            INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, CollectedDate, Reference, Comment, ActionBy)
            SELECT c.CollectionId, 'COLLECTED', NULL, c.Amount, @CollectedDate, @Reference, @Comment, @UserId
            FROM   [Payroll].[Collections] AS c
            JOIN   @Pick AS p ON p.CollectionId = c.CollectionId;
        COMMIT TRANSACTION;

        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'Marked as received.' ELSE CONCAT(@TotalCount, N' collections marked as received.') END;
        RETURN;
    END;

    /* ======================= REOPEN ============================== */
    /* undo a "received" marked by mistake - back to pending, with the reason */
    IF @Action = 'REOPEN'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Live WHERE CollectionId = @Id)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This collection no longer exists.';
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[Collections] WHERE CollectionId = @Id AND Status = 'COLLECTED')
        BEGIN
            SELECT @ResultCode = 'NOT_COLLECTED', @ResultMessage = N'This collection is not marked as received.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter why it is set back to pending.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, CollectedDate, Reference, Comment, ActionBy)
            SELECT CollectionId, 'REOPENED', Amount, NULL, CollectedDate, Reference, @Comment, @UserId
            FROM   [Payroll].[Collections] WHERE CollectionId = @Id;

            UPDATE [Payroll].[Collections]
               SET Status = 'PENDING', CollectedDate = NULL, Reference = NULL, Comment = NULL, CollectedBy = NULL, CollectedOn = NULL,
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE CollectionId = @Id;
        COMMIT TRANSACTION;
        SELECT @NewId = @Id, @ResultMessage = N'Set back to pending.';
        RETURN;
    END;
END;
GO

/* ---- 4. Payroll.usp_Collection_FromPayroll - the collections of an approved payroll */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_FromPayroll]
    @RunId   BIGINT,
    @UserId  BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* an approved (closed) regular payroll only */
    DECLARE @CompanyId INT, @RunMonth DATE;
    SELECT  @CompanyId = r.CompanyId, @RunMonth = r.RunMonth
    FROM    [Payroll].[PayrollRuns] AS r
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR';
    IF @CompanyId IS NULL RETURN;

    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0)
        EXEC [Payroll].[usp_PayComponent_SeedCollection] @CompanyId = @CompanyId, @UserId = @UserId;
    DECLARE @CollId INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents]
                           WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0 AND IsActive = 1);
    IF @CollId IS NULL RETURN;      -- the type is deactivated: no collections

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    /* Gross Monthly (contract Basic Salary + Allowances) below the Work Permit Salary */
    DECLARE @Coll TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, Gross DECIMAL(12,3) NOT NULL,
                         Wps DECIMAL(12,3) NOT NULL, Amt DECIMAL(12,3) NOT NULL);
    INSERT INTO @Coll (RunEmployeeId, EmployeeId, Gross, Wps, Amt)
    SELECT  re.RunEmployeeId, re.EmployeeId, g.Gross, k.WorkPermitSalary, k.WorkPermitSalary - g.Gross
    FROM    [Payroll].[PayrollRunEmployees] AS re
    JOIN    [Kuwait].[EmployeeCompliance] AS k  ON k.EmployeeId = re.EmployeeId AND k.Deleted = 0
    JOIN    [Employee].[EmployeePayroll]  AS ep ON ep.EmployeeId = re.EmployeeId AND ep.Deleted = 0
    CROSS APPLY (SELECT CAST(ISNULL(ep.BasicSalary, 0) + ISNULL(ep.Allowances, 0) AS DECIMAL(12,3)) AS Gross) AS g
    WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0
      AND   ISNULL(ep.BasicSalary, 0) > 0
      AND   k.WorkPermitSalary > g.Gross;

    DECLARE @CollNew TABLE (CollectionId BIGINT PRIMARY KEY, Amount DECIMAL(12,3) NOT NULL);

    BEGIN TRANSACTION;
        /* a pending one follows the figures; one already collected is never changed */
        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  x.CollectionId, 'UPDATED', x.Amount, c.Amt, N'Payroll approved', @UserId
        FROM    [Payroll].[Collections] AS x
        JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING' AND x.Amount <> c.Amt;

        UPDATE  x
           SET  Amount = c.Amt, GrossMonthly = c.Gross, WorkPermitSalary = c.Wps, RunEmployeeId = c.RunEmployeeId,
                ModifiedBy = @UserId, ModifiedDate = @Now
        FROM    [Payroll].[Collections] AS x
        JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   (x.Amount <> c.Amt OR x.GrossMonthly <> c.Gross OR x.WorkPermitSalary <> c.Wps OR x.RunEmployeeId <> c.RunEmployeeId);

        /* no longer due (e.g. approved again after a change) */
        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  x.CollectionId, 'REMOVED', x.Amount, NULL, N'No longer due when the payroll was approved', @UserId
        FROM    [Payroll].[Collections] AS x
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId);
        UPDATE  x SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM    [Payroll].[Collections] AS x
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId);

        INSERT INTO [Payroll].[Collections] (CompanyId, PayrollRunId, RunEmployeeId, EmployeeId, RunMonth, PayComponentId,
                                             GrossMonthly, WorkPermitSalary, Amount, Status, CreatedBy)
        OUTPUT  inserted.CollectionId, inserted.Amount INTO @CollNew (CollectionId, Amount)
        SELECT  @CompanyId, @RunId, c.RunEmployeeId, c.EmployeeId, @RunMonth, @CollId, c.Gross, c.Wps, c.Amt, 'PENDING', @UserId
        FROM    @Coll AS c
        WHERE   NOT EXISTS (SELECT 1 FROM [Payroll].[Collections] x
                            WHERE x.PayrollRunId = @RunId AND x.EmployeeId = c.EmployeeId AND x.Deleted = 0);

        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  n.CollectionId, 'CREATED', NULL, n.Amount, N'Payroll approved - gross monthly below the work permit salary', @UserId
        FROM    @CollNew AS n;
    COMMIT TRANSACTION;
END;
GO

/* ---- 5. first run: collections only for approved payrolls ----------------- */
INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment)
SELECT  c.CollectionId, 'REMOVED', c.Amount, NULL, N'Recorded once the payroll is approved'
FROM    [Payroll].[Collections] AS c
JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
WHERE   c.Deleted = 0 AND c.Status = 'PENDING' AND r.Stage <> 'CLOSED';

UPDATE  c SET Deleted = 1, DeletedDate = SYSUTCDATETIME()
FROM    [Payroll].[Collections] AS c
JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
WHERE   c.Deleted = 0 AND c.Status = 'PENDING' AND r.Stage <> 'CLOSED';
PRINT CONCAT(N'Pending collections of payrolls not approved yet removed: ', @@ROWCOUNT);
GO

DECLARE @Run BIGINT, @Done INT = 0;
DECLARE runs CURSOR LOCAL FAST_FORWARD FOR
    SELECT PayrollRunId FROM [Payroll].[PayrollRuns] WHERE Deleted = 0 AND Stage = 'CLOSED' AND RunType = 'REGULAR';
OPEN runs;
FETCH NEXT FROM runs INTO @Run;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Payroll].[usp_Collection_FromPayroll] @RunId = @Run;
    SET @Done += 1;
    FETCH NEXT FROM runs INTO @Run;
END;
CLOSE runs; DEALLOCATE runs;
PRINT CONCAT(N'Approved payrolls checked for collections: ', @Done);
GO

/* ---- 6. the texts --------------------------------------------------------- */
UPDATE l SET EnglishText = v.EnglishText, ArabicText = v.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN  (VALUES
        ('col.intro_text', N'When an employee''s gross monthly salary (Basic + Allowances) is below the work permit salary, approving the payroll records the difference here. It is for the company''s records only - not on the payslip, in the net pay or the bank file. Mark it here once collected.', N'عندما يكون إجمالي الراتب الشهري للموظف (الأساسي + البدلات) أقل من راتب إذن العمل، يُسجَّل الفرق هنا عند اعتماد الرواتب. وهو لسجلات الشركة فقط - لا يظهر في قسيمة الراتب أو صافي الراتب أو ملف البنك. سجّل تحصيله هنا.'),
        ('col.none_this_month_text', N'Every employee''s gross monthly salary reaches their work permit salary, or the payroll is not approved yet.', N'إجمالي الراتب الشهري لكل موظف يصل إلى راتب إذن العمل، أو لم تُعتمد الرواتب بعد.'),
        ('col.no_payroll_yet', N'No approved payroll for this company yet', N'لا توجد رواتب معتمدة لهذه الشركة بعد'),
        ('col.no_payroll_yet_text', N'Collections are recorded when a payroll is approved.', N'تُسجَّل التحصيلات عند اعتماد الرواتب.')
      ) AS v (LabelKey, EnglishText, ArabicText) ON v.LabelKey = l.LabelKey COLLATE DATABASE_DEFAULT
WHERE  l.Deleted = 0;
PRINT CONCAT(N'Collection texts updated: ', @@ROWCOUNT);

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('msg.pr_v01_profile', 'msg', N'No Basic Salary on the employee profile (Employee > Employment > Payroll & Bank)', N'لا يوجد راتب أساسي في ملف الموظف (الموظف > التوظيف > الرواتب والبنك)', NULL),
        ('msg.pr_salary_contract', 'msg', N'Monthly salary (employment contract)', N'الراتب الشهري (عقد العمل)', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
