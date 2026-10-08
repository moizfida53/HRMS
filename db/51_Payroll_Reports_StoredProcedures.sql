/* =====================================================================
   51_Payroll_Reports_StoredProcedures.sql  -  HRMS Payroll Reports
   ---------------------------------------------------------------------
   Run AFTER 50. Idempotent (CREATE OR ALTER).

   Payroll.usp_PayrollReport  @Report = one of the codes below, for the
   CLOSED payrolls of @RunMonth (or of @Year when no month is given), in
   the user's company scope, optionally one department (@DepartmentId).
   Figures are always the payroll's own (PayrollRunEmployees / Lines).

     Payroll      PAY_REGISTER   every employee: salary, earnings, deductions, net
                  PAY_DEPT       totals per department
                  PAY_VARIANCE   net against the month before, per employee
                  PAY_COST       employer cost per department (gross + employer PIFSS)
     Salary       SAL_GRADE      salary range per grade
                  SAL_REVISIONS  pay item amount changes in the period
                  SAL_TREND      12 months of headcount and cost up to the period
     Deduction    DED_COMPONENT  deductions per pay item type
                  DED_EMPLOYEE   deductions per employee
                  DED_LOANS      instalment loans and advances outstanding
     Overtime     OT_EMPLOYEE    overtime paid per employee
                  OT_DEPT        overtime paid per department
     Compliance   CMP_PIFSS      PIFSS contribution (Kuwaiti staff): employee and employer share
                  CMP_WPS        salary (WPS) files generated in the period
                  CMP_AUDIT      payroll actions in the period (who, when, what)

   Employer PIFSS uses the rates in force at the month end on the
   PIFSS-applicable salary items, capped at the ceiling - the same rule
   the payroll uses for the employee share.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[ufn_RunPayees]', N'IF') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 50 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollReport]
    @Report        VARCHAR(20),
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL,
    @Year          INT             = NULL,
    @RunMonth      DATE            = NULL,
    @DepartmentId  INT             = NULL,
    @TotalCount    INT             = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET ANSI_WARNINGS OFF;   -- NULLs eliminated in the aggregates are expected
    SET @TotalCount = 0;

    DECLARE @From DATE = COALESCE(@RunMonth, DATEFROMPARTS(ISNULL(@Year, YEAR(SYSUTCDATETIME())), 1, 1));
    DECLARE @To   DATE = COALESCE(@RunMonth, DATEFROMPARTS(ISNULL(@Year, YEAR(SYSUTCDATETIME())), 12, 1));

    /* the payrolls of the period */
    DECLARE @Runs TABLE (PayrollRunId BIGINT PRIMARY KEY, CompanyId INT, RunMonth DATE, RunCode NVARCHAR(40));
    IF @Report <> 'SAL_TREND'
        INSERT INTO @Runs
        SELECT r.PayrollRunId, r.CompanyId, r.RunMonth, r.RunCode
        FROM   [Payroll].[PayrollRuns] AS r
        WHERE  r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth BETWEEN @From AND @To
          AND  [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;

    /* the employees of those payrolls (department filter) */
    DECLARE @Emp TABLE (RunEmployeeId BIGINT PRIMARY KEY, PayrollRunId BIGINT, EmployeeId BIGINT, EmployeeNo NVARCHAR(20), EmployeeName NVARCHAR(300),
                        DepartmentName NVARCHAR(150), IsKuwaiti BIT, Salary DECIMAL(14,3), Earnings DECIMAL(14,3), Deductions DECIMAL(14,3), Net DECIMAL(14,3));
    INSERT INTO @Emp
    SELECT re.RunEmployeeId, re.PayrollRunId, re.EmployeeId, re.EmployeeNo, re.EmployeeName, ISNULL(re.DepartmentName, N'—'), re.IsKuwaiti,
           re.SalaryTotal, re.EarningsTotal, ABS(re.DeductionsTotal), re.NetPay
    FROM   [Payroll].[PayrollRunEmployees] AS re
    JOIN   @Runs AS r ON r.PayrollRunId = re.PayrollRunId
    WHERE  re.Deleted = 0 AND re.IsExcluded = 0 AND (@DepartmentId IS NULL OR re.DepartmentId = @DepartmentId);

    /* employer PIFSS per run employee (Kuwaiti staff) */
    DECLARE @Pifss TABLE (RunEmployeeId BIGINT PRIMARY KEY, Base DECIMAL(14,3), EmployeeShare DECIMAL(14,3), EmployerShare DECIMAL(14,3));
    IF @Report IN ('PAY_COST', 'CMP_PIFSS')
        INSERT INTO @Pifss
        SELECT e.RunEmployeeId, b.Base,
               ISNULL((SELECT -SUM(l.Amount) FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                       WHERE l.RunEmployeeId = e.RunEmployeeId AND l.Deleted = 0 AND c.SystemCode = 'PIFSS_EE'), 0),
               ISNULL((SELECT SUM(v.Share)
                       FROM [Payroll].[PifssContributionRates] AS pr
                       CROSS APPLY (SELECT ROUND(CASE WHEN pr.SalaryCeiling IS NOT NULL AND b.Base > pr.SalaryCeiling THEN pr.SalaryCeiling ELSE b.Base END
                                                 * pr.EmployerRate / 100.0, 3) AS Share) AS v
                       WHERE pr.Deleted = 0 AND pr.IsActive = 1 AND pr.ApplicableTo = 'KUWAITI'
                         AND pr.EffectiveFrom <= EOMONTH(r.RunMonth) AND (pr.EffectiveTo IS NULL OR pr.EffectiveTo >= EOMONTH(r.RunMonth))), 0)
        FROM   @Emp AS e
        JOIN   @Runs AS r ON r.PayrollRunId = e.PayrollRunId
        CROSS APPLY (SELECT ISNULL(SUM(l.Amount), 0) AS Base
                     FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                     WHERE l.RunEmployeeId = e.RunEmployeeId AND l.Deleted = 0 AND l.ItemClass = 'SALARY' AND c.IsPifssApplicable = 1) AS b
        WHERE  e.IsKuwaiti = 1;

    /* ======================= Payroll ============================ */
    IF @Report = 'PAY_REGISTER'
    BEGIN
        SELECT e.EmployeeNo, e.EmployeeName, e.DepartmentName, r.RunCode, e.Salary, e.Earnings, e.Deductions, e.Net
        FROM   @Emp AS e JOIN @Runs AS r ON r.PayrollRunId = e.PayrollRunId
        ORDER BY e.DepartmentName, e.EmployeeNo, r.RunMonth;
    END
    ELSE IF @Report = 'PAY_DEPT'
    BEGIN
        SELECT e.DepartmentName, COUNT(DISTINCT e.EmployeeId) AS Employees, SUM(e.Salary + e.Earnings) AS Gross,
               SUM(e.Deductions) AS Deductions, SUM(e.Net) AS Net
        FROM   @Emp AS e GROUP BY e.DepartmentName ORDER BY SUM(e.Net) DESC;
    END
    ELSE IF @Report = 'PAY_VARIANCE'
    BEGIN
        /* this period against the month before it (the same scope) */
        DECLARE @Prev DATE = DATEADD(MONTH, -1, @From);
        ;WITH cur AS (SELECT EmployeeId, MAX(EmployeeNo) AS EmployeeNo, MAX(EmployeeName) AS EmployeeName, MAX(DepartmentName) AS DepartmentName, SUM(Net) AS Net
                      FROM @Emp GROUP BY EmployeeId),
              prv AS (SELECT re.EmployeeId, MAX(re.EmployeeNo) AS EmployeeNo, MAX(re.EmployeeName) AS EmployeeName, MAX(ISNULL(re.DepartmentName, N'—')) AS DepartmentName,
                             SUM(re.NetPay) AS Net
                      FROM [Payroll].[PayrollRunEmployees] AS re
                      JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = re.PayrollRunId
                      WHERE re.Deleted = 0 AND re.IsExcluded = 0 AND r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth = @Prev
                        AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
                        AND (@DepartmentId IS NULL OR re.DepartmentId = @DepartmentId)
                      GROUP BY re.EmployeeId)
        SELECT COALESCE(c.EmployeeNo, p.EmployeeNo) AS EmployeeNo, COALESCE(c.EmployeeName, p.EmployeeName) AS EmployeeName,
               COALESCE(c.DepartmentName, p.DepartmentName) AS DepartmentName,
               ISNULL(p.Net, 0) AS PreviousNet, ISNULL(c.Net, 0) AS CurrentNet, ISNULL(c.Net, 0) - ISNULL(p.Net, 0) AS Difference,
               CAST(CASE WHEN ISNULL(p.Net, 0) = 0 THEN NULL ELSE ROUND((ISNULL(c.Net, 0) - p.Net) * 100.0 / p.Net, 2) END AS DECIMAL(9,2)) AS ChangePercent,
               CASE WHEN p.EmployeeId IS NULL THEN 'NEW' WHEN c.EmployeeId IS NULL THEN 'LEFT' ELSE 'CHANGED' END AS ChangeType
        FROM   cur AS c FULL JOIN prv AS p ON p.EmployeeId = c.EmployeeId
        WHERE  ISNULL(c.Net, 0) <> ISNULL(p.Net, 0)
        ORDER BY ABS(ISNULL(c.Net, 0) - ISNULL(p.Net, 0)) DESC;
    END
    ELSE IF @Report = 'PAY_COST'
    BEGIN
        SELECT e.DepartmentName, COUNT(DISTINCT e.EmployeeId) AS Employees, SUM(e.Salary + e.Earnings) AS Gross,
               ISNULL(SUM(p.EmployerShare), 0) AS EmployerPifss, SUM(e.Salary + e.Earnings) + ISNULL(SUM(p.EmployerShare), 0) AS TotalCost
        FROM   @Emp AS e LEFT JOIN @Pifss AS p ON p.RunEmployeeId = e.RunEmployeeId
        GROUP BY e.DepartmentName ORDER BY TotalCost DESC;
    END

    /* ======================= Salary ============================= */
    ELSE IF @Report = 'SAL_GRADE'
    BEGIN
        SELECT ISNULL(g.GradeName, N'—') AS GradeName, COUNT(DISTINCT e.EmployeeId) AS Employees,
               MIN(e.Salary) AS MinSalary, CAST(AVG(e.Salary) AS DECIMAL(14,3)) AS AvgSalary, MAX(e.Salary) AS MaxSalary
        FROM   @Emp AS e
        JOIN   [Employee].[Employees] AS emp ON emp.EmployeeId = e.EmployeeId
        LEFT JOIN [Core].[Grades] AS g ON g.GradeId = emp.GradeId
        GROUP BY g.GradeName ORDER BY MIN(e.Salary);
    END
    ELSE IF @Report = 'SAL_REVISIONS'
    BEGIN
        SELECT CAST(h.ActionDate AS DATE) AS ChangeDate, emp.EmployeeNo, LTRIM(RTRIM(CONCAT(emp.FirstName, N' ', emp.LastName))) AS EmployeeName,
               c.ComponentName, h.OldAmount, h.NewAmount, ISNULL(h.NewAmount, 0) - ISNULL(h.OldAmount, 0) AS Difference, h.Comment,
               COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS ChangedBy
        FROM   [Payroll].[EmployeePayItemHistory] AS h
        JOIN   [Payroll].[EmployeePayItems] AS i ON i.EmployeePayItemId = h.EmployeePayItemId
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
        JOIN   [Employee].[Employees] AS emp ON emp.EmployeeId = h.EmployeeId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE  h.Deleted = 0 AND h.ActionCode IN ('CHANGED', 'REVISED') AND ISNULL(h.OldAmount, -1) <> ISNULL(h.NewAmount, -1)
          AND  h.ActionDate >= @From AND h.ActionDate < DATEADD(MONTH, 1, @To)
          AND  [Payroll].[ufn_InCompanyScope](i.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@DepartmentId IS NULL OR emp.DepartmentId = @DepartmentId)
        ORDER BY h.ActionDate DESC;
    END
    ELSE IF @Report = 'SAL_TREND'
    BEGIN
        DECLARE @End DATE = @To;
        SELECT r.RunMonth, COUNT(DISTINCT re.EmployeeId) AS Employees, SUM(re.SalaryTotal + re.EarningsTotal) AS Gross,
               SUM(ABS(re.DeductionsTotal)) AS Deductions, SUM(re.NetPay) AS Net
        FROM   [Payroll].[PayrollRuns] AS r
        JOIN   [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0 AND re.IsExcluded = 0
        WHERE  r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth > DATEADD(MONTH, -12, @End) AND r.RunMonth <= @End
          AND  [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@DepartmentId IS NULL OR re.DepartmentId = @DepartmentId)
        GROUP BY r.RunMonth ORDER BY r.RunMonth;
    END

    /* ======================= Deduction ========================== */
    ELSE IF @Report = 'DED_COMPONENT'
    BEGIN
        SELECT c.ComponentName, c.ComponentCode, COUNT(DISTINCT l.EmployeeId) AS Employees, -SUM(l.Amount) AS Amount
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   @Emp AS e ON e.RunEmployeeId = l.RunEmployeeId
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = l.PayComponentId
        WHERE  l.Deleted = 0 AND l.Amount < 0
        GROUP BY c.ComponentName, c.ComponentCode ORDER BY -SUM(l.Amount) DESC;
    END
    ELSE IF @Report = 'DED_EMPLOYEE'
    BEGIN
        SELECT e.EmployeeNo, e.EmployeeName, e.DepartmentName,
               -SUM(CASE WHEN c.SystemCode = 'PIFSS_EE' THEN l.Amount ELSE 0 END) AS Pifss,
               -SUM(CASE WHEN l.ItemClass = 'LOAN' THEN l.Amount ELSE 0 END) AS Loans,
               -SUM(CASE WHEN c.SystemCode NOT IN ('PIFSS_EE') OR c.SystemCode IS NULL THEN CASE WHEN l.ItemClass <> 'LOAN' THEN l.Amount ELSE 0 END ELSE 0 END) AS Other,
               -SUM(l.Amount) AS Total
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   @Emp AS e ON e.RunEmployeeId = l.RunEmployeeId
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = l.PayComponentId
        WHERE  l.Deleted = 0 AND l.Amount < 0
        GROUP BY e.EmployeeId, e.EmployeeNo, e.EmployeeName, e.DepartmentName ORDER BY Total DESC;
    END
    ELSE IF @Report = 'DED_LOANS'
    BEGIN
        /* instalment items (loans, advances) still running, with what the closed payrolls recovered */
        SELECT emp.EmployeeNo, LTRIM(RTRIM(CONCAT(emp.FirstName, N' ', emp.LastName))) AS EmployeeName, c.ComponentName,
               i.TotalAmount, i.Amount AS Instalment, ISNULL(rec.Recovered, 0) AS Recovered,
               ISNULL(i.TotalAmount, 0) - ISNULL(rec.Recovered, 0) AS Balance,
               i.InstalmentCount - ISNULL(rec.Paid, 0) AS InstalmentsLeft, i.StartMonth
        FROM   [Payroll].[EmployeePayItems] AS i
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = i.PayComponentId
        JOIN   [Employee].[Employees] AS emp ON emp.EmployeeId = i.EmployeeId
        OUTER APPLY (SELECT -SUM(l.Amount) AS Recovered, COUNT(1) AS Paid
                     FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
                     WHERE l.EmployeePayItemId = i.EmployeePayItemId AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage = 'CLOSED'
                       AND r.RunMonth <= @To) AS rec
        WHERE  i.Deleted = 0 AND i.AppliesMode = 'INSTALMENT' AND c.ComponentType = 'DEDUCTION' AND i.Status IN ('ACTIVE', 'PENDING')
          AND  i.StartMonth <= @To
          AND  [Payroll].[ufn_InCompanyScope](i.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@DepartmentId IS NULL OR emp.DepartmentId = @DepartmentId)
          AND  ISNULL(i.TotalAmount, 0) - ISNULL(rec.Recovered, 0) > 0
        ORDER BY Balance DESC;
    END

    /* ======================= Overtime =========================== */
    ELSE IF @Report IN ('OT_EMPLOYEE', 'OT_DEPT')
    BEGIN
        DECLARE @Ot TABLE (EmployeeId BIGINT, EmployeeNo NVARCHAR(20), EmployeeName NVARCHAR(300), DepartmentName NVARCHAR(150), Lines INT, Amount DECIMAL(14,3), Basic DECIMAL(14,3));
        INSERT INTO @Ot
        SELECT e.EmployeeId, MAX(e.EmployeeNo), MAX(e.EmployeeName), MAX(e.DepartmentName), COUNT(1), SUM(l.Amount), MAX(e.Salary)
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   @Emp AS e ON e.RunEmployeeId = l.RunEmployeeId
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = l.PayComponentId
        WHERE  l.Deleted = 0 AND l.Amount > 0 AND (c.SystemCode = 'OVERTIME' OR c.ComponentCode LIKE N'OT[_]%' OR c.ComponentCode = N'OVERTIME')
        GROUP BY e.EmployeeId;

        IF @Report = 'OT_EMPLOYEE'
            SELECT EmployeeNo, EmployeeName, DepartmentName, Lines, Amount,
                   CAST(CASE WHEN Basic > 0 THEN ROUND(Amount * 100.0 / Basic, 2) END AS DECIMAL(9,2)) AS PercentOfSalary
            FROM @Ot ORDER BY Amount DESC;
        ELSE
            SELECT DepartmentName, COUNT(1) AS Employees, SUM(Lines) AS Lines, SUM(Amount) AS Amount
            FROM @Ot GROUP BY DepartmentName ORDER BY SUM(Amount) DESC;
    END

    /* ======================= Compliance ========================= */
    ELSE IF @Report = 'CMP_PIFSS'
    BEGIN
        SELECT e.EmployeeNo, e.EmployeeName,
               CASE WHEN LEN(ci.CivilIdNumber) > 4 THEN REPLICATE(N'•', LEN(ci.CivilIdNumber) - 4) + RIGHT(ci.CivilIdNumber, 4) ELSE ci.CivilIdNumber END AS CivilId,
               p.Base AS ContributorySalary, p.EmployeeShare, p.EmployerShare, p.EmployeeShare + p.EmployerShare AS Total
        FROM   @Pifss AS p
        JOIN   @Emp AS e ON e.RunEmployeeId = p.RunEmployeeId
        LEFT JOIN [Kuwait].[EmployeeCompliance] AS ci ON ci.EmployeeId = e.EmployeeId
        ORDER BY e.EmployeeNo;
    END
    ELSE IF @Report = 'CMP_WPS'
    BEGIN
        SELECT f.FileNo, r.RunCode, ISNULL(b.BankName, N'—') AS BankName, f.FileKind, f.LineCount, f.TotalAmount, f.ValueDate, f.Status,
               (SELECT COUNT(1) FROM [Payroll].[BankPayments] p WHERE p.BankFileId = f.BankFileId AND p.Deleted = 0 AND p.Status = 'PAID') AS PaidCount,
               (SELECT COUNT(1) FROM [Payroll].[BankPayments] p WHERE p.BankFileId = f.BankFileId AND p.Deleted = 0 AND p.Status = 'FAILED') AS FailedCount
        FROM   [Payroll].[BankFiles] AS f
        JOIN   @Runs AS r ON r.PayrollRunId = f.PayrollRunId
        LEFT JOIN [Payroll].[Banks] AS b ON b.BankId = f.BankId
        WHERE  f.Deleted = 0
        ORDER BY f.CreatedDate DESC;
    END
    ELSE IF @Report = 'CMP_AUDIT'
    BEGIN
        SELECT h.ActionDate, r.RunCode, h.ActionCode, h.FromStage, h.ToStage, h.Comment,
               COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS ActionBy
        FROM   [Payroll].[PayrollRunHistory] AS h
        JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = h.PayrollRunId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE  h.Deleted = 0 AND r.Deleted = 0 AND r.RunMonth BETWEEN @From AND @To
          AND  [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
        ORDER BY h.ActionDate DESC;
    END;

    SET @TotalCount = @@ROWCOUNT;
END;
GO

/* the periods that have closed payrolls (the report filters) */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollReport_Periods]
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SELECT DISTINCT r.RunMonth
    FROM   [Payroll].[PayrollRuns] AS r
    WHERE  r.Deleted = 0 AND r.Stage = 'CLOSED' AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
    ORDER BY r.RunMonth DESC;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/51 applied: Payroll.usp_PayrollReport and usp_PayrollReport_Periods. Run db/52 (labels) next.';
GO
