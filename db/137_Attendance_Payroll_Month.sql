/* =====================================================================
   137_Attendance_Payroll_Month.sql  -  Attendance follows the payroll month
   ---------------------------------------------------------------------
   Run after db/136. Safe to re-run.

   Time & Attendance works by the payroll month of the company's monthly
   payroll calendar (the default one first) instead of the calendar month:
   with "Period starts on day" 25, October is 25 Sep - 24 Oct. It applies
   to the days list and its figures, the calculation (absences, free lates,
   the monthly cap), the Monthly Summary and its posting to the payroll,
   the import (the months it touches, the posted check), the Attendance
   Sheet (range, posted days, marks, locks). Start day 1: the calendar
   month, as before.

   Attendance.ufn_StartDay(company)          the start day (1 - 28; 1 with no monthly calendar)
   Attendance.ufn_MonthFrom / ufn_MonthTo   the first / last day of a payroll month
   Attendance.ufn_MonthOf(company, date)    the payroll month a day belongs to (25 Sep -> October)

   Note: months already posted keep what was posted; post a month again
   (undo the posting, then post) to post its new days.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[usp_AttMark_Manage]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/129, db/134 and db/136 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER FUNCTION [Attendance].[ufn_StartDay] (@CompanyId INT)
RETURNS INT
AS
BEGIN
    DECLARE @d INT = (SELECT TOP (1) DAY(c.FirstPeriodStartDate)
                      FROM   [Payroll].[PayrollCalendars] AS c
                      WHERE  c.CompanyId = @CompanyId AND c.Deleted = 0 AND c.IsActive = 1 AND c.PayFrequency = 'MONTHLY'
                      ORDER BY CASE WHEN c.IsDefault = 1 THEN 0 ELSE 1 END, c.PayrollCalendarId);
    RETURN CASE WHEN @d IS NULL OR @d < 1 THEN 1 WHEN @d > 28 THEN 28 ELSE @d END;
END;
GO

CREATE OR ALTER FUNCTION [Attendance].[ufn_MonthFrom] (@CompanyId INT, @Month DATE)
RETURNS DATE
AS
BEGIN
    DECLARE @sd INT = [Attendance].[ufn_StartDay](@CompanyId);
    DECLARE @m DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    RETURN CASE WHEN @sd = 1 THEN @m ELSE DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@m), MONTH(@m), @sd)) END;
END;
GO

CREATE OR ALTER FUNCTION [Attendance].[ufn_MonthTo] (@CompanyId INT, @Month DATE)
RETURNS DATE
AS
BEGIN
    DECLARE @sd INT = [Attendance].[ufn_StartDay](@CompanyId);
    DECLARE @m DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
    RETURN CASE WHEN @sd = 1 THEN EOMONTH(@m) ELSE DATEFROMPARTS(YEAR(@m), MONTH(@m), @sd - 1) END;
END;
GO

CREATE OR ALTER FUNCTION [Attendance].[ufn_MonthOf] (@CompanyId INT, @Date DATE)
RETURNS DATE
AS
BEGIN
    DECLARE @sd INT = [Attendance].[ufn_StartDay](@CompanyId);
    DECLARE @m DATE = DATEFROMPARTS(YEAR(@Date), MONTH(@Date), 1);
    RETURN CASE WHEN @sd = 1 OR DAY(@Date) < @sd THEN @m ELSE DATEADD(MONTH, 1, @m) END;
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttImport_Manage]
    @Action         VARCHAR(20),
    @Id             BIGINT         = NULL,
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FileName       NVARCHAR(260)  = NULL,
    @FileFormat     VARCHAR(10)    = NULL,
    @MappingText    NVARCHAR(1000) = NULL,
    @FileRowCount   INT            = NULL,
    @SkippedCount   INT            = NULL,
    @Json           NVARCHAR(MAX)  = NULL,
    @PageNumber     INT            = 1,
    @PageSize       INT            = 20,
    @UserId         BIGINT         = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action = 'SAVE'
    BEGIN
        DECLARE @In TABLE (EmployeeId BIGINT, CompanyId INT, WorkDate DATE, ClockIn DATETIME2(0), ClockOut DATETIME2(0), Punches SMALLINT,
                           PRIMARY KEY (EmployeeId, WorkDate));
        INSERT INTO @In (EmployeeId, CompanyId, WorkDate, ClockIn, ClockOut, Punches)
        SELECT  j.EmployeeId, e.CompanyId, j.WorkDate, MIN(j.ClockIn), MAX(j.ClockOut), MAX(ISNULL(j.Punches, 0))
        FROM    OPENJSON(ISNULL(@Json, N'[]'))
                WITH (EmployeeId BIGINT '$.employeeId', WorkDate DATE '$.workDate', ClockIn DATETIME2(0) '$.clockIn',
                      ClockOut DATETIME2(0) '$.clockOut', Punches SMALLINT '$.punches') AS j
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = j.EmployeeId AND e.Deleted = 0
        WHERE   j.WorkDate IS NOT NULL AND [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1
        GROUP BY j.EmployeeId, e.CompanyId, j.WorkDate;

        IF NOT EXISTS (SELECT 1 FROM @In)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Nothing to import - no row matched an employee of your companies.';
            RETURN;
        END;
        /* a month already posted to the payroll is not changed by an import */
        IF EXISTS (SELECT 1 FROM @In i JOIN [Attendance].[Postings] p ON p.EmployeeId = i.EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate))
        BEGIN
            DECLARE @Posted NVARCHAR(200) = (SELECT STRING_AGG(m, N', ') FROM (SELECT DISTINCT FORMAT(p.RunMonth, 'MMM yyyy', 'en-US') AS m
                FROM @In i JOIN [Attendance].[Postings] p ON p.EmployeeId = i.EmployeeId AND p.Deleted = 0
                AND p.RunMonth = [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate)) AS x);
            SELECT @ResultCode = 'POSTED', @ResultMessage = CONCAT(N'Already posted to the payroll: ', @Posted,
                N'. Undo the posting (Monthly Summary) before importing these days again.');
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Attendance].[Imports] (FileName, FileFormat, MappingText, FromDate, ToDate, FileRowCount, RecordCount, EmployeeCount, SkippedCount, CreatedBy)
            SELECT LEFT(ISNULL(@FileName, N'attendance'), 260), CASE WHEN @FileFormat = 'PUNCH' THEN 'PUNCH' ELSE 'PAIRED' END, LEFT(@MappingText, 1000),
                   MIN(WorkDate), MAX(WorkDate), ISNULL(@FileRowCount, 0), COUNT(1), COUNT(DISTINCT EmployeeId), ISNULL(@SkippedCount, 0), @UserId
            FROM   @In;
            SET @NewId = SCOPE_IDENTITY();

            /* the new file replaces those days (the old values are kept, deleted) */
            UPDATE r SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Attendance].[Records] AS r
            JOIN   @In AS i ON i.EmployeeId = r.EmployeeId AND i.WorkDate = r.WorkDate
            WHERE  r.Deleted = 0;

            INSERT INTO [Attendance].[Records] (ImportId, CompanyId, EmployeeId, WorkDate, ClockIn, ClockOut, PunchCount, Source, CreatedBy)
            SELECT @NewId, i.CompanyId, i.EmployeeId, i.WorkDate, i.ClockIn, i.ClockOut, i.Punches, 'IMPORT', @UserId
            FROM   @In AS i;
            SET @TotalCount = @@ROWCOUNT;
        COMMIT TRANSACTION;

        SELECT DISTINCT i.CompanyId, [Attendance].[ufn_MonthOf](i.CompanyId, i.WorkDate) AS RunMonth FROM @In AS i;
        SET @ResultMessage = CONCAT(N'Imported ', @TotalCount, N' days.');
        RETURN;
    END;

    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN ISNULL(@PageSize, 20) NOT BETWEEN 1 AND 200 THEN 20 ELSE @PageSize END;
        ;WITH x AS (
            SELECT  i.ImportId, i.FileName, i.FileFormat, i.MappingText, i.FromDate, i.ToDate, i.FileRowCount, i.RecordCount, i.EmployeeCount,
                    i.SkippedCount, i.CreatedDate,
                    COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ce.FirstName, N' ', ce.LastName))), N''), cu.Username) AS CreatedByName,
                    (SELECT COUNT(1) FROM [Attendance].[Records] r WHERE r.ImportId = i.ImportId AND r.Deleted = 0) AS LiveCount
            FROM    [Attendance].[Imports] AS i
            LEFT JOIN [Security].[Users] AS cu ON cu.UserId = i.CreatedBy
            LEFT JOIN [Employee].[Employees] AS ce ON ce.EmployeeId = cu.EmployeeId
            WHERE   i.Deleted = 0
              AND   EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.ImportId = i.ImportId
                            AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1)
        )
        SELECT x.*, COUNT(1) OVER () AS Total FROM x
        ORDER BY x.CreatedDate DESC, x.ImportId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Attendance].[Records] r JOIN [Attendance].[Postings] p ON p.EmployeeId = r.EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)
                   WHERE r.ImportId = @Id AND r.Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'POSTED', @ResultMessage = N'Days of this file are already posted to the payroll - undo the posting first.';
            RETURN;
        END;
        DECLARE @Months TABLE (CompanyId INT, RunMonth DATE);
        INSERT INTO @Months SELECT DISTINCT r.CompanyId, [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)
        FROM [Attendance].[Records] r WHERE r.ImportId = @Id AND r.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;
        BEGIN TRANSACTION;
            UPDATE [Attendance].[Records] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            WHERE  ImportId = @Id AND Deleted = 0 AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1;
            IF NOT EXISTS (SELECT 1 FROM [Attendance].[Records] WHERE ImportId = @Id AND Deleted = 0)
                UPDATE [Attendance].[Imports] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE ImportId = @Id;
        COMMIT TRANSACTION;
        SELECT CompanyId, RunMonth FROM @Months;
        SET @ResultMessage = N'The file''s days were removed.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttRecord_Manage]
    @Action         VARCHAR(20),
    @Id             BIGINT         = NULL,
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FilterCompany  INT            = NULL,
    @Month          DATE           = NULL,
    @EmployeeId     BIGINT         = NULL,
    @StatusFilter   VARCHAR(12)    = NULL,
    @Search         NVARCHAR(200)  = NULL,
    @ClockIn        DATETIME2(0)   = NULL,
    @ClockOut       DATETIME2(0)   = NULL,
    @IsExcused      BIT            = NULL,
    @Note           NVARCHAR(500)  = NULL,
    @Json           NVARCHAR(MAX)  = NULL,
    @PageNumber     INT            = 1,
    @PageSize       INT            = 50,
    @UserId         BIGINT         = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    /* db/137: a month is the payroll month of the company's calendar (start 25 -> 25th of the previous month to the 24th) */
    DECLARE @MonthKey DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, GETDATE())), MONTH(ISNULL(@Month, GETDATE())), 1);
    DECLARE @From DATE = CASE WHEN @FilterCompany IS NULL THEN DATEADD(DAY, -31, @MonthKey) ELSE [Attendance].[ufn_MonthFrom](@FilterCompany, @MonthKey) END;
    DECLARE @To DATE = CASE WHEN @FilterCompany IS NULL THEN EOMONTH(@MonthKey) ELSE [Attendance].[ufn_MonthTo](@FilterCompany, @MonthKey) END;
    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 50) NOT BETWEEN 1 AND 500 THEN 50 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'CTX_RECORDS'
    BEGIN
        SELECT  r.RecordId, r.CompanyId, r.EmployeeId, r.WorkDate, r.ClockIn, r.ClockOut, r.PunchCount, r.Source, r.IsExcused, r.Note
        FROM    [Attendance].[Records] AS r
        WHERE   r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.WorkDate BETWEEN @From AND @To
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId);
        RETURN;
    END;

    IF @Action = 'CTX_EMP'
    BEGIN
        SELECT  e.EmployeeId, e.CompanyId, ISNULL(ep.BasicSalary, 0) AS BasicSalary, ISNULL(ep.Allowances, 0) AS Allowances,
                e.HireDate, e.TerminationDate
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId
        WHERE   e.Deleted = 0 AND e.CompanyId = @FilterCompany
          AND   [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@EmployeeId IS NULL OR e.EmployeeId = @EmployeeId)
          AND  (EXISTS (SELECT 1 FROM [Attendance].[EmployeePatterns] a WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom <= @To)
                OR EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.EmployeeId = e.EmployeeId AND r.Deleted = 0 AND r.WorkDate BETWEEN @From AND @To));
        RETURN;
    END;

    IF @Action = 'CTX_LEAVE'
    BEGIN
        SELECT  lr.EmployeeId, lr.StartDate, ISNULL(lr.ActualEndDate, lr.EndDate) AS EndDate, lr.HalfDay
        FROM    [Leave].[LeaveRequests] AS lr
        WHERE   lr.Deleted = 0 AND lr.Status = 'APPROVED' AND lr.CompanyId = @FilterCompany
          AND   lr.StartDate <= @To AND ISNULL(lr.ActualEndDate, lr.EndDate) >= @From;
        RETURN;
    END;

    IF @Action = 'CTX_HOLIDAY'
    BEGIN
        SELECT  h.FromDate, h.ToDate, h.HolidayName
        FROM    [Leave].[PublicHolidays] AS h
        WHERE   h.Deleted = 0 AND (h.CompanyId IS NULL OR h.CompanyId = @FilterCompany)
          AND   h.FromDate <= @To AND h.ToDate >= @From;
        RETURN;
    END;

    IF @Action = 'SAVE_CALC'
    BEGIN
        DECLARE @R TABLE (RecordId BIGINT, EmployeeId BIGINT, WorkDate DATE, PatternId INT, Status VARCHAR(12), WorkedMinutes INT,
                          LateMinutes INT, ShortMinutes INT, OvertimeMinutes INT, DeductionAmount DECIMAL(12,3), OvertimeAmount DECIMAL(12,3),
                          DeductionNote NVARCHAR(300));
        INSERT INTO @R
        SELECT  ISNULL(j.RecordId, 0), j.EmployeeId, j.WorkDate, j.PatternId, j.Status, ISNULL(j.WorkedMinutes, 0), ISNULL(j.LateMinutes, 0),
                ISNULL(j.ShortMinutes, 0), ISNULL(j.OvertimeMinutes, 0), ISNULL(j.DeductionAmount, 0), ISNULL(j.OvertimeAmount, 0), j.DeductionNote
        FROM    OPENJSON(ISNULL(@Json, N'[]'))
                WITH (RecordId BIGINT '$.recordId', EmployeeId BIGINT '$.employeeId', WorkDate DATE '$.workDate', PatternId INT '$.patternId',
                      Status VARCHAR(12) '$.status', WorkedMinutes INT '$.workedMinutes', LateMinutes INT '$.lateMinutes',
                      ShortMinutes INT '$.shortMinutes', OvertimeMinutes INT '$.overtimeMinutes', DeductionAmount DECIMAL(12,3) '$.deductionAmount',
                      OvertimeAmount DECIMAL(12,3) '$.overtimeAmount', DeductionNote NVARCHAR(300) '$.deductionNote') AS j;

        BEGIN TRANSACTION;
            /* the days worked out before (absent, leave, holiday) are worked out again */
            UPDATE [Attendance].[Records] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            WHERE  Deleted = 0 AND Source = 'GENERATED' AND CompanyId = @FilterCompany AND WorkDate BETWEEN @From AND @To
              AND (@EmployeeId IS NULL OR EmployeeId = @EmployeeId)
              AND  [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1;

            UPDATE r SET PatternId = x.PatternId, Status = x.Status, WorkedMinutes = x.WorkedMinutes, LateMinutes = x.LateMinutes,
                         ShortMinutes = x.ShortMinutes, OvertimeMinutes = x.OvertimeMinutes, DeductionAmount = x.DeductionAmount,
                         OvertimeAmount = x.OvertimeAmount, DeductionNote = x.DeductionNote
            FROM   [Attendance].[Records] AS r
            JOIN   @R AS x ON x.RecordId = r.RecordId
            WHERE  r.Deleted = 0 AND r.CompanyId = @FilterCompany AND x.RecordId > 0;

            INSERT INTO [Attendance].[Records] (CompanyId, EmployeeId, WorkDate, Source, PatternId, Status, WorkedMinutes, LateMinutes,
                                                ShortMinutes, OvertimeMinutes, DeductionAmount, OvertimeAmount, DeductionNote, CreatedBy)
            SELECT @FilterCompany, x.EmployeeId, x.WorkDate, 'GENERATED', x.PatternId, x.Status, 0, 0, 0, 0, x.DeductionAmount, 0, x.DeductionNote, @UserId
            FROM   @R AS x
            JOIN   [Employee].[Employees] AS e ON e.EmployeeId = x.EmployeeId AND e.CompanyId = @FilterCompany
            WHERE  x.RecordId = 0 AND x.WorkDate BETWEEN @From AND @To
              AND  NOT EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.EmployeeId = x.EmployeeId AND r.WorkDate = x.WorkDate AND r.Deleted = 0);
        COMMIT TRANSACTION;
        SELECT @TotalCount = COUNT(1) FROM @R;
        RETURN;
    END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        ;WITH x AS (
            SELECT  r.RecordId, r.ImportId, r.CompanyId, co.CompanyName, r.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                    LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName, d.DepartmentName,
                    r.WorkDate, r.ClockIn, r.ClockOut, r.PunchCount, r.Source, r.PatternId, p.PatternName, r.Status, r.WorkedMinutes,
                    r.LateMinutes, r.ShortMinutes, r.OvertimeMinutes, r.DeductionAmount, r.OvertimeAmount, r.DeductionNote, r.IsExcused, r.Note,
                    r.OriginalClockIn, r.OriginalClockOut, r.EditedDate,
                    COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS EditedByName,
                    CAST(CASE WHEN EXISTS (SELECT 1 FROM [Attendance].[Postings] ps WHERE ps.EmployeeId = r.EmployeeId AND ps.Deleted = 0
                               AND ps.RunMonth = [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)) THEN 1 ELSE 0 END AS BIT) AS IsPosted
            FROM    [Attendance].[Records] AS r
            JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
            JOIN    [Core].[Companies] AS co ON co.CompanyId = r.CompanyId
            LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
            LEFT JOIN [Attendance].[Patterns] AS p ON p.PatternId = r.PatternId
            LEFT JOIN [Security].[Users] AS u ON u.UserId = r.EditedBy
            LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
            WHERE   r.Deleted = 0
              AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
              AND  (   (@Action = 'GET' AND r.RecordId = @Id)
                    OR (@Action = 'LIST' AND r.WorkDate BETWEEN @From AND @To
                        AND (@FilterCompany IS NOT NULL OR [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate) = @MonthKey)
                        AND (@FilterCompany IS NULL OR r.CompanyId = @FilterCompany)
                        AND (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId)
                        AND (@StatusFilter IS NULL
                             OR (@StatusFilter = 'ISSUES' AND r.Status IN ('LATE', 'SHORT', 'LATE_SHORT', 'ABSENT', 'MISSING', 'NO_PATTERN'))
                             OR (@StatusFilter = 'DEDUCTED' AND r.DeductionAmount > 0)
                             OR (@StatusFilter = 'LATE' AND r.Status IN ('LATE', 'LATE_SHORT'))
                             OR (@StatusFilter = 'SHORT' AND r.Status IN ('SHORT', 'LATE_SHORT'))
                             OR (@StatusFilter = 'OVERTIME' AND r.OvertimeMinutes > 0)
                             OR r.Status = @StatusFilter)))
        )
        SELECT  x.*, COUNT(1) OVER () AS Total
        FROM    x
        WHERE  (@Pattern IS NULL OR x.EmployeeName LIKE @Pattern ESCAPE '\' OR x.ArabicName LIKE @Pattern ESCAPE '\'
                OR x.EmployeeNo LIKE @Pattern ESCAPE '\' OR x.DepartmentName LIKE @Pattern ESCAPE '\')
        ORDER BY x.EmployeeName, x.EmployeeId, x.WorkDate
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'KPIS'
    BEGIN
        SELECT  COUNT(DISTINCT r.EmployeeId) AS EmployeeCount,
                ISNULL(SUM(CASE WHEN r.Status IN ('PRESENT', 'LATE', 'SHORT', 'LATE_SHORT', 'EXCUSED') THEN 1 ELSE 0 END), 0) AS PresentDays,
                ISNULL(SUM(CASE WHEN r.Status IN ('LATE', 'LATE_SHORT') THEN 1 ELSE 0 END), 0) AS LateDays,
                ISNULL(SUM(CASE WHEN r.Status IN ('SHORT', 'LATE_SHORT') THEN 1 ELSE 0 END), 0) AS ShortDays,
                ISNULL(SUM(CASE WHEN r.Status = 'ABSENT' THEN 1 ELSE 0 END), 0) AS AbsentDays,
                ISNULL(SUM(CASE WHEN r.Status IN ('MISSING', 'NO_PATTERN') THEN 1 ELSE 0 END), 0) AS ReviewDays,
                ISNULL(SUM(r.LateMinutes), 0) AS LateMinutes, ISNULL(SUM(r.ShortMinutes), 0) AS ShortMinutes,
                ISNULL(SUM(r.OvertimeMinutes), 0) AS OvertimeMinutes,
                ISNULL(SUM(r.DeductionAmount), 0) AS DeductionAmount, ISNULL(SUM(r.OvertimeAmount), 0) AS OvertimeAmount,
                MIN(r.WorkDate) AS FirstDate, MAX(r.WorkDate) AS LastDate
        FROM    [Attendance].[Records] AS r
        WHERE   r.Deleted = 0 AND r.WorkDate BETWEEN @From AND @To
          AND  (@FilterCompany IS NOT NULL OR [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate) = @MonthKey)
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@FilterCompany IS NULL OR r.CompanyId = @FilterCompany)
          AND  (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId);
        RETURN;
    END;

    IF @Action = 'MONTHS'
    BEGIN
        SELECT DISTINCT [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate) AS RunMonth
        FROM   [Attendance].[Records] AS r
        WHERE  r.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@FilterCompany IS NULL OR r.CompanyId = @FilterCompany)
        ORDER BY RunMonth DESC;
        RETURN;
    END;

    IF @Action = 'EDIT'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Attendance].[Records] WHERE RecordId = @Id AND Deleted = 0
                       AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'The day was not found.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Attendance].[Records] r JOIN [Attendance].[Postings] p ON p.EmployeeId = r.EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate) WHERE r.RecordId = @Id)
        BEGIN
            SELECT @ResultCode = 'POSTED', @ResultMessage = N'This month is already posted to the payroll - undo the posting to change a day.';
            RETURN;
        END;
        IF @ClockIn IS NOT NULL AND @ClockOut IS NOT NULL AND @ClockOut <= @ClockIn
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The clock out must be after the clock in.';
            RETURN;
        END;
        UPDATE [Attendance].[Records]
        SET    OriginalClockIn  = CASE WHEN EditedDate IS NULL THEN ClockIn ELSE OriginalClockIn END,
               OriginalClockOut = CASE WHEN EditedDate IS NULL THEN ClockOut ELSE OriginalClockOut END,
               ClockIn = @ClockIn, ClockOut = @ClockOut, IsExcused = ISNULL(@IsExcused, 0), Note = NULLIF(LTRIM(RTRIM(@Note)), N''),
               Source = CASE WHEN Source = 'GENERATED' THEN 'MANUAL' ELSE Source END,
               EditedBy = @UserId, EditedDate = @Now
        WHERE  RecordId = @Id;
        SELECT CompanyId, [Attendance].[ufn_MonthOf](CompanyId, WorkDate) AS RunMonth, EmployeeId FROM [Attendance].[Records] WHERE RecordId = @Id;
        SET @ResultMessage = N'Day saved.';
        RETURN;
    END;

    IF @Action = 'ADD'
    BEGIN
        /* a day the device missed: entered by hand */
        DECLARE @Co INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @Co IS NULL OR [Payroll].[ufn_InCompanyScope](@Co, @CompanyId, @CompanyIds) = 0 OR @Month IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the employee and the date.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Attendance].[Postings] p WHERE p.EmployeeId = @EmployeeId AND p.Deleted = 0
                   AND p.RunMonth = [Attendance].[ufn_MonthOf](@Co, @Month))
        BEGIN
            SELECT @ResultCode = 'POSTED', @ResultMessage = N'This month is already posted to the payroll - undo the posting to change a day.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE [Attendance].[Records] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            WHERE  EmployeeId = @EmployeeId AND WorkDate = @Month AND Deleted = 0;
            INSERT INTO [Attendance].[Records] (CompanyId, EmployeeId, WorkDate, ClockIn, ClockOut, Source, IsExcused, Note, EditedBy, EditedDate, CreatedBy)
            VALUES (@Co, @EmployeeId, @Month, @ClockIn, @ClockOut, 'MANUAL', ISNULL(@IsExcused, 0), NULLIF(LTRIM(RTRIM(@Note)), N''), @UserId, @Now, @UserId);
            SET @NewId = SCOPE_IDENTITY();
        COMMIT TRANSACTION;
        SELECT @Co AS CompanyId, [Attendance].[ufn_MonthOf](@Co, @Month) AS RunMonth, @EmployeeId AS EmployeeId;
        SET @ResultMessage = N'Day saved.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttSummary_Manage]
    @Action         VARCHAR(20),
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FilterCompany  INT            = NULL,
    @Month          DATE           = NULL,
    @Json           NVARCHAR(MAX)  = NULL,
    @UserId         BIGINT         = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @From DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, GETDATE())), MONTH(ISNULL(@Month, GETDATE())), 1);
    DECLARE @To DATE = EOMONTH(@From);
    /* db/137: the days of the payroll month (the calendar's start day): @From stays the month itself */
    DECLARE @DFrom DATE = CASE WHEN @FilterCompany IS NULL THEN @From ELSE [Attendance].[ufn_MonthFrom](@FilterCompany, @From) END;
    DECLARE @DTo DATE = CASE WHEN @FilterCompany IS NULL THEN @To ELSE [Attendance].[ufn_MonthTo](@FilterCompany, @From) END;
    DECLARE @Ref NVARCHAR(50) = N'ATT:' + FORMAT(@From, 'yyyy-MM', 'en-US');

    IF @FilterCompany IS NULL OR [Payroll].[ufn_InCompanyScope](@FilterCompany, @CompanyId, @CompanyIds) = 0
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the company.';
        RETURN;
    END;

    IF @Action = 'LIST'
    BEGIN
        SELECT  e.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName,
                e.ArabicName, d.DepartmentName, pat.PatternName,
                COUNT(r.RecordId) AS DayCount,
                SUM(CASE WHEN r.Status IN ('PRESENT', 'LATE', 'SHORT', 'LATE_SHORT', 'EXCUSED') THEN 1 ELSE 0 END) AS PresentDays,
                SUM(CASE WHEN r.Status IN ('LATE', 'LATE_SHORT') THEN 1 ELSE 0 END) AS LateDays,
                SUM(CASE WHEN r.Status IN ('SHORT', 'LATE_SHORT') THEN 1 ELSE 0 END) AS ShortDays,
                SUM(CASE WHEN r.Status = 'ABSENT' THEN 1 ELSE 0 END) AS AbsentDays,
                SUM(CASE WHEN r.Status = 'LEAVE' THEN 1 ELSE 0 END) AS LeaveDays,
                SUM(CASE WHEN r.Status IN ('MISSING', 'NO_PATTERN') THEN 1 ELSE 0 END) AS ReviewDays,
                SUM(r.WorkedMinutes) AS WorkedMinutes, SUM(r.LateMinutes) AS LateMinutes, SUM(r.ShortMinutes) AS ShortMinutes,
                SUM(r.OvertimeMinutes) AS OvertimeMinutes, SUM(r.DeductionAmount) AS DeductionAmount, SUM(r.OvertimeAmount) AS OvertimeAmount,
                ps.DeductionAmount AS PostedDeduction, ps.OvertimeAmount AS PostedOvertime, ps.PostedDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS PostedByName
        FROM    [Attendance].[Records] AS r
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        OUTER APPLY (SELECT TOP (1) p.PatternName FROM [Attendance].[EmployeePatterns] a JOIN [Attendance].[Patterns] p ON p.PatternId = a.PatternId
                     WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom <= @DTo ORDER BY a.EffectiveFrom DESC) AS pat
        LEFT JOIN [Attendance].[Postings] AS ps ON ps.EmployeeId = e.EmployeeId AND ps.RunMonth = @From AND ps.Deleted = 0
        LEFT JOIN [Security].[Users] AS u ON u.UserId = ps.PostedBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.WorkDate BETWEEN @DFrom AND @DTo
        GROUP BY e.EmployeeId, e.EmployeeCode, e.EmployeeNo, e.FirstName, e.LastName, e.ArabicName, d.DepartmentName, pat.PatternName,
                 ps.DeductionAmount, ps.OvertimeAmount, ps.PostedDate, ue.FirstName, ue.LastName, u.Username
        ORDER BY EmployeeName;
        RETURN;
    END;

    IF @Action = 'POST'
    BEGIN
        DECLARE @P TABLE (EmployeeId BIGINT PRIMARY KEY, Deduction DECIMAL(12,3), Overtime DECIMAL(12,3));
        INSERT INTO @P (EmployeeId, Deduction, Overtime)
        SELECT  j.EmployeeId, ROUND(ISNULL(j.Deduction, 0), 3), ROUND(ISNULL(j.Overtime, 0), 3)
        FROM    OPENJSON(ISNULL(@Json, N'[]')) WITH (EmployeeId BIGINT '$.employeeId', Deduction DECIMAL(12,3) '$.deduction',
                                                     Overtime DECIMAL(12,3) '$.overtime') AS j
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = j.EmployeeId AND e.CompanyId = @FilterCompany AND e.Deleted = 0;

        IF NOT EXISTS (SELECT 1 FROM @P)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Nothing to post for this month.';
            RETURN;
        END;
        /* a pay item a closed payroll has used is never replaced */
        IF EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] i JOIN @P p ON p.EmployeeId = i.EmployeeId
                   WHERE i.Deleted = 0 AND i.SourceRef = @Ref AND i.PayrollRunId IS NOT NULL)
           OR EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r WHERE r.CompanyId = @FilterCompany AND r.RunMonth = @From AND r.Deleted = 0
                      AND r.RunType = 'REGULAR' AND r.Stage = 'CLOSED')
        BEGIN
            SELECT @ResultCode = 'CLOSED', @ResultMessage = N'The payroll of this month is already approved - the attendance can no longer be posted to it.';
            RETURN;
        END;

        DECLARE @DedType INT, @OtType INT;
        BEGIN TRANSACTION;
            /* the item types of the posting (added to the company when missing) */
            IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @FilterCompany AND ComponentCode = N'ATT_DEDUCTION' AND Deleted = 0)
                INSERT INTO [Payroll].[PayComponents] (CompanyId, ComponentCode, ComponentName, ArabicName, ComponentType, ValueType,
                    CalculationMethod, IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, Description, CreatedBy)
                VALUES (@FilterCompany, N'ATT_DEDUCTION', N'Attendance deduction', N'خصم الحضور', 'DEDUCTION', 'VARIABLE', 'AMOUNT', 0, 0, 1, 300,
                        N'Late arrival, short hours and absence - posted from Time & Attendance.', @UserId);
            IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @FilterCompany AND ComponentCode = N'ATT_OVERTIME' AND Deleted = 0)
                INSERT INTO [Payroll].[PayComponents] (CompanyId, ComponentCode, ComponentName, ArabicName, ComponentType, ValueType,
                    CalculationMethod, IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, Description, CreatedBy)
                VALUES (@FilterCompany, N'ATT_OVERTIME', N'Overtime (attendance)', N'العمل الإضافي (الحضور)', 'EARNING', 'VARIABLE', 'AMOUNT', 0, 0, 1, 210,
                        N'Overtime worked - posted from Time & Attendance.', @UserId);
            SELECT @DedType = PayComponentId FROM [Payroll].[PayComponents] WHERE CompanyId = @FilterCompany AND ComponentCode = N'ATT_DEDUCTION' AND Deleted = 0;
            SELECT @OtType  = PayComponentId FROM [Payroll].[PayComponents] WHERE CompanyId = @FilterCompany AND ComponentCode = N'ATT_OVERTIME' AND Deleted = 0;

            /* posting again replaces the month's items and the posting */
            UPDATE i SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Payroll].[EmployeePayItems] AS i JOIN @P AS p ON p.EmployeeId = i.EmployeeId
            WHERE  i.Deleted = 0 AND i.SourceRef = @Ref;
            UPDATE s SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Attendance].[Postings] AS s JOIN @P AS p ON p.EmployeeId = s.EmployeeId
            WHERE  s.Deleted = 0 AND s.RunMonth = @From;

            DECLARE @Items TABLE (ItemId BIGINT, EmployeeId BIGINT, Kind CHAR(1));
            INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, SourceRef, CreatedBy)
            OUTPUT inserted.EmployeePayItemId, inserted.EmployeeId, CASE WHEN inserted.PayComponentId = @DedType THEN 'D' ELSE 'O' END INTO @Items
            SELECT @FilterCompany, p.EmployeeId, v.TypeId, v.Amount, 'ONCE', @From,
                   CONCAT(N'Time & Attendance - ', FORMAT(@From, 'MMMM yyyy', 'en-US')), 'ACTIVE', @Ref, @UserId
            FROM   @P AS p
            CROSS APPLY (VALUES (@DedType, p.Deduction), (@OtType, p.Overtime)) AS v(TypeId, Amount)
            WHERE  v.Amount > 0;

            INSERT INTO [Attendance].[Postings] (CompanyId, RunMonth, EmployeeId, DeductionAmount, OvertimeAmount, DeductionItemId, OvertimeItemId, PostedBy)
            SELECT @FilterCompany, @From, p.EmployeeId, p.Deduction, p.Overtime,
                   (SELECT TOP (1) ItemId FROM @Items i WHERE i.EmployeeId = p.EmployeeId AND i.Kind = 'D'),
                   (SELECT TOP (1) ItemId FROM @Items i WHERE i.EmployeeId = p.EmployeeId AND i.Kind = 'O'), @UserId
            FROM   @P AS p;
            SET @TotalCount = @@ROWCOUNT;
        COMMIT TRANSACTION;
        SET @ResultMessage = CONCAT(N'Posted to the payroll for ', @TotalCount, CASE WHEN @TotalCount = 1 THEN N' employee' ELSE N' employees' END,
                                    N' - recalculate the month''s payroll if it is already created.');
        RETURN;
    END;

    IF @Action = 'UNPOST'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] i JOIN [Employee].[Employees] e ON e.EmployeeId = i.EmployeeId AND e.CompanyId = @FilterCompany
                   WHERE i.Deleted = 0 AND i.SourceRef = @Ref AND i.PayrollRunId IS NOT NULL)
           OR EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r WHERE r.CompanyId = @FilterCompany AND r.RunMonth = @From AND r.Deleted = 0
                      AND r.RunType = 'REGULAR' AND r.Stage = 'CLOSED')
        BEGIN
            SELECT @ResultCode = 'CLOSED', @ResultMessage = N'The payroll of this month is already approved - the posting stays.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            UPDATE i SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Payroll].[EmployeePayItems] AS i JOIN [Employee].[Employees] AS e ON e.EmployeeId = i.EmployeeId AND e.CompanyId = @FilterCompany
            WHERE  i.Deleted = 0 AND i.SourceRef = @Ref;
            UPDATE [Attendance].[Postings] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            WHERE  Deleted = 0 AND CompanyId = @FilterCompany AND RunMonth = @From;
            SET @TotalCount = @@ROWCOUNT;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'The posting was taken back - the days can be changed again.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttSheet]
    @Action         VARCHAR(20),
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FilterCompany  INT            = NULL,
    @Month          DATE           = NULL,
    @FromDate       DATE           = NULL,
    @ToDate         DATE           = NULL,
    @Search         NVARCHAR(200)  = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;

    IF @FilterCompany IS NULL OR [Payroll].[ufn_InCompanyScope](@FilterCompany, @CompanyId, @CompanyIds) = 0
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the company.';
        RETURN;
    END;

    IF @Action = 'PERIOD'
    BEGIN
        /* db/137: the payroll month of the company's calendar start day (the same days attendance is worked out and posted for) */
        SELECT [Attendance].[ufn_MonthFrom](@FilterCompany, @Month) AS StartDate, [Attendance].[ufn_MonthTo](@FilterCompany, @Month) AS EndDate;
        RETURN;
    END;

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName,
                d.DepartmentName, e.HireDate, e.TerminationDate
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0 AND e.CompanyId = @FilterCompany
          AND  (e.HireDate IS NULL OR e.HireDate <= @ToDate)
          AND  (e.TerminationDate IS NULL OR e.TerminationDate >= @FromDate)
          AND  (EXISTS (SELECT 1 FROM [Attendance].[EmployeePatterns] a WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom <= @ToDate)
                OR EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.EmployeeId = e.EmployeeId AND r.Deleted = 0
                           AND r.WorkDate BETWEEN @FromDate AND @ToDate))
          AND  (@Pattern IS NULL OR e.FirstName LIKE @Pattern ESCAPE '\' OR e.LastName LIKE @Pattern ESCAPE '\'
                OR e.ArabicName LIKE @Pattern ESCAPE '\' OR e.EmployeeNo LIKE @Pattern ESCAPE '\' OR e.EmployeeCode LIKE @Pattern ESCAPE '\'
                OR d.DepartmentName LIKE @Pattern ESCAPE '\')
        ORDER BY d.DepartmentName, EmployeeName;
        RETURN;
    END;

    IF @Action = 'DAYS'
    BEGIN
        SELECT  r.RecordId, r.EmployeeId, r.WorkDate, r.ClockIn, r.ClockOut, r.Source, r.Status, r.WorkedMinutes, r.LateMinutes,
                r.ShortMinutes, r.OvertimeMinutes, r.DeductionAmount, r.OvertimeAmount, r.DeductionNote, r.IsExcused, r.Note, r.ManualStatus, r.ManualMinutes,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM [Attendance].[Postings] ps WHERE ps.EmployeeId = r.EmployeeId AND ps.Deleted = 0
                           AND ps.RunMonth = [Attendance].[ufn_MonthOf](r.CompanyId, r.WorkDate)) THEN 1 ELSE 0 END AS BIT) AS IsPosted
        FROM    [Attendance].[Records] AS r
        WHERE   r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.WorkDate BETWEEN @FromDate AND @ToDate;
        RETURN;
    END;

    IF @Action = 'HOLIDAYS'
    BEGIN
        SELECT h.FromDate, h.ToDate, h.HolidayName
        FROM   [Leave].[PublicHolidays] AS h
        WHERE  h.Deleted = 0 AND (h.CompanyId IS NULL OR h.CompanyId = @FilterCompany) AND h.FromDate <= @ToDate AND h.ToDate >= @FromDate;
        RETURN;
    END;

    IF @Action = 'LEAVE'
    BEGIN
        SELECT lr.EmployeeId, lr.StartDate, ISNULL(lr.ActualEndDate, lr.EndDate) AS EndDate, lr.HalfDay
        FROM   [Leave].[LeaveRequests] AS lr
        WHERE  lr.Deleted = 0 AND lr.Status = 'APPROVED' AND lr.CompanyId = @FilterCompany
          AND  lr.StartDate <= @ToDate AND ISNULL(lr.ActualEndDate, lr.EndDate) >= @FromDate;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

CREATE OR ALTER PROCEDURE [Attendance].[usp_AttMark_Manage]
    @Action         VARCHAR(20),
    @Id             BIGINT         = NULL,
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FilterCompany  INT            = NULL,
    @Month          DATE           = NULL,
    @FromDate       DATE           = NULL,
    @ToDate         DATE           = NULL,
    @Json           NVARCHAR(MAX)  = NULL,
    @UserId         BIGINT         = NULL,
    @TotalCount     INT            = NULL OUTPUT,
    @NewId          BIGINT         = NULL OUTPUT,
    @ResultCode     VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    IF @Action = 'CLEAR'
    BEGIN
        UPDATE [Attendance].[Records] SET ManualStatus = NULL, ManualMinutes = NULL
        WHERE  RecordId = @Id AND Deleted = 0 AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1;
        RETURN;
    END;

    IF @FilterCompany IS NULL OR [Payroll].[ufn_InCompanyScope](@FilterCompany, @CompanyId, @CompanyIds) = 0
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the company.';
        RETURN;
    END;

    IF @Action = 'MARKS'
    BEGIN
        DECLARE @MFrom DATE = [Attendance].[ufn_MonthFrom](@FilterCompany, @Month), @MTo DATE = [Attendance].[ufn_MonthTo](@FilterCompany, @Month);
        SELECT r.RecordId, r.ManualStatus, r.ManualMinutes
        FROM   [Attendance].[Records] AS r
        WHERE  r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.ManualStatus IS NOT NULL
          AND  r.WorkDate BETWEEN @MFrom AND @MTo;
        RETURN;
    END;

    /* the dates that cannot be marked: a regular payroll generated (Registered or later) or a month posted */
    DECLARE @Locks TABLE (StartDate DATE, EndDate DATE, Reason VARCHAR(10));
    INSERT INTO @Locks
    SELECT pp.StartDate, pp.EndDate, 'PAYROLL'
    FROM   [Payroll].[PayrollRuns] AS pr
    JOIN   [Payroll].[PayrollPeriods] AS pp ON pp.PayrollPeriodId = pr.PayrollPeriodId
    WHERE  pr.Deleted = 0 AND pr.CompanyId = @FilterCompany AND pr.RunType = 'REGULAR'
      AND  pr.Stage NOT IN ('DRAFT', 'CANCELLED')
      AND  pp.StartDate <= ISNULL(@ToDate, '9999-12-31') AND pp.EndDate >= ISNULL(@FromDate, '1900-01-01');
    INSERT INTO @Locks
    SELECT x.F, x.T, 'POSTED'
    FROM  (SELECT DISTINCT [Attendance].[ufn_MonthFrom](@FilterCompany, ps.RunMonth) AS F, [Attendance].[ufn_MonthTo](@FilterCompany, ps.RunMonth) AS T
           FROM   [Attendance].[Postings] AS ps
           JOIN   [Employee].[Employees] AS e ON e.EmployeeId = ps.EmployeeId AND e.CompanyId = @FilterCompany
           WHERE  ps.Deleted = 0) AS x
    WHERE  x.F <= ISNULL(@ToDate, '9999-12-31') AND x.T >= ISNULL(@FromDate, '1900-01-01');

    IF @Action = 'LOCKS'
    BEGIN
        SELECT StartDate, EndDate, Reason FROM @Locks;
        RETURN;
    END;

    IF @Action = 'SAVE'
    BEGIN
        DECLARE @M TABLE (EmployeeId BIGINT, WorkDate DATE, Status VARCHAR(12), Minutes INT, Note NVARCHAR(500));
        INSERT INTO @M
        SELECT j.EmployeeId, j.WorkDate, UPPER(j.Status), CASE WHEN j.Minutes > 0 THEN j.Minutes ELSE NULL END, NULLIF(LTRIM(RTRIM(j.Note)), N'')
        FROM   OPENJSON(ISNULL(@Json, N'[]'))
               WITH (EmployeeId BIGINT '$.employeeId', WorkDate DATE '$.date', Status VARCHAR(12) '$.status',
                     Minutes INT '$.minutes', Note NVARCHAR(500) '$.note') AS j;

        IF NOT EXISTS (SELECT 1 FROM @M)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Nothing to save.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @M WHERE Status NOT IN ('PRESENT', 'ABSENT', 'LATE', 'SHORT', 'LEAVE', 'HOLIDAY', 'EXCUSED') OR WorkDate IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A day has an unknown mark.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @M WHERE Status IN ('LATE', 'SHORT') AND Minutes IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the minutes of each late / short day.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @M m WHERE NOT EXISTS (SELECT 1 FROM [Employee].[Employees] e
                   WHERE e.EmployeeId = m.EmployeeId AND e.CompanyId = @FilterCompany AND e.Deleted = 0))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'An employee is not of this company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @M m JOIN @Locks l ON m.WorkDate BETWEEN l.StartDate AND l.EndDate)
        BEGIN
            SELECT @ResultCode = 'LOCKED', @ResultMessage = N'The payroll of some of these days is already generated - they can no longer be changed.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE r
            SET    ManualStatus = m.Status,
                   ManualMinutes = CASE WHEN m.Status IN ('LATE', 'SHORT') THEN m.Minutes END,
                   IsExcused = CASE WHEN m.Status = 'EXCUSED' THEN 1 ELSE 0 END,
                   Note = ISNULL(m.Note, r.Note),
                   Source = CASE WHEN r.Source = 'GENERATED' THEN 'MANUAL' ELSE r.Source END,
                   EditedBy = @UserId, EditedDate = @Now
            FROM   [Attendance].[Records] AS r
            JOIN   @M AS m ON m.EmployeeId = r.EmployeeId AND m.WorkDate = r.WorkDate
            WHERE  r.Deleted = 0;

            INSERT INTO [Attendance].[Records] (CompanyId, EmployeeId, WorkDate, Source, Status, ManualStatus, ManualMinutes, IsExcused, Note,
                                                EditedBy, EditedDate, CreatedBy)
            SELECT @FilterCompany, m.EmployeeId, m.WorkDate, 'MANUAL', m.Status, m.Status,
                   CASE WHEN m.Status IN ('LATE', 'SHORT') THEN m.Minutes END, CASE WHEN m.Status = 'EXCUSED' THEN 1 ELSE 0 END, m.Note,
                   @UserId, @Now, @UserId
            FROM   @M AS m
            WHERE  NOT EXISTS (SELECT 1 FROM [Attendance].[Records] r WHERE r.EmployeeId = m.EmployeeId AND r.WorkDate = m.WorkDate AND r.Deleted = 0);
        COMMIT TRANSACTION;

        SELECT @TotalCount = COUNT(1) FROM @M;
        SELECT DISTINCT [Attendance].[ufn_MonthOf](@FilterCompany, WorkDate) AS RunMonth FROM @M;
        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'1 day saved.' ELSE CONCAT(@TotalCount, N' days saved.') END;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO
