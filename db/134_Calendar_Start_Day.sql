/* =====================================================================
   134_Calendar_Start_Day.sql  -  Payroll Calendar start day, Pay Periods view only
   ---------------------------------------------------------------------
   Run after db/129. Safe to re-run.

   - Payroll Calendar (monthly): the form asks the day each period starts
     (1 - 28) and the first payroll month, and shows where the period ends
     (start 25 -> 25th to 24th of the next month). The first period's start
     (FirstPeriodStartDate) is worked out from them.
   - Pay Periods is for viewing: the periods are generated from the
     calendar when a payroll is created (Create Payroll > Next).
   - Attendance Sheet: with no period generated for the month yet, the
     range follows the company's monthly calendar start day (not the
     calendar month).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[usp_AttMark_Manage]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/129 before this script.', 16, 1);
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
        /* the company's payroll period of the month (the default monthly calendar first); none generated yet
           (periods are made when a payroll is created): worked out from that calendar's start day - start 25
           gives 25th of the previous month to 24th of the month, start 1 the calendar month */
        IF EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] AS p
                   WHERE p.Deleted = 0 AND p.CompanyId = @FilterCompany AND p.PayrollYear = YEAR(@Month) AND p.PayrollMonth = MONTH(@Month))
        BEGIN
            SELECT TOP (1) p.StartDate, p.EndDate
            FROM   [Payroll].[PayrollPeriods] AS p
            LEFT JOIN [Payroll].[PayrollCalendars] AS c ON c.PayrollCalendarId = p.PayrollCalendarId
            WHERE  p.Deleted = 0 AND p.CompanyId = @FilterCompany
              AND  p.PayrollYear = YEAR(@Month) AND p.PayrollMonth = MONTH(@Month)
              AND (c.PayrollCalendarId IS NULL OR (c.Deleted = 0 AND c.IsActive = 1))
            ORDER BY CASE WHEN c.PayFrequency = 'MONTHLY' THEN 0 ELSE 1 END, CASE WHEN c.IsDefault = 1 THEN 0 ELSE 1 END, p.StartDate;
            RETURN;
        END;

        DECLARE @Anchor DATE = (SELECT TOP (1) c.FirstPeriodStartDate FROM [Payroll].[PayrollCalendars] AS c
                                WHERE c.CompanyId = @FilterCompany AND c.Deleted = 0 AND c.IsActive = 1 AND c.PayFrequency = 'MONTHLY'
                                ORDER BY CASE WHEN c.IsDefault = 1 THEN 0 ELSE 1 END, c.PayrollCalendarId);
        IF @Anchor IS NULL RETURN;      /* no monthly calendar: the calendar month */
        DECLARE @Sd INT = DAY(@Anchor);
        IF @Sd > 28 SET @Sd = 28;
        SELECT CASE WHEN @Sd = 1 THEN DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1)
                    ELSE DATEADD(MONTH, -1, DATEFROMPARTS(YEAR(@Month), MONTH(@Month), @Sd)) END AS StartDate,
               CASE WHEN @Sd = 1 THEN EOMONTH(DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1))
                    ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), @Sd - 1) END AS EndDate;
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

/* ---- labels ----------------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.cal_start_day', 'pr', N'Period starts on day', N'تبدأ الفترة في اليوم', NULL),
        ('pr.cal_first_month', 'pr', N'First payroll month', N'أول شهر رواتب', NULL),
        ('pr.cal_span_month', 'pr', N'Each period is the calendar month - from the 1st to the last day of the month.', N'كل فترة هي الشهر الميلادي - من اليوم 1 إلى آخر يوم في الشهر.', NULL),
        ('pr.cal_span_0_1', 'pr', N'Each period runs from day {0} of a month to day {1} of the next month - the payroll month is the one it ends in.', N'كل فترة من اليوم {0} من الشهر إلى اليوم {1} من الشهر التالي - شهر الرواتب هو الشهر الذي تنتهي فيه.', NULL),
        ('pr.cal_span_first_0_1_2', 'pr', N'First period - {0}: {1} to {2}', N'أول فترة - {0}: من {1} إلى {2}', NULL),
        ('pr.cal_weekly_start_hint', 'pr', N'The date the first week / fortnight starts - the next ones follow every 7 / 14 days.', N'تاريخ بدء أول أسبوع / أسبوعين - تتبعها الفترات كل 7 / 14 يوماً.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

/* Pay Periods: generated with the payroll now */
UPDATE [Core].[UiLabels]
SET    EnglishText = N'The pay periods are made from the payroll calendar when a payroll is created - none for this year yet.',
       ArabicText  = N'تُنشأ فترات الدفع من تقويم الرواتب عند إنشاء مسير رواتب - لا توجد فترات لهذا العام بعد.'
WHERE  LabelKey = 'pr.use_generate_periods_to_create_the_pay_periods_of_this_y' AND Deleted = 0;
UPDATE [Core].[UiLabels]
SET    EnglishText = N'Periods are made from the payroll calendar when a payroll is created.',
       ArabicText  = N'تُنشأ الفترات من تقويم الرواتب عند إنشاء مسير رواتب.'
WHERE  LabelKey = 'pr.periods_are_generated_per_calendar_and_year' AND Deleted = 0;
GO
