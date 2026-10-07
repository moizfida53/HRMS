/* ================================================================
   HRMS Kuwait - Dashboard: "Employees by company" bar chart
   ----------------------------------------------------------------
   Re-creates Employee.usp_Dashboard_Get (db/24 version, unchanged)
   with one new action:

     COMPANY   every company with its headcount on the selected month
               (today for the current month). Not narrowed by the
               top-bar @CompanyIds filter - the page lists all companies
               and highlights the selected ones.

   Run AFTER 24.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_Dashboard_Get]
    @Action        VARCHAR(10),
    @CompanyId     INT   = NULL,   -- NULL = all companies
    @CompanyIds    NVARCHAR(2000) = NULL,   -- db/24: comma-separated ids, NULL = all
    @MonthStart    DATE  = NULL    -- first day of the selected month; NULL = this month
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Today       DATE = CAST(SYSDATETIME() AS DATE);
    SET @MonthStart = DATEFROMPARTS(YEAR(ISNULL(@MonthStart, @Today)), MONTH(ISNULL(@MonthStart, @Today)), 1);

    DECLARE @MonthEnd    DATE = EOMONTH(@MonthStart);
    DECLARE @AsOf        DATE = CASE WHEN @MonthEnd > @Today THEN @Today ELSE @MonthEnd END;
    DECLARE @PrevStart   DATE = DATEADD(MONTH, -1, @MonthStart);
    DECLARE @PrevEnd     DATE = EOMONTH(@PrevStart);
    DECLARE @Horizon     DATE = DATEADD(DAY, 30, @Today);

    /* ======================= COMPANY (db/26) ===================== */
    /* Headcount of every company, for the "Employees by company" bar chart.
       Lists ALL companies (the top-bar @CompanyIds filter only highlights
       bars on the page); a user tied to one company (@CompanyId) sees only
       their own. */
    IF @Action = 'COMPANY'
    BEGIN
        SELECT  c.CompanyId,
                c.CompanyName,
                Headcount = COUNT(e.EmployeeId)
        FROM        [Core].[Companies] AS c
        LEFT JOIN   [Employee].[Employees] AS e
               ON   e.CompanyId = c.CompanyId
              AND   e.IsDeleted = 0
              AND   (e.HireDate IS NULL OR e.HireDate <= @AsOf)
              AND   (e.TerminationDate IS NULL OR e.TerminationDate > @AsOf)
              AND   NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)
        WHERE       (@CompanyId IS NULL OR c.CompanyId = @CompanyId)
        GROUP BY    c.CompanyId, c.CompanyName, c.IsActive
        HAVING      c.IsActive = 1 OR COUNT(e.EmployeeId) > 0
        ORDER BY    COUNT(e.EmployeeId) DESC, c.CompanyName;
        RETURN;
    END;

    /* Employees in scope (company filter, not soft-deleted) */
    DECLARE @Emp TABLE (
        EmployeeId BIGINT PRIMARY KEY, FullName NVARCHAR(250), DepartmentId INT,
        HireDate DATE, TerminationDate DATE, EmploymentStatus NVARCHAR(20),
        DateOfBirth DATE, ProbationEndDate DATE,
        CreatedDate DATETIME2(0), ModifiedDate DATETIME2(0));

    INSERT INTO @Emp
    SELECT e.EmployeeId,
           LTRIM(RTRIM(CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')))),
           e.DepartmentId, e.HireDate, e.TerminationDate, e.EmploymentStatus,
           e.DateOfBirth, e.ProbationEndDate, e.CreatedDate, e.ModifiedDate
    FROM [Employee].[Employees] e
    WHERE e.IsDeleted = 0
      AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
      AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);

    /* ======================= KPI ================================== */
    IF @Action = 'KPI'
    BEGIN
        SELECT
            TotalEmployees      = SUM(CASE WHEN x.OnBooks = 1 THEN 1 ELSE 0 END),
            PrevTotalEmployees  = SUM(CASE WHEN x.OnBooksPrev = 1 THEN 1 ELSE 0 END),
            ActiveEmployees     = SUM(CASE WHEN x.OnBooks = 1 AND x.EmploymentStatus IN (N'Active', N'Probation') THEN 1 ELSE 0 END),
            OnLeave             = SUM(CASE WHEN x.OnBooks = 1 AND x.EmploymentStatus = N'OnLeave' THEN 1 ELSE 0 END),
            NewJoiners          = SUM(CASE WHEN x.HireDate BETWEEN @MonthStart AND @MonthEnd THEN 1 ELSE 0 END),
            PrevNewJoiners      = SUM(CASE WHEN x.HireDate BETWEEN @PrevStart  AND @PrevEnd  THEN 1 ELSE 0 END),
            Separations         = SUM(CASE WHEN x.TerminationDate BETWEEN @MonthStart AND @MonthEnd THEN 1 ELSE 0 END),
            PrevSeparations     = SUM(CASE WHEN x.TerminationDate BETWEEN @PrevStart  AND @PrevEnd  THEN 1 ELSE 0 END)
        FROM (
            SELECT e.*,
                   OnBooks = CASE WHEN (e.HireDate IS NULL OR e.HireDate <= @AsOf)
                                   AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned')
                                            AND (e.TerminationDate IS NULL OR e.TerminationDate <= @AsOf))
                                   AND (e.TerminationDate IS NULL OR e.TerminationDate > @AsOf)
                                  THEN 1 ELSE 0 END,
                   OnBooksPrev = CASE WHEN (e.HireDate IS NULL OR e.HireDate <= @PrevEnd)
                                       AND (e.TerminationDate IS NULL OR e.TerminationDate > @PrevEnd)
                                      THEN 1 ELSE 0 END
            FROM @Emp e
        ) x;
        RETURN;
    END;

    /* ======================= TREND ================================ */
    IF @Action = 'TREND'
    BEGIN
        DECLARE @Months TABLE (MonthStart DATE PRIMARY KEY, MonthEnd DATE, AsOf DATE);
        DECLARE @i INT = 11;
        DECLARE @m DATE;
        WHILE @i >= 0
        BEGIN
            SET @m = DATEADD(MONTH, -@i, @MonthStart);
            INSERT INTO @Months VALUES (@m, EOMONTH(@m), CASE WHEN EOMONTH(@m) > @Today THEN @Today ELSE EOMONTH(@m) END);
            SET @i -= 1;
        END;

        DECLARE @HasPayroll BIT = CASE WHEN OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL THEN 0 ELSE 1 END;
        DECLARE @Pay TABLE (EmployeeId BIGINT PRIMARY KEY, Gross DECIMAL(14,3));
        IF @HasPayroll = 1
            INSERT INTO @Pay
            EXEC (N'SELECT EmployeeId, ISNULL(BasicSalary, 0) + ISNULL(Allowances, 0) FROM [Employee].[EmployeePayroll]');

        SELECT  m.MonthStart,
                Headcount = (SELECT COUNT(1) FROM @Emp e
                             WHERE (e.HireDate IS NULL OR e.HireDate <= m.AsOf)
                               AND (e.TerminationDate IS NULL OR e.TerminationDate > m.AsOf)
                               AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)),
                Joiners   = (SELECT COUNT(1) FROM @Emp e WHERE e.HireDate BETWEEN m.MonthStart AND m.MonthEnd),
                Leavers   = (SELECT COUNT(1) FROM @Emp e WHERE e.TerminationDate BETWEEN m.MonthStart AND m.MonthEnd),
                GrossPayroll = CASE WHEN @HasPayroll = 0 THEN NULL ELSE
                               (SELECT ISNULL(SUM(p.Gross), 0) FROM @Emp e JOIN @Pay p ON p.EmployeeId = e.EmployeeId
                                WHERE (e.HireDate IS NULL OR e.HireDate <= m.AsOf)
                                  AND (e.TerminationDate IS NULL OR e.TerminationDate > m.AsOf)
                                  AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)) END
        FROM @Months m
        ORDER BY m.MonthStart;
        RETURN;
    END;

    /* ======================= DEPT ================================= */
    IF @Action = 'DEPT'
    BEGIN
        SELECT  DepartmentName = ISNULL(d.DepartmentName, N'Unassigned'),
                Headcount      = COUNT(1)
        FROM        @Emp e
        LEFT JOIN   [Core].[Departments] d ON d.DepartmentId = e.DepartmentId
        WHERE       (e.HireDate IS NULL OR e.HireDate <= @Today)
                AND (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
                AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned')
        GROUP BY    ISNULL(d.DepartmentName, N'Unassigned')
        ORDER BY    COUNT(1) DESC, ISNULL(d.DepartmentName, N'Unassigned');
        RETURN;
    END;

    /* ======================= PAYROLL ============================== */
    IF @Action = 'PAYROLL'
    BEGIN
        IF OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
        BEGIN
            SELECT EmployeesWithSalary = 0, TotalBasic = CAST(NULL AS DECIMAL(14,3)),
                   TotalAllowances = CAST(NULL AS DECIMAL(14,3)), Gross = CAST(NULL AS DECIMAL(14,3));
            RETURN;
        END;

        DECLARE @PayrollSql NVARCHAR(MAX) = N'
            SELECT  EmployeesWithSalary = COUNT(1),
                    TotalBasic          = SUM(ISNULL(p.BasicSalary, 0)),
                    TotalAllowances     = SUM(ISNULL(p.Allowances, 0)),
                    Gross               = SUM(ISNULL(p.BasicSalary, 0) + ISNULL(p.Allowances, 0))
            FROM    [Employee].[EmployeePayroll] p
            JOIN    [Employee].[Employees] e ON e.EmployeeId = p.EmployeeId
            WHERE   e.IsDeleted = 0
              AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
              AND   (@CompanyIds IS NULL OR CHARINDEX(N'','' + CAST(e.CompanyId AS VARCHAR(12)) + N'','', N'','' + REPLACE(@CompanyIds, N'' '', N'''') + N'','') > 0)
              AND   (e.HireDate IS NULL OR e.HireDate <= @AsOf)
              AND   (e.TerminationDate IS NULL OR e.TerminationDate > @AsOf)
              AND   e.EmploymentStatus NOT IN (N''Terminated'', N''Resigned'');';
        EXEC sys.sp_executesql @PayrollSql, N'@CompanyId INT, @CompanyIds NVARCHAR(2000), @AsOf DATE', @CompanyId, @CompanyIds, @AsOf;
        RETURN;
    END;

    /* ======================= ACTIONS ============================== */
    IF @Action = 'ACTIONS'
    BEGIN
        -- #temp (not a table variable) so the dynamic SQL below can see it
        CREATE TABLE #Live (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO #Live
        SELECT EmployeeId FROM @Emp e
        WHERE (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
          AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned');

        DECLARE @MandatoryMissing INT = NULL;
        IF OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NOT NULL
           AND OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NOT NULL
        BEGIN
            DECLARE @MissingSql NVARCHAR(MAX) = N'
                SELECT @n = COUNT(DISTINCT l.EmployeeId)
                FROM #Live l
                CROSS JOIN [Documents].[vw_DocumentTypes] v
                WHERE v.IsActive = 1 AND v.Attachment_Mandatory = 1
                  AND NOT EXISTS (SELECT 1 FROM [Documents].[EmployeeDocumentAttachments] a
                                  WHERE a.EmployeeId = l.EmployeeId
                                    AND a.DocumentTypeId = v.DocumentTypeId AND a.IsDeleted = 0);';
            EXEC sys.sp_executesql @MissingSql, N'@n INT OUTPUT', @MandatoryMissing OUTPUT;
        END;

        SELECT
            DocumentsExpiring = (SELECT COUNT(DISTINCT c.EmployeeId)
                                 FROM [Kuwait].[EmployeeCompliance] c JOIN #Live l ON l.EmployeeId = c.EmployeeId
                                 WHERE c.CivilIdExpiryDate    BETWEEN @Today AND @Horizon
                                    OR c.PassportExpiryDate   BETWEEN @Today AND @Horizon
                                    OR c.ResidencyExpiryDate  BETWEEN @Today AND @Horizon
                                    OR c.WorkPermitExpiryDate BETWEEN @Today AND @Horizon),
            DocumentsExpired  = (SELECT COUNT(DISTINCT c.EmployeeId)
                                 FROM [Kuwait].[EmployeeCompliance] c JOIN #Live l ON l.EmployeeId = c.EmployeeId
                                 WHERE c.CivilIdExpiryDate    < @Today
                                    OR c.PassportExpiryDate   < @Today
                                    OR c.ResidencyExpiryDate  < @Today
                                    OR c.WorkPermitExpiryDate < @Today),
            ProbationEnding   = (SELECT COUNT(1) FROM @Emp e JOIN #Live l ON l.EmployeeId = e.EmployeeId
                                 WHERE e.ProbationEndDate BETWEEN @Today AND @Horizon),
            MandatoryDocumentsMissing = @MandatoryMissing;
        RETURN;
    END;

    /* ======================= EVENTS =============================== */
    IF @Action = 'EVENTS'
    BEGIN
        ;WITH live AS (
            SELECT * FROM @Emp e
            WHERE (e.TerminationDate IS NULL OR e.TerminationDate > @Today)
              AND e.EmploymentStatus NOT IN (N'Terminated', N'Resigned')
        ),
        birthdays AS (
            SELECT l.EmployeeId, l.FullName,
                   NextDate = CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today), l.DateOfBirth) < @Today
                                   THEN DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today) + 1, l.DateOfBirth)
                                   ELSE DATEADD(YEAR, DATEDIFF(YEAR, l.DateOfBirth, @Today), l.DateOfBirth) END
            FROM live l WHERE l.DateOfBirth IS NOT NULL
        ),
        anniversaries AS (
            SELECT l.EmployeeId, l.FullName, l.HireDate,
                   NextDate = CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today), l.HireDate) < @Today
                                   THEN DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today) + 1, l.HireDate)
                                   ELSE DATEADD(YEAR, DATEDIFF(YEAR, l.HireDate, @Today), l.HireDate) END
            FROM live l WHERE l.HireDate IS NOT NULL
        ),
        expiries AS (
            SELECT l.EmployeeId, l.FullName, v.Doc, v.ExpiryDate
            FROM live l
            JOIN [Kuwait].[EmployeeCompliance] c ON c.EmployeeId = l.EmployeeId
            CROSS APPLY (VALUES (N'Civil ID',    c.CivilIdExpiryDate),
                                (N'Passport',    c.PassportExpiryDate),
                                (N'Residency',   c.ResidencyExpiryDate),
                                (N'Work permit', c.WorkPermitExpiryDate)) v(Doc, ExpiryDate)
            WHERE v.ExpiryDate BETWEEN @Today AND @Horizon
        ),
        allEvents AS (
            SELECT EventType = 'BIRTHDAY', EmployeeId, FullName, EventDate = NextDate, Detail = N'Birthday'
            FROM birthdays WHERE NextDate BETWEEN @Today AND @Horizon
            UNION ALL
            SELECT 'ANNIVERSARY', EmployeeId, FullName, NextDate,
                   CONCAT(DATEDIFF(YEAR, HireDate, NextDate), N' year', CASE WHEN DATEDIFF(YEAR, HireDate, NextDate) = 1 THEN N'' ELSE N's' END, N' with the company')
            FROM anniversaries WHERE NextDate BETWEEN @Today AND @Horizon AND DATEDIFF(YEAR, HireDate, NextDate) >= 1
            UNION ALL
            SELECT 'EXPIRY', EmployeeId, FullName, ExpiryDate, CONCAT(Doc, N' expires') FROM expiries
            UNION ALL
            SELECT 'PROBATION', EmployeeId, FullName, ProbationEndDate, N'Probation ends'
            FROM live WHERE ProbationEndDate BETWEEN @Today AND @Horizon
        )
        SELECT TOP (15) EventType, EmployeeId, EmployeeName = FullName, EventDate, Detail
        FROM allEvents
        ORDER BY EventDate, EventType, FullName;
        RETURN;
    END;

    /* ======================= ACTIVITY ============================= */
    IF @Action = 'ACTIVITY'
    BEGIN
        DECLARE @Activity TABLE (EmployeeId BIGINT, EmployeeName NVARCHAR(250), Activity NVARCHAR(200), ActivityDate DATETIME2(0), Status NVARCHAR(30));

        INSERT INTO @Activity
        SELECT TOP (10) EmployeeId, FullName, N'New employee added', CreatedDate, N'Completed'
        FROM @Emp WHERE CreatedDate IS NOT NULL ORDER BY CreatedDate DESC;

        INSERT INTO @Activity
        SELECT TOP (10) EmployeeId, FullName, N'Profile updated', ModifiedDate, N'Updated'
        FROM @Emp WHERE ModifiedDate IS NOT NULL AND ModifiedDate > DATEADD(MINUTE, 1, CreatedDate)
        ORDER BY ModifiedDate DESC;

        INSERT INTO @Activity
        SELECT TOP (10) e.EmployeeId, e.FullName, N'Kuwait compliance updated', ISNULL(c.ModifiedDate, c.CreatedDate), N'Updated'
        FROM [Kuwait].[EmployeeCompliance] c JOIN @Emp e ON e.EmployeeId = c.EmployeeId
        ORDER BY ISNULL(c.ModifiedDate, c.CreatedDate) DESC;

        IF OBJECT_ID(N'[Documents].[EmployeeDocumentAttachments]', N'U') IS NOT NULL
           AND OBJECT_ID(N'[Documents].[vw_DocumentTypes]', N'V') IS NOT NULL
        BEGIN
            DECLARE @DocActivity TABLE (EmployeeId BIGINT, Activity NVARCHAR(200), ActivityDate DATETIME2(0));
            INSERT INTO @DocActivity
            EXEC (N'SELECT TOP (10) a.EmployeeId, CONCAT(N''Uploaded '', v.DocumentTypeName), a.UploadedDate
                    FROM [Documents].[EmployeeDocumentAttachments] a
                    JOIN [Documents].[vw_DocumentTypes] v ON v.DocumentTypeId = a.DocumentTypeId
                    ORDER BY a.UploadedDate DESC');

            INSERT INTO @Activity
            SELECT d.EmployeeId, e.FullName, d.Activity, d.ActivityDate, N'Uploaded'
            FROM @DocActivity d JOIN @Emp e ON e.EmployeeId = d.EmployeeId;
        END;

        SELECT TOP (8) EmployeeId, EmployeeName, Activity, ActivityDate, Status
        FROM @Activity
        ORDER BY ActivityDate DESC;
        RETURN;
    END;
END;
GO

PRINT N'db/26 applied: usp_Dashboard_Get COMPANY action (employees by company).';
GO
