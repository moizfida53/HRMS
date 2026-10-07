/* =====================================================================
   30_Payroll_Master_StoredProcedures.sql  -  HRMS Kuwait: Payroll Phase 1
   ---------------------------------------------------------------------
   Run AFTER 29_Payroll_Master_Tables.sql.

   Every master uses the same envelope as the Organization Setup
   procedures, so Data/Repositories/MasterRepositoryBase can drive them:

       @Action  LIST | GET | INSERT | UPDATE | DELETE | TOGGLE  (+ extras)
       @Id, @Search, @IsActiveFilter, @CompanyId, @CompanyIds, @ParentId,
       @PageNumber, @PageSize, @SortColumn, @SortDirection, @UserId
       OUT: @TotalCount, @NewId, @ResultCode, @ResultMessage

   Extra actions
     usp_PayrollPeriod_Manage       GENERATE, SET_STATUS, HISTORY
     usp_PayComponent_Manage        SEED  (insert the minimum component set
                                           for @CompanyId if missing)
     usp_SalaryStructure_Manage     LINES, RESOLVE
     usp_IndemnityRuleSet_Manage    SLABS, FACTORS

   Header + lines are saved in ONE call (atomic) by passing the lines as
   JSON (@LinesJson, @SlabsJson, @FactorsJson). Requires database
   compatibility level 130+ (SQL Server 2016+) for OPENJSON.

   DELETE always means Deleted = 1 (soft delete) - see script 28.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* =====================================================================
   Payroll.ufn_IbanIsValid  -  ISO 13616 mod-97 check
   ---------------------------------------------------------------------
   Returns 1 when the IBAN's check digits are correct. Kuwait IBANs
   (country KW) must also be exactly 30 characters.
   Catches the typical one-wrong-digit typo before a salary is sent to
   the wrong account.
===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_IbanIsValid] (@Iban NVARCHAR(50))
RETURNS BIT
AS
BEGIN
    DECLARE @s VARCHAR(50) = UPPER(REPLACE(REPLACE(CAST(ISNULL(@Iban, N'') AS VARCHAR(50)), ' ', ''), '-', ''));

    IF LEN(@s) < 15 OR LEN(@s) > 34 RETURN 0;
    IF @s LIKE '%[^A-Z0-9]%'         RETURN 0;
    IF LEFT(@s, 2) LIKE '%[^A-Z]%'   RETURN 0;
    IF SUBSTRING(@s, 3, 2) LIKE '%[^0-9]%' RETURN 0;
    IF LEFT(@s, 2) = 'KW' AND LEN(@s) <> 30 RETURN 0;

    DECLARE @r VARCHAR(50) = SUBSTRING(@s, 5, 50) + LEFT(@s, 4);
    DECLARE @i INT = 1, @n INT = LEN(@r), @c CHAR(1), @mod INT = 0, @v INT;

    WHILE @i <= @n
    BEGIN
        SET @c = SUBSTRING(@r, @i, 1);
        IF @c BETWEEN '0' AND '9'
            SET @mod = (@mod * 10 + (ASCII(@c) - 48)) % 97;
        ELSE
        BEGIN
            SET @v = ASCII(@c) - 55;              -- A = 10 ... Z = 35
            SET @mod = (@mod * 100 + @v) % 97;
        END;
        SET @i += 1;
    END;

    RETURN CASE WHEN @mod = 1 THEN 1 ELSE 0 END;
END;
GO

/* =====================================================================
   Payroll.usp_PayrollCalendar_Manage
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollCalendar_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    /* ---- LIST filters and paging ------------------------------- */
    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @CalendarCode             NVARCHAR(30)    = NULL,
    @CalendarName             NVARCHAR(150)   = NULL,
    @ArabicName               NVARCHAR(150)   = NULL,
    @PayFrequency             VARCHAR(10)     = NULL,
    @FirstPeriodStartDate     DATE            = NULL,
    @CutOffDay                TINYINT         = NULL,
    @PaymentDay               TINYINT         = NULL,
    @PaymentMonthOffset       TINYINT         = NULL,
    @CutOffOffsetDays         SMALLINT        = NULL,
    @PaymentOffsetDays        SMALLINT        = NULL,
    @WorkingDaysBasis         VARCHAR(10)     = NULL,
    @FixedDaysPerMonth        TINYINT         = NULL,
    @CurrencyId               INT             = NULL,
    @Description              NVARCHAR(500)   = NULL,
    @IsDefault                BIT             = NULL,
    @IsActive                 BIT             = NULL,

    /* ---- audit ------------------------------------------------- */
    @UserId                   BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------- */
    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[PayrollCalendars] AS pc
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR pc.CalendarCode LIKE @Pattern ESCAPE '\' OR pc.CalendarName LIKE @Pattern ESCAPE '\');

        SELECT  pc.PayrollCalendarId, pc.CompanyId, pc.CalendarCode, pc.CalendarName, pc.ArabicName,
                pc.PayFrequency, pc.FirstPeriodStartDate, pc.CutOffDay, pc.PaymentDay, pc.PaymentMonthOffset,
                pc.CutOffOffsetDays, pc.PaymentOffsetDays, pc.WorkingDaysBasis, pc.FixedDaysPerMonth,
                pc.CurrencyId, pc.Description, pc.IsDefault, pc.IsActive,
                c.CompanyName, cu.CurrencyCode,
                (SELECT COUNT(1) FROM [Payroll].[PayrollPeriods] p WHERE p.Deleted = 0 AND p.PayrollCalendarId = pc.PayrollCalendarId) AS PeriodCount,
                (SELECT TOP 1 p.PeriodName FROM [Payroll].[PayrollPeriods] p
                  WHERE p.Deleted = 0 AND p.PayrollCalendarId = pc.PayrollCalendarId AND p.Status <> 'CLOSED'
                  ORDER BY p.StartDate) AS CurrentPeriodName
        FROM        [Payroll].[PayrollCalendars] AS pc
        INNER JOIN  [Core].[Companies]           AS c  ON c.CompanyId   = pc.CompanyId
        LEFT JOIN   [Core].[Currencies]          AS cu ON cu.CurrencyId = pc.CurrencyId
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR pc.CalendarCode LIKE @Pattern ESCAPE '\' OR pc.CalendarName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CalendarCode' THEN pc.CalendarCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CalendarCode' THEN pc.CalendarCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CalendarName' THEN pc.CalendarName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CalendarName' THEN pc.CalendarName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'PayFrequency' THEN pc.PayFrequency END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'PayFrequency' THEN pc.PayFrequency END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName'  THEN c.CompanyName  END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName'  THEN c.CompanyName  END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'     THEN pc.IsActive    END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'     THEN pc.IsActive    END DESC,
                pc.CalendarName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  pc.PayrollCalendarId, pc.CompanyId, pc.CalendarCode, pc.CalendarName, pc.ArabicName,
                pc.PayFrequency, pc.FirstPeriodStartDate, pc.CutOffDay, pc.PaymentDay, pc.PaymentMonthOffset,
                pc.CutOffOffsetDays, pc.PaymentOffsetDays, pc.WorkingDaysBasis, pc.FixedDaysPerMonth,
                pc.CurrencyId, pc.Description, pc.IsDefault, pc.IsActive,
                c.CompanyName, cu.CurrencyCode,
                (SELECT COUNT(1) FROM [Payroll].[PayrollPeriods] p WHERE p.Deleted = 0 AND p.PayrollCalendarId = pc.PayrollCalendarId) AS PeriodCount,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] p
                                       WHERE p.Deleted = 0 AND p.PayrollCalendarId = pc.PayrollCalendarId AND p.Status <> 'OPEN')
                          THEN 1 ELSE 0 END AS BIT) AS IsScheduleLocked
        FROM        [Payroll].[PayrollCalendars] AS pc
        INNER JOIN  [Core].[Companies]           AS c  ON c.CompanyId   = pc.CompanyId
        LEFT JOIN   [Core].[Currencies]          AS cu ON cu.CurrencyId = pc.CurrencyId
        WHERE pc.PayrollCalendarId = @Id AND pc.Deleted = 0;
        RETURN;
    END;

    /* ======================= shared validation =================== */
    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SET @PayFrequency     = UPPER(LTRIM(RTRIM(@PayFrequency)));
        SET @WorkingDaysBasis = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@WorkingDaysBasis)), ''), 'FIXED'));
        SET @PaymentMonthOffset = ISNULL(@PaymentMonthOffset, 0);

        IF @CompanyId IS NULL OR NULLIF(LTRIM(RTRIM(@CalendarCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@CalendarName)), N'') IS NULL
           OR @FirstPeriodStartDate IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Company, code, name and first period start date are required.';
            RETURN;
        END;

        IF @PayFrequency NOT IN ('MONTHLY', 'BIWEEKLY', 'WEEKLY')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Payroll frequency must be Monthly, Bi-weekly or Weekly.';
            RETURN;
        END;

        IF @PayFrequency = 'MONTHLY'
        BEGIN
            IF @CutOffDay IS NULL OR @PaymentDay IS NULL
               OR @CutOffDay NOT BETWEEN 1 AND 31 OR @PaymentDay NOT BETWEEN 1 AND 31
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A monthly calendar needs a cut-off day and a payment day between 1 and 31.';
                RETURN;
            END;
            IF DAY(@FirstPeriodStartDate) > 28
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'For a monthly calendar the period start day must be between 1 and 28 so every month has it.';
                RETURN;
            END;
            SELECT @CutOffOffsetDays = NULL, @PaymentOffsetDays = NULL;
        END
        ELSE
        BEGIN
            IF @CutOffOffsetDays IS NULL OR @PaymentOffsetDays IS NULL
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A weekly / bi-weekly calendar needs cut-off and payment offsets (days from period end).';
                RETURN;
            END;
            SELECT @CutOffDay = NULL, @PaymentDay = NULL, @PaymentMonthOffset = 0;
        END;

        IF @WorkingDaysBasis NOT IN ('CALENDAR', 'FIXED', 'WORKING')
           OR (@WorkingDaysBasis = 'FIXED' AND ISNULL(@FixedDaysPerMonth, 0) NOT BETWEEN 1 AND 31)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Working days basis is invalid. A fixed basis needs the number of days (e.g. 26 or 30).';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                   WHERE Deleted = 0 AND CompanyId = @CompanyId AND CalendarCode = @CalendarCode
                     AND (@Action = 'INSERT' OR PayrollCalendarId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            IF ISNULL(@IsDefault, 0) = 1
                UPDATE [Payroll].[PayrollCalendars] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE CompanyId = @CompanyId AND IsDefault = 1 AND Deleted = 0;

            INSERT INTO [Payroll].[PayrollCalendars]
                (CompanyId, CalendarCode, CalendarName, ArabicName, PayFrequency, FirstPeriodStartDate,
                 CutOffDay, PaymentDay, PaymentMonthOffset, CutOffOffsetDays, PaymentOffsetDays,
                 WorkingDaysBasis, FixedDaysPerMonth, CurrencyId, Description, IsDefault, IsActive, CreatedBy)
            VALUES
                (@CompanyId, @CalendarCode, @CalendarName, @ArabicName, @PayFrequency, @FirstPeriodStartDate,
                 @CutOffDay, @PaymentDay, @PaymentMonthOffset, @CutOffOffsetDays, @PaymentOffsetDays,
                 @WorkingDaysBasis, CASE WHEN @WorkingDaysBasis = 'FIXED' THEN @FixedDaysPerMonth END,
                 @CurrencyId, @Description, ISNULL(@IsDefault, 0), ISNULL(@IsActive, 1), @UserId);

            SET @NewId = SCOPE_IDENTITY();
        COMMIT;
        SET @ResultMessage = N'Payroll calendar created successfully. Use "Generate periods" to create its pay periods.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        DECLARE @OldCompanyId INT, @OldFrequency VARCHAR(10), @OldStart DATE;
        SELECT @OldCompanyId = CompanyId, @OldFrequency = PayFrequency, @OldStart = FirstPeriodStartDate
        FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @Id AND Deleted = 0;

        IF @OldCompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;

        /* Once a period has left OPEN, the schedule that produced it is frozen. */
        IF (@OldCompanyId <> @CompanyId OR @OldFrequency <> @PayFrequency OR @OldStart <> @FirstPeriodStartDate)
           AND EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] WHERE Deleted = 0 AND PayrollCalendarId = @Id AND Status <> 'OPEN')
        BEGIN
            SELECT @ResultCode = 'SCHEDULE_LOCKED',
                   @ResultMessage = N'Payroll has already been processed on this calendar, so its company, frequency and start date can no longer change. Create a new calendar instead.';
            RETURN;
        END;

        BEGIN TRAN;
            IF ISNULL(@IsDefault, 0) = 1
                UPDATE [Payroll].[PayrollCalendars] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE CompanyId = @CompanyId AND IsDefault = 1 AND Deleted = 0 AND PayrollCalendarId <> @Id;

            UPDATE [Payroll].[PayrollCalendars]
               SET CompanyId            = @CompanyId,
                   CalendarCode         = @CalendarCode,
                   CalendarName         = @CalendarName,
                   ArabicName           = @ArabicName,
                   PayFrequency         = @PayFrequency,
                   FirstPeriodStartDate = @FirstPeriodStartDate,
                   CutOffDay            = @CutOffDay,
                   PaymentDay           = @PaymentDay,
                   PaymentMonthOffset   = @PaymentMonthOffset,
                   CutOffOffsetDays     = @CutOffOffsetDays,
                   PaymentOffsetDays    = @PaymentOffsetDays,
                   WorkingDaysBasis     = @WorkingDaysBasis,
                   FixedDaysPerMonth    = CASE WHEN @WorkingDaysBasis = 'FIXED' THEN @FixedDaysPerMonth END,
                   CurrencyId           = @CurrencyId,
                   Description          = @Description,
                   IsDefault            = ISNULL(@IsDefault, 0),
                   IsActive             = ISNULL(@IsActive, IsActive),
                   ModifiedBy           = @UserId,
                   ModifiedDate         = SYSUTCDATETIME()
             WHERE PayrollCalendarId = @Id;

            IF @OldCompanyId <> @CompanyId
                UPDATE [Payroll].[PayrollPeriods] SET CompanyId = @CompanyId, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE PayrollCalendarId = @Id AND Deleted = 0;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Payroll calendar updated successfully. Existing OPEN periods keep their dates; edit them on the Periods list if needed.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] WHERE Deleted = 0 AND PayrollCalendarId = @Id)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods]   WHERE Deleted = 0 AND PayrollCalendarId = @Id AND Status <> 'OPEN')
           OR EXISTS (SELECT 1 FROM [Payroll].[SalaryStructures] WHERE Deleted = 0 AND PayrollCalendarId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This calendar has processed periods or is used by a salary structure and cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        BEGIN TRAN;
            UPDATE [Payroll].[PayrollPeriods]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE PayrollCalendarId = @Id AND Deleted = 0;           -- only OPEN periods can remain here

            UPDATE [Payroll].[PayrollCalendars]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME(), IsDefault = 0
             WHERE PayrollCalendarId = @Id AND Deleted = 0;
        COMMIT;

        SET @ResultMessage = N'Payroll calendar deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] WHERE Deleted = 0 AND PayrollCalendarId = @Id)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists.';
            RETURN;
        END;

        UPDATE [Payroll].[PayrollCalendars]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END,
               IsDefault = CASE WHEN IsActive = 1 THEN 0 ELSE IsDefault END,   -- an inactive calendar cannot stay default
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PayrollCalendarId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Payroll calendar activated.' ELSE N'Payroll calendar deactivated.' END
        FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_PayrollPeriod_Manage
   ---------------------------------------------------------------------
   LIST        @ParentId = PayrollCalendarId (required), @PeriodYear,
               @StatusFilter optional
   GET         one period
   GENERATE    @ParentId = calendar, @PeriodYear = year: creates any
               missing periods of that year (existing ones untouched)
   UPDATE      dates / remarks - only while the period is OPEN
   SET_STATUS  @NewStatus (+ @Remarks). Allowed moves:
                 OPEN -> PROCESSING -> APPROVED -> POSTED -> CLOSED
                 PROCESSING -> OPEN,  APPROVED -> PROCESSING  (re-open)
               A period can only start PROCESSING when every earlier
               period of the same calendar is POSTED or CLOSED.
   HISTORY     status history of @Id
   DELETE      only an OPEN period that has no later period after it
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollPeriod_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,   -- not used (periods have a status, not IsActive)
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,   -- PayrollCalendarId
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',
    @PeriodYear               SMALLINT        = NULL,
    @StatusFilter             VARCHAR(12)     = NULL,

    /* ---- editable columns -------------------------------------- */
    @StartDate                DATE            = NULL,
    @EndDate                  DATE            = NULL,
    @CutOffDate               DATE            = NULL,
    @PaymentDate              DATE            = NULL,
    @PeriodName               NVARCHAR(100)   = NULL,
    @Remarks                  NVARCHAR(500)   = NULL,
    @NewStatus                VARCHAR(12)     = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'GENERATE', 'UPDATE', 'SET_STATUS', 'HISTORY', 'DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    SET @StatusFilter  = NULLIF(UPPER(LTRIM(RTRIM(@StatusFilter))), '');

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Payroll].[PayrollPeriods]   AS p
        INNER JOIN  [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        WHERE p.Deleted = 0 AND pc.Deleted = 0
          AND (@ParentId     IS NULL OR p.PayrollCalendarId = @ParentId)
          AND (@CompanyId    IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds   IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@PeriodYear   IS NULL OR p.PayrollYear = @PeriodYear)
          AND (@StatusFilter IS NULL OR p.Status = @StatusFilter);

        SELECT  p.PayrollPeriodId, p.PayrollCalendarId, p.PayrollYear AS PeriodYear, p.PayrollMonth, p.PeriodNumber, p.PeriodCode, p.PeriodName,
                p.StartDate, p.EndDate, p.CutOffDate, p.PaymentDate, p.Status, p.StatusChangedDate, p.Remarks,
                pc.CalendarCode, pc.CalendarName, pc.PayFrequency, pc.CompanyId,
                DATEDIFF(DAY, p.StartDate, p.EndDate) + 1 AS CalendarDays
        FROM        [Payroll].[PayrollPeriods]   AS p
        INNER JOIN  [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        WHERE p.Deleted = 0 AND pc.Deleted = 0
          AND (@ParentId     IS NULL OR p.PayrollCalendarId = @ParentId)
          AND (@CompanyId    IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds   IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@PeriodYear   IS NULL OR p.PayrollYear = @PeriodYear)
          AND (@StatusFilter IS NULL OR p.Status = @StatusFilter)
        ORDER BY
                CASE WHEN @SortDirection = 'DESC' AND ISNULL(@SortColumn, 'StartDate') = 'StartDate' THEN p.StartDate END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'Status' THEN p.Status END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'Status' THEN p.Status END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'PaymentDate' THEN p.PaymentDate END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'PaymentDate' THEN p.PaymentDate END DESC,
                p.StartDate ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  p.PayrollPeriodId, p.PayrollCalendarId, p.PayrollYear AS PeriodYear, p.PayrollMonth, p.PeriodNumber, p.PeriodCode, p.PeriodName,
                p.StartDate, p.EndDate, p.CutOffDate, p.PaymentDate, p.Status, p.StatusChangedBy, p.StatusChangedDate, p.Remarks,
                pc.CalendarCode, pc.CalendarName, pc.PayFrequency, pc.CompanyId
        FROM        [Payroll].[PayrollPeriods]   AS p
        INNER JOIN  [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = p.PayrollCalendarId
        WHERE p.PayrollPeriodId = @Id AND p.Deleted = 0;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        SELECT h.PeriodStatusHistoryId, h.PayrollPeriodId, h.FromStatus, h.ToStatus, h.Remarks, h.ChangedBy, h.ChangedDate
        FROM   [Payroll].[PayrollPeriodStatusHistory] AS h
        WHERE  h.PayrollPeriodId = @Id AND h.Deleted = 0
        ORDER BY h.ChangedDate DESC, h.PeriodStatusHistoryId DESC;
        RETURN;
    END;

    /* ======================= GENERATE ============================ */
    IF @Action = 'GENERATE'
    BEGIN
        DECLARE @Freq VARCHAR(10), @Anchor DATE, @CutDay TINYINT, @PayDay TINYINT, @PayMonthOffset TINYINT,
                @CutOffset SMALLINT, @PayOffset SMALLINT, @CalActive BIT, @CalCompanyId INT;

        SELECT @Freq = PayFrequency, @Anchor = FirstPeriodStartDate, @CutDay = CutOffDay, @PayDay = PaymentDay,
               @PayMonthOffset = PaymentMonthOffset, @CutOffset = CutOffOffsetDays, @PayOffset = PaymentOffsetDays,
               @CalActive = IsActive, @CalCompanyId = CompanyId
        FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @ParentId AND Deleted = 0;

        IF @Freq IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select a payroll calendar first.';
            RETURN;
        END;
        IF @CalActive = 0
        BEGIN
            SELECT @ResultCode = 'INACTIVE', @ResultMessage = N'This calendar is inactive. Activate it before generating periods.';
            RETURN;
        END;
        IF @PeriodYear IS NULL OR @PeriodYear NOT BETWEEN 2000 AND 2100
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the year to generate (2000 - 2100).';
            RETURN;
        END;

        DECLARE @Gen TABLE (PeriodNumber TINYINT, StartDate DATE, EndDate DATE, CutOffDate DATE, PaymentDate DATE,
                            PeriodCode NVARCHAR(30), PeriodName NVARCHAR(100));

        IF @Freq = 'MONTHLY'
        BEGIN
            /* Period n is named after month n. With a start day of 1 it is the
               calendar month; with start day d > 1 it runs from day d of the
               previous month to day d-1 of month n (e.g. 21 Sep - 20 Oct = Oct). */
            DECLARE @d INT = DAY(@Anchor);
            ;WITH m AS (SELECT TOP (12) CAST(ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) AS INT) AS n FROM sys.all_objects)
            INSERT INTO @Gen (PeriodNumber, StartDate, EndDate, PeriodCode, PeriodName)
            SELECT  m.n,
                    CASE WHEN @d = 1 THEN DATEFROMPARTS(@PeriodYear, m.n, 1)
                         ELSE DATEADD(MONTH, -1, DATEFROMPARTS(@PeriodYear, m.n, @d)) END,
                    CASE WHEN @d = 1 THEN EOMONTH(DATEFROMPARTS(@PeriodYear, m.n, 1))
                         ELSE DATEFROMPARTS(@PeriodYear, m.n, @d - 1) END,
                    CONCAT(N'M', @PeriodYear, N'-', RIGHT(CONCAT(N'0', m.n), 2)),
                    CONCAT(DATENAME(MONTH, DATEFROMPARTS(@PeriodYear, m.n, 1)), N' ', @PeriodYear)
            FROM m;

            UPDATE g
               SET CutOffDate  = DATEFROMPARTS(YEAR(g.EndDate), MONTH(g.EndDate),
                                     CASE WHEN @CutDay > DAY(EOMONTH(g.EndDate)) THEN DAY(EOMONTH(g.EndDate)) ELSE @CutDay END),
                   PaymentDate = DATEFROMPARTS(YEAR(x.PayMonth), MONTH(x.PayMonth),
                                     CASE WHEN @PayDay > DAY(EOMONTH(x.PayMonth)) THEN DAY(EOMONTH(x.PayMonth)) ELSE @PayDay END)
            FROM @Gen AS g
            CROSS APPLY (SELECT DATEADD(MONTH, @PayMonthOffset, DATEFROMPARTS(YEAR(g.EndDate), MONTH(g.EndDate), 1)) AS PayMonth) AS x;
        END
        ELSE
        BEGIN
            DECLARE @Step INT = CASE @Freq WHEN 'WEEKLY' THEN 7 ELSE 14 END;
            DECLARE @YearStart DATE = DATEFROMPARTS(@PeriodYear, 1, 1);
            DECLARE @k INT = CASE WHEN @Anchor >= @YearStart THEN 0
                                  ELSE CEILING(DATEDIFF(DAY, @Anchor, @YearStart) / CAST(@Step AS DECIMAL(9,2))) END;
            DECLARE @s DATE = DATEADD(DAY, @k * @Step, @Anchor), @no INT = 1;
            DECLARE @Prefix NCHAR(1) = CASE @Freq WHEN 'WEEKLY' THEN N'W' ELSE N'B' END;
            DECLARE @Label NVARCHAR(10) = CASE @Freq WHEN 'WEEKLY' THEN N'Week' ELSE N'Fortnight' END;

            WHILE YEAR(@s) = @PeriodYear AND @no <= 53
            BEGIN
                INSERT INTO @Gen (PeriodNumber, StartDate, EndDate, CutOffDate, PaymentDate, PeriodCode, PeriodName)
                VALUES (@no, @s, DATEADD(DAY, @Step - 1, @s),
                        DATEADD(DAY, @CutOffset, DATEADD(DAY, @Step - 1, @s)),
                        DATEADD(DAY, @PayOffset, DATEADD(DAY, @Step - 1, @s)),
                        CONCAT(@Prefix, @PeriodYear, N'-', RIGHT(CONCAT(N'0', @no), 2)),
                        CONCAT(@Label, N' ', @no, N' - ', @PeriodYear));
                SET @s = DATEADD(DAY, @Step, @s);
                SET @no += 1;
            END;
        END;

        /* Never generate before the calendar's first period. */
        DELETE FROM @Gen WHERE StartDate < @Anchor;

        DECLARE @Inserted TABLE (PayrollPeriodId INT);

        BEGIN TRAN;
            INSERT INTO [Payroll].[PayrollPeriods]
                (PayrollCalendarId, CompanyId, PayrollYear, PayrollMonth, PeriodNumber, PeriodCode, PeriodName, StartDate, EndDate, CutOffDate, PaymentDate, Status, CreatedBy)
            OUTPUT inserted.PayrollPeriodId INTO @Inserted
            SELECT @ParentId, @CalCompanyId, @PeriodYear, MONTH(g.EndDate), g.PeriodNumber, g.PeriodCode, g.PeriodName, g.StartDate, g.EndDate, g.CutOffDate, g.PaymentDate, 'OPEN', @UserId
            FROM @Gen AS g
            WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods] p
                              WHERE p.Deleted = 0 AND p.PayrollCalendarId = @ParentId
                                AND (   (p.PayrollYear = @PeriodYear AND p.PeriodNumber = g.PeriodNumber)
                                     OR (p.StartDate <= g.EndDate AND p.EndDate >= g.StartDate)));

            INSERT INTO [Payroll].[PayrollPeriodStatusHistory] (PayrollPeriodId, FromStatus, ToStatus, Remarks, ChangedBy)
            SELECT i.PayrollPeriodId, NULL, 'OPEN', N'Generated', @UserId FROM @Inserted AS i;
        COMMIT;

        SELECT @TotalCount = COUNT(1) FROM @Inserted;
        SET @ResultMessage = CASE WHEN @TotalCount = 0 THEN N'All periods for that year already exist - nothing to generate.'
                                  ELSE CONCAT(@TotalCount, N' period(s) generated for ', @PeriodYear, N'.') END;
        RETURN;
    END;

    /* ======== common existence check for UPDATE / SET_STATUS / DELETE ======== */
    DECLARE @CurStatus VARCHAR(12), @CalId INT, @CurStart DATE, @CurEnd DATE;
    SELECT @CurStatus = Status, @CalId = PayrollCalendarId, @CurStart = StartDate, @CurEnd = EndDate
    FROM [Payroll].[PayrollPeriods] WHERE PayrollPeriodId = @Id AND Deleted = 0;

    IF @CurStatus IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That period no longer exists. Refresh and try again.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        IF @CurStatus <> 'OPEN'
        BEGIN
            SELECT @ResultCode = 'PERIOD_LOCKED', @ResultMessage = N'Only an OPEN period can be edited.';
            RETURN;
        END;

        SELECT @StartDate = ISNULL(@StartDate, @CurStart), @EndDate = ISNULL(@EndDate, @CurEnd);

        IF @EndDate < @StartDate OR @CutOffDate IS NULL OR @PaymentDate IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'End date must be on or after the start date, and cut-off and payment dates are required.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods]
                   WHERE Deleted = 0 AND PayrollCalendarId = @CalId AND PayrollPeriodId <> @Id
                     AND StartDate <= @EndDate AND EndDate >= @StartDate)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'These dates overlap another period of the same calendar.';
            RETURN;
        END;

        UPDATE [Payroll].[PayrollPeriods]
           SET StartDate = @StartDate, EndDate = @EndDate, CutOffDate = @CutOffDate, PaymentDate = @PaymentDate,
               PeriodName = ISNULL(NULLIF(LTRIM(RTRIM(@PeriodName)), N''), PeriodName),
               Remarks = @Remarks, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PayrollPeriodId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Period updated successfully.';
        RETURN;
    END;

    /* ======================= SET_STATUS ========================== */
    IF @Action = 'SET_STATUS'
    BEGIN
        SET @NewStatus = UPPER(LTRIM(RTRIM(ISNULL(@NewStatus, ''))));

        IF NOT (   (@CurStatus = 'OPEN'       AND @NewStatus = 'PROCESSING')
                OR (@CurStatus = 'PROCESSING' AND @NewStatus IN ('OPEN', 'APPROVED'))
                OR (@CurStatus = 'APPROVED'   AND @NewStatus IN ('PROCESSING', 'POSTED'))
                OR (@CurStatus = 'POSTED'     AND @NewStatus = 'CLOSED'))
        BEGIN
            SELECT @ResultCode = 'INVALID_TRANSITION',
                   @ResultMessage = CONCAT(N'A period cannot move from ', @CurStatus, N' to ', NULLIF(@NewStatus, ''), N'.');
            RETURN;
        END;

        IF @NewStatus = 'PROCESSING' AND @CurStatus = 'OPEN'
           AND EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods]
                       WHERE Deleted = 0 AND PayrollCalendarId = @CalId AND StartDate < @CurStart
                         AND Status IN ('OPEN', 'PROCESSING', 'APPROVED'))
        BEGIN
            SELECT @ResultCode = 'PREVIOUS_OPEN',
                   @ResultMessage = N'An earlier period of this calendar is not posted yet. Payroll periods must be processed in order.';
            RETURN;
        END;

        BEGIN TRAN;
            UPDATE [Payroll].[PayrollPeriods]
               SET Status = @NewStatus, StatusChangedBy = @UserId, StatusChangedDate = SYSUTCDATETIME(),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE PayrollPeriodId = @Id;

            INSERT INTO [Payroll].[PayrollPeriodStatusHistory] (PayrollPeriodId, FromStatus, ToStatus, Remarks, ChangedBy)
            VALUES (@Id, @CurStatus, @NewStatus, @Remarks, @UserId);
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = CONCAT(N'Period status changed to ', @NewStatus, N'.');
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF @CurStatus <> 'OPEN'
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Only an OPEN period can be deleted.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods]
                   WHERE Deleted = 0 AND PayrollCalendarId = @CalId AND StartDate > @CurStart AND Status <> 'OPEN')
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'A later period of this calendar has already been processed, so this one cannot be deleted.';
            RETURN;
        END;

        UPDATE [Payroll].[PayrollPeriods]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE PayrollPeriodId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Period deleted successfully.';
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_PayComponent_SeedDefaults
   ---------------------------------------------------------------------
   Inserts the minimum earning / deduction set for one company, skipping
   any component whose code (or system code) the company already has.
   Called by script 32 for every existing company, and by
   usp_PayComponent_Manage @Action = 'SEED' for a company created later.

   Components with a SystemCode are the ones the payroll engine has to
   recognise; they cannot be deleted (deactivate instead) and BASIC
   cannot even be deactivated. All others are ordinary rows you can
   rename, re-flag, deactivate or delete.
   Kuwait has no personal income tax, so IsTaxable defaults to 0.
   The PIFSS / indemnity / overtime / leave flags below are sensible
   starting values - review them with the client's finance team.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayComponent_SeedDefaults]
    @CompanyId   INT,
    @UserId      BIGINT = NULL,
    @Inserted    INT    = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET @Inserted = 0;

    IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @CompanyId AND Deleted = 0)
        RETURN;

    DECLARE @Seed TABLE (
        ComponentCode NVARCHAR(30), ComponentName NVARCHAR(150), ArabicName NVARCHAR(150), ComponentType VARCHAR(10),
        ValueType VARCHAR(10), CalculationMethod VARCHAR(12), CalculationBase VARCHAR(15),
        IsPifss BIT, IsIndemnity BIT, IsOvertime BIT, IsLeaveSalary BIT, IsRecurring BIT, IsProrated BIT,
        SystemCode VARCHAR(30), DisplayOrder SMALLINT);

    INSERT INTO @Seed VALUES
    /*  code         name                                arabic                         type        value       method        base            pifss ind ot leave recur prorate systemcode         order */
    (N'BASIC',      N'Basic Salary',                    N'الراتب الأساسي',              'EARNING',  'FIXED',    'AMOUNT',     NULL,             1,   1,  1,  1,    1,    1,     'BASIC',          10),
    (N'HOUSING',    N'Housing Allowance',               N'بدل السكن',                   'EARNING',  'FIXED',    'AMOUNT',     NULL,             1,   1,  0,  1,    1,    1,     NULL,             20),
    (N'TRANSPORT',  N'Transportation Allowance',        N'بدل المواصلات',               'EARNING',  'FIXED',    'AMOUNT',     NULL,             1,   1,  0,  1,    1,    1,     NULL,             30),
    (N'FOOD',       N'Food Allowance',                  N'بدل الطعام',                  'EARNING',  'FIXED',    'AMOUNT',     NULL,             1,   1,  0,  1,    1,    1,     NULL,             40),
    (N'TELEPHONE',  N'Telephone Allowance',             N'بدل الهاتف',                  'EARNING',  'FIXED',    'AMOUNT',     NULL,             0,   0,  0,  0,    1,    1,     NULL,             50),
    (N'OTHER_ALW',  N'Other Allowances',                N'بدلات أخرى',                  'EARNING',  'FIXED',    'AMOUNT',     NULL,             0,   0,  0,  0,    1,    1,     NULL,             60),
    (N'OVERTIME',   N'Overtime',                        N'العمل الإضافي',               'EARNING',  'VARIABLE', 'HOURS',      'OVERTIME_BASE',  0,   0,  0,  0,    0,    0,     'OVERTIME',       70),
    (N'BONUS',      N'Bonus',                           N'مكافأة',                      'EARNING',  'VARIABLE', 'AMOUNT',     NULL,             0,   0,  0,  0,    0,    0,     NULL,             80),
    (N'COMMISSION', N'Commission',                      N'عمولة',                       'EARNING',  'VARIABLE', 'AMOUNT',     NULL,             0,   0,  0,  0,    0,    0,     NULL,             90),
    (N'INCENTIVE',  N'Incentives',                      N'حوافز',                       'EARNING',  'VARIABLE', 'AMOUNT',     NULL,             0,   0,  0,  0,    0,    0,     NULL,            100),
    (N'LOAN',       N'Loan',                            N'قرض',                         'DEDUCTION','VARIABLE', 'SYSTEM',     NULL,             0,   0,  0,  0,    1,    0,     'LOAN',          210),
    (N'SAL_ADV',    N'Salary Advance',                  N'سلفة على الراتب',             'DEDUCTION','VARIABLE', 'SYSTEM',     NULL,             0,   0,  0,  0,    0,    0,     'SALARY_ADVANCE',220),
    (N'ABSENCE',    N'Absence',                         N'خصم غياب',                    'DEDUCTION','VARIABLE', 'DAYS',       'FIXED_GROSS',    0,   0,  0,  0,    0,    0,     'ABSENCE',       230),
    (N'UNPAID_LV',  N'Unpaid Leave',                    N'إجازة بدون راتب',             'DEDUCTION','VARIABLE', 'DAYS',       'FIXED_GROSS',    0,   0,  0,  0,    0,    0,     'UNPAID_LEAVE',  240),
    (N'INSURANCE',  N'Insurance',                       N'التأمين',                     'DEDUCTION','FIXED',    'AMOUNT',     NULL,             0,   0,  0,  0,    1,    0,     NULL,            250),
    (N'OTHER_DED',  N'Other Deductions',                N'استقطاعات أخرى',              'DEDUCTION','VARIABLE', 'AMOUNT',     NULL,             0,   0,  0,  0,    0,    0,     NULL,            260),
    (N'PIFSS_EE',   N'Social Security (PIFSS)',         N'التأمينات الاجتماعية',        'DEDUCTION','FIXED',    'SYSTEM',     NULL,             0,   0,  0,  0,    1,    0,     'PIFSS_EE',      270);

    INSERT INTO [Payroll].[PayComponents]
        (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod, CalculationBase,
         IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable, IsRecurring, IsProrated, ShowOnPayslip,
         DisplayOrder, SystemCode, IsSystem, IsActive, CreatedBy)
    SELECT @CompanyId, s.ComponentCode, s.ComponentName, s.ArabicName, s.ComponentName, s.ComponentType, s.ValueType, s.CalculationMethod, s.CalculationBase,
           0, s.IsPifss, s.IsIndemnity, s.IsOvertime, s.IsLeaveSalary, s.IsRecurring, s.IsProrated, 1,
           s.DisplayOrder, s.SystemCode, CASE WHEN s.SystemCode IS NULL THEN 0 ELSE 1 END, 1, @UserId
    FROM @Seed AS s
    WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] pc
                      WHERE pc.Deleted = 0 AND pc.CompanyId = @CompanyId
                        AND (pc.ComponentCode = s.ComponentCode OR (s.SystemCode IS NOT NULL AND pc.SystemCode = s.SystemCode)));

    SET @Inserted = @@ROWCOUNT;
END;
GO

/* =====================================================================
   Payroll.usp_PayComponent_Manage
   ---------------------------------------------------------------------
   One procedure for BOTH earnings and deductions; the UI shows them on
   two tabs by passing @ComponentTypeFilter = 'EARNING' / 'DEDUCTION'.
   SEED inserts the minimum component set for @CompanyId (if missing).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayComponent_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',
    @ComponentTypeFilter      VARCHAR(10)     = NULL,   -- EARNING / DEDUCTION / NULL = both

    /* ---- editable columns -------------------------------------- */
    @ComponentCode            NVARCHAR(30)    = NULL,
    @ComponentName            NVARCHAR(150)   = NULL,
    @ArabicName               NVARCHAR(150)   = NULL,
    @PayslipLabel             NVARCHAR(100)   = NULL,
    @ComponentType            VARCHAR(10)     = NULL,
    @ValueType                VARCHAR(10)     = NULL,
    @CalculationMethod        VARCHAR(12)     = NULL,
    @CalculationBase          VARCHAR(15)     = NULL,
    @DefaultAmount            DECIMAL(12,3)   = NULL,
    @DefaultPercentage        DECIMAL(7,4)    = NULL,
    @Formula                  NVARCHAR(1000)  = NULL,
    @MinAmount                DECIMAL(12,3)   = NULL,
    @MaxAmount                DECIMAL(12,3)   = NULL,
    @IsTaxable                BIT             = NULL,
    @IsPifssApplicable        BIT             = NULL,
    @IsIndemnityApplicable    BIT             = NULL,
    @IsOvertimeApplicable     BIT             = NULL,
    @IsLeaveSalaryApplicable  BIT             = NULL,
    @IsRecurring              BIT             = NULL,
    @IsProrated               BIT             = NULL,
    @ShowOnPayslip            BIT             = NULL,
    @GLAccountCode            NVARCHAR(50)    = NULL,
    @GLAccountName            NVARCHAR(150)   = NULL,
    @CostCenterId             INT             = NULL,
    @DisplayOrder             SMALLINT        = NULL,
    @Description              NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE', 'SEED')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    SET @ComponentTypeFilter = NULLIF(UPPER(LTRIM(RTRIM(@ComponentTypeFilter))), '');

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[PayComponents] AS pc
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ComponentTypeFilter IS NULL OR pc.ComponentType = @ComponentTypeFilter)
          AND (@Pattern IS NULL OR pc.ComponentCode LIKE @Pattern ESCAPE '\' OR pc.ComponentName LIKE @Pattern ESCAPE '\'
               OR pc.ArabicName LIKE @Pattern ESCAPE '\' OR pc.GLAccountCode LIKE @Pattern ESCAPE '\');

        SELECT  pc.PayComponentId, pc.CompanyId, pc.ComponentCode, pc.ComponentName, pc.ArabicName, pc.PayslipLabel,
                pc.ComponentType, pc.ValueType, pc.CalculationMethod, pc.CalculationBase,
                pc.DefaultAmount, pc.DefaultPercentage, pc.Formula, pc.MinAmount, pc.MaxAmount,
                pc.IsTaxable, pc.IsPifssApplicable, pc.IsIndemnityApplicable, pc.IsOvertimeApplicable,
                pc.IsLeaveSalaryApplicable, pc.IsRecurring, pc.IsProrated, pc.ShowOnPayslip,
                pc.GLAccountCode, pc.GLAccountName, pc.CostCenterId, pc.DisplayOrder, pc.SystemCode, pc.IsSystem,
                pc.Description, pc.IsActive,
                c.CompanyName, cc.CostCenterName,
                (SELECT COUNT(1) FROM [Payroll].[SalaryStructureComponents] l
                  WHERE l.Deleted = 0 AND l.PayComponentId = pc.PayComponentId) AS StructureCount
        FROM        [Payroll].[PayComponents] AS pc
        INNER JOIN  [Core].[Companies]        AS c  ON c.CompanyId     = pc.CompanyId
        LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = pc.CostCenterId
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ComponentTypeFilter IS NULL OR pc.ComponentType = @ComponentTypeFilter)
          AND (@Pattern IS NULL OR pc.ComponentCode LIKE @Pattern ESCAPE '\' OR pc.ComponentName LIKE @Pattern ESCAPE '\'
               OR pc.ArabicName LIKE @Pattern ESCAPE '\' OR pc.GLAccountCode LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentCode'     THEN pc.ComponentCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentCode'     THEN pc.ComponentCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentName'     THEN pc.ComponentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentName'     THEN pc.ComponentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentType'     THEN pc.ComponentType END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentType'     THEN pc.ComponentType END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CalculationMethod' THEN pc.CalculationMethod END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CalculationMethod' THEN pc.CalculationMethod END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'          THEN pc.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'          THEN pc.IsActive END DESC,
                CASE WHEN @SortDirection = 'DESC' AND ISNULL(@SortColumn, 'DisplayOrder') = 'DisplayOrder' THEN pc.DisplayOrder END DESC,
                pc.DisplayOrder ASC, pc.ComponentName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  pc.PayComponentId, pc.CompanyId, pc.ComponentCode, pc.ComponentName, pc.ArabicName, pc.PayslipLabel,
                pc.ComponentType, pc.ValueType, pc.CalculationMethod, pc.CalculationBase,
                pc.DefaultAmount, pc.DefaultPercentage, pc.Formula, pc.MinAmount, pc.MaxAmount,
                pc.IsTaxable, pc.IsPifssApplicable, pc.IsIndemnityApplicable, pc.IsOvertimeApplicable,
                pc.IsLeaveSalaryApplicable, pc.IsRecurring, pc.IsProrated, pc.ShowOnPayslip,
                pc.GLAccountCode, pc.GLAccountName, pc.CostCenterId, pc.DisplayOrder, pc.SystemCode, pc.IsSystem,
                pc.Description, pc.IsActive,
                c.CompanyName, cc.CostCenterName,
                (SELECT COUNT(1) FROM [Payroll].[SalaryStructureComponents] l
                  WHERE l.Deleted = 0 AND l.PayComponentId = pc.PayComponentId) AS StructureCount
        FROM        [Payroll].[PayComponents] AS pc
        INNER JOIN  [Core].[Companies]        AS c  ON c.CompanyId     = pc.CompanyId
        LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = pc.CostCenterId
        WHERE pc.PayComponentId = @Id AND pc.Deleted = 0;
        RETURN;
    END;

    /* ======================= SEED ================================ */
    IF @Action = 'SEED'
    BEGIN
        IF @CompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select a company first.';
            RETURN;
        END;
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @CompanyId, @UserId = @UserId, @Inserted = @TotalCount OUTPUT;
        SET @ResultMessage = CASE WHEN @TotalCount = 0 THEN N'This company already has all the standard components.'
                                  ELSE CONCAT(@TotalCount, N' standard component(s) added.') END;
        RETURN;
    END;

    /* ======================= shared validation =================== */
    DECLARE @CurSystemCode VARCHAR(30), @CurType VARCHAR(10), @CurCode NVARCHAR(30), @CurCompanyId INT, @CurMethod VARCHAR(12), @Exists BIT = 0;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @Exists = 1, @CurSystemCode = SystemCode, @CurType = ComponentType, @CurCode = ComponentCode,
               @CurCompanyId = CompanyId, @CurMethod = CalculationMethod
        FROM [Payroll].[PayComponents] WHERE PayComponentId = @Id AND Deleted = 0;

        IF @Exists = 0
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        /* System components keep their identity: code, type, company and (for SYSTEM-calculated ones) method. */
        IF @CurSystemCode IS NOT NULL
            SELECT @ComponentCode = @CurCode, @ComponentType = @CurType, @CompanyId = @CurCompanyId,
                   @CalculationMethod = CASE WHEN @CurMethod = 'SYSTEM' THEN 'SYSTEM' ELSE @CalculationMethod END;

        SELECT @ComponentType     = UPPER(LTRIM(RTRIM(@ComponentType))),
               @ValueType         = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@ValueType)), ''), 'FIXED')),
               @CalculationMethod = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@CalculationMethod)), ''), 'AMOUNT')),
               @CalculationBase   = NULLIF(UPPER(LTRIM(RTRIM(@CalculationBase))), '');

        IF @CompanyId IS NULL OR NULLIF(LTRIM(RTRIM(@ComponentCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@ComponentName)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Company, code and name are required.';
            RETURN;
        END;
        IF @ComponentType NOT IN ('EARNING', 'DEDUCTION')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose whether this is an Earning or a Deduction.';
            RETURN;
        END;
        IF @ValueType NOT IN ('FIXED', 'VARIABLE')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose Fixed or Variable.';
            RETURN;
        END;
        IF @CalculationMethod NOT IN ('AMOUNT', 'PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA', 'SYSTEM')
           OR (@CalculationMethod = 'SYSTEM' AND @CurSystemCode IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose a calculation method: Amount, Percentage, Days, Hours or Formula.';
            RETURN;
        END;
        IF @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS')
           AND ISNULL(@CalculationBase, '') NOT IN ('BASIC', 'FIXED_GROSS', 'OVERTIME_BASE', 'INDEMNITY_BASE')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Percentage, Days and Hours methods need a calculation base (Basic, Fixed gross, Overtime base or Indemnity base).';
            RETURN;
        END;
        IF @CalculationMethod = 'PERCENTAGE' AND @DefaultPercentage IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the default percentage.';
            RETURN;
        END;
        IF @CalculationMethod = 'FORMULA' AND NULLIF(LTRIM(RTRIM(@Formula)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the formula.';
            RETURN;
        END;
        IF @ComponentType = 'DEDUCTION'
           AND (ISNULL(@IsPifssApplicable, 0) = 1 OR ISNULL(@IsIndemnityApplicable, 0) = 1
                OR ISNULL(@IsOvertimeApplicable, 0) = 1 OR ISNULL(@IsLeaveSalaryApplicable, 0) = 1)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Social security, end-of-service, overtime and leave-salary flags apply to earnings only.';
            RETURN;
        END;
        IF @MinAmount IS NOT NULL AND @MaxAmount IS NOT NULL AND @MaxAmount < @MinAmount
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Maximum amount cannot be less than the minimum amount.';
            RETURN;
        END;
        IF @CostCenterId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @CostCenterId AND CompanyId = @CompanyId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The selected cost center does not belong to this company.';
            RETURN;
        END;
        IF @CurSystemCode = 'BASIC' AND ISNULL(@IsActive, 1) = 0
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT', @ResultMessage = N'Basic Salary is required by the payroll engine and cannot be deactivated.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[PayComponents]
                   WHERE Deleted = 0 AND CompanyId = @CompanyId AND ComponentCode = @ComponentCode
                     AND (@Action = 'INSERT' OR PayComponentId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[PayComponents]
            (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod, CalculationBase,
             DefaultAmount, DefaultPercentage, Formula, MinAmount, MaxAmount,
             IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable,
             IsRecurring, IsProrated, ShowOnPayslip, GLAccountCode, GLAccountName, CostCenterId, DisplayOrder,
             SystemCode, IsSystem, Description, IsActive, CreatedBy)
        VALUES
            (@CompanyId, @ComponentCode, @ComponentName, @ArabicName, @PayslipLabel, @ComponentType, @ValueType, @CalculationMethod,
             CASE WHEN @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA') THEN @CalculationBase END,
             @DefaultAmount, CASE WHEN @CalculationMethod = 'PERCENTAGE' THEN @DefaultPercentage END,
             CASE WHEN @CalculationMethod = 'FORMULA' THEN @Formula END, @MinAmount, @MaxAmount,
             ISNULL(@IsTaxable, 0), ISNULL(@IsPifssApplicable, 0), ISNULL(@IsIndemnityApplicable, 0), ISNULL(@IsOvertimeApplicable, 0),
             ISNULL(@IsLeaveSalaryApplicable, 0), ISNULL(@IsRecurring, 1), ISNULL(@IsProrated, 1), ISNULL(@ShowOnPayslip, 1),
             @GLAccountCode, @GLAccountName, @CostCenterId, ISNULL(@DisplayOrder, 100),
             NULL, 0, @Description, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = CASE WHEN @ComponentType = 'EARNING' THEN N'Earning component created successfully.'
                                  ELSE N'Deduction component created successfully.' END;
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        /* Changing the type of a component already used in a structure would flip the sign of those lines. */
        IF @ComponentType <> @CurType
           AND EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] WHERE Deleted = 0 AND PayComponentId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This component is used in a salary structure, so it cannot be switched between Earning and Deduction.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET CompanyId               = @CompanyId,
               ComponentCode           = @ComponentCode,
               ComponentName           = @ComponentName,
               ArabicName              = @ArabicName,
               PayslipLabel            = @PayslipLabel,
               ComponentType           = @ComponentType,
               ValueType               = @ValueType,
               CalculationMethod       = @CalculationMethod,
               CalculationBase         = CASE WHEN @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA') THEN @CalculationBase END,
               DefaultAmount           = @DefaultAmount,
               DefaultPercentage       = CASE WHEN @CalculationMethod = 'PERCENTAGE' THEN @DefaultPercentage END,
               Formula                 = CASE WHEN @CalculationMethod = 'FORMULA' THEN @Formula END,
               MinAmount               = @MinAmount,
               MaxAmount               = @MaxAmount,
               IsTaxable               = ISNULL(@IsTaxable, 0),
               IsPifssApplicable       = ISNULL(@IsPifssApplicable, 0),
               IsIndemnityApplicable   = ISNULL(@IsIndemnityApplicable, 0),
               IsOvertimeApplicable    = ISNULL(@IsOvertimeApplicable, 0),
               IsLeaveSalaryApplicable = ISNULL(@IsLeaveSalaryApplicable, 0),
               IsRecurring             = ISNULL(@IsRecurring, 1),
               IsProrated              = ISNULL(@IsProrated, 1),
               ShowOnPayslip           = ISNULL(@ShowOnPayslip, 1),
               GLAccountCode           = @GLAccountCode,
               GLAccountName           = @GLAccountName,
               CostCenterId            = @CostCenterId,
               DisplayOrder            = ISNULL(@DisplayOrder, DisplayOrder),
               Description             = @Description,
               IsActive                = ISNULL(@IsActive, IsActive),
               ModifiedBy              = @UserId,
               ModifiedDate            = SYSUTCDATETIME()
         WHERE PayComponentId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Component updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF @CurSystemCode IS NOT NULL
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT',
                   @ResultMessage = CASE WHEN @CurSystemCode = 'BASIC' THEN N'Basic Salary is required by the payroll engine and cannot be deleted.'
                                         ELSE N'This is a standard component the payroll engine relies on. Deactivate it instead of deleting it.' END;
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] WHERE Deleted = 0 AND PayComponentId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This component is used in a salary structure and cannot be deleted. Remove it from the structure or deactivate it instead.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE PayComponentId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Component deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF @CurSystemCode = 'BASIC'
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT', @ResultMessage = N'Basic Salary is required by the payroll engine and cannot be deactivated.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PayComponentId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Component activated.' ELSE N'Component deactivated.' END
        FROM [Payroll].[PayComponents] WHERE PayComponentId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_SalaryStructure_Manage
   ---------------------------------------------------------------------
   INSERT / UPDATE   header + lines in one call. @LinesJson is an array:
       [ { "PayComponentId": 1, "CalculationMethod": null, "CalculationBase": null, "Amount": 450.000,
           "Percentage": null, "MinAmount": null, "MaxAmount": null,
           "IsMandatory": true, "AllowOverride": true, "DisplayOrder": 10 }, ... ]
     - lines are matched on PayComponentId: existing ones are updated,
       new ones inserted, missing ones soft-deleted.
     - @LinesJson = NULL on UPDATE leaves the lines untouched.
     - the structure must contain the company's BASIC component.
   LINES     lines of structure @Id (with component details)
   RESOLVE   best structure for a new hire:
               @CompanyId, @DesignationId, @PositionId, @GradeId, @AsOfDate
             Returns header row then line rows (2 result sets).
             Most specific match wins: Job Position (4) > Designation (2)
             > Grade (1); ties -> latest EffectiveFrom.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_SalaryStructure_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    /* ---- editable columns -------------------------------------- */
    @StructureCode            NVARCHAR(30)    = NULL,
    @StructureName            NVARCHAR(150)   = NULL,
    @ArabicName               NVARCHAR(150)   = NULL,
    @DesignationId            INT             = NULL,
    @PositionId               INT             = NULL,
    @GradeId                  INT             = NULL,
    @PayrollCalendarId        INT             = NULL,
    @EffectiveFrom            DATE            = NULL,
    @EffectiveTo              DATE            = NULL,
    @Description              NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,
    @LinesJson                NVARCHAR(MAX)   = NULL,
    @AsOfDate                 DATE            = NULL,   -- RESOLVE

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'LINES', 'RESOLVE', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Payroll].[SalaryStructures] AS s
        LEFT JOIN   [Core].[Designations]        AS dg ON dg.DesignationId = s.DesignationId
        LEFT JOIN   [Core].[Positions]           AS jp ON jp.PositionId    = s.PositionId
        WHERE  s.Deleted = 0
          AND (@IsActiveFilter IS NULL OR s.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR s.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(s.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR s.StructureCode LIKE @Pattern ESCAPE '\' OR s.StructureName LIKE @Pattern ESCAPE '\'
               OR dg.DesignationName LIKE @Pattern ESCAPE '\' OR jp.PositionName LIKE @Pattern ESCAPE '\');

        SELECT  s.SalaryStructureId, s.CompanyId, s.StructureCode, s.StructureName, s.ArabicName,
                s.DesignationId, s.PositionId, s.GradeId, s.PayrollCalendarId, s.EffectiveFrom, s.EffectiveTo,
                s.Description, s.IsActive,
                c.CompanyName, dg.DesignationName, jp.PositionName, g.GradeName, pc.CalendarName,
                ISNULL(t.LineCount, 0)     AS LineCount,
                ISNULL(t.FixedEarnings, 0) AS FixedEarningsTotal
        FROM        [Payroll].[SalaryStructures] AS s
        INNER JOIN  [Core].[Companies]           AS c  ON c.CompanyId      = s.CompanyId
        LEFT JOIN   [Core].[Designations]        AS dg ON dg.DesignationId = s.DesignationId
        LEFT JOIN   [Core].[Positions]           AS jp ON jp.PositionId    = s.PositionId
        LEFT JOIN   [Core].[Grades]              AS g  ON g.GradeId        = s.GradeId
        LEFT JOIN   [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = s.PayrollCalendarId
        OUTER APPLY (SELECT COUNT(1) AS LineCount,
                            SUM(CASE WHEN comp.ComponentType = 'EARNING'
                                      AND ISNULL(l.CalculationMethod, comp.CalculationMethod) = 'AMOUNT'
                                     THEN ISNULL(l.Amount, comp.DefaultAmount) END) AS FixedEarnings
                     FROM [Payroll].[SalaryStructureComponents] l
                     INNER JOIN [Payroll].[PayComponents] comp ON comp.PayComponentId = l.PayComponentId
                     WHERE l.Deleted = 0 AND l.SalaryStructureId = s.SalaryStructureId) AS t
        WHERE  s.Deleted = 0
          AND (@IsActiveFilter IS NULL OR s.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR s.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(s.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR s.StructureCode LIKE @Pattern ESCAPE '\' OR s.StructureName LIKE @Pattern ESCAPE '\'
               OR dg.DesignationName LIKE @Pattern ESCAPE '\' OR jp.PositionName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'StructureCode'   THEN s.StructureCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'StructureCode'   THEN s.StructureCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'StructureName'   THEN s.StructureName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'StructureName'   THEN s.StructureName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DesignationName' THEN dg.DesignationName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DesignationName' THEN dg.DesignationName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'PositionName'    THEN jp.PositionName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'PositionName'    THEN jp.PositionName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EffectiveFrom'   THEN s.EffectiveFrom END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EffectiveFrom'   THEN s.EffectiveFrom END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'        THEN s.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'        THEN s.IsActive END DESC,
                s.StructureName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= RESOLVE ============================= */
    IF @Action = 'RESOLVE'
    BEGIN
        SET @AsOfDate = ISNULL(@AsOfDate, CAST(SYSUTCDATETIME() AS DATE));
        SET @Id = NULL;

        SELECT TOP (1) @Id = s.SalaryStructureId
        FROM   [Payroll].[SalaryStructures] AS s
        WHERE  s.Deleted = 0 AND s.IsActive = 1 AND s.CompanyId = @CompanyId
          AND  s.EffectiveFrom <= @AsOfDate AND (s.EffectiveTo IS NULL OR s.EffectiveTo >= @AsOfDate)
          AND (s.PositionId    IS NULL OR s.PositionId    = @PositionId)
          AND (s.DesignationId IS NULL OR s.DesignationId = @DesignationId)
          AND (s.GradeId       IS NULL OR s.GradeId       = @GradeId)
        ORDER BY (CASE WHEN s.PositionId    IS NOT NULL THEN 4 ELSE 0 END
                + CASE WHEN s.DesignationId IS NOT NULL THEN 2 ELSE 0 END
                + CASE WHEN s.GradeId       IS NOT NULL THEN 1 ELSE 0 END) DESC,
                 s.EffectiveFrom DESC, s.SalaryStructureId DESC;

        IF @Id IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'No salary structure matches this designation / job position / grade.', @NewId = 0;
            /* still return the two empty result sets so the caller's reader shape is stable */
        END
        ELSE
            SET @NewId = @Id;
        /* fall through to GET + LINES below */
    END;

    /* ======================= GET ================================= */
    IF @Action IN ('GET', 'RESOLVE')
    BEGIN
        SELECT  s.SalaryStructureId, s.CompanyId, s.StructureCode, s.StructureName, s.ArabicName,
                s.DesignationId, s.PositionId, s.GradeId, s.PayrollCalendarId, s.EffectiveFrom, s.EffectiveTo,
                s.Description, s.IsActive,
                c.CompanyName, dg.DesignationName, jp.PositionName, g.GradeName, pc.CalendarName
        FROM        [Payroll].[SalaryStructures] AS s
        INNER JOIN  [Core].[Companies]           AS c  ON c.CompanyId      = s.CompanyId
        LEFT JOIN   [Core].[Designations]        AS dg ON dg.DesignationId = s.DesignationId
        LEFT JOIN   [Core].[Positions]           AS jp ON jp.PositionId    = s.PositionId
        LEFT JOIN   [Core].[Grades]              AS g  ON g.GradeId        = s.GradeId
        LEFT JOIN   [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = s.PayrollCalendarId
        WHERE s.SalaryStructureId = @Id AND s.Deleted = 0;

        IF @Action = 'GET' RETURN;
    END;

    /* ======================= LINES =============================== */
    IF @Action IN ('LINES', 'RESOLVE')
    BEGIN
        SELECT  l.SalaryStructureComponentId, l.SalaryStructureId, l.PayComponentId,
                l.CalculationMethod, l.CalculationBase, l.Amount, l.Percentage, l.MinAmount, l.MaxAmount,
                l.IsMandatory, l.AllowOverride, l.DisplayOrder,
                comp.ComponentCode, comp.ComponentName, comp.ArabicName, comp.ComponentType, comp.ValueType,
                comp.CalculationBase, comp.SystemCode, comp.IsActive AS ComponentIsActive,
                ISNULL(l.CalculationMethod, comp.CalculationMethod) AS EffectiveMethod,
                ISNULL(l.CalculationBase,   comp.CalculationBase)   AS EffectiveBase,
                ISNULL(l.Amount,     comp.DefaultAmount)            AS EffectiveAmount,
                ISNULL(l.Percentage, comp.DefaultPercentage)        AS EffectivePercentage
        FROM        [Payroll].[SalaryStructureComponents] AS l
        INNER JOIN  [Payroll].[PayComponents]             AS comp ON comp.PayComponentId = l.PayComponentId
        WHERE l.SalaryStructureId = @Id AND l.Deleted = 0
        ORDER BY comp.ComponentType DESC, l.DisplayOrder, comp.DisplayOrder, comp.ComponentName;   -- EARNING before DEDUCTION
        RETURN;
    END;

    /* ======================= shared validation =================== */
    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[SalaryStructures] WHERE SalaryStructureId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    DECLARE @Lines TABLE (
        PayComponentId INT NOT NULL, CalculationMethod VARCHAR(12) NULL, CalculationBase VARCHAR(15) NULL, Amount DECIMAL(12,3) NULL, Percentage DECIMAL(7,4) NULL,
        MinAmount DECIMAL(12,3) NULL, MaxAmount DECIMAL(12,3) NULL, IsMandatory BIT NULL, AllowOverride BIT NULL, DisplayOrder SMALLINT NULL);
    DECLARE @HasLines BIT = 0;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        IF @CompanyId IS NULL OR NULLIF(LTRIM(RTRIM(@StructureCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@StructureName)), N'') IS NULL
           OR @EffectiveFrom IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Company, code, name and effective-from date are required.';
            RETURN;
        END;
        IF @EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Effective-to date cannot be before the effective-from date.';
            RETURN;
        END;
        IF (@DesignationId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Core].[Designations] WHERE DesignationId = @DesignationId AND CompanyId = @CompanyId AND Deleted = 0))
           OR (@PositionId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Core].[Positions] WHERE PositionId = @PositionId AND CompanyId = @CompanyId AND Deleted = 0))
           OR (@GradeId    IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Core].[Grades] WHERE GradeId = @GradeId AND CompanyId = @CompanyId AND Deleted = 0))
           OR (@PayrollCalendarId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @PayrollCalendarId AND CompanyId = @CompanyId AND Deleted = 0))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Designation, job position, grade and payroll calendar must all belong to the selected company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[SalaryStructures]
                   WHERE Deleted = 0 AND CompanyId = @CompanyId AND StructureCode = @StructureCode
                     AND (@Action = 'INSERT' OR SalaryStructureId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
        /* Two active structures for exactly the same Designation / Position / Grade must not overlap in time,
           otherwise RESOLVE could not tell which one a new hire should get. */
        IF ISNULL(@IsActive, 1) = 1
           AND EXISTS (SELECT 1 FROM [Payroll].[SalaryStructures]
                       WHERE Deleted = 0 AND IsActive = 1 AND CompanyId = @CompanyId
                         AND (@Action = 'INSERT' OR SalaryStructureId <> @Id)
                         AND ISNULL(DesignationId, -1) = ISNULL(@DesignationId, -1)
                         AND ISNULL(PositionId,    -1) = ISNULL(@PositionId,    -1)
                         AND ISNULL(GradeId,       -1) = ISNULL(@GradeId,       -1)
                         AND EffectiveFrom <= ISNULL(@EffectiveTo, '9999-12-31')
                         AND ISNULL(EffectiveTo, '9999-12-31') >= @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active structure already covers this designation / job position / grade for overlapping dates. End-date it first.';
            RETURN;
        END;

        IF @LinesJson IS NOT NULL
        BEGIN
            IF ISJSON(@LinesJson) = 0
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The structure lines could not be read.';
                RETURN;
            END;

            INSERT INTO @Lines (PayComponentId, CalculationMethod, CalculationBase, Amount, Percentage, MinAmount, MaxAmount, IsMandatory, AllowOverride, DisplayOrder)
            SELECT j.PayComponentId, NULLIF(UPPER(LTRIM(RTRIM(j.CalculationMethod))), ''), NULLIF(UPPER(LTRIM(RTRIM(j.CalculationBase))), ''),
                   j.Amount, j.Percentage, j.MinAmount, j.MaxAmount,
                   j.IsMandatory, j.AllowOverride, j.DisplayOrder
            FROM OPENJSON(@LinesJson)
                 WITH (PayComponentId INT '$.PayComponentId', CalculationMethod VARCHAR(12) '$.CalculationMethod',
                       CalculationBase VARCHAR(15) '$.CalculationBase',
                       Amount DECIMAL(12,3) '$.Amount', Percentage DECIMAL(7,4) '$.Percentage',
                       MinAmount DECIMAL(12,3) '$.MinAmount', MaxAmount DECIMAL(12,3) '$.MaxAmount',
                       IsMandatory BIT '$.IsMandatory', AllowOverride BIT '$.AllowOverride', DisplayOrder SMALLINT '$.DisplayOrder') AS j
            WHERE j.PayComponentId IS NOT NULL;

            SET @HasLines = 1;

            IF EXISTS (SELECT PayComponentId FROM @Lines GROUP BY PayComponentId HAVING COUNT(1) > 1)
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A component can appear only once in a structure.';
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM @Lines l
                       WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] c
                                         WHERE c.PayComponentId = l.PayComponentId AND c.CompanyId = @CompanyId AND c.Deleted = 0))
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Every component must belong to the selected company.';
                RETURN;
            END;
            /* Inactive components may stay on an existing line but cannot be newly added. */
            IF EXISTS (SELECT 1 FROM @Lines l
                       INNER JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                       WHERE c.IsActive = 0
                         AND NOT EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] x
                                         WHERE x.Deleted = 0 AND x.SalaryStructureId = @Id AND x.PayComponentId = l.PayComponentId))
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'An inactive component cannot be added to a structure.';
                RETURN;
            END;
            IF NOT EXISTS (SELECT 1 FROM @Lines l
                           INNER JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                           WHERE c.SystemCode = 'BASIC')
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A salary structure must include Basic Salary.';
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM @Lines WHERE CalculationMethod IS NOT NULL AND CalculationMethod NOT IN ('AMOUNT', 'PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA'))
               OR EXISTS (SELECT 1 FROM @Lines WHERE CalculationBase IS NOT NULL AND CalculationBase NOT IN ('BASIC', 'FIXED_GROSS', 'OVERTIME_BASE', 'INDEMNITY_BASE'))
               OR EXISTS (SELECT 1 FROM @Lines WHERE (Amount < 0) OR (MinAmount < 0) OR (MaxAmount < 0) OR (MaxAmount < MinAmount)
                                                  OR (Percentage NOT BETWEEN 0 AND 1000))
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'One of the lines has an invalid method, amount or percentage.';
                RETURN;
            END;
            /* What the engine will actually use = line override, else component default. */
            DECLARE @BadLine NVARCHAR(150) =
                (SELECT TOP 1 c.ComponentName
                 FROM @Lines l INNER JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                 CROSS APPLY (SELECT ISNULL(l.CalculationMethod, c.CalculationMethod) AS M,
                                     ISNULL(l.CalculationBase,   c.CalculationBase)   AS B,
                                     ISNULL(l.Percentage,        c.DefaultPercentage) AS P) AS e
                 WHERE (e.M IN ('PERCENTAGE', 'DAYS', 'HOURS') AND e.B IS NULL)
                    OR (e.M = 'PERCENTAGE' AND e.P IS NULL)
                    OR (e.M = 'FORMULA' AND c.Formula IS NULL)
                    OR (l.CalculationMethod IS NOT NULL AND c.CalculationMethod = 'SYSTEM' AND l.CalculationMethod <> 'SYSTEM'));
            IF @BadLine IS NOT NULL
            BEGIN
                SELECT @ResultCode = 'VALIDATION',
                       @ResultMessage = CONCAT(N'"', @BadLine, N'": a Percentage line needs a percentage and a base, Days / Hours need a base, Formula needs a formula on the component, and system-calculated components cannot be overridden.');
                RETURN;
            END;
        END
        ELSE IF @Action = 'INSERT'
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Add at least the Basic Salary line to the structure.';
            RETURN;
        END;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            INSERT INTO [Payroll].[SalaryStructures]
                (CompanyId, StructureCode, StructureName, ArabicName, DesignationId, PositionId, GradeId, PayrollCalendarId,
                 EffectiveFrom, EffectiveTo, Description, IsActive, CreatedBy)
            VALUES
                (@CompanyId, @StructureCode, @StructureName, @ArabicName, @DesignationId, @PositionId, @GradeId, @PayrollCalendarId,
                 @EffectiveFrom, @EffectiveTo, @Description, ISNULL(@IsActive, 1), @UserId);

            SET @NewId = SCOPE_IDENTITY();

            INSERT INTO [Payroll].[SalaryStructureComponents]
                (SalaryStructureId, PayComponentId, CalculationMethod, CalculationBase, Amount, Percentage, MinAmount, MaxAmount,
                 IsMandatory, AllowOverride, DisplayOrder, CreatedBy)
            SELECT @NewId, l.PayComponentId, l.CalculationMethod, l.CalculationBase, l.Amount, l.Percentage, l.MinAmount, l.MaxAmount,
                   ISNULL(l.IsMandatory, 1), ISNULL(l.AllowOverride, 1), ISNULL(l.DisplayOrder, c.DisplayOrder), @UserId
            FROM @Lines l INNER JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId;
        COMMIT;

        SET @ResultMessage = N'Salary structure created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[SalaryStructures]
               SET CompanyId         = @CompanyId,
                   StructureCode     = @StructureCode,
                   StructureName     = @StructureName,
                   ArabicName        = @ArabicName,
                   DesignationId     = @DesignationId,
                   PositionId        = @PositionId,
                   GradeId           = @GradeId,
                   PayrollCalendarId = @PayrollCalendarId,
                   EffectiveFrom     = @EffectiveFrom,
                   EffectiveTo       = @EffectiveTo,
                   Description       = @Description,
                   IsActive          = ISNULL(@IsActive, IsActive),
                   ModifiedBy        = @UserId,
                   ModifiedDate      = SYSUTCDATETIME()
             WHERE SalaryStructureId = @Id;

            IF @HasLines = 1
            BEGIN
                /* removed lines -> soft delete */
                UPDATE x
                   SET x.Deleted = 1, x.DeletedBy = @UserId, x.DeletedDate = SYSUTCDATETIME()
                FROM [Payroll].[SalaryStructureComponents] AS x
                WHERE x.SalaryStructureId = @Id AND x.Deleted = 0
                  AND NOT EXISTS (SELECT 1 FROM @Lines l WHERE l.PayComponentId = x.PayComponentId);

                /* kept lines -> update */
                UPDATE x
                   SET x.CalculationMethod = l.CalculationMethod,
                       x.CalculationBase   = l.CalculationBase,
                       x.Amount            = l.Amount,
                       x.Percentage        = l.Percentage,
                       x.MinAmount         = l.MinAmount,
                       x.MaxAmount         = l.MaxAmount,
                       x.IsMandatory       = ISNULL(l.IsMandatory, 1),
                       x.AllowOverride     = ISNULL(l.AllowOverride, 1),
                       x.DisplayOrder      = ISNULL(l.DisplayOrder, x.DisplayOrder),
                       x.ModifiedBy        = @UserId,
                       x.ModifiedDate      = SYSUTCDATETIME()
                FROM [Payroll].[SalaryStructureComponents] AS x
                INNER JOIN @Lines AS l ON l.PayComponentId = x.PayComponentId
                WHERE x.SalaryStructureId = @Id AND x.Deleted = 0;

                /* new lines -> insert */
                INSERT INTO [Payroll].[SalaryStructureComponents]
                    (SalaryStructureId, PayComponentId, CalculationMethod, CalculationBase, Amount, Percentage, MinAmount, MaxAmount,
                     IsMandatory, AllowOverride, DisplayOrder, CreatedBy)
                SELECT @Id, l.PayComponentId, l.CalculationMethod, l.CalculationBase, l.Amount, l.Percentage, l.MinAmount, l.MaxAmount,
                       ISNULL(l.IsMandatory, 1), ISNULL(l.AllowOverride, 1), ISNULL(l.DisplayOrder, c.DisplayOrder), @UserId
                FROM @Lines l INNER JOIN [Payroll].[PayComponents] c ON c.PayComponentId = l.PayComponentId
                WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] x
                                  WHERE x.SalaryStructureId = @Id AND x.Deleted = 0 AND x.PayComponentId = l.PayComponentId);
            END;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Salary structure updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        /* Phase 1: nothing references a structure yet except its own lines.
           When the Employee Salary tab arrives it will add an IN_USE check here. */
        BEGIN TRAN;
            UPDATE [Payroll].[SalaryStructureComponents]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE SalaryStructureId = @Id AND Deleted = 0;

            UPDATE [Payroll].[SalaryStructures]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE SalaryStructureId = @Id AND Deleted = 0;
        COMMIT;

        SET @ResultMessage = N'Salary structure deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        /* Re-activating must not create an overlap with another active structure. */
        IF EXISTS (SELECT 1
                   FROM [Payroll].[SalaryStructures] AS me
                   INNER JOIN [Payroll].[SalaryStructures] AS o
                           ON o.CompanyId = me.CompanyId AND o.SalaryStructureId <> me.SalaryStructureId
                          AND o.Deleted = 0 AND o.IsActive = 1
                          AND ISNULL(o.DesignationId, -1) = ISNULL(me.DesignationId, -1)
                          AND ISNULL(o.PositionId,    -1) = ISNULL(me.PositionId,    -1)
                          AND ISNULL(o.GradeId,       -1) = ISNULL(me.GradeId,       -1)
                          AND o.EffectiveFrom <= ISNULL(me.EffectiveTo, '9999-12-31')
                          AND ISNULL(o.EffectiveTo, '9999-12-31') >= me.EffectiveFrom
                   WHERE me.SalaryStructureId = @Id AND me.IsActive = 0)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active structure covers the same designation / job position / grade for overlapping dates.';
            RETURN;
        END;

        UPDATE [Payroll].[SalaryStructures]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE SalaryStructureId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Salary structure activated.' ELSE N'Salary structure deactivated.' END
        FROM [Payroll].[SalaryStructures] WHERE SalaryStructureId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_PifssRate_Manage  -  effective-dated social security rates
   ---------------------------------------------------------------------
   Rates are country-level (not per company). Optional LIST filter
   @AsOfDate returns only the rows in force on that date.
   Two ACTIVE rows with the same ContributionCode + ApplicableTo cannot
   overlap in time: to change a rate, end-date the current row and add
   a new one (history is kept, nothing is overwritten).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PifssRate_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- not used (country-level)
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- not used
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',
    @AsOfDate                 DATE            = NULL,

    @ContributionCode         NVARCHAR(30)    = NULL,
    @ContributionName         NVARCHAR(150)   = NULL,
    @ApplicableTo             VARCHAR(10)     = NULL,
    @CalculationBasis         VARCHAR(10)     = NULL,
    @EmployeeRate             DECIMAL(7,4)    = NULL,
    @EmployerRate             DECIMAL(7,4)    = NULL,
    @GovernmentRate           DECIMAL(7,4)    = NULL,
    @SalaryFloor              DECIMAL(12,3)   = NULL,
    @SalaryCeiling            DECIMAL(12,3)   = NULL,
    @EffectiveFrom            DATE            = NULL,
    @EffectiveTo              DATE            = NULL,
    @IsVerified               BIT             = NULL,
    @Notes                    NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[PifssContributionRates] AS r
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (@AsOfDate IS NULL OR (r.EffectiveFrom <= @AsOfDate AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @AsOfDate)))
          AND (@Pattern IS NULL OR r.ContributionCode LIKE @Pattern ESCAPE '\' OR r.ContributionName LIKE @Pattern ESCAPE '\');

        SELECT  r.PifssRateId, r.ContributionCode, r.ContributionName, r.ApplicableTo, r.CalculationBasis,
                r.EmployeeRate, r.EmployerRate, r.GovernmentRate, r.SalaryFloor, r.SalaryCeiling,
                r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive,
                CAST(CASE WHEN r.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
                           AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE)) THEN 1 ELSE 0 END AS BIT) AS IsCurrent
        FROM   [Payroll].[PifssContributionRates] AS r
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (@AsOfDate IS NULL OR (r.EffectiveFrom <= @AsOfDate AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @AsOfDate)))
          AND (@Pattern IS NULL OR r.ContributionCode LIKE @Pattern ESCAPE '\' OR r.ContributionName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ContributionName' THEN r.ContributionName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ContributionName' THEN r.ContributionName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EffectiveFrom'    THEN r.EffectiveFrom END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EffectiveFrom'    THEN r.EffectiveFrom END DESC,
                r.ApplicableTo, r.ContributionCode, r.EffectiveFrom DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  r.PifssRateId, r.ContributionCode, r.ContributionName, r.ApplicableTo, r.CalculationBasis,
                r.EmployeeRate, r.EmployerRate, r.GovernmentRate, r.SalaryFloor, r.SalaryCeiling,
                r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive
        FROM   [Payroll].[PifssContributionRates] AS r
        WHERE  r.PifssRateId = @Id AND r.Deleted = 0;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates] WHERE PifssRateId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @ApplicableTo     = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@ApplicableTo)), ''), 'KUWAITI')),
               @CalculationBasis = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@CalculationBasis)), ''), 'CAPPED'));

        IF NULLIF(LTRIM(RTRIM(@ContributionCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@ContributionName)), N'') IS NULL
           OR @EffectiveFrom IS NULL OR @EmployeeRate IS NULL OR @EmployerRate IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Code, name, employee rate, employer rate and effective-from date are required.';
            RETURN;
        END;
        IF @ApplicableTo NOT IN ('KUWAITI', 'GCC', 'EXPAT', 'ALL') OR @CalculationBasis NOT IN ('CAPPED', 'BAND')
           OR @EmployeeRate NOT BETWEEN 0 AND 100 OR @EmployerRate NOT BETWEEN 0 AND 100
           OR (@GovernmentRate IS NOT NULL AND @GovernmentRate NOT BETWEEN 0 AND 100)
           OR (@SalaryFloor IS NOT NULL AND @SalaryCeiling IS NOT NULL AND @SalaryCeiling < @SalaryFloor)
           OR (@EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Check the rates (0 - 100 %), the salary floor / ceiling and the effective dates.';
            RETURN;
        END;
        IF ISNULL(@IsActive, 1) = 1
           AND EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates]
                       WHERE Deleted = 0 AND IsActive = 1 AND ContributionCode = @ContributionCode AND ApplicableTo = @ApplicableTo
                         AND (@Action = 'INSERT' OR PifssRateId <> @Id)
                         AND EffectiveFrom <= ISNULL(@EffectiveTo, '9999-12-31')
                         AND ISNULL(EffectiveTo, '9999-12-31') >= @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active rate for this contribution and nationality group overlaps these dates. End-date the existing rate first.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[PifssContributionRates]
            (ContributionCode, ContributionName, ApplicableTo, CalculationBasis, EmployeeRate, EmployerRate, GovernmentRate,
             SalaryFloor, SalaryCeiling, EffectiveFrom, EffectiveTo, IsVerified, Notes, IsActive, CreatedBy)
        VALUES
            (@ContributionCode, @ContributionName, @ApplicableTo, @CalculationBasis, @EmployeeRate, @EmployerRate, @GovernmentRate,
             @SalaryFloor, @SalaryCeiling, @EffectiveFrom, @EffectiveTo, ISNULL(@IsVerified, 0), @Notes, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Social security rate created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        UPDATE [Payroll].[PifssContributionRates]
           SET ContributionCode = @ContributionCode, ContributionName = @ContributionName, ApplicableTo = @ApplicableTo,
               CalculationBasis = @CalculationBasis, EmployeeRate = @EmployeeRate, EmployerRate = @EmployerRate,
               GovernmentRate = @GovernmentRate, SalaryFloor = @SalaryFloor, SalaryCeiling = @SalaryCeiling,
               EffectiveFrom = @EffectiveFrom, EffectiveTo = @EffectiveTo, IsVerified = ISNULL(@IsVerified, IsVerified),
               Notes = @Notes, IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PifssRateId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Social security rate updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Payroll].[PifssContributionRates]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE PifssRateId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Social security rate deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates] AS me
                   INNER JOIN [Payroll].[PifssContributionRates] AS o
                           ON o.ContributionCode = me.ContributionCode AND o.ApplicableTo = me.ApplicableTo
                          AND o.PifssRateId <> me.PifssRateId AND o.Deleted = 0 AND o.IsActive = 1
                          AND o.EffectiveFrom <= ISNULL(me.EffectiveTo, '9999-12-31')
                          AND ISNULL(o.EffectiveTo, '9999-12-31') >= me.EffectiveFrom
                   WHERE me.PifssRateId = @Id AND me.IsActive = 0)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active rate overlaps these dates, so this one cannot be re-activated.';
            RETURN;
        END;

        UPDATE [Payroll].[PifssContributionRates]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PifssRateId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Rate activated.' ELSE N'Rate deactivated.' END
        FROM [Payroll].[PifssContributionRates] WHERE PifssRateId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_IndemnityRuleSet_Manage  -  end-of-service rules
   ---------------------------------------------------------------------
   INSERT / UPDATE   header + @SlabsJson + @FactorsJson in one call:
       @SlabsJson   [ { "FromYears": 0, "ToYears": 5, "EntitlementUnit": "DAYS",   "EntitlementValue": 15 },
                      { "FromYears": 5, "ToYears": null, "EntitlementUnit": "MONTHS", "EntitlementValue": 1 } ]
       @FactorsJson [ { "SeparationType": "RESIGNATION", "FromYears": 3, "ToYears": 5, "EntitlementPercent": 50 }, ... ]
     NULL json on UPDATE = leave those lines untouched. Lines are
     replaced as a set (old rows are soft-deleted, so history remains).
   SLABS / FACTORS   lines of rule set @Id
   Only one ACTIVE rule set may be in force on any date.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_IndemnityRuleSet_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- not used (country-level)
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- not used
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    @RuleSetCode              NVARCHAR(30)    = NULL,
    @RuleSetName              NVARCHAR(150)   = NULL,
    @DailyWageDivisor         DECIMAL(5,2)    = NULL,
    @MaxIndemnityMonths       DECIMAL(6,2)    = NULL,
    @MinServiceMonths         DECIMAL(6,2)    = NULL,
    @EffectiveFrom            DATE            = NULL,
    @EffectiveTo              DATE            = NULL,
    @IsVerified               BIT             = NULL,
    @Notes                    NVARCHAR(1000)  = NULL,
    @IsActive                 BIT             = NULL,
    @SlabsJson                NVARCHAR(MAX)   = NULL,
    @FactorsJson              NVARCHAR(MAX)   = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'SLABS', 'FACTORS', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[IndemnityRuleSets] AS r
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (@Pattern IS NULL OR r.RuleSetCode LIKE @Pattern ESCAPE '\' OR r.RuleSetName LIKE @Pattern ESCAPE '\');

        SELECT  r.IndemnityRuleSetId, r.RuleSetCode, r.RuleSetName, r.DailyWageDivisor, r.MaxIndemnityMonths, r.MinServiceMonths,
                r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive,
                (SELECT COUNT(1) FROM [Payroll].[IndemnityServiceSlabs] s       WHERE s.Deleted = 0 AND s.IndemnityRuleSetId = r.IndemnityRuleSetId) AS SlabCount,
                (SELECT COUNT(1) FROM [Payroll].[IndemnityEntitlementFactors] f WHERE f.Deleted = 0 AND f.IndemnityRuleSetId = r.IndemnityRuleSetId) AS FactorCount
        FROM   [Payroll].[IndemnityRuleSets] AS r
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (@Pattern IS NULL OR r.RuleSetCode LIKE @Pattern ESCAPE '\' OR r.RuleSetName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'RuleSetName' THEN r.RuleSetName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'RuleSetName' THEN r.RuleSetName END DESC,
                r.EffectiveFrom DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  r.IndemnityRuleSetId, r.RuleSetCode, r.RuleSetName, r.DailyWageDivisor, r.MaxIndemnityMonths, r.MinServiceMonths,
                r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive
        FROM   [Payroll].[IndemnityRuleSets] AS r
        WHERE  r.IndemnityRuleSetId = @Id AND r.Deleted = 0;
        RETURN;
    END;

    IF @Action = 'SLABS'
    BEGIN
        SELECT s.IndemnityServiceSlabId, s.IndemnityRuleSetId, s.FromYears, s.ToYears, s.EntitlementUnit, s.EntitlementValue, s.DisplayOrder
        FROM   [Payroll].[IndemnityServiceSlabs] AS s
        WHERE  s.IndemnityRuleSetId = @Id AND s.Deleted = 0
        ORDER BY s.FromYears;
        RETURN;
    END;

    IF @Action = 'FACTORS'
    BEGIN
        SELECT f.IndemnityEntitlementFactorId, f.IndemnityRuleSetId, f.SeparationType, f.FromYears, f.ToYears, f.EntitlementPercent
        FROM   [Payroll].[IndemnityEntitlementFactors] AS f
        WHERE  f.IndemnityRuleSetId = @Id AND f.Deleted = 0
        ORDER BY f.SeparationType, f.FromYears;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[IndemnityRuleSets] WHERE IndemnityRuleSetId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    DECLARE @Slabs TABLE (FromYears DECIMAL(5,2), ToYears DECIMAL(5,2), EntitlementUnit VARCHAR(6), EntitlementValue DECIMAL(7,3), DisplayOrder SMALLINT);
    DECLARE @Factors TABLE (SeparationType VARCHAR(20), FromYears DECIMAL(5,2), ToYears DECIMAL(5,2), EntitlementPercent DECIMAL(7,4));

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SET @DailyWageDivisor = ISNULL(@DailyWageDivisor, 26);

        IF NULLIF(LTRIM(RTRIM(@RuleSetCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@RuleSetName)), N'') IS NULL OR @EffectiveFrom IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Code, name and effective-from date are required.';
            RETURN;
        END;
        IF @DailyWageDivisor <= 0 OR @DailyWageDivisor > 31 OR (@MaxIndemnityMonths IS NOT NULL AND @MaxIndemnityMonths <= 0)
           OR (@EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Check the daily-wage divisor (1 - 31), the cap and the effective dates.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[IndemnityRuleSets]
                   WHERE Deleted = 0 AND RuleSetCode = @RuleSetCode AND (@Action = 'INSERT' OR IndemnityRuleSetId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
        IF ISNULL(@IsActive, 1) = 1
           AND EXISTS (SELECT 1 FROM [Payroll].[IndemnityRuleSets]
                       WHERE Deleted = 0 AND IsActive = 1 AND (@Action = 'INSERT' OR IndemnityRuleSetId <> @Id)
                         AND EffectiveFrom <= ISNULL(@EffectiveTo, '9999-12-31')
                         AND ISNULL(EffectiveTo, '9999-12-31') >= @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active indemnity rule set is in force for overlapping dates. End-date it first.';
            RETURN;
        END;

        IF @SlabsJson IS NOT NULL
        BEGIN
            IF ISJSON(@SlabsJson) = 0
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The service slabs could not be read.';
                RETURN;
            END;
            INSERT INTO @Slabs (FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder)
            SELECT j.FromYears, j.ToYears, UPPER(LTRIM(RTRIM(j.EntitlementUnit))), j.EntitlementValue,
                   ROW_NUMBER() OVER (ORDER BY j.FromYears)
            FROM OPENJSON(@SlabsJson) WITH (FromYears DECIMAL(5,2) '$.FromYears', ToYears DECIMAL(5,2) '$.ToYears',
                                            EntitlementUnit VARCHAR(6) '$.EntitlementUnit', EntitlementValue DECIMAL(7,3) '$.EntitlementValue') AS j;

            IF NOT EXISTS (SELECT 1 FROM @Slabs)
               OR EXISTS (SELECT 1 FROM @Slabs WHERE FromYears IS NULL OR FromYears < 0 OR (ToYears IS NOT NULL AND ToYears <= FromYears)
                                                 OR EntitlementUnit NOT IN ('DAYS', 'MONTHS') OR EntitlementUnit IS NULL
                                                 OR EntitlementValue IS NULL OR EntitlementValue < 0)
               OR EXISTS (SELECT 1 FROM @Slabs a JOIN @Slabs b ON a.DisplayOrder < b.DisplayOrder
                          WHERE a.FromYears < ISNULL(b.ToYears, 999) AND ISNULL(a.ToYears, 999) > b.FromYears)
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Service slabs need valid, non-overlapping year ranges and an entitlement in Days or Months.';
                RETURN;
            END;
        END
        ELSE IF @Action = 'INSERT'
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Add at least one service slab.';
            RETURN;
        END;

        IF @FactorsJson IS NOT NULL
        BEGIN
            IF ISJSON(@FactorsJson) = 0
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The entitlement factors could not be read.';
                RETURN;
            END;
            INSERT INTO @Factors (SeparationType, FromYears, ToYears, EntitlementPercent)
            SELECT UPPER(LTRIM(RTRIM(j.SeparationType))), j.FromYears, j.ToYears, j.EntitlementPercent
            FROM OPENJSON(@FactorsJson) WITH (SeparationType VARCHAR(20) '$.SeparationType', FromYears DECIMAL(5,2) '$.FromYears',
                                              ToYears DECIMAL(5,2) '$.ToYears', EntitlementPercent DECIMAL(7,4) '$.EntitlementPercent') AS j;

            IF EXISTS (SELECT 1 FROM @Factors
                       WHERE SeparationType IS NULL
                          OR SeparationType NOT IN ('RESIGNATION', 'TERMINATION', 'CONTRACT_END', 'RETIREMENT', 'DEATH', 'DISABILITY', 'OTHER')
                          OR FromYears IS NULL OR FromYears < 0 OR (ToYears IS NOT NULL AND ToYears <= FromYears)
                          OR EntitlementPercent IS NULL OR EntitlementPercent NOT BETWEEN 0 AND 100)
               OR EXISTS (SELECT 1 FROM (SELECT *, ROW_NUMBER() OVER (ORDER BY SeparationType, FromYears) AS rn FROM @Factors) a
                          JOIN (SELECT *, ROW_NUMBER() OVER (ORDER BY SeparationType, FromYears) AS rn FROM @Factors) b
                            ON a.SeparationType = b.SeparationType AND a.rn < b.rn
                          WHERE a.FromYears < ISNULL(b.ToYears, 999) AND ISNULL(a.ToYears, 999) > b.FromYears)
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Entitlement factors need a valid separation type, non-overlapping year ranges and a percentage between 0 and 100.';
                RETURN;
            END;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            INSERT INTO [Payroll].[IndemnityRuleSets]
                (RuleSetCode, RuleSetName, DailyWageDivisor, MaxIndemnityMonths, MinServiceMonths, EffectiveFrom, EffectiveTo,
                 IsVerified, Notes, IsActive, CreatedBy)
            VALUES
                (@RuleSetCode, @RuleSetName, @DailyWageDivisor, @MaxIndemnityMonths, @MinServiceMonths, @EffectiveFrom, @EffectiveTo,
                 ISNULL(@IsVerified, 0), @Notes, ISNULL(@IsActive, 1), @UserId);
            SET @NewId = SCOPE_IDENTITY();

            INSERT INTO [Payroll].[IndemnityServiceSlabs] (IndemnityRuleSetId, FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder, CreatedBy)
            SELECT @NewId, FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder, @UserId FROM @Slabs;

            INSERT INTO [Payroll].[IndemnityEntitlementFactors] (IndemnityRuleSetId, SeparationType, FromYears, ToYears, EntitlementPercent, CreatedBy)
            SELECT @NewId, SeparationType, FromYears, ToYears, EntitlementPercent, @UserId FROM @Factors;
        COMMIT;

        SET @ResultMessage = N'Indemnity rule set created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[IndemnityRuleSets]
               SET RuleSetCode = @RuleSetCode, RuleSetName = @RuleSetName, DailyWageDivisor = @DailyWageDivisor,
                   MaxIndemnityMonths = @MaxIndemnityMonths, MinServiceMonths = @MinServiceMonths,
                   EffectiveFrom = @EffectiveFrom, EffectiveTo = @EffectiveTo, IsVerified = ISNULL(@IsVerified, IsVerified),
                   Notes = @Notes, IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE IndemnityRuleSetId = @Id;

            IF @SlabsJson IS NOT NULL
            BEGIN
                UPDATE [Payroll].[IndemnityServiceSlabs]
                   SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
                 WHERE IndemnityRuleSetId = @Id AND Deleted = 0;

                INSERT INTO [Payroll].[IndemnityServiceSlabs] (IndemnityRuleSetId, FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder, CreatedBy)
                SELECT @Id, FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder, @UserId FROM @Slabs;
            END;

            IF @FactorsJson IS NOT NULL
            BEGIN
                UPDATE [Payroll].[IndemnityEntitlementFactors]
                   SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
                 WHERE IndemnityRuleSetId = @Id AND Deleted = 0;

                INSERT INTO [Payroll].[IndemnityEntitlementFactors] (IndemnityRuleSetId, SeparationType, FromYears, ToYears, EntitlementPercent, CreatedBy)
                SELECT @Id, SeparationType, FromYears, ToYears, EntitlementPercent, @UserId FROM @Factors;
            END;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Indemnity rule set updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[IndemnityServiceSlabs]       SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE IndemnityRuleSetId = @Id AND Deleted = 0;
            UPDATE [Payroll].[IndemnityEntitlementFactors] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE IndemnityRuleSetId = @Id AND Deleted = 0;
            UPDATE [Payroll].[IndemnityRuleSets]           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE IndemnityRuleSetId = @Id AND Deleted = 0;
        COMMIT;

        SET @ResultMessage = N'Indemnity rule set deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[IndemnityRuleSets] AS me
                   INNER JOIN [Payroll].[IndemnityRuleSets] AS o
                           ON o.IndemnityRuleSetId <> me.IndemnityRuleSetId AND o.Deleted = 0 AND o.IsActive = 1
                          AND o.EffectiveFrom <= ISNULL(me.EffectiveTo, '9999-12-31')
                          AND ISNULL(o.EffectiveTo, '9999-12-31') >= me.EffectiveFrom
                   WHERE me.IndemnityRuleSetId = @Id AND me.IsActive = 0)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active rule set overlaps these dates, so this one cannot be re-activated.';
            RETURN;
        END;

        UPDATE [Payroll].[IndemnityRuleSets]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE IndemnityRuleSetId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Rule set activated.' ELSE N'Rule set deactivated.' END
        FROM [Payroll].[IndemnityRuleSets] WHERE IndemnityRuleSetId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_OvertimeRate_Manage
   ---------------------------------------------------------------------
   CompanyId NULL = statutory default; a company row overrides it for
   that company. LIST with @CompanyId returns the defaults AND that
   company's own rows (IsCompanyOverride tells them apart).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_OvertimeRate_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column (NULL = statutory default)
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    @OvertimeCode             VARCHAR(20)     = NULL,
    @OvertimeName             NVARCHAR(150)   = NULL,
    @Multiplier               DECIMAL(5,3)    = NULL,
    @HourlyRateDivisorDays    DECIMAL(5,2)    = NULL,
    @HoursPerDay              DECIMAL(4,2)    = NULL,
    @MaxHoursPerDay           DECIMAL(4,2)    = NULL,
    @MaxHoursPerYear          INT             = NULL,
    @EffectiveFrom            DATE            = NULL,
    @EffectiveTo              DATE            = NULL,
    @IsVerified               BIT             = NULL,
    @Notes                    NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[OvertimeRates] AS r
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (r.CompanyId IS NULL OR @CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND (r.CompanyId IS NULL OR @CompanyIds IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR r.OvertimeCode LIKE @Pattern ESCAPE '\' OR r.OvertimeName LIKE @Pattern ESCAPE '\');

        SELECT  r.OvertimeRateId, r.CompanyId, r.OvertimeCode, r.OvertimeName, r.Multiplier, r.HourlyRateDivisorDays, r.HoursPerDay,
                r.MaxHoursPerDay, r.MaxHoursPerYear, r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive,
                ISNULL(c.CompanyName, N'(Statutory default)') AS CompanyName,
                CAST(CASE WHEN r.CompanyId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsCompanyOverride
        FROM        [Payroll].[OvertimeRates] AS r
        LEFT JOIN   [Core].[Companies]        AS c ON c.CompanyId = r.CompanyId
        WHERE  r.Deleted = 0
          AND (@IsActiveFilter IS NULL OR r.IsActive = @IsActiveFilter)
          AND (r.CompanyId IS NULL OR @CompanyId IS NULL OR r.CompanyId = @CompanyId)
          AND (r.CompanyId IS NULL OR @CompanyIds IS NULL OR CHARINDEX(',' + CAST(r.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@Pattern IS NULL OR r.OvertimeCode LIKE @Pattern ESCAPE '\' OR r.OvertimeName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'OvertimeName' THEN r.OvertimeName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'OvertimeName' THEN r.OvertimeName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'Multiplier'   THEN r.Multiplier END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'Multiplier'   THEN r.Multiplier END DESC,
                CASE WHEN r.CompanyId IS NULL THEN 0 ELSE 1 END, c.CompanyName, r.Multiplier, r.EffectiveFrom DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  r.OvertimeRateId, r.CompanyId, r.OvertimeCode, r.OvertimeName, r.Multiplier, r.HourlyRateDivisorDays, r.HoursPerDay,
                r.MaxHoursPerDay, r.MaxHoursPerYear, r.EffectiveFrom, r.EffectiveTo, r.IsVerified, r.Notes, r.IsActive,
                ISNULL(c.CompanyName, N'(Statutory default)') AS CompanyName
        FROM        [Payroll].[OvertimeRates] AS r
        LEFT JOIN   [Core].[Companies]        AS c ON c.CompanyId = r.CompanyId
        WHERE  r.OvertimeRateId = @Id AND r.Deleted = 0;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[OvertimeRates] WHERE OvertimeRateId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @OvertimeCode          = UPPER(LTRIM(RTRIM(@OvertimeCode))),
               @HourlyRateDivisorDays = ISNULL(@HourlyRateDivisorDays, 26),
               @HoursPerDay           = ISNULL(@HoursPerDay, 8);

        IF @OvertimeCode NOT IN ('NORMAL_DAY', 'REST_DAY', 'PUBLIC_HOLIDAY', 'NIGHT', 'OTHER') OR @OvertimeCode IS NULL
           OR NULLIF(LTRIM(RTRIM(@OvertimeName)), N'') IS NULL OR @Multiplier IS NULL OR @EffectiveFrom IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Overtime type, name, multiplier and effective-from date are required.';
            RETURN;
        END;
        IF @Multiplier <= 0 OR @Multiplier > 10 OR @HourlyRateDivisorDays <= 0 OR @HourlyRateDivisorDays > 31
           OR @HoursPerDay <= 0 OR @HoursPerDay > 24 OR (@MaxHoursPerDay IS NOT NULL AND @MaxHoursPerDay NOT BETWEEN 0 AND 24)
           OR (@EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Check the multiplier, hours, divisor and effective dates.';
            RETURN;
        END;
        IF ISNULL(@IsActive, 1) = 1
           AND EXISTS (SELECT 1 FROM [Payroll].[OvertimeRates]
                       WHERE Deleted = 0 AND IsActive = 1 AND OvertimeCode = @OvertimeCode
                         AND ISNULL(CompanyId, 0) = ISNULL(@CompanyId, 0)
                         AND (@Action = 'INSERT' OR OvertimeRateId <> @Id)
                         AND EffectiveFrom <= ISNULL(@EffectiveTo, '9999-12-31')
                         AND ISNULL(EffectiveTo, '9999-12-31') >= @EffectiveFrom)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'An active rate for this overtime type already covers overlapping dates. End-date it first.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[OvertimeRates]
            (CompanyId, OvertimeCode, OvertimeName, Multiplier, HourlyRateDivisorDays, HoursPerDay, MaxHoursPerDay, MaxHoursPerYear,
             EffectiveFrom, EffectiveTo, IsVerified, Notes, IsActive, CreatedBy)
        VALUES
            (@CompanyId, @OvertimeCode, @OvertimeName, @Multiplier, @HourlyRateDivisorDays, @HoursPerDay, @MaxHoursPerDay, @MaxHoursPerYear,
             @EffectiveFrom, @EffectiveTo, ISNULL(@IsVerified, 0), @Notes, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Overtime rate created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        UPDATE [Payroll].[OvertimeRates]
           SET CompanyId = @CompanyId, OvertimeCode = @OvertimeCode, OvertimeName = @OvertimeName, Multiplier = @Multiplier,
               HourlyRateDivisorDays = @HourlyRateDivisorDays, HoursPerDay = @HoursPerDay, MaxHoursPerDay = @MaxHoursPerDay,
               MaxHoursPerYear = @MaxHoursPerYear, EffectiveFrom = @EffectiveFrom, EffectiveTo = @EffectiveTo,
               IsVerified = ISNULL(@IsVerified, IsVerified), Notes = @Notes, IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OvertimeRateId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Overtime rate updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Payroll].[OvertimeRates]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE OvertimeRateId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Overtime rate deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[OvertimeRates] AS me
                   INNER JOIN [Payroll].[OvertimeRates] AS o
                           ON o.OvertimeCode = me.OvertimeCode AND ISNULL(o.CompanyId, 0) = ISNULL(me.CompanyId, 0)
                          AND o.OvertimeRateId <> me.OvertimeRateId AND o.Deleted = 0 AND o.IsActive = 1
                          AND o.EffectiveFrom <= ISNULL(me.EffectiveTo, '9999-12-31')
                          AND ISNULL(o.EffectiveTo, '9999-12-31') >= me.EffectiveFrom
                   WHERE me.OvertimeRateId = @Id AND me.IsActive = 0)
        BEGIN
            SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'Another active rate overlaps these dates, so this one cannot be re-activated.';
            RETURN;
        END;

        UPDATE [Payroll].[OvertimeRates]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE OvertimeRateId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Overtime rate activated.' ELSE N'Overtime rate deactivated.' END
        FROM [Payroll].[OvertimeRates] WHERE OvertimeRateId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_Bank_Manage  -  bank master (shared by all companies)
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Bank_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- not used (banks are global)
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- not used
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    @BankCode                 NVARCHAR(20)    = NULL,
    @BankName                 NVARCHAR(150)   = NULL,
    @ArabicName               NVARCHAR(150)   = NULL,
    @ShortName                NVARCHAR(30)    = NULL,
    @SwiftCode                NVARCHAR(11)    = NULL,
    @IbanBankCode             NVARCHAR(10)    = NULL,
    @WpsBankCode              NVARCHAR(20)    = NULL,
    @CountryId                INT             = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[Banks] AS b
        WHERE  b.Deleted = 0
          AND (@IsActiveFilter IS NULL OR b.IsActive = @IsActiveFilter)
          AND (@Pattern IS NULL OR b.BankCode LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\'
               OR b.ShortName LIKE @Pattern ESCAPE '\' OR b.SwiftCode LIKE @Pattern ESCAPE '\' OR b.WpsBankCode LIKE @Pattern ESCAPE '\');

        SELECT  b.BankId, b.BankCode, b.BankName, b.ArabicName, b.ShortName, b.SwiftCode, b.IbanBankCode, b.WpsBankCode,
                b.CountryId, b.IsActive, co.CountryName,
                (SELECT COUNT(1) FROM [Payroll].[CompanyBankAccounts] a WHERE a.Deleted = 0 AND a.BankId = b.BankId) AS AccountCount
        FROM        [Payroll].[Banks]   AS b
        LEFT JOIN   [Core].[Countries]  AS co ON co.CountryId = b.CountryId
        WHERE  b.Deleted = 0
          AND (@IsActiveFilter IS NULL OR b.IsActive = @IsActiveFilter)
          AND (@Pattern IS NULL OR b.BankCode LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\'
               OR b.ShortName LIKE @Pattern ESCAPE '\' OR b.SwiftCode LIKE @Pattern ESCAPE '\' OR b.WpsBankCode LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BankCode'    THEN b.BankCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BankCode'    THEN b.BankCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BankName'    THEN b.BankName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BankName'    THEN b.BankName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'SwiftCode'   THEN b.SwiftCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'SwiftCode'   THEN b.SwiftCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'    THEN b.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'    THEN b.IsActive END DESC,
                b.BankName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  b.BankId, b.BankCode, b.BankName, b.ArabicName, b.ShortName, b.SwiftCode, b.IbanBankCode, b.WpsBankCode,
                b.CountryId, b.IsActive, co.CountryName
        FROM        [Payroll].[Banks]   AS b
        LEFT JOIN   [Core].[Countries]  AS co ON co.CountryId = b.CountryId
        WHERE b.BankId = @Id AND b.Deleted = 0;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[Banks] WHERE BankId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @SwiftCode    = NULLIF(UPPER(REPLACE(LTRIM(RTRIM(@SwiftCode)), N' ', N'')), N''),
               @IbanBankCode = NULLIF(UPPER(LTRIM(RTRIM(@IbanBankCode))), N'');

        IF NULLIF(LTRIM(RTRIM(@BankCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@BankName)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Bank code and name are required.';
            RETURN;
        END;
        IF @SwiftCode IS NOT NULL AND (LEN(@SwiftCode) NOT IN (8, 11) OR @SwiftCode LIKE N'%[^A-Z0-9]%')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A SWIFT / BIC code is 8 or 11 letters and digits.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[Banks] WHERE Deleted = 0 AND BankCode = @BankCode AND (@Action = 'INSERT' OR BankId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[Banks] (BankCode, BankName, ArabicName, ShortName, SwiftCode, IbanBankCode, WpsBankCode, CountryId, IsActive, CreatedBy)
        VALUES (@BankCode, @BankName, @ArabicName, @ShortName, @SwiftCode, @IbanBankCode, @WpsBankCode, @CountryId, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Bank created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        UPDATE [Payroll].[Banks]
           SET BankCode = @BankCode, BankName = @BankName, ArabicName = @ArabicName, ShortName = @ShortName,
               SwiftCode = @SwiftCode, IbanBankCode = @IbanBankCode, WpsBankCode = @WpsBankCode, CountryId = @CountryId,
               IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE BankId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Bank updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[CompanyBankAccounts] WHERE Deleted = 0 AND BankId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'A company bank account uses this bank, so it cannot be deleted. Deactivate it instead.';
            RETURN;
        END;

        UPDATE [Payroll].[Banks] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE BankId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Bank deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Payroll].[Banks]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE BankId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Bank activated.' ELSE N'Bank deactivated.' END
        FROM [Payroll].[Banks] WHERE BankId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_CompanyBankAccount_Manage  -  company's own debit accounts
   ---------------------------------------------------------------------
   IBAN is normalised (upper case, no spaces) and mod-97 checked.
   At most one default account per company (setting a new default
   clears the old one).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_CompanyBankAccount_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,   -- LIST filter: BankId
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',

    @BankId                   INT             = NULL,
    @AccountCode              NVARCHAR(30)    = NULL,
    @AccountTitle             NVARCHAR(150)   = NULL,
    @AccountNumber            NVARCHAR(34)    = NULL,
    @Iban                     NVARCHAR(50)    = NULL,   -- wider than the column: users type IBANs with spaces
    @CurrencyId               INT             = NULL,
    @BranchName               NVARCHAR(150)   = NULL,
    @WpsEmployerCode          NVARCHAR(50)    = NULL,
    @PamFileNo                NVARCHAR(50)    = NULL,
    @IsDefault                BIT             = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Payroll].[CompanyBankAccounts] AS a
        INNER JOIN  [Payroll].[Banks]               AS b ON b.BankId = a.BankId
        WHERE  a.Deleted = 0
          AND (@IsActiveFilter IS NULL OR a.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR a.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(a.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ParentId IS NULL OR a.BankId = @ParentId)
          AND (@Pattern IS NULL OR a.AccountCode LIKE @Pattern ESCAPE '\' OR a.AccountTitle LIKE @Pattern ESCAPE '\'
               OR a.Iban LIKE @Pattern ESCAPE '\' OR a.AccountNumber LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\');

        SELECT  a.CompanyBankAccountId, a.CompanyId, a.BankId, a.AccountCode, a.AccountTitle, a.AccountNumber, a.Iban,
                a.CurrencyId, a.BranchName, a.WpsEmployerCode, a.PamFileNo, a.IsDefault, a.IsActive,
                c.CompanyName, b.BankName, b.SwiftCode, b.WpsBankCode, cu.CurrencyCode
        FROM        [Payroll].[CompanyBankAccounts] AS a
        INNER JOIN  [Payroll].[Banks]               AS b  ON b.BankId      = a.BankId
        INNER JOIN  [Core].[Companies]              AS c  ON c.CompanyId   = a.CompanyId
        LEFT JOIN   [Core].[Currencies]             AS cu ON cu.CurrencyId = a.CurrencyId
        WHERE  a.Deleted = 0
          AND (@IsActiveFilter IS NULL OR a.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR a.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(a.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ParentId IS NULL OR a.BankId = @ParentId)
          AND (@Pattern IS NULL OR a.AccountCode LIKE @Pattern ESCAPE '\' OR a.AccountTitle LIKE @Pattern ESCAPE '\'
               OR a.Iban LIKE @Pattern ESCAPE '\' OR a.AccountNumber LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'AccountCode'  THEN a.AccountCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'AccountCode'  THEN a.AccountCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'AccountTitle' THEN a.AccountTitle END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'AccountTitle' THEN a.AccountTitle END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'BankName'     THEN b.BankName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'BankName'     THEN b.BankName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CompanyName'  THEN c.CompanyName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CompanyName'  THEN c.CompanyName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'     THEN a.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'     THEN a.IsActive END DESC,
                a.IsDefault DESC, a.AccountTitle ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  a.CompanyBankAccountId, a.CompanyId, a.BankId, a.AccountCode, a.AccountTitle, a.AccountNumber, a.Iban,
                a.CurrencyId, a.BranchName, a.WpsEmployerCode, a.PamFileNo, a.IsDefault, a.IsActive,
                c.CompanyName, b.BankName, b.SwiftCode, b.WpsBankCode, cu.CurrencyCode
        FROM        [Payroll].[CompanyBankAccounts] AS a
        INNER JOIN  [Payroll].[Banks]               AS b  ON b.BankId      = a.BankId
        INNER JOIN  [Core].[Companies]              AS c  ON c.CompanyId   = a.CompanyId
        LEFT JOIN   [Core].[Currencies]             AS cu ON cu.CurrencyId = a.CurrencyId
        WHERE a.CompanyBankAccountId = @Id AND a.Deleted = 0;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[CompanyBankAccounts] WHERE CompanyBankAccountId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @Iban          = NULLIF(UPPER(REPLACE(REPLACE(LTRIM(RTRIM(@Iban)), N' ', N''), N'-', N'')), N''),
               @AccountNumber = NULLIF(LTRIM(RTRIM(@AccountNumber)), N'');

        IF @CompanyId IS NULL OR @BankId IS NULL OR NULLIF(LTRIM(RTRIM(@AccountCode)), N'') IS NULL
           OR NULLIF(LTRIM(RTRIM(@AccountTitle)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Company, bank, account code and account title are required.';
            RETURN;
        END;
        IF @Iban IS NULL AND @AccountNumber IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the IBAN or the account number.';
            RETURN;
        END;
        IF @Iban IS NOT NULL AND (LEN(@Iban) > 34 OR [Payroll].[ufn_IbanIsValid](@Iban) = 0)
        BEGIN
            SELECT @ResultCode = 'INVALID_IBAN', @ResultMessage = N'That IBAN is not valid. Kuwait IBANs are 30 characters starting with KW - check for a mistyped digit.';
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[Banks] WHERE BankId = @BankId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select a valid bank.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[CompanyBankAccounts]
                   WHERE Deleted = 0 AND CompanyId = @CompanyId AND AccountCode = @AccountCode
                     AND (@Action = 'INSERT' OR CompanyBankAccountId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
        IF @Iban IS NOT NULL
           AND EXISTS (SELECT 1 FROM [Payroll].[CompanyBankAccounts]
                       WHERE Deleted = 0 AND Iban = @Iban AND (@Action = 'INSERT' OR CompanyBankAccountId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_IBAN', @ResultMessage = N'This IBAN is already registered as a company account.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            IF ISNULL(@IsDefault, 0) = 1
                UPDATE [Payroll].[CompanyBankAccounts] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE CompanyId = @CompanyId AND IsDefault = 1 AND Deleted = 0;

            INSERT INTO [Payroll].[CompanyBankAccounts]
                (CompanyId, BankId, AccountCode, AccountTitle, AccountNumber, Iban, CurrencyId, BranchName,
                 WpsEmployerCode, PamFileNo, IsDefault, IsActive, CreatedBy)
            VALUES
                (@CompanyId, @BankId, @AccountCode, @AccountTitle, @AccountNumber, @Iban, @CurrencyId, @BranchName,
                 @WpsEmployerCode, @PamFileNo, ISNULL(@IsDefault, 0), ISNULL(@IsActive, 1), @UserId);

            SET @NewId = SCOPE_IDENTITY();
        COMMIT;

        SET @ResultMessage = N'Company bank account created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
            IF ISNULL(@IsDefault, 0) = 1
                UPDATE [Payroll].[CompanyBankAccounts] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE CompanyId = @CompanyId AND IsDefault = 1 AND Deleted = 0 AND CompanyBankAccountId <> @Id;

            UPDATE [Payroll].[CompanyBankAccounts]
               SET CompanyId = @CompanyId, BankId = @BankId, AccountCode = @AccountCode, AccountTitle = @AccountTitle,
                   AccountNumber = @AccountNumber, Iban = @Iban, CurrencyId = @CurrencyId, BranchName = @BranchName,
                   WpsEmployerCode = @WpsEmployerCode, PamFileNo = @PamFileNo, IsDefault = ISNULL(@IsDefault, 0),
                   IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE CompanyBankAccountId = @Id;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Company bank account updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Payroll].[CompanyBankAccounts]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME(), IsDefault = 0
         WHERE CompanyBankAccountId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Company bank account deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Payroll].[CompanyBankAccounts]
           SET IsActive  = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END,
               IsDefault = CASE WHEN IsActive = 1 THEN 0 ELSE IsDefault END,
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE CompanyBankAccountId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Bank account activated.' ELSE N'Bank account deactivated.' END
        FROM [Payroll].[CompanyBankAccounts] WHERE CompanyBankAccountId = @Id;
        RETURN;
    END;
END;
GO

PRINT N'30_Payroll_Master_StoredProcedures.sql applied.';
GO
