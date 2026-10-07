/* =====================================================================
   48_Payroll_Settings_StoredProcedures.sql  -  HRMS Payroll Settings
   ---------------------------------------------------------------------
   Run AFTER 47_Payroll_Settings_Tables.sql. Idempotent (CREATE OR ALTER).

   The procedures of the five rule screens. Same envelope as db/30, so
   the repositories drive them the same way:

       @Action  LIST | GET | INSERT | UPDATE | DELETE | TOGGLE  (+ extras)
       @Id, @Search, @IsActiveFilter, @CompanyId, @CompanyIds,
       @PageNumber, @PageSize, @UserId
       OUT: @TotalCount, @NewId, @ResultCode, @ResultMessage

     usp_DeductionPolicy_Manage   + LINES (priorities), CALENDARS
     usp_ProrationRule_Manage     LIST / GET / UPDATE (one row per calendar,
                                  @Id = PayrollCalendarId; UPDATE inserts the
                                  rule the first time and also saves the
                                  calendar's day basis)
     usp_ApprovalProcess_Manage   + ROLES, USERS
     usp_BankFileFormat_Manage    + LINES (fields), BANKS
     usp_GLMapping_Manage         + COMPONENTS

   Lines are saved with the header in ONE call (JSON, array order = order).
   DELETE always means Deleted = 1 (soft delete) - see script 28.

   Company scope (LIST): rows of the companies in @CompanyId / @CompanyIds,
   plus the defaults (CompanyId NULL) for every company.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[DeductionPolicies]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 47 (payroll settings tables) before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* =====================================================================
   Payroll.ufn_InCompanyScope - the row's company is in the list scope
   (NULL company = a default row, always in scope).
===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_InCompanyScope] (@RowCompanyId INT, @CompanyId INT, @CompanyIds NVARCHAR(2000))
RETURNS BIT
AS
BEGIN
    IF @RowCompanyId IS NULL RETURN 1;
    IF @CompanyId IS NOT NULL AND @RowCompanyId <> @CompanyId RETURN 0;
    IF @CompanyIds IS NOT NULL
       AND CHARINDEX(',' + CAST(@RowCompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') = 0 RETURN 0;
    RETURN 1;
END;
GO

/* =====================================================================
   Payroll.usp_DeductionPolicy_Manage
   ---------------------------------------------------------------------
   One policy per company and calendar (CompanyId NULL = the default for
   every company; PayrollCalendarId NULL = every calendar of the company).
   The default cannot be deleted or deactivated.
   @PrioritiesJson: [{"DeductionGroup":"STATUTORY","Behaviour":"ALWAYS"}, ...]
   - top = recovered first.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_DeductionPolicy_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column (NULL = default)
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,

    @PayrollCalendarId        INT             = NULL,
    @MaxDeductionPercent      DECIMAL(5,2)    = NULL,
    @WhenExceeded             VARCHAR(10)     = NULL,
    @Notes                    NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,
    @PrioritiesJson           NVARCHAR(MAX)   = NULL,

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

    IF @Action NOT IN ('LIST', 'GET', 'LINES', 'CALENDARS', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Payroll].[DeductionPolicies] AS d
        LEFT JOIN   [Core].[Companies]            AS c  ON c.CompanyId = d.CompanyId
        LEFT JOIN   [Payroll].[PayrollCalendars]  AS pc ON pc.PayrollCalendarId = d.PayrollCalendarId
        WHERE  d.Deleted = 0
          AND (@IsActiveFilter IS NULL OR d.IsActive = @IsActiveFilter)
          AND [Payroll].[ufn_InCompanyScope](d.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@Pattern IS NULL OR c.CompanyName LIKE @Pattern ESCAPE '\' OR pc.CalendarName LIKE @Pattern ESCAPE '\'
               OR d.Notes LIKE @Pattern ESCAPE '\');

        SELECT  d.DeductionPolicyId, d.CompanyId, d.PayrollCalendarId, d.MaxDeductionPercent, d.WhenExceeded, d.Notes, d.IsActive,
                c.CompanyName, pc.CalendarName,
                CAST(CASE WHEN d.CompanyId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsDefault,
                (SELECT STRING_AGG(p.DeductionGroup, ',') WITHIN GROUP (ORDER BY p.PriorityNo)
                 FROM [Payroll].[DeductionPriorities] p WHERE p.DeductionPolicyId = d.DeductionPolicyId AND p.Deleted = 0) AS PriorityOrder
        FROM        [Payroll].[DeductionPolicies] AS d
        LEFT JOIN   [Core].[Companies]            AS c  ON c.CompanyId = d.CompanyId
        LEFT JOIN   [Payroll].[PayrollCalendars]  AS pc ON pc.PayrollCalendarId = d.PayrollCalendarId
        WHERE  d.Deleted = 0
          AND (@IsActiveFilter IS NULL OR d.IsActive = @IsActiveFilter)
          AND [Payroll].[ufn_InCompanyScope](d.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@Pattern IS NULL OR c.CompanyName LIKE @Pattern ESCAPE '\' OR pc.CalendarName LIKE @Pattern ESCAPE '\'
               OR d.Notes LIKE @Pattern ESCAPE '\')
        ORDER BY CASE WHEN d.CompanyId IS NULL THEN 0 ELSE 1 END, c.CompanyName,
                 CASE WHEN d.PayrollCalendarId IS NULL THEN 0 ELSE 1 END, pc.CalendarName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT  d.DeductionPolicyId, d.CompanyId, d.PayrollCalendarId, d.MaxDeductionPercent, d.WhenExceeded, d.Notes, d.IsActive,
                c.CompanyName, pc.CalendarName,
                CAST(CASE WHEN d.CompanyId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsDefault
        FROM        [Payroll].[DeductionPolicies] AS d
        LEFT JOIN   [Core].[Companies]            AS c  ON c.CompanyId = d.CompanyId
        LEFT JOIN   [Payroll].[PayrollCalendars]  AS pc ON pc.PayrollCalendarId = d.PayrollCalendarId
        WHERE  d.DeductionPolicyId = @Id AND d.Deleted = 0;
        RETURN;
    END;

    IF @Action = 'LINES'
    BEGIN
        SELECT p.PriorityNo, p.DeductionGroup, p.Behaviour
        FROM   [Payroll].[DeductionPriorities] AS p
        WHERE  p.DeductionPolicyId = @Id AND p.Deleted = 0
        ORDER BY p.PriorityNo;
        RETURN;
    END;

    /* the active calendars of a company (the policy's calendar dropdown) */
    IF @Action = 'CALENDARS'
    BEGIN
        SELECT pc.PayrollCalendarId AS Id, pc.CalendarName AS [Text]
        FROM   [Payroll].[PayrollCalendars] AS pc
        WHERE  pc.CompanyId = @CompanyId AND pc.Deleted = 0 AND (pc.IsActive = 1 OR pc.PayrollCalendarId = @PayrollCalendarId)
        ORDER BY pc.CalendarName;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[DeductionPolicies] WHERE DeductionPolicyId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    DECLARE @IsDefaultRow BIT =
        CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[DeductionPolicies] WHERE DeductionPolicyId = @Id AND CompanyId IS NULL) THEN 1 ELSE 0 END;

    DECLARE @Lines TABLE (PriorityNo SMALLINT, DeductionGroup VARCHAR(15), Behaviour VARCHAR(10));

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        /* the default stays the default (company and calendar cannot be changed) */
        IF @Action = 'UPDATE' AND @IsDefaultRow = 1 SELECT @CompanyId = NULL, @PayrollCalendarId = NULL, @IsActive = 1;
        SET @WhenExceeded = UPPER(LTRIM(RTRIM(ISNULL(@WhenExceeded, 'DEFER'))));

        IF @Action = 'INSERT' AND @CompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the company the rule is for (the default already exists).';
            RETURN;
        END;
        IF @MaxDeductionPercent IS NULL OR @MaxDeductionPercent <= 0 OR @MaxDeductionPercent > 100
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the maximum deductions as a percentage above 0 and up to 100.';
            RETURN;
        END;
        IF @WhenExceeded NOT IN ('DEFER', 'WARN')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose what happens when the limit is exceeded.';
            RETURN;
        END;
        IF @PayrollCalendarId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @PayrollCalendarId AND CompanyId = @CompanyId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The payroll calendar does not belong to the selected company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[DeductionPolicies]
                   WHERE Deleted = 0 AND (@Action = 'INSERT' OR DeductionPolicyId <> @Id)
                     AND ISNULL(CompanyId, 0) = ISNULL(@CompanyId, 0) AND ISNULL(PayrollCalendarId, 0) = ISNULL(@PayrollCalendarId, 0))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'A deduction rule already exists for this company and calendar. Edit that one instead.';
            RETURN;
        END;

        IF @PrioritiesJson IS NULL OR ISJSON(@PrioritiesJson) = 0
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Add the deduction priorities.';
            RETURN;
        END;
        INSERT INTO @Lines (PriorityNo, DeductionGroup, Behaviour)
        SELECT CAST(j.[key] AS SMALLINT) + 1,
               UPPER(LTRIM(RTRIM(JSON_VALUE(j.value, '$.DeductionGroup')))),
               UPPER(LTRIM(RTRIM(JSON_VALUE(j.value, '$.Behaviour'))))
        FROM   OPENJSON(@PrioritiesJson) AS j;

        IF NOT EXISTS (SELECT 1 FROM @Lines)
           OR EXISTS (SELECT 1 FROM @Lines WHERE DeductionGroup IS NULL OR DeductionGroup NOT IN ('STATUTORY', 'ABSENCE', 'STANDING', 'ADVANCE', 'LOAN', 'ONE_TIME')
                                              OR Behaviour IS NULL OR Behaviour NOT IN ('ALWAYS', 'TAKEN', 'DEFER'))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Every priority needs a deduction group and what happens to it.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Lines GROUP BY DeductionGroup HAVING COUNT(1) > 1)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Each deduction group can be listed once only.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Lines WHERE DeductionGroup = 'STATUTORY' AND Behaviour <> 'ALWAYS')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Statutory deductions (PIFSS) are always taken - they cannot be deferred.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            INSERT INTO [Payroll].[DeductionPolicies] (CompanyId, PayrollCalendarId, MaxDeductionPercent, WhenExceeded, Notes, IsActive, CreatedBy)
            VALUES (@CompanyId, @PayrollCalendarId, @MaxDeductionPercent, @WhenExceeded, NULLIF(LTRIM(RTRIM(@Notes)), N''), ISNULL(@IsActive, 1), @UserId);
            SET @NewId = SCOPE_IDENTITY();

            INSERT INTO [Payroll].[DeductionPriorities] (DeductionPolicyId, PriorityNo, DeductionGroup, Behaviour)
            SELECT @NewId, PriorityNo, DeductionGroup, Behaviour FROM @Lines;
        COMMIT;

        SET @ResultMessage = N'Deduction rule created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[DeductionPolicies]
               SET CompanyId = @CompanyId, PayrollCalendarId = @PayrollCalendarId, MaxDeductionPercent = @MaxDeductionPercent,
                   WhenExceeded = @WhenExceeded, Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''), IsActive = ISNULL(@IsActive, IsActive),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE DeductionPolicyId = @Id;

            UPDATE [Payroll].[DeductionPriorities]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE DeductionPolicyId = @Id AND Deleted = 0;

            INSERT INTO [Payroll].[DeductionPriorities] (DeductionPolicyId, PriorityNo, DeductionGroup, Behaviour)
            SELECT @Id, PriorityNo, DeductionGroup, Behaviour FROM @Lines;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Deduction rule updated successfully.';
        RETURN;
    END;

    IF @Action IN ('DELETE', 'TOGGLE') AND @IsDefaultRow = 1
    BEGIN
        SELECT @ResultCode = 'IN_USE', @ResultMessage = N'The default rule applies to every company without its own - it can be edited, not removed or deactivated.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[DeductionPriorities] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE DeductionPolicyId = @Id AND Deleted = 0;
            UPDATE [Payroll].[DeductionPolicies]   SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE DeductionPolicyId = @Id AND Deleted = 0;
        COMMIT;
        SET @ResultMessage = N'Deduction rule deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Payroll].[DeductionPolicies]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE DeductionPolicyId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Deduction rule activated.' ELSE N'Deduction rule deactivated.' END
        FROM [Payroll].[DeductionPolicies] WHERE DeductionPolicyId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_ProrationRule_Manage
   ---------------------------------------------------------------------
   One row per payroll calendar - LIST returns every calendar in scope
   (HasRule = 0 shows the defaults until the rule is first saved).
   @Id = PayrollCalendarId. UPDATE saves the calendar's day basis too.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_ProrationRule_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,   -- PayrollCalendarId

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,   -- the calendar's status
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,

    @WorkingDaysBasis         VARCHAR(10)     = NULL,
    @FixedDaysPerMonth        TINYINT         = NULL,
    @ProrateJoiners           BIT             = NULL,
    @ProrateLeavers           BIT             = NULL,
    @ProrateRevisions         BIT             = NULL,
    @ProrateUnpaidLeave       BIT             = NULL,
    @ExcludeRestDays          BIT             = NULL,
    @Notes                    NVARCHAR(500)   = NULL,

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

    IF @Action NOT IN ('LIST', 'GET', 'UPDATE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF @Action = 'LIST'
            SELECT @TotalCount = COUNT(1)
            FROM        [Payroll].[PayrollCalendars] AS pc
            LEFT JOIN   [Core].[Companies]           AS c ON c.CompanyId = pc.CompanyId
            WHERE  pc.Deleted = 0
              AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
              AND [Payroll].[ufn_InCompanyScope](pc.CompanyId, @CompanyId, @CompanyIds) = 1
              AND (@Pattern IS NULL OR pc.CalendarName LIKE @Pattern ESCAPE '\' OR pc.CalendarCode LIKE @Pattern ESCAPE '\'
                   OR c.CompanyName LIKE @Pattern ESCAPE '\');

        SELECT  pc.PayrollCalendarId, pc.CompanyId, c.CompanyName, pc.CalendarCode, pc.CalendarName, pc.PayFrequency,
                pc.WorkingDaysBasis, pc.FixedDaysPerMonth, pc.IsActive,
                r.ProrationRuleId,
                CAST(CASE WHEN r.ProrationRuleId IS NULL THEN 0 ELSE 1 END AS BIT) AS HasRule,
                ISNULL(r.ProrateJoiners, 1)     AS ProrateJoiners,
                ISNULL(r.ProrateLeavers, 1)     AS ProrateLeavers,
                ISNULL(r.ProrateRevisions, 1)   AS ProrateRevisions,
                ISNULL(r.ProrateUnpaidLeave, 1) AS ProrateUnpaidLeave,
                ISNULL(r.ExcludeRestDays, 1)    AS ExcludeRestDays,
                r.Notes
        FROM        [Payroll].[PayrollCalendars] AS pc
        LEFT JOIN   [Core].[Companies]           AS c ON c.CompanyId = pc.CompanyId
        LEFT JOIN   [Payroll].[ProrationRules]   AS r ON r.PayrollCalendarId = pc.PayrollCalendarId AND r.Deleted = 0
        WHERE  pc.Deleted = 0
          AND (@Action = 'LIST' OR pc.PayrollCalendarId = @Id)
          AND (@Action = 'GET' OR (
                   (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
               AND [Payroll].[ufn_InCompanyScope](pc.CompanyId, @CompanyId, @CompanyIds) = 1
               AND (@Pattern IS NULL OR pc.CalendarName LIKE @Pattern ESCAPE '\' OR pc.CalendarCode LIKE @Pattern ESCAPE '\'
                    OR c.CompanyName LIKE @Pattern ESCAPE '\')))
        ORDER BY c.CompanyName, pc.CalendarName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* UPDATE */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] WHERE PayrollCalendarId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That payroll calendar no longer exists. Refresh and try again.';
        RETURN;
    END;

    SET @WorkingDaysBasis = UPPER(LTRIM(RTRIM(ISNULL(@WorkingDaysBasis, 'FIXED'))));
    IF @WorkingDaysBasis NOT IN ('CALENDAR', 'FIXED', 'WORKING')
       OR (@WorkingDaysBasis = 'FIXED' AND (@FixedDaysPerMonth IS NULL OR @FixedDaysPerMonth NOT BETWEEN 1 AND 31))
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the day basis; a fixed basis needs the days per month (1 to 31).';
        RETURN;
    END;

    BEGIN TRAN;
        UPDATE [Payroll].[PayrollCalendars]
           SET WorkingDaysBasis = @WorkingDaysBasis,
               FixedDaysPerMonth = CASE WHEN @WorkingDaysBasis = 'FIXED' THEN @FixedDaysPerMonth ELSE FixedDaysPerMonth END,
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PayrollCalendarId = @Id;

        IF EXISTS (SELECT 1 FROM [Payroll].[ProrationRules] WHERE PayrollCalendarId = @Id AND Deleted = 0)
            UPDATE [Payroll].[ProrationRules]
               SET ProrateJoiners = ISNULL(@ProrateJoiners, ProrateJoiners), ProrateLeavers = ISNULL(@ProrateLeavers, ProrateLeavers),
                   ProrateRevisions = ISNULL(@ProrateRevisions, ProrateRevisions), ProrateUnpaidLeave = ISNULL(@ProrateUnpaidLeave, ProrateUnpaidLeave),
                   ExcludeRestDays = ISNULL(@ExcludeRestDays, ExcludeRestDays), Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE PayrollCalendarId = @Id AND Deleted = 0;
        ELSE
            INSERT INTO [Payroll].[ProrationRules]
                (PayrollCalendarId, ProrateJoiners, ProrateLeavers, ProrateRevisions, ProrateUnpaidLeave, ExcludeRestDays, Notes, CreatedBy)
            VALUES
                (@Id, ISNULL(@ProrateJoiners, 1), ISNULL(@ProrateLeavers, 1), ISNULL(@ProrateRevisions, 1), ISNULL(@ProrateUnpaidLeave, 1),
                 ISNULL(@ExcludeRestDays, 1), NULLIF(LTRIM(RTRIM(@Notes)), N''), @UserId);
    COMMIT;

    SET @NewId = @Id;
    SET @ResultMessage = N'Proration rule saved successfully.';
END;
GO

/* =====================================================================
   Payroll.usp_ApprovalProcess_Manage
   ---------------------------------------------------------------------
   One route per process (CompanyId NULL = the default; a company row
   overrides it for that company). The defaults cannot be deleted or
   deactivated. ROLES / USERS feed the dropdowns (@CompanyId: that
   company's plus the global ones).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_ApprovalProcess_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column (NULL = default)
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,

    @ProcessCode              VARCHAR(20)     = NULL,
    @Level1RoleId             INT             = NULL,
    @Level1DelegateUserId     BIGINT          = NULL,
    @Level2RoleId             INT             = NULL,
    @Level2DelegateUserId     BIGINT          = NULL,
    @Level2AboveAmount        DECIMAL(12,3)   = NULL,
    @AllowSelfApproval        BIT             = NULL,
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

    IF @Action NOT IN ('LIST', 'GET', 'ROLES', 'USERS', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'ROLES'
    BEGIN
        SELECT r.RoleId AS Id, r.RoleName AS [Text]
        FROM   [Security].[Roles] AS r
        WHERE  r.Deleted = 0 AND r.IsActive = 1 AND (r.CompanyId IS NULL OR r.CompanyId = @CompanyId)
        ORDER BY r.RoleName;
        RETURN;
    END;

    IF @Action = 'USERS'
    BEGIN
        SELECT u.UserId AS Id, u.Username AS [Text]
        FROM   [Security].[Users] AS u
        WHERE  u.Deleted = 0 AND u.IsActive = 1 AND (@CompanyId IS NULL OR u.CompanyId IS NULL OR u.CompanyId = @CompanyId)
        ORDER BY u.Username;
        RETURN;
    END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF @Action = 'LIST'
            SELECT @TotalCount = COUNT(1)
            FROM        [Payroll].[ApprovalProcesses] AS a
            LEFT JOIN   [Core].[Companies]            AS c ON c.CompanyId = a.CompanyId
            WHERE  a.Deleted = 0
              AND (@IsActiveFilter IS NULL OR a.IsActive = @IsActiveFilter)
              AND (@ProcessCode IS NULL OR a.ProcessCode = @ProcessCode)
              AND [Payroll].[ufn_InCompanyScope](a.CompanyId, @CompanyId, @CompanyIds) = 1
              AND (@Pattern IS NULL OR a.ProcessCode LIKE @Pattern ESCAPE '\' OR c.CompanyName LIKE @Pattern ESCAPE '\');

        SELECT  a.ApprovalProcessId, a.ProcessCode, a.CompanyId, a.Level1RoleId, a.Level1DelegateUserId, a.Level2RoleId,
                a.Level2DelegateUserId, a.Level2AboveAmount, a.AllowSelfApproval, a.Notes, a.IsActive,
                c.CompanyName,
                r1.RoleName AS Level1RoleName, u1.Username AS Level1DelegateName,
                r2.RoleName AS Level2RoleName, u2.Username AS Level2DelegateName,
                CAST(CASE WHEN a.CompanyId IS NULL THEN 1 ELSE 0 END AS BIT) AS IsDefault
        FROM        [Payroll].[ApprovalProcesses] AS a
        LEFT JOIN   [Core].[Companies]            AS c  ON c.CompanyId = a.CompanyId
        LEFT JOIN   [Security].[Roles]            AS r1 ON r1.RoleId = a.Level1RoleId
        LEFT JOIN   [Security].[Roles]            AS r2 ON r2.RoleId = a.Level2RoleId
        LEFT JOIN   [Security].[Users]            AS u1 ON u1.UserId = a.Level1DelegateUserId
        LEFT JOIN   [Security].[Users]            AS u2 ON u2.UserId = a.Level2DelegateUserId
        WHERE  a.Deleted = 0
          AND (@Action = 'LIST' OR a.ApprovalProcessId = @Id)
          AND (@Action = 'GET' OR (
                   (@IsActiveFilter IS NULL OR a.IsActive = @IsActiveFilter)
               AND (@ProcessCode IS NULL OR a.ProcessCode = @ProcessCode)
               AND [Payroll].[ufn_InCompanyScope](a.CompanyId, @CompanyId, @CompanyIds) = 1
               AND (@Pattern IS NULL OR a.ProcessCode LIKE @Pattern ESCAPE '\' OR c.CompanyName LIKE @Pattern ESCAPE '\')))
        ORDER BY CASE a.ProcessCode WHEN 'PAYROLL_RUN' THEN 1 WHEN 'SALARY_REVISION' THEN 2 WHEN 'LOAN' THEN 3
                                    WHEN 'SALARY_ADVANCE' THEN 4 WHEN 'PAYROLL_ADJUSTMENT' THEN 5 ELSE 6 END,
                 CASE WHEN a.CompanyId IS NULL THEN 0 ELSE 1 END, c.CompanyName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[ApprovalProcesses] WHERE ApprovalProcessId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    DECLARE @IsDefaultRow BIT =
        CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[ApprovalProcesses] WHERE ApprovalProcessId = @Id AND CompanyId IS NULL) THEN 1 ELSE 0 END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        /* process and company of an existing route are fixed (a different scope = a new route) */
        IF @Action = 'UPDATE'
            SELECT @ProcessCode = ProcessCode, @CompanyId = CompanyId, @IsActive = CASE WHEN CompanyId IS NULL THEN 1 ELSE @IsActive END
            FROM [Payroll].[ApprovalProcesses] WHERE ApprovalProcessId = @Id;
        SET @ProcessCode = UPPER(LTRIM(RTRIM(@ProcessCode)));

        IF @ProcessCode IS NULL OR @ProcessCode NOT IN ('PAYROLL_RUN', 'SALARY_REVISION', 'LOAN', 'SALARY_ADVANCE', 'PAYROLL_ADJUSTMENT', 'FINAL_SETTLEMENT')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the process.';
            RETURN;
        END;
        IF @Action = 'INSERT' AND @CompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the company the route is for (the default already exists).';
            RETURN;
        END;
        IF @Level1RoleId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the level 1 approver role.';
            RETURN;
        END;
        IF @Level2RoleId IS NULL AND (@Level2AboveAmount IS NOT NULL OR @Level2DelegateUserId IS NOT NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the level 2 approver role, or clear the level 2 amount and delegate.';
            RETURN;
        END;
        IF @Level2RoleId = @Level1RoleId
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Level 2 must be a different role from level 1.';
            RETURN;
        END;
        IF @Level2AboveAmount IS NOT NULL AND @Level2AboveAmount < 0
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter an amount of 0 or more.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM (VALUES (@Level1RoleId), (@Level2RoleId)) AS x(RoleId)
                   WHERE x.RoleId IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM [Security].[Roles] r
                                     WHERE r.RoleId = x.RoleId AND r.Deleted = 0
                                       AND (r.CompanyId IS NULL OR @CompanyId IS NULL OR r.CompanyId = @CompanyId)))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'An approver role is not available for this company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM (VALUES (@Level1DelegateUserId), (@Level2DelegateUserId)) AS x(UserId)
                   WHERE x.UserId IS NOT NULL
                     AND NOT EXISTS (SELECT 1 FROM [Security].[Users] u WHERE u.UserId = x.UserId AND u.Deleted = 0 AND u.IsActive = 1))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A delegate is not an active user.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[ApprovalProcesses]
                   WHERE Deleted = 0 AND (@Action = 'INSERT' OR ApprovalProcessId <> @Id)
                     AND ProcessCode = @ProcessCode AND ISNULL(CompanyId, 0) = ISNULL(@CompanyId, 0))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'This company already has its own route for this process. Edit that one instead.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[ApprovalProcesses]
            (ProcessCode, CompanyId, Level1RoleId, Level1DelegateUserId, Level2RoleId, Level2DelegateUserId, Level2AboveAmount,
             AllowSelfApproval, Notes, IsActive, CreatedBy)
        VALUES
            (@ProcessCode, @CompanyId, @Level1RoleId, @Level1DelegateUserId, @Level2RoleId, @Level2DelegateUserId, @Level2AboveAmount,
             ISNULL(@AllowSelfApproval, 0), NULLIF(LTRIM(RTRIM(@Notes)), N''), ISNULL(@IsActive, 1), @UserId);
        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Approval route created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        UPDATE [Payroll].[ApprovalProcesses]
           SET Level1RoleId = @Level1RoleId, Level1DelegateUserId = @Level1DelegateUserId,
               Level2RoleId = @Level2RoleId, Level2DelegateUserId = @Level2DelegateUserId, Level2AboveAmount = @Level2AboveAmount,
               AllowSelfApproval = ISNULL(@AllowSelfApproval, AllowSelfApproval), Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''),
               IsActive = ISNULL(@IsActive, IsActive), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE ApprovalProcessId = @Id;
        SET @NewId = @Id;
        SET @ResultMessage = N'Approval route updated successfully.';
        RETURN;
    END;

    IF @Action IN ('DELETE', 'TOGGLE') AND @IsDefaultRow = 1
    BEGIN
        SELECT @ResultCode = 'IN_USE', @ResultMessage = N'The default route applies to every company without its own - it can be edited, not removed or deactivated.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Payroll].[ApprovalProcesses] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE ApprovalProcessId = @Id AND Deleted = 0;
        SET @ResultMessage = N'Approval route deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Payroll].[ApprovalProcesses]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE ApprovalProcessId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Approval route activated.' ELSE N'Approval route deactivated.' END
        FROM [Payroll].[ApprovalProcesses] WHERE ApprovalProcessId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_BankFileFormat_Manage
   ---------------------------------------------------------------------
   The salary file layout per bank (BankId NULL = a general format).
   Exactly one default format (used for banks without their own); making
   a format the default clears the old one. The default cannot be
   deleted or deactivated.
   @FieldsJson: [{"FieldName":"IBAN","SourceCode":"IBAN","ConstantValue":null,
                  "Width":30,"PadChar":" ","AlignRight":false}, ...]
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_BankFileFormat_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- not used (formats are global)
    @CompanyIds               NVARCHAR(2000)  = NULL,   -- not used
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,

    @FormatCode               NVARCHAR(30)    = NULL,
    @FormatName               NVARCHAR(150)   = NULL,
    @BankId                   INT             = NULL,
    @FileType                 VARCHAR(10)     = NULL,
    @Delimiter                NVARCHAR(3)     = NULL,
    @HasHeader                BIT             = NULL,
    @HasTrailer               BIT             = NULL,
    @FileNamePattern          NVARCHAR(100)   = NULL,
    @IsDefault                BIT             = NULL,
    @Notes                    NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,
    @FieldsJson               NVARCHAR(MAX)   = NULL,

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

    IF @Action NOT IN ('LIST', 'GET', 'LINES', 'BANKS', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'BANKS'
    BEGIN
        SELECT b.BankId AS Id, b.BankName AS [Text]
        FROM   [Payroll].[Banks] AS b
        WHERE  b.Deleted = 0 AND (b.IsActive = 1 OR b.BankId = @BankId)
        ORDER BY b.BankName;
        RETURN;
    END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF @Action = 'LIST'
            SELECT @TotalCount = COUNT(1)
            FROM        [Payroll].[BankFileFormats] AS f
            LEFT JOIN   [Payroll].[Banks]           AS b ON b.BankId = f.BankId
            WHERE  f.Deleted = 0
              AND (@IsActiveFilter IS NULL OR f.IsActive = @IsActiveFilter)
              AND (@Pattern IS NULL OR f.FormatCode LIKE @Pattern ESCAPE '\' OR f.FormatName LIKE @Pattern ESCAPE '\'
                   OR b.BankName LIKE @Pattern ESCAPE '\');

        SELECT  f.BankFileFormatId, f.FormatCode, f.FormatName, f.BankId, f.FileType, f.Delimiter, f.HasHeader, f.HasTrailer,
                f.FileNamePattern, f.IsDefault, f.Notes, f.IsActive, b.BankName,
                (SELECT COUNT(1) FROM [Payroll].[BankFileFormatFields] x WHERE x.BankFileFormatId = f.BankFileFormatId AND x.Deleted = 0) AS FieldCount
        FROM        [Payroll].[BankFileFormats] AS f
        LEFT JOIN   [Payroll].[Banks]           AS b ON b.BankId = f.BankId
        WHERE  f.Deleted = 0
          AND (@Action = 'LIST' OR f.BankFileFormatId = @Id)
          AND (@Action = 'GET' OR (
                   (@IsActiveFilter IS NULL OR f.IsActive = @IsActiveFilter)
               AND (@Pattern IS NULL OR f.FormatCode LIKE @Pattern ESCAPE '\' OR f.FormatName LIKE @Pattern ESCAPE '\'
                    OR b.BankName LIKE @Pattern ESCAPE '\')))
        ORDER BY f.IsDefault DESC, b.BankName, f.FormatName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action = 'LINES'
    BEGIN
        SELECT x.FieldNo, x.FieldName, x.SourceCode, x.ConstantValue, x.Width, x.PadChar, x.AlignRight
        FROM   [Payroll].[BankFileFormatFields] AS x
        WHERE  x.BankFileFormatId = @Id AND x.Deleted = 0
        ORDER BY x.FieldNo;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] WHERE BankFileFormatId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    DECLARE @WasDefault BIT =
        CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] WHERE BankFileFormatId = @Id AND IsDefault = 1) THEN 1 ELSE 0 END;

    DECLARE @Fields TABLE (FieldNo SMALLINT, FieldName NVARCHAR(50), SourceCode VARCHAR(20), ConstantValue NVARCHAR(100),
                           Width SMALLINT, PadChar NCHAR(1), AlignRight BIT);

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @FormatCode = UPPER(LTRIM(RTRIM(@FormatCode))), @FormatName = LTRIM(RTRIM(@FormatName)),
               @FileType = UPPER(LTRIM(RTRIM(ISNULL(@FileType, 'CSV')))),
               @IsDefault = CASE WHEN @WasDefault = 1 THEN 1 ELSE ISNULL(@IsDefault, 0) END;   -- the default moves by making another one the default
        IF @IsDefault = 1 SET @IsActive = 1;
        IF @FileType = 'FIXED' SET @Delimiter = NULL;

        IF NULLIF(@FormatCode, N'') IS NULL OR NULLIF(@FormatName, N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Code and name are required.';
            RETURN;
        END;
        IF @FileType NOT IN ('CSV', 'TXT', 'FIXED') OR (@FileType <> 'FIXED' AND (@Delimiter IS NULL OR @Delimiter = N''))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose the file type; a CSV or text file needs a delimiter.';
            RETURN;
        END;
        IF @BankId IS NOT NULL AND NOT EXISTS (SELECT 1 FROM [Payroll].[Banks] WHERE BankId = @BankId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select a valid bank.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats]
                   WHERE Deleted = 0 AND FormatCode = @FormatCode AND (@Action = 'INSERT' OR BankFileFormatId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
        IF @BankId IS NOT NULL AND ISNULL(@IsActive, 1) = 1
           AND EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats]
                       WHERE Deleted = 0 AND IsActive = 1 AND BankId = @BankId AND (@Action = 'INSERT' OR BankFileFormatId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'This bank already has an active format. Deactivate it first, or edit it.';
            RETURN;
        END;

        IF @FieldsJson IS NULL OR ISJSON(@FieldsJson) = 0
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Add the fields of the file.';
            RETURN;
        END;
        INSERT INTO @Fields (FieldNo, FieldName, SourceCode, ConstantValue, Width, PadChar, AlignRight)
        SELECT CAST(j.[key] AS SMALLINT) + 1,
               NULLIF(LTRIM(RTRIM(JSON_VALUE(j.value, '$.FieldName'))), N''),
               UPPER(LTRIM(RTRIM(JSON_VALUE(j.value, '$.SourceCode')))),
               NULLIF(JSON_VALUE(j.value, '$.ConstantValue'), N''),
               TRY_CAST(JSON_VALUE(j.value, '$.Width') AS SMALLINT),
               NULLIF(JSON_VALUE(j.value, '$.PadChar'), N''),
               ISNULL(TRY_CAST(JSON_VALUE(j.value, '$.AlignRight') AS BIT), 0)
        FROM   OPENJSON(@FieldsJson) AS j;

        IF NOT EXISTS (SELECT 1 FROM @Fields)
           OR EXISTS (SELECT 1 FROM @Fields
                      WHERE FieldName IS NULL OR LEN(FieldName) > 50 OR SourceCode IS NULL
                         OR SourceCode NOT IN ('EMPLOYER_CODE', 'PAM_FILE_NO', 'EMPLOYEE_CODE', 'CIVIL_ID', 'EMPLOYEE_NAME', 'BANK_WPS_CODE',
                                               'BANK_SWIFT', 'IBAN', 'ACCOUNT_NO', 'NET_AMOUNT', 'BASIC_AMOUNT', 'ALLOWANCES', 'DEDUCTIONS',
                                               'PERIOD_YYYYMM', 'PAY_DATE', 'DEBIT_IBAN', 'CONSTANT')
                         OR (SourceCode = 'CONSTANT' AND ConstantValue IS NULL)
                         OR (Width IS NOT NULL AND Width NOT BETWEEN 1 AND 500))
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Every field needs a name and a source (a fixed value needs the value); widths are 1 to 500.';
            RETURN;
        END;
        IF @FileType = 'FIXED' AND EXISTS (SELECT 1 FROM @Fields WHERE Width IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A fixed-width file needs the width of every field.';
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM @Fields WHERE SourceCode IN ('IBAN', 'ACCOUNT_NO'))
           OR NOT EXISTS (SELECT 1 FROM @Fields WHERE SourceCode = 'NET_AMOUNT')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A salary file needs at least the employee''s IBAN (or account number) and the net amount.';
            RETURN;
        END;
    END;

    IF @Action = 'INSERT'
    BEGIN
        BEGIN TRAN;
            IF @IsDefault = 1
                UPDATE [Payroll].[BankFileFormats] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE IsDefault = 1 AND Deleted = 0;

            INSERT INTO [Payroll].[BankFileFormats]
                (FormatCode, FormatName, BankId, FileType, Delimiter, HasHeader, HasTrailer, FileNamePattern, IsDefault, Notes, IsActive, CreatedBy)
            VALUES
                (@FormatCode, @FormatName, @BankId, @FileType, @Delimiter, ISNULL(@HasHeader, 1), ISNULL(@HasTrailer, 0),
                 NULLIF(LTRIM(RTRIM(@FileNamePattern)), N''), @IsDefault, NULLIF(LTRIM(RTRIM(@Notes)), N''), ISNULL(@IsActive, 1), @UserId);
            SET @NewId = SCOPE_IDENTITY();

            INSERT INTO [Payroll].[BankFileFormatFields] (BankFileFormatId, FieldNo, FieldName, SourceCode, ConstantValue, Width, PadChar, AlignRight)
            SELECT @NewId, FieldNo, FieldName, SourceCode, CASE WHEN SourceCode = 'CONSTANT' THEN ConstantValue END, Width, PadChar, AlignRight
            FROM @Fields;
        COMMIT;

        SET @ResultMessage = N'Bank file format created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        BEGIN TRAN;
            IF @IsDefault = 1
                UPDATE [Payroll].[BankFileFormats] SET IsDefault = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
                 WHERE IsDefault = 1 AND Deleted = 0 AND BankFileFormatId <> @Id;

            UPDATE [Payroll].[BankFileFormats]
               SET FormatCode = @FormatCode, FormatName = @FormatName, BankId = @BankId, FileType = @FileType, Delimiter = @Delimiter,
                   HasHeader = ISNULL(@HasHeader, HasHeader), HasTrailer = ISNULL(@HasTrailer, HasTrailer),
                   FileNamePattern = NULLIF(LTRIM(RTRIM(@FileNamePattern)), N''), IsDefault = @IsDefault,
                   Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''), IsActive = ISNULL(@IsActive, IsActive),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE BankFileFormatId = @Id;

            UPDATE [Payroll].[BankFileFormatFields]
               SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE BankFileFormatId = @Id AND Deleted = 0;

            INSERT INTO [Payroll].[BankFileFormatFields] (BankFileFormatId, FieldNo, FieldName, SourceCode, ConstantValue, Width, PadChar, AlignRight)
            SELECT @Id, FieldNo, FieldName, SourceCode, CASE WHEN SourceCode = 'CONSTANT' THEN ConstantValue END, Width, PadChar, AlignRight
            FROM @Fields;
        COMMIT;

        SET @NewId = @Id;
        SET @ResultMessage = N'Bank file format updated successfully.';
        RETURN;
    END;

    IF @Action IN ('DELETE', 'TOGGLE') AND @WasDefault = 1
    BEGIN
        SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This is the default format. Make another format the default first.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[BankFileFormatFields] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE BankFileFormatId = @Id AND Deleted = 0;
            UPDATE [Payroll].[BankFileFormats]      SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE BankFileFormatId = @Id AND Deleted = 0;
        COMMIT;
        SET @ResultMessage = N'Bank file format deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] AS me
                   INNER JOIN [Payroll].[BankFileFormats] AS o
                           ON o.BankFileFormatId <> me.BankFileFormatId AND o.Deleted = 0 AND o.IsActive = 1 AND o.BankId = me.BankId
                   WHERE me.BankFileFormatId = @Id AND me.IsActive = 0)
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'This bank already has another active format, so this one cannot be re-activated.';
            RETURN;
        END;

        UPDATE [Payroll].[BankFileFormats]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE BankFileFormatId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Format activated.' ELSE N'Format deactivated.' END
        FROM [Payroll].[BankFileFormats] WHERE BankFileFormatId = @Id;
        RETURN;
    END;
END;
GO

/* =====================================================================
   Payroll.usp_GLMapping_Manage
   ---------------------------------------------------------------------
   Debit / credit GL accounts of a pay item type, for one cost center or
   any (CostCenterId NULL). The company is the pay item type's company.
   COMPONENTS feeds the dropdown (@CompanyId).
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_GLMapping_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @ComponentType            VARCHAR(10)     = NULL,   -- LIST filter: EARNING / DEDUCTION

    @PayComponentId           INT             = NULL,
    @CostCenterId             INT             = NULL,
    @DebitAccountCode         NVARCHAR(50)    = NULL,
    @DebitAccountName         NVARCHAR(150)   = NULL,
    @CreditAccountCode        NVARCHAR(50)    = NULL,
    @CreditAccountName        NVARCHAR(150)   = NULL,
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

    IF @Action NOT IN ('LIST', 'GET', 'COMPONENTS', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action = 'COMPONENTS'
    BEGIN
        SELECT pc.PayComponentId AS Id, pc.ComponentName + N' (' + pc.ComponentCode + N')' AS [Text]
        FROM   [Payroll].[PayComponents] AS pc
        WHERE  pc.CompanyId = @CompanyId AND pc.Deleted = 0 AND (pc.IsActive = 1 OR pc.PayComponentId = @PayComponentId)
        ORDER BY pc.ComponentType, pc.DisplayOrder, pc.ComponentName;
        RETURN;
    END;

    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF @Action = 'LIST'
            SELECT @TotalCount = COUNT(1)
            FROM        [Payroll].[GLMappings]    AS g
            INNER JOIN  [Payroll].[PayComponents] AS pc ON pc.PayComponentId = g.PayComponentId
            LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = g.CostCenterId
            WHERE  g.Deleted = 0
              AND (@IsActiveFilter IS NULL OR g.IsActive = @IsActiveFilter)
              AND (@ComponentType IS NULL OR pc.ComponentType = @ComponentType)
              AND [Payroll].[ufn_InCompanyScope](pc.CompanyId, @CompanyId, @CompanyIds) = 1
              AND (@Pattern IS NULL OR pc.ComponentName LIKE @Pattern ESCAPE '\' OR pc.ComponentCode LIKE @Pattern ESCAPE '\'
                   OR g.DebitAccountCode LIKE @Pattern ESCAPE '\' OR g.CreditAccountCode LIKE @Pattern ESCAPE '\'
                   OR g.DebitAccountName LIKE @Pattern ESCAPE '\' OR g.CreditAccountName LIKE @Pattern ESCAPE '\'
                   OR cc.CostCenterName LIKE @Pattern ESCAPE '\');

        SELECT  g.GLMappingId, g.PayComponentId, g.CostCenterId, g.DebitAccountCode, g.DebitAccountName, g.CreditAccountCode,
                g.CreditAccountName, g.Notes, g.IsActive,
                pc.CompanyId, c.CompanyName, pc.ComponentCode, pc.ComponentName, pc.ComponentType, cc.CostCenterName
        FROM        [Payroll].[GLMappings]    AS g
        INNER JOIN  [Payroll].[PayComponents] AS pc ON pc.PayComponentId = g.PayComponentId
        LEFT JOIN   [Core].[Companies]        AS c  ON c.CompanyId = pc.CompanyId
        LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = g.CostCenterId
        WHERE  g.Deleted = 0
          AND (@Action = 'LIST' OR g.GLMappingId = @Id)
          AND (@Action = 'GET' OR (
                   (@IsActiveFilter IS NULL OR g.IsActive = @IsActiveFilter)
               AND (@ComponentType IS NULL OR pc.ComponentType = @ComponentType)
               AND [Payroll].[ufn_InCompanyScope](pc.CompanyId, @CompanyId, @CompanyIds) = 1
               AND (@Pattern IS NULL OR pc.ComponentName LIKE @Pattern ESCAPE '\' OR pc.ComponentCode LIKE @Pattern ESCAPE '\'
                    OR g.DebitAccountCode LIKE @Pattern ESCAPE '\' OR g.CreditAccountCode LIKE @Pattern ESCAPE '\'
                    OR g.DebitAccountName LIKE @Pattern ESCAPE '\' OR g.CreditAccountName LIKE @Pattern ESCAPE '\'
                    OR cc.CostCenterName LIKE @Pattern ESCAPE '\')))
        ORDER BY c.CompanyName, pc.ComponentType, pc.DisplayOrder, pc.ComponentName,
                 CASE WHEN g.CostCenterId IS NULL THEN 0 ELSE 1 END, cc.CostCenterName
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[GLMappings] WHERE GLMappingId = @Id AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        SELECT @DebitAccountCode = NULLIF(LTRIM(RTRIM(@DebitAccountCode)), N''), @CreditAccountCode = NULLIF(LTRIM(RTRIM(@CreditAccountCode)), N'');

        DECLARE @ComponentCompanyId INT =
            (SELECT CompanyId FROM [Payroll].[PayComponents] WHERE PayComponentId = @PayComponentId AND Deleted = 0);

        IF @ComponentCompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the pay item type.';
            RETURN;
        END;
        IF @DebitAccountCode IS NULL OR @CreditAccountCode IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the debit and the credit account.';
            RETURN;
        END;
        IF @DebitAccountCode = @CreditAccountCode
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The debit and credit accounts must be different.';
            RETURN;
        END;
        IF @CostCenterId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @CostCenterId AND CompanyId = @ComponentCompanyId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The cost center does not belong to the pay item type''s company.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[GLMappings]
                   WHERE Deleted = 0 AND (@Action = 'INSERT' OR GLMappingId <> @Id)
                     AND PayComponentId = @PayComponentId AND ISNULL(CostCenterId, 0) = ISNULL(@CostCenterId, 0))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'This pay item type is already mapped for this cost center. Edit that mapping instead.';
            RETURN;
        END;
        SET @CompanyId = @ComponentCompanyId;
    END;

    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[GLMappings]
            (PayComponentId, CostCenterId, DebitAccountCode, DebitAccountName, CreditAccountCode, CreditAccountName, Notes, IsActive, CreatedBy)
        VALUES
            (@PayComponentId, @CostCenterId, @DebitAccountCode, NULLIF(LTRIM(RTRIM(@DebitAccountName)), N''), @CreditAccountCode,
             NULLIF(LTRIM(RTRIM(@CreditAccountName)), N''), NULLIF(LTRIM(RTRIM(@Notes)), N''), ISNULL(@IsActive, 1), @UserId);
        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'GL mapping created successfully.';
        RETURN;
    END;

    IF @Action = 'UPDATE'
    BEGIN
        UPDATE [Payroll].[GLMappings]
           SET PayComponentId = @PayComponentId, CostCenterId = @CostCenterId,
               DebitAccountCode = @DebitAccountCode, DebitAccountName = NULLIF(LTRIM(RTRIM(@DebitAccountName)), N''),
               CreditAccountCode = @CreditAccountCode, CreditAccountName = NULLIF(LTRIM(RTRIM(@CreditAccountName)), N''),
               Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''), IsActive = ISNULL(@IsActive, IsActive),
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE GLMappingId = @Id;
        SET @NewId = @Id;
        SET @ResultMessage = N'GL mapping updated successfully.';
        RETURN;
    END;

    IF @Action = 'DELETE'
    BEGIN
        UPDATE [Payroll].[GLMappings] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE GLMappingId = @Id AND Deleted = 0;
        SET @ResultMessage = N'GL mapping deleted successfully.';
        RETURN;
    END;

    IF @Action = 'TOGGLE'
    BEGIN
        UPDATE [Payroll].[GLMappings]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE GLMappingId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'GL mapping activated.' ELSE N'GL mapping deactivated.' END
        FROM [Payroll].[GLMappings] WHERE GLMappingId = @Id;
        RETURN;
    END;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/48 applied: deduction, proration, approval, bank file format and GL mapping procedures.';
GO
