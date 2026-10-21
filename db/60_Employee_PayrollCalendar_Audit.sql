/* =====================================================================
   60_Employee_PayrollCalendar_Audit.sql  -  HRMS: each employee's payroll
   calendar, and the employee Audit Report
   ---------------------------------------------------------------------
   Run after 01-59, THEN re-run 35_Payroll_Processing_StoredProcedures1.sql
   (the payroll engine now pays each employee by their own calendar).
   Safe to re-run.

     1. Employee.Employees.PayrollCalendarId - the payroll calendar an
        employee is paid by (positions / policies differ inside a company,
        so the calendar is per employee, not per company)
     2. Employee.EmployeeAuditLog - one row per audited transaction of an
        employee (who, when, old -> new value)
     3. Employee.usp_EmployeeAudit_Manage
          ADD     write one audit row (the application logs employee
                  create / update / activate / delete, salary and bank
                  changes, payroll exclusion and inclusion)
          LIST    the Audit Report: company, employee, transaction type
                  and date filters, search, paging
     4. Employee.usp_EmployeePayrollCalendar_Manage
          GET     the employee's calendar
          SET     assign / change it (same company, active calendar) and
                  write CALENDAR_ASSIGNED / CALENDAR_CHANGED in one
                  transaction. WHO may change an assigned calendar is
                  checked by the application (EMPLOYEE_PAYROLL_CALENDAR_CHANGE)
          COUNTS  per calendar of a company: how many current employees
                  it pays (NULL = not assigned yet) - Create Payroll
     5. Permissions EMPLOYEE_PAYROLL_CALENDAR_CHANGE ("only the admin can
        change a calendar once assigned") and AUDIT_REPORT_VIEW, granted
        to System Administrator only; grant them to other roles on
        Security > Create Roles
     6. ONE-TIME: employees without a calendar get their company's default
        calendar (or its only active one), logged as CALENDAR_ASSIGNED
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[PayrollCalendars]', N'U') IS NULL OR OBJECT_ID(N'[Employee].[Employees]', N'U') IS NULL
    RAISERROR(N'Run db/29 (payroll calendars) and the employee scripts first.', 16, 1);
GO

/* ------------------------------------------------------------------
   1. Employee.Employees.PayrollCalendarId
   ------------------------------------------------------------------ */
IF COL_LENGTH('Employee.Employees', 'PayrollCalendarId') IS NULL
    ALTER TABLE [Employee].[Employees] ADD [PayrollCalendarId] INT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_Employees_PayrollCalendar')
    ALTER TABLE [Employee].[Employees] WITH CHECK
        ADD CONSTRAINT [FK_Employees_PayrollCalendar] FOREIGN KEY ([PayrollCalendarId])
            REFERENCES [Payroll].[PayrollCalendars] ([PayrollCalendarId]);
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_Employees_PayrollCalendar' AND object_id = OBJECT_ID(N'[Employee].[Employees]'))
    CREATE INDEX [IX_Employees_PayrollCalendar] ON [Employee].[Employees] ([CompanyId], [PayrollCalendarId]);
GO

/* ------------------------------------------------------------------
   2. Employee.EmployeeAuditLog
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Employee].[EmployeeAuditLog]', N'U') IS NULL
BEGIN
    CREATE TABLE [Employee].[EmployeeAuditLog] (
        AuditLogId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeeAuditLog PRIMARY KEY,
        EmployeeId       BIGINT          NOT NULL,
        CompanyId        INT             NULL,          -- the employee's company at the time
        TransactionType  VARCHAR(40)     NOT NULL,      -- CALENDAR_CHANGED, SALARY_CHANGED, ... (Models/Audit)
        FieldName        NVARCHAR(100)   NULL,
        OldValue         NVARCHAR(500)   NULL,
        NewValue         NVARCHAR(500)   NULL,
        Reference        NVARCHAR(100)   NULL,          -- e.g. the payroll code of an exclusion
        Remarks          NVARCHAR(1000)  NULL,
        ActionBy         BIGINT          NULL,
        ActionDate       DATETIME2(0)    NOT NULL CONSTRAINT DF_EmployeeAuditLog_ActionDate DEFAULT (SYSUTCDATETIME()),

        CONSTRAINT FK_EmployeeAuditLog_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees] (EmployeeId)
    );
    CREATE INDEX IX_EmployeeAuditLog_Employee ON [Employee].[EmployeeAuditLog] (EmployeeId, ActionDate DESC);
    CREATE INDEX IX_EmployeeAuditLog_Date     ON [Employee].[EmployeeAuditLog] (ActionDate DESC) INCLUDE (CompanyId, TransactionType);
END;
GO

/* ------------------------------------------------------------------
   3. Employee.usp_EmployeeAudit_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeAudit_Manage]
    @Action           VARCHAR(20),
    @Id               BIGINT          = NULL,     -- ADD: the employee
    @EmployeeId       BIGINT          = NULL,     -- LIST: one employee
    @CompanyId        INT             = NULL,     -- a user pinned to a company
    @CompanyIds       NVARCHAR(2000)  = NULL,     -- top-bar company filter (CSV)
    @TransactionType  VARCHAR(400)    = NULL,     -- ADD: the type; LIST: CSV of types (NULL = all)
    @FieldName        NVARCHAR(100)   = NULL,
    @OldValue         NVARCHAR(500)   = NULL,
    @NewValue         NVARCHAR(500)   = NULL,
    @Reference        NVARCHAR(100)   = NULL,
    @Remarks          NVARCHAR(1000)  = NULL,
    @DateFrom         DATETIME2(0)    = NULL,     -- LIST: UTC instant, inclusive (the app converts the user's local day)
    @DateTo           DATETIME2(0)    = NULL,     -- LIST: UTC instant, exclusive
    @Search           NVARCHAR(200)   = NULL,
    @PageNumber       INT             = 1,
    @PageSize         INT             = 50,
    @UserId           BIGINT          = NULL,

    @TotalCount       INT             = NULL OUTPUT,
    @NewId            BIGINT          = NULL OUTPUT,
    @ResultCode       VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage    NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 50 WHEN @PageSize > 20000 THEN 20000 ELSE @PageSize END;

    IF @Action NOT IN ('ADD', 'LIST')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= ADD ================================= */
    IF @Action = 'ADD'
    BEGIN
        DECLARE @aCo INT;
        SELECT @aCo = CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @Id;
        IF @aCo IS NULL OR NULLIF(LTRIM(RTRIM(@TransactionType)), '') IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
            RETURN;
        END;

        INSERT INTO [Employee].[EmployeeAuditLog] (EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Reference, Remarks, ActionBy)
        VALUES (@Id, @aCo, UPPER(LTRIM(RTRIM(@TransactionType))), NULLIF(@FieldName, N''), @OldValue, @NewValue,
                NULLIF(@Reference, N''), NULLIF(@Remarks, N''), @UserId);
        SET @NewId = SCOPE_IDENTITY();
        RETURN;
    END;

    /* ======================= LIST ================================ */
    DECLARE @Types TABLE (TransactionType VARCHAR(40) PRIMARY KEY);
    INSERT INTO @Types (TransactionType)
    SELECT DISTINCT UPPER(LTRIM(RTRIM(value))) FROM STRING_SPLIT(ISNULL(@TransactionType, ''), ',') WHERE LTRIM(RTRIM(value)) <> '';
    DECLARE @AllTypes BIT = CASE WHEN EXISTS (SELECT 1 FROM @Types) THEN 0 ELSE 1 END;

    ;WITH x AS (
        SELECT  a.AuditLogId, a.EmployeeId, a.CompanyId, a.TransactionType, a.FieldName, a.OldValue, a.NewValue,
                a.Reference, a.Remarks, a.ActionBy, a.ActionDate,
                ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName,
                e.ArabicName, co.CompanyName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Employee].[EmployeeAuditLog] AS a
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = a.CompanyId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = a.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   (@CompanyId  IS NULL OR a.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(a.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND   (@EmployeeId IS NULL OR a.EmployeeId = @EmployeeId)
          AND   (@AllTypes = 1 OR a.TransactionType IN (SELECT TransactionType FROM @Types))
          AND   (@DateFrom IS NULL OR a.ActionDate >= @DateFrom)
          AND   (@DateTo IS NULL OR a.ActionDate < @DateTo)
          AND   (@Search IS NULL
                 OR e.EmployeeCode LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%'
                 OR CONCAT(e.FirstName, N' ', e.LastName) LIKE N'%' + @Search + N'%' OR e.ArabicName LIKE N'%' + @Search + N'%'
                 OR a.OldValue LIKE N'%' + @Search + N'%' OR a.NewValue LIKE N'%' + @Search + N'%'
                 OR a.Reference LIKE N'%' + @Search + N'%' OR a.Remarks LIKE N'%' + @Search + N'%')
    )
    SELECT  x.*, COUNT(1) OVER () AS TotalRows
    INTO    #Page
    FROM    x
    ORDER BY x.ActionDate DESC, x.AuditLogId DESC
    OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

    SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #Page;
    IF @TotalCount = 0 AND @PageNumber > 1
        SELECT @TotalCount = COUNT(1)
        FROM   [Employee].[EmployeeAuditLog] AS a
        WHERE  (@CompanyId  IS NULL OR a.CompanyId = @CompanyId)
          AND  (@EmployeeId IS NULL OR a.EmployeeId = @EmployeeId);

    SELECT AuditLogId, EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Reference, Remarks,
           ActionBy, ActionDate, EmployeeNo, EmployeeName, ArabicName, CompanyName, ActionByName
    FROM   #Page
    ORDER BY ActionDate DESC, AuditLogId DESC;
END;
GO

/* ------------------------------------------------------------------
   4. Employee.usp_EmployeePayrollCalendar_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeePayrollCalendar_Manage]
    @Action             VARCHAR(20),
    @Id                 BIGINT          = NULL,     -- the employee (GET / SET)
    @CompanyId          INT             = NULL,     -- COUNTS
    @PayrollCalendarId  INT             = NULL,     -- SET
    @Remarks            NVARCHAR(1000)  = NULL,
    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;

    IF @Action NOT IN ('GET', 'SET', 'COUNTS')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  e.EmployeeId, e.CompanyId, e.PayrollCalendarId, pc.CalendarCode, pc.CalendarName, pc.ArabicName AS CalendarArabicName,
                pc.PayFrequency, pc.IsActive AS CalendarIsActive,
                (SELECT TOP 1 a.ActionDate FROM [Employee].[EmployeeAuditLog] a
                  WHERE a.EmployeeId = e.EmployeeId AND a.TransactionType IN ('CALENDAR_ASSIGNED', 'CALENDAR_CHANGED')
                  ORDER BY a.ActionDate DESC, a.AuditLogId DESC) AS LastChangedDate
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = e.PayrollCalendarId
        WHERE   e.EmployeeId = @Id;
        RETURN;
    END;

    /* ======================= COUNTS ============================== */
    IF @Action = 'COUNTS'
    BEGIN
        /* employees a payroll of the company can pay today: not removed, not terminated / resigned without an end date */
        SELECT  e.PayrollCalendarId, COUNT(1) AS EmployeeCount
        FROM    [Employee].[Employees] AS e
        WHERE   e.CompanyId = @CompanyId AND e.Deleted = 0 AND e.IsDeleted = 0
          AND   NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)
          AND   (e.TerminationDate IS NULL OR e.TerminationDate >= DATEADD(MONTH, -2, CAST(SYSUTCDATETIME() AS DATE)))
        GROUP BY e.PayrollCalendarId;
        RETURN;
    END;

    /* ======================= SET ================================= */
    DECLARE @eCo INT, @Old INT, @OldName NVARCHAR(200), @NewName NVARCHAR(200), @NewCo INT, @NewActive BIT;
    SELECT @eCo = e.CompanyId, @Old = e.PayrollCalendarId,
           @OldName = CASE WHEN pc.PayrollCalendarId IS NULL THEN NULL ELSE CONCAT(pc.CalendarCode, N' · ', pc.CalendarName) END
    FROM   [Employee].[Employees] AS e
    LEFT JOIN [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = e.PayrollCalendarId
    WHERE  e.EmployeeId = @Id AND e.Deleted = 0;

    IF @eCo IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.';
        RETURN;
    END;
    IF @PayrollCalendarId IS NULL
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the payroll calendar of the employee.';
        RETURN;
    END;

    SELECT @NewCo = CompanyId, @NewActive = IsActive, @NewName = CONCAT(CalendarCode, N' · ', CalendarName)
    FROM   [Payroll].[PayrollCalendars]
    WHERE  PayrollCalendarId = @PayrollCalendarId AND Deleted = 0;

    IF @NewCo IS NULL OR @NewCo <> @eCo
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The payroll calendar must belong to the employee''s company.';
        RETURN;
    END;
    IF @NewActive = 0 AND ISNULL(@Old, 0) <> @PayrollCalendarId
    BEGIN
        SELECT @ResultCode = 'INACTIVE', @ResultMessage = N'This payroll calendar is inactive.';
        RETURN;
    END;

    IF @Old = @PayrollCalendarId
    BEGIN
        SET @NewId = @Id;
        RETURN;     -- nothing changed, nothing to log
    END;

    BEGIN TRANSACTION;
        UPDATE [Employee].[Employees]
           SET PayrollCalendarId = @PayrollCalendarId, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        WHERE  EmployeeId = @Id;

        INSERT INTO [Employee].[EmployeeAuditLog] (EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Remarks, ActionBy)
        VALUES (@Id, @eCo, CASE WHEN @Old IS NULL THEN 'CALENDAR_ASSIGNED' ELSE 'CALENDAR_CHANGED' END,
                N'Payroll calendar', @OldName, @NewName, NULLIF(LTRIM(RTRIM(@Remarks)), N''), @UserId);
    COMMIT TRANSACTION;

    SELECT @NewId = @Id,
           @ResultMessage = CASE WHEN @Old IS NULL THEN N'Payroll calendar assigned.' ELSE N'Payroll calendar changed.' END;
END;
GO

/* ------------------------------------------------------------------
   5. Permissions (System Administrator only, the first time)
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('EMPLOYEE_PAYROLL_CALENDAR_CHANGE', 'Employee', 'CalendarChange'),
    ('AUDIT_REPORT_VIEW', 'Audit', 'View');

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
   6. One-time: give every employee without a calendar their company's
      default calendar (else its only active calendar)
   ------------------------------------------------------------------ */
DECLARE @Assigned TABLE (EmployeeId BIGINT PRIMARY KEY, CompanyId INT, PayrollCalendarId INT);

;WITH pick AS (
    SELECT  pc.CompanyId, pc.PayrollCalendarId,
            ROW_NUMBER() OVER (PARTITION BY pc.CompanyId ORDER BY pc.IsDefault DESC, pc.PayrollCalendarId) AS rn,
            SUM(CASE WHEN pc.IsDefault = 1 THEN 1 ELSE 0 END) OVER (PARTITION BY pc.CompanyId) AS Defaults,
            COUNT(1) OVER (PARTITION BY pc.CompanyId) AS Calendars
    FROM    [Payroll].[PayrollCalendars] AS pc
    WHERE   pc.Deleted = 0 AND pc.IsActive = 1
)
UPDATE e
   SET e.PayrollCalendarId = p.PayrollCalendarId
OUTPUT inserted.EmployeeId, inserted.CompanyId, inserted.PayrollCalendarId INTO @Assigned
FROM   [Employee].[Employees] AS e
JOIN   pick AS p ON p.CompanyId = e.CompanyId AND p.rn = 1 AND (p.Defaults >= 1 OR p.Calendars = 1)
WHERE  e.PayrollCalendarId IS NULL AND e.Deleted = 0;

INSERT INTO [Employee].[EmployeeAuditLog] (EmployeeId, CompanyId, TransactionType, FieldName, OldValue, NewValue, Remarks, ActionBy)
SELECT a.EmployeeId, a.CompanyId, 'CALENDAR_ASSIGNED', N'Payroll calendar', NULL, CONCAT(pc.CalendarCode, N' · ', pc.CalendarName),
       N'Initial assignment: the company''s default payroll calendar (db/60).', NULL
FROM   @Assigned AS a
JOIN   [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = a.PayrollCalendarId;

PRINT CONCAT(N'Employees given their company''s default payroll calendar: ', @@ROWCOUNT);
GO
