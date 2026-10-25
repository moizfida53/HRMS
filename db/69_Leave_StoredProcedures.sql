/* =====================================================================
   69_Leave_StoredProcedures.sql  -  HRMS Leave, phase 1: the logic
   ---------------------------------------------------------------------
   Run after 68. CREATE OR ALTER everywhere - safe to re-run.

     Leave.fn_LeaveDays           days a leave counts: working days (the
                                  company's weekend left out) or calendar
                                  days, public holidays left out or not,
                                  0.5 for a half day
     Leave.tvf_Balances           every employee's balance per leave type
                                  on a date (nothing is stored)
     Leave.usp_LeaveSetup_Manage  Settings > leave types, pay bands,
                                  public holidays, weekend / approval
     Leave.usp_LeaveRequest_Manage requests: LIST / GET / PREVIEW / SAVE /
                                  APPROVE / REJECT / CANCEL / RETURN /
                                  HISTORY / SUMMARY / EMPLOYEES / TYPES
     Leave.usp_LeaveBalance_Manage balances: LIST / EMPLOYEE / LEDGER /
                                  ADJUST / DELETE_ENTRY

   How a balance is worked out (Leave.tvf_Balances, on a date):
     ACCRUE     earned from the opening balance date (else the hire date):
                MONTHLY  days per year / 12 for each full month
                UPFRONT  the whole year on 1 January (first year pro rata)
                + opening + adjustments - approved days since that date
     YEARLY     days per year for the calendar year + adjustments of the
                year - approved days starting in the year
     ONCE       days once in the service + adjustments - all approved days
     UNLIMITED  no balance; taken days are only counted
   Pending requests are shown apart and also reserve their days when a new
   request is checked.

   Approval: line manager (level 1, when the company asks for it and the
   employee's reporting manager has a user account) then HR (level 2).
   Level 1 can also be given with the LEAVE_APPROVE_L1 right, level 2 needs
   LEAVE_APPROVE_L2; nobody approves their own request without
   LEAVE_APPROVE_SELF (System Administrator always may).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Leave].[LeaveRequests]', N'U') IS NULL
    RAISERROR(N'Run db/68 first.', 16, 1);
GO

/* ------------------------------------------------------------------
   Leave.fn_LeaveDays
   ------------------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[fn_LeaveDays]
(
    @CompanyId    INT,
    @LeaveTypeId  INT,
    @Start        DATE,
    @End          DATE,
    @HalfDay      BIT
)
RETURNS DECIMAL(6, 2)
AS
BEGIN
    IF @Start IS NULL OR @End IS NULL OR @End < @Start OR DATEDIFF(DAY, @Start, @End) > 400 RETURN 0;

    DECLARE @Mode VARCHAR(10), @ExHol BIT, @Weekend VARCHAR(30), @Count INT;
    SELECT @Mode = CountMode, @ExHol = ExcludeHolidays FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId;
    SELECT @Weekend = WeekendDays FROM [Leave].[Settings] WHERE CompanyId = @CompanyId AND Deleted = 0;
    SET @Weekend = N',' + REPLACE(ISNULL(@Weekend, '5,6'), ' ', '') + N',';
    SET @Mode = ISNULL(@Mode, 'WORKING');
    SET @ExHol = ISNULL(@ExHol, 1);

    ;WITH n AS (
        SELECT TOP (DATEDIFF(DAY, @Start, @End) + 1) ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 AS i
        FROM   sys.all_objects AS a CROSS JOIN sys.all_objects AS b
    ), d AS (
        SELECT DATEADD(DAY, n.i, @Start) AS dt FROM n
    )
    SELECT @Count = COUNT(1)
    FROM   d
    -- ISO weekday without depending on DATEFIRST: 1900-01-01 was a Monday
    WHERE  (@Mode = 'CALENDAR'
            OR CHARINDEX(N',' + CAST(DATEDIFF(DAY, CAST('19000101' AS DATE), d.dt) % 7 + 1 AS NVARCHAR(1)) + N',', @Weekend) = 0)
      AND  (@ExHol = 0
            OR NOT EXISTS (SELECT 1 FROM [Leave].[PublicHolidays] AS h
                           WHERE h.Deleted = 0 AND (h.CompanyId IS NULL OR h.CompanyId = @CompanyId)
                             AND d.dt BETWEEN h.FromDate AND h.ToDate));

    RETURN CASE WHEN @HalfDay = 1 AND @Count > 0 THEN 0.5 ELSE CAST(@Count AS DECIMAL(6, 2)) END;
END;
GO

/* ------------------------------------------------------------------
   Leave.tvf_Balances
   ------------------------------------------------------------------ */
CREATE OR ALTER FUNCTION [Leave].[tvf_Balances]
(
    @AsOf        DATE,
    @EmployeeId  BIGINT        -- NULL = every employee
)
RETURNS TABLE
AS
RETURN
WITH et AS (
    SELECT  e.EmployeeId, e.CompanyId, e.HireDate,
            t.LeaveTypeId, t.BalanceMode, t.DaysPerYear, t.AccrualMethod,
            op.OpeningDate, ISNULL(op.OpeningDays, 0) AS OpeningDays,
            CASE t.BalanceMode
                 WHEN 'ACCRUE' THEN COALESCE(op.OpeningDate, e.HireDate, DATEFROMPARTS(YEAR(@AsOf), 1, 1))
                 WHEN 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 1, 1)
                 ELSE CAST('19000101' AS DATE) END AS WinStart,
            CASE WHEN t.BalanceMode = 'YEARLY' THEN DATEFROMPARTS(YEAR(@AsOf), 12, 31)
                 ELSE CAST('99991231' AS DATE) END AS WinEnd
    FROM    [Employee].[Employees] AS e
    JOIN    [Leave].[LeaveTypes] AS t
            ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
           AND (t.Gender IS NULL OR t.Gender = e.Gender)
    OUTER APPLY (SELECT TOP (1) l.EntryDate AS OpeningDate, l.Days AS OpeningDays
                 FROM   [Leave].[LeaveLedger] AS l
                 WHERE  l.EmployeeId = e.EmployeeId AND l.LeaveTypeId = t.LeaveTypeId AND l.EntryType = 'OPENING'
                   AND  l.Deleted = 0 AND l.EntryDate <= @AsOf
                 ORDER BY l.EntryDate DESC, l.EntryId DESC) AS op
    WHERE   e.Deleted = 0 AND (@EmployeeId IS NULL OR e.EmployeeId = @EmployeeId)
),
calc AS (
    SELECT  et.*,
            CAST(CASE et.BalanceMode
                 WHEN 'ACCRUE' THEN
                      CASE WHEN et.WinStart > @AsOf THEN 0
                           WHEN et.AccrualMethod = 'UPFRONT'
                                THEN ISNULL(et.DaysPerYear, 0) * ((YEAR(@AsOf) - YEAR(et.WinStart)) + (13 - MONTH(et.WinStart)) / 12.0)
                           ELSE ISNULL(et.DaysPerYear, 0) / 12.0
                                * (DATEDIFF(MONTH, et.WinStart, @AsOf) - CASE WHEN DAY(@AsOf) < DAY(et.WinStart) THEN 1 ELSE 0 END)
                      END
                 WHEN 'UNLIMITED' THEN 0
                 ELSE ISNULL(et.DaysPerYear, 0) END AS DECIMAL(9, 2)) AS Earned,
            ISNULL((SELECT SUM(a.Days) FROM [Leave].[LeaveLedger] AS a
                    WHERE a.EmployeeId = et.EmployeeId AND a.LeaveTypeId = et.LeaveTypeId AND a.EntryType = 'ADJUST'
                      AND a.Deleted = 0 AND a.EntryDate BETWEEN et.WinStart AND et.WinEnd AND a.EntryDate <= @AsOf), 0) AS Adjusted,
            ISNULL((SELECT SUM(r.Days) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'APPROVED' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Taken,
            ISNULL((SELECT SUM(r.Days) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = 'PENDING' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Pending
    FROM    et
)
SELECT  EmployeeId, CompanyId, LeaveTypeId, BalanceMode, WinStart, WinEnd, OpeningDate,
        CAST(OpeningDays AS DECIMAL(9, 2)) AS OpeningDays, Earned, CAST(Adjusted AS DECIMAL(9, 2)) AS Adjusted,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted END AS DECIMAL(9, 2)) AS Entitled,
        CAST(Taken AS DECIMAL(9, 2)) AS Taken,
        CAST(Pending AS DECIMAL(9, 2)) AS Pending,
        CAST(CASE WHEN BalanceMode = 'UNLIMITED' THEN NULL ELSE OpeningDays + Earned + Adjusted - Taken END AS DECIMAL(9, 2)) AS Available
FROM    calc;
GO

/* ------------------------------------------------------------------
   Leave.usp_LeaveSetup_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveSetup_Manage]
    @Action               VARCHAR(20),
    @Id                   INT             = NULL,
    @CompanyId            INT             = NULL,     -- a user tied to one company
    @CompanyIds           NVARCHAR(2000)  = NULL,     -- top-bar filter
    @ForCompanyId         INT             = NULL,     -- the company a record is for
    @Year                 INT             = NULL,
    /* leave type */
    @TypeCode             VARCHAR(20)     = NULL,
    @TypeName             NVARCHAR(100)   = NULL,
    @ArabicName           NVARCHAR(100)   = NULL,
    @Category             VARCHAR(12)     = NULL,
    @BalanceMode          VARCHAR(10)     = NULL,
    @DaysPerYear          DECIMAL(6, 2)   = NULL,
    @AccrualMethod        VARCHAR(10)     = NULL,
    @PayType              VARCHAR(10)     = NULL,
    @EligibleAfterMonths  SMALLINT        = NULL,
    @Gender               CHAR(1)         = NULL,
    @CountMode            VARCHAR(10)     = NULL,
    @ExcludeHolidays      BIT             = NULL,
    @AllowHalfDay         BIT             = NULL,
    @AllowNegative        BIT             = NULL,
    @RequiresDocument     BIT             = NULL,
    @MinNoticeDays        SMALLINT        = NULL,
    @MaxDaysPerRequest    SMALLINT        = NULL,
    @Color                VARCHAR(7)      = NULL,
    @SortOrder            SMALLINT        = NULL,
    @IsActive             BIT             = NULL,
    @Tiers                VARCHAR(400)    = NULL,     -- '1-15:100,16-25:75'
    /* holiday */
    @HolidayName          NVARCHAR(100)   = NULL,
    @FromDate             DATE            = NULL,
    @ToDate               DATE            = NULL,
    @AllCompanies         BIT             = NULL,
    /* settings */
    @WeekendDays          VARCHAR(20)     = NULL,
    @ManagerApproval      BIT             = NULL,
    @UserId               BIGINT          = NULL,

    @TotalCount           INT             = NULL OUTPUT,
    @NewId                BIGINT          = NULL OUTPUT,
    @ResultCode           VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage        NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';

    /* the companies the user works with */
    DECLARE @Co TABLE (CompanyId INT PRIMARY KEY, CompanyName NVARCHAR(200));
    INSERT INTO @Co
    SELECT c.CompanyId, c.CompanyName FROM [Core].[Companies] AS c
    WHERE  c.Deleted = 0
      AND  (@CompanyId IS NULL OR c.CompanyId = @CompanyId)
      AND  (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(c.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0);

    /* a company set up after db/68 gets the default types the first time it is looked at */
    IF @Action IN ('TYPES', 'SETTINGS')
    BEGIN
        DECLARE @seed INT = (SELECT TOP (1) c.CompanyId FROM @Co c
                             WHERE NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] t WHERE t.CompanyId = c.CompanyId AND t.Deleted = 0)
                                OR NOT EXISTS (SELECT 1 FROM [Leave].[Settings] s WHERE s.CompanyId = c.CompanyId)
                             ORDER BY c.CompanyId);
        WHILE @seed IS NOT NULL
        BEGIN
            EXEC [Leave].[usp_LeaveType_SeedDefaults] @CompanyId = @seed, @UserId = @UserId;
            SET @seed = (SELECT TOP (1) c.CompanyId FROM @Co c
                         WHERE c.CompanyId > @seed
                           AND (NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] t WHERE t.CompanyId = c.CompanyId AND t.Deleted = 0)
                                OR NOT EXISTS (SELECT 1 FROM [Leave].[Settings] s WHERE s.CompanyId = c.CompanyId))
                         ORDER BY c.CompanyId);
        END;
    END;

    /* ======================= leave types ========================== */
    IF @Action = 'TYPES'
    BEGIN
        SELECT  t.LeaveTypeId, t.CompanyId, c.CompanyName, t.TypeCode, t.TypeName, t.ArabicName, t.Category, t.BalanceMode,
                t.DaysPerYear, t.AccrualMethod, t.PayType, t.EligibleAfterMonths, t.Gender, t.CountMode, t.ExcludeHolidays,
                t.AllowHalfDay, t.AllowNegative, t.RequiresDocument, t.MinNoticeDays, t.MaxDaysPerRequest, t.Color, t.SortOrder, t.IsActive,
                (SELECT STRING_AGG(CONCAT(x.FromDay, '-', x.ToDay, ':', CAST(x.PayPercent AS DECIMAL(5, 0))), ',') WITHIN GROUP (ORDER BY x.FromDay)
                 FROM [Leave].[LeaveTypeTiers] x WHERE x.LeaveTypeId = t.LeaveTypeId AND x.Deleted = 0) AS Tiers,
                (SELECT COUNT(1) FROM [Leave].[LeaveRequests] r WHERE r.LeaveTypeId = t.LeaveTypeId AND r.Deleted = 0) AS UsageCount
        FROM    [Leave].[LeaveTypes] AS t
        JOIN    @Co AS c ON c.CompanyId = t.CompanyId
        WHERE   t.Deleted = 0 AND (@ForCompanyId IS NULL OR t.CompanyId = @ForCompanyId)
        ORDER BY c.CompanyName, t.SortOrder, t.TypeName;
        RETURN;
    END;

    IF @Action = 'TYPE_SAVE'
    BEGIN
        SET @TypeCode = UPPER(NULLIF(LTRIM(RTRIM(@TypeCode)), ''));
        SET @TypeName = NULLIF(LTRIM(RTRIM(@TypeName)), N'');
        SET @ArabicName = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
        IF @Id > 0 SELECT @ForCompanyId = CompanyId FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @Id AND Deleted = 0;

        IF NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @ForCompanyId)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the company.'; RETURN; END;
        IF @TypeCode IS NULL OR @TypeName IS NULL OR @TypeCode LIKE '%[^A-Z0-9_]%'
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter a code (letters, digits, _) and a name.'; RETURN; END;
        IF @BalanceMode NOT IN ('ACCRUE', 'YEARLY', 'ONCE', 'UNLIMITED') OR @PayType NOT IN ('FULL', 'TIERED', 'UNPAID')
           OR ISNULL(@CountMode, '') NOT IN ('WORKING', 'CALENDAR')
           OR ISNULL(@Category, 'OTHER') NOT IN ('ANNUAL', 'SICK', 'EMERGENCY', 'HAJJ', 'MATERNITY', 'BEREAVEMENT', 'UNPAID', 'OTHER')
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Check the leave type settings.'; RETURN; END;
        IF @BalanceMode <> 'UNLIMITED' AND (@DaysPerYear IS NULL OR @DaysPerYear <= 0 OR @DaysPerYear > 366)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days (1 to 366).'; RETURN; END;
        IF EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE CompanyId = @ForCompanyId AND TypeCode = @TypeCode AND Deleted = 0 AND LeaveTypeId <> ISNULL(@Id, 0))
        BEGIN SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'This company already has a leave type with this code.'; RETURN; END;

        /* pay bands '1-15:100,16-25:75' */
        DECLARE @T TABLE (FromDay SMALLINT, ToDay SMALLINT, Pct DECIMAL(5, 2));
        DECLARE @Rest VARCHAR(410) = ISNULL(@Tiers, '') + ',', @At INT, @Tok VARCHAR(40), @F INT, @To INT, @P DECIMAL(5, 2);
        WHILE CHARINDEX(',', @Rest) > 0
        BEGIN
            SET @At = CHARINDEX(',', @Rest);
            SET @Tok = LTRIM(RTRIM(LEFT(@Rest, @At - 1)));
            SET @Rest = STUFF(@Rest, 1, @At, '');
            IF @Tok = '' CONTINUE;
            SET @F  = TRY_CAST(LEFT(@Tok, CHARINDEX('-', @Tok + '-') - 1) AS INT);
            SET @To = TRY_CAST(SUBSTRING(@Tok, CHARINDEX('-', @Tok + '-') + 1, CHARINDEX(':', @Tok + ':') - CHARINDEX('-', @Tok + '-') - 1) AS INT);
            SET @P  = TRY_CAST(SUBSTRING(@Tok, CHARINDEX(':', @Tok + ':') + 1, 10) AS DECIMAL(5, 2));
            IF @F IS NULL OR @To IS NULL OR @P IS NULL OR @F < 1 OR @To < @F OR @To > 366 OR @P < 0 OR @P > 100
            BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Each pay band needs from day, to day and a percent from 0 to 100.'; RETURN; END;
            INSERT INTO @T VALUES (@F, @To, @P);
        END;
        IF EXISTS (SELECT 1 FROM @T a JOIN @T b ON a.FromDay < b.FromDay AND a.ToDay >= b.FromDay)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The pay bands overlap.'; RETURN; END;

        BEGIN TRANSACTION;
        IF @Id > 0
        BEGIN
            UPDATE [Leave].[LeaveTypes]
               SET TypeCode = @TypeCode, TypeName = @TypeName, ArabicName = @ArabicName, Category = ISNULL(@Category, 'OTHER'),
                   BalanceMode = @BalanceMode, DaysPerYear = CASE WHEN @BalanceMode = 'UNLIMITED' THEN NULL ELSE @DaysPerYear END,
                   AccrualMethod = CASE WHEN @BalanceMode = 'ACCRUE' THEN ISNULL(@AccrualMethod, 'MONTHLY') END,
                   PayType = @PayType, EligibleAfterMonths = ISNULL(@EligibleAfterMonths, 0), Gender = NULLIF(@Gender, ''),
                   CountMode = @CountMode, ExcludeHolidays = ISNULL(@ExcludeHolidays, 0), AllowHalfDay = ISNULL(@AllowHalfDay, 0),
                   AllowNegative = ISNULL(@AllowNegative, 0), RequiresDocument = ISNULL(@RequiresDocument, 0),
                   MinNoticeDays = ISNULL(@MinNoticeDays, 0), MaxDaysPerRequest = NULLIF(@MaxDaysPerRequest, 0),
                   Color = NULLIF(@Color, ''), SortOrder = ISNULL(@SortOrder, SortOrder), IsActive = ISNULL(@IsActive, 1),
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveTypeId = @Id AND Deleted = 0;
        END
        ELSE
        BEGIN
            INSERT INTO [Leave].[LeaveTypes] (CompanyId, TypeCode, TypeName, ArabicName, Category, BalanceMode, DaysPerYear, AccrualMethod, PayType,
                   EligibleAfterMonths, Gender, CountMode, ExcludeHolidays, AllowHalfDay, AllowNegative, RequiresDocument, MinNoticeDays,
                   MaxDaysPerRequest, Color, SortOrder, IsActive, CreatedBy)
            VALUES (@ForCompanyId, @TypeCode, @TypeName, @ArabicName, ISNULL(@Category, 'OTHER'), @BalanceMode,
                    CASE WHEN @BalanceMode = 'UNLIMITED' THEN NULL ELSE @DaysPerYear END,
                    CASE WHEN @BalanceMode = 'ACCRUE' THEN ISNULL(@AccrualMethod, 'MONTHLY') END, @PayType,
                    ISNULL(@EligibleAfterMonths, 0), NULLIF(@Gender, ''), @CountMode, ISNULL(@ExcludeHolidays, 0), ISNULL(@AllowHalfDay, 0),
                    ISNULL(@AllowNegative, 0), ISNULL(@RequiresDocument, 0), ISNULL(@MinNoticeDays, 0), NULLIF(@MaxDaysPerRequest, 0),
                    NULLIF(@Color, ''),
                    ISNULL(@SortOrder, (SELECT ISNULL(MAX(SortOrder), 0) + 10 FROM [Leave].[LeaveTypes] WHERE CompanyId = @ForCompanyId AND Deleted = 0)),
                    ISNULL(@IsActive, 1), @UserId);
            SET @Id = CAST(SCOPE_IDENTITY() AS INT);
        END;

        UPDATE [Leave].[LeaveTypeTiers] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE LeaveTypeId = @Id AND Deleted = 0;
        INSERT INTO [Leave].[LeaveTypeTiers] (LeaveTypeId, FromDay, ToDay, PayPercent, CreatedBy)
        SELECT @Id, FromDay, ToDay, Pct, @UserId FROM @T WHERE @PayType = 'TIERED';
        COMMIT;

        SELECT @NewId = @Id, @ResultMessage = N'Leave type saved.';
        RETURN;
    END;

    IF @Action IN ('TYPE_TOGGLE', 'TYPE_DELETE')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] t JOIN @Co c ON c.CompanyId = t.CompanyId WHERE t.LeaveTypeId = @Id AND t.Deleted = 0)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        IF @Action = 'TYPE_TOGGLE'
        BEGIN
            UPDATE [Leave].[LeaveTypes] SET IsActive = 1 - IsActive, ModifiedBy = @UserId, ModifiedDate = @Now WHERE LeaveTypeId = @Id;
            SELECT @NewId = @Id, @ResultMessage = CASE WHEN (SELECT IsActive FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @Id) = 1
                                                       THEN N'Leave type activated.' ELSE N'Leave type deactivated.' END;
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] WHERE LeaveTypeId = @Id AND Deleted = 0)
           OR EXISTS (SELECT 1 FROM [Leave].[LeaveLedger] WHERE LeaveTypeId = @Id AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Requests or balances use this leave type. Deactivate it instead.'; RETURN; END;
        UPDATE [Leave].[LeaveTypes] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE LeaveTypeId = @Id;
        SELECT @NewId = @Id, @ResultMessage = N'Leave type deleted.';
        RETURN;
    END;

    /* ======================= public holidays ====================== */
    IF @Action = 'HOLIDAYS'
    BEGIN
        SET @Year = ISNULL(@Year, YEAR(GETDATE()));
        SELECT  h.HolidayId, h.CompanyId, c.CompanyName, h.HolidayName, h.ArabicName, h.FromDate, h.ToDate,
                DATEDIFF(DAY, h.FromDate, h.ToDate) + 1 AS DayCount
        FROM    [Leave].[PublicHolidays] AS h
        LEFT JOIN @Co AS c ON c.CompanyId = h.CompanyId
        WHERE   h.Deleted = 0 AND (h.CompanyId IS NULL OR c.CompanyId IS NOT NULL)
          AND   (YEAR(h.FromDate) = @Year OR YEAR(h.ToDate) = @Year)
        ORDER BY h.FromDate, h.HolidayName;
        RETURN;
    END;

    IF @Action = 'HOLIDAY_SAVE'
    BEGIN
        SET @HolidayName = NULLIF(LTRIM(RTRIM(@HolidayName)), N'');
        SET @ArabicName = NULLIF(LTRIM(RTRIM(@ArabicName)), N'');
        SET @ToDate = ISNULL(@ToDate, @FromDate);
        IF @HolidayName IS NULL OR @FromDate IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the holiday name and its date.'; RETURN; END;
        IF @ToDate < @FromDate OR DATEDIFF(DAY, @FromDate, @ToDate) > 31
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The last day must be on or after the first, at most 31 days later.'; RETURN; END;
        /* a holiday for every company only by a user who sees every company */
        IF ISNULL(@AllCompanies, 0) = 1 AND (@CompanyId IS NOT NULL) SET @AllCompanies = 0;
        IF ISNULL(@AllCompanies, 0) = 0 AND NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @ForCompanyId)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the company, or every company.'; RETURN; END;
        IF @Id > 0 AND NOT EXISTS (SELECT 1 FROM [Leave].[PublicHolidays] h LEFT JOIN @Co c ON c.CompanyId = h.CompanyId
                                   WHERE h.HolidayId = @Id AND h.Deleted = 0 AND (c.CompanyId IS NOT NULL OR (h.CompanyId IS NULL AND @CompanyId IS NULL)))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;

        IF @Id > 0
            UPDATE [Leave].[PublicHolidays]
               SET CompanyId = CASE WHEN @AllCompanies = 1 THEN NULL ELSE @ForCompanyId END, HolidayName = @HolidayName, ArabicName = @ArabicName,
                   FromDate = @FromDate, ToDate = @ToDate, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE HolidayId = @Id;
        ELSE
        BEGIN
            INSERT INTO [Leave].[PublicHolidays] (CompanyId, HolidayName, ArabicName, FromDate, ToDate, CreatedBy)
            VALUES (CASE WHEN @AllCompanies = 1 THEN NULL ELSE @ForCompanyId END, @HolidayName, @ArabicName, @FromDate, @ToDate, @UserId);
            SET @Id = CAST(SCOPE_IDENTITY() AS INT);
        END;
        SELECT @NewId = @Id, @ResultMessage = N'Public holiday saved.';
        RETURN;
    END;

    IF @Action = 'HOLIDAY_DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Leave].[PublicHolidays] h LEFT JOIN @Co c ON c.CompanyId = h.CompanyId
                       WHERE h.HolidayId = @Id AND h.Deleted = 0 AND (c.CompanyId IS NOT NULL OR (h.CompanyId IS NULL AND @CompanyId IS NULL)))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        UPDATE [Leave].[PublicHolidays] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE HolidayId = @Id;
        SELECT @NewId = @Id, @ResultMessage = N'Public holiday deleted.';
        RETURN;
    END;

    /* ======================= settings ============================= */
    IF @Action = 'SETTINGS'
    BEGIN
        SELECT c.CompanyId, c.CompanyName, ISNULL(s.WeekendDays, '5,6') AS WeekendDays, ISNULL(s.ManagerApproval, 1) AS ManagerApproval
        FROM   @Co AS c
        LEFT JOIN [Leave].[Settings] AS s ON s.CompanyId = c.CompanyId AND s.Deleted = 0
        ORDER BY c.CompanyName;
        RETURN;
    END;

    IF @Action = 'SETTINGS_SAVE'
    BEGIN
        SET @WeekendDays = REPLACE(ISNULL(@WeekendDays, ''), ' ', '');
        IF NOT EXISTS (SELECT 1 FROM @Co WHERE CompanyId = @ForCompanyId)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the company.'; RETURN; END;
        IF @WeekendDays LIKE '%[^1-7,]%' OR LEN(@WeekendDays) > 13
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the weekend days.'; RETURN; END;

        IF EXISTS (SELECT 1 FROM [Leave].[Settings] WHERE CompanyId = @ForCompanyId)
            UPDATE [Leave].[Settings]
               SET WeekendDays = @WeekendDays, ManagerApproval = ISNULL(@ManagerApproval, 1), Deleted = 0,
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE CompanyId = @ForCompanyId;
        ELSE
            INSERT INTO [Leave].[Settings] (CompanyId, WeekendDays, ManagerApproval, CreatedBy)
            VALUES (@ForCompanyId, @WeekendDays, ISNULL(@ManagerApproval, 1), @UserId);
        SELECT @NewId = @ForCompanyId, @ResultMessage = N'Leave settings saved.';
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ------------------------------------------------------------------
   Leave.usp_LeaveRequest_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveRequest_Manage]
    @Action            VARCHAR(20),
    @Id                BIGINT          = NULL,
    @CompanyId         INT             = NULL,
    @CompanyIds        NVARCHAR(2000)  = NULL,
    /* LIST filters */
    @StatusFilter      VARCHAR(12)     = NULL,     -- PENDING, APPROVED, REJECTED, CANCELLED, MINE (waiting for me), ALL
    @LeaveTypeId       INT             = NULL,
    @EmployeeId        BIGINT          = NULL,
    @FromDate          DATE            = NULL,
    @ToDate            DATE            = NULL,
    @Search            NVARCHAR(200)   = NULL,
    @SelfOnly          BIT             = 0,        -- My Leave: only @SelfEmployeeId's own requests
    @SelfEmployeeId    BIGINT          = NULL,     -- the signed-in user's employee
    @TeamOnly          BIT             = 0,        -- My Leave > team: requests waiting for the user as line manager
    @PageNumber        INT             = 1,
    @PageSize          INT             = 25,
    /* SAVE */
    @StartDate         DATE            = NULL,
    @EndDate           DATE            = NULL,
    @HalfDay           BIT             = 0,
    @Reason            NVARCHAR(500)   = NULL,
    @DocumentPath      NVARCHAR(400)   = NULL,
    @DocumentName      NVARCHAR(260)   = NULL,
    @DocumentType      NVARCHAR(100)   = NULL,
    @DocumentSize      BIGINT          = NULL,
    @IsHr              BIT             = 0,        -- entered / handled by HR (LEAVE_MANAGE): no notice rule
    @ApproveNow        BIT             = 0,        -- HR with the final approval right: approved at once
    /* decisions */
    @Comment           NVARCHAR(500)   = NULL,
    @ExpectedLevel     TINYINT         = NULL,
    @CanApproveL1      BIT             = 0,
    @CanApproveL2      BIT             = 0,
    @AllowSelf         BIT             = 0,
    @ReturnDate        DATE            = NULL,
    @UserId            BIGINT          = NULL,

    @TotalCount        INT             = NULL OUTPUT,
    @NewId             BIGINT          = NULL OUTPUT,
    @ResultCode        VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage     NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME(), @Today DATE = CAST(SYSDATETIME() AS DATE);
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Reason = NULLIF(LTRIM(RTRIM(@Reason)), N'');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* the employees the user may see: own company / top-bar filter; My Leave: only their own */
    DECLARE @MyEmployee BIGINT = (SELECT TOP (1) u.EmployeeId FROM [Security].[Users] u WHERE u.UserId = @UserId AND u.Deleted = 0);

    /* ======================= EMPLOYEES (pickers) ================== */
    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, e.CompanyId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName, e.Gender, e.HireDate
        FROM    [Employee].[Employees] AS e
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0
          AND   NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
        ORDER BY e.FirstName, e.LastName;
        RETURN;
    END;

    /* ======================= TYPES (for one employee) ============= */
    IF @Action = 'TYPES'
    BEGIN
        SELECT  t.LeaveTypeId, t.CompanyId, t.TypeCode, t.TypeName, t.ArabicName, t.Category, t.BalanceMode, t.PayType, t.CountMode,
                t.AllowHalfDay, t.RequiresDocument, t.MinNoticeDays, t.MaxDaysPerRequest, t.Color, t.EligibleAfterMonths,
                b.Entitled, b.Taken, b.Pending, b.Available
        FROM    [Employee].[Employees] AS e
        JOIN    [Leave].[LeaveTypes] AS t ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
                                         AND (t.Gender IS NULL OR t.Gender = e.Gender)
        LEFT JOIN [Leave].[tvf_Balances](ISNULL(@StartDate, @Today), @EmployeeId) AS b ON b.LeaveTypeId = t.LeaveTypeId
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0
        ORDER BY t.SortOrder, t.TypeName;
        RETURN;
    END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN @PageSize < 1 THEN 25 WHEN @PageSize > 1000 THEN 1000 ELSE @PageSize END;

        ;WITH x AS (
            SELECT  r.LeaveRequestId, r.RequestNo, r.CompanyId, co.CompanyName, r.EmployeeId,
                    ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                    LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                    d.DepartmentName,
                    r.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category,
                    r.StartDate, r.EndDate, r.ActualEndDate, r.ActualReturnDate, r.HalfDay, r.Days, r.PlannedDays, r.Status, r.ApprovalLevel,
                    r.Reason, r.ManagerUserId, r.CreatedDate, r.CreatedBy, r.EnteredByHr,
                    CASE WHEN r.DocumentPath IS NULL THEN 0 ELSE 1 END AS HasDocument,
                    u.EmployeeId AS SubmitterEmployeeId
            FROM    [Leave].[LeaveRequests] AS r
            JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
            JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
            LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = r.CompanyId
            LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
            LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
            WHERE   r.Deleted = 0
              AND   (@SelfOnly = 1 OR @TeamOnly = 1
                     OR ((@CompanyId IS NULL OR r.CompanyId = @CompanyId)
                         AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(r.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)))
              AND   (@SelfOnly = 0 OR r.EmployeeId = @SelfEmployeeId)
              AND   (@TeamOnly = 0 OR (e.ReportingManagerId = @MyEmployee AND @MyEmployee IS NOT NULL))
              AND   (@EmployeeId IS NULL OR r.EmployeeId = @EmployeeId)
              AND   (@LeaveTypeId IS NULL OR r.LeaveTypeId = @LeaveTypeId)
              AND   (@FromDate IS NULL OR ISNULL(r.ActualEndDate, r.EndDate) >= @FromDate)
              AND   (@ToDate IS NULL OR r.StartDate <= @ToDate)
              AND   (ISNULL(@StatusFilter, 'ALL') = 'ALL'
                     OR (@StatusFilter = 'MINE' AND r.Status = 'PENDING'
                         AND ((r.ApprovalLevel = 1 AND (r.ManagerUserId = @UserId OR @CanApproveL1 = 1))
                              OR (r.ApprovalLevel = 2 AND @CanApproveL2 = 1)))
                     OR (@StatusFilter = 'ONLEAVE' AND r.Status = 'APPROVED' AND @Today BETWEEN r.StartDate AND ISNULL(r.ActualEndDate, r.EndDate))
                     OR (@StatusFilter = 'UPCOMING' AND r.Status = 'APPROVED' AND r.StartDate > @Today)
                     OR r.Status = @StatusFilter)
              AND   (@Search IS NULL OR r.RequestNo LIKE N'%' + @Search + N'%' OR e.FirstName LIKE N'%' + @Search + N'%'
                     OR e.LastName LIKE N'%' + @Search + N'%' OR e.EmployeeCode LIKE N'%' + @Search + N'%'
                     OR e.EmployeeNo LIKE N'%' + @Search + N'%' OR t.TypeName LIKE N'%' + @Search + N'%')
        )
        SELECT  *, COUNT(1) OVER () AS TotalRows
        INTO    #List
        FROM    x;

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #List;
        SELECT  LeaveRequestId, RequestNo, CompanyId, CompanyName, EmployeeId, EmployeeNo, EmployeeName, EmployeeArabicName, DepartmentName,
                LeaveTypeId, TypeName, TypeArabicName, Color, Category, StartDate, EndDate, ActualEndDate, ActualReturnDate, HalfDay, Days, PlannedDays,
                Status, ApprovalLevel, Reason, ManagerUserId, CreatedDate, CreatedBy, EnteredByHr, HasDocument, SubmitterEmployeeId
        FROM    #List
        ORDER BY CASE WHEN Status = 'PENDING' THEN 0 ELSE 1 END, StartDate DESC, LeaveRequestId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  r.LeaveRequestId, r.RequestNo, r.CompanyId, co.CompanyName, r.EmployeeId,
                ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                d.DepartmentName, e.ReportingManagerId,
                r.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.CountMode, t.AllowHalfDay, t.RequiresDocument,
                r.StartDate, r.EndDate, r.ActualEndDate, r.ActualReturnDate, r.HalfDay, r.Days, r.PlannedDays, r.Status, r.ApprovalLevel,
                r.Reason, r.ManagerUserId, r.ManagerApprovedBy, r.ManagerApprovedDate, r.DecidedBy, r.DecidedDate, r.DecisionComment,
                r.CancelledBy, r.CancelledDate, r.DocumentName, r.DocumentType, r.DocumentSize, r.DocumentPath,
                CASE WHEN r.DocumentPath IS NULL THEN 0 ELSE 1 END AS HasDocument,
                r.EnteredByHr, r.CreatedBy, r.CreatedDate,
                cu.Username AS CreatedByName, mu.Username AS ManagerName, du.Username AS DecidedByName,
                LTRIM(RTRIM(CONCAT(me.FirstName, N' ', me.LastName))) AS ManagerEmployeeName,
                cu.EmployeeId AS SubmitterEmployeeId
        FROM    [Leave].[LeaveRequests] AS r
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = r.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = r.LeaveTypeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = r.CompanyId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Employee].[Employees] AS me ON me.EmployeeId = e.ReportingManagerId
        LEFT JOIN [Security].[Users] AS cu ON cu.UserId = r.CreatedBy
        LEFT JOIN [Security].[Users] AS mu ON mu.UserId = r.ManagerUserId
        LEFT JOIN [Security].[Users] AS du ON du.UserId = r.DecidedBy
        WHERE   r.LeaveRequestId = @Id AND r.Deleted = 0;
        RETURN;
    END;

    IF @Action = 'HISTORY'
    BEGIN
        SELECT  h.HistoryId, h.ActionCode, h.ActionBy, u.Username AS ActionByName, h.ActionDate, h.Comment
        FROM    [Leave].[LeaveRequestHistory] AS h
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        WHERE   h.LeaveRequestId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate, h.HistoryId;
        RETURN;
    END;

    /* ======================= SUMMARY (KPIs, Dashboard) ============ */
    IF @Action = 'SUMMARY'
    BEGIN
        DECLARE @MonthStart DATE = DATEFROMPARTS(YEAR(ISNULL(@FromDate, @Today)), MONTH(ISNULL(@FromDate, @Today)), 1);
        DECLARE @MonthEnd DATE = EOMONTH(@MonthStart);
        ;WITH r AS (
            SELECT  q.*, t.Category, ISNULL(q.ActualEndDate, q.EndDate) AS LastDay
            FROM    [Leave].[LeaveRequests] AS q
            JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = q.LeaveTypeId
            JOIN    [Employee].[Employees] AS e ON e.EmployeeId = q.EmployeeId AND e.Deleted = 0
            WHERE   q.Deleted = 0
              AND   (@CompanyId IS NULL OR q.CompanyId = @CompanyId)
              AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(q.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
        )
        SELECT
            PendingTotal      = (SELECT COUNT(1) FROM r WHERE Status = 'PENDING'),
            PendingForMe      = (SELECT COUNT(1) FROM r WHERE Status = 'PENDING'
                                  AND ((ApprovalLevel = 1 AND (ManagerUserId = @UserId OR @CanApproveL1 = 1)) OR (ApprovalLevel = 2 AND @CanApproveL2 = 1))),
            OnLeaveToday      = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND @Today BETWEEN StartDate AND LastDay),
            StartingThisWeek  = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND StartDate > @Today AND StartDate <= DATEADD(DAY, 7, @Today)),
            ApprovedThisMonth = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            /* employees on leave in the month, by kind (Dashboard) */
            AnnualInMonth     = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'ANNUAL' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            SickInMonth       = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'SICK' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            EmergencyInMonth  = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category = 'EMERGENCY' AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            OtherInMonth      = (SELECT COUNT(DISTINCT EmployeeId) FROM r WHERE Status = 'APPROVED' AND Category NOT IN ('ANNUAL', 'SICK', 'EMERGENCY') AND StartDate <= @MonthEnd AND LastDay >= @MonthStart),
            DueBack           = (SELECT COUNT(1) FROM r WHERE Status = 'APPROVED' AND ActualReturnDate IS NULL AND LastDay < @Today AND LastDay >= DATEADD(DAY, -30, @Today));
        RETURN;
    END;

    /* ======================= PREVIEW / SAVE ======================= */
    IF @Action IN ('PREVIEW', 'SAVE')
    BEGIN
        DECLARE @eCo INT, @eHire DATE, @eGender CHAR(1), @eStatus NVARCHAR(20), @eMgr BIGINT, @eDel BIT;
        DECLARE @old_Status VARCHAR(12), @old_Employee BIGINT, @old_Doc NVARCHAR(400), @old_Creator BIGINT;
        IF @Id > 0
        BEGIN
            SELECT @old_Status = Status, @old_Employee = EmployeeId, @old_Doc = DocumentPath, @old_Creator = CreatedBy
            FROM [Leave].[LeaveRequests] WHERE LeaveRequestId = @Id AND Deleted = 0;
            IF @old_Status IS NULL
            BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That request was not found.'; RETURN; END;
            IF @old_Status <> 'PENDING'
            BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'Only a pending request can be changed.'; RETURN; END;
            SET @EmployeeId = @old_Employee;
        END;

        SELECT @eCo = e.CompanyId, @eHire = e.HireDate, @eGender = e.Gender, @eStatus = e.EmploymentStatus,
               @eMgr = e.ReportingManagerId, @eDel = CASE WHEN e.Deleted = 1 OR e.IsDeleted = 1 THEN 1 ELSE 0 END
        FROM   [Employee].[Employees] AS e WHERE e.EmployeeId = @EmployeeId;

        IF @eCo IS NULL OR @eDel = 1
           OR (@IsHr = 1 AND ((@CompanyId IS NOT NULL AND @eCo <> @CompanyId)
                              OR (@CompanyIds IS NOT NULL AND CHARINDEX(N',' + CAST(@eCo AS NVARCHAR(12)) + N',', @Csv) = 0)))
           OR (@IsHr = 0 AND (@MyEmployee IS NULL OR @EmployeeId <> @MyEmployee))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee.'; RETURN; END;

        DECLARE @tCo INT, @tActive BIT, @tGender CHAR(1), @tHalf BIT, @tMode VARCHAR(10), @tNeg BIT, @tNotice SMALLINT, @tMax SMALLINT,
                @tElig SMALLINT, @tName NVARCHAR(100);
        SELECT @tCo = CompanyId, @tActive = IsActive, @tGender = Gender, @tHalf = AllowHalfDay, @tMode = BalanceMode, @tNeg = AllowNegative,
               @tNotice = MinNoticeDays, @tMax = MaxDaysPerRequest, @tElig = EligibleAfterMonths, @tName = TypeName
        FROM   [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND Deleted = 0;

        IF @tCo IS NULL OR @tCo <> @eCo OR @tActive = 0 OR (@tGender IS NOT NULL AND @tGender <> ISNULL(@eGender, ''))
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'This leave type is not available for the employee.'; RETURN; END;
        IF @StartDate IS NULL OR @EndDate IS NULL OR @EndDate < @StartDate
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the first and last day of the leave.'; RETURN; END;
        IF DATEDIFF(DAY, @StartDate, @EndDate) > 365
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A leave can be at most one year long.'; RETURN; END;
        IF ISNULL(@HalfDay, 0) = 1 AND (@tHalf = 0 OR @StartDate <> @EndDate)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A half day is a single day, for a leave type that allows it.'; RETURN; END;

        DECLARE @Days DECIMAL(6, 2) = [Leave].[fn_LeaveDays](@eCo, @LeaveTypeId, @StartDate, @EndDate, ISNULL(@HalfDay, 0));

        DECLARE @bEntitled DECIMAL(9, 2), @bTaken DECIMAL(9, 2), @bPending DECIMAL(9, 2), @bAvail DECIMAL(9, 2);
        SELECT @bEntitled = b.Entitled, @bTaken = b.Taken, @bAvail = b.Available,
               @bPending = b.Pending - ISNULL((SELECT r.Days FROM [Leave].[LeaveRequests] r WHERE r.LeaveRequestId = @Id AND r.Status = 'PENDING' AND r.Deleted = 0
                                               AND r.StartDate BETWEEN b.WinStart AND b.WinEnd), 0)
        FROM   [Leave].[tvf_Balances](@StartDate, @EmployeeId) AS b
        WHERE  b.LeaveTypeId = @LeaveTypeId;

        /* the problems, worst first; PREVIEW shows them all, SAVE stops at the first */
        DECLARE @Problems TABLE (Seq INT IDENTITY(1, 1), Code VARCHAR(40), Message NVARCHAR(400));
        IF @Days <= 0
            INSERT INTO @Problems VALUES ('NO_DAYS', N'These dates have no working days to take (weekend or public holiday).');
        IF EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] r
                   WHERE r.EmployeeId = @EmployeeId AND r.Deleted = 0 AND r.Status IN ('PENDING', 'APPROVED') AND r.LeaveRequestId <> ISNULL(@Id, 0)
                     AND r.StartDate <= @EndDate AND ISNULL(r.ActualEndDate, r.EndDate) >= @StartDate)
            INSERT INTO @Problems VALUES ('OVERLAP', N'The employee already has a leave on some of these days.');
        IF @tElig > 0 AND @eHire IS NOT NULL AND DATEADD(MONTH, @tElig, @eHire) > @StartDate
            INSERT INTO @Problems VALUES ('NOT_ELIGIBLE', CONCAT(N'Not eligible yet: this leave can be taken from ',
                                                                 FORMAT(DATEADD(MONTH, @tElig, @eHire), 'dd MMM yyyy', 'en-US'), N'.'));
        IF @tMax IS NOT NULL AND @Days > @tMax
            INSERT INTO @Problems VALUES ('TOO_LONG', CONCAT(N'At most ', @tMax, N' days per request for this leave type.'));
        IF @tMode <> 'UNLIMITED' AND @tNeg = 0 AND @Days > ISNULL(@bAvail, 0) - ISNULL(@bPending, 0)
            INSERT INTO @Problems VALUES ('BALANCE', CONCAT(N'Not enough balance: ', FORMAT(ISNULL(@bAvail, 0) - ISNULL(@bPending, 0), '0.##', 'en-US'),
                                                            N' days available, ', FORMAT(@Days, '0.##', 'en-US'), N' requested.'));
        IF ISNULL(@IsHr, 0) = 0 AND @tNotice > 0 AND DATEDIFF(DAY, @Today, @StartDate) < @tNotice
            INSERT INTO @Problems VALUES ('NOTICE', CONCAT(N'This leave needs ', @tNotice, N' days notice.'));

        IF @Action = 'PREVIEW'
        BEGIN
            SELECT @Days AS Days, @bEntitled AS Entitled, @bTaken AS Taken, @bPending AS Pending, @bAvail AS Available,
                   CASE WHEN @tMode = 'UNLIMITED' THEN NULL ELSE ISNULL(@bAvail, 0) - ISNULL(@bPending, 0) - @Days END AS After,
                   (SELECT STRING_AGG(Message, N'|') WITHIN GROUP (ORDER BY Seq) FROM @Problems) AS Problems;
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM @Problems)
        BEGIN
            SELECT TOP (1) @ResultCode = Code, @ResultMessage = Message FROM @Problems ORDER BY Seq;
            RETURN;
        END;

        /* who approves: the line manager first (company setting, a manager with a user account who is not the submitter) */
        DECLARE @MgrUser BIGINT = NULL, @NeedMgr BIT = ISNULL((SELECT ManagerApproval FROM [Leave].[Settings] WHERE CompanyId = @eCo AND Deleted = 0), 1);
        IF @NeedMgr = 1 AND @eMgr IS NOT NULL
            SET @MgrUser = (SELECT TOP (1) u.UserId FROM [Security].[Users] u
                            WHERE u.EmployeeId = @eMgr AND u.Deleted = 0 AND u.IsActive = 1 ORDER BY u.UserId);
        DECLARE @Level TINYINT = CASE WHEN @MgrUser IS NOT NULL AND @MgrUser <> ISNULL(@UserId, 0) THEN 1 ELSE 2 END;
        DECLARE @Final BIT = CASE WHEN ISNULL(@ApproveNow, 0) = 1 AND @IsHr = 1 AND @CanApproveL2 = 1
                                       AND (@EmployeeId <> ISNULL(@MyEmployee, 0) OR @AllowSelf = 1) THEN 1 ELSE 0 END;

        BEGIN TRANSACTION;
        IF @Id > 0
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET LeaveTypeId = @LeaveTypeId, StartDate = @StartDate, EndDate = @EndDate, HalfDay = ISNULL(@HalfDay, 0),
                   Days = @Days, PlannedDays = @Days, Reason = @Reason,
                   Status = CASE WHEN @Final = 1 THEN 'APPROVED' ELSE 'PENDING' END,
                   ApprovalLevel = @Level, ManagerUserId = @MgrUser, ManagerApprovedBy = NULL, ManagerApprovedDate = NULL,
                   DecidedBy = CASE WHEN @Final = 1 THEN @UserId END, DecidedDate = CASE WHEN @Final = 1 THEN @Now END,
                   DocumentPath = ISNULL(@DocumentPath, DocumentPath), DocumentName = ISNULL(@DocumentName, DocumentName),
                   DocumentType = ISNULL(@DocumentType, DocumentType), DocumentSize = ISNULL(@DocumentSize, DocumentSize),
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
            VALUES (@Id, 'EDITED', @UserId, CONCAT(FORMAT(@StartDate, 'dd/MM/yyyy', 'en-US'), N' - ', FORMAT(@EndDate, 'dd/MM/yyyy', 'en-US'),
                                                   N' (', FORMAT(@Days, '0.##', 'en-US'), N')'));
        END
        ELSE
        BEGIN
            DECLARE @Year INT = YEAR(@StartDate);
            DECLARE @Seq INT = ISNULL((SELECT MAX(TRY_CAST(RIGHT(RequestNo, 5) AS INT)) FROM [Leave].[LeaveRequests] WITH (UPDLOCK, HOLDLOCK)
                                       WHERE RequestNo LIKE CONCAT('LV-', @Year, '-%')), 0) + 1;
            INSERT INTO [Leave].[LeaveRequests] (RequestNo, CompanyId, EmployeeId, LeaveTypeId, StartDate, EndDate, HalfDay, Days, PlannedDays, Reason,
                   Status, ApprovalLevel, ManagerUserId, DecidedBy, DecidedDate, DocumentPath, DocumentName, DocumentType, DocumentSize,
                   EnteredByHr, CreatedBy)
            VALUES (CONCAT('LV-', @Year, '-', RIGHT(CONCAT('00000', @Seq), 5)), @eCo, @EmployeeId, @LeaveTypeId, @StartDate, @EndDate,
                    ISNULL(@HalfDay, 0), @Days, @Days, @Reason,
                    CASE WHEN @Final = 1 THEN 'APPROVED' ELSE 'PENDING' END, @Level, @MgrUser,
                    CASE WHEN @Final = 1 THEN @UserId END, CASE WHEN @Final = 1 THEN @Now END,
                    @DocumentPath, @DocumentName, @DocumentType, @DocumentSize, ISNULL(@IsHr, 0), @UserId);
            SET @Id = SCOPE_IDENTITY();
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
            VALUES (@Id, 'SUBMITTED', @UserId, @Reason);
        END;
        IF @Final = 1
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'APPROVED', @UserId, N'Entered and approved by HR');
        COMMIT;

        SELECT @NewId = @Id,
               @ResultMessage = CASE WHEN @Final = 1 THEN N'Leave request saved and approved.'
                                     WHEN @Level = 1 THEN N'Leave request sent to the line manager for approval.'
                                     ELSE N'Leave request sent to HR for approval.' END;
        RETURN;
    END;

    /* ======================= decisions ============================ */
    DECLARE @rStatus VARCHAR(12), @rLevel TINYINT, @rEmp BIGINT, @rCo INT, @rMgr BIGINT, @rStart DATE, @rEnd DATE, @rType INT, @rHalf BIT, @rCreator BIGINT;
    SELECT @rStatus = Status, @rLevel = ApprovalLevel, @rEmp = EmployeeId, @rCo = CompanyId, @rMgr = ManagerUserId,
           @rStart = StartDate, @rEnd = EndDate, @rType = LeaveTypeId, @rHalf = HalfDay, @rCreator = CreatedBy
    FROM   [Leave].[LeaveRequests] WHERE LeaveRequestId = @Id AND Deleted = 0;

    IF @rStatus IS NULL AND @Action IN ('APPROVE', 'REJECT', 'CANCEL', 'RETURN')
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That request was not found.'; RETURN; END;

    /* HR actions stay inside the user's companies; a line manager acts on their own team */
    DECLARE @InScope BIT = CASE WHEN (@CompanyId IS NULL OR @rCo = @CompanyId)
                                     AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(@rCo AS NVARCHAR(12)) + N',', @Csv) > 0) THEN 1 ELSE 0 END;

    IF @Action IN ('APPROVE', 'REJECT')
    BEGIN
        IF @rStatus <> 'PENDING'
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'This request has already been decided.'; RETURN; END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @rLevel
        BEGIN SELECT @ResultCode = 'STALE', @ResultMessage = N'Someone else has acted on this request - reload the list.'; RETURN; END;
        IF NOT ((@rLevel = 1 AND (@rMgr = @UserId OR (@CanApproveL1 = 1 AND @InScope = 1)))
                OR (@rLevel = 2 AND @CanApproveL2 = 1 AND @InScope = 1))
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You are not an approver for this step.'; RETURN; END;
        IF @rEmp = ISNULL(@MyEmployee, 0) AND @AllowSelf = 0
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You cannot approve your own leave.'; RETURN; END;
        IF @Action = 'REJECT' AND @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for rejecting.'; RETURN; END;

        BEGIN TRANSACTION;
        IF @Action = 'REJECT'
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET Status = 'REJECTED', DecidedBy = @UserId, DecidedDate = @Now, DecisionComment = @Comment, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'REJECTED', @UserId, @Comment);
            SET @ResultMessage = N'Leave request rejected.';
        END
        ELSE IF @rLevel = 1
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET ApprovalLevel = 2, ManagerApprovedBy = @UserId, ManagerApprovedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'MANAGER_APPROVED', @UserId, @Comment);
            SET @ResultMessage = N'Approved - sent to HR for the final approval.';
        END
        ELSE
        BEGIN
            UPDATE [Leave].[LeaveRequests]
               SET Status = 'APPROVED', DecidedBy = @UserId, DecidedDate = @Now, DecisionComment = @Comment, ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE LeaveRequestId = @Id;
            INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'APPROVED', @UserId, @Comment);
            SET @ResultMessage = N'Leave request approved.';
        END;
        COMMIT;
        SET @NewId = @Id;
        RETURN;
    END;

    IF @Action = 'CANCEL'
    BEGIN
        IF @rStatus NOT IN ('PENDING', 'APPROVED')
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'This request can no longer be cancelled.'; RETURN; END;
        /* the employee cancels their own request until the leave starts; HR (in scope) at any time */
        IF NOT ((@IsHr = 1 AND @InScope = 1)
                OR (@rEmp = ISNULL(@MyEmployee, 0) AND (@rStatus = 'PENDING' OR @rStart > @Today)))
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'Only HR can cancel a leave that has started.'; RETURN; END;

        BEGIN TRANSACTION;
        UPDATE [Leave].[LeaveRequests]
           SET Status = 'CANCELLED', CancelledBy = @UserId, CancelledDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE LeaveRequestId = @Id;
        INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment) VALUES (@Id, 'CANCELLED', @UserId, @Comment);
        COMMIT;
        SELECT @NewId = @Id, @ResultMessage = N'Leave request cancelled - the days are back in the balance.';
        RETURN;
    END;

    IF @Action = 'RETURN'
    BEGIN
        IF @rStatus <> 'APPROVED'
        BEGIN SELECT @ResultCode = 'INVALID_STATUS', @ResultMessage = N'The return can be recorded for an approved leave only.'; RETURN; END;
        IF NOT (@IsHr = 1 AND @InScope = 1)
        BEGIN SELECT @ResultCode = 'FORBIDDEN', @ResultMessage = N'You do not have permission to do this.'; RETURN; END;
        IF @ReturnDate IS NULL OR @ReturnDate <= @rStart OR DATEDIFF(DAY, @rStart, @ReturnDate) > 400
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The return date must be after the first day of the leave.'; RETURN; END;

        DECLARE @ActualEnd DATE = DATEADD(DAY, -1, @ReturnDate);
        DECLARE @ActualDays DECIMAL(6, 2) = [Leave].[fn_LeaveDays](@rCo, @rType, @rStart, @ActualEnd, CASE WHEN @ActualEnd = @rStart THEN @rHalf ELSE 0 END);
        IF @ActualEnd > @rEnd
           AND EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] r
                       WHERE r.EmployeeId = @rEmp AND r.Deleted = 0 AND r.Status IN ('PENDING', 'APPROVED') AND r.LeaveRequestId <> @Id
                         AND r.StartDate <= @ActualEnd AND ISNULL(r.ActualEndDate, r.EndDate) >= @rStart)
        BEGIN SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'The late return runs into another leave of the employee.'; RETURN; END;

        BEGIN TRANSACTION;
        UPDATE [Leave].[LeaveRequests]
           SET ActualReturnDate = @ReturnDate, ActualEndDate = @ActualEnd, Days = @ActualDays,
               ReturnRecordedBy = @UserId, ReturnRecordedDate = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
         WHERE LeaveRequestId = @Id;
        INSERT INTO [Leave].[LeaveRequestHistory] (LeaveRequestId, ActionCode, ActionBy, Comment)
        VALUES (@Id, 'RETURNED', @UserId,
                CONCAT(N'Back on ', FORMAT(@ReturnDate, 'dd/MM/yyyy', 'en-US'), N' - ', FORMAT(@ActualDays, '0.##', 'en-US'), N' days',
                       CASE WHEN @Comment IS NULL THEN N'' ELSE N' - ' + @Comment END));
        COMMIT;
        SELECT @NewId = @Id,
               @ResultMessage = CASE WHEN @ActualEnd < @rEnd THEN N'Early return recorded - the unused days are back in the balance.'
                                     WHEN @ActualEnd > @rEnd THEN N'Late return recorded - the extra days are counted.'
                                     ELSE N'Return to work recorded.' END;
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ------------------------------------------------------------------
   Leave.usp_LeaveBalance_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Leave].[usp_LeaveBalance_Manage]
    @Action        VARCHAR(20),
    @Id            BIGINT          = NULL,
    @CompanyId     INT             = NULL,
    @CompanyIds    NVARCHAR(2000)  = NULL,
    @AsOf          DATE            = NULL,
    @EmployeeId    BIGINT          = NULL,
    @LeaveTypeId   INT             = NULL,
    @Category      VARCHAR(12)     = NULL,
    @Search        NVARCHAR(200)   = NULL,
    @SelfOnly      BIT             = 0,
    @EntryType     VARCHAR(10)     = NULL,
    @EntryDate     DATE            = NULL,
    @Days          DECIMAL(7, 2)   = NULL,
    @Comment       NVARCHAR(500)   = NULL,
    @PageNumber    INT             = 1,
    @PageSize      INT             = 25,
    @UserId        BIGINT          = NULL,

    @TotalCount    INT             = NULL OUTPUT,
    @NewId         BIGINT          = NULL OUTPUT,
    @ResultCode    VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE), @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    SET @AsOf = ISNULL(@AsOf, @Today);
    SET @Search = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* the employee is in the user's companies (My Leave: the user's own employee, checked by the caller) */
    DECLARE @EmpOk BIT = CASE WHEN @EmployeeId IS NULL THEN 1
                              WHEN @SelfOnly = 1 THEN 1
                              WHEN EXISTS (SELECT 1 FROM [Employee].[Employees] e WHERE e.EmployeeId = @EmployeeId AND e.Deleted = 0
                                             AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                                             AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)) THEN 1
                              ELSE 0 END;
    IF @EmpOk = 0
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee.'; RETURN; END;

    /* ======================= LIST - employee x type ============== */
    IF @Action = 'LIST'
    BEGIN
        SET @PageNumber = CASE WHEN @PageNumber < 1 THEN 1 ELSE @PageNumber END;
        SET @PageSize = CASE WHEN @PageSize < 1 THEN 25 WHEN @PageSize > 5000 THEN 5000 ELSE @PageSize END;
        SELECT  b.EmployeeId, ISNULL(e.EmployeeCode, e.EmployeeNo) AS EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                co.CompanyName, d.DepartmentName, e.HireDate,
                b.LeaveTypeId, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted, b.Entitled, b.Taken, b.Pending, b.Available,
                COUNT(1) OVER () AS TotalRows
        INTO    #B
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = b.EmployeeId
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        LEFT JOIN [Core].[Companies] AS co ON co.CompanyId = e.CompanyId
        LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
        WHERE   e.IsDeleted = 0 AND NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned'))
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0)
          AND   (@LeaveTypeId IS NULL OR b.LeaveTypeId = @LeaveTypeId)
          AND   (@Category IS NULL OR t.Category = @Category)
          AND   (@Search IS NULL OR e.FirstName LIKE N'%' + @Search + N'%' OR e.LastName LIKE N'%' + @Search + N'%'
                 OR e.EmployeeCode LIKE N'%' + @Search + N'%' OR e.EmployeeNo LIKE N'%' + @Search + N'%');

        SELECT @TotalCount = ISNULL(MAX(TotalRows), 0) FROM #B;
        SELECT * FROM #B
        ORDER BY EmployeeName, LeaveTypeId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= EMPLOYEE - one employee's balances ==== */
    IF @Action = 'EMPLOYEE'
    BEGIN
        SELECT  b.EmployeeId, b.LeaveTypeId, t.TypeCode, t.TypeName, t.ArabicName AS TypeArabicName, t.Color, t.Category, t.BalanceMode,
                t.AccrualMethod, t.DaysPerYear, t.PayType, b.WinStart, b.OpeningDate, b.OpeningDays, b.Earned, b.Adjusted,
                b.Entitled, b.Taken, b.Pending, b.Available
        FROM    [Leave].[tvf_Balances](@AsOf, @EmployeeId) AS b
        JOIN    [Leave].[LeaveTypes] AS t ON t.LeaveTypeId = b.LeaveTypeId
        WHERE   @EmployeeId IS NOT NULL
        ORDER BY t.SortOrder, t.TypeName;
        RETURN;
    END;

    /* ======================= LEDGER - how a balance is made up ===== */
    IF @Action = 'LEDGER'
    BEGIN
        SELECT  'ENTRY' AS Kind, l.EntryId AS RefId, l.EntryType AS Code, l.EntryDate AS OnDate, NULL AS ToDate, l.Days, l.Comment,
                u.Username AS ByName, l.CreatedDate, NULL AS RequestNo, NULL AS Status
        FROM    [Leave].[LeaveLedger] AS l
        LEFT JOIN [Security].[Users] AS u ON u.UserId = l.CreatedBy
        WHERE   l.EmployeeId = @EmployeeId AND l.LeaveTypeId = @LeaveTypeId AND l.Deleted = 0
        UNION ALL
        SELECT  'REQUEST', r.LeaveRequestId, 'TAKEN', r.StartDate, ISNULL(r.ActualEndDate, r.EndDate), -r.Days, r.Reason,
                u.Username, r.CreatedDate, r.RequestNo, r.Status
        FROM    [Leave].[LeaveRequests] AS r
        LEFT JOIN [Security].[Users] AS u ON u.UserId = r.CreatedBy
        WHERE   r.EmployeeId = @EmployeeId AND r.LeaveTypeId = @LeaveTypeId AND r.Deleted = 0 AND r.Status IN ('APPROVED', 'PENDING')
        ORDER BY OnDate DESC, CreatedDate DESC;
        RETURN;
    END;

    /* ======================= ADJUST / OPENING ===================== */
    IF @Action = 'ADJUST'
    BEGIN
        DECLARE @eCo INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId AND Deleted = 0);
        IF @eCo IS NULL OR NOT EXISTS (SELECT 1 FROM [Leave].[LeaveTypes] WHERE LeaveTypeId = @LeaveTypeId AND CompanyId = @eCo AND Deleted = 0)
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Choose the employee and leave type.'; RETURN; END;
        IF @EntryType NOT IN ('OPENING', 'ADJUST') OR @Days IS NULL OR @Days NOT BETWEEN -999 AND 999
           OR (@EntryType = 'OPENING' AND @Days < 0) OR (@EntryType = 'ADJUST' AND @Days = 0)
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the number of days (an opening balance cannot be negative).'; RETURN; END;
        IF @EntryType = 'ADJUST' AND @Comment IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for the adjustment.'; RETURN; END;
        SET @EntryDate = ISNULL(@EntryDate, @Today);

        INSERT INTO [Leave].[LeaveLedger] (CompanyId, EmployeeId, LeaveTypeId, EntryType, EntryDate, Days, Comment, CreatedBy)
        VALUES (@eCo, @EmployeeId, @LeaveTypeId, @EntryType, @EntryDate, @Days, @Comment, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CASE WHEN @EntryType = 'OPENING' THEN N'Opening balance saved.' ELSE N'Balance adjusted.' END;
        RETURN;
    END;

    IF @Action = 'DELETE_ENTRY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Leave].[LeaveLedger] l JOIN [Employee].[Employees] e ON e.EmployeeId = l.EmployeeId
                       WHERE l.EntryId = @Id AND l.Deleted = 0
                         AND (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
                         AND (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0))
        BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record was not found.'; RETURN; END;
        UPDATE [Leave].[LeaveLedger] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EntryId = @Id;
        SELECT @NewId = @Id, @ResultMessage = N'Balance entry removed.';
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO
