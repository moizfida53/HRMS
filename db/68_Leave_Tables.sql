/* =====================================================================
   68_Leave_Tables.sql  -  HRMS Leave, phase 1: tables, defaults, rights
   ---------------------------------------------------------------------
   Run after 28 (soft delete) and 60. Safe to re-run - a re-run also repairs
   a first run that met older Leave.LeaveTypes / LeaveRequests tables (step 0).

     Leave.Settings          one row per company: weekend days, whether
                             the line manager approves before HR
     Leave.LeaveTypes        Annual, Sick, Emergency, Hajj, Maternity ...
                             per company, each with its own rules
     Leave.LeaveTypeTiers    pay by day band (sick leave: 15 days full,
                             10 at 75 % ...) - used by payroll in phase 2
     Leave.PublicHolidays    official holidays (one company or all)
     Leave.LeaveRequests     the requests, with their approval steps
     Leave.LeaveRequestHistory  who did what to a request, and when
     Leave.LeaveLedger       opening balances and manual adjustments

   Balances are NOT stored: Leave.tvf_Balances (db/69) works them out from
   the type's rule (earned monthly, per year, once in service ...), the
   opening balance, adjustments and the approved requests - so a balance
   can never drift from the requests behind it.

   Default leave types follow the Kuwait private-sector labour law (Law
   6/2010) - review them with HR / legal; every value can be changed on
   Leave > Settings. Only the fixed-date public holidays are seeded; add
   the Islamic holidays (Eid, Isra'a & Mi'raj, Hijri New Year, Prophet's
   birthday) each year, as they move with the moon.

   Nothing is ever physically deleted (db/28): every table has
   Deleted / DeletedBy / DeletedDate and every read filters Deleted = 0.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Leave')
    EXEC (N'CREATE SCHEMA [Leave]');
GO

/* ------------------------------------------------------------------
   0. An older Leave design (from the original base schema) may already
      have Leave.LeaveTypes / Leave.LeaveRequests with other columns.
      Such a table is renamed to ..._Legacy (with its constraints and
      triggers, so their names are free again) when it is EMPTY; when it
      holds rows the script stops and changes nothing. Foreign keys of
      this module's tables that a first run tied to the old tables are
      dropped here and added again further down.
   ------------------------------------------------------------------ */
DECLARE @Legacy TABLE (TableName SYSNAME, MarkerColumn SYSNAME);
INSERT INTO @Legacy VALUES (N'LeaveTypes', N'TypeCode'), (N'LeaveRequests', N'RequestNo');

DECLARE @t SYSNAME, @marker SYSNAME, @id INT, @rows BIGINT, @sql NVARCHAR(MAX), @child SYSNAME, @fk SYSNAME, @fkTable SYSNAME;
DECLARE legacy_cursor CURSOR LOCAL FAST_FORWARD FOR SELECT TableName, MarkerColumn FROM @Legacy;
OPEN legacy_cursor;
FETCH NEXT FROM legacy_cursor INTO @t, @marker;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @id = OBJECT_ID(N'[Leave].' + QUOTENAME(@t), N'U');
    IF @id IS NOT NULL AND COL_LENGTH(N'[Leave].' + QUOTENAME(@t), @marker) IS NULL
    BEGIN
        SET @sql = N'SELECT @n = COUNT_BIG(*) FROM [Leave].' + QUOTENAME(@t) + N';';
        EXEC sp_executesql @sql, N'@n BIGINT OUTPUT', @n = @rows OUTPUT;
        IF @rows > 0
        BEGIN
            RAISERROR (N'[Leave].[%s] already exists with a different design and holds %I64d rows. Nothing was changed - send its structure to the developer before running this script.', 16, 1, @t, @rows);
            SET NOEXEC ON;   -- skip the rest of the script (reset at its end)
            BREAK;
        END;

        /* this module's foreign keys that point at the old table */
        DECLARE fk_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT f.name, OBJECT_NAME(f.parent_object_id)
            FROM   sys.foreign_keys f
            WHERE  f.referenced_object_id = @id
              AND  f.parent_object_id IN (OBJECT_ID(N'[Leave].[LeaveTypeTiers]'), OBJECT_ID(N'[Leave].[LeaveLedger]'),
                                          OBJECT_ID(N'[Leave].[LeaveRequestHistory]'));
        OPEN fk_cursor;
        FETCH NEXT FROM fk_cursor INTO @fk, @fkTable;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'ALTER TABLE [Leave].' + QUOTENAME(@fkTable) + N' DROP CONSTRAINT ' + QUOTENAME(@fk) + N';';
            EXEC (@sql);
            FETCH NEXT FROM fk_cursor INTO @fk, @fkTable;
        END;
        CLOSE fk_cursor; DEALLOCATE fk_cursor;

        /* its constraints and triggers keep their names otherwise (PK_LeaveTypes, TR_SoftDelete_LeaveTypes ...) */
        DECLARE child_cursor CURSOR LOCAL FAST_FORWARD FOR
            SELECT o.name FROM sys.objects o
            WHERE  o.parent_object_id = @id AND o.type IN ('PK', 'UQ', 'F', 'D', 'C', 'TR') AND o.name NOT LIKE N'%[_]Legacy';
        OPEN child_cursor;
        FETCH NEXT FROM child_cursor INTO @child;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @sql = N'[Leave].' + QUOTENAME(@child);
            SET @child = LEFT(@child, 121) + N'_Legacy';
            EXEC sp_rename @sql, @child, N'OBJECT';
            FETCH NEXT FROM child_cursor INTO @child;
        END;
        CLOSE child_cursor; DEALLOCATE child_cursor;

        SET @sql = N'[Leave].' + QUOTENAME(@t);
        SET @child = @t + N'_Legacy';
        EXEC sp_rename @sql, @child, N'OBJECT';
        PRINT CONCAT(N'The old, empty [Leave].[', @t, N'] was renamed to [Leave].[', @t, N'_Legacy].');
    END;
    FETCH NEXT FROM legacy_cursor INTO @t, @marker;
END;
CLOSE legacy_cursor; DEALLOCATE legacy_cursor;
GO

/* ------------------------------------------------------------------
   1. Leave.Settings - per company
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[Settings]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[Settings](
        CompanyId        INT           NOT NULL CONSTRAINT PK_LeaveSettings PRIMARY KEY,
        WeekendDays      VARCHAR(20)   NOT NULL CONSTRAINT DF_LeaveSettings_Weekend DEFAULT ('5,6'),   -- ISO days: 1 Mon ... 5 Fri, 6 Sat, 7 Sun
        ManagerApproval  BIT           NOT NULL CONSTRAINT DF_LeaveSettings_Manager DEFAULT (1),       -- line manager approves before HR
        CreatedBy        BIGINT        NULL,
        CreatedDate      DATETIME2(0)  NOT NULL CONSTRAINT DF_LeaveSettings_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy       BIGINT        NULL,
        ModifiedDate     DATETIME2(0)  NULL,
        Deleted          BIT           NOT NULL CONSTRAINT DF_LeaveSettings_Deleted DEFAULT (0),
        DeletedBy        BIGINT        NULL,
        DeletedDate      DATETIME2(0)  NULL,
        CONSTRAINT FK_LeaveSettings_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId)
    );
    PRINT N'Created [Leave].[Settings].';
END
GO

/* ------------------------------------------------------------------
   2. Leave.LeaveTypes
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[LeaveTypes]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[LeaveTypes](
        LeaveTypeId          INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_LeaveTypes PRIMARY KEY,
        CompanyId            INT            NOT NULL,
        TypeCode             VARCHAR(20)    NOT NULL,
        TypeName             NVARCHAR(100)  NOT NULL,
        ArabicName           NVARCHAR(100)  NULL,
        Category             VARCHAR(12)    NOT NULL CONSTRAINT DF_LeaveTypes_Category DEFAULT ('OTHER'),
        /* ACCRUE    earned over time and kept (annual leave)
           YEARLY    a number of days each calendar year (sick, emergency)
           ONCE      a number of days once in the whole service (Hajj)
           UNLIMITED no balance - only counted (unpaid, bereavement) */
        BalanceMode          VARCHAR(10)    NOT NULL,
        DaysPerYear          DECIMAL(6, 2)  NULL,
        AccrualMethod        VARCHAR(10)    NULL,            -- ACCRUE only: MONTHLY (2.5 / month) or UPFRONT (the year at once)
        PayType              VARCHAR(10)    NOT NULL CONSTRAINT DF_LeaveTypes_Pay DEFAULT ('FULL'),
        EligibleAfterMonths  SMALLINT       NOT NULL CONSTRAINT DF_LeaveTypes_Eligible DEFAULT (0),
        Gender               CHAR(1)        NULL,            -- M / F / NULL = everyone
        CountMode            VARCHAR(10)    NOT NULL CONSTRAINT DF_LeaveTypes_Count DEFAULT ('WORKING'),
        ExcludeHolidays      BIT            NOT NULL CONSTRAINT DF_LeaveTypes_ExclHol DEFAULT (1),
        AllowHalfDay         BIT            NOT NULL CONSTRAINT DF_LeaveTypes_Half DEFAULT (0),
        AllowNegative        BIT            NOT NULL CONSTRAINT DF_LeaveTypes_Negative DEFAULT (0),
        RequiresDocument     BIT            NOT NULL CONSTRAINT DF_LeaveTypes_Doc DEFAULT (0),
        MinNoticeDays        SMALLINT       NOT NULL CONSTRAINT DF_LeaveTypes_Notice DEFAULT (0),
        MaxDaysPerRequest    SMALLINT       NULL,
        Color                VARCHAR(7)     NULL,
        SortOrder            SMALLINT       NOT NULL CONSTRAINT DF_LeaveTypes_Sort DEFAULT (0),
        IsActive             BIT            NOT NULL CONSTRAINT DF_LeaveTypes_Active DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_LeaveTypes_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_LeaveTypes_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(0)   NULL,
        CONSTRAINT FK_LeaveTypes_Company   FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_LeaveTypes_Mode      CHECK (BalanceMode IN ('ACCRUE', 'YEARLY', 'ONCE', 'UNLIMITED')),
        CONSTRAINT CK_LeaveTypes_Accrual   CHECK (AccrualMethod IS NULL OR AccrualMethod IN ('MONTHLY', 'UPFRONT')),
        CONSTRAINT CK_LeaveTypes_Pay       CHECK (PayType IN ('FULL', 'TIERED', 'UNPAID')),
        CONSTRAINT CK_LeaveTypes_Count     CHECK (CountMode IN ('WORKING', 'CALENDAR')),
        CONSTRAINT CK_LeaveTypes_Gender    CHECK (Gender IS NULL OR Gender IN ('M', 'F')),
        CONSTRAINT CK_LeaveTypes_Category  CHECK (Category IN ('ANNUAL', 'SICK', 'EMERGENCY', 'HAJJ', 'MATERNITY', 'BEREAVEMENT', 'UNPAID', 'OTHER')),
        CONSTRAINT CK_LeaveTypes_Days      CHECK (DaysPerYear IS NULL OR DaysPerYear BETWEEN 0 AND 366)
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_LeaveTypes_Code ON [Leave].[LeaveTypes] (CompanyId, TypeCode) WHERE Deleted = 0;');
    PRINT N'Created [Leave].[LeaveTypes].';
END
GO

/* ------------------------------------------------------------------
   3. Leave.LeaveTypeTiers - pay by day band within the year
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[LeaveTypeTiers]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[LeaveTypeTiers](
        TierId        INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_LeaveTypeTiers PRIMARY KEY,
        LeaveTypeId   INT            NOT NULL,
        FromDay       SMALLINT       NOT NULL,
        ToDay         SMALLINT       NOT NULL,
        PayPercent    DECIMAL(5, 2)  NOT NULL,
        CreatedBy     BIGINT         NULL,
        CreatedDate   DATETIME2(0)   NOT NULL CONSTRAINT DF_LeaveTypeTiers_Created DEFAULT (SYSUTCDATETIME()),
        Deleted       BIT            NOT NULL CONSTRAINT DF_LeaveTypeTiers_Deleted DEFAULT (0),
        DeletedBy     BIGINT         NULL,
        DeletedDate   DATETIME2(0)   NULL,
        CONSTRAINT FK_LeaveTypeTiers_Type FOREIGN KEY (LeaveTypeId) REFERENCES [Leave].[LeaveTypes](LeaveTypeId),
        CONSTRAINT CK_LeaveTypeTiers_Days CHECK (FromDay >= 1 AND ToDay >= FromDay),
        CONSTRAINT CK_LeaveTypeTiers_Pct  CHECK (PayPercent BETWEEN 0 AND 100)
    );
    PRINT N'Created [Leave].[LeaveTypeTiers].';
END
GO

/* ------------------------------------------------------------------
   4. Leave.PublicHolidays
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[PublicHolidays]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[PublicHolidays](
        HolidayId     INT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_PublicHolidays PRIMARY KEY,
        CompanyId     INT            NULL,           -- NULL = every company
        HolidayName   NVARCHAR(100)  NOT NULL,
        ArabicName    NVARCHAR(100)  NULL,
        FromDate      DATE           NOT NULL,
        ToDate        DATE           NOT NULL,
        CreatedBy     BIGINT         NULL,
        CreatedDate   DATETIME2(0)   NOT NULL CONSTRAINT DF_PublicHolidays_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy    BIGINT         NULL,
        ModifiedDate  DATETIME2(0)   NULL,
        Deleted       BIT            NOT NULL CONSTRAINT DF_PublicHolidays_Deleted DEFAULT (0),
        DeletedBy     BIGINT         NULL,
        DeletedDate   DATETIME2(0)   NULL,
        CONSTRAINT FK_PublicHolidays_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_PublicHolidays_Dates   CHECK (ToDate >= FromDate AND DATEDIFF(DAY, FromDate, ToDate) <= 31)
    );
    EXEC (N'CREATE NONCLUSTERED INDEX IX_PublicHolidays_Dates ON [Leave].[PublicHolidays] (FromDate, ToDate) INCLUDE (CompanyId) WHERE Deleted = 0;');
    PRINT N'Created [Leave].[PublicHolidays].';
END
GO

/* ------------------------------------------------------------------
   5. Leave.LeaveRequests
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[LeaveRequests](
        LeaveRequestId      BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_LeaveRequests PRIMARY KEY,
        RequestNo           VARCHAR(20)    NOT NULL,                 -- LV-2026-00001
        CompanyId           INT            NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        LeaveTypeId         INT            NOT NULL,
        StartDate           DATE           NOT NULL,
        EndDate             DATE           NOT NULL,
        HalfDay             BIT            NOT NULL CONSTRAINT DF_LeaveRequests_Half DEFAULT (0),
        Days                DECIMAL(6, 2)  NOT NULL,                 -- the days that count (actual ones once the return is recorded)
        PlannedDays         DECIMAL(6, 2)  NOT NULL,
        Reason              NVARCHAR(500)  NULL,
        Status              VARCHAR(12)    NOT NULL CONSTRAINT DF_LeaveRequests_Status DEFAULT ('PENDING'),
        ApprovalLevel       TINYINT        NOT NULL CONSTRAINT DF_LeaveRequests_Level DEFAULT (2),   -- while PENDING: 1 manager, 2 HR
        ManagerUserId       BIGINT         NULL,                     -- the line manager's user when it was submitted
        ManagerApprovedBy   BIGINT         NULL,
        ManagerApprovedDate DATETIME2(0)   NULL,
        DecidedBy           BIGINT         NULL,                     -- final approval / rejection
        DecidedDate         DATETIME2(0)   NULL,
        DecisionComment     NVARCHAR(500)  NULL,
        CancelledBy         BIGINT         NULL,
        CancelledDate       DATETIME2(0)   NULL,
        ActualReturnDate    DATE           NULL,
        ActualEndDate       DATE           NULL,
        ReturnRecordedBy    BIGINT         NULL,
        ReturnRecordedDate  DATETIME2(0)   NULL,
        DocumentPath        NVARCHAR(400)  NULL,
        DocumentName        NVARCHAR(260)  NULL,
        DocumentType        NVARCHAR(100)  NULL,
        DocumentSize        BIGINT         NULL,
        EnteredByHr         BIT            NOT NULL CONSTRAINT DF_LeaveRequests_Hr DEFAULT (0),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_LeaveRequests_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_LeaveRequests_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(0)   NULL,
        CONSTRAINT FK_LeaveRequests_Company  FOREIGN KEY (CompanyId)   REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_LeaveRequests_Employee FOREIGN KEY (EmployeeId)  REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_LeaveRequests_Type     FOREIGN KEY (LeaveTypeId) REFERENCES [Leave].[LeaveTypes](LeaveTypeId),
        CONSTRAINT CK_LeaveRequests_Dates    CHECK (EndDate >= StartDate),
        CONSTRAINT CK_LeaveRequests_Days     CHECK (Days >= 0 AND PlannedDays >= 0),
        CONSTRAINT CK_LeaveRequests_Status   CHECK (Status IN ('PENDING', 'APPROVED', 'REJECTED', 'CANCELLED')),
        CONSTRAINT CK_LeaveRequests_Level    CHECK (ApprovalLevel IN (1, 2))
    );
    EXEC (N'CREATE UNIQUE NONCLUSTERED INDEX UQ_LeaveRequests_No ON [Leave].[LeaveRequests] (RequestNo) WHERE Deleted = 0;');
    EXEC (N'CREATE NONCLUSTERED INDEX IX_LeaveRequests_Employee ON [Leave].[LeaveRequests] (EmployeeId, StartDate) INCLUDE (LeaveTypeId, EndDate, Status, Days) WHERE Deleted = 0;');
    EXEC (N'CREATE NONCLUSTERED INDEX IX_LeaveRequests_Status ON [Leave].[LeaveRequests] (Status, CompanyId, StartDate) WHERE Deleted = 0;');
    PRINT N'Created [Leave].[LeaveRequests].';
END
GO

IF OBJECT_ID(N'[Leave].[LeaveRequestHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[LeaveRequestHistory](
        HistoryId       BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_LeaveRequestHistory PRIMARY KEY,
        LeaveRequestId  BIGINT         NOT NULL,
        ActionCode      VARCHAR(20)    NOT NULL,   -- SUBMITTED, EDITED, MANAGER_APPROVED, APPROVED, REJECTED, CANCELLED, RETURNED
        ActionBy        BIGINT         NULL,
        ActionDate      DATETIME2(0)   NOT NULL CONSTRAINT DF_LeaveRequestHistory_Date DEFAULT (SYSUTCDATETIME()),
        Comment         NVARCHAR(500)  NULL,
        Deleted         BIT            NOT NULL CONSTRAINT DF_LeaveRequestHistory_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(0)   NULL,
        CONSTRAINT FK_LeaveRequestHistory_Request FOREIGN KEY (LeaveRequestId) REFERENCES [Leave].[LeaveRequests](LeaveRequestId)
    );
    EXEC (N'CREATE NONCLUSTERED INDEX IX_LeaveRequestHistory_Request ON [Leave].[LeaveRequestHistory] (LeaveRequestId) WHERE Deleted = 0;');
    PRINT N'Created [Leave].[LeaveRequestHistory].';
END
GO

/* ------------------------------------------------------------------
   6. Leave.LeaveLedger - opening balances and manual adjustments
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Leave].[LeaveLedger]', N'U') IS NULL
BEGIN
    CREATE TABLE [Leave].[LeaveLedger](
        EntryId       BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_LeaveLedger PRIMARY KEY,
        CompanyId     INT            NOT NULL,
        EmployeeId    BIGINT         NOT NULL,
        LeaveTypeId   INT            NOT NULL,
        /* OPENING  the balance on EntryDate (go-live, or a correction):
                    earning restarts from that day
           ADJUST   + / - days on EntryDate, with a reason */
        EntryType     VARCHAR(10)    NOT NULL,
        EntryDate     DATE           NOT NULL,
        Days          DECIMAL(7, 2)  NOT NULL,
        Comment       NVARCHAR(500)  NULL,
        CreatedBy     BIGINT         NULL,
        CreatedDate   DATETIME2(0)   NOT NULL CONSTRAINT DF_LeaveLedger_Created DEFAULT (SYSUTCDATETIME()),
        Deleted       BIT            NOT NULL CONSTRAINT DF_LeaveLedger_Deleted DEFAULT (0),
        DeletedBy     BIGINT         NULL,
        DeletedDate   DATETIME2(0)   NULL,
        CONSTRAINT FK_LeaveLedger_Employee FOREIGN KEY (EmployeeId)  REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_LeaveLedger_Type     FOREIGN KEY (LeaveTypeId) REFERENCES [Leave].[LeaveTypes](LeaveTypeId),
        CONSTRAINT CK_LeaveLedger_Type     CHECK (EntryType IN ('OPENING', 'ADJUST')),
        CONSTRAINT CK_LeaveLedger_Days     CHECK (Days BETWEEN -999 AND 999 AND (EntryType = 'ADJUST' OR Days >= 0))
    );
    EXEC (N'CREATE NONCLUSTERED INDEX IX_LeaveLedger_Employee ON [Leave].[LeaveLedger] (EmployeeId, LeaveTypeId, EntryDate) WHERE Deleted = 0;');
    PRINT N'Created [Leave].[LeaveLedger].';
END
GO

/* foreign keys to this module's own LeaveTypes / LeaveRequests (step 0 drops ones a first run tied to old tables) */
IF OBJECT_ID(N'[Leave].[FK_LeaveTypeTiers_Type]', N'F') IS NULL
    ALTER TABLE [Leave].[LeaveTypeTiers] WITH CHECK
        ADD CONSTRAINT FK_LeaveTypeTiers_Type FOREIGN KEY (LeaveTypeId) REFERENCES [Leave].[LeaveTypes](LeaveTypeId);
IF OBJECT_ID(N'[Leave].[FK_LeaveLedger_Type]', N'F') IS NULL
    ALTER TABLE [Leave].[LeaveLedger] WITH CHECK
        ADD CONSTRAINT FK_LeaveLedger_Type FOREIGN KEY (LeaveTypeId) REFERENCES [Leave].[LeaveTypes](LeaveTypeId);
IF OBJECT_ID(N'[Leave].[FK_LeaveRequestHistory_Request]', N'F') IS NULL
    ALTER TABLE [Leave].[LeaveRequestHistory] WITH CHECK
        ADD CONSTRAINT FK_LeaveRequestHistory_Request FOREIGN KEY (LeaveRequestId) REFERENCES [Leave].[LeaveRequests](LeaveRequestId);
GO

/* ------------------------------------------------------------------
   7. Default leave types for a company (also called for a company
      created later - Leave > Settings does it when it finds none)
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveType_SeedDefaults]
    @CompanyId  INT,
    @UserId     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @CompanyId AND Deleted = 0) RETURN;

    IF NOT EXISTS (SELECT 1 FROM [Leave].[Settings] WHERE CompanyId = @CompanyId)
        INSERT INTO [Leave].[Settings] (CompanyId, CreatedBy) VALUES (@CompanyId, @UserId);

    IF EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE CompanyId = @CompanyId AND Deleted = 0) RETURN;

    DECLARE @Seed TABLE (
        TypeCode VARCHAR(20), TypeName NVARCHAR(100), ArabicName NVARCHAR(100), Category VARCHAR(12), BalanceMode VARCHAR(10),
        DaysPerYear DECIMAL(6,2), AccrualMethod VARCHAR(10), PayType VARCHAR(10), EligibleAfterMonths SMALLINT, Gender CHAR(1),
        CountMode VARCHAR(10), ExcludeHolidays BIT, AllowHalfDay BIT, RequiresDocument BIT, MaxDaysPerRequest SMALLINT,
        Color VARCHAR(7), SortOrder SMALLINT);
    INSERT INTO @Seed VALUES
    /*  code          name                    arabic               category      mode        days  accrual    pay       elig gen  count       exHol half doc max   color      order */
    ('ANNUAL',      N'Annual Leave',       N'إجازة سنوية',       'ANNUAL',      'ACCRUE',    30,   'MONTHLY', 'FULL',    9,   NULL, 'WORKING',  1,    1,   0,  NULL, '#2563eb', 10),
    ('SICK',        N'Sick Leave',         N'إجازة مرضية',       'SICK',        'YEARLY',    75,   NULL,      'TIERED',  0,   NULL, 'CALENDAR', 0,    0,   1,  NULL, '#dc2626', 20),
    ('EMERGENCY',   N'Emergency Leave',    N'إجازة طارئة',       'EMERGENCY',   'YEARLY',    3,    NULL,      'FULL',    0,   NULL, 'WORKING',  1,    1,   0,  NULL, '#d97706', 30),
    ('HAJJ',        N'Hajj Leave',         N'إجازة الحج',        'HAJJ',        'ONCE',      21,   NULL,      'FULL',    24,  NULL, 'CALENDAR', 0,    0,   0,  NULL, '#059669', 40),
    ('MATERNITY',   N'Maternity Leave',    N'إجازة أمومة',       'MATERNITY',   'YEARLY',    70,   NULL,      'FULL',    0,   'F',  'CALENDAR', 0,    0,   1,  NULL, '#db2777', 50),
    ('BEREAVEMENT', N'Bereavement Leave',  N'إجازة وفاة',        'BEREAVEMENT', 'UNLIMITED', NULL, NULL,      'FULL',    0,   NULL, 'CALENDAR', 0,    0,   0,  3,    '#475569', 60),
    ('UNPAID',      N'Unpaid Leave',       N'إجازة بدون راتب',   'UNPAID',      'UNLIMITED', NULL, NULL,      'UNPAID',  0,   NULL, 'CALENDAR', 0,    0,   0,  NULL, '#64748b', 70);

    INSERT INTO [Leave].[LeaveTypes] (CompanyId, TypeCode, TypeName, ArabicName, Category, BalanceMode, DaysPerYear, AccrualMethod, PayType,
                                      EligibleAfterMonths, Gender, CountMode, ExcludeHolidays, AllowHalfDay, RequiresDocument, MaxDaysPerRequest,
                                      Color, SortOrder, CreatedBy)
    SELECT @CompanyId, TypeCode, TypeName, ArabicName, Category, BalanceMode, DaysPerYear, AccrualMethod, PayType,
           EligibleAfterMonths, Gender, CountMode, ExcludeHolidays, AllowHalfDay, RequiresDocument, MaxDaysPerRequest,
           Color, SortOrder, @UserId
    FROM   @Seed;

    /* sick leave pay bands: 15 days full, 10 at 75 %, 10 at 50 %, 10 at 25 %, 30 unpaid */
    INSERT INTO [Leave].[LeaveTypeTiers] (LeaveTypeId, FromDay, ToDay, PayPercent, CreatedBy)
    SELECT t.LeaveTypeId, v.FromDay, v.ToDay, v.Pct, @UserId
    FROM   [Leave].[LeaveTypes] AS t
    CROSS JOIN (VALUES (1, 15, 100.00), (16, 25, 75.00), (26, 35, 50.00), (36, 45, 25.00), (46, 75, 0.00)) AS v (FromDay, ToDay, Pct)
    WHERE  t.CompanyId = @CompanyId AND t.TypeCode = 'SICK' AND t.Deleted = 0;
END;
GO

DECLARE @cid INT;
DECLARE co CURSOR LOCAL FAST_FORWARD FOR SELECT CompanyId FROM [Core].[Companies] WHERE Deleted = 0;
OPEN co;
FETCH NEXT FROM co INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Leave].[usp_LeaveType_SeedDefaults] @CompanyId = @cid;
    FETCH NEXT FROM co INTO @cid;
END;
CLOSE co; DEALLOCATE co;
GO

/* ------------------------------------------------------------------
   8. Fixed-date Kuwait public holidays (every company), 2026 - 2027
   ------------------------------------------------------------------ */
INSERT INTO [Leave].[PublicHolidays] (CompanyId, HolidayName, ArabicName, FromDate, ToDate)
SELECT NULL, v.Name, v.Ar, v.d, v.d
FROM  (VALUES
        (N'New Year''s Day', N'رأس السنة الميلادية', CAST('2026-01-01' AS DATE)),
        (N'National Day',    N'العيد الوطني',        CAST('2026-02-25' AS DATE)),
        (N'Liberation Day',  N'عيد التحرير',         CAST('2026-02-26' AS DATE)),
        (N'New Year''s Day', N'رأس السنة الميلادية', CAST('2027-01-01' AS DATE)),
        (N'National Day',    N'العيد الوطني',        CAST('2027-02-25' AS DATE)),
        (N'Liberation Day',  N'عيد التحرير',         CAST('2027-02-26' AS DATE))
      ) AS v (Name, Ar, d)
WHERE NOT EXISTS (SELECT 1 FROM [Leave].[PublicHolidays] h WHERE h.CompanyId IS NULL AND h.FromDate = v.d AND h.Deleted = 0);
GO

/* ------------------------------------------------------------------
   9. Permissions (System Administrator, the first time)
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action) VALUES
    ('LEAVE_VIEW',           'Leave', 'View'),
    ('LEAVE_MANAGE',         'Leave', 'Manage'),
    ('LEAVE_BALANCE_ADJUST', 'Leave', 'BalanceAdjust'),
    ('LEAVE_SETUP_VIEW',     'Leave', 'SetupView'),
    ('LEAVE_SETUP_EDIT',     'Leave', 'SetupEdit'),
    ('LEAVE_APPROVE_L1',     'Leave', 'ApproveL1'),
    ('LEAVE_APPROVE_L2',     'Leave', 'ApproveL2'),
    ('LEAVE_APPROVE_SELF',   'Leave', 'ApproveSelf');

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
PRINT CONCAT(N'Leave permission codes created: ', @CodesCreated);
DROP TABLE #Codes;
GO

SET NOEXEC OFF;   -- in case step 0 stopped the script
GO
