/* =====================================================================
   65_Employee_Date_Alerts.sql  -  HRMS: alerts on employee date fields
   ---------------------------------------------------------------------
   Run after 28 and 60. Safe to re-run.

   An administrator sets reminders on a date field of the Employee page
   (the bell next to the field) - e.g. Civil ID Expiry: 2 months before,
   1 week before, on the day. The reminders belong to the FIELD, so they
   apply to that date of every employee. Once an employee's date reaches
   a reminder it is listed under "HR actions required" on the Dashboard.

     1. Employee.DateFieldAlerts - the reminders (field, unit, value).
     2. Employee.usp_DateAlert_Manage
          LIST  every reminder
          SAVE  replace one field's reminders (@Rules = 'M2,W1,D0')
          DUE   the live employees' dates that have reached a reminder:
                - an expiry (Civil ID, passport, ...) stays due once it has
                  passed, until the date is renewed;
                - probation end / termination drop off after the day;
                - date of birth / hire date recur every year (the next
                  birthday / work anniversary).
     3. Permission EMPLOYEE_DATE_ALERTS (System Administrator).
     4. Labels (English + Arabic).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------
   1. Employee.DateFieldAlerts
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Employee].[DateFieldAlerts]', N'U') IS NULL
BEGIN
    CREATE TABLE [Employee].[DateFieldAlerts](
        AlertId      INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_DateFieldAlerts PRIMARY KEY,
        FieldKey     VARCHAR(50)  NOT NULL,
        UnitCode     CHAR(1)      NOT NULL CONSTRAINT CK_DateFieldAlerts_Unit CHECK (UnitCode IN ('M', 'W', 'D')),
        Value        INT          NOT NULL CONSTRAINT CK_DateFieldAlerts_Value CHECK (Value BETWEEN 0 AND 99),
        CreatedBy    BIGINT       NULL,
        CreatedDate  DATETIME2(0) NOT NULL CONSTRAINT DF_DateFieldAlerts_CreatedDate DEFAULT (SYSUTCDATETIME()),
        CONSTRAINT UQ_DateFieldAlerts UNIQUE (FieldKey, UnitCode, Value)
    );
    PRINT N'Created [Employee].[DateFieldAlerts].';
END
GO

/* ------------------------------------------------------------------
   2. Employee.usp_DateAlert_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Employee].[usp_DateAlert_Manage]
    @Action            VARCHAR(10),
    @FieldKey          VARCHAR(50)     = NULL,
    @Rules             VARCHAR(400)    = NULL,     -- SAVE: 'M2,W1,D0' (unit + value), '' = no alerts
    @CompanyId         INT             = NULL,     -- DUE: a user tied to one company
    @CompanyIds        NVARCHAR(2000)  = NULL,     -- DUE: top-bar company filter, NULL = all
    @UserId            BIGINT          = NULL,

    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0;

    /* the date fields that take alerts - keep in step with DateAlertFields (HRMS.Domain) */
    DECLARE @Fields TABLE (FieldKey VARCHAR(50) PRIMARY KEY, Kind CHAR(1));   -- X expiry, E event, A annual
    INSERT INTO @Fields VALUES
        ('DateOfBirth', 'A'), ('HireDate', 'A'), ('ProbationEndDate', 'E'), ('TerminationDate', 'E'),
        ('CivilIdExpiryDate', 'X'), ('PassportExpiryDate', 'X'), ('ResidencyExpiryDate', 'X'),
        ('WorkPermitExpiryDate', 'X'), ('DrivingLicenseExpiryDate', 'X'), ('HealthCertificateExpiry', 'X');

    IF @Action = 'LIST'
    BEGIN
        SELECT   FieldKey, UnitCode, Value
        FROM     [Employee].[DateFieldAlerts]
        ORDER BY FieldKey, CASE UnitCode WHEN 'M' THEN 1 WHEN 'W' THEN 2 ELSE 3 END, Value DESC;
        RETURN;
    END;

    IF @Action = 'SAVE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Fields WHERE FieldKey = @FieldKey)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'This date field does not take alerts.';
            RETURN;
        END;

        /* read 'M2,W1,D0' */
        DECLARE @New TABLE (UnitCode CHAR(1), Value INT, PRIMARY KEY (UnitCode, Value));
        DECLARE @Rest VARCHAR(410) = ISNULL(@Rules, '') + ',', @At INT, @Token VARCHAR(20), @Unit CHAR(1), @Val INT;
        WHILE CHARINDEX(',', @Rest) > 0
        BEGIN
            SET @At    = CHARINDEX(',', @Rest);
            SET @Token = LTRIM(RTRIM(LEFT(@Rest, @At - 1)));
            SET @Rest  = STUFF(@Rest, 1, @At, '');
            IF @Token = '' CONTINUE;

            SET @Unit = UPPER(LEFT(@Token, 1));
            SET @Val  = TRY_CAST(SUBSTRING(@Token, 2, 10) AS INT);
            IF @Unit NOT IN ('M', 'W', 'D') OR @Val IS NULL OR @Val NOT BETWEEN 0 AND 99
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Each alert needs a number from 0 to 99 and months, weeks or days.';
                RETURN;
            END;
            IF @Val = 0 SET @Unit = 'D';   -- "on the day" is the same in any unit
            IF NOT EXISTS (SELECT 1 FROM @New WHERE UnitCode = @Unit AND Value = @Val)
                INSERT INTO @New (UnitCode, Value) VALUES (@Unit, @Val);
        END;

        IF (SELECT COUNT(1) FROM @New) > 10
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A date field can have up to 10 alerts.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            DELETE FROM [Employee].[DateFieldAlerts] WHERE FieldKey = @FieldKey;
            INSERT INTO [Employee].[DateFieldAlerts] (FieldKey, UnitCode, Value, CreatedBy)
            SELECT @FieldKey, UnitCode, Value, @UserId FROM @New;
        COMMIT;

        SELECT @NewId = (SELECT COUNT(1) FROM @New),
               @ResultMessage = CASE WHEN EXISTS (SELECT 1 FROM @New) THEN N'Alerts saved.' ELSE N'Alerts removed.' END;
        RETURN;
    END;

    IF @Action = 'DUE'
    BEGIN
        DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
        DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';

        /* each live employee's dates, one row per field */
        ;WITH live AS (
            SELECT  e.EmployeeId, e.EmployeeCode, CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')) AS EmployeeName,
                    co.CompanyName, e.DateOfBirth, e.HireDate, e.ProbationEndDate, e.TerminationDate
            FROM        [Employee].[Employees] AS e
            LEFT JOIN   [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
            WHERE   e.IsDeleted = 0 AND e.Deleted = 0
              AND   e.EmploymentStatus NOT IN (N'Terminated', N'Resigned')
              AND   (e.TerminationDate IS NULL OR e.TerminationDate >= @Today)
              AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
              AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
        ),
        dates AS (
            SELECT l.EmployeeId, v.FieldKey, v.FieldDate
            FROM   live AS l
            LEFT JOIN [Kuwait].[EmployeeCompliance] AS c ON c.EmployeeId = l.EmployeeId
            CROSS APPLY (VALUES
                ('DateOfBirth',              l.DateOfBirth),
                ('HireDate',                 l.HireDate),
                ('ProbationEndDate',         l.ProbationEndDate),
                ('TerminationDate',          l.TerminationDate),
                ('CivilIdExpiryDate',        c.CivilIdExpiryDate),
                ('PassportExpiryDate',       c.PassportExpiryDate),
                ('ResidencyExpiryDate',      c.ResidencyExpiryDate),
                ('WorkPermitExpiryDate',     c.WorkPermitExpiryDate),
                ('DrivingLicenseExpiryDate', c.DrivingLicenseExpiryDate),
                ('HealthCertificateExpiry',  c.HealthCertificateExpiry)) AS v (FieldKey, FieldDate)
            WHERE  v.FieldDate IS NOT NULL
              AND  EXISTS (SELECT 1 FROM [Employee].[DateFieldAlerts] r WHERE r.FieldKey = v.FieldKey)
        ),
        due AS (
            SELECT  d.EmployeeId, d.FieldKey, d.FieldDate, f.Kind,
                    /* a yearly field: its next birthday / anniversary (a future hire date is just that date) */
                    CASE WHEN f.Kind = 'A' AND d.FieldDate < @Today
                         THEN CASE WHEN DATEADD(YEAR, DATEDIFF(YEAR, d.FieldDate, @Today), d.FieldDate) >= @Today
                                   THEN DATEADD(YEAR, DATEDIFF(YEAR, d.FieldDate, @Today), d.FieldDate)
                                   ELSE DATEADD(YEAR, DATEDIFF(YEAR, d.FieldDate, @Today) + 1, d.FieldDate) END
                         ELSE d.FieldDate END AS DueDate
            FROM    dates AS d
            JOIN    @Fields AS f ON f.FieldKey = d.FieldKey
        )
        SELECT TOP (300)
                l.EmployeeId, l.EmployeeCode, l.EmployeeName, l.CompanyName,
                u.FieldKey, u.FieldDate, u.DueDate,
                DATEDIFF(DAY, @Today, u.DueDate) AS DaysLeft,
                hit.UnitCode AS RuleUnit, hit.Value AS RuleValue
        FROM    due AS u
        JOIN    live AS l ON l.EmployeeId = u.EmployeeId
        /* the reminder that fired most recently (the one closest to the date) */
        CROSS APPLY (
            SELECT TOP (1) r.UnitCode, r.Value
            FROM   [Employee].[DateFieldAlerts] AS r
            CROSS APPLY (SELECT CASE r.UnitCode WHEN 'M' THEN DATEADD(MONTH, -r.Value, u.DueDate)
                                                WHEN 'W' THEN DATEADD(WEEK,  -r.Value, u.DueDate)
                                                ELSE          DATEADD(DAY,   -r.Value, u.DueDate) END AS FiresOn) AS fire
            WHERE  r.FieldKey = u.FieldKey AND fire.FiresOn <= @Today
            ORDER BY fire.FiresOn DESC
        ) AS hit
        WHERE   u.DueDate >= @Today OR u.Kind = 'X'   -- only an expiry stays due once it has passed
        ORDER BY DATEDIFF(DAY, @Today, u.DueDate), l.EmployeeName, u.FieldKey;
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ------------------------------------------------------------------
   3. Permission (System Administrator only, the first time)
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('EMPLOYEE_DATE_ALERTS', 'Employee', 'DateAlerts');

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] r
JOIN   [Security].[Permissions] p ON p.Deleted = 0
JOIN   #Codes c ON c.PermissionCode = p.PermissionCode AND c.IsNew = 1
WHERE  r.RoleCode = N'SYSADMIN' AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);

-- PRINT takes no subquery: count into a variable first
DECLARE @CodesCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Permission codes created: ', @CodesCreated);
DROP TABLE #Codes;
GO

/* ------------------------------------------------------------------
   4. Labels (English + Arabic) - new keys only
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('emp.date_alerts', 'emp', N'Date alerts', N'تنبيهات التاريخ', NULL),
        ('emp.date_alerts_for', 'emp', N'Alerts for {0}', N'تنبيهات {0}', NULL),
        ('emp.date_alerts_scope', 'emp', N'These alerts apply to this date of every employee. When an employee''s date reaches an alert, it is listed under HR actions required on the Dashboard.', N'تنطبق هذه التنبيهات على هذا التاريخ لجميع الموظفين. عندما يصل تاريخ موظف إلى أحد التنبيهات، يظهر ضمن إجراءات الموارد البشرية المطلوبة في لوحة المعلومات.', NULL),
        ('emp.date_alerts_quick_add', 'emp', N'Quick add', N'إضافة سريعة', NULL),
        ('emp.date_alerts_list', 'emp', N'Alerts', N'التنبيهات', NULL),
        ('emp.date_alerts_none', 'emp', N'No alerts yet - pick a quick option above or add your own.', N'لا توجد تنبيهات بعد - اختر خياراً سريعاً أعلاه أو أضف تنبيهاً خاصاً.', NULL),
        ('emp.date_alerts_add', 'emp', N'Add alert', N'إضافة تنبيه', NULL),
        ('emp.date_alerts_value', 'emp', N'How many', N'العدد', NULL),
        ('emp.date_alerts_unit', 'emp', N'Months, weeks or days', N'أشهر أو أسابيع أو أيام', NULL),
        ('emp.date_alerts_months', 'emp', N'Months', N'أشهر', NULL),
        ('emp.date_alerts_weeks', 'emp', N'Weeks', N'أسابيع', NULL),
        ('emp.date_alerts_days', 'emp', N'Days', N'أيام', NULL),
        ('emp.date_alerts_remove', 'emp', N'Remove alert', N'حذف التنبيه', NULL),
        ('emp.date_alerts_save', 'emp', N'Save alerts', N'حفظ التنبيهات', NULL),
        ('js.alert_1_month', 'js', N'1 month', N'شهر واحد', NULL),
        ('js.alert_1_week', 'js', N'1 week', N'أسبوع واحد', NULL),
        ('js.alert_1_day', 'js', N'1 day', N'يوم واحد', NULL),
        ('js.alert_n_months', 'js', N'{0} months', N'{0} أشهر', NULL),
        ('js.alert_n_weeks', 'js', N'{0} weeks', N'{0} أسابيع', NULL),
        ('js.alert_n_days', 'js', N'{0} days', N'{0} أيام', NULL),
        ('js.alert_on_the_day', 'js', N'On the day', N'في نفس اليوم', NULL),
        ('js.alert_before', 'js', N'{0} before', N'قبل {0}', NULL),
        ('js.alert_before_word', 'js', N'before', N'قبل التاريخ', NULL),
        ('js.alert_none_set', 'js', N'{0}: no alerts set', N'{0}: لا توجد تنبيهات', NULL),
        ('js.alert_value_invalid', 'js', N'Enter a whole number from 0 to 99 for each alert.', N'أدخل رقماً صحيحاً من 0 إلى 99 لكل تنبيه.', NULL),
        ('dash.date_alerts', 'dash', N'Date alerts', N'تنبيهات التواريخ', NULL),
        ('dash.date_alerts_none', 'dash', N'No employee date has reached an alert.', N'لم يصل أي تاريخ لموظف إلى تنبيه.', NULL),
        ('dash.alert_overdue_days', 'dash', N'Expired {0} days ago', N'انتهى منذ {0} يوم', NULL),
        ('dash.alert_overdue_yesterday', 'dash', N'Expired yesterday', N'انتهى أمس', NULL),
        ('dash.alert_today', 'dash', N'Today', N'اليوم', NULL),
        ('dash.alert_tomorrow', 'dash', N'Tomorrow', N'غداً', NULL),
        ('dash.alert_in_days', 'dash', N'In {0} days', N'خلال {0} يوم', NULL),
        ('dash.alert_rule_on_the_day', 'dash', N'On the day', N'في نفس اليوم', NULL),
        ('dash.alert_rule_1_month', 'dash', N'1 month before', N'قبل شهر', NULL),
        ('dash.alert_rule_1_week', 'dash', N'1 week before', N'قبل أسبوع', NULL),
        ('dash.alert_rule_1_day', 'dash', N'1 day before', N'قبل يوم', NULL),
        ('dash.alert_rule_months', 'dash', N'{0} months before', N'قبل {0} أشهر', NULL),
        ('dash.alert_rule_weeks', 'dash', N'{0} weeks before', N'قبل {0} أسابيع', NULL),
        ('dash.alert_rule_days', 'dash', N'{0} days before', N'قبل {0} أيام', NULL),
        ('dash.alert_rule_hint', 'dash', N'The alert that was reached', N'التنبيه الذي تم الوصول إليه', NULL),
        ('dash.alert_view', 'dash', N'View', N'عرض', NULL),
        ('dash.alert_view_named', 'dash', N'View {0} - {1}', N'عرض {0} - {1}', NULL),
        ('dash.alert_show_all', 'dash', N'Show all ({0})', N'عرض الكل ({0})', NULL),
        ('dash.alert_show_less', 'dash', N'Show fewer', N'عرض أقل', NULL),
        ('dash.alert_open_profile', 'dash', N'Open the full profile', N'فتح الملف الكامل', NULL),
        ('sec.fn_date_alerts', 'sec', N'Date alerts', N'تنبيهات التواريخ', NULL),
        ('sec.fn_date_alerts_hint', 'sec', N'The bell next to each date field: set its alerts for every employee', N'الجرس بجانب كل حقل تاريخ: ضبط تنبيهاته لجميع الموظفين', NULL),
        ('msg.date_alerts_saved', 'msg', N'Alerts saved.', N'تم حفظ التنبيهات.', N'Alerts saved.'),
        ('msg.date_alerts_removed', 'msg', N'Alerts removed.', N'تمت إزالة التنبيهات.', N'Alerts removed.'),
        ('msg.date_alerts_bad_field', 'msg', N'This date field does not take alerts.', N'حقل التاريخ هذا لا يقبل التنبيهات.', N'This date field does not take alerts.'),
        ('msg.date_alerts_bad_value', 'msg', N'Each alert needs a number from 0 to 99 and months, weeks or days.', N'يحتاج كل تنبيه إلى رقم من 0 إلى 99 وأشهر أو أسابيع أو أيام.', N'Each alert needs a number from 0 to 99 and months, weeks or days.'),
        ('msg.date_alerts_max', 'msg', N'A date field can have up to 10 alerts.', N'يمكن أن يحتوي حقل التاريخ على 10 تنبيهات كحد أقصى.', N'A date field can have up to 10 alerts.')
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Date alert labels inserted: ', @LabelsInserted);
GO
