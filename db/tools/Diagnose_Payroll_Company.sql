/* =====================================================================
   tools/Diagnose_Payroll_Company.sql  -  HRMS: why a company's employees
   are not in Create Payroll
   ---------------------------------------------------------------------
   READ-ONLY - changes nothing. Set the company and month below, run it,
   and read the four result sets:
     1. the company found (by name, legal name or code)
     2. its payroll calendars: frequency, active, default, the period of
        the month and its status, and the payrolls already made
     3. every employee with the reason the payroll engine would or would
        not pay them for the month (same rules as db/35 + db/80)
     4. a count per reason
   ===================================================================== */
SET NOCOUNT ON;

DECLARE @CompanyName NVARCHAR(200) = N'RanD';                  -- name, legal name or code
DECLARE @Month       DATE          = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1);   -- first day of the payroll month

/* ---- 1. the company --------------------------------------------------- */
DECLARE @Co TABLE (CompanyId INT PRIMARY KEY);
INSERT INTO @Co
SELECT c.CompanyId FROM [Core].[Companies] AS c
WHERE  c.Deleted = 0
  AND (c.CompanyName LIKE N'%' + @CompanyName + N'%' OR c.LegalName LIKE N'%' + @CompanyName + N'%' OR c.CompanyCode = @CompanyName);

SELECT N'1. Company' AS [Check], c.CompanyId, c.CompanyCode, c.CompanyName, c.LegalName, c.IsActive,
       (SELECT COUNT(1) FROM [Employee].[Employees] e WHERE e.CompanyId = c.CompanyId AND e.Deleted = 0) AS EmployeesOnRecord
FROM   [Core].[Companies] AS c JOIN @Co AS x ON x.CompanyId = c.CompanyId;

IF NOT EXISTS (SELECT 1 FROM @Co)
BEGIN
    PRINT N'No company matches "' + @CompanyName + N'". Check the name / code.';
    RETURN;
END;
IF (SELECT COUNT(1) FROM @Co) > 1
    PRINT N'NOTE: more than one company matches - the lists below cover all of them.';

/* ---- 2. payroll calendars -------------------------------------------- */
SELECT N'2. Calendar' AS [Check], pc.CompanyId, pc.PayrollCalendarId, pc.CalendarCode, pc.CalendarName, pc.PayFrequency,
       pc.IsActive, pc.IsDefault, pc.FirstPeriodStartDate,
       p.PayrollPeriodId, p.PeriodName, p.StartDate, p.EndDate, p.Status AS PeriodStatus,
       (SELECT STRING_AGG(CONCAT(r.RunCode, N' ', r.RunType, N' ', r.Stage), N', ')
        FROM [Payroll].[PayrollRuns] r WHERE r.PayrollPeriodId = p.PayrollPeriodId AND r.Deleted = 0) AS PayrollsOfPeriod,
       CASE WHEN pc.IsActive = 0 THEN N'Inactive - pays nobody'
            WHEN p.PayrollPeriodId IS NULL THEN N'No period in the month - Create Payroll generates it on Next'
            WHEN p.Status NOT IN (N'OPEN', N'PROCESSING') THEN N'Period ' + p.Status + N' - no new regular payroll'
            ELSE N'OK' END AS Note
FROM   [Payroll].[PayrollCalendars] AS pc
JOIN   @Co AS x ON x.CompanyId = pc.CompanyId
LEFT JOIN [Payroll].[PayrollPeriods] AS p
       ON p.PayrollCalendarId = pc.PayrollCalendarId AND p.Deleted = 0
      AND p.PayrollYear = YEAR(@Month) AND p.PayrollMonth = MONTH(@Month)
WHERE  pc.Deleted = 0
ORDER BY pc.CompanyId, pc.IsDefault DESC, pc.CalendarName, p.StartDate;

IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] pc JOIN @Co x ON x.CompanyId = pc.CompanyId WHERE pc.Deleted = 0 AND pc.IsActive = 1)
    PRINT N'The company has NO active payroll calendar. Create Payroll makes "Monthly Payroll" on Next (db/80 + this version of the app).';

/* ---- 3. every employee and the reason -------------------------------- */
DECLARE @Start DATE = @Month, @End DATE = EOMONTH(@Month);

;WITH emp AS (
    SELECT e.EmployeeId, e.CompanyId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
           LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName,
           e.Deleted, e.IsDeleted, e.EmploymentStatus, e.HireDate, e.TerminationDate, e.PayrollCalendarId,
           pc.CompanyId AS CalendarCompanyId, pc.CalendarName, pc.PayFrequency, pc.IsActive AS CalendarActive, pc.Deleted AS CalendarDeleted,
           d.PayrollCalendarId AS DefaultCalendarId, d.PayFrequency AS DefaultFrequency
    FROM   [Employee].[Employees] AS e
    JOIN   @Co AS x ON x.CompanyId = e.CompanyId
    LEFT JOIN [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = e.PayrollCalendarId
    OUTER APPLY (SELECT TOP (1) dc.PayrollCalendarId, dc.PayFrequency FROM [Payroll].[PayrollCalendars] dc
                 WHERE dc.CompanyId = e.CompanyId AND dc.IsDefault = 1 AND dc.IsActive = 1 AND dc.Deleted = 0) AS d
)
SELECT N'3. Employee' AS [Check], EmployeeId, EmployeeNo, EmployeeName, EmploymentStatus, HireDate, TerminationDate,
       Deleted, IsDeleted AS Inactive, PayrollCalendarId, CalendarName, PayFrequency,
       CASE
         WHEN Deleted = 1 THEN N'Removed (Deleted = 1)'
         WHEN IsDeleted = 1 THEN N'Inactive employee (Employee.IsDeleted = 1) - activate the employee'
         WHEN EmploymentStatus IN (N'Terminated', N'Resigned') AND TerminationDate IS NULL
              THEN N'Status ' + EmploymentStatus + N' with no termination date'
         WHEN TerminationDate < @Start THEN N'Terminated before the month'
         WHEN HireDate > @End THEN N'Hired after the month'
         WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] oe JOIN [Payroll].[PayrollRuns] o ON o.PayrollRunId = oe.PayrollRunId
                      WHERE oe.EmployeeId = emp.EmployeeId AND oe.Deleted = 0 AND o.Deleted = 0 AND o.RunType = 'REGULAR'
                        AND o.RunMonth = @Month AND o.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED'))
              THEN N'Already in a created regular payroll of the month'
         WHEN OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NOT NULL
              AND EXISTS (SELECT 1 FROM [Payroll].[FinalSettlements] fs WHERE fs.EmployeeId = emp.EmployeeId AND fs.Deleted = 0
                            AND fs.SettlementType <> 'ENCASHMENT' AND fs.Status <> 'CANCELLED' AND fs.SalaryFrom <= @End)
              THEN N'Has a final settlement - it pays the month'
         WHEN PayrollCalendarId IS NOT NULL AND CalendarCompanyId = CompanyId AND CalendarActive = 1 AND CalendarDeleted = 0
              THEN CASE WHEN PayFrequency = 'MONTHLY' THEN N'OK - paid by its monthly calendar'
                        ELSE N'OK - paid by its ' + LOWER(PayFrequency) + N' calendar (Create Payroll > Weekly / bi-weekly)' END
         WHEN DefaultCalendarId IS NULL
              THEN N'OK - no (usable) calendar: paid by the "Monthly Payroll" calendar Create Payroll makes'
         ELSE CASE WHEN PayrollCalendarId IS NOT NULL AND CalendarCompanyId <> CompanyId THEN N'Calendar of ANOTHER company - paid by the default calendar (db/80)'
                   WHEN PayrollCalendarId IS NOT NULL THEN N'Calendar inactive / removed - paid by the default calendar (db/80)'
                   ELSE N'OK - no calendar: paid by the default calendar' END
              + CASE WHEN DefaultFrequency <> 'MONTHLY' THEN N' (the default is ' + LOWER(DefaultFrequency) + N')' ELSE N'' END
       END AS Reason
INTO   #Diag
FROM   emp;

SELECT * FROM #Diag ORDER BY CASE WHEN Reason LIKE N'OK%' THEN 1 ELSE 0 END, EmployeeNo;

/* ---- 4. count per reason --------------------------------------------- */
SELECT N'4. Summary' AS [Check], Reason, COUNT(1) AS Employees
FROM   #Diag GROUP BY Reason ORDER BY COUNT(1) DESC;

DROP TABLE #Diag;
