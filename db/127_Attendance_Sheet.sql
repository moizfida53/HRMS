/* =====================================================================
   127_Attendance_Sheet.sql  -  Time & Attendance > Attendance Sheet
   ---------------------------------------------------------------------
   Run after db/126. Safe to re-run.

   The Attendance Sheet shows a company's employees down the left and the
   days of a range across: a tick for present, a cross for absent, L for
   late (with the minutes), S for short hours, LV leave, H holiday ... and
   each employee's totals. The range is the payroll period of the month
   chosen (Payroll.PayrollPeriods of the company), or a From / To of its own.

   Attendance.usp_AttSheet
     PERIOD     the payroll period of a company and month (@Month)
     EMPLOYEES  the company's employees working in the range (with a pattern
                or a day recorded)
     DAYS       the days recorded in the range
     HOLIDAYS   public holidays in the range
     LEAVE      approved leave in the range
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[Records]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/126 before this script.', 16, 1);
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
        /* the company's payroll period of the month - a monthly calendar first */
        SELECT TOP (1) p.StartDate, p.EndDate
        FROM   [Payroll].[PayrollPeriods] AS p
        LEFT JOIN [Payroll].[PayrollCalendars] AS c ON c.PayrollCalendarId = p.PayrollCalendarId
        WHERE  p.Deleted = 0 AND p.CompanyId = @FilterCompany
          AND  p.PayrollYear = YEAR(@Month) AND p.PayrollMonth = MONTH(@Month)
          AND (c.PayrollCalendarId IS NULL OR (c.Deleted = 0 AND c.IsActive = 1))
        ORDER BY CASE WHEN c.PayFrequency = 'MONTHLY' THEN 0 ELSE 1 END, p.StartDate;
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
                r.ShortMinutes, r.OvertimeMinutes, r.DeductionAmount, r.OvertimeAmount, r.DeductionNote, r.IsExcused, r.Note,
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
        ('att.nav_sheet', 'att', N'Attendance Sheet', N'كشف الحضور', NULL),
        ('att.sheet_subtitle', 'att', N'Every employee''s days at a glance - present, absent, late, leave and holidays.', N'أيام كل موظف بنظرة واحدة - حضور وغياب وتأخير وإجازات وعطلات.', NULL),
        ('att.payroll_month', 'att', N'Payroll month', N'شهر الرواتب', NULL),
        ('att.date_from', 'att', N'From', N'من', NULL),
        ('att.date_to', 'att', N'To', N'إلى', NULL),
        ('att.show', 'att', N'Show', N'عرض', NULL),
        ('att.range_period_0_1', 'att', N'Payroll period {0} – {1}', N'فترة الرواتب {0} – {1}', NULL),
        ('att.range_custom', 'att', N'Custom range', N'فترة مخصصة', NULL),
        ('att.range_too_long', 'att', N'The range is limited to 62 days - the first 62 are shown.', N'الفترة محدودة بـ 62 يوماً - تُعرض أول 62 يوماً.', NULL),
        ('att.legend', 'att', N'Legend', N'المفتاح', NULL),
        ('att.lg_present', 'att', N'Present', N'حاضر', NULL),
        ('att.lg_absent', 'att', N'Absent', N'غائب', NULL),
        ('att.lg_late', 'att', N'Late (minutes)', N'متأخر (دقائق)', NULL),
        ('att.lg_short', 'att', N'Short hours', N'نقص ساعات', NULL),
        ('att.lg_missing', 'att', N'One punch', N'بصمة واحدة', NULL),
        ('att.lg_leave', 'att', N'Leave', N'إجازة', NULL),
        ('att.lg_holiday', 'att', N'Holiday', N'عطلة', NULL),
        ('att.lg_off', 'att', N'Day off', N'راحة', NULL),
        ('att.lg_excused', 'att', N'Excused', N'معذور', NULL),
        ('att.lg_none', 'att', N'No record', N'لا سجل', NULL),
        ('att.t_present', 'att', N'P', N'ح', NULL),
        ('att.t_late', 'att', N'L', N'ت', NULL),
        ('att.t_absent', 'att', N'A', N'غ', NULL),
        ('att.t_leave', 'att', N'LV', N'إج', NULL),
        ('att.t_present_hint', 'att', N'Days present (late and short included)', N'أيام الحضور (مع التأخير والنقص)', NULL),
        ('att.t_late_hint', 'att', N'Days late', N'أيام التأخير', NULL),
        ('att.t_absent_hint', 'att', N'Days absent', N'أيام الغياب', NULL),
        ('att.t_leave_hint', 'att', N'Days on leave', N'أيام الإجازة', NULL),
        ('att.t_ded', 'att', N'Deduction', N'الخصم', NULL),
        ('att.sheet_empty', 'att', N'No employee to show', N'لا يوجد موظف للعرض', NULL),
        ('att.sheet_empty_text', 'att', N'Assign attendance patterns to the employees or import the device report for this range.', N'عيّن أنماط الحضور للموظفين أو استورد تقرير الجهاز لهذه الفترة.', NULL),
        ('att.cell_hint', 'att', N'Click a day to change it, or an empty day to add it.', N'انقر يوماً لتعديله أو يوماً فارغاً لإضافته.', NULL),
        ('att.day_totals', 'att', N'Present per day', N'الحضور لكل يوم', NULL),
        ('att.print', 'att', N'Print', N'طباعة', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
