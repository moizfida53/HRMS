/* =====================================================================
   136_Attendance_Sheet_Start_Day.sql  -  Attendance Sheet follows the calendar's start day
   ---------------------------------------------------------------------
   Run after db/134. Safe to re-run.

   The Attendance Sheet's range for a payroll month is worked out from the
   start day of the company's monthly payroll calendar (the default one
   first): start 25 -> 25 Sep - 24 Oct for October, start 24 -> 24 Sep -
   23 Oct, start 28 -> 28 Sep - 27 Oct, start 1 -> 1 - 31 Oct. A pay period
   generated before the start day was changed no longer decides it.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[usp_AttMark_Manage]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/129 and db/134 before this script.', 16, 1);
    SET NOEXEC ON;
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
        /* db/136: the range follows the start day of the company's monthly calendar (the default one first):
           start 25 -> 25th of the previous month to 24th of the month; start 1 -> the calendar month. A period
           generated before the start day changed does not decide it any more. No monthly calendar: the
           company's period of the month, else the calendar month. */
        DECLARE @Anchor DATE = (SELECT TOP (1) c.FirstPeriodStartDate FROM [Payroll].[PayrollCalendars] AS c
                                WHERE c.CompanyId = @FilterCompany AND c.Deleted = 0 AND c.IsActive = 1 AND c.PayFrequency = 'MONTHLY'
                                ORDER BY CASE WHEN c.IsDefault = 1 THEN 0 ELSE 1 END, c.PayrollCalendarId);
        IF @Anchor IS NOT NULL
        BEGIN
            DECLARE @Sd INT = DAY(@Anchor);
            IF @Sd > 28 SET @Sd = 28;
            SELECT CASE WHEN @Sd = 1 THEN DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1)
                        ELSE DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@Month), MONTH(@Month), @Sd)) END AS StartDate,
                   CASE WHEN @Sd = 1 THEN EOMONTH(DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1))
                        ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), @Sd - 1) END AS EndDate;
            RETURN;
        END;

        SELECT TOP (1) p.StartDate, p.EndDate
        FROM   [Payroll].[PayrollPeriods] AS p
        LEFT JOIN [Payroll].[PayrollCalendars] AS c ON c.PayrollCalendarId = p.PayrollCalendarId
        WHERE  p.Deleted = 0 AND p.CompanyId = @FilterCompany
          AND  p.PayrollYear = YEAR(@Month) AND p.PayrollMonth = MONTH(@Month)
          AND (c.PayrollCalendarId IS NULL OR (c.Deleted = 0 AND c.IsActive = 1))
        ORDER BY CASE WHEN c.IsDefault = 1 THEN 0 ELSE 1 END, p.StartDate;
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
                           AND ps.RunMonth = DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1)) THEN 1 ELSE 0 END AS BIT) AS IsPosted
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

