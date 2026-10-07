/* =====================================================================
   40_FinalSettlement_StoredProcedures.sql  -  HRMS Payroll: Final Settlement
   ---------------------------------------------------------------------
   Run after 39. CREATE OR ALTER everywhere - safe to re-run.
   Then re-run 35 (the payroll engine leaves out an employee whose
   settlement pays the last salary) and run 41 (labels).

     Payroll.ufn_FinalSettlement_Salary    the monthly salary of an employee
                                           in a month, per salary item type
                                           (same rule as the payroll engine:
                                           approved salary items, or the
                                           employee profile when there are none)
     Payroll.usp_FinalSettlement_Calculate the calculation (internal)
     Payroll.usp_FinalSettlement_Manage    LIST / GET / LINES / HISTORY /
                                           SUMMARY / EMPLOYEES / DEFAULTS /
                                           SAVE / RECALC / ADD_LINE /
                                           REMOVE_LINE / TOGGLE_LINE / SUBMIT /
                                           APPROVE / RETURN / REJECT / PAY /
                                           CANCEL

   How a settlement is calculated
     Pending salary   every salary item from "Salary unpaid from" to the last
                      working day, month by month: amount x days / days in
                      the month (calendar days; an item type that is not
                      prorated is paid in full). Default "unpaid from" = the
                      day after the last closed regular payroll that paid the
                      employee.
     Pay items        one-time earnings / deductions of those months that no
                      payroll has paid, and monthly ones prorated like salary.
     Leave            days to encash x leave salary / daily divisor. Leave
                      salary = the salary item types marked "Leave salary"
                      (the whole salary when none is marked).
     Indemnity        Payroll.IndemnityRuleSets in force on the last working
                      day: each service slab (days or months of indemnity
                      salary per year), capped at MaxIndemnityMonths, times
                      the % for the separation type and the years of service.
                      Indemnity salary = the item types marked "Indemnity"
                      (the whole salary when none is marked).
                      Service years = (last day - hire date + 1) / 365.
     Recoveries       loan / advance balances, unpaid instalment deductions,
                      PIFSS employee share on the pending salary (Kuwaitis),
                      salary a closed payroll paid after the last working day.
     Lines added by hand (earnings / recoveries) are kept on recalculation,
     and so is the choice to waive an automatic pay item or loan line.

   Approval  HR (PAYROLL_RUN_APPROVE_HR), then Finance (_FINANCE); the
             person who submitted cannot approve, the HR approver cannot
             give the Finance approval - except SYSADMIN.
   On final approval of an exit settlement the employee becomes Resigned /
   Terminated with the last working day as termination date, the recovered
   loans and paid pay items end, and monthly items stop after that month.
   A leave encashment without exit becomes a one-time Leave Encashment
   earning in the month chosen, paid by that month's payroll.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 39 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* =====================================================================
   ufn_FinalSettlement_Salary
   ===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_FinalSettlement_Salary] (@EmployeeId BIGINT, @Month DATE)
RETURNS TABLE
AS
RETURN
    WITH s AS (
        SELECT  i.EmployeePayItemId, i.PayComponentId, i.Amount,
                ROW_NUMBER() OVER (PARTITION BY i.PayComponentId ORDER BY i.StartMonth DESC, i.EmployeePayItemId DESC) AS rn
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        WHERE   i.EmployeeId = @EmployeeId AND i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
          AND   c.ItemClass = 'SALARY' AND i.AppliesMode = 'MONTHLY'
          AND   i.StartMonth <= @Month AND (i.EndMonth IS NULL OR i.EndMonth >= @Month)
    )
    SELECT  s.EmployeePayItemId, c.PayComponentId, c.ComponentName, c.ArabicName, s.Amount,
            c.IsIndemnityApplicable, c.IsLeaveSalaryApplicable, c.IsPifssApplicable, c.IsProrated, c.DisplayOrder,
            CAST(0 AS BIT) AS FromProfile
    FROM    s
    JOIN    [Payroll].[PayComponents] AS c ON c.PayComponentId = s.PayComponentId
    WHERE   s.rn = 1
    UNION ALL
    /* no salary items at all yet -> basic + allowances from the employee profile (as the engine does) */
    SELECT  NULL, c.PayComponentId, c.ComponentName, c.ArabicName, v.Amount,
            c.IsIndemnityApplicable, c.IsLeaveSalaryApplicable, c.IsPifssApplicable, c.IsProrated, c.DisplayOrder,
            CAST(1 AS BIT)
    FROM    [Employee].[Employees]       AS e
    JOIN    [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId
    CROSS APPLY (VALUES ('BASIC', ep.BasicSalary), ('OTHER_ALW', ep.Allowances)) AS v(Code, Amount)
    JOIN    [Payroll].[PayComponents]    AS c ON c.CompanyId = e.CompanyId AND c.ComponentCode = v.Code AND c.Deleted = 0
    WHERE   e.EmployeeId = @EmployeeId AND v.Amount > 0
      AND   NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] AS i
                        JOIN [Payroll].[PayComponents] AS ic ON ic.PayComponentId = i.PayComponentId
                        WHERE i.EmployeeId = @EmployeeId AND i.Deleted = 0 AND ic.ItemClass = 'SALARY' AND i.PayrollRunId IS NULL);
GO

/* =====================================================================
   usp_FinalSettlement_Calculate  (internal - inside the caller's transaction)
   ===================================================================== */
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

/* =====================================================================
   usp_FinalSettlement_Manage
   ===================================================================== */
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
                CASE WHEN e.HireDate IS NULL OR e.HireDate > @dLwd THEN 0 ELSE DATEDIFF(DAY, e.HireDate, @dLwd) + 1 END AS ServiceDays,
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
        SELECT  s.*, co.CompanyName, co.ArabicName AS CompanyArabicName, co.CompanyCode,
                e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.EmploymentStatus, e.NoticePeriodDays, d.DepartmentName, d.ArabicName AS DepartmentArabicName,
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

SET NOEXEC OFF;
GO
PRINT N'db/40 applied: final settlement calculation and workflow procedures. Re-run db/35 and run db/41 next.';
GO
