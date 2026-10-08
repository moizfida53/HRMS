/* =====================================================================
   53_Payroll_Dashboard.sql  -  HRMS: the Payroll Dashboard
   ---------------------------------------------------------------------
   Run after 34-52. Idempotent (CREATE OR ALTER). Then run db/54 (labels).

   Payroll.usp_PayrollDashboard  @Action, for the user's company scope
   (@CompanyId / @CompanyIds) and one payroll month (@RunMonth):

     MONTHS     the months that have payrolls (the period picker), newest first
     SUMMARY    the month's figures: the main payroll (regular run) and its
                stage, employees paid (and the month before), joiners and
                leavers, net pay (and the month before), gross, employer PIFSS
     TREND      net pay of the 12 months up to @RunMonth
     DEPT       gross cost per department in @RunMonth
     CALENDAR   the payroll periods of the month before, this one and the next
     ATTENTION  what needs doing: validation errors and unacknowledged
                warnings of live payrolls, pay items and loans waiting for
                approval, work permits expiring this month, statutory rows not
                verified, closed payrolls without a bank file / journal,
                journals not posted, payments failed

   Figures count the payrolls past Draft and not Cancelled (Registered ...
   Closed) - a live payroll shows its current calculation.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[usp_PayrollFinance_NavCounts]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 49 and 50 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollDashboard]
    @Action        VARCHAR(20),
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL,
    @RunMonth      DATE            = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_WARNINGS OFF;   -- NULLs eliminated in the aggregates are expected

    DECLARE @M DATE = DATEFROMPARTS(YEAR(ISNULL(@RunMonth, SYSUTCDATETIME())), MONTH(ISNULL(@RunMonth, SYSUTCDATETIME())), 1);
    DECLARE @Prev DATE = DATEADD(MONTH, -1, @M);

    /* the payrolls in scope that count (past Draft, not Cancelled) */
    DECLARE @Runs TABLE (PayrollRunId BIGINT PRIMARY KEY, CompanyId INT, RunMonth DATE, RunType VARCHAR(10), Stage VARCHAR(20));
    INSERT INTO @Runs
    SELECT r.PayrollRunId, r.CompanyId, r.RunMonth, r.RunType, r.Stage
    FROM   [Payroll].[PayrollRuns] AS r
    WHERE  r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED')
      AND  [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
      AND (@Action IN ('MONTHS', 'TREND') OR r.RunMonth IN (@M, @Prev));

    /* ======================= MONTHS ============================== */
    IF @Action = 'MONTHS'
    BEGIN
        SELECT DISTINCT RunMonth FROM @Runs ORDER BY RunMonth DESC;
        RETURN;
    END;

    /* ======================= SUMMARY ============================= */
    IF @Action = 'SUMMARY'
    BEGIN
        DECLARE @MainRun BIGINT =
            (SELECT TOP (1) PayrollRunId FROM @Runs WHERE RunMonth = @M
             ORDER BY CASE WHEN RunType = 'REGULAR' THEN 0 ELSE 1 END, PayrollRunId DESC);

        ;WITH emp AS (
            SELECT r.RunMonth, re.RunEmployeeId, re.EmployeeId, re.HireDate, re.TerminationDate, re.IsKuwaiti,
                   re.SalaryTotal, re.EarningsTotal, re.NetPay
            FROM   @Runs AS r
            JOIN   [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0 AND re.IsExcluded = 0
        ), pifss AS (
            /* employer share: the rates in force at the month end on the PIFSS-applicable salary items, capped */
            SELECT ISNULL(SUM(v.Share), 0) AS EmployerPifss
            FROM   emp AS e
            CROSS APPLY (SELECT ISNULL(SUM(l.Amount), 0) AS Base
                         FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                         WHERE l.RunEmployeeId = e.RunEmployeeId AND l.Deleted = 0 AND l.ItemClass = 'SALARY' AND c.IsPifssApplicable = 1) AS b
            JOIN   [Payroll].[PifssContributionRates] AS pr
                   ON pr.Deleted = 0 AND pr.IsActive = 1 AND pr.ApplicableTo = 'KUWAITI'
                  AND pr.EffectiveFrom <= EOMONTH(@M) AND (pr.EffectiveTo IS NULL OR pr.EffectiveTo >= EOMONTH(@M))
            CROSS APPLY (SELECT ROUND(CASE WHEN pr.SalaryCeiling IS NOT NULL AND b.Base > pr.SalaryCeiling THEN pr.SalaryCeiling ELSE b.Base END
                                      * pr.EmployerRate / 100.0, 3) AS Share) AS v
            WHERE  e.RunMonth = @M AND e.IsKuwaiti = 1
        )
        SELECT  @M AS RunMonth,
                m.PayrollRunId AS MainRunId, m.RunCode AS MainRunCode, m.Stage AS MainStage, m.RunType AS MainRunType,
                pc.CalendarName, pp.CutOffDate, pp.PaymentDate,
                (SELECT COUNT(1) FROM @Runs WHERE RunMonth = @M) AS RunCount,
                (SELECT COUNT(DISTINCT EmployeeId) FROM emp WHERE RunMonth = @M) AS EmployeeCount,
                (SELECT COUNT(DISTINCT EmployeeId) FROM emp WHERE RunMonth = @Prev) AS PrevEmployeeCount,
                (SELECT COUNT(DISTINCT EmployeeId) FROM emp WHERE RunMonth = @M AND HireDate BETWEEN @M AND EOMONTH(@M)) AS Joiners,
                (SELECT COUNT(DISTINCT EmployeeId) FROM emp WHERE RunMonth = @M AND TerminationDate BETWEEN @M AND EOMONTH(@M)) AS Leavers,
                (SELECT ISNULL(SUM(NetPay), 0) FROM emp WHERE RunMonth = @M) AS NetPay,
                (SELECT ISNULL(SUM(NetPay), 0) FROM emp WHERE RunMonth = @Prev) AS PrevNetPay,
                (SELECT ISNULL(SUM(SalaryTotal + EarningsTotal), 0) FROM emp WHERE RunMonth = @M) AS Gross,
                (SELECT EmployerPifss FROM pifss) AS EmployerPifss
        FROM    (SELECT 1 AS one) AS x
        LEFT JOIN [Payroll].[PayrollRuns]      AS m  ON m.PayrollRunId = @MainRun
        LEFT JOIN [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = m.PayrollCalendarId
        LEFT JOIN [Payroll].[PayrollPeriods]   AS pp ON pp.PayrollPeriodId = m.PayrollPeriodId;
        RETURN;
    END;

    /* ======================= TREND =============================== */
    IF @Action = 'TREND'
    BEGIN
        ;WITH months AS (
            SELECT DATEADD(MONTH, -n, @M) AS RunMonth
            FROM (VALUES (0),(1),(2),(3),(4),(5),(6),(7),(8),(9),(10),(11)) AS x(n)
        )
        SELECT  mo.RunMonth,
                ISNULL(SUM(re.NetPay), 0) AS NetPay,
                ISNULL(SUM(re.SalaryTotal + re.EarningsTotal), 0) AS Gross,
                COUNT(DISTINCT re.EmployeeId) AS Employees
        FROM    months AS mo
        LEFT JOIN @Runs AS r ON r.RunMonth = mo.RunMonth
        LEFT JOIN [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0 AND re.IsExcluded = 0
        GROUP BY mo.RunMonth
        ORDER BY mo.RunMonth;
        RETURN;
    END;

    /* ======================= DEPT ================================ */
    IF @Action = 'DEPT'
    BEGIN
        SELECT  ISNULL(re.DepartmentName, N'—') AS DepartmentName,
                COUNT(DISTINCT re.EmployeeId) AS Employees,
                SUM(re.SalaryTotal + re.EarningsTotal) AS Gross,
                SUM(re.NetPay) AS NetPay
        FROM    @Runs AS r
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0 AND re.IsExcluded = 0
        WHERE   r.RunMonth = @M
        GROUP BY re.DepartmentName
        ORDER BY Gross DESC;
        RETURN;
    END;

    /* ======================= CALENDAR ============================ */
    IF @Action = 'CALENDAR'
    BEGIN
        SELECT  pp.PayrollPeriodId, pp.CompanyId, co.CompanyName, pc.CalendarName,
                DATEFROMPARTS(pp.PayrollYear, pp.PayrollMonth, 1) AS PeriodMonth,
                pp.StartDate, pp.EndDate, pp.PaymentDate, pp.Status,
                lr.RunCode, lr.Stage AS RunStage
        FROM    [Payroll].[PayrollPeriods] AS pp
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = pp.PayrollCalendarId AND pc.Deleted = 0
        JOIN    [Core].[Companies] AS co ON co.CompanyId = pp.CompanyId
        OUTER APPLY (SELECT TOP (1) r.RunCode, r.Stage FROM [Payroll].[PayrollRuns] r
                     WHERE r.PayrollPeriodId = pp.PayrollPeriodId AND r.Deleted = 0 AND r.Stage <> 'CANCELLED'
                     ORDER BY CASE WHEN r.RunType = 'REGULAR' THEN 0 ELSE 1 END, r.PayrollRunId DESC) AS lr
        WHERE   pp.Deleted = 0
          AND   [Payroll].[ufn_InCompanyScope](pp.CompanyId, @CompanyId, @CompanyIds) = 1
          AND   DATEFROMPARTS(pp.PayrollYear, pp.PayrollMonth, 1) BETWEEN @Prev AND DATEADD(MONTH, 1, @M)
        ORDER BY DATEFROMPARTS(pp.PayrollYear, pp.PayrollMonth, 1) DESC, co.CompanyName, pc.CalendarName;
        RETURN;
    END;

    /* ======================= ATTENTION =========================== */
    IF @Action = 'ATTENTION'
    BEGIN
        DECLARE @Since DATE = DATEADD(MONTH, -12, @M);
        SELECT
            (SELECT COUNT(1) FROM [Payroll].[PayrollRunIssues] AS i JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = i.PayrollRunId
             WHERE i.Deleted = 0 AND i.Severity = 'ERROR' AND r.Deleted = 0 AND r.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')
               AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS ValidationErrors,
            (SELECT COUNT(1) FROM [Payroll].[PayrollRunIssues] AS i JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = i.PayrollRunId
             WHERE i.Deleted = 0 AND i.Severity = 'WARNING' AND i.IsAcknowledged = 0 AND r.Deleted = 0
               AND r.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')
               AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS OpenWarnings,
            (SELECT COUNT(1) FROM [Payroll].[EmployeePayItems] AS i JOIN [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
             WHERE i.Deleted = 0 AND i.Status = 'PENDING' AND c.ItemClass <> 'LOAN'
               AND [Payroll].[ufn_InCompanyScope](i.CompanyId, @CompanyId, @CompanyIds) = 1) AS PayItemsPending,
            (SELECT COUNT(1) FROM [Payroll].[EmployeePayItems] AS i JOIN [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
             WHERE i.Deleted = 0 AND i.Status = 'PENDING' AND c.ItemClass = 'LOAN'
               AND [Payroll].[ufn_InCompanyScope](i.CompanyId, @CompanyId, @CompanyIds) = 1) AS LoansPending,
            (SELECT COUNT(1) FROM [Kuwait].[EmployeeCompliance] AS k JOIN [Employee].[Employees] AS e ON e.EmployeeId = k.EmployeeId
             WHERE e.IsDeleted = 0 AND k.WorkPermitExpiryDate BETWEEN CAST(SYSUTCDATETIME() AS DATE) AND EOMONTH(SYSUTCDATETIME())
               AND [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1) AS PermitsExpiring,
            (SELECT COUNT(1) FROM [Payroll].[PifssContributionRates] WHERE Deleted = 0 AND IsActive = 1 AND IsVerified = 0)
          + (SELECT COUNT(1) FROM [Payroll].[IndemnityRuleSets]       WHERE Deleted = 0 AND IsActive = 1 AND IsVerified = 0)
          + (SELECT COUNT(1) FROM [Payroll].[OvertimeRates]           WHERE Deleted = 0 AND IsActive = 1 AND IsVerified = 0) AS UnverifiedRules,
            (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] AS r
             WHERE r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth >= @Since AND r.TotalNet > 0
               AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
               AND NOT EXISTS (SELECT 1 FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = r.PayrollRunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED')) AS BankFilesToMake,
            (SELECT COUNT(1) FROM [Payroll].[BankPayments] AS p JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = p.PayrollRunId
             WHERE p.Deleted = 0 AND p.Status = 'FAILED'
               AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS PaymentsFailed,
            (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] AS r
             WHERE r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth >= @Since
               AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
               AND NOT EXISTS (SELECT 1 FROM [Payroll].[JournalBatches] j WHERE j.PayrollRunId = r.PayrollRunId AND j.Deleted = 0 AND j.Status <> 'REVERSED')) AS JournalsToMake,
            (SELECT COUNT(1) FROM [Payroll].[JournalBatches] AS j
             WHERE j.Deleted = 0 AND j.Status IN ('READY', 'EXPORTED')
               AND [Payroll].[ufn_InCompanyScope](j.CompanyId, @CompanyId, @CompanyIds) = 1) AS JournalsToPost;
        RETURN;
    END;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/53 applied: Payroll.usp_PayrollDashboard. Run db/54 (labels) next.';
GO
