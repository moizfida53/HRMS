/* =====================================================================
   35_Payroll_Processing_StoredProcedures.sql  -  HRMS Payroll Phase 2
   ---------------------------------------------------------------------
   Run after 34. CREATE OR ALTER everywhere - safe to re-run.

     Payroll.usp_PayrollRun_Calculate      the payroll engine (internal)
     Payroll.usp_PayrollRun_Validate       validation rules V01-V20 (internal)
     Payroll.usp_PayrollRun_Manage         runs: LIST / GET / NEXT_CODE /
                                           PERIODS / DRAFTS / DRAFT_SAVE /
                                           FINALIZE / DISCARD / RECALC /
                                           SET_STAGE / APPROVE / CANCEL /
                                           REOPEN / HISTORY
     Payroll.usp_PayrollRunEmployee_Manage employees and lines of a run:
                                           LIST / LINES / SUMMARY /
                                           COMPONENTS / ADD_LINE /
                                           REMOVE_LINE / EXCLUDE / INCLUDE /
                                           COMPARE
     Payroll.usp_PayrollRunIssue_Manage    validation results: LIST / ACK

   Calculation rules (one payroll month at a time)
     * Who: active employees of the company (Employee.IsDeleted = 0) hired
       on or before the period end and not terminated before its start,
       narrowed by the run's scope (department, location, employment type,
       nationality). Excluded employees stay listed with a reason, unpaid.
     * Salary items (class SALARY, every month) are prorated by days
       employed in the period when the item type is "Prorated":
       monthly calendar  amount x paid days / period days
       weekly / bi-weekly amount x paid days / days in the payroll month
       An employee with no salary items at all falls back to the basic
       salary and allowances on the employee profile (Employee.EmployeePayroll).
     * Earnings / deductions apply once, every month or in instalments;
       loans and advances in instalments until the count is reached. An item
       is paid by one live payroll per month only (no double payment by an
       off-cycle run). Off-cycle runs pay only the lines added in them.
     * PIFSS employee share for Kuwaiti employees from the effective rates in
       Payroll.PifssContributionRates on the PIFSS-applicable salary lines.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* =====================================================================
   ENGINE
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Calculate]
    @RunId        BIGINT,
    @EmployeeIds  NVARCHAR(MAX) = NULL,   -- CSV; NULL = whole run (also re-syncs who is in it)
    @UserId       BIGINT        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CompanyId INT, @Start DATE, @End DATE, @RunMonth DATE, @RunType VARCHAR(10), @Stage VARCHAR(20),
            @Freq VARCHAR(10), @Dept INT, @Loc INT, @EmpType NVARCHAR(20), @Nat VARCHAR(12), @CalendarId INT;

    SELECT  @CompanyId = r.CompanyId, @Start = p.StartDate, @End = p.EndDate, @RunMonth = r.RunMonth,
            @RunType = r.RunType, @Stage = r.Stage, @Freq = pc.PayFrequency, @CalendarId = r.PayrollCalendarId,
            @Dept = r.ScopeDepartmentId, @Loc = r.ScopeWorkLocationId, @EmpType = r.ScopeEmploymentType, @Nat = r.ScopeNationality
    FROM    [Payroll].[PayrollRuns]      AS r
    JOIN    [Payroll].[PayrollPeriods]   AS p  ON p.PayrollPeriodId    = r.PayrollPeriodId
    JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0;

    IF @CompanyId IS NULL OR @Stage NOT IN ('DRAFT', 'REGISTERED')
        RETURN;

    DECLARE @PeriodDays INT = DATEDIFF(DAY, @Start, @End) + 1;
    DECLARE @BasisDays  INT = CASE WHEN @Freq = 'MONTHLY' THEN @PeriodDays ELSE DAY(EOMONTH(@RunMonth)) END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRANSACTION;

    /* ---- 1. who is in the run (whole-run calculation only) ----------- */
    IF @EmployeeIds IS NULL
    BEGIN
        DECLARE @Eligible TABLE (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO @Eligible (EmployeeId)
        SELECT e.EmployeeId
        FROM   [Employee].[Employees] AS e
        LEFT JOIN [Core].[Countries]  AS n ON n.CountryId = e.NationalityCountryId
        WHERE  e.CompanyId = @CompanyId AND e.Deleted = 0 AND e.IsDeleted = 0
          AND  (e.HireDate IS NULL OR e.HireDate <= @End)
          AND  (e.TerminationDate IS NULL OR e.TerminationDate >= @Start)
          AND  NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)
          AND  (@Dept    IS NULL OR e.DepartmentId   = @Dept)
          AND  (@Loc     IS NULL OR e.WorkLocationId = @Loc)
          AND  (@EmpType IS NULL OR e.EmploymentType = @EmpType)
          AND  (@Nat     IS NULL OR (@Nat = 'KUWAITI' AND n.CountryCode IN ('KW', 'KWT'))
                                 OR (@Nat = 'NON_KUWAITI' AND ISNULL(n.CountryCode, '') NOT IN ('KW', 'KWT')));

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
    DECLARE @T TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, IsExcluded BIT NOT NULL);
    INSERT INTO @T (RunEmployeeId, EmployeeId, IsExcluded)
    SELECT re.RunEmployeeId, re.EmployeeId, re.IsExcluded
    FROM   [Payroll].[PayrollRunEmployees] AS re
    WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0
      AND  (@EmployeeIds IS NULL OR re.EmployeeId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@EmployeeIds, ',')));

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
    LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId
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

    /* ---- 5a. salary items (regular runs) ----------------------------- */
    IF @RunType = 'REGULAR'
    BEGIN
        ;WITH s AS (
            SELECT  i.*, c.ComponentName, c.ArabicName AS CompArabic, c.IsProrated, c.DisplayOrder,
                    ROW_NUMBER() OVER (PARTITION BY i.EmployeeId, i.PayComponentId ORDER BY i.StartMonth DESC, i.EmployeePayItemId DESC) AS rn
            FROM    [Payroll].[EmployeePayItems] AS i
            JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            JOIN    @T AS t ON t.EmployeeId = i.EmployeeId AND t.IsExcluded = 0
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
        JOIN    @T AS t ON t.RunEmployeeId = re.RunEmployeeId AND t.IsExcluded = 0
        JOIN    [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = re.EmployeeId
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
                 OR (@RunType = 'REGULAR' AND i.PayrollRunId IS NULL AND ISNULL(u.ThisMonth, 0) = 0 AND (
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

    /* ---- 5c. PIFSS employee share (Kuwaiti, regular runs) ------------ */
    IF @RunType = 'REGULAR'
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
                JOIN    @T AS t ON t.RunEmployeeId = l.RunEmployeeId AND t.IsExcluded = 0
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

/* =====================================================================
   VALIDATION
     ERROR    V01 no salary            V03 negative net        V20 no employees
     WARNING  V02 salary from profile  V07 no bank account      V10 unverified PIFSS rates
              V11 no cost center       V12 deductions > 50 %    V15 net changed > 25 %
              V17 work permit / residency expires before pay date
              V18 zero net pay         V19 suspended / on leave
   Acknowledgements survive a re-validation (same rule + employee).
   ===================================================================== */
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
        INSERT INTO @New SELECT EmployeeId, 'V01', 'ERROR', N'No salary items' FROM @E WHERE HasSalary = 0;
        INSERT INTO @New
        SELECT DISTINCT l.EmployeeId, 'V02', 'WARNING', N'Salary taken from the employee profile - add salary items on Pay Items'
        FROM [Payroll].[PayrollRunLines] l JOIN @E e ON e.EmployeeId = l.EmployeeId
        WHERE l.PayrollRunId = @RunId AND l.Deleted = 0 AND l.Source = 'PROFILE';
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

/* =====================================================================
   RUNS
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Manage]
    @Action               VARCHAR(20),
    @Id                   BIGINT          = NULL,

    /* list filters */
    @CompanyId            INT             = NULL,
    @CompanyIds           NVARCHAR(2000)  = NULL,
    @RunMonth             DATE            = NULL,
    @StageFilter          VARCHAR(20)     = NULL,     -- a stage, or 'FINISHED' = closed + cancelled
    @TypeFilter           VARCHAR(10)     = NULL,
    @Year                 INT             = NULL,
    @Search               NVARCHAR(200)   = NULL,
    @PageNumber           INT             = 1,
    @PageSize             INT             = 25,

    /* create / draft */
    @PayrollCalendarId    INT             = NULL,
    @PayrollPeriodId      INT             = NULL,
    @RunType              VARCHAR(10)     = NULL,
    @Description          NVARCHAR(500)   = NULL,
    @ScopeDepartmentId    INT             = NULL,
    @ScopeWorkLocationId  INT             = NULL,
    @ScopeEmploymentType  NVARCHAR(20)    = NULL,
    @ScopeNationality     VARCHAR(12)     = NULL,

    /* stage changes */
    @Stage                VARCHAR(20)     = NULL,
    @Comment              NVARCHAR(500)   = NULL,
    @AllowSelfApproval    BIT             = 0,

    @UserId               BIGINT          = NULL,

    @TotalCount           INT             = NULL OUTPUT,
    @NewId                BIGINT          = NULL OUTPUT,
    @ResultCode           VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage        NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    SET @Description = NULLIF(LTRIM(RTRIM(@Description)), N'');
    SET @Comment     = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Search      = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @PageNumber  = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize    = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 500 THEN 500 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action NOT IN ('LIST', 'GET', 'NEXT_CODE', 'PERIODS', 'DRAFTS', 'DRAFT_SAVE', 'FINALIZE', 'DISCARD', 'RECALC', 'VALIDATE',
                       'SET_STAGE', 'APPROVE', 'CANCEL', 'REOPEN', 'HISTORY', 'MONTHS')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= LIST / GET ========================== */
    IF @Action IN ('LIST', 'GET')
    BEGIN
        DECLARE @L TABLE (PayrollRunId BIGINT PRIMARY KEY);
        INSERT INTO @L (PayrollRunId)
        SELECT r.PayrollRunId
        FROM   [Payroll].[PayrollRuns] AS r
        WHERE  r.Deleted = 0
          AND  (   (@Action = 'GET'  AND r.PayrollRunId = @Id)
                OR (@Action = 'LIST' AND r.Stage <> 'DRAFT'
                    AND (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
                    AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
                    AND (@RunMonth   IS NULL OR r.RunMonth = @RunMonth)
                    AND (@Year       IS NULL OR YEAR(r.RunMonth) = @Year)
                    AND (@TypeFilter IS NULL OR r.RunType = @TypeFilter)
                    AND (@StageFilter IS NULL OR r.Stage = @StageFilter OR (@StageFilter = 'FINISHED' AND r.Stage IN ('CLOSED', 'CANCELLED'))
                                              OR (@StageFilter = 'LIVE' AND r.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')))
                    AND (@Pattern IS NULL OR r.RunCode LIKE @Pattern ESCAPE '\' OR r.Description LIKE @Pattern ESCAPE '\')));

        SET @TotalCount = (SELECT COUNT(1) FROM @L);

        SELECT  r.PayrollRunId, r.CompanyId, co.CompanyCode, co.CompanyName, r.PayrollCalendarId, pc.CalendarCode, pc.CalendarName,
                pc.ArabicName AS CalendarArabicName, pc.PayFrequency,
                r.PayrollPeriodId, p.PeriodName, p.PeriodNumber, p.StartDate, p.EndDate, p.PaymentDate, p.Status AS PeriodStatus,
                r.RunMonth, r.RunSeq, r.RunCode, r.RunType, r.Description, r.Stage, r.ApprovalLevel,
                r.ScopeDepartmentId, r.ScopeWorkLocationId, r.ScopeEmploymentType, r.ScopeNationality,
                r.EmployeeCount, r.ExcludedCount, r.TotalSalary, r.TotalEarnings, r.TotalDeductions, r.TotalNet,
                r.TotalSalary + r.TotalEarnings AS TotalGross,
                r.ErrorCount, r.WarningCount,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunIssues] i WHERE i.PayrollRunId = r.PayrollRunId AND i.Deleted = 0
                   AND i.Severity = 'WARNING' AND i.IsAcknowledged = 1) AS AcknowledgedCount,
                r.CalculatedDate, r.ValidatedDate, r.SubmittedBy, r.SubmittedDate, r.ClosedDate, r.CancelledDate, r.CancelReason,
                r.CreatedBy, r.CreatedDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ce.FirstName, N' ', ce.LastName))), N''), cu.Username) AS CreatedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(se.FirstName, N' ', se.LastName))), N''), su.Username) AS SubmittedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(xe.FirstName, N' ', xe.LastName))), N''), xu.Username) AS ClosedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ke.FirstName, N' ', ke.LastName))), N''), ku.Username) AS CancelledByName,
                (SELECT MAX(h.ActionDate) FROM [Payroll].[PayrollRunHistory] h WHERE h.PayrollRunId = r.PayrollRunId AND h.Deleted = 0) AS LastActionDate,
                (SELECT TOP 1 h.ActionBy FROM [Payroll].[PayrollRunHistory] h WHERE h.PayrollRunId = r.PayrollRunId AND h.Deleted = 0
                   AND h.ActionCode = 'APPROVED' AND h.ApprovalLevel = 1 ORDER BY h.ActionDate DESC) AS Level1ApprovedBy
        FROM    @L AS l
        JOIN    [Payroll].[PayrollRuns]      AS r  ON r.PayrollRunId = l.PayrollRunId
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]   AS p  ON p.PayrollPeriodId = r.PayrollPeriodId
        LEFT JOIN [Security].[Users] AS cu ON cu.UserId = r.CreatedBy   LEFT JOIN [Employee].[Employees] ce ON ce.EmployeeId = cu.EmployeeId
        LEFT JOIN [Security].[Users] AS su ON su.UserId = r.SubmittedBy LEFT JOIN [Employee].[Employees] se ON se.EmployeeId = su.EmployeeId
        LEFT JOIN [Security].[Users] AS xu ON xu.UserId = r.ClosedBy    LEFT JOIN [Employee].[Employees] xe ON xe.EmployeeId = xu.EmployeeId
        LEFT JOIN [Security].[Users] AS ku ON ku.UserId = r.CancelledBy LEFT JOIN [Employee].[Employees] ke ON ke.EmployeeId = ku.EmployeeId
        ORDER BY r.RunMonth DESC, r.RunSeq DESC, r.PayrollRunId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= MONTHS (filter options) ============= */
    IF @Action = 'MONTHS'
    BEGIN
        SELECT r.RunMonth, COUNT(1) AS RunCount
        FROM   [Payroll].[PayrollRuns] r
        WHERE  r.Deleted = 0 AND r.Stage <> 'DRAFT'
          AND  (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        GROUP BY r.RunMonth
        ORDER BY r.RunMonth DESC;
        RETURN;
    END;

    /* ======================= PERIODS (with payroll counts) ======= */
    IF @Action = 'PERIODS'
    BEGIN
        SELECT  p.PayrollPeriodId, p.PayrollCalendarId, p.PayrollYear AS PeriodYear, p.PayrollMonth, p.PeriodNumber, p.PeriodCode, p.PeriodName,
                p.StartDate, p.EndDate, p.CutOffDate, p.PaymentDate, p.Status, p.Remarks, pc.PayFrequency,
                DATEFROMPARTS(p.PayrollYear, p.PayrollMonth, 1) AS RunMonth,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] r WHERE r.PayrollPeriodId = p.PayrollPeriodId AND r.Deleted = 0 AND r.Stage <> 'DRAFT') AS RunCount,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] r WHERE r.PayrollPeriodId = p.PayrollPeriodId AND r.Deleted = 0 AND r.Stage = 'CANCELLED') AS CancelledCount
        FROM    [Payroll].[PayrollPeriods] AS p
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        WHERE   p.Deleted = 0 AND p.PayrollCalendarId = @PayrollCalendarId
          AND   (@Year IS NULL OR p.PayrollYear = @Year)
          AND   (@StageFilter IS NULL OR (@StageFilter = 'OPENABLE' AND p.Status IN ('OPEN', 'PROCESSING', 'APPROVED')))
        ORDER BY p.StartDate;
        RETURN;
    END;

    /* ======================= NEXT_CODE =========================== */
    IF @Action = 'NEXT_CODE'
    BEGIN
        DECLARE @nCo INT, @nCode NVARCHAR(30), @nMonth DATE, @nSeq INT;
        SELECT @nCo = pc.CompanyId, @nCode = co.CompanyCode, @nMonth = DATEFROMPARTS(p.PayrollYear, p.PayrollMonth, 1)
        FROM   [Payroll].[PayrollPeriods] p
        JOIN   [Payroll].[PayrollCalendars] pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        JOIN   [Core].[Companies] co ON co.CompanyId = pc.CompanyId
        WHERE  p.PayrollPeriodId = @PayrollPeriodId AND p.Deleted = 0;

        IF @nCo IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select a payroll period.';
            RETURN;
        END;

        SELECT @nSeq = ISNULL(MAX(RunSeq), 0) + 1 FROM [Payroll].[PayrollRuns]
        WHERE CompanyId = @nCo AND RunMonth = @nMonth AND Deleted = 0 AND RunSeq IS NOT NULL;

        SELECT  @nSeq AS NextSeq,
                CONCAT(@nCode, N'-', YEAR(@nMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@nMonth)), 2), N'-',
                       CASE WHEN @nSeq < 10 THEN CONCAT(N'0', @nSeq) ELSE CAST(@nSeq AS NVARCHAR(5)) END) AS RunCode,
                @nMonth AS RunMonth,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] WHERE CompanyId = @nCo AND RunMonth = @nMonth AND Deleted = 0 AND Stage <> 'DRAFT') AS IssuedCount,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] WHERE CompanyId = @nCo AND RunMonth = @nMonth AND Deleted = 0 AND Stage = 'CANCELLED') AS CancelledCount,
                (SELECT TOP 1 RunCode FROM [Payroll].[PayrollRuns]
                  WHERE PayrollPeriodId = @PayrollPeriodId AND RunType = 'REGULAR' AND Deleted = 0
                    AND Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')) AS RegularRunCode;
        RETURN;
    END;

    /* ======================= DRAFTS ============================== */
    IF @Action = 'DRAFTS'
    BEGIN
        SELECT  r.PayrollRunId, r.CompanyId, r.PayrollCalendarId, pc.CalendarName, r.PayrollPeriodId, p.PeriodName, p.StartDate, p.EndDate,
                pc.PayFrequency, p.PeriodNumber, r.RunType, r.Description, r.EmployeeCount, r.CreatedDate, ISNULL(r.ModifiedDate, r.CreatedDate) AS LastSaved
        FROM    [Payroll].[PayrollRuns] r
        JOIN    [Payroll].[PayrollCalendars] pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods] p ON p.PayrollPeriodId = r.PayrollPeriodId
        WHERE   r.Deleted = 0 AND r.Stage = 'DRAFT' AND (r.CreatedBy = @UserId OR @UserId IS NULL)
          AND   (@CompanyId  IS NULL OR r.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ORDER BY ISNULL(r.ModifiedDate, r.CreatedDate) DESC;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT  h.RunHistoryId, h.ActionCode, h.FromStage, h.ToStage, h.ApprovalLevel, h.Comment, h.ActionBy, h.ActionDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Payroll].[PayrollRunHistory] h
        LEFT JOIN [Security].[Users] u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] e ON e.EmployeeId = u.EmployeeId
        WHERE   h.PayrollRunId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate, h.RunHistoryId;
        RETURN;
    END;

    /* ======================= DRAFT_SAVE ========================== */
    IF @Action = 'DRAFT_SAVE'
    BEGIN
        DECLARE @dCo INT, @dCalActive BIT, @dPeriodStatus NVARCHAR(30), @dMonth DATE, @dCal INT;

        IF @RunType NOT IN ('REGULAR', 'OFFCYCLE')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the payroll type.';
            RETURN;
        END;

        SELECT @dCo = pc.CompanyId, @dCalActive = pc.IsActive, @dPeriodStatus = p.Status,
               @dMonth = DATEFROMPARTS(p.PayrollYear, p.PayrollMonth, 1), @dCal = pc.PayrollCalendarId
        FROM   [Payroll].[PayrollPeriods] p
        JOIN   [Payroll].[PayrollCalendars] pc ON pc.PayrollCalendarId = p.PayrollCalendarId AND pc.Deleted = 0
        WHERE  p.PayrollPeriodId = @PayrollPeriodId AND p.Deleted = 0 AND p.PayrollCalendarId = @PayrollCalendarId;

        IF @dCo IS NULL OR (@CompanyId IS NOT NULL AND @dCo <> @CompanyId)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the company, payroll calendar and period.';
            RETURN;
        END;
        IF @dCalActive = 0
        BEGIN
            SELECT @ResultCode = 'INACTIVE', @ResultMessage = N'This payroll calendar is inactive.';
            RETURN;
        END;
        IF @RunType = 'REGULAR' AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns]
                   WHERE PayrollPeriodId = @PayrollPeriodId AND RunType = 'REGULAR' AND Deleted = 0
                     AND Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED'))
        BEGIN
            SELECT @ResultCode = 'REGULAR_EXISTS',
                   @ResultMessage = N'A regular payroll already exists for this calendar and period. Choose Off-cycle for a second payroll, or cancel the existing one first.';
            RETURN;
        END;

        /* regular: OPEN / PROCESSING periods; off-cycle also after the regular payroll closed (APPROVED) */
        IF @dPeriodStatus NOT IN (N'OPEN', N'PROCESSING') AND NOT (@RunType = 'OFFCYCLE' AND @dPeriodStatus = N'APPROVED')
        BEGIN
            SELECT @ResultCode = 'PERIOD_CLOSED', @ResultMessage = N'This period is no longer open for payrolls.';
            RETURN;
        END;
        IF @Id IS NULL OR @Id = 0
        BEGIN
            INSERT INTO [Payroll].[PayrollRuns] (CompanyId, PayrollCalendarId, PayrollPeriodId, RunMonth, RunType, Description, Stage,
                                                 ScopeDepartmentId, ScopeWorkLocationId, ScopeEmploymentType, ScopeNationality, CreatedBy)
            VALUES (@dCo, @dCal, @PayrollPeriodId, @dMonth, @RunType, @Description, 'DRAFT',
                    @ScopeDepartmentId, @ScopeWorkLocationId, NULLIF(@ScopeEmploymentType, N''), NULLIF(@ScopeNationality, ''), @UserId);
            SET @NewId = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] WHERE PayrollRunId = @Id AND Deleted = 0 AND Stage = 'DRAFT')
            BEGIN
                SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That draft no longer exists. Start again.';
                RETURN;
            END;
            UPDATE [Payroll].[PayrollRuns]
               SET CompanyId = @dCo, PayrollCalendarId = @dCal, PayrollPeriodId = @PayrollPeriodId, RunMonth = @dMonth,
                   RunType = @RunType, Description = @Description,
                   ScopeDepartmentId = @ScopeDepartmentId, ScopeWorkLocationId = @ScopeWorkLocationId,
                   ScopeEmploymentType = NULLIF(@ScopeEmploymentType, N''), ScopeNationality = NULLIF(@ScopeNationality, ''),
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  PayrollRunId = @Id;
            SET @NewId = @Id;
        END;

        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @NewId, @EmployeeIds = NULL, @UserId = @UserId;
        SET @ResultMessage = N'Draft saved.';
        RETURN;
    END;

    /* everything below works on an existing run */
    DECLARE @rStage VARCHAR(20), @rType VARCHAR(10), @rCo INT, @rMonth DATE, @rPeriod INT, @rCal INT, @rLevel TINYINT,
            @rSubmittedBy BIGINT, @rErrors INT, @rDesc NVARCHAR(500), @rCode NVARCHAR(40), @rEmployees INT;
    SELECT  @rStage = Stage, @rType = RunType, @rCo = CompanyId, @rMonth = RunMonth, @rPeriod = PayrollPeriodId, @rCal = PayrollCalendarId,
            @rLevel = ApprovalLevel, @rSubmittedBy = SubmittedBy, @rErrors = ErrorCount, @rDesc = Description, @rCode = RunCode,
            @rEmployees = EmployeeCount
    FROM    [Payroll].[PayrollRuns] WHERE PayrollRunId = @Id AND Deleted = 0;

    IF @rStage IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That payroll no longer exists. Refresh and try again.';
        RETURN;
    END;

    /* ======================= DISCARD (drafts only) =============== */
    IF @Action = 'DISCARD'
    BEGIN
        IF @rStage <> 'DRAFT'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'Only a draft can be discarded. Cancel the payroll instead.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Payroll].[EmployeePayItems]    SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PayrollRunId = @Id AND Deleted = 0;
            UPDATE [Payroll].[PayrollRunLines]     SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PayrollRunId = @Id AND Deleted = 0;
            UPDATE [Payroll].[PayrollRunEmployees] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PayrollRunId = @Id AND Deleted = 0;
            UPDATE [Payroll].[PayrollRuns]         SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PayrollRunId = @Id;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Draft discarded.';
        RETURN;
    END;

    /* ======================= RECALC ============================== */
    IF @Action = 'RECALC'
    BEGIN
        IF @rStage NOT IN ('DRAFT', 'REGISTERED')
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'The payroll can only be recalculated while it is Registered.';
            RETURN;
        END;
        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @Id, @EmployeeIds = NULL, @UserId = @UserId;
        IF @rStage = 'REGISTERED'
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, ActionBy)
            VALUES (@Id, 'RECALCULATED', @rStage, @rStage, @UserId);
        SET @ResultMessage = N'Payroll recalculated.';
        RETURN;
    END;

    /* ======================= VALIDATE (re-run the checks) ======== */
    IF @Action = 'VALIDATE'
    BEGIN
        IF @rStage <> 'VALIDATION'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'The checks can only be re-run while the payroll is in Validation.';
            RETURN;
        END;
        EXEC [Payroll].[usp_PayrollRun_Validate] @RunId = @Id, @UserId = @UserId;
        SET @ResultMessage = N'Validation re-run.';
        RETURN;
    END;

    /* ======================= FINALIZE (draft -> Registered) ====== */
    IF @Action = 'FINALIZE'
    BEGIN
        IF @rStage <> 'DRAFT'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'This payroll has already been created.';
            RETURN;
        END;

        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @Id, @EmployeeIds = NULL, @UserId = @UserId;

        IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] WHERE PayrollRunId = @Id AND Deleted = 0 AND IsExcluded = 0
                       AND (@rType = 'REGULAR' OR LineCount > 0))
        BEGIN
            SELECT @ResultCode = 'NO_EMPLOYEES',
                   @ResultMessage = CASE WHEN @rType = 'OFFCYCLE'
                                         THEN N'An off-cycle payroll needs at least one line. Add an earning or deduction to an employee in step 2.'
                                         ELSE N'No employees match the scope of this payroll.' END;
            RETURN;
        END;

        BEGIN TRANSACTION;
            /* the run number: serialise per company and month */
            DECLARE @fSeq INT, @fCompanyCode NVARCHAR(30);
            SELECT @fCompanyCode = CompanyCode FROM [Core].[Companies] WHERE CompanyId = @rCo;
            SELECT @fSeq = ISNULL(MAX(RunSeq), 0) + 1
            FROM   [Payroll].[PayrollRuns] WITH (UPDLOCK, HOLDLOCK)
            WHERE  CompanyId = @rCo AND RunMonth = @rMonth AND Deleted = 0 AND RunSeq IS NOT NULL;

            IF @rType = 'REGULAR' AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] WITH (UPDLOCK, HOLDLOCK)
                       WHERE PayrollPeriodId = @rPeriod AND RunType = 'REGULAR' AND Deleted = 0
                         AND Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED'))
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'REGULAR_EXISTS',
                       @ResultMessage = N'A regular payroll already exists for this calendar and period. Choose Off-cycle for a second payroll, or cancel the existing one first.';
                RETURN;
            END;

            IF @rDesc IS NULL AND (@rType <> 'REGULAR' OR @fSeq > 1)
            BEGIN
                ROLLBACK TRANSACTION;
                SELECT @ResultCode = 'DESCRIPTION_REQUIRED',
                       @ResultMessage = N'Enter the reason for this payroll - it is not the first payroll for this company and month.';
                RETURN;
            END;

            DECLARE @fCode NVARCHAR(40) = CONCAT(@fCompanyCode, N'-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-',
                                                 CASE WHEN @fSeq < 10 THEN CONCAT(N'0', @fSeq) ELSE CAST(@fSeq AS NVARCHAR(5)) END);

            /* off-cycle: only employees with lines take part */
            IF @rType = 'OFFCYCLE'
                UPDATE [Payroll].[PayrollRunEmployees] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
                WHERE PayrollRunId = @Id AND Deleted = 0 AND IsExcluded = 0 AND LineCount = 0;

            UPDATE [Payroll].[PayrollRuns]
               SET RunSeq = @fSeq, RunCode = @fCode, Stage = 'REGISTERED', CreatedBy = ISNULL(CreatedBy, @UserId),
                   CreatedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  PayrollRunId = @Id;

            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy)
            VALUES (@Id, 'CREATED', NULL, 'REGISTERED', @rDesc, @UserId);

            /* a regular payroll moves its period into PROCESSING (db/29 status workflow) */
            IF @rType = 'REGULAR' AND EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] WHERE PayrollPeriodId = @rPeriod AND Status = N'OPEN')
            BEGIN
                UPDATE [Payroll].[PayrollPeriods] SET Status = N'PROCESSING', StatusChangedBy = @UserId, StatusChangedDate = @Now
                WHERE PayrollPeriodId = @rPeriod;
                INSERT INTO [Payroll].[PayrollPeriodStatusHistory] (PayrollPeriodId, FromStatus, ToStatus, Remarks, ChangedBy)
                VALUES (@rPeriod, 'OPEN', 'PROCESSING', CONCAT(N'Payroll ', @fCode, N' created'), @UserId);
            END;
        COMMIT TRANSACTION;

        SELECT @NewId = @Id, @ResultMessage = CONCAT(N'Payroll ', @fCode, N' created.');
        RETURN;
    END;

    /* ======================= SET_STAGE =========================== */
    IF @Action = 'SET_STAGE'
    BEGIN
        IF @rStage = 'REGISTERED' AND @Stage = 'VALIDATION'
        BEGIN
            IF @rEmployees = 0
            BEGIN
                SELECT @ResultCode = 'NO_EMPLOYEES', @ResultMessage = N'There are no employees in this payroll.';
                RETURN;
            END;
            EXEC [Payroll].[usp_PayrollRun_Validate] @RunId = @Id, @UserId = @UserId;
            UPDATE [Payroll].[PayrollRuns] SET Stage = 'VALIDATION', ModifiedBy = @UserId, ModifiedDate = @Now WHERE PayrollRunId = @Id;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy)
            VALUES (@Id, 'REGISTRATION_DONE', @rStage, 'VALIDATION', @Comment, @UserId);
            SET @ResultMessage = N'Registration completed. The payroll moved to Validation.';
            RETURN;
        END;

        IF @rStage = 'VALIDATION' AND @Stage = 'REGISTERED'
        BEGIN
            UPDATE [Payroll].[PayrollRuns] SET Stage = 'REGISTERED', ModifiedBy = @UserId, ModifiedDate = @Now WHERE PayrollRunId = @Id;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy)
            VALUES (@Id, 'BACK_TO_REGISTER', @rStage, 'REGISTERED', @Comment, @UserId);
            SET @ResultMessage = N'The payroll is back in the register.';
            RETURN;
        END;

        IF @rStage = 'VALIDATION' AND @Stage = 'AWAITING_APPROVAL'
        BEGIN
            EXEC [Payroll].[usp_PayrollRun_Validate] @RunId = @Id, @UserId = @UserId;
            IF (SELECT ErrorCount FROM [Payroll].[PayrollRuns] WHERE PayrollRunId = @Id) > 0
            BEGIN
                SELECT @ResultCode = 'HAS_ERRORS', @ResultMessage = N'Fix the validation errors before submitting this payroll for approval.';
                RETURN;
            END;
            UPDATE [Payroll].[PayrollRuns]
               SET Stage = 'AWAITING_APPROVAL', ApprovalLevel = 0, SubmittedBy = @UserId, SubmittedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE PayrollRunId = @Id;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy)
            VALUES (@Id, 'SUBMITTED', @rStage, 'AWAITING_APPROVAL', @Comment, @UserId);
            SET @ResultMessage = N'Submitted for approval.';
            RETURN;
        END;

        IF @rStage = 'AWAITING_APPROVAL' AND @Stage = 'VALIDATION'
        BEGIN
            IF @Comment IS NULL
            BEGIN
                SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter a comment explaining what needs to be corrected.';
                RETURN;
            END;
            UPDATE [Payroll].[PayrollRuns] SET Stage = 'VALIDATION', ApprovalLevel = 0, ModifiedBy = @UserId, ModifiedDate = @Now WHERE PayrollRunId = @Id;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, ApprovalLevel, Comment, ActionBy)
            VALUES (@Id, 'RETURNED', @rStage, 'VALIDATION', @rLevel + 1, @Comment, @UserId);
            SET @ResultMessage = N'Returned for correction. The payroll is back in Validation.';
            RETURN;
        END;

        SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'This step is not possible at the payroll''s current stage. Refresh the page.';
        RETURN;
    END;

    /* ======================= APPROVE ============================= */
    IF @Action = 'APPROVE'
    BEGIN
        IF @rStage <> 'AWAITING_APPROVAL'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'This payroll is not waiting for approval.';
            RETURN;
        END;

        DECLARE @aLevel TINYINT = @rLevel + 1;
        IF @AllowSelfApproval = 0 AND (
               @UserId = @rSubmittedBy
            OR (@aLevel = 2 AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRunHistory] WHERE PayrollRunId = @Id AND Deleted = 0
                                        AND ActionCode = 'APPROVED' AND ApprovalLevel = 1 AND ActionBy = @UserId
                                        AND ActionDate >= (SELECT SubmittedDate FROM [Payroll].[PayrollRuns] WHERE PayrollRunId = @Id))))
        BEGIN
            SELECT @ResultCode = 'SEGREGATION',
                   @ResultMessage = N'You cannot approve a payroll you submitted or already approved at the previous level.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, ApprovalLevel, Comment, ActionBy)
            VALUES (@Id, 'APPROVED', @rStage, CASE WHEN @aLevel >= 2 THEN 'CLOSED' ELSE @rStage END, @aLevel, @Comment, @UserId);

            IF @aLevel >= 2
            BEGIN
                UPDATE [Payroll].[PayrollRuns]
                   SET ApprovalLevel = 2, Stage = 'CLOSED', ClosedBy = @UserId, ClosedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE PayrollRunId = @Id;

                IF @rType = 'REGULAR' AND EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] WHERE PayrollPeriodId = @rPeriod AND Status = N'PROCESSING')
                BEGIN
                    UPDATE [Payroll].[PayrollPeriods] SET Status = N'APPROVED', StatusChangedBy = @UserId, StatusChangedDate = @Now
                    WHERE PayrollPeriodId = @rPeriod;
                    INSERT INTO [Payroll].[PayrollPeriodStatusHistory] (PayrollPeriodId, FromStatus, ToStatus, Remarks, ChangedBy)
                    VALUES (@rPeriod, 'PROCESSING', 'APPROVED', CONCAT(N'Payroll ', @rCode, N' closed'), @UserId);
                END;
                SET @ResultMessage = N'Approved. The payroll is closed.';
            END
            ELSE
            BEGIN
                UPDATE [Payroll].[PayrollRuns] SET ApprovalLevel = @aLevel, ModifiedBy = @UserId, ModifiedDate = @Now WHERE PayrollRunId = @Id;
                SET @ResultMessage = N'Approved. Waiting for the Finance Manager.';
            END;
        COMMIT TRANSACTION;

        SET @NewId = @aLevel;
        RETURN;
    END;

    /* ======================= CANCEL / REJECT ===================== */
    IF @Action = 'CANCEL'
    BEGIN
        IF @rStage NOT IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'Only a payroll that is not closed can be cancelled.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for cancelling this payroll.';
            RETURN;
        END;
        UPDATE [Payroll].[PayrollRuns]
           SET Stage = 'CANCELLED', CancelledBy = @UserId, CancelledDate = @Now, CancelReason = @Comment, ModifiedBy = @UserId, ModifiedDate = @Now
        WHERE PayrollRunId = @Id;
        INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, ApprovalLevel, Comment, ActionBy)
        VALUES (@Id, CASE WHEN @rStage = 'AWAITING_APPROVAL' THEN 'REJECTED' ELSE 'CANCELLED' END, @rStage, 'CANCELLED',
                CASE WHEN @rStage = 'AWAITING_APPROVAL' THEN @rLevel + 1 END, @Comment, @UserId);
        SET @ResultMessage = CONCAT(N'Payroll ', @rCode, N' cancelled. It keeps its number.');
        RETURN;
    END;

    /* ======================= REOPEN ============================== */
    IF @Action = 'REOPEN'
    BEGIN
        IF @rStage <> 'CLOSED'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'Only a closed payroll can be reopened.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for reopening this payroll.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Payroll].[PayrollRuns]
               SET Stage = 'VALIDATION', ApprovalLevel = 0, ClosedBy = NULL, ClosedDate = NULL, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE PayrollRunId = @Id;
            INSERT INTO [Payroll].[PayrollRunHistory] (PayrollRunId, ActionCode, FromStage, ToStage, Comment, ActionBy)
            VALUES (@Id, 'REOPENED', 'CLOSED', 'VALIDATION', @Comment, @UserId);
            IF @rType = 'REGULAR' AND EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] WHERE PayrollPeriodId = @rPeriod AND Status = N'APPROVED')
            BEGIN
                UPDATE [Payroll].[PayrollPeriods] SET Status = N'PROCESSING', StatusChangedBy = @UserId, StatusChangedDate = @Now WHERE PayrollPeriodId = @rPeriod;
                INSERT INTO [Payroll].[PayrollPeriodStatusHistory] (PayrollPeriodId, FromStatus, ToStatus, Remarks, ChangedBy)
                VALUES (@rPeriod, 'APPROVED', 'PROCESSING', CONCAT(N'Payroll ', @rCode, N' reopened'), @UserId);
            END;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Payroll reopened. It is back in Validation.';
        RETURN;
    END;
END;
GO

/* =====================================================================
   EMPLOYEES AND LINES OF A RUN
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRunEmployee_Manage]
    @Action          VARCHAR(20),
    @Id              BIGINT          = NULL,     -- PayrollRunId
    @OtherId         BIGINT          = NULL,     -- COMPARE: the second run
    @EmployeeId      BIGINT          = NULL,
    @EmployeeIds     NVARCHAR(MAX)   = NULL,     -- ADD_LINE: CSV of employees
    @LineId          BIGINT          = NULL,
    @PayComponentId  INT             = NULL,
    @Amount          DECIMAL(12,3)   = NULL,
    @Comment         NVARCHAR(500)   = NULL,
    @Filter          VARCHAR(20)     = NULL,     -- all / added / moves / missing / excluded / changed / issues
    @Search          NVARCHAR(200)   = NULL,
    @SortColumn      VARCHAR(30)     = NULL,     -- Name / Net / Change
    @PageNumber      INT             = 1,
    @PageSize        INT             = 25,
    @UserId          BIGINT          = NULL,

    @TotalCount      INT             = NULL OUTPUT,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Comment    = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action NOT IN ('LIST', 'LINES', 'SUMMARY', 'COMPONENTS', 'ADD_LINE', 'REMOVE_LINE', 'EXCLUDE', 'INCLUDE', 'COMPARE', 'EXCLUDED')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    DECLARE @Stage VARCHAR(20), @RunType VARCHAR(10), @CompanyId INT, @Start DATE, @End DATE, @RunMonth DATE;
    SELECT  @Stage = r.Stage, @RunType = r.RunType, @CompanyId = r.CompanyId, @Start = p.StartDate, @End = p.EndDate, @RunMonth = r.RunMonth
    FROM    [Payroll].[PayrollRuns] r JOIN [Payroll].[PayrollPeriods] p ON p.PayrollPeriodId = r.PayrollPeriodId
    WHERE   r.PayrollRunId = @Id AND r.Deleted = 0;

    IF @Stage IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That payroll no longer exists. Refresh and try again.';
        RETURN;
    END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        DECLARE @F TABLE (RunEmployeeId BIGINT PRIMARY KEY, SortName NVARCHAR(300), Net DECIMAL(12,3), Change DECIMAL(12,3));
        INSERT INTO @F
        SELECT re.RunEmployeeId, re.EmployeeName, re.NetPay, ABS(re.NetPay - ISNULL(re.PreviousNet, re.NetPay))
        FROM   [Payroll].[PayrollRunEmployees] re
        WHERE  re.PayrollRunId = @Id AND re.Deleted = 0
          AND  (@EmployeeId IS NULL OR re.EmployeeId = @EmployeeId)
          AND  (@Pattern IS NULL OR re.EmployeeName LIKE @Pattern ESCAPE '\' OR re.EmployeeNo LIKE @Pattern ESCAPE '\' OR re.ArabicName LIKE @Pattern ESCAPE '\')
          AND  (   ISNULL(@Filter, 'all') = 'all'
                OR (@Filter = 'included' AND re.IsExcluded = 0 AND (@RunType = 'REGULAR' OR re.LineCount > 0))
                OR (@Filter = 'added'    AND re.AddedLineCount > 0)
                OR (@Filter = 'moves'    AND ((re.HireDate BETWEEN @Start AND @End) OR (re.TerminationDate BETWEEN @Start AND @End)))
                OR (@Filter = 'missing'  AND re.IsExcluded = 0 AND re.HasSalary = 0 AND @RunType = 'REGULAR')
                OR (@Filter = 'excluded' AND re.IsExcluded = 1)
                OR (@Filter = 'changed'  AND re.PreviousNet IS NOT NULL AND re.NetPay <> re.PreviousNet)
                OR (@Filter = 'issues'   AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRunIssues] i WHERE i.PayrollRunId = @Id AND i.EmployeeId = re.EmployeeId AND i.Deleted = 0)));

        SET @TotalCount = (SELECT COUNT(1) FROM @F);

        SELECT  re.RunEmployeeId, re.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName, re.DepartmentName, re.CostCenterId,
                re.IsKuwaiti, re.EmploymentStatus, re.HireDate, re.TerminationDate, re.PeriodDays, re.PaidDays, re.HasBankAccount,
                re.IsExcluded, re.ExcludeReason, re.SalaryTotal, re.EarningsTotal, re.DeductionsTotal,
                re.SalaryTotal + re.EarningsTotal AS GrossPay, re.NetPay, re.PreviousNet, re.LineCount, re.AddedLineCount, re.HasSalary,
                CAST(CASE WHEN re.HireDate BETWEEN @Start AND @End THEN 1 ELSE 0 END AS BIT) AS IsJoiner,
                CAST(CASE WHEN re.TerminationDate BETWEEN @Start AND @End THEN 1 ELSE 0 END AS BIT) AS IsLeaver,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunIssues] i WHERE i.PayrollRunId = @Id AND i.EmployeeId = re.EmployeeId AND i.Deleted = 0 AND i.Severity = 'ERROR') AS ErrorCount
        FROM    @F f
        JOIN    [Payroll].[PayrollRunEmployees] re ON re.RunEmployeeId = f.RunEmployeeId
        ORDER BY CASE WHEN @SortColumn = 'Change' THEN f.Change END DESC,
                 CASE WHEN @SortColumn = 'Net' THEN f.Net END DESC,
                 f.SortName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= EXCLUDED ============================ */
    IF @Action = 'EXCLUDED'
    BEGIN
        SELECT  re.RunEmployeeId, re.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName, re.ExcludeReason, re.ExcludedDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS ExcludedByName
        FROM    [Payroll].[PayrollRunEmployees] re
        LEFT JOIN [Security].[Users] u ON u.UserId = re.ExcludedBy
        LEFT JOIN [Employee].[Employees] ue ON ue.EmployeeId = u.EmployeeId
        WHERE   re.PayrollRunId = @Id AND re.Deleted = 0 AND re.IsExcluded = 1
        ORDER BY re.EmployeeName;
        RETURN;
    END;

    /* ======================= LINES =============================== */
    IF @Action = 'LINES'
    BEGIN
        SELECT  l.RunLineId, l.EmployeeId, l.PayComponentId, l.ItemClass, l.ComponentName, l.ComponentArabicName, l.Comment, l.Source,
                l.EmployeePayItemId, l.InstalmentNo, i.InstalmentCount, l.FullAmount, l.Amount
        FROM    [Payroll].[PayrollRunLines] l
        LEFT JOIN [Payroll].[EmployeePayItems] i ON i.EmployeePayItemId = l.EmployeePayItemId
        WHERE   l.PayrollRunId = @Id AND l.Deleted = 0 AND (@EmployeeId IS NULL OR l.EmployeeId = @EmployeeId)
        ORDER BY l.EmployeeId,
                 CASE l.ItemClass WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'STATUTORY' THEN 3 WHEN 'LOAN' THEN 4 ELSE 5 END,
                 l.DisplayOrder, l.RunLineId;
        RETURN;
    END;

    /* ======================= SUMMARY ============================= */
    IF @Action = 'SUMMARY'
    BEGIN
        SELECT  COUNT(CASE WHEN re.IsExcluded = 0 AND (@RunType = 'REGULAR' OR re.LineCount > 0) THEN 1 END)                        AS EmployeeCount,
                COUNT(CASE WHEN re.IsExcluded = 0 AND re.PaidDays >= re.PeriodDays THEN 1 END)                                     AS FullPeriodCount,
                COUNT(CASE WHEN re.IsExcluded = 0 AND re.HireDate BETWEEN @Start AND @End THEN 1 END)                             AS JoinerCount,
                COUNT(CASE WHEN re.IsExcluded = 0 AND re.TerminationDate BETWEEN @Start AND @End THEN 1 END)                      AS LeaverCount,
                COUNT(CASE WHEN re.IsExcluded = 1 THEN 1 END)                                                                      AS ExcludedCount,
                COUNT(CASE WHEN re.IsExcluded = 0 AND re.HasSalary = 0 AND @RunType = 'REGULAR' THEN 1 END)                       AS MissingSalaryCount,
                COUNT(CASE WHEN re.IsExcluded = 0 AND re.HasBankAccount = 0 THEN 1 END)                                            AS NoBankCount,
                ISNULL(SUM(re.SalaryTotal), 0) AS TotalSalary, ISNULL(SUM(re.EarningsTotal), 0) AS TotalEarnings,
                ISNULL(SUM(re.DeductionsTotal), 0) AS TotalDeductions, ISNULL(SUM(re.NetPay), 0) AS TotalNet,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'RUN')                  AS AddedLineCount,
                (SELECT ISNULL(SUM(CASE WHEN l.Amount > 0 THEN l.Amount END), 0) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'RUN') AS AddedPlus,
                (SELECT ISNULL(-SUM(CASE WHEN l.Amount < 0 THEN l.Amount END), 0) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'RUN') AS AddedMinus,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'PAY_ITEM')             AS PayItemCount,
                (SELECT ISNULL(SUM(l.Amount), 0) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'PAY_ITEM') AS PayItemAmount,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'LOAN')                 AS LoanCount,
                (SELECT ISNULL(-SUM(l.Amount), 0) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'LOAN') AS LoanAmount,
                (SELECT COUNT(1) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'STATUTORY')            AS PifssCount,
                (SELECT ISNULL(-SUM(l.Amount), 0) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'STATUTORY') AS PifssAmount,
                (SELECT COUNT(DISTINCT l.EmployeeId) FROM [Payroll].[PayrollRunLines] l WHERE l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'PROFILE') AS ProfileSalaryCount,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates] r WHERE r.Deleted = 0 AND r.IsActive = 1 AND r.IsVerified = 0
                                       AND r.EffectiveFrom <= @End AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @End)) THEN 1 ELSE 0 END AS BIT) AS PifssUnverified,
                (SELECT STRING_AGG(CAST(CONCAT(x.EmployeeName, N' · ', x.EmployeeNo) AS NVARCHAR(MAX)), N', ')
                   FROM (SELECT TOP 5 m.EmployeeName, m.EmployeeNo FROM [Payroll].[PayrollRunEmployees] m
                         WHERE m.PayrollRunId = @Id AND m.Deleted = 0 AND m.IsExcluded = 0 AND m.HasSalary = 0 AND @RunType = 'REGULAR'
                         ORDER BY m.EmployeeName) AS x) AS MissingSalaryNames
        FROM    [Payroll].[PayrollRunEmployees] re
        WHERE   re.PayrollRunId = @Id AND re.Deleted = 0;
        RETURN;
    END;

    /* ======================= COMPONENTS (for "Add line") ========= */
    IF @Action = 'COMPONENTS'
    BEGIN
        SELECT  c.PayComponentId, c.ComponentCode, c.ComponentName, c.ArabicName, c.ItemClass, c.DisplayOrder
        FROM    [Payroll].[PayComponents] c
        WHERE   c.CompanyId = @CompanyId AND c.Deleted = 0 AND c.IsActive = 1 AND c.ItemClass IN ('EARNING', 'DEDUCTION')
        ORDER BY CASE c.ItemClass WHEN 'EARNING' THEN 1 ELSE 2 END, c.DisplayOrder, c.ComponentName;
        RETURN;
    END;

    /* ======================= COMPARE (two runs) ================== */
    IF @Action = 'COMPARE'
    BEGIN
        SELECT  ISNULL(a.EmployeeId, b.EmployeeId) AS EmployeeId,
                ISNULL(a.EmployeeNo, b.EmployeeNo) AS EmployeeNo,
                ISNULL(a.EmployeeName, b.EmployeeName) AS EmployeeName,
                ISNULL(a.ArabicName, b.ArabicName) AS ArabicName,
                a.NetPay AS NetA, b.NetPay AS NetB, ISNULL(b.NetPay, 0) - ISNULL(a.NetPay, 0) AS Difference
        FROM    (SELECT * FROM [Payroll].[PayrollRunEmployees] WHERE PayrollRunId = @Id AND Deleted = 0 AND IsExcluded = 0) a
        FULL JOIN (SELECT * FROM [Payroll].[PayrollRunEmployees] WHERE PayrollRunId = @OtherId AND Deleted = 0 AND IsExcluded = 0) b
                ON b.EmployeeId = a.EmployeeId
        ORDER BY ABS(ISNULL(b.NetPay, 0) - ISNULL(a.NetPay, 0)) DESC, ISNULL(a.EmployeeName, b.EmployeeName);
        RETURN;
    END;

    /* ======================= writes ============================== */
    IF @Stage NOT IN ('DRAFT', 'REGISTERED')
    BEGIN
        SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'Lines and employees can only be changed while the payroll is Registered.';
        RETURN;
    END;

    IF @Action = 'ADD_LINE'
    BEGIN
        DECLARE @Class VARCHAR(10);
        SELECT @Class = ItemClass FROM [Payroll].[PayComponents]
        WHERE PayComponentId = @PayComponentId AND CompanyId = @CompanyId AND Deleted = 0 AND IsActive = 1;

        IF @Class NOT IN ('EARNING', 'DEDUCTION') OR @Class IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose an earning or deduction type.';
            RETURN;
        END;
        IF @Amount IS NULL OR @Amount <= 0 OR @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter an amount and a comment.';
            RETURN;
        END;

        DECLARE @Targets TABLE (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO @Targets
        SELECT DISTINCT re.EmployeeId
        FROM   [Payroll].[PayrollRunEmployees] re
        WHERE  re.PayrollRunId = @Id AND re.Deleted = 0 AND re.IsExcluded = 0
          AND  re.EmployeeId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@EmployeeIds, CAST(@EmployeeId AS NVARCHAR(30))), ','));

        IF NOT EXISTS (SELECT 1 FROM @Targets)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select at least one employee who is in this payroll.';
            RETURN;
        END;

        INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, PayrollRunId, CreatedBy)
        SELECT @CompanyId, t.EmployeeId, @PayComponentId, @Amount, 'ONCE', @RunMonth, @Comment, 'ACTIVE', @Id, @UserId
        FROM   @Targets t;

        DECLARE @Csv NVARCHAR(MAX) = (SELECT STRING_AGG(CAST(EmployeeId AS NVARCHAR(30)), ',') FROM @Targets);
        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @Id, @EmployeeIds = @Csv, @UserId = @UserId;

        SELECT @TotalCount = COUNT(1) FROM @Targets;
        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'Line added.' ELSE CONCAT(N'Line added to ', @TotalCount, N' employees.') END;
        RETURN;
    END;

    IF @Action = 'REMOVE_LINE'
    BEGIN
        DECLARE @ItemId BIGINT, @LineEmp BIGINT;
        SELECT @ItemId = l.EmployeePayItemId, @LineEmp = l.EmployeeId
        FROM   [Payroll].[PayrollRunLines] l
        WHERE  l.RunLineId = @LineId AND l.PayrollRunId = @Id AND l.Deleted = 0 AND l.Source = 'RUN';

        IF @ItemId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Only lines added in this payroll can be removed here.';
            RETURN;
        END;

        UPDATE [Payroll].[EmployeePayItems] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        WHERE EmployeePayItemId = @ItemId AND PayrollRunId = @Id;

        DECLARE @One NVARCHAR(30) = CAST(@LineEmp AS NVARCHAR(30));
        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @Id, @EmployeeIds = @One, @UserId = @UserId;
        SET @ResultMessage = N'Line removed.';
        RETURN;
    END;

    IF @Action IN ('EXCLUDE', 'INCLUDE')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] WHERE PayrollRunId = @Id AND EmployeeId = @EmployeeId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That employee is not in this payroll.';
            RETURN;
        END;
        IF @Action = 'EXCLUDE' AND @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for excluding this employee.';
            RETURN;
        END;

        UPDATE [Payroll].[PayrollRunEmployees]
           SET IsExcluded = CASE WHEN @Action = 'EXCLUDE' THEN 1 ELSE 0 END,
               ExcludeReason = CASE WHEN @Action = 'EXCLUDE' THEN @Comment END,
               ExcludedBy = CASE WHEN @Action = 'EXCLUDE' THEN @UserId END,
               ExcludedDate = CASE WHEN @Action = 'EXCLUDE' THEN @Now END
        WHERE PayrollRunId = @Id AND EmployeeId = @EmployeeId AND Deleted = 0;

        DECLARE @Emp NVARCHAR(30) = CAST(@EmployeeId AS NVARCHAR(30));
        EXEC [Payroll].[usp_PayrollRun_Calculate] @RunId = @Id, @EmployeeIds = @Emp, @UserId = @UserId;
        /* the run totals count excluded employees */
        SET @ResultMessage = CASE WHEN @Action = 'EXCLUDE' THEN N'Employee excluded from this payroll.' ELSE N'Employee included again.' END;
        RETURN;
    END;
END;
GO

/* =====================================================================
   VALIDATION RESULTS
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRunIssue_Manage]
    @Action          VARCHAR(20),
    @Id              BIGINT          = NULL,     -- PayrollRunId
    @IssueId         BIGINT          = NULL,
    @Severity        VARCHAR(10)     = NULL,
    @StatusFilter    VARCHAR(10)     = NULL,     -- OPEN / ACK
    @RuleCode        VARCHAR(10)     = NULL,
    @Search          NVARCHAR(200)   = NULL,
    @Comment         NVARCHAR(500)   = NULL,
    @PageNumber      INT             = 1,
    @PageSize        INT             = 50,
    @UserId          BIGINT          = NULL,

    @TotalCount      INT             = NULL OUTPUT,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Search  = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 50 WHEN @PageSize > 1000 THEN 1000 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        DECLARE @I TABLE (RunIssueId BIGINT PRIMARY KEY);
        INSERT INTO @I
        SELECT i.RunIssueId
        FROM   [Payroll].[PayrollRunIssues] i
        LEFT JOIN [Payroll].[PayrollRunEmployees] re ON re.PayrollRunId = i.PayrollRunId AND re.EmployeeId = i.EmployeeId AND re.Deleted = 0
        WHERE  i.PayrollRunId = @Id AND i.Deleted = 0
          AND  (@Severity IS NULL OR i.Severity = @Severity)
          AND  (@RuleCode IS NULL OR i.RuleCode = @RuleCode)
          AND  (@StatusFilter IS NULL OR (@StatusFilter = 'OPEN' AND i.IsAcknowledged = 0) OR (@StatusFilter = 'ACK' AND i.IsAcknowledged = 1))
          AND  (@Pattern IS NULL OR i.Message LIKE @Pattern ESCAPE '\' OR re.EmployeeName LIKE @Pattern ESCAPE '\' OR re.EmployeeNo LIKE @Pattern ESCAPE '\');

        SET @TotalCount = (SELECT COUNT(1) FROM @I);

        SELECT  i.RunIssueId, i.EmployeeId, i.RuleCode, i.Severity, i.Message, i.IsAcknowledged, i.AcknowledgedDate, i.AcknowledgeReason,
                re.EmployeeNo, re.EmployeeName, re.ArabicName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS AcknowledgedByName
        FROM    @I x
        JOIN    [Payroll].[PayrollRunIssues] i ON i.RunIssueId = x.RunIssueId
        LEFT JOIN [Payroll].[PayrollRunEmployees] re ON re.PayrollRunId = i.PayrollRunId AND re.EmployeeId = i.EmployeeId AND re.Deleted = 0
        LEFT JOIN [Security].[Users] u ON u.UserId = i.AcknowledgedBy
        LEFT JOIN [Employee].[Employees] ue ON ue.EmployeeId = u.EmployeeId
        ORDER BY CASE i.Severity WHEN 'ERROR' THEN 0 ELSE 1 END, i.IsAcknowledged, i.RuleCode, re.EmployeeName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'ACK'
    BEGIN
        DECLARE @Stage VARCHAR(20), @Sev VARCHAR(10);
        SELECT @Stage = r.Stage, @Sev = i.Severity
        FROM   [Payroll].[PayrollRunIssues] i JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = i.PayrollRunId
        WHERE  i.RunIssueId = @IssueId AND i.PayrollRunId = @Id AND i.Deleted = 0 AND r.Deleted = 0;

        IF @Stage IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That issue no longer exists. Revalidate and try again.';
            RETURN;
        END;
        IF @Stage <> 'VALIDATION'
        BEGIN
            SELECT @ResultCode = 'INVALID_STAGE', @ResultMessage = N'Warnings can only be acknowledged while the payroll is in Validation.';
            RETURN;
        END;
        IF @Sev <> 'WARNING'
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Errors cannot be acknowledged - they must be fixed.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for acknowledging this warning.';
            RETURN;
        END;

        UPDATE [Payroll].[PayrollRunIssues]
           SET IsAcknowledged = 1, AcknowledgedBy = @UserId, AcknowledgedDate = SYSUTCDATETIME(), AcknowledgeReason = @Comment
        WHERE RunIssueId = @IssueId;
        SET @ResultMessage = N'Warning acknowledged.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

PRINT N'db/35 applied: payroll engine, validation and run procedures.';
GO
