/* =====================================================================
   126_Attendance.sql  -  Time & Attendance
   ---------------------------------------------------------------------
   Run after db/34, db/37, db/57 and db/68 (Leave: public holidays and
   leave requests). Safe to re-run.

   Time & Attendance imports the fingerprint device's report (Excel /
   CSV), works out each employee's day from the attendance pattern they
   are assigned, and posts the month's deductions (late arrival, short
   hours, absence) and overtime to the payroll as pay items.

     Attendance.Patterns          working hours / shifts and their rules:
                                  fixed shift (start - end) or flexible
                                  (minimum hours), grace minutes, weekly
                                  days off, late / short-hours rules,
                                  absence, missing punches, overtime, the
                                  salary a day is worked out from and the
                                  monthly cap of the deductions
     Attendance.PatternSlabs      the late / short-hours slabs: from - to
                                  minutes -> an amount, a % of a day's pay
                                  or the minutes pro rata
     Attendance.EmployeeSettings  the employee's ID on the device
     Attendance.EmployeePatterns  the pattern of an employee from a date
     Attendance.Imports           every file imported (the columns found)
     Attendance.Records           one row per employee and day: clock in /
                                  out, worked, late, short, overtime, the
                                  deduction and the status; absences are
                                  added (GENERATED) for the days the
                                  import covers
     Attendance.Postings          what was posted to the payroll per month

   Posting creates one-time pay items (Payroll.EmployeePayItems, SourceRef
   'ATT:yyyy-MM') of the item types ATT_DEDUCTION and ATT_OVERTIME (added
   to the company when missing). Posting again replaces them while no
   closed payroll has used them.

   Rights: ATTENDANCE_VIEW (see), ATTENDANCE_IMPORT (import, edit days,
   assign patterns), ATTENDANCE_POST (post to the payroll),
   ATTENDANCE_SETUP_VIEW / ATTENDANCE_SETUP_EDIT (patterns). First run:
   granted to System Administrator and the roles that manage deductions.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[EmployeePayItems]', N'U') IS NULL OR OBJECT_ID(N'[Leave].[PublicHolidays]', N'U') IS NULL
   OR OBJECT_ID(N'[Security].[RolePermissions]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/34, db/57 and db/68 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

IF SCHEMA_ID(N'Attendance') IS NULL EXEC (N'CREATE SCHEMA [Attendance] AUTHORIZATION [dbo];');
GO

/* ---- 1. tables ------------------------------------------------------------ */
IF OBJECT_ID(N'[Attendance].[Patterns]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[Patterns](
        PatternId            INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttPatterns PRIMARY KEY,
        CompanyId            INT            NOT NULL,
        PatternCode          NVARCHAR(30)   NOT NULL,
        PatternName          NVARCHAR(150)  NOT NULL,
        ArabicName           NVARCHAR(150)  NULL,
        PatternType          VARCHAR(10)    NOT NULL CONSTRAINT DF_AttPatterns_Type DEFAULT ('FIXED'),
        ShiftStart           TIME(0)        NULL,
        ShiftEnd             TIME(0)        NULL,
        RequiredMinutes      SMALLINT       NOT NULL CONSTRAINT DF_AttPatterns_Required DEFAULT (480),
        BreakMinutes         SMALLINT       NOT NULL CONSTRAINT DF_AttPatterns_Break DEFAULT (0),
        GraceMinutes         SMALLINT       NOT NULL CONSTRAINT DF_AttPatterns_Grace DEFAULT (0),
        WeeklyOffDays        VARCHAR(30)    NULL,                     -- FRI,SAT
        LateEnabled          BIT            NOT NULL CONSTRAINT DF_AttPatterns_Late DEFAULT (1),
        ShortEnabled         BIT            NOT NULL CONSTRAINT DF_AttPatterns_Short DEFAULT (1),
        CombineRule          VARCHAR(10)    NOT NULL CONSTRAINT DF_AttPatterns_Combine DEFAULT ('HIGHER'),
        FreeLatesPerMonth    TINYINT        NOT NULL CONSTRAINT DF_AttPatterns_FreeLates DEFAULT (0),
        AbsentEnabled        BIT            NOT NULL CONSTRAINT DF_AttPatterns_Absent DEFAULT (1),
        AbsentDayValue       DECIMAL(5,2)   NOT NULL CONSTRAINT DF_AttPatterns_AbsentDays DEFAULT (1),
        MissingPunch         VARCHAR(10)    NOT NULL CONSTRAINT DF_AttPatterns_Missing DEFAULT ('FLAG'),
        OvertimeEnabled      BIT            NOT NULL CONSTRAINT DF_AttPatterns_Ot DEFAULT (0),
        OvertimeAfterMinutes SMALLINT       NOT NULL CONSTRAINT DF_AttPatterns_OtAfter DEFAULT (30),
        OvertimeRate         DECIMAL(5,2)   NOT NULL CONSTRAINT DF_AttPatterns_OtRate DEFAULT (1.25),
        SalaryBasis          VARCHAR(10)    NOT NULL CONSTRAINT DF_AttPatterns_Basis DEFAULT ('BASIC'),
        DayDivisor           TINYINT        NOT NULL CONSTRAINT DF_AttPatterns_Divisor DEFAULT (26),
        MaxDeductionType     VARCHAR(10)    NOT NULL CONSTRAINT DF_AttPatterns_MaxType DEFAULT ('NONE'),
        MaxDeductionValue    DECIMAL(12,3)  NULL,
        Description          NVARCHAR(500)  NULL,
        IsActive             BIT            NOT NULL CONSTRAINT DF_AttPatterns_Active DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_AttPatterns_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Attendance_Patterns_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_AttPatterns_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_AttPatterns_Type     CHECK (PatternType IN ('FIXED', 'FLEXIBLE')),
        CONSTRAINT CK_AttPatterns_Combine  CHECK (CombineRule IN ('HIGHER', 'BOTH')),
        CONSTRAINT CK_AttPatterns_Missing  CHECK (MissingPunch IN ('FLAG', 'IGNORE', 'HALF_DAY', 'ABSENT')),
        CONSTRAINT CK_AttPatterns_Basis    CHECK (SalaryBasis IN ('BASIC', 'GROSS')),
        CONSTRAINT CK_AttPatterns_MaxType  CHECK (MaxDeductionType IN ('NONE', 'AMOUNT', 'PERCENT')),
        CONSTRAINT CK_AttPatterns_Required CHECK (RequiredMinutes BETWEEN 1 AND 1440),
        CONSTRAINT CK_AttPatterns_Divisor  CHECK (DayDivisor BETWEEN 1 AND 31),
        CONSTRAINT CK_AttPatterns_Shift    CHECK (PatternType = 'FLEXIBLE' OR (ShiftStart IS NOT NULL AND ShiftEnd IS NOT NULL))
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttPatterns_Code ON [Attendance].[Patterns](CompanyId, PatternCode) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Attendance].[PatternSlabs]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[PatternSlabs](
        SlabId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttPatternSlabs PRIMARY KEY,
        PatternId       INT            NOT NULL,
        RuleKind        VARCHAR(6)     NOT NULL,      -- LATE / SHORT
        FromMinutes     SMALLINT       NOT NULL,
        ToMinutes       SMALLINT       NULL,          -- NULL = and above
        DeductionType   VARCHAR(12)    NOT NULL,      -- AMOUNT / DAY_PERCENT / PRORATA
        Value           DECIMAL(12,3)  NOT NULL CONSTRAINT DF_AttSlabs_Value DEFAULT (0),
        SortOrder       SMALLINT       NOT NULL CONSTRAINT DF_AttSlabs_Sort DEFAULT (0),
        Deleted         BIT            NOT NULL CONSTRAINT DF_Attendance_PatternSlabs_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(7)   NULL,
        CONSTRAINT FK_AttSlabs_Pattern FOREIGN KEY (PatternId) REFERENCES [Attendance].[Patterns](PatternId),
        CONSTRAINT CK_AttSlabs_Kind  CHECK (RuleKind IN ('LATE', 'SHORT')),
        CONSTRAINT CK_AttSlabs_Type  CHECK (DeductionType IN ('AMOUNT', 'DAY_PERCENT', 'PRORATA')),
        CONSTRAINT CK_AttSlabs_Range CHECK (FromMinutes >= 0 AND (ToMinutes IS NULL OR ToMinutes >= FromMinutes)),
        CONSTRAINT CK_AttSlabs_Value CHECK (Value >= 0)
    );
    CREATE INDEX IX_AttSlabs_Pattern ON [Attendance].[PatternSlabs](PatternId, RuleKind, FromMinutes) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Attendance].[EmployeeSettings]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[EmployeeSettings](
        EmployeeId      BIGINT         NOT NULL CONSTRAINT PK_AttEmployeeSettings PRIMARY KEY,
        DeviceUserId    NVARCHAR(30)   NULL,          -- the ID on the fingerprint device (when it is not the employee number)
        ModifiedBy      BIGINT         NULL,
        ModifiedDate    DATETIME2(0)   NOT NULL CONSTRAINT DF_AttEmpSettings_Modified DEFAULT (SYSUTCDATETIME()),
        Deleted         BIT            NOT NULL CONSTRAINT DF_Attendance_EmployeeSettings_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(7)   NULL,
        CONSTRAINT FK_AttEmpSettings_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId)
    );
END;
GO

IF OBJECT_ID(N'[Attendance].[EmployeePatterns]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[EmployeePatterns](
        AssignmentId    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttEmployeePatterns PRIMARY KEY,
        EmployeeId      BIGINT         NOT NULL,
        PatternId       INT            NOT NULL,
        EffectiveFrom   DATE           NOT NULL,
        CreatedBy       BIGINT         NULL,
        CreatedDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_AttEmpPatterns_Created DEFAULT (SYSUTCDATETIME()),
        Deleted         BIT            NOT NULL CONSTRAINT DF_Attendance_EmployeePatterns_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(7)   NULL,
        CONSTRAINT FK_AttEmpPatterns_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_AttEmpPatterns_Pattern  FOREIGN KEY (PatternId)  REFERENCES [Attendance].[Patterns](PatternId)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttEmpPatterns_From ON [Attendance].[EmployeePatterns](EmployeeId, EffectiveFrom) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Attendance].[Imports]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[Imports](
        ImportId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttImports PRIMARY KEY,
        FileName        NVARCHAR(260)  NOT NULL,
        FileFormat      VARCHAR(10)    NOT NULL,      -- PAIRED (date, in, out) / PUNCH (one row per punch)
        MappingText     NVARCHAR(1000) NULL,          -- the columns found, as shown
        FromDate        DATE           NULL,
        ToDate          DATE           NULL,
        FileRowCount    INT            NOT NULL CONSTRAINT DF_AttImports_Rows DEFAULT (0),
        RecordCount     INT            NOT NULL CONSTRAINT DF_AttImports_Records DEFAULT (0),
        EmployeeCount   INT            NOT NULL CONSTRAINT DF_AttImports_Employees DEFAULT (0),
        SkippedCount    INT            NOT NULL CONSTRAINT DF_AttImports_Skipped DEFAULT (0),
        CreatedBy       BIGINT         NULL,
        CreatedDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_AttImports_Created DEFAULT (SYSUTCDATETIME()),
        Deleted         BIT            NOT NULL CONSTRAINT DF_Attendance_Imports_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(7)   NULL,
        CONSTRAINT CK_AttImports_Format CHECK (FileFormat IN ('PAIRED', 'PUNCH'))
    );
END;
GO

IF OBJECT_ID(N'[Attendance].[Records]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[Records](
        RecordId          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttRecords PRIMARY KEY,
        ImportId          BIGINT         NULL,
        CompanyId         INT            NOT NULL,
        EmployeeId        BIGINT         NOT NULL,
        WorkDate          DATE           NOT NULL,
        ClockIn           DATETIME2(0)   NULL,
        ClockOut          DATETIME2(0)   NULL,
        PunchCount        SMALLINT       NOT NULL CONSTRAINT DF_AttRecords_Punches DEFAULT (0),
        Source            VARCHAR(10)    NOT NULL CONSTRAINT DF_AttRecords_Source DEFAULT ('IMPORT'),
        PatternId         INT            NULL,
        Status            VARCHAR(12)    NOT NULL CONSTRAINT DF_AttRecords_Status DEFAULT ('PRESENT'),
        WorkedMinutes     INT            NOT NULL CONSTRAINT DF_AttRecords_Worked DEFAULT (0),
        LateMinutes       INT            NOT NULL CONSTRAINT DF_AttRecords_Late DEFAULT (0),
        ShortMinutes      INT            NOT NULL CONSTRAINT DF_AttRecords_Short DEFAULT (0),
        OvertimeMinutes   INT            NOT NULL CONSTRAINT DF_AttRecords_Ot DEFAULT (0),
        DeductionAmount   DECIMAL(12,3)  NOT NULL CONSTRAINT DF_AttRecords_Ded DEFAULT (0),
        OvertimeAmount    DECIMAL(12,3)  NOT NULL CONSTRAINT DF_AttRecords_OtAmt DEFAULT (0),
        DeductionNote     NVARCHAR(300)  NULL,
        IsExcused         BIT            NOT NULL CONSTRAINT DF_AttRecords_Excused DEFAULT (0),
        Note              NVARCHAR(500)  NULL,
        OriginalClockIn   DATETIME2(0)   NULL,        -- as imported, when changed by hand
        OriginalClockOut  DATETIME2(0)   NULL,
        EditedBy          BIGINT         NULL,
        EditedDate        DATETIME2(0)   NULL,
        CreatedBy         BIGINT         NULL,
        CreatedDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_AttRecords_Created DEFAULT (SYSUTCDATETIME()),
        Deleted           BIT            NOT NULL CONSTRAINT DF_Attendance_Records_Deleted DEFAULT (0),
        DeletedBy         BIGINT         NULL,
        DeletedDate       DATETIME2(7)   NULL,
        CONSTRAINT FK_AttRecords_Import   FOREIGN KEY (ImportId)   REFERENCES [Attendance].[Imports](ImportId),
        CONSTRAINT FK_AttRecords_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_AttRecords_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_AttRecords_Source   CHECK (Source IN ('IMPORT', 'MANUAL', 'GENERATED')),
        CONSTRAINT CK_AttRecords_Status   CHECK (Status IN ('PRESENT', 'LATE', 'SHORT', 'LATE_SHORT', 'ABSENT', 'OFF', 'HOLIDAY',
                                                            'LEAVE', 'MISSING', 'EXCUSED', 'NO_PATTERN'))
    );
    /* one live day per employee: a new import replaces the day */
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttRecords_Day ON [Attendance].[Records](EmployeeId, WorkDate) WHERE Deleted = 0;
    CREATE INDEX IX_AttRecords_Month ON [Attendance].[Records](CompanyId, WorkDate) INCLUDE (EmployeeId, Status, DeductionAmount) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Attendance].[Postings]', N'U') IS NULL
BEGIN
    CREATE TABLE [Attendance].[Postings](
        PostingId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AttPostings PRIMARY KEY,
        CompanyId        INT            NOT NULL,
        RunMonth         DATE           NOT NULL,
        EmployeeId       BIGINT         NOT NULL,
        DeductionAmount  DECIMAL(12,3)  NOT NULL,
        OvertimeAmount   DECIMAL(12,3)  NOT NULL,
        DeductionItemId  BIGINT         NULL,
        OvertimeItemId   BIGINT         NULL,
        PostedBy         BIGINT         NULL,
        PostedDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_AttPostings_Posted DEFAULT (SYSUTCDATETIME()),
        Deleted          BIT            NOT NULL CONSTRAINT DF_Attendance_Postings_Deleted DEFAULT (0),
        DeletedBy        BIGINT         NULL,
        DeletedDate      DATETIME2(7)   NULL,
        CONSTRAINT FK_AttPostings_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_AttPostings_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_AttPostings_Month    CHECK (DAY(RunMonth) = 1)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_AttPostings_Employee ON [Attendance].[Postings](EmployeeId, RunMonth) WHERE Deleted = 0;
END;
GO

/* the delete guard of db/28 (INSTEAD OF DELETE -> Deleted = 1) */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'Patterns';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'PatternSlabs';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'EmployeeSettings';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'EmployeePatterns';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'Imports';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'Records';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Attendance', @TableName = N'Postings';
END;
GO

/* ---- 2. Attendance.usp_AttPattern_Manage ---------------------------------
     LIST    the patterns of the companies in scope (with the employees on them)
     GET     one pattern;  SLABS  its slabs (@Id) or every pattern's (@Id NULL)
     SAVE    insert / update (@Id) with @SlabsJson
     TOGGLE  active / inactive;  DELETE  (refused while employees are on it)
   -------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Attendance].[usp_AttPattern_Manage]
    @Action               VARCHAR(20),
    @Id                   INT            = NULL,
    @CompanyId            INT            = NULL,
    @CompanyIds           NVARCHAR(2000) = NULL,
    @Search               NVARCHAR(200)  = NULL,
    @IsActiveFilter       BIT            = NULL,
    @PatternCompanyId     INT            = NULL,
    @PatternCode          NVARCHAR(30)   = NULL,
    @PatternName          NVARCHAR(150)  = NULL,
    @ArabicName           NVARCHAR(150)  = NULL,
    @PatternType          VARCHAR(10)    = NULL,
    @ShiftStart           TIME(0)        = NULL,
    @ShiftEnd             TIME(0)        = NULL,
    @RequiredMinutes      SMALLINT       = NULL,
    @BreakMinutes         SMALLINT       = NULL,
    @GraceMinutes         SMALLINT       = NULL,
    @WeeklyOffDays        VARCHAR(30)    = NULL,
    @LateEnabled          BIT            = NULL,
    @ShortEnabled         BIT            = NULL,
    @CombineRule          VARCHAR(10)    = NULL,
    @FreeLatesPerMonth    TINYINT        = NULL,
    @AbsentEnabled        BIT            = NULL,
    @AbsentDayValue       DECIMAL(5,2)   = NULL,
    @MissingPunch         VARCHAR(10)    = NULL,
    @OvertimeEnabled      BIT            = NULL,
    @OvertimeAfterMinutes SMALLINT       = NULL,
    @OvertimeRate         DECIMAL(5,2)   = NULL,
    @SalaryBasis          VARCHAR(10)    = NULL,
    @DayDivisor           TINYINT        = NULL,
    @MaxDeductionType     VARCHAR(10)    = NULL,
    @MaxDeductionValue    DECIMAL(12,3)  = NULL,
    @Description          NVARCHAR(500)  = NULL,
    @IsActive             BIT            = NULL,
    @SlabsJson            NVARCHAR(MAX)  = NULL,
    @UserId               BIGINT         = NULL,
    @TotalCount           INT            = NULL OUTPUT,
    @NewId                BIGINT         = NULL OUTPUT,
    @ResultCode           VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage        NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        SELECT  p.PatternId, p.CompanyId, co.CompanyName, p.PatternCode, p.PatternName, p.ArabicName, p.PatternType,
                p.ShiftStart, p.ShiftEnd, p.RequiredMinutes, p.BreakMinutes, p.GraceMinutes, p.WeeklyOffDays,
                p.LateEnabled, p.ShortEnabled, p.CombineRule, p.FreeLatesPerMonth, p.AbsentEnabled, p.AbsentDayValue,
                p.MissingPunch, p.OvertimeEnabled, p.OvertimeAfterMinutes, p.OvertimeRate, p.SalaryBasis, p.DayDivisor,
                p.MaxDeductionType, p.MaxDeductionValue, p.Description, p.IsActive,
                (SELECT COUNT(DISTINCT a.EmployeeId) FROM [Attendance].[EmployeePatterns] AS a
                 WHERE a.PatternId = p.PatternId AND a.Deleted = 0
                   AND a.EffectiveFrom = (SELECT MAX(b.EffectiveFrom) FROM [Attendance].[EmployeePatterns] AS b
                                          WHERE b.EmployeeId = a.EmployeeId AND b.Deleted = 0 AND b.EffectiveFrom <= CAST(GETDATE() AS DATE))) AS EmployeeCount
        FROM    [Attendance].[Patterns] AS p
        JOIN    [Core].[Companies] AS co ON co.CompanyId = p.CompanyId
        WHERE   p.Deleted = 0
          AND  (@Action = 'LIST' OR p.PatternId = @Id)
          AND  (@Action = 'GET' OR [Payroll].[ufn_InCompanyScope](p.CompanyId, @CompanyId, @CompanyIds) = 1)
          AND  (@IsActiveFilter IS NULL OR p.IsActive = @IsActiveFilter)
          AND  (@Pattern IS NULL OR p.PatternCode LIKE @Pattern ESCAPE '\' OR p.PatternName LIKE @Pattern ESCAPE '\'
                OR p.ArabicName LIKE @Pattern ESCAPE '\')
        ORDER BY co.CompanyName, p.PatternName;
        SET @TotalCount = @@ROWCOUNT;
        RETURN;
    END;

    IF @Action = 'SLABS'
    BEGIN
        SELECT  s.SlabId, s.PatternId, s.RuleKind, s.FromMinutes, s.ToMinutes, s.DeductionType, s.Value, s.SortOrder
        FROM    [Attendance].[PatternSlabs] AS s
        JOIN    [Attendance].[Patterns] AS p ON p.PatternId = s.PatternId AND p.Deleted = 0
        WHERE   s.Deleted = 0 AND (s.PatternId = @Id OR (@Id IS NULL AND [Payroll].[ufn_InCompanyScope](p.CompanyId, @CompanyId, @CompanyIds) = 1))
        ORDER BY s.PatternId, s.RuleKind, s.FromMinutes;
        RETURN;
    END;

    IF @Action = 'SAVE'
    BEGIN
        SET @PatternCode = UPPER(NULLIF(LTRIM(RTRIM(@PatternCode)), N''));
        SET @PatternName = NULLIF(LTRIM(RTRIM(@PatternName)), N'');
        IF @PatternCompanyId IS NULL OR @PatternCode IS NULL OR @PatternName IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the company, the code and the name.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Attendance].[Patterns] WHERE CompanyId = @PatternCompanyId AND PatternCode = @PatternCode
                   AND Deleted = 0 AND PatternId <> ISNULL(@Id, 0))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'Another pattern of this company has this code.';
            RETURN;
        END;
        IF ISNULL(@PatternType, 'FIXED') = 'FIXED' AND (@ShiftStart IS NULL OR @ShiftEnd IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the shift start and end.';
            RETURN;
        END;
        IF @Id > 0 AND NOT EXISTS (SELECT 1 FROM [Attendance].[Patterns] WHERE PatternId = @Id AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'The pattern was not found.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            IF ISNULL(@Id, 0) = 0
            BEGIN
                INSERT INTO [Attendance].[Patterns] (CompanyId, PatternCode, PatternName, ArabicName, PatternType, ShiftStart, ShiftEnd,
                    RequiredMinutes, BreakMinutes, GraceMinutes, WeeklyOffDays, LateEnabled, ShortEnabled, CombineRule, FreeLatesPerMonth,
                    AbsentEnabled, AbsentDayValue, MissingPunch, OvertimeEnabled, OvertimeAfterMinutes, OvertimeRate, SalaryBasis,
                    DayDivisor, MaxDeductionType, MaxDeductionValue, Description, IsActive, CreatedBy)
                VALUES (@PatternCompanyId, @PatternCode, @PatternName, NULLIF(LTRIM(RTRIM(@ArabicName)), N''), ISNULL(@PatternType, 'FIXED'),
                    @ShiftStart, @ShiftEnd, ISNULL(@RequiredMinutes, 480), ISNULL(@BreakMinutes, 0), ISNULL(@GraceMinutes, 0),
                    NULLIF(@WeeklyOffDays, ''), ISNULL(@LateEnabled, 1), ISNULL(@ShortEnabled, 1), ISNULL(@CombineRule, 'HIGHER'),
                    ISNULL(@FreeLatesPerMonth, 0), ISNULL(@AbsentEnabled, 1), ISNULL(@AbsentDayValue, 1), ISNULL(@MissingPunch, 'FLAG'),
                    ISNULL(@OvertimeEnabled, 0), ISNULL(@OvertimeAfterMinutes, 30), ISNULL(@OvertimeRate, 1.25), ISNULL(@SalaryBasis, 'BASIC'),
                    ISNULL(@DayDivisor, 26), ISNULL(@MaxDeductionType, 'NONE'), @MaxDeductionValue, NULLIF(LTRIM(RTRIM(@Description)), N''),
                    ISNULL(@IsActive, 1), @UserId);
                SET @Id = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE [Attendance].[Patterns]
                SET    CompanyId = @PatternCompanyId, PatternCode = @PatternCode, PatternName = @PatternName,
                       ArabicName = NULLIF(LTRIM(RTRIM(@ArabicName)), N''), PatternType = ISNULL(@PatternType, 'FIXED'),
                       ShiftStart = @ShiftStart, ShiftEnd = @ShiftEnd, RequiredMinutes = ISNULL(@RequiredMinutes, 480),
                       BreakMinutes = ISNULL(@BreakMinutes, 0), GraceMinutes = ISNULL(@GraceMinutes, 0), WeeklyOffDays = NULLIF(@WeeklyOffDays, ''),
                       LateEnabled = ISNULL(@LateEnabled, 1), ShortEnabled = ISNULL(@ShortEnabled, 1), CombineRule = ISNULL(@CombineRule, 'HIGHER'),
                       FreeLatesPerMonth = ISNULL(@FreeLatesPerMonth, 0), AbsentEnabled = ISNULL(@AbsentEnabled, 1),
                       AbsentDayValue = ISNULL(@AbsentDayValue, 1), MissingPunch = ISNULL(@MissingPunch, 'FLAG'),
                       OvertimeEnabled = ISNULL(@OvertimeEnabled, 0), OvertimeAfterMinutes = ISNULL(@OvertimeAfterMinutes, 30),
                       OvertimeRate = ISNULL(@OvertimeRate, 1.25), SalaryBasis = ISNULL(@SalaryBasis, 'BASIC'), DayDivisor = ISNULL(@DayDivisor, 26),
                       MaxDeductionType = ISNULL(@MaxDeductionType, 'NONE'), MaxDeductionValue = @MaxDeductionValue,
                       Description = NULLIF(LTRIM(RTRIM(@Description)), N''), IsActive = ISNULL(@IsActive, 1),
                       ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  PatternId = @Id;
            END;

            UPDATE [Attendance].[PatternSlabs] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PatternId = @Id AND Deleted = 0;
            INSERT INTO [Attendance].[PatternSlabs] (PatternId, RuleKind, FromMinutes, ToMinutes, DeductionType, Value, SortOrder)
            SELECT  @Id, j.RuleKind, j.FromMinutes, j.ToMinutes, j.DeductionType, ISNULL(j.Value, 0),
                    ROW_NUMBER() OVER (ORDER BY j.RuleKind, j.FromMinutes)
            FROM    OPENJSON(ISNULL(@SlabsJson, N'[]'))
                    WITH (RuleKind VARCHAR(6) '$.ruleKind', FromMinutes SMALLINT '$.fromMinutes', ToMinutes SMALLINT '$.toMinutes',
                          DeductionType VARCHAR(12) '$.deductionType', Value DECIMAL(12,3) '$.value') AS j
            WHERE   j.RuleKind IN ('LATE', 'SHORT') AND j.FromMinutes IS NOT NULL AND j.DeductionType IN ('AMOUNT', 'DAY_PERCENT', 'PRORATA');
        COMMIT TRANSACTION;
        SELECT @NewId = @Id, @ResultMessage = N'Attendance pattern saved.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Attendance].[Patterns] SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = @Now WHERE PatternId = @Id AND Deleted = 0;
        IF @@ROWCOUNT = 0 SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'The pattern was not found.';
        ELSE SET @ResultMessage = N'Saved.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Attendance].[EmployeePatterns] WHERE PatternId = @Id AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Employees are assigned to this pattern - assign them another one, or deactivate it.';
            RETURN;
        END;
        UPDATE [Attendance].[Patterns] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE PatternId = @Id AND Deleted = 0;
        SET @ResultMessage = N'Attendance pattern deleted.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- 3. Attendance.usp_AttEmployee_Manage --------------------------------
     LIST     the employees in scope: device ID, pattern now (and from when), salary
     MATCH    every employee in scope with the IDs a device file may name them by
     ASSIGNS  the pattern assignments of the employees in scope (for the calculation)
     SET      @Json [{employeeId, deviceUserId, setDevice, patternId, effectiveFrom}]
   -------------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Attendance].[usp_AttEmployee_Manage]
    @Action         VARCHAR(20),
    @Id             BIGINT         = NULL,
    @CompanyId      INT            = NULL,
    @CompanyIds     NVARCHAR(2000) = NULL,
    @FilterCompany  INT            = NULL,
    @PatternFilter  INT            = NULL,     -- -1 = no pattern
    @Search         NVARCHAR(200)  = NULL,
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
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Today DATE = CAST(GETDATE() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME();
    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize = CASE WHEN ISNULL(@PageSize, 50) NOT BETWEEN 1 AND 500 THEN 50 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(210) = CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action IN ('LIST', 'MATCH')
    BEGIN
        ;WITH x AS (
            SELECT  e.EmployeeId, e.CompanyId, co.CompanyName, e.EmployeeNo, e.EmployeeCode,
                    LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName,
                    d.DepartmentName, e.EmploymentStatus, e.HireDate, s.DeviceUserId,
                    cur.PatternId, cur.EffectiveFrom, p.PatternCode, p.PatternName, nxt.NextPatternId, nxt.NextFrom,
                    ep.BasicSalary, ep.Allowances
            FROM    [Employee].[Employees] AS e
            JOIN    [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
            LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
            LEFT JOIN [Attendance].[EmployeeSettings] AS s ON s.EmployeeId = e.EmployeeId AND s.Deleted = 0
            LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId
            OUTER APPLY (SELECT TOP (1) a.PatternId, a.EffectiveFrom FROM [Attendance].[EmployeePatterns] AS a
                         WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom <= @Today
                         ORDER BY a.EffectiveFrom DESC) AS cur
            OUTER APPLY (SELECT TOP (1) a.PatternId AS NextPatternId, a.EffectiveFrom AS NextFrom FROM [Attendance].[EmployeePatterns] AS a
                         WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom > @Today
                         ORDER BY a.EffectiveFrom) AS nxt
            LEFT JOIN [Attendance].[Patterns] AS p ON p.PatternId = ISNULL(cur.PatternId, nxt.NextPatternId)
            WHERE   e.Deleted = 0 AND e.IsDeleted = 0
              AND   [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1
              AND  (@FilterCompany IS NULL OR e.CompanyId = @FilterCompany)
              AND  (@Action = 'MATCH' OR NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate < DATEADD(MONTH, -2, @Today)))
        )
        SELECT  x.*, COUNT(1) OVER () AS Total
        FROM    x
        WHERE  (@PatternFilter IS NULL OR (@PatternFilter = -1 AND x.PatternId IS NULL AND x.NextPatternId IS NULL)
                OR x.PatternId = @PatternFilter OR x.NextPatternId = @PatternFilter)
          AND  (@Pattern IS NULL OR x.EmployeeName LIKE @Pattern ESCAPE '\' OR x.ArabicName LIKE @Pattern ESCAPE '\'
                OR x.EmployeeNo LIKE @Pattern ESCAPE '\' OR x.EmployeeCode LIKE @Pattern ESCAPE '\' OR x.DeviceUserId LIKE @Pattern ESCAPE '\'
                OR x.DepartmentName LIKE @Pattern ESCAPE '\')
        ORDER BY x.CompanyName, x.EmployeeName
        OFFSET (CASE WHEN @Action = 'MATCH' THEN 0 ELSE (@PageNumber - 1) * @PageSize END) ROWS
        FETCH NEXT (CASE WHEN @Action = 'MATCH' THEN 100000 ELSE @PageSize END) ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'ASSIGNS'
    BEGIN
        SELECT  a.AssignmentId, a.EmployeeId, a.PatternId, a.EffectiveFrom
        FROM    [Attendance].[EmployeePatterns] AS a
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        WHERE   a.Deleted = 0 AND (@Id IS NULL OR a.EmployeeId = @Id)
          AND   [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1
        ORDER BY a.EmployeeId, a.EffectiveFrom;
        RETURN;
    END;

    IF @Action = 'SET'
    BEGIN
        DECLARE @Rows TABLE (EmployeeId BIGINT PRIMARY KEY, DeviceUserId NVARCHAR(30), SetDevice BIT, PatternId INT, EffectiveFrom DATE);
        INSERT INTO @Rows (EmployeeId, DeviceUserId, SetDevice, PatternId, EffectiveFrom)
        SELECT  j.EmployeeId, NULLIF(LTRIM(RTRIM(j.DeviceUserId)), N''), ISNULL(j.SetDevice, 0), j.PatternId, j.EffectiveFrom
        FROM    OPENJSON(ISNULL(@Json, N'[]'))
                WITH (EmployeeId BIGINT '$.employeeId', DeviceUserId NVARCHAR(30) '$.deviceUserId', SetDevice BIT '$.setDevice',
                      PatternId INT '$.patternId', EffectiveFrom DATE '$.effectiveFrom') AS j
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = j.EmployeeId AND e.Deleted = 0
        WHERE   [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1;

        /* a pattern must belong to the employee's company */
        IF EXISTS (SELECT 1 FROM @Rows r JOIN [Employee].[Employees] e ON e.EmployeeId = r.EmployeeId
                   LEFT JOIN [Attendance].[Patterns] p ON p.PatternId = r.PatternId AND p.Deleted = 0
                   WHERE r.PatternId IS NOT NULL AND (p.PatternId IS NULL OR p.CompanyId <> e.CompanyId))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A pattern can only be assigned to employees of its own company.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            MERGE [Attendance].[EmployeeSettings] AS t
            USING (SELECT EmployeeId, DeviceUserId FROM @Rows WHERE SetDevice = 1) AS s ON t.EmployeeId = s.EmployeeId
            WHEN MATCHED THEN UPDATE SET DeviceUserId = s.DeviceUserId, ModifiedBy = @UserId, ModifiedDate = @Now, Deleted = 0
            WHEN NOT MATCHED THEN INSERT (EmployeeId, DeviceUserId, ModifiedBy) VALUES (s.EmployeeId, s.DeviceUserId, @UserId);

            /* the same date replaces the assignment of that date */
            UPDATE a SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
            FROM   [Attendance].[EmployeePatterns] AS a
            JOIN   @Rows AS r ON r.EmployeeId = a.EmployeeId AND r.PatternId IS NOT NULL
                             AND a.EffectiveFrom = ISNULL(r.EffectiveFrom, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1))
            WHERE  a.Deleted = 0;

            INSERT INTO [Attendance].[EmployeePatterns] (EmployeeId, PatternId, EffectiveFrom, CreatedBy)
            SELECT r.EmployeeId, r.PatternId, ISNULL(r.EffectiveFrom, DATEFROMPARTS(YEAR(@Today), MONTH(@Today), 1)), @UserId
            FROM   @Rows AS r
            WHERE  r.PatternId IS NOT NULL
              AND  NOT EXISTS (SELECT 1 FROM [Attendance].[EmployeePatterns] AS a
                               WHERE a.EmployeeId = r.EmployeeId AND a.Deleted = 0
                                 AND a.EffectiveFrom = (SELECT MAX(b.EffectiveFrom) FROM [Attendance].[EmployeePatterns] AS b
                                                        WHERE b.EmployeeId = r.EmployeeId AND b.Deleted = 0
                                                          AND b.EffectiveFrom <= ISNULL(r.EffectiveFrom, @Today))
                                 AND a.PatternId = r.PatternId);
        COMMIT TRANSACTION;
        SELECT @TotalCount = COUNT(1) FROM @Rows;
        SET @ResultMessage = CONCAT(N'Saved for ', @TotalCount, CASE WHEN @TotalCount = 1 THEN N' employee.' ELSE N' employees.' END);
        RETURN;
    END;

    IF @Action = 'UNASSIGN'
    BEGIN
        UPDATE a SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Attendance].[EmployeePatterns] AS a
        JOIN   [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        WHERE  a.AssignmentId = @Id AND a.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](e.CompanyId, @CompanyId, @CompanyIds) = 1;
        SET @ResultMessage = N'Assignment removed.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- 4. Attendance.usp_AttImport_Manage -----------------------------------
     SAVE    a file: @Json [{employeeId, companyId, workDate, clockIn, clockOut, punches}]
             replaces the employee's day; returns the months touched (CompanyId, Month)
     LIST    the files imported (newest first)
     DELETE  removes a file's days (refused for a month already posted); returns the months
   -------------------------------------------------------------------------- */
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
                   AND p.RunMonth = DATEFROMPARTS(YEAR(i.WorkDate), MONTH(i.WorkDate), 1))
        BEGIN
            DECLARE @Posted NVARCHAR(200) = (SELECT STRING_AGG(m, N', ') FROM (SELECT DISTINCT FORMAT(p.RunMonth, 'MMM yyyy', 'en-US') AS m
                FROM @In i JOIN [Attendance].[Postings] p ON p.EmployeeId = i.EmployeeId AND p.Deleted = 0
                AND p.RunMonth = DATEFROMPARTS(YEAR(i.WorkDate), MONTH(i.WorkDate), 1)) AS x);
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

        SELECT DISTINCT i.CompanyId, DATEFROMPARTS(YEAR(i.WorkDate), MONTH(i.WorkDate), 1) AS RunMonth FROM @In AS i;
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
                   AND p.RunMonth = DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1)
                   WHERE r.ImportId = @Id AND r.Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'POSTED', @ResultMessage = N'Days of this file are already posted to the payroll - undo the posting first.';
            RETURN;
        END;
        DECLARE @Months TABLE (CompanyId INT, RunMonth DATE);
        INSERT INTO @Months SELECT DISTINCT r.CompanyId, DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1)
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

/* ---- 5. Attendance.usp_AttRecord_Manage ----------------------------------
     CTX_RECORDS  the days of a company and month (for the calculation)
     CTX_EMP      the employees of the company with a pattern or a day that month: salary, hire / leaving
     CTX_LEAVE    approved leave days in the month;  CTX_HOLIDAY  public holidays in the month
     SAVE_CALC    @Json results: updates the days, adds / removes the days worked out (absent, leave ...)
     LIST         the days (filters, paging);  KPIS  the month's figures
     GET / EDIT   one day: clock in / out, excused, note (the original times are kept)
   -------------------------------------------------------------------------- */
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
    DECLARE @From DATE = DATEFROMPARTS(YEAR(ISNULL(@Month, GETDATE())), MONTH(ISNULL(@Month, GETDATE())), 1);
    DECLARE @To DATE = EOMONTH(@From);
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
                               AND ps.RunMonth = DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1)) THEN 1 ELSE 0 END AS BIT) AS IsPosted
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
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@FilterCompany IS NULL OR r.CompanyId = @FilterCompany)
          AND  (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId);
        RETURN;
    END;

    IF @Action = 'MONTHS'
    BEGIN
        SELECT DISTINCT DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1) AS RunMonth
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
                   AND p.RunMonth = DATEFROMPARTS(YEAR(r.WorkDate), MONTH(r.WorkDate), 1) WHERE r.RecordId = @Id)
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
        SELECT CompanyId, DATEFROMPARTS(YEAR(WorkDate), MONTH(WorkDate), 1) AS RunMonth, EmployeeId FROM [Attendance].[Records] WHERE RecordId = @Id;
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
                   AND p.RunMonth = DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1))
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
        SELECT @Co AS CompanyId, DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) AS RunMonth, @EmployeeId AS EmployeeId;
        SET @ResultMessage = N'Day saved.';
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- 6. Attendance.usp_AttSummary_Manage ---------------------------------
     LIST    the month per employee (company): days, late, short, absent, overtime, deduction, posted
     POST    @Json [{employeeId, deduction, overtime}] -> one-time pay items of the month
     UNPOST  takes the month's posting back (refused once a closed payroll used it)
   -------------------------------------------------------------------------- */
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
                     WHERE a.EmployeeId = e.EmployeeId AND a.Deleted = 0 AND a.EffectiveFrom <= @To ORDER BY a.EffectiveFrom DESC) AS pat
        LEFT JOIN [Attendance].[Postings] AS ps ON ps.EmployeeId = e.EmployeeId AND ps.RunMonth = @From AND ps.Deleted = 0
        LEFT JOIN [Security].[Users] AS u ON u.UserId = ps.PostedBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   r.Deleted = 0 AND r.CompanyId = @FilterCompany AND r.WorkDate BETWEEN @From AND @To
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

/* ---- 7. rights (first run: from the Deductions rights) -------------------- */
IF OBJECT_ID('tempdb..#AttCodes') IS NOT NULL DROP TABLE #AttCodes;
CREATE TABLE #AttCodes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                        Action VARCHAR(30) COLLATE DATABASE_DEFAULT, FromCode VARCHAR(60) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #AttCodes (PermissionCode, Module, Action, FromCode)
VALUES ('ATTENDANCE_VIEW', 'Attendance', 'VIEW', 'PAYROLL_DED_VIEW'),
       ('ATTENDANCE_IMPORT', 'Attendance', 'IMPORT', 'PAYROLL_DED_EDIT'),
       ('ATTENDANCE_POST', 'Attendance', 'POST', 'PAYROLL_DED_EDIT'),
       ('ATTENDANCE_SETUP_VIEW', 'AttendanceSetup', 'VIEW', 'PAYROLL_SETUP_VIEW'),
       ('ATTENDANCE_SETUP_EDIT', 'AttendanceSetup', 'EDIT', 'PAYROLL_SETUP_EDIT');

UPDATE c SET IsNew = 1 FROM #AttCodes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #AttCodes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT r.RoleId, p.PermissionId
FROM   #AttCodes c
JOIN   [Security].[Permissions] p ON p.PermissionCode = c.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] r ON r.Deleted = 0
WHERE  c.IsNew = 1
  AND (r.RoleCode = N'SYSADMIN'
       OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                  WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = c.FromCode))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @AttGranted INT = @@ROWCOUNT;
DECLARE @AttCreated INT = (SELECT COUNT(1) FROM #AttCodes WHERE IsNew = 1);
PRINT CONCAT(N'Attendance rights created: ', @AttCreated, N', granted: ', @AttGranted);
DROP TABLE #AttCodes;
GO

/* ---- 8. labels (English + Arabic) ------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('sec.mod_attendance', 'sec', N'Time & Attendance', N'الوقت والحضور', NULL),
        ('sec.pg_attendance', 'sec', N'Attendance', N'الحضور', NULL),
        ('sec.pg_attendance_hint', 'sec', N'Read: the days and the month. Write: import the device report, correct days, assign patterns.', N'قراءة: الأيام والشهر. كتابة: استيراد تقرير الجهاز وتصحيح الأيام وتعيين الأنماط.', NULL),
        ('sec.fn_attendance_post', 'sec', N'Post to payroll', N'الترحيل إلى الرواتب', NULL),
        ('sec.fn_attendance_post_hint', 'sec', N'Posts the month''s attendance deductions and overtime to the payroll.', N'يرحّل خصومات الحضور والعمل الإضافي للشهر إلى الرواتب.', NULL),
        ('sec.pg_attendance_settings', 'sec', N'Attendance settings', N'إعدادات الحضور', NULL),
        ('sec.pg_attendance_settings_hint', 'sec', N'The attendance patterns: working hours, shifts and deduction rules.', N'أنماط الحضور: ساعات العمل والورديات وقواعد الخصم.', NULL),

        ('att.nav_attendance', 'att', N'Attendance', N'الحضور', NULL),
        ('att.nav_import', 'att', N'Import', N'الاستيراد', NULL),
        ('att.nav_summary', 'att', N'Monthly Summary', N'الملخص الشهري', NULL),
        ('att.nav_employees', 'att', N'Employees & Patterns', N'الموظفون والأنماط', NULL),
        ('att.nav_settings', 'att', N'Attendance Settings', N'إعدادات الحضور', NULL),

        ('att.register_subtitle', 'att', N'Every employee''s day - clock in / out, late, short hours, overtime and the deduction.', N'يوم كل موظف - الدخول والخروج والتأخير ونقص الساعات والعمل الإضافي والخصم.', NULL),
        ('att.import_subtitle', 'att', N'Import the fingerprint device''s report - the columns and the employees are found for you to check.', N'استيراد تقرير جهاز البصمة - تُكتشف الأعمدة والموظفون لتراجعها.', NULL),
        ('att.summary_subtitle', 'att', N'Each employee''s month - posted to the payroll as one-time pay items.', N'شهر كل موظف - يُرحّل إلى الرواتب كبنود لمرة واحدة.', NULL),
        ('att.employees_subtitle', 'att', N'Each employee''s ID on the device and the attendance pattern they work by.', N'رقم كل موظف على الجهاز ونمط الحضور الذي يعمل به.', NULL),
        ('att.settings_subtitle', 'att', N'Working hours / shifts and their deduction rules.', N'ساعات العمل / الورديات وقواعد الخصم.', NULL),

        ('att.kpi_present', 'att', N'Days present', N'أيام الحضور', NULL),
        ('att.kpi_present_note', 'att', N'{0} employees · {1} – {2}', N'{0} موظف · {1} – {2}', NULL),
        ('att.kpi_late_short', 'att', N'Late / short days', N'أيام التأخير / النقص', NULL),
        ('att.kpi_late_short_note', 'att', N'Late {0} · short {1} (h:mm)', N'تأخير {0} · نقص {1} (س:د)', NULL),
        ('att.kpi_absent', 'att', N'Absent days', N'أيام الغياب', NULL),
        ('att.kpi_review_note', 'att', N'{0} to review (one punch, no pattern)', N'{0} للمراجعة (بصمة واحدة، بدون نمط)', NULL),
        ('att.kpi_deduction', 'att', N'Deductions (KWD)', N'الخصومات (د.ك)', NULL),
        ('att.kpi_overtime_note', 'att', N'Overtime KWD {0} · {1} h', N'عمل إضافي {0} د.ك · {1} س', NULL),

        ('att.all_companies', 'att', N'All companies', N'كل الشركات', NULL),
        ('att.all_days', 'att', N'All days', N'كل الأيام', NULL),
        ('att.f_issues', 'att', N'To act on (late, short, absent, review)', N'تحتاج إجراء (تأخير، نقص، غياب، مراجعة)', NULL),
        ('att.f_deducted', 'att', N'With a deduction', N'بها خصم', NULL),
        ('att.f_late', 'att', N'Late', N'تأخير', NULL),
        ('att.f_short', 'att', N'Short hours', N'نقص ساعات', NULL),
        ('att.f_overtime', 'att', N'Overtime', N'عمل إضافي', NULL),
        ('att.search_employee', 'att', N'Search employee, number, department', N'ابحث بالموظف أو الرقم أو القسم', NULL),

        ('att.st_present', 'att', N'Present', N'حاضر', NULL),
        ('att.st_late', 'att', N'Late', N'متأخر', NULL),
        ('att.st_short', 'att', N'Short hours', N'نقص ساعات', NULL),
        ('att.st_late_short', 'att', N'Late & short', N'تأخير ونقص', NULL),
        ('att.st_absent', 'att', N'Absent', N'غائب', NULL),
        ('att.st_off', 'att', N'Day off', N'يوم راحة', NULL),
        ('att.st_holiday', 'att', N'Holiday', N'عطلة', NULL),
        ('att.st_leave', 'att', N'On leave', N'في إجازة', NULL),
        ('att.st_missing', 'att', N'One punch', N'بصمة واحدة', NULL),
        ('att.st_excused', 'att', N'Excused', N'معذور', NULL),
        ('att.st_no_pattern', 'att', N'No pattern', N'بدون نمط', NULL),
        ('att.no_punch', 'att', N'No punch in the file', N'لا بصمة في الملف', NULL),

        ('att.col_employee', 'att', N'Employee', N'الموظف', NULL),
        ('att.col_date', 'att', N'Date', N'التاريخ', NULL),
        ('att.col_in', 'att', N'In', N'دخول', NULL),
        ('att.col_out', 'att', N'Out', N'خروج', NULL),
        ('att.col_worked', 'att', N'Worked', N'العمل', NULL),
        ('att.col_late', 'att', N'Late', N'تأخير', NULL),
        ('att.col_short', 'att', N'Short', N'نقص', NULL),
        ('att.col_overtime', 'att', N'Overtime', N'إضافي', NULL),
        ('att.col_deduction', 'att', N'Deduction', N'الخصم', NULL),
        ('att.col_pattern', 'att', N'Pattern', N'النمط', NULL),
        ('att.col_payroll', 'att', N'Payroll', N'الرواتب', NULL),
        ('att.col_device_id', 'att', N'Device ID', N'رقم الجهاز', NULL),
        ('att.col_salary', 'att', N'Basic (+ allowances)', N'الأساسي (+ البدلات)', NULL),
        ('att.col_file', 'att', N'File', N'الملف', NULL),
        ('att.col_imported_by', 'att', N'Imported by', N'استورده', NULL),
        ('att.col_id', 'att', N'ID in the file', N'الرقم في الملف', NULL),
        ('att.col_name_file', 'att', N'Name in the file', N'الاسم في الملف', NULL),
        ('att.col_matched_by', 'att', N'Matched by', N'طريقة المطابقة', NULL),
        ('att.col_column', 'att', N'Column', N'العمود', NULL),
        ('att.col_sample', 'att', N'First value', N'أول قيمة', NULL),
        ('att.col_read_as', 'att', N'Read as', N'يُقرأ كـ', NULL),
        ('att.ot_short', 'att', N'OT', N'إضافي', NULL),
        ('att.1_day', 'att', N'1 day', N'يوم واحد', NULL),
        ('att.0_days', 'att', N'{0} days', N'{0} يوم', NULL),
        ('att.no_days_match', 'att', N'No day matches the filters', N'لا يوجد يوم يطابق التصفية', NULL),
        ('att.no_days_yet', 'att', N'No attendance for this month yet', N'لا يوجد حضور لهذا الشهر بعد', NULL),
        ('att.no_days_text', 'att', N'Import the fingerprint device''s report - the days are worked out from each employee''s pattern.', N'استورد تقرير جهاز البصمة - تُحسب الأيام من نمط كل موظف.', NULL),
        ('att.edit_day', 'att', N'Change the day', N'تعديل اليوم', NULL),
        ('att.edited_by_0', 'att', N'Changed by {0}', N'عدّله {0}', NULL),
        ('att.posted_locked', 'att', N'Posted to the payroll - take the posting back to change it', N'مرحّل إلى الرواتب - ألغِ الترحيل لتعديله', NULL),
        ('att.add_day', 'att', N'Add a day', N'إضافة يوم', NULL),
        ('att.add_day_hint', 'att', N'A day the device missed', N'يوم لم يسجله الجهاز', NULL),
        ('att.recalculate', 'att', N'Work out again', N'إعادة الحساب', NULL),
        ('att.recalculate_hint', 'att', N'After a change of a pattern, an assignment, a salary or a leave', N'بعد تغيير نمط أو تعيين أو راتب أو إجازة', NULL),
        ('att.import', 'att', N'Import attendance', N'استيراد الحضور', NULL),
        ('att.select_employee', 'att', N'Select the employee', N'اختر الموظف', NULL),
        ('att.device_0', 'att', N'Device: {0}', N'الجهاز: {0}', NULL),
        ('att.times_hint', 'att', N'A clock out before the clock in is the next day (a night shift).', N'الخروج قبل الدخول يعني اليوم التالي (وردية ليلية).', NULL),
        ('att.excused', 'att', N'Excused', N'معذور', NULL),
        ('att.excused_hint', 'att', N'- no deduction for this day (permission, mission, sick note ...).', N'- لا خصم لهذا اليوم (استئذان، مهمة، عذر طبي ...).', NULL),
        ('att.note_placeholder', 'att', N'Why it was changed - kept with the day', N'سبب التعديل - يُحفظ مع اليوم', NULL),

        ('att.drop_title', 'att', N'Drop the device''s report here', N'أفلت تقرير الجهاز هنا', NULL),
        ('att.drop_text', 'att', N'Excel (.xlsx) or CSV, in English or Arabic - a row per day or a row per punch.', N'إكسل (.xlsx) أو CSV، بالعربية أو الإنجليزية - صف لكل يوم أو صف لكل بصمة.', NULL),
        ('att.choose_file', 'att', N'Choose the file', N'اختر الملف', NULL),
        ('att.how_title', 'att', N'How it reads the file', N'كيف يُقرأ الملف', NULL),
        ('att.how_1', 'att', N'The columns are found from their titles (English or Arabic) and checked against their values - a file without titles is read from its values.', N'تُكتشف الأعمدة من عناوينها (عربية أو إنجليزية) وتُطابق مع قيمها - والملف بدون عناوين يُقرأ من قيمه.', NULL),
        ('att.how_2', 'att', N'A row per day (number, date, in, out) or a row per punch (number, date-time, check-in / out): the first punch is the clock in, the last the clock out.', N'صف لكل يوم (الرقم، التاريخ، الدخول، الخروج) أو صف لكل بصمة: أول بصمة دخول وآخر بصمة خروج.', NULL),
        ('att.how_3', 'att', N'The IDs are matched to employees by their device ID, employee number or name - the rest you link once and it is remembered.', N'تُطابق الأرقام مع الموظفين برقم الجهاز أو الرقم الوظيفي أو الاسم - والباقي تربطه مرة ويُحفظ.', NULL),
        ('att.how_4', 'att', N'Importing a day again replaces it; the totals and hours the device worked out are not used - each day is worked out from the employee''s pattern.', N'استيراد اليوم مرة أخرى يستبدله؛ ولا تُستخدم مجاميع الجهاز - يُحسب كل يوم من نمط الموظف.', NULL),
        ('att.format_paired', 'att', N'A row per employee and day', N'صف لكل موظف ويوم', NULL),
        ('att.format_punch', 'att', N'A row per punch', N'صف لكل بصمة', NULL),
        ('att.other_file', 'att', N'Another file', N'ملف آخر', NULL),
        ('att.p_rows', 'att', N'Rows', N'الصفوف', NULL),
        ('att.p_days', 'att', N'Days', N'الأيام', NULL),
        ('att.p_period', 'att', N'Period', N'الفترة', NULL),
        ('att.p_employees', 'att', N'Employees', N'الموظفون', NULL),
        ('att.p_skipped', 'att', N'Rows skipped', N'صفوف متجاوزة', NULL),
        ('att.p_problem', 'att', N'The file could not be read yet.', N'تعذّرت قراءة الملف بعد.', NULL),
        ('att.p_problem_fix', 'att', N'Choose below what each column holds.', N'اختر أدناه ما يحويه كل عمود.', NULL),
        ('att.columns_title', 'att', N'Columns found', N'الأعمدة المكتشفة', NULL),
        ('att.columns_text', 'att', N'Change what a column is read as - the file is read again.', N'غيّر قراءة العمود - يُعاد قراءة الملف.', NULL),
        ('att.skipped_rows', 'att', N'Rows skipped and why', N'الصفوف المتجاوزة وسببها', NULL),
        ('att.sample_title', 'att', N'First days read', N'أول الأيام المقروءة', NULL),
        ('att.sample_text', 'att', N'Check the dates and times are right.', N'تحقق من صحة التواريخ والأوقات.', NULL),
        ('att.people_title', 'att', N'Employees in the file', N'الموظفون في الملف', NULL),
        ('att.people_text', 'att', N'Link an ID that was not matched, or leave it out.', N'اربط الرقم غير المطابق أو اتركه.', NULL),
        ('att.remember_links', 'att', N'Remember the links as the employees'' device IDs', N'احفظ الربط كأرقام الجهاز للموظفين', NULL),
        ('att.import_0_days', 'att', N'Import {0} days', N'استيراد {0} يوم', NULL),
        ('att.role_none', 'att', N'Not used', N'غير مستخدم', NULL),
        ('att.role_employeeid', 'att', N'Employee number / ID', N'رقم الموظف', NULL),
        ('att.role_name', 'att', N'Name', N'الاسم', NULL),
        ('att.role_date', 'att', N'Date', N'التاريخ', NULL),
        ('att.role_clockin', 'att', N'Clock in', N'وقت الدخول', NULL),
        ('att.role_clockout', 'att', N'Clock out', N'وقت الخروج', NULL),
        ('att.role_datetime', 'att', N'Punch date & time', N'تاريخ ووقت البصمة', NULL),
        ('att.role_time', 'att', N'Punch time', N'وقت البصمة', NULL),
        ('att.role_state', 'att', N'Check-in / out', N'دخول / خروج', NULL),
        ('att.role_weekday', 'att', N'Day name', N'اسم اليوم', NULL),
        ('att.role_department', 'att', N'Department', N'القسم', NULL),
        ('att.role_total', 'att', N'Device totals (not used)', N'مجاميع الجهاز (غير مستخدمة)', NULL),
        ('att.by_header', 'att', N'from its title', N'من عنوانه', NULL),
        ('att.by_data', 'att', N'from its values', N'من قيمه', NULL),
        ('att.by_chosen', 'att', N'chosen', N'مختار', NULL),
        ('att.by_none', 'att', N'not recognised', N'غير معروف', NULL),
        ('att.m_device', 'att', N'Device ID', N'رقم الجهاز', NULL),
        ('att.m_number', 'att', N'Employee number', N'الرقم الوظيفي', NULL),
        ('att.m_name', 'att', N'Name', N'الاسم', NULL),
        ('att.m_chosen', 'att', N'Linked here', N'رُبط هنا', NULL),
        ('att.m_none', 'att', N'Not found', N'غير موجود', NULL),
        ('att.m_ambiguous', 'att', N'Several employees', N'أكثر من موظف', NULL),
        ('att.leave_out', 'att', N'Leave out', N'استبعاد', NULL),
        ('att.link_employee', 'att', N'link another', N'اربط بآخر', NULL),
        ('att.n_of_m', 'att', N'{0} of {1} matched', N'{0} من {1} مطابق', NULL),
        ('att.n_unmatched', 'att', N'{0} to link', N'{0} للربط', NULL),
        ('att.imports_title', 'att', N'Files imported', N'الملفات المستوردة', NULL),
        ('att.1_file', 'att', N'1 file', N'ملف واحد', NULL),
        ('att.0_files', 'att', N'{0} files', N'{0} ملفات', NULL),
        ('att.no_imports', 'att', N'No file imported yet', N'لم يُستورد أي ملف بعد', NULL),
        ('att.no_imports_text', 'att', N'The device reports imported are listed here.', N'تظهر هنا تقارير الجهاز المستوردة.', NULL),
        ('att.0_skipped', 'att', N'{0} rows skipped', N'{0} صف متجاوز', NULL),
        ('att.of_0', 'att', N'of {0}', N'من {0}', NULL),
        ('att.replaced_hint', 'att', N'Some days were replaced by a later file or by hand.', N'استُبدلت بعض الأيام بملف لاحق أو يدوياً.', NULL),
        ('att.open_days', 'att', N'Open the days', N'فتح الأيام', NULL),
        ('att.delete_import', 'att', N'Remove the file''s days', N'حذف أيام الملف', NULL),
        ('att.delete_import_text', 'att', N'The days of this file are removed and the month is worked out again.', N'تُحذف أيام هذا الملف ويُعاد حساب الشهر.', NULL),

        ('att.1_employee', 'att', N'1 employee', N'موظف واحد', NULL),
        ('att.0_employees', 'att', N'{0} employees', N'{0} موظف', NULL),
        ('att.present', 'att', N'Present', N'حضور', NULL),
        ('att.absent', 'att', N'Absent', N'غياب', NULL),
        ('att.leave', 'att', N'Leave', N'إجازة', NULL),
        ('att.late_days', 'att', N'Late days', N'أيام التأخير', NULL),
        ('att.short_days', 'att', N'Short days', N'أيام النقص', NULL),
        ('att.late_hm', 'att', N'Late (h:mm)', N'التأخير (س:د)', NULL),
        ('att.short_hm', 'att', N'Short (h:mm)', N'النقص (س:د)', NULL),
        ('att.overtime_hm', 'att', N'Overtime (h:mm)', N'الإضافي (س:د)', NULL),
        ('att.to_review', 'att', N'To review', N'للمراجعة', NULL),
        ('att.0_to_review', 'att', N'{0} to review', N'{0} للمراجعة', NULL),
        ('att.deduction_kwd', 'att', N'Deduction (KWD)', N'الخصم (د.ك)', NULL),
        ('att.overtime_kwd', 'att', N'Overtime (KWD)', N'الإضافي (د.ك)', NULL),
        ('att.posted', 'att', N'Posted', N'مرحّل', NULL),
        ('att.not_posted', 'att', N'Not posted', N'غير مرحّل', NULL),
        ('att.changed', 'att', N'Changed since posted', N'تغيّر بعد الترحيل', NULL),
        ('att.posted_0_1', 'att', N'Posted: deduction {0}, overtime {1}', N'المرحّل: خصم {0}، إضافي {1}', NULL),
        ('att.posted_title', 'att', N'Posted to the payroll.', N'مرحّل إلى الرواتب.', NULL),
        ('att.posted_text', 'att', N'The deductions and overtime are one-time pay items of the month - recalculate the payroll if it is already created.', N'الخصومات والإضافي بنود لمرة واحدة للشهر - أعد حساب الرواتب إن كانت منشأة.', NULL),
        ('att.posted_changed_title', 'att', N'The month changed since it was posted.', N'تغيّر الشهر بعد ترحيله.', NULL),
        ('att.posted_changed_text', 'att', N'Post it again so the payroll has the latest figures.', N'رحّله مرة أخرى لتحصل الرواتب على أحدث الأرقام.', NULL),
        ('att.review_title', 'att', N'{0} days to review.', N'{0} يوم للمراجعة.', NULL),
        ('att.review_text', 'att', N'Days with one punch or with no pattern carry no deduction until they are corrected.', N'الأيام ذات البصمة الواحدة أو بدون نمط لا خصم عليها حتى تُصحح.', NULL),
        ('att.review_link', 'att', N'Open them', N'افتحها', NULL),
        ('att.no_pattern', 'att', N'No pattern', N'بدون نمط', NULL),
        ('att.summary_sheet', 'att', N'Attendance', N'الحضور', NULL),
        ('att.summary_hint', 'att', N'Posting creates the pay items "Attendance deduction" and "Overtime (attendance)" of the month; posting again replaces them until the month''s payroll is approved.', N'الترحيل ينشئ بندي "خصم الحضور" و"العمل الإضافي (الحضور)" للشهر؛ وإعادة الترحيل تستبدلهما حتى اعتماد رواتب الشهر.', NULL),
        ('att.post', 'att', N'Post to payroll', N'ترحيل إلى الرواتب', NULL),
        ('att.post_again', 'att', N'Post again', N'إعادة الترحيل', NULL),
        ('att.post_title', 'att', N'Post the month to the payroll?', N'ترحيل الشهر إلى الرواتب؟', NULL),
        ('att.post_text_0_1', 'att', N'Deductions KWD {0} and overtime KWD {1} become one-time pay items of the month.', N'تصبح الخصومات {0} د.ك والإضافي {1} د.ك بنوداً لمرة واحدة للشهر.', NULL),
        ('att.unpost', 'att', N'Take the posting back', N'إلغاء الترحيل', NULL),

        ('att.employees_hint', 'att', N'The device ID is only needed when the device does not use the employee number. A new pattern applies from its date; earlier days keep the pattern they had.', N'رقم الجهاز مطلوب فقط إذا لم يستخدم الجهاز الرقم الوظيفي. النمط الجديد يسري من تاريخه؛ والأيام السابقة تبقى على نمطها.', NULL),
        ('att.all_patterns', 'att', N'All patterns', N'كل الأنماط', NULL),
        ('att.choose_pattern', 'att', N'Choose the pattern', N'اختر النمط', NULL),
        ('att.1_selected', 'att', N'1 employee selected', N'موظف واحد محدد', NULL),
        ('att.0_selected', 'att', N'{0} employees selected', N'{0} موظف محدد', NULL),
        ('att.from', 'att', N'From', N'من', NULL),
        ('att.from_0', 'att', N'From {0}', N'من {0}', NULL),
        ('att.since_0', 'att', N'Since {0}', N'منذ {0}', NULL),
        ('att.assign', 'att', N'Assign', N'تعيين', NULL),
        ('att.select_all', 'att', N'Select all', N'تحديد الكل', NULL),
        ('att.no_employees', 'att', N'No employee matches', N'لا يوجد موظف مطابق', NULL),
        ('att.device_saved', 'att', N'Device ID saved.', N'تم حفظ رقم الجهاز.', NULL),
        ('att.pattern_other_company', 'att', N'The pattern belongs to another company than some employees selected.', N'النمط يتبع شركة أخرى غير بعض الموظفين المحددين.', NULL),
        ('att.no_patterns_title', 'att', N'No attendance pattern yet', N'لا يوجد نمط حضور بعد', NULL),
        ('att.no_patterns_text', 'att', N'Add the working hours / shifts and their deduction rules, then assign them to the employees.', N'أضف ساعات العمل / الورديات وقواعد الخصم ثم عيّنها للموظفين.', NULL),
        ('att.no_patterns_match', 'att', N'No pattern matches', N'لا يوجد نمط مطابق', NULL),

        ('att.settings_banner_title', 'att', N'How a day is worked out.', N'كيف يُحسب اليوم.', NULL),
        ('att.settings_banner_text', 'att', N'Late = clock in after the shift start beyond the grace minutes. Short hours = the required hours not worked (the break is taken off). Each is priced by its slabs - with no slab the minutes are deducted pro rata. A day''s pay = the salary / the day divisor.', N'التأخير = الدخول بعد بداية الوردية بأكثر من دقائق السماح. نقص الساعات = الساعات المطلوبة غير المعمولة (بعد خصم الاستراحة). يُسعّر كل منهما حسب شرائحه - وبدون شرائح تُخصم الدقائق نسبياً. أجر اليوم = الراتب / قاسم الأيام.', NULL),
        ('att.add_pattern', 'att', N'Add pattern', N'إضافة نمط', NULL),
        ('att.edit_pattern', 'att', N'Edit pattern', N'تعديل النمط', NULL),
        ('att.delete_pattern_text', 'att', N'Delete this pattern? It can only be deleted while no employee is assigned to it.', N'حذف هذا النمط؟ لا يُحذف إلا إذا لم يُعيّن لأي موظف.', NULL),
        ('att.search_patterns', 'att', N'Search patterns', N'ابحث في الأنماط', NULL),
        ('att.1_pattern', 'att', N'1 pattern', N'نمط واحد', NULL),
        ('att.0_patterns', 'att', N'{0} patterns', N'{0} أنماط', NULL),
        ('att.type_fixed', 'att', N'Fixed shift', N'وردية ثابتة', NULL),
        ('att.type_fixed_hint', 'att', N'A start and end time: late arrival and short hours count.', N'وقت بداية ونهاية: يُحسب التأخير ونقص الساعات.', NULL),
        ('att.type_flexible', 'att', N'Flexible hours', N'ساعات مرنة', NULL),
        ('att.type_flexible_hint', 'att', N'Any time of the day: only the minimum working hours count.', N'أي وقت من اليوم: يُحسب الحد الأدنى من ساعات العمل فقط.', NULL),
        ('att.required_0', 'att', N'{0} h a day', N'{0} س يومياً', NULL),
        ('att.grace_0', 'att', N'{0} min grace', N'{0} د سماح', NULL),
        ('att.off_0', 'att', N'off {0}', N'راحة {0}', NULL),
        ('att.off', 'att', N'Off', N'متوقف', NULL),
        ('att.rule_late', 'att', N'Late arrival', N'التأخير', NULL),
        ('att.rule_short', 'att', N'Short hours', N'نقص الساعات', NULL),
        ('att.rule_absent', 'att', N'Absence', N'الغياب', NULL),
        ('att.rule_overtime', 'att', N'Overtime', N'العمل الإضافي', NULL),
        ('att.rule_pay', 'att', N'A day''s pay', N'أجر اليوم', NULL),
        ('att.pro_rata', 'att', N'pro rata', N'نسبياً', NULL),
        ('att.pro_rata_minutes', 'att', N'The minutes, pro rata', N'الدقائق نسبياً', NULL),
        ('att.of_day', 'att', N'of a day', N'من اليوم', NULL),
        ('att.free_lates_0', 'att', N'First {0} late days a month free', N'أول {0} أيام تأخير شهرياً مجانية', NULL),
        ('att.absent_0_days', 'att', N'{0} day''s pay', N'أجر {0} يوم', NULL),
        ('att.ot_0_1', 'att', N'After {0} min, x{1}', N'بعد {0} د، ×{1}', NULL),
        ('att.day_pay_0_1', 'att', N'{0} / {1}', N'{0} / {1}', NULL),
        ('att.cap_0', 'att', N'Capped at {0} a month', N'بحد أقصى {0} شهرياً', NULL),
        ('att.basis_basic', 'att', N'Basic salary', N'الراتب الأساسي', NULL),
        ('att.basis_gross', 'att', N'Basic + allowances', N'الأساسي + البدلات', NULL),
        ('att.missing_flag', 'att', N'One punch: to review (no deduction)', N'بصمة واحدة: للمراجعة (بدون خصم)', NULL),
        ('att.missing_ignore', 'att', N'One punch: counts as present', N'بصمة واحدة: تُحسب حضوراً', NULL),
        ('att.missing_half_day', 'att', N'One punch: half a day''s pay', N'بصمة واحدة: نصف أجر يوم', NULL),
        ('att.missing_absent', 'att', N'One punch: counts as absent', N'بصمة واحدة: تُحسب غياباً', NULL),

        ('att.pattern', 'att', N'Pattern', N'النمط', NULL),
        ('att.name_placeholder', 'att', N'Day shift 10:00 - 22:00', N'وردية نهارية 10:00 - 22:00', NULL),
        ('att.type', 'att', N'Type', N'النوع', NULL),
        ('att.hours', 'att', N'Working hours', N'ساعات العمل', NULL),
        ('att.shift_start', 'att', N'Shift start', N'بداية الوردية', NULL),
        ('att.shift_end', 'att', N'Shift end', N'نهاية الوردية', NULL),
        ('att.required_hours', 'att', N'Required hours a day', N'الساعات المطلوبة يومياً', NULL),
        ('att.required_hint', 'att', N'h:mm (11:30). Empty: the shift less the break.', N'س:د (11:30). فارغ: الوردية ناقص الاستراحة.', NULL),
        ('att.break_minutes', 'att', N'Break (minutes)', N'الاستراحة (دقائق)', NULL),
        ('att.break_hint', 'att', N'Taken off the time between clock in and out.', N'تُخصم من الوقت بين الدخول والخروج.', NULL),
        ('att.grace_minutes', 'att', N'Grace (minutes)', N'السماح (دقائق)', NULL),
        ('att.grace_hint', 'att', N'Late or short within it: nothing counts.', N'التأخير أو النقص ضمنه: لا يُحسب.', NULL),
        ('att.weekly_off', 'att', N'Weekly days off', N'أيام الراحة الأسبوعية', NULL),
        ('att.weekly_off_hint', 'att', N'No absence on these days; work on them is overtime.', N'لا غياب في هذه الأيام؛ والعمل فيها إضافي.', NULL),
        ('att.d_sat', 'att', N'Sat', N'السبت', NULL),
        ('att.d_sun', 'att', N'Sun', N'الأحد', NULL),
        ('att.d_mon', 'att', N'Mon', N'الاثنين', NULL),
        ('att.d_tue', 'att', N'Tue', N'الثلاثاء', NULL),
        ('att.d_wed', 'att', N'Wed', N'الأربعاء', NULL),
        ('att.d_thu', 'att', N'Thu', N'الخميس', NULL),
        ('att.d_fri', 'att', N'Fri', N'الجمعة', NULL),
        ('att.deductions', 'att', N'Late arrival and minimum hours', N'التأخير والحد الأدنى للساعات', NULL),
        ('att.late_enabled', 'att', N'Deduct late arrival', N'خصم التأخير', NULL),
        ('att.late_enabled_hint', 'att', N'Fixed shifts: the minutes after the shift start.', N'الورديات الثابتة: الدقائق بعد بداية الوردية.', NULL),
        ('att.short_enabled', 'att', N'Deduct short hours', N'خصم نقص الساعات', NULL),
        ('att.short_enabled_hint', 'att', N'The required hours not worked (an early leave too).', N'الساعات المطلوبة غير المعمولة (والخروج المبكر).', NULL),
        ('att.combine', 'att', N'A day late and short', N'يوم فيه تأخير ونقص', NULL),
        ('att.combine_higher', 'att', N'The higher', N'الأعلى', NULL),
        ('att.combine_higher_hint', 'att', N'Arriving late usually makes the day short too - counted once.', N'التأخير غالباً ينقص اليوم - يُحسب مرة واحدة.', NULL),
        ('att.combine_both', 'att', N'Both', N'كلاهما', NULL),
        ('att.combine_both_hint', 'att', N'Late and short are deducted each.', N'يُخصم التأخير والنقص كل على حدة.', NULL),
        ('att.free_lates', 'att', N'Free late days a month', N'أيام تأخير مجانية شهرياً', NULL),
        ('att.free_lates_hint', 'att', N'The first ones carry no late deduction.', N'الأولى بدون خصم تأخير.', NULL),
        ('att.slabs', 'att', N'Slabs', N'الشرائح', NULL),
        ('att.slabs_hint', 'att', N'Minutes from - to (empty = and above) and what is deducted: an amount, a % of a day''s pay, or the minutes pro rata (the value multiplies it, 0 = x1). A rule with no slab deducts the minutes pro rata.', N'الدقائق من - إلى (فارغ = فأكثر) وما يُخصم: مبلغ، أو نسبة من أجر اليوم، أو الدقائق نسبياً (القيمة مضاعف، 0 = ×1). القاعدة بدون شرائح تخصم الدقائق نسبياً.', NULL),
        ('att.slab_rule', 'att', N'Rule', N'القاعدة', NULL),
        ('att.slab_from', 'att', N'From (min)', N'من (د)', NULL),
        ('att.slab_to', 'att', N'To (min)', N'إلى (د)', NULL),
        ('att.slab_deduct', 'att', N'Deduct', N'الخصم', NULL),
        ('att.slab_value', 'att', N'Value', N'القيمة', NULL),
        ('att.and_above', 'att', N'and above', N'فأكثر', NULL),
        ('att.add_slab', 'att', N'Add a slab', N'إضافة شريحة', NULL),
        ('att.ded_amount', 'att', N'Amount (KWD)', N'مبلغ (د.ك)', NULL),
        ('att.ded_day_percent', 'att', N'% of a day''s pay', N'% من أجر اليوم', NULL),
        ('att.ded_prorata', 'att', N'Minutes pro rata', N'الدقائق نسبياً', NULL),
        ('att.absence_and_punches', 'att', N'Absence and missing punches', N'الغياب والبصمات الناقصة', NULL),
        ('att.absent_enabled', 'att', N'Deduct absence', N'خصم الغياب', NULL),
        ('att.absent_enabled_hint', 'att', N'A working day the file covers with no punch, not on leave or a holiday.', N'يوم عمل يغطيه الملف بلا بصمة وليس إجازة أو عطلة.', NULL),
        ('att.absent_value', 'att', N'An absent day costs', N'يوم الغياب يكلف', NULL),
        ('att.days_pay', 'att', N'day''s pay', N'أجر يوم', NULL),
        ('att.missing_punch', 'att', N'A day with one punch only', N'يوم ببصمة واحدة فقط', NULL),
        ('att.overtime', 'att', N'Overtime', N'العمل الإضافي', NULL),
        ('att.overtime_enabled', 'att', N'Pay overtime', N'احتساب العمل الإضافي', NULL),
        ('att.overtime_enabled_hint', 'att', N'The minutes past the required hours; on a day off or a holiday every minute worked.', N'الدقائق بعد الساعات المطلوبة؛ وفي يوم الراحة أو العطلة كل دقيقة عمل.', NULL),
        ('att.ot_after', 'att', N'Counts from', N'يُحسب ابتداءً من', NULL),
        ('att.minutes', 'att', N'minutes extra', N'دقيقة إضافية', NULL),
        ('att.ot_rate', 'att', N'Rate', N'المعدل', NULL),
        ('att.ot_rate_hint', 'att', N'Of the hourly pay (1.25 = 125%).', N'من أجر الساعة (1.25 = 125%).', NULL),
        ('att.pay_and_cap', 'att', N'A day''s pay and the monthly cap', N'أجر اليوم والحد الشهري', NULL),
        ('att.salary_basis', 'att', N'A day''s pay is worked out from', N'يُحسب أجر اليوم من', NULL),
        ('att.day_divisor', 'att', N'Days in a month', N'أيام الشهر', NULL),
        ('att.day_divisor_hint', 'att', N'The salary is divided by it (26 or 30).', N'يُقسم عليه الراتب (26 أو 30).', NULL),
        ('att.max_deduction', 'att', N'Maximum deduction a month', N'الحد الأقصى للخصم شهرياً', NULL),
        ('att.max_none', 'att', N'No maximum', N'بدون حد', NULL),
        ('att.max_amount', 'att', N'An amount (KWD)', N'مبلغ (د.ك)', NULL),
        ('att.max_percent', 'att', N'A % of the salary', N'نسبة من الراتب', NULL),
        ('att.max_value', 'att', N'Maximum', N'الحد الأقصى', NULL),
        ('att.max_value_hint', 'att', N'Past it the latest days carry no deduction.', N'بعده لا خصم على الأيام الأخيرة.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Attendance labels inserted: ', @@ROWCOUNT);
GO
