/* ============================================================================
   146 - Employee Self Service (mobile / installable web app at /ess)
   ----------------------------------------------------------------------------
   What an employee does from their phone, signed in with their own user
   (Security.Users.EmployeeId links the user to the employee):

     * Punch In / Punch Out - only inside the geofence of their work location
       (Employee.WorkLocationId, else every location of their branch) that has
       a latitude / longitude (Organization > Locations). The distance and the
       GPS accuracy are checked HERE, on the server - the phone only reports
       its position. Every attempt, accepted or refused, is logged in
       Attendance.MobilePunches.
     * The month's attendance (Attendance.Records - the same days the device
       import and the Attendance Sheet use).
     * Their profile, read-only.
   Annual leave (balance, history, request) goes through the existing Leave
   procedures (usp_LeaveRequest_Manage, @IsHr = 0 = the employee themself).

   Changes:
     1. Core.Locations.PunchRadiusM      - optional radius per location (NULL = the
                                           app setting SelfService:PunchRadiusMeters, 15 m)
     2. Attendance.Records.Source        - 'MOBILE' allowed
     3. Attendance.MobilePunches         - the log of every punch attempt
     4. Attendance.usp_EssSelfService    - TODAY, LOCATIONS, PUNCH, MONTH, PROFILE
     5. Core.UiLabels                    - Arabic for the self-service screens

   Safe to run more than once.
   ============================================================================ */

SET NOCOUNT ON;
GO

/* ---- 1. Core.Locations.PunchRadiusM ------------------------------------ */
IF COL_LENGTH('Core.Locations', 'PunchRadiusM') IS NULL
BEGIN
    ALTER TABLE [Core].[Locations] ADD PunchRadiusM SMALLINT NULL;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_Locations_PunchRadius')
BEGIN
    ALTER TABLE [Core].[Locations] WITH CHECK
        ADD CONSTRAINT CK_Locations_PunchRadius CHECK (PunchRadiusM IS NULL OR PunchRadiusM BETWEEN 5 AND 1000);
END;
GO

/* ---- 2. Attendance.Records.Source: 'MOBILE' ------------------------------ */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AttRecords_Source'
           AND definition NOT LIKE '%MOBILE%')
BEGIN
    ALTER TABLE [Attendance].[Records] DROP CONSTRAINT CK_AttRecords_Source;
END;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = 'CK_AttRecords_Source')
BEGIN
    ALTER TABLE [Attendance].[Records] WITH CHECK
        ADD CONSTRAINT CK_AttRecords_Source CHECK (Source IN ('IMPORT', 'MANUAL', 'GENERATED', 'MOBILE'));
END;
GO

/* ---- 3. Attendance.MobilePunches ---------------------------------------- */
IF OBJECT_ID(N'[Attendance].[MobilePunches]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[MobilePunches](
        PunchId         BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttMobilePunches PRIMARY KEY,
        EmployeeId      BIGINT          NULL,
        UserId          BIGINT          NULL,
        PunchType       VARCHAR(3)      NOT NULL,          -- IN / OUT
        PunchTime       DATETIME2(0)    NOT NULL,          -- local (Kuwait) time, as the clock in / out
        Latitude        DECIMAL(10,7)   NULL,
        Longitude       DECIMAL(10,7)   NULL,
        AccuracyM       DECIMAL(9,2)    NULL,
        LocationId      INT             NULL,              -- the nearest location of the employee
        DistanceM       DECIMAL(9,2)    NULL,
        RadiusM         SMALLINT        NULL,
        Accepted        BIT             NOT NULL,
        ResultCode      VARCHAR(40)     NULL,
        RecordId        BIGINT          NULL,              -- the Attendance.Records day it set
        IpAddress       NVARCHAR(64)    NULL,
        UserAgent       NVARCHAR(400)   NULL,
        CreatedDate     DATETIME2(0)    NOT NULL CONSTRAINT DF_AttMobilePunches_Created DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT CK_AttMobilePunches_Type CHECK (PunchType IN ('IN', 'OUT'))
    );
    CREATE INDEX IX_AttMobilePunches_Employee ON [Attendance].[MobilePunches](EmployeeId, PunchTime);
END;
GO

/* ---- 4. Attendance.usp_EssSelfService ----------------------------------
     The employee is ALWAYS the one linked to @UserId - never a parameter.

     TODAY       the employee, today's day and the day still open (punched in, not out)
     LOCATIONS   where they may punch: their work location when it has coordinates,
                 else every location of their branch that has them
     PUNCH       @PunchType IN / OUT at @LocalNow from @Latitude / @Longitude (+-@AccuracyM)
                 -> NO_EMPLOYEE, NO_LOCATION, NO_GPS, ACCURACY, OUT_OF_RANGE, ALREADY_IN,
                    NOT_IN, ALREADY_OUT, POSTED; the row of the day on success
     MONTH       the days of the calendar month of @Month
     PROFILE     the employee's own details (read-only)
   -------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Attendance].[usp_EssSelfService]
    @Action          VARCHAR(20),
    @UserId          BIGINT          = NULL,
    @LocalNow        DATETIME2(0)    = NULL,
    @Month           DATE            = NULL,
    @PunchType       VARCHAR(3)      = NULL,
    @Latitude        DECIMAL(10,7)   = NULL,
    @Longitude       DECIMAL(10,7)   = NULL,
    @AccuracyM       DECIMAL(9,2)    = NULL,
    @DefaultRadiusM  INT             = 15,
    @MaxAccuracyM    INT             = 50,
    @IpAddress       NVARCHAR(64)    = NULL,
    @UserAgent       NVARCHAR(400)   = NULL,
    @TotalCount      INT             = NULL OUTPUT,
    @NewId           BIGINT          = NULL OUTPUT,
    @ResultCode      VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage   NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @LocalNow = ISNULL(@LocalNow, DATEADD(HOUR, 3, SYSUTCDATETIME()));
    DECLARE @Today DATE = CAST(@LocalNow AS DATE);

    /* ---- the signed-in user's employee --------------------------------- */
    DECLARE @EmployeeId BIGINT, @eCo INT, @eBranch INT, @eWorkLoc INT;
    SELECT  @EmployeeId = e.EmployeeId, @eCo = e.CompanyId, @eBranch = e.BranchId, @eWorkLoc = e.WorkLocationId
    FROM    [Security].[Users] AS u
    JOIN    [Employee].[Employees] AS e ON e.EmployeeId = u.EmployeeId
    WHERE   u.UserId = @UserId AND u.Deleted = 0 AND u.IsActive = 1
      AND   e.Deleted = 0 AND e.IsDeleted = 0;

    IF @EmployeeId IS NULL
    BEGIN
        SELECT @ResultCode = 'NO_EMPLOYEE', @ResultMessage = N'Your account is not linked to an employee. Contact your HR administrator.';
        IF @Action = 'PUNCH'
            INSERT INTO [Attendance].[MobilePunches] (UserId, PunchType, PunchTime, Latitude, Longitude, AccuracyM, Accepted, ResultCode, IpAddress, UserAgent)
            VALUES (@UserId, CASE WHEN @PunchType = 'OUT' THEN 'OUT' ELSE 'IN' END, @LocalNow, @Latitude, @Longitude, @AccuracyM, 0, @ResultCode, @IpAddress, @UserAgent);
        RETURN;
    END;

    /* ---- where the employee may punch ---------------------------------- */
    DECLARE @Locs TABLE (LocationId INT PRIMARY KEY, LocationName NVARCHAR(150), Latitude DECIMAL(10,7), Longitude DECIMAL(10,7), RadiusM INT);
    INSERT INTO @Locs
    SELECT  l.LocationId, l.LocationName, l.Latitude, l.Longitude, ISNULL(l.PunchRadiusM, @DefaultRadiusM)
    FROM    [Core].[Locations] AS l
    WHERE   l.Deleted = 0 AND l.IsActive = 1 AND l.CompanyId = @eCo
      AND   l.Latitude IS NOT NULL AND l.Longitude IS NOT NULL
      AND   l.LocationId = @eWorkLoc;
    IF NOT EXISTS (SELECT 1 FROM @Locs) AND @eBranch IS NOT NULL
        INSERT INTO @Locs
        SELECT  l.LocationId, l.LocationName, l.Latitude, l.Longitude, ISNULL(l.PunchRadiusM, @DefaultRadiusM)
        FROM    [Core].[Locations] AS l
        WHERE   l.Deleted = 0 AND l.IsActive = 1 AND l.CompanyId = @eCo
          AND   l.Latitude IS NOT NULL AND l.Longitude IS NOT NULL
          AND   l.BranchId = @eBranch;

    /* ======================= TODAY ====================================== */
    IF @Action = 'TODAY'
    BEGIN
        SELECT  e.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName,
                co.CompanyName, br.BranchName,
                @Today AS Today,
                t.RecordId AS TodayRecordId, t.ClockIn AS TodayClockIn, t.ClockOut AS TodayClockOut, t.Status AS TodayStatus,
                o.RecordId AS OpenRecordId, o.WorkDate AS OpenWorkDate, o.ClockIn AS OpenClockIn,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM @Locs) THEN 1 ELSE 0 END AS BIT) AS HasLocation
        FROM    [Employee].[Employees] AS e
        JOIN    [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
        LEFT JOIN [Core].[Branches] AS br ON br.BranchId = e.BranchId
        OUTER APPLY (SELECT TOP (1) r.RecordId, r.ClockIn, r.ClockOut, r.Status
                     FROM [Attendance].[Records] AS r
                     WHERE r.EmployeeId = e.EmployeeId AND r.WorkDate = @Today AND r.Deleted = 0) AS t
        /* a shift still open: punched in (today, or yesterday for a night shift) and not out */
        OUTER APPLY (SELECT TOP (1) r.RecordId, r.WorkDate, r.ClockIn
                     FROM [Attendance].[Records] AS r
                     WHERE r.EmployeeId = e.EmployeeId AND r.Deleted = 0 AND r.ClockIn IS NOT NULL AND r.ClockOut IS NULL
                       AND r.WorkDate IN (@Today, DATEADD(DAY, -1, @Today))
                       AND r.ClockIn >= DATEADD(HOUR, -20, @LocalNow)
                     ORDER BY r.WorkDate DESC) AS o
        WHERE   e.EmployeeId = @EmployeeId;
        RETURN;
    END;

    /* ======================= LOCATIONS ================================== */
    IF @Action = 'LOCATIONS'
    BEGIN
        SELECT LocationId, LocationName, Latitude, Longitude, RadiusM FROM @Locs ORDER BY LocationName;
        RETURN;
    END;

    /* ======================= PUNCH ====================================== */
    IF @Action = 'PUNCH'
    BEGIN
        SET @PunchType = CASE WHEN UPPER(@PunchType) = 'OUT' THEN 'OUT' ELSE 'IN' END;
        DECLARE @LocId INT, @Dist FLOAT, @Radius INT, @RecId BIGINT, @WorkDate DATE;

        IF @Latitude IS NOT NULL AND @Longitude IS NOT NULL
           AND @Latitude BETWEEN -90 AND 90 AND @Longitude BETWEEN -180 AND 180
        BEGIN
            /* the nearest location (haversine, metres) */
            SELECT TOP (1) @LocId = x.LocationId, @Dist = x.Dist, @Radius = x.RadiusM
            FROM (
                SELECT  l.LocationId, l.RadiusM,
                        6371000.0 * 2 * ASIN(SQRT(
                            POWER(SIN(RADIANS(CAST(l.Latitude AS FLOAT) - CAST(@Latitude AS FLOAT)) / 2), 2)
                          + COS(RADIANS(CAST(@Latitude AS FLOAT))) * COS(RADIANS(CAST(l.Latitude AS FLOAT)))
                          * POWER(SIN(RADIANS(CAST(l.Longitude AS FLOAT) - CAST(@Longitude AS FLOAT)) / 2), 2))) AS Dist
                FROM    @Locs AS l
            ) AS x
            ORDER BY x.Dist;
        END;

        IF NOT EXISTS (SELECT 1 FROM @Locs)
            SELECT @ResultCode = 'NO_LOCATION', @ResultMessage = N'Mobile punch is not set up for your branch yet. Contact your HR administrator.';
        ELSE IF @Latitude IS NULL OR @Longitude IS NULL OR @LocId IS NULL
            SELECT @ResultCode = 'NO_GPS', @ResultMessage = N'Your location could not be read. Turn on location for this app and try again.';
        ELSE IF @AccuracyM IS NULL OR @AccuracyM > @MaxAccuracyM
            SELECT @ResultCode = 'ACCURACY', @ResultMessage = N'Your GPS signal is too weak. Wait a few seconds, or move near a window, and try again.';
        ELSE IF @Dist > @Radius
            SELECT @ResultCode = 'OUT_OF_RANGE', @ResultMessage = N'You are too far from your branch to punch.';

        IF @ResultCode = 'SUCCESS'
        BEGIN
            BEGIN TRANSACTION;

            IF @PunchType = 'IN'
            BEGIN
                DECLARE @tIn DATETIME2(0);
                SELECT TOP (1) @RecId = RecordId, @tIn = ClockIn
                FROM   [Attendance].[Records] WITH (UPDLOCK, HOLDLOCK)
                WHERE  EmployeeId = @EmployeeId AND WorkDate = @Today AND Deleted = 0;
                SET @WorkDate = @Today;

                IF @tIn IS NOT NULL
                    SELECT @ResultCode = 'ALREADY_IN', @ResultMessage = N'You have already punched in today.';
                ELSE IF EXISTS (SELECT 1 FROM [Attendance].[Postings] p WHERE p.EmployeeId = @EmployeeId AND p.Deleted = 0
                                AND p.RunMonth = DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1))
                    SELECT @ResultCode = 'POSTED', @ResultMessage = N'This month is already closed for attendance. Contact your HR administrator.';
                ELSE IF @RecId IS NOT NULL
                    /* a day worked out before (absent) or added by hand without a time */
                    UPDATE [Attendance].[Records]
                    SET    ClockIn = @LocalNow, PunchCount = 1, Source = 'MOBILE'
                    WHERE  RecordId = @RecId;
                ELSE
                BEGIN
                    INSERT INTO [Attendance].[Records] (CompanyId, EmployeeId, WorkDate, ClockIn, PunchCount, Source, CreatedBy)
                    VALUES (@eCo, @EmployeeId, @Today, @LocalNow, 1, 'MOBILE', @UserId);
                    SET @RecId = SCOPE_IDENTITY();
                END;
            END
            ELSE
            BEGIN
                SELECT TOP (1) @RecId = RecordId, @WorkDate = WorkDate
                FROM   [Attendance].[Records] WITH (UPDLOCK, HOLDLOCK)
                WHERE  EmployeeId = @EmployeeId AND Deleted = 0 AND ClockIn IS NOT NULL AND ClockOut IS NULL
                  AND  WorkDate IN (@Today, DATEADD(DAY, -1, @Today))
                  AND  ClockIn >= DATEADD(HOUR, -20, @LocalNow)
                ORDER BY WorkDate DESC;

                IF @RecId IS NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM [Attendance].[Records] WHERE EmployeeId = @EmployeeId AND WorkDate = @Today
                               AND Deleted = 0 AND ClockOut IS NOT NULL)
                        SELECT @ResultCode = 'ALREADY_OUT', @ResultMessage = N'You have already punched out today.';
                    ELSE
                        SELECT @ResultCode = 'NOT_IN', @ResultMessage = N'Punch in first.';
                END
                ELSE IF EXISTS (SELECT 1 FROM [Attendance].[Postings] p WHERE p.EmployeeId = @EmployeeId AND p.Deleted = 0
                                AND p.RunMonth = DATEFROMPARTS(YEAR(@WorkDate), MONTH(@WorkDate), 1))
                    SELECT @ResultCode = 'POSTED', @ResultMessage = N'This month is already closed for attendance. Contact your HR administrator.';
                ELSE
                    UPDATE [Attendance].[Records]
                    SET    ClockOut = @LocalNow, PunchCount = PunchCount + 1
                    WHERE  RecordId = @RecId;
            END;

            COMMIT TRANSACTION;
        END;

        INSERT INTO [Attendance].[MobilePunches] (EmployeeId, UserId, PunchType, PunchTime, Latitude, Longitude, AccuracyM, LocationId,
                                                  DistanceM, RadiusM, Accepted, ResultCode, RecordId, IpAddress, UserAgent)
        VALUES (@EmployeeId, @UserId, @PunchType, @LocalNow, @Latitude, @Longitude, @AccuracyM, @LocId,
                CAST(@Dist AS DECIMAL(9,2)), @Radius, CASE WHEN @ResultCode = 'SUCCESS' THEN 1 ELSE 0 END, @ResultCode,
                CASE WHEN @ResultCode = 'SUCCESS' THEN @RecId END, @IpAddress, @UserAgent);

        IF @ResultCode = 'SUCCESS'
        BEGIN
            SELECT @NewId = @RecId,
                   @ResultMessage = CASE WHEN @PunchType = 'IN' THEN N'Punched in.' ELSE N'Punched out.' END;
            SELECT  r.RecordId, r.CompanyId, r.EmployeeId, r.WorkDate, r.ClockIn, r.ClockOut,
                    l.LocationName, CAST(@Dist AS DECIMAL(9,2)) AS DistanceM
            FROM    [Attendance].[Records] AS r
            LEFT JOIN @Locs AS l ON l.LocationId = @LocId
            WHERE   r.RecordId = @RecId;
        END
        ELSE IF @ResultCode = 'OUT_OF_RANGE'
            /* the distance goes back to the screen ("240 m away") */
            SELECT CAST(NULL AS BIGINT) AS RecordId, @eCo AS CompanyId, @EmployeeId AS EmployeeId, @Today AS WorkDate,
                   CAST(NULL AS DATETIME2(0)) AS ClockIn, CAST(NULL AS DATETIME2(0)) AS ClockOut,
                   (SELECT LocationName FROM @Locs WHERE LocationId = @LocId) AS LocationName, CAST(@Dist AS DECIMAL(9,2)) AS DistanceM;
        RETURN;
    END;

    /* ======================= MONTH ====================================== */
    IF @Action = 'MONTH'
    BEGIN
        DECLARE @From DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, @Today)), MONTH(ISNULL(@Month, @Today)), 1);
        DECLARE @To DATE = EOMONTH(@From);
        SELECT  r.RecordId, r.WorkDate, r.ClockIn, r.ClockOut, r.Source, r.Status,
                r.WorkedMinutes, r.LateMinutes, r.ShortMinutes, r.IsExcused
        FROM    [Attendance].[Records] AS r
        WHERE   r.EmployeeId = @EmployeeId AND r.Deleted = 0 AND r.WorkDate BETWEEN @From AND @To
        ORDER BY r.WorkDate;
        RETURN;
    END;

    /* ======================= PROFILE ==================================== */
    IF @Action = 'PROFILE'
    BEGIN
        SELECT  e.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.MiddleName, N' ', e.LastName))) AS EmployeeName, e.ArabicName,
                e.Gender, e.DateOfBirth, e.MaritalStatus, nc.CountryName AS NationalityName,
                e.MobileNumber, e.WorkEmail, kc.CivilIdNumber, kc.CivilIdExpiryDate,
                co.CompanyName, br.BranchName, d.DepartmentName, s.SectionName, p.PositionName, dg.DesignationName,
                loc.LocationName, LTRIM(RTRIM(CONCAT(mgr.FirstName, N' ', mgr.LastName))) AS ReportingManagerName,
                e.HireDate, e.ProbationEndDate, e.EmploymentType, e.EmploymentStatus
        FROM    [Employee].[Employees] AS e
        JOIN    [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
        LEFT JOIN [Core].[Branches] AS br ON br.BranchId = e.BranchId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Core].[Sections] AS s ON s.SectionId = e.SectionId
        LEFT JOIN [Core].[Positions] AS p ON p.PositionId = e.PositionId
        LEFT JOIN [Core].[Designations] AS dg ON dg.DesignationId = e.DesignationId
        LEFT JOIN [Core].[Locations] AS loc ON loc.LocationId = e.WorkLocationId
        LEFT JOIN [Core].[Countries] AS nc ON nc.CountryId = e.NationalityCountryId
        LEFT JOIN [Employee].[Employees] AS mgr ON mgr.EmployeeId = e.ReportingManagerId
        LEFT JOIN [Kuwait].[EmployeeCompliance] AS kc ON kc.EmployeeId = e.EmployeeId
        WHERE   e.EmployeeId = @EmployeeId;
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- 5. Labels (English text -> Arabic, read by L.Tr / L["ess.*"]) ------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('ess.app_name', 'ess', N'Self Service', N'الخدمة الذاتية', NULL),
        ('ess.app_desc', 'ess', N'Punch in and out, your attendance, annual leave and profile.', N'تسجيل الحضور والانصراف، وحضورك، وإجازتك السنوية، وملفك الشخصي.', NULL),
        ('ess.signin_title', 'ess', N'Employee sign in', N'تسجيل دخول الموظف', NULL),
        ('ess.signin_sub', 'ess', N'Punch in, check your attendance and apply for annual leave.', N'سجّل حضورك، وتابع حضورك، وقدّم طلب إجازة سنوية.', NULL),
        ('ess.not_linked', 'ess', N'Your account is not linked to an employee. Contact your HR administrator.', N'حسابك غير مرتبط بموظف. تواصل مع مسؤول الموارد البشرية.', NULL),
        ('ess.install_title', 'ess', N'Install on your phone', N'ثبّت التطبيق على هاتفك', NULL),
        ('ess.install_android', 'ess', N'Add the app to your home screen for one-tap access.', N'أضف التطبيق إلى الشاشة الرئيسية للوصول بلمسة واحدة.', NULL),
        ('ess.install_ios', 'ess', N'On iPhone: tap Share, then Add to Home Screen.', N'على iPhone: اضغط مشاركة ثم إضافة إلى الشاشة الرئيسية.', NULL),
        ('ess.install_button', 'ess', N'Add to Home Screen', N'إضافة إلى الشاشة الرئيسية', NULL),
        ('ess.tab_punch', 'ess', N'Punch', N'البصمة', NULL),
        ('ess.tab_attendance', 'ess', N'Attendance', N'الحضور', NULL),
        ('ess.tab_leave', 'ess', N'Leave', N'الإجازة', NULL),
        ('ess.tab_profile', 'ess', N'Profile', N'الملف', NULL),
        ('ess.hello', 'ess', N'Hello', N'مرحباً', NULL),
        ('ess.punch_in', 'ess', N'Punch In', N'تسجيل حضور', NULL),
        ('ess.punch_out', 'ess', N'Punch Out', N'تسجيل انصراف', NULL),
        ('ess.done_today', 'ess', N'Done for today', N'انتهى يومك', NULL),
        ('ess.locating', 'ess', N'Getting your location…', N'جارٍ تحديد موقعك…', NULL),
        ('ess.inside', 'ess', N'At {0} · {1} m away', N'في {0} · على بعد {1} م', NULL),
        ('ess.outside', 'ess', N'{0} m from {1}', N'على بعد {0} م من {1}', NULL),
        ('ess.hint_inside', 'ess', N'You are within range of your branch.', N'أنت ضمن نطاق فرعك.', NULL),
        ('ess.hint_outside', 'ess', N'Move within {0} m of your branch to punch.', N'اقترب إلى {0} م من فرعك لتسجيل البصمة.', NULL),
        ('ess.hint_locating', 'ess', N'Keep this screen open - accuracy improves in a few seconds.', N'أبقِ هذه الشاشة مفتوحة - تتحسن الدقة خلال ثوانٍ.', NULL),
        ('ess.hint_weak', 'ess', N'GPS accuracy is ±{0} m - wait for a stronger signal.', N'دقة الموقع ±{0} م - انتظر إشارة أقوى.', NULL),
        ('ess.gps_denied', 'ess', N'Location is turned off for this app. Allow location in your phone settings to punch.', N'خدمة الموقع متوقفة لهذا التطبيق. اسمح بالموقع من إعدادات الهاتف لتسجيل البصمة.', NULL),
        ('ess.gps_unsupported', 'ess', N'This browser cannot read your location.', N'هذا المتصفح لا يستطيع قراءة موقعك.', NULL),
        ('ess.no_location', 'ess', N'Mobile punch is not set up for your branch yet. Contact your HR administrator.', N'تسجيل البصمة عبر الجوال غير مفعّل لفرعك بعد. تواصل مع مسؤول الموارد البشرية.', NULL),
        ('ess.in', 'ess', N'In', N'دخول', NULL),
        ('ess.out', 'ess', N'Out', N'خروج', NULL),
        ('ess.worked', 'ess', N'Worked', N'مدة العمل', NULL),
        ('ess.this_month', 'ess', N'This month', N'هذا الشهر', NULL),
        ('ess.view_sheet', 'ess', N'View sheet', N'عرض الكشف', NULL),
        ('ess.present', 'ess', N'Present', N'حضور', NULL),
        ('ess.absent', 'ess', N'Absent', N'غياب', NULL),
        ('ess.short', 'ess', N'Short', N'نقص', NULL),
        ('ess.late', 'ess', N'Late', N'تأخير', NULL),
        ('ess.leave', 'ess', N'Leave', N'إجازة', NULL),
        ('ess.attendance_sheet', 'ess', N'Attendance Sheet', N'كشف الحضور', NULL),
        ('ess.daily_log', 'ess', N'Daily log', N'السجل اليومي', NULL),
        ('ess.no_days', 'ess', N'No attendance recorded for this month yet.', N'لا يوجد حضور مسجل لهذا الشهر بعد.', NULL),
        ('ess.date', 'ess', N'Date', N'التاريخ', NULL),
        ('ess.hours', 'ess', N'Hours', N'الساعات', NULL),
        ('ess.status', 'ess', N'Status', N'الحالة', NULL),
        ('ess.annual_leave', 'ess', N'Annual Leave', N'الإجازة السنوية', NULL),
        ('ess.days_left', 'ess', N'days left', N'يوم متبقٍ', NULL),
        ('ess.entitled', 'ess', N'Entitled', N'المستحق', NULL),
        ('ess.taken', 'ess', N'Taken', N'المأخوذ', NULL),
        ('ess.pending', 'ess', N'Pending', N'قيد الموافقة', NULL),
        ('ess.request_leave', 'ess', N'Request leave', N'طلب إجازة', NULL),
        ('ess.leave_history', 'ess', N'Leave history', N'سجل الإجازات', NULL),
        ('ess.no_leave', 'ess', N'No annual leave requests yet.', N'لا توجد طلبات إجازة سنوية بعد.', NULL),
        ('ess.no_annual', 'ess', N'Annual leave is not set up for your company yet.', N'الإجازة السنوية غير معدّة لشركتك بعد.', NULL),
        ('ess.request_title', 'ess', N'Request Annual Leave', N'طلب إجازة سنوية', NULL),
        ('ess.available', 'ess', N'Available balance', N'الرصيد المتاح', NULL),
        ('ess.from', 'ess', N'From', N'من', NULL),
        ('ess.to', 'ess', N'To', N'إلى', NULL),
        ('ess.reason', 'ess', N'Reason (optional)', N'السبب (اختياري)', NULL),
        ('ess.days_requested', 'ess', N'Days requested', N'الأيام المطلوبة', NULL),
        ('ess.balance_after', 'ess', N'Balance after', N'الرصيد بعد الطلب', NULL),
        ('ess.submit', 'ess', N'Submit request', N'إرسال الطلب', NULL),
        ('ess.confirm_unpaid', 'ess', N'Send anyway', N'إرسال على أي حال', NULL),
        ('ess.cancel', 'ess', N'Cancel', N'إلغاء', NULL),
        ('ess.st_pending', 'ess', N'Pending', N'قيد الموافقة', NULL),
        ('ess.st_approved', 'ess', N'Approved', N'موافق عليها', NULL),
        ('ess.st_rejected', 'ess', N'Rejected', N'مرفوضة', NULL),
        ('ess.st_cancelled', 'ess', N'Cancelled', N'ملغاة', NULL),
        ('ess.st_returned', 'ess', N'Returned', N'عاد للعمل', NULL),
        ('ess.readonly_note', 'ess', N'This information is read-only. Contact HR to request a change.', N'هذه المعلومات للعرض فقط. تواصل مع الموارد البشرية لطلب تعديل.', NULL),
        ('ess.personal', 'ess', N'Personal', N'شخصي', NULL),
        ('ess.employment', 'ess', N'Employment', N'الوظيفة', NULL),
        ('ess.employee_no', 'ess', N'Employee No.', N'الرقم الوظيفي', NULL),
        ('ess.civil_id', 'ess', N'Civil ID', N'البطاقة المدنية', NULL),
        ('ess.civil_id_expiry', 'ess', N'Civil ID expiry', N'انتهاء البطاقة المدنية', NULL),
        ('ess.nationality', 'ess', N'Nationality', N'الجنسية', NULL),
        ('ess.dob', 'ess', N'Date of birth', N'تاريخ الميلاد', NULL),
        ('ess.gender', 'ess', N'Gender', N'الجنس', NULL),
        ('ess.marital', 'ess', N'Marital status', N'الحالة الاجتماعية', NULL),
        ('ess.mobile', 'ess', N'Mobile', N'الجوال', NULL),
        ('ess.work_email', 'ess', N'Work email', N'البريد الإلكتروني للعمل', NULL),
        ('ess.company', 'ess', N'Company', N'الشركة', NULL),
        ('ess.branch', 'ess', N'Branch', N'الفرع', NULL),
        ('ess.department', 'ess', N'Department', N'القسم', NULL),
        ('ess.section', 'ess', N'Section', N'الوحدة', NULL),
        ('ess.position', 'ess', N'Position', N'المنصب', NULL),
        ('ess.designation', 'ess', N'Designation', N'المسمى الوظيفي', NULL),
        ('ess.work_location', 'ess', N'Work location', N'موقع العمل', NULL),
        ('ess.manager', 'ess', N'Reporting to', N'المدير المباشر', NULL),
        ('ess.hire_date', 'ess', N'Joining date', N'تاريخ التعيين', NULL),
        ('ess.probation_end', 'ess', N'Probation ends', N'نهاية فترة التجربة', NULL),
        ('ess.employment_type', 'ess', N'Employment type', N'نوع التوظيف', NULL),
        ('ess.sign_out', 'ess', N'Sign out', N'تسجيل الخروج', NULL),
        ('ess.offline', 'ess', N'You are offline. Connect to the internet to punch.', N'أنت غير متصل. اتصل بالإنترنت لتسجيل البصمة.', NULL),
        ('ess.error', 'ess', N'Something went wrong. Please try again.', N'حدث خطأ. حاول مرة أخرى.', NULL),
        ('ess.session_ended', 'ess', N'Your session ended. Please sign in again.', N'انتهت جلستك. سجّل الدخول مرة أخرى.', NULL),
        ('ess.open_desktop', 'ess', N'Open the full HR system', N'فتح نظام الموارد البشرية الكامل', NULL),
        /* messages from the procedures and the controller (translated by L.Tr on the English text) */
        ('ess.dow_0', 'ess', N'Sunday', N'الأحد', NULL),
        ('ess.dow_1', 'ess', N'Monday', N'الاثنين', NULL),
        ('ess.dow_2', 'ess', N'Tuesday', N'الثلاثاء', NULL),
        ('ess.dow_3', 'ess', N'Wednesday', N'الأربعاء', NULL),
        ('ess.dow_4', 'ess', N'Thursday', N'الخميس', NULL),
        ('ess.dow_5', 'ess', N'Friday', N'الجمعة', NULL),
        ('ess.dow_6', 'ess', N'Saturday', N'السبت', NULL),
        ('ess.dow_short_0', 'ess', N'Su', N'ح', NULL),
        ('ess.dow_short_1', 'ess', N'Mo', N'ن', NULL),
        ('ess.dow_short_2', 'ess', N'Tu', N'ث', NULL),
        ('ess.dow_short_3', 'ess', N'We', N'ر', NULL),
        ('ess.dow_short_4', 'ess', N'Th', N'خ', NULL),
        ('ess.dow_short_5', 'ess', N'Fr', N'ج', NULL),
        ('ess.dow_short_6', 'ess', N'Sa', N'س', NULL),
        ('ess.st_excused', 'ess', N'Excused', N'معذور', NULL),
        ('ess.st_holiday', 'ess', N'Holiday', N'عطلة', NULL),
        ('ess.st_off', 'ess', N'Day off', N'راحة', NULL),
        ('ess.st_missing', 'ess', N'One punch', N'بصمة واحدة', NULL),
        ('ess.in_progress', 'ess', N'In progress', N'جارٍ', NULL),
        ('ess.doc_needed', 'ess', N'This leave needs a supporting document. Please apply from the full HR system.', N'تحتاج هذه الإجازة إلى مستند داعم. يرجى التقديم من نظام الموارد البشرية الكامل.', NULL),
        ('ess.m_punched_in', 'ess', N'Punched in.', N'تم تسجيل الحضور.', NULL),
        ('ess.m_punched_out', 'ess', N'Punched out.', N'تم تسجيل الانصراف.', NULL),
        ('ess.m_no_gps', 'ess', N'Your location could not be read. Turn on location for this app and try again.', N'تعذّرت قراءة موقعك. فعّل الموقع لهذا التطبيق وحاول مرة أخرى.', NULL),
        ('ess.m_accuracy', 'ess', N'Your GPS signal is too weak. Wait a few seconds, or move near a window, and try again.', N'إشارة الموقع ضعيفة. انتظر ثوانٍ أو اقترب من نافذة وحاول مرة أخرى.', NULL),
        ('ess.m_out_of_range', 'ess', N'You are too far from your branch to punch.', N'أنت بعيد عن فرعك ولا يمكنك تسجيل البصمة.', NULL),
        ('ess.m_already_in', 'ess', N'You have already punched in today.', N'لقد سجلت حضورك اليوم بالفعل.', NULL),
        ('ess.m_already_out', 'ess', N'You have already punched out today.', N'لقد سجلت انصرافك اليوم بالفعل.', NULL),
        ('ess.m_not_in', 'ess', N'Punch in first.', N'سجّل الحضور أولاً.', NULL),
        ('ess.m_posted', 'ess', N'This month is already closed for attendance. Contact your HR administrator.', N'تم إغلاق حضور هذا الشهر. تواصل مع مسؤول الموارد البشرية.', NULL),
        ('ess.m_leave_sent', 'ess', N'Your leave request has been sent for approval.', N'تم إرسال طلب إجازتك للموافقة.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
GO

PRINT '146_Employee_Self_Service.sql applied.';
GO
