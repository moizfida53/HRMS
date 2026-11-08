/* =====================================================================
   129_Attendance_Sheet_Marks.sql  -  Attendance Sheet: marking days by hand
   ---------------------------------------------------------------------
   Run after db/127. Safe to re-run.

   A right click on a day of the Attendance Sheet marks it Present, Absent,
   Late (minutes), Short (minutes), Leave, Holiday or Excused (a comment).
   The marks are kept on the day (Attendance.Records.ManualStatus /
   ManualMinutes) and win over the clock times when the month is worked
   out again. Days of a payroll already generated (Registered or later,
   regular payroll) or of a month posted from attendance cannot be marked.

   Attendance.usp_AttMark_Manage
     MARKS  the marked days of a company and month (for the calculation)
     LOCKS  the date ranges of a company that cannot be marked
     SAVE   @Json [{employeeId, date, status, minutes, note}] - the months touched
     CLEAR  @Id - a day's mark taken off (its times were corrected in the day form)
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Attendance].[usp_AttSheet]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/127 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF COL_LENGTH(N'[Attendance].[Records]', N'ManualStatus') IS NULL
    ALTER TABLE [Attendance].[Records] ADD ManualStatus VARCHAR(12) NULL
        CONSTRAINT CK_AttRecords_ManualStatus CHECK (ManualStatus IN ('PRESENT', 'ABSENT', 'LATE', 'SHORT', 'LEAVE', 'HOLIDAY', 'EXCUSED'));
GO
IF COL_LENGTH(N'[Attendance].[Records]', N'ManualMinutes') IS NULL
    ALTER TABLE [Attendance].[Records] ADD ManualMinutes INT NULL;
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
        DECLARE @MFrom DATE = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1);
        SELECT r.RecordId, r.ManualStatus, r.ManualMinutes
        FROM   [Attendance].[Records] AS r
        WHERE  r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.ManualStatus IS NOT NULL
          AND  r.WorkDate BETWEEN @MFrom AND EOMONTH(@MFrom);
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
    SELECT DISTINCT ps.RunMonth, EOMONTH(ps.RunMonth), 'POSTED'
    FROM   [Attendance].[Postings] AS ps
    JOIN   [Employee].[Employees] AS e ON e.EmployeeId = ps.EmployeeId AND e.CompanyId = @FilterCompany
    WHERE  ps.Deleted = 0
      AND  ps.RunMonth <= ISNULL(@ToDate, '9999-12-31') AND EOMONTH(ps.RunMonth) >= ISNULL(@FromDate, '1900-01-01');

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
        SELECT DISTINCT DATEFROMPARTS(YEAR(WorkDate), MONTH(WorkDate), 1) AS RunMonth FROM @M;
        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'1 day saved.' ELSE CONCAT(@TotalCount, N' days saved.') END;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- labels ----------------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('att.mk_present', 'att', N'Present', N'حاضر', NULL),
        ('att.mk_absent', 'att', N'Absent', N'غائب', NULL),
        ('att.mk_late', 'att', N'Late…', N'متأخر…', NULL),
        ('att.mk_short', 'att', N'Short hours…', N'نقص ساعات…', NULL),
        ('att.mk_leave', 'att', N'Leave', N'إجازة', NULL),
        ('att.mk_holiday', 'att', N'Holiday', N'عطلة', NULL),
        ('att.mk_excused', 'att', N'Excused…', N'معذور…', NULL),
        ('att.mk_undo', 'att', N'Undo this change', N'تراجع عن هذا التغيير', NULL),
        ('att.mk_open', 'att', N'Open the day…', N'فتح اليوم…', NULL),
        ('att.mk_locked', 'att', N'Payroll generated - locked', N'تم إنشاء الرواتب - مقفل', NULL),
        ('att.mk_late_title', 'att', N'Late', N'تأخير', NULL),
        ('att.mk_short_title', 'att', N'Short hours', N'نقص ساعات', NULL),
        ('att.mk_excused_title', 'att', N'Excused', N'معذور', NULL),
        ('att.mk_late_minutes', 'att', N'Minutes late', N'دقائق التأخير', NULL),
        ('att.mk_short_minutes', 'att', N'Minutes short', N'دقائق النقص', NULL),
        ('att.mk_comment', 'att', N'Comment', N'تعليق', NULL),
        ('att.mk_apply', 'att', N'Apply', N'تطبيق', NULL),
        ('att.mk_cancel', 'att', N'Cancel', N'إلغاء', NULL),
        ('att.mk_save_0', 'att', N'Save changes ({0})', N'حفظ التغييرات ({0})', NULL),
        ('att.mk_discard', 'att', N'Discard', N'تجاهل', NULL),
        ('att.mk_unsaved_title', 'att', N'Save the changes?', N'حفظ التغييرات؟', NULL),
        ('att.mk_unsaved_text', 'att', N'You changed days on the Attendance Sheet. Save them before leaving?', N'لقد غيّرت أياماً في كشف الحضور. هل تحفظها قبل المغادرة؟', NULL),
        ('att.mk_yes_save', 'att', N'Yes, save', N'نعم، احفظ', NULL),
        ('att.mk_no_leave', 'att', N'No, leave', N'لا، غادر', NULL),
        ('att.mk_hint', 'att', N'Right-click a day to mark it.', N'انقر بالزر الأيمن على يوم لتعليمه.', NULL),
        ('att.lg_manual', 'att', N'Marked by hand', N'معلّم يدوياً', NULL),
        ('att.lg_locked', 'att', N'Payroll generated', N'تم إنشاء الرواتب', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO
