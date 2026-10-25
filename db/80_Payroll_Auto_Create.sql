/* =====================================================================
   80_Payroll_Auto_Create.sql  -  HRMS: Create Payroll by month only
   ---------------------------------------------------------------------
   Run after 79. Safe to re-run. Re-run it after 35_Payroll_Processing_
   StoredProcedures1.sql whenever that script is run again (it replaces
   the engine below with its older copy).

   Create Payroll no longer asks for a payroll calendar or a period: the
   user picks the company and the month, and the application makes one
   payroll per payroll calendar its employees are assigned to (Employee.
   PayrollCalendarId; no calendar = the company's default), using that
   calendar's period of the month - the periods of the month are
   generated when the calendar has none yet.

   This script: the engine (Payroll.usp_PayrollRun_Calculate) pays an
   employee in ONE regular payroll per month. An employee already in
   another created regular payroll of the same month (Registered,
   Validation, Awaiting approval or Closed - e.g. moved to another
   calendar after his first payroll) is left out. Off-cycle payrolls are
   not affected. Everything else is as in db/35.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[usp_PayrollRun_Calculate]', N'P') IS NULL
    RAISERROR(N'Run 35_Payroll_Processing_StoredProcedures1.sql first.', 16, 1);
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

    /* the profile salary is paid through the company's Basic Salary / Other Allowances
       pay components: a company set up after the payroll seed (db/32) gets the defaults now */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND Deleted = 0 AND ComponentCode = N'BASIC')
       AND OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @CompanyId, @UserId = @UserId;

    DECLARE @PeriodDays INT = DATEDIFF(DAY, @Start, @End) + 1;
    DECLARE @BasisDays  INT = CASE WHEN @Freq = 'MONTHLY' THEN @PeriodDays ELSE DAY(EOMONTH(@RunMonth)) END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRANSACTION;

    /* ---- 1. who is in the run (whole-run calculation only) ----------- */
    IF @EmployeeIds IS NULL
    BEGIN
        /* a payroll pays the employees of ITS calendar (db/60); an employee with no
           calendar yet is paid by the company's default calendar */
        DECLARE @DefaultCal BIT = CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                                                    WHERE PayrollCalendarId = @CalendarId AND IsDefault = 1) THEN 1 ELSE 0 END;
        DECLARE @Eligible TABLE (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO @Eligible (EmployeeId)
        SELECT e.EmployeeId
        FROM   [Employee].[Employees] AS e
        LEFT JOIN [Core].[Countries]  AS n ON n.CountryId = e.NationalityCountryId
        WHERE  e.CompanyId = @CompanyId AND e.Deleted = 0 AND e.IsDeleted = 0
          AND  (e.PayrollCalendarId = @CalendarId OR (e.PayrollCalendarId IS NULL AND @DefaultCal = 1))
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

    /* ---- 5a. salary items (regular runs, off-cycle catch-up) --------- */
    IF @RunType = 'REGULAR' OR EXISTS (SELECT 1 FROM @T WHERE CatchUp = 1)
    BEGIN
        ;WITH s AS (
            SELECT  i.*, c.ComponentName, c.ArabicName AS CompArabic, c.IsProrated, c.DisplayOrder,
                    ROW_NUMBER() OVER (PARTITION BY i.EmployeeId, i.PayComponentId ORDER BY i.StartMonth DESC, i.EmployeePayItemId DESC) AS rn
            FROM    [Payroll].[EmployeePayItems] AS i
            JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            JOIN    @T AS t ON t.EmployeeId = i.EmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
            WHERE   i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
              AND   c.ItemClass = 'SALARY' AND i.AppliesMode = 'MONTHLY'
              AND   i.StartMonth <= @RunMonth AND (i.EndMonth IS NULL OR i.EndMonth >= @RunMonth)
        )
        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, EmployeePayItemId, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, re.RunEmployeeId, s.EmployeeId, s.PayComponentId, 'SALARY', s.ComponentName, s.CompArabic,
                CASE WHEN s.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN CONCAT(N'Prorated ', re.PaidDays, N' of ', re.PeriodDays, N' days')
                     ELSE ISNULL(NULLIF(LTRIM(RTRIM(s.Comment)), N''), N'Monthly salary item') END,
                'SALARY', s.EmployeePayItemId, s.Amount,
                CASE WHEN s.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN ROUND(s.Amount * re.PaidDays / NULLIF(re.PeriodDays, 0), 3) ELSE s.Amount END,
                s.DisplayOrder
        FROM    s
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = @RunId AND re.EmployeeId = s.EmployeeId AND re.Deleted = 0
        WHERE   s.rn = 1;

        /* no salary items at all yet -> basic + allowances from the employee profile */
        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, re.RunEmployeeId, re.EmployeeId, c.PayComponentId, 'SALARY', c.ComponentName, c.ArabicName,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN CONCAT(N'Prorated ', re.PaidDays, N' of ', re.PeriodDays, N' days')
                     ELSE N'From the employee profile' END,
                'PROFILE', v.Amount,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN ROUND(v.Amount * re.PaidDays / NULLIF(re.PeriodDays, 0), 3) ELSE v.Amount END,
                c.DisplayOrder
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    @T AS t ON t.RunEmployeeId = re.RunEmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
        JOIN    [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = re.EmployeeId AND ep.Deleted = 0
        CROSS APPLY (VALUES ('BASIC', ep.BasicSalary), ('OTHER_ALW', ep.Allowances)) AS v(Code, Amount)
        JOIN    [Payroll].[PayComponents] AS c ON c.CompanyId = @CompanyId AND c.ComponentCode = v.Code AND c.Deleted = 0
        WHERE   v.Amount > 0
          AND   NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] i
                            JOIN [Payroll].[PayComponents] ic ON ic.PayComponentId = i.PayComponentId
                            WHERE i.EmployeeId = re.EmployeeId AND i.Deleted = 0 AND ic.ItemClass = 'SALARY' AND i.PayrollRunId IS NULL);
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

PRINT N'Payroll engine: one regular payroll per employee per month.';
GO
