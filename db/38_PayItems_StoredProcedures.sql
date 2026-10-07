/* =====================================================================
   38_PayItems_StoredProcedures.sql  -  HRMS Payroll: Pay Items
   ---------------------------------------------------------------------
   Run after 37. CREATE OR ALTER everywhere - safe to re-run.

     Payroll.usp_PayItem_Save     the rules of one pay item (internal: used
                                  by SAVE and by the Excel import, inside
                                  the caller's transaction)
     Payroll.usp_PayItem_Manage   LIST / GET / SUMMARY / EMP_SUMMARY / TYPES /
                                  EMPLOYEES / HISTORY / SAVE / APPROVE /
                                  REJECT / END / DELETE
     Payroll.usp_PayItem_Import   validates every row of an Excel file and
                                  saves all of them - or none

   Rules
     Salary      every month from a month; a change is a NEW item from a
                 later month that replaces the current one once approved
                 (HR, then Finance). The current amount applies until then.
     Earning     one time or every month (optionally until a month)
     Deduction   one time, every month, or in instalments
     Loan        total / instalments = monthly instalment; numbered LN-0001
                 (loan) or SA-0001 (salary advance); needs approval
     An item already paid by a payroll keeps its amount: only the comment
     and its last month can change - end it and add a new one instead.
     Nothing is physically deleted.
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH(N'Payroll.EmployeePayItems', N'ApprovalLevel') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 37 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* =====================================================================
   usp_PayItem_Save
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayItem_Save]
    @Id               BIGINT          = NULL,
    @EmployeeId       BIGINT          = NULL,
    @PayComponentId   INT             = NULL,
    @Amount           DECIMAL(12,3)   = NULL,
    @AppliesMode      VARCHAR(10)     = NULL,
    @StartMonth       DATE            = NULL,
    @EndMonth         DATE            = NULL,
    @InstalmentCount  SMALLINT        = NULL,
    @TotalAmount      DECIMAL(12,3)   = NULL,
    @Comment          NVARCHAR(500)   = NULL,
    @CompanyScope     INT             = NULL,
    @CompanyIds       NVARCHAR(2000)  = NULL,
    @UserId           BIGINT          = NULL,
    @NewId            BIGINT          = NULL OUTPUT,
    @ResultCode       VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage    NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0);
    SET @Id          = NULLIF(@Id, 0);
    SET @Comment     = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @AppliesMode = UPPER(NULLIF(LTRIM(RTRIM(@AppliesMode)), ''));
    IF @StartMonth IS NOT NULL SET @StartMonth = DATEFROMPARTS(YEAR(@StartMonth), MONTH(@StartMonth), 1);
    IF @EndMonth   IS NOT NULL SET @EndMonth   = DATEFROMPARTS(YEAR(@EndMonth), MONTH(@EndMonth), 1);
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    /* ---- employee and item type ---- */
    DECLARE @CompanyId INT;
    SELECT @CompanyId = e.CompanyId
    FROM   [Employee].[Employees] AS e
    WHERE  e.EmployeeId = @EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
      AND  (@CompanyScope IS NULL OR e.CompanyId = @CompanyScope)
      AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);
    IF @CompanyId IS NULL
    BEGIN
        SELECT @ResultCode = 'EMPLOYEE_REQUIRED', @ResultMessage = N'Select an employee.';
        RETURN;
    END;

    DECLARE @Class VARCHAR(10), @SysCode VARCHAR(30), @CompActive BIT;
    SELECT @Class = c.ItemClass, @SysCode = c.SystemCode, @CompActive = c.IsActive
    FROM   [Payroll].[PayComponents] AS c
    WHERE  c.PayComponentId = @PayComponentId AND c.CompanyId = @CompanyId AND c.Deleted = 0
      AND  c.ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN');
    IF @Class IS NULL
    BEGIN
        SELECT @ResultCode = 'TYPE_REQUIRED', @ResultMessage = N'Select an item type of the employee''s company.';
        RETURN;
    END;
    IF @Comment IS NULL
    BEGIN
        SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter a comment - why it is paid or deducted.';
        RETURN;
    END;
    IF @StartMonth IS NULL
    BEGIN
        SELECT @ResultCode = 'MONTH_REQUIRED', @ResultMessage = N'Select the month it applies from.';
        RETURN;
    END;

    /* ---- what each class allows ---- */
    IF @Class = 'SALARY'
        SELECT @AppliesMode = 'MONTHLY', @EndMonth = NULL, @InstalmentCount = NULL, @TotalAmount = NULL;
    ELSE IF @Class = 'LOAN'
    BEGIN
        IF @TotalAmount IS NULL OR @TotalAmount <= 0
        BEGIN
            SELECT @ResultCode = 'TOTAL_REQUIRED', @ResultMessage = N'Enter the total amount of the loan or advance.';
            RETURN;
        END;
        IF @InstalmentCount IS NULL OR @InstalmentCount < 1 OR @InstalmentCount > 600
        BEGIN
            SELECT @ResultCode = 'INSTALMENTS_REQUIRED', @ResultMessage = N'Enter the number of instalments (1 to 600).';
            RETURN;
        END;
        SELECT @AppliesMode = 'INSTALMENT', @EndMonth = NULL, @Amount = ROUND(@TotalAmount / @InstalmentCount, 3);
    END
    ELSE IF @Class = 'EARNING'
    BEGIN
        IF ISNULL(@AppliesMode, '') NOT IN ('ONCE', 'MONTHLY')
        BEGIN
            SELECT @ResultCode = 'APPLIES_INVALID', @ResultMessage = N'An earning applies one time or every month.';
            RETURN;
        END;
        SELECT @InstalmentCount = NULL, @TotalAmount = NULL;
        IF @AppliesMode = 'ONCE' SET @EndMonth = NULL;
    END
    ELSE
    BEGIN
        IF ISNULL(@AppliesMode, '') NOT IN ('ONCE', 'MONTHLY', 'INSTALMENT')
        BEGIN
            SELECT @ResultCode = 'APPLIES_INVALID', @ResultMessage = N'A deduction applies one time, every month or in instalments.';
            RETURN;
        END;
        IF @AppliesMode = 'INSTALMENT'
        BEGIN
            IF @InstalmentCount IS NULL OR @InstalmentCount < 1 OR @InstalmentCount > 600
            BEGIN
                SELECT @ResultCode = 'INSTALMENTS_REQUIRED', @ResultMessage = N'Enter the number of instalments (1 to 600).';
                RETURN;
            END;
            SELECT @EndMonth = NULL, @TotalAmount = @Amount * @InstalmentCount;
        END
        ELSE
        BEGIN
            SELECT @InstalmentCount = NULL, @TotalAmount = NULL;
            IF @AppliesMode = 'ONCE' SET @EndMonth = NULL;
        END;
    END;

    IF @Amount IS NULL OR @Amount <= 0 OR @Amount > 999999.999
    BEGIN
        SELECT @ResultCode = 'AMOUNT_INVALID', @ResultMessage = N'Enter an amount greater than zero.';
        RETURN;
    END;
    IF @EndMonth IS NOT NULL AND @EndMonth < @StartMonth
    BEGIN
        SELECT @ResultCode = 'END_BEFORE_START', @ResultMessage = N'The last month cannot be before the first month.';
        RETURN;
    END;

    /* ---- the item being changed ---- */
    DECLARE @oStatus VARCHAR(10), @oEmp BIGINT, @oComp INT, @oClass VARCHAR(10), @oAmount DECIMAL(12,3), @oMode VARCHAR(10),
            @oStart DATE, @oEnd DATE, @oCount SMALLINT, @oTotal DECIMAL(12,3), @oComment NVARCHAR(500), @oReplaces BIGINT,
            @Used BIT = 0, @LastPaid DATE = NULL;
    IF @Id IS NOT NULL
    BEGIN
        SELECT @oStatus = i.Status, @oEmp = i.EmployeeId, @oComp = i.PayComponentId, @oClass = c.ItemClass, @oAmount = i.Amount,
               @oMode = i.AppliesMode, @oStart = i.StartMonth, @oEnd = i.EndMonth, @oCount = i.InstalmentCount, @oTotal = i.TotalAmount,
               @oComment = i.Comment, @oReplaces = i.ReplacesItemId
        FROM   [Payroll].[EmployeePayItems] AS i
        JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        WHERE  i.EmployeePayItemId = @Id AND i.Deleted = 0 AND i.PayrollRunId IS NULL AND i.CompanyId = @CompanyId;

        IF @oStatus IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This pay item no longer exists.';
            RETURN;
        END;
        IF @oEmp <> @EmployeeId
        BEGIN
            SELECT @ResultCode = 'EMPLOYEE_LOCKED', @ResultMessage = N'The employee of a pay item cannot be changed. Add a new item instead.';
            RETURN;
        END;
        IF @oClass <> @Class
        BEGIN
            SELECT @ResultCode = 'CLASS_LOCKED', @ResultMessage = N'The class of a pay item cannot be changed. Delete it and add a new one.';
            RETURN;
        END;
        IF @oStatus = 'ENDED'
        BEGIN
            SELECT @ResultCode = 'ENDED', @ResultMessage = N'This item has ended and cannot be changed.';
            RETURN;
        END;
        SELECT @LastPaid = MAX(r.RunMonth)
        FROM   [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
        WHERE  l.EmployeePayItemId = @Id AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED');
        IF @LastPaid IS NOT NULL SET @Used = 1;

        /* a salary item keeps its type; its last month is set by approvals and End only */
        IF @Class = 'SALARY' AND @oComp <> @PayComponentId
        BEGIN
            SELECT @ResultCode = 'TYPE_LOCKED', @ResultMessage = N'The item type of a salary item cannot be changed. Delete it and add a new one.';
            RETURN;
        END;
        IF @Class = 'SALARY' SET @EndMonth = @oEnd;
        IF @oComp <> @PayComponentId AND @CompActive = 0
        BEGIN
            SELECT @ResultCode = 'TYPE_INACTIVE', @ResultMessage = N'This item type is inactive. Activate it in Payroll Settings or choose another.';
            RETURN;
        END;
        IF @EndMonth IS NOT NULL AND @LastPaid IS NOT NULL AND @EndMonth < @LastPaid
        BEGIN
            SELECT @ResultCode = 'END_BEFORE_PAID', @ResultMessage = N'The last month cannot be before a month already paid.';
            RETURN;
        END;
    END;
    ELSE IF @CompActive = 0
    BEGIN
        SELECT @ResultCode = 'TYPE_INACTIVE', @ResultMessage = N'This item type is inactive. Activate it in Payroll Settings or choose another.';
        RETURN;
    END;

    DECLARE @MoneyChanged BIT = CASE WHEN @Id IS NOT NULL AND (
                  @oAmount <> @Amount OR @oMode <> @AppliesMode OR @oStart <> @StartMonth OR @oComp <> @PayComponentId
               OR ISNULL(@oCount, -1) <> ISNULL(@InstalmentCount, -1) OR ISNULL(@oTotal, -1) <> ISNULL(@TotalAmount, -1)) THEN 1 ELSE 0 END;
    DECLARE @EndChanged BIT = CASE WHEN @Id IS NOT NULL AND ISNULL(@oEnd, '19000101') <> ISNULL(@EndMonth, '19000101') THEN 1 ELSE 0 END;

    /* a one-time item cannot go into a month whose payroll is closed */
    IF @AppliesMode = 'ONCE' AND (@Id IS NULL OR @oStart <> @StartMonth OR @oMode <> @AppliesMode)
       AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r WHERE r.CompanyId = @CompanyId AND r.Deleted = 0
                   AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR' AND r.RunMonth = @StartMonth)
    BEGIN
        SELECT @ResultCode = 'MONTH_CLOSED',
               @ResultMessage = N'The payroll of that month is already closed. Choose a later month, or add the line to an off-cycle payroll.';
        RETURN;
    END;

    /* ================= changing an existing item ================= */
    IF @Id IS NOT NULL
    BEGIN
        /* comment / last month only */
        IF @MoneyChanged = 0
        BEGIN
            IF @EndChanged = 1 AND @Class = 'SALARY'
            BEGIN
                SELECT @ResultCode = 'USE_END', @ResultMessage = N'Use End to stop a salary item.';
                RETURN;
            END;
            UPDATE [Payroll].[EmployeePayItems]
               SET Comment = @Comment, EndMonth = @EndMonth, ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  EmployeePayItemId = @Id;
            IF ISNULL(@oComment, N'') <> @Comment OR @EndChanged = 1
                INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
                VALUES (@Id, @EmployeeId, 'CHANGED', @oAmount, @Amount, @Comment, @UserId);
            SET @ResultMessage = N'Pay item saved.';
            RETURN;
        END;

        /* an approved salary item: the change becomes a new item from a later month */
        IF @Class = 'SALARY' AND @oStatus = 'ACTIVE'
        BEGIN
            IF @oEnd IS NOT NULL
            BEGIN
                SELECT @ResultCode = 'REPLACED',
                       @ResultMessage = N'This salary amount has an end month (it was replaced or ended). Change the latest amount instead.';
                RETURN;
            END;
            IF @StartMonth <= @oStart
            BEGIN
                SELECT @ResultCode = 'REVISE_START',
                       @ResultMessage = N'A salary change must apply from a later month than the current amount.';
                RETURN;
            END;
            IF EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] WHERE EmployeeId = @EmployeeId AND PayComponentId = @PayComponentId
                       AND Deleted = 0 AND PayrollRunId IS NULL AND Status = 'PENDING')
            BEGIN
                SELECT @ResultCode = 'PENDING_EXISTS', @ResultMessage = N'This employee already has a change of this item waiting for approval.';
                RETURN;
            END;
            INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment,
                                                       Status, ApprovalLevel, SubmittedBy, SubmittedDate, ReplacesItemId, CreatedBy)
            VALUES (@CompanyId, @EmployeeId, @PayComponentId, @Amount, 'MONTHLY', @StartMonth, @Comment,
                    'PENDING', 0, @UserId, @Now, @Id, @UserId);
            SET @NewId = SCOPE_IDENTITY();
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
            VALUES (@NewId, @EmployeeId, 'REVISED', @oAmount, @Amount, @Comment, @UserId);
            SET @ResultMessage = N'Salary change sent for approval. The current amount is paid until the change is approved and starts.';
            RETURN;
        END;

        IF @Used = 1
        BEGIN
            SELECT @ResultCode = 'ALREADY_PAID',
                   @ResultMessage = N'This item has already been paid by a payroll. Only its comment and last month can be changed - end it and add a new item instead.';
            RETURN;
        END;

        /* an approved loan keeps its terms: end it (or delete it if unpaid) and add a new one */
        IF @Class = 'LOAN' AND @oStatus = 'ACTIVE'
        BEGIN
            SELECT @ResultCode = 'LOAN_APPROVED',
                   @ResultMessage = N'An approved loan cannot be changed. End it - or delete it if no payroll has deducted it yet - and add a new one.';
            RETURN;
        END;
        DECLARE @Reapprove BIT = 0;

        IF @Class = 'SALARY' AND @oReplaces IS NOT NULL
           AND @StartMonth <= (SELECT StartMonth FROM [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @oReplaces)
        BEGIN
            SELECT @ResultCode = 'REVISE_START', @ResultMessage = N'A salary change must apply from a later month than the current amount.';
            RETURN;
        END;

        UPDATE [Payroll].[EmployeePayItems]
           SET PayComponentId = @PayComponentId, Amount = @Amount, AppliesMode = @AppliesMode, StartMonth = @StartMonth, EndMonth = @EndMonth,
               InstalmentCount = @InstalmentCount, TotalAmount = @TotalAmount, Comment = @Comment,
               Status        = CASE WHEN @Reapprove = 1 OR Status = 'PENDING' THEN 'PENDING' ELSE Status END,
               ApprovalLevel = CASE WHEN @Reapprove = 1 OR Status = 'PENDING' THEN 0 ELSE ApprovalLevel END,
               SubmittedBy   = CASE WHEN @Reapprove = 1 OR Status = 'PENDING' THEN @UserId ELSE SubmittedBy END,
               SubmittedDate = CASE WHEN @Reapprove = 1 OR Status = 'PENDING' THEN @Now ELSE SubmittedDate END,
               ModifiedBy = @UserId, ModifiedDate = @Now
        WHERE  EmployeePayItemId = @Id;

        INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        VALUES (@Id, @EmployeeId, 'CHANGED', @oAmount, @Amount, @Comment, @UserId);

        SET @ResultMessage = CASE WHEN @oStatus = 'PENDING' THEN N'Saved. It is paid once it is approved (HR, then Finance).'
                                  ELSE N'Pay item saved.' END;
        GOTO LiveRunHint;
    END;

    /* ================= a new item ================= */
    DECLARE @Replaces BIGINT = NULL;
    IF @Class = 'SALARY'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] WHERE EmployeeId = @EmployeeId AND PayComponentId = @PayComponentId
                   AND Deleted = 0 AND PayrollRunId IS NULL AND Status = 'PENDING')
        BEGIN
            SELECT @ResultCode = 'PENDING_EXISTS', @ResultMessage = N'This employee already has a change of this item waiting for approval.';
            RETURN;
        END;
        SELECT TOP 1 @Replaces = EmployeePayItemId, @oStart = StartMonth
        FROM   [Payroll].[EmployeePayItems]
        WHERE  EmployeeId = @EmployeeId AND PayComponentId = @PayComponentId AND Deleted = 0 AND PayrollRunId IS NULL
          AND  Status = 'ACTIVE' AND AppliesMode = 'MONTHLY' AND (EndMonth IS NULL OR EndMonth >= @StartMonth)
        ORDER BY StartMonth DESC, EmployeePayItemId DESC;
        IF @Replaces IS NOT NULL AND @StartMonth <= @oStart
        BEGIN
            SELECT @ResultCode = 'REVISE_START', @ResultMessage = N'A salary change must apply from a later month than the current amount.';
            RETURN;
        END;
    END;

    DECLARE @Ref NVARCHAR(50) = NULL;
    IF @Class = 'LOAN'
    BEGIN
        DECLARE @Prefix NVARCHAR(3) = CASE WHEN @SysCode = 'SALARY_ADVANCE' THEN N'SA-' ELSE N'LN-' END, @Last INT;
        SELECT @Last = MAX(TRY_CAST(SUBSTRING(SourceRef, 4, 12) AS INT))
        FROM   [Payroll].[EmployeePayItems] WITH (UPDLOCK, HOLDLOCK)
        WHERE  CompanyId = @CompanyId AND SourceRef LIKE @Prefix + N'%';
        SET @Last = ISNULL(@Last, 0) + 1;
        SET @Ref = @Prefix + CASE WHEN @Last < 10000 THEN RIGHT(N'000' + CAST(@Last AS NVARCHAR(12)), 4) ELSE CAST(@Last AS NVARCHAR(12)) END;
    END;

    DECLARE @NeedsApproval BIT = CASE WHEN @Class IN ('SALARY', 'LOAN') THEN 1 ELSE 0 END;

    INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, EndMonth, InstalmentCount,
                                               TotalAmount, Comment, Status, ApprovalLevel, SubmittedBy, SubmittedDate, ReplacesItemId, SourceRef, CreatedBy)
    VALUES (@CompanyId, @EmployeeId, @PayComponentId, @Amount, @AppliesMode, @StartMonth, @EndMonth, @InstalmentCount,
            @TotalAmount, @Comment,
            CASE WHEN @NeedsApproval = 1 THEN 'PENDING' ELSE 'ACTIVE' END,
            CASE WHEN @NeedsApproval = 1 THEN 0 ELSE 2 END,
            CASE WHEN @NeedsApproval = 1 THEN @UserId END,
            CASE WHEN @NeedsApproval = 1 THEN @Now END,
            @Replaces, @Ref, @UserId);
    SET @NewId = SCOPE_IDENTITY();

    INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
    VALUES (@NewId, @EmployeeId, CASE WHEN @Replaces IS NULL THEN 'CREATED' ELSE 'REVISED' END,
            CASE WHEN @Replaces IS NOT NULL THEN (SELECT Amount FROM [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @Replaces) END,
            @Amount, @Comment, @UserId);

    SET @ResultMessage = CASE WHEN @NeedsApproval = 1 THEN N'Saved. It is paid once it is approved (HR, then Finance).' ELSE N'Pay item saved.' END;

LiveRunHint:
    /* an active item for a month whose regular payroll is already calculated: it needs a recalculation */
    IF @ResultMessage = N'Pay item saved.'
       AND EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] r
                   WHERE r.CompanyId = @CompanyId AND r.Deleted = 0 AND r.RunType = 'REGULAR'
                     AND r.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL')
                     AND r.RunMonth >= @StartMonth AND (@AppliesMode <> 'ONCE' OR r.RunMonth = @StartMonth)
                     AND (@EndMonth IS NULL OR r.RunMonth <= @EndMonth))
        SET @ResultMessage = N'Pay item saved. The payroll of that month is already calculated - recalculate it (Payroll Register) to include this item.';
END;
GO

/* =====================================================================
   usp_PayItem_Manage
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayItem_Manage]
    @Action             VARCHAR(20),
    @Id                 BIGINT          = NULL,

    /* scope and filters */
    @CompanyId          INT             = NULL,     -- the user's own company (company users)
    @CompanyIds         NVARCHAR(2000)  = NULL,     -- the company filter of the top bar
    @EmployeeId         BIGINT          = NULL,
    @ItemClass          VARCHAR(10)     = NULL,
    @StatusFilter       VARCHAR(10)     = NULL,     -- OPEN (active + pending, default), ACTIVE, PENDING, ENDED, ALL
    @Search             NVARCHAR(200)   = NULL,
    @Month              DATE            = NULL,
    @PageNumber         INT             = 1,
    @PageSize           INT             = 25,

    /* save */
    @PayComponentId     INT             = NULL,
    @Amount             DECIMAL(12,3)   = NULL,
    @AppliesMode        VARCHAR(10)     = NULL,
    @StartMonth         DATE            = NULL,
    @EndMonth           DATE            = NULL,
    @InstalmentCount    SMALLINT        = NULL,
    @TotalAmount        DECIMAL(12,3)   = NULL,
    @Comment            NVARCHAR(500)   = NULL,

    @AllowSelfApproval  BIT             = 0,
    @ExpectedLevel      TINYINT         = NULL,     -- APPROVE / REJECT: the level the user saw (stops a double approval)
    @UserId             BIGINT          = NULL,

    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;
    SET @Search     = NULLIF(LTRIM(RTRIM(@Search)), N'');
    SET @CompanyIds = NULLIF(LTRIM(RTRIM(@CompanyIds)), N'');
    SET @ItemClass  = NULLIF(UPPER(LTRIM(RTRIM(@ItemClass))), '');
    SET @StatusFilter = ISNULL(NULLIF(UPPER(LTRIM(RTRIM(@StatusFilter))), ''), 'OPEN');
    SET @PageNumber = CASE WHEN @PageNumber IS NULL OR @PageNumber < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN @PageSize IS NULL OR @PageSize < 1 THEN 25 WHEN @PageSize > 10000 THEN 10000 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(210) = CASE WHEN @Search IS NULL THEN NULL
        ELSE N'%' + REPLACE(REPLACE(REPLACE(@Search, N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @ThisMonth DATE = DATEFROMPARTS(YEAR(SYSDATETIME()), MONTH(SYSDATETIME()), 1);
    SET @Month = ISNULL(DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1), @ThisMonth);

    IF @Action NOT IN ('LIST', 'GET', 'SUMMARY', 'EMP_SUMMARY', 'TYPES', 'EMPLOYEES', 'HISTORY', 'SAVE', 'APPROVE', 'REJECT', 'END', 'DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* what has been paid of each item (live and closed payrolls) */
    DECLARE @Paid TABLE (EmployeePayItemId BIGINT PRIMARY KEY, PaidCount INT, PaidAmount DECIMAL(14,3), LastPaidMonth DATE);
    IF @Action IN ('LIST', 'GET', 'SUMMARY', 'EMP_SUMMARY')
        INSERT INTO @Paid
        SELECT l.EmployeePayItemId, COUNT(1), SUM(ABS(l.Amount)), MAX(r.RunMonth)
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   [Payroll].[PayrollRuns]     AS r ON r.PayrollRunId = l.PayrollRunId
        JOIN   [Payroll].[EmployeePayItems] AS i ON i.EmployeePayItemId = l.EmployeePayItemId
        WHERE  l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED') AND i.PayrollRunId IS NULL
          AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
          AND  (@EmployeeId IS NULL OR i.EmployeeId = @EmployeeId OR @Action <> 'EMP_SUMMARY')
        GROUP BY l.EmployeePayItemId;

    /* ======================= LIST / GET ========================== */
    IF @Action IN ('LIST', 'GET')
    BEGIN
        IF OBJECT_ID('tempdb..#L') IS NOT NULL DROP TABLE #L;
        SELECT  i.EmployeePayItemId, i.CompanyId, co.CompanyName, i.EmployeeId, e.EmployeeNo,
                LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                i.PayComponentId, c.ComponentCode, c.ComponentName, c.ArabicName AS ComponentArabicName, c.ItemClass, c.SystemCode,
                i.Amount, i.AppliesMode, i.StartMonth, i.EndMonth, i.InstalmentCount, i.TotalAmount, i.Comment, i.Status,
                i.ApprovalLevel, i.SubmittedBy, i.SubmittedDate, i.ReplacesItemId, ri.Amount AS ReplacedAmount, i.SourceRef,
                i.CreatedBy, i.CreatedDate,
                ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount, p.LastPaidMonth,
                CASE WHEN i.AppliesMode = 'INSTALMENT' AND i.TotalAmount IS NOT NULL
                     THEN CASE WHEN i.TotalAmount - ISNULL(p.PaidAmount, 0) > 0 THEN i.TotalAmount - ISNULL(p.PaidAmount, 0) ELSE 0 END END AS Balance,
                CASE WHEN i.Status = 'ACTIVE' AND (
                             (i.AppliesMode = 'INSTALMENT' AND ISNULL(p.PaidCount, 0) >= i.InstalmentCount)
                          OR (i.AppliesMode = 'MONTHLY' AND i.EndMonth IS NOT NULL AND i.EndMonth < @ThisMonth)
                          OR (i.AppliesMode = 'ONCE' AND i.StartMonth < @ThisMonth AND ISNULL(p.PaidCount, 0) > 0))
                     THEN 'ENDED' ELSE i.Status END AS EffectiveStatus,
                CASE c.ItemClass WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'DEDUCTION' THEN 3 ELSE 4 END AS ClassOrder,
                c.DisplayOrder
        INTO    #L
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c  ON c.PayComponentId = i.PayComponentId
        JOIN    [Employee].[Employees]       AS e  ON e.EmployeeId = i.EmployeeId
        LEFT JOIN [Core].[Companies]         AS co ON co.CompanyId = i.CompanyId
        LEFT JOIN [Payroll].[EmployeePayItems] AS ri ON ri.EmployeePayItemId = i.ReplacesItemId
        LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
        WHERE   i.Deleted = 0 AND i.PayrollRunId IS NULL
          AND   (@CompanyId  IS NULL OR i.CompanyId = @CompanyId)
          AND   (   (@Action = 'GET' AND i.EmployeePayItemId = @Id)
                 OR (@Action = 'LIST'
                     AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
                     AND (@EmployeeId IS NULL OR i.EmployeeId = @EmployeeId)
                     AND (@ItemClass  IS NULL OR c.ItemClass = @ItemClass)
                     AND (@Pattern IS NULL OR e.EmployeeNo LIKE @Pattern ESCAPE '\' OR CONCAT(e.FirstName, N' ', e.LastName) LIKE @Pattern ESCAPE '\'
                          OR e.ArabicName LIKE @Pattern ESCAPE '\' OR c.ComponentName LIKE @Pattern ESCAPE '\' OR c.ArabicName LIKE @Pattern ESCAPE '\'
                          OR i.Comment LIKE @Pattern ESCAPE '\' OR i.SourceRef LIKE @Pattern ESCAPE '\')));

        IF @Action = 'LIST' AND @StatusFilter <> 'ALL'
            DELETE FROM #L WHERE NOT ((@StatusFilter = 'OPEN' AND EffectiveStatus IN ('ACTIVE', 'PENDING')) OR EffectiveStatus = @StatusFilter);

        SELECT @TotalCount = COUNT(1) FROM #L;
        SELECT * FROM #L
        ORDER BY EmployeeName, EmployeeNo, ClassOrder, DisplayOrder, StartMonth, EmployeePayItemId
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= SUMMARY (KPIs) ====================== */
    IF @Action = 'SUMMARY'
    BEGIN
        ;WITH base AS (
            SELECT i.*, c.ItemClass, ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount
            FROM   [Payroll].[EmployeePayItems] AS i
            JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            JOIN   [Employee].[Employees]       AS e ON e.EmployeeId = i.EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
            LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
            WHERE  i.Deleted = 0 AND i.PayrollRunId IS NULL
              AND  (@CompanyId  IS NULL OR i.CompanyId = @CompanyId)
              AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ), sal AS (
            SELECT b.*, ROW_NUMBER() OVER (PARTITION BY b.EmployeeId, b.PayComponentId ORDER BY b.StartMonth DESC, b.EmployeePayItemId DESC) AS rn
            FROM   base AS b
            WHERE  b.ItemClass = 'SALARY' AND b.Status = 'ACTIVE' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month)
        ), mon AS (
            SELECT b.*
            FROM   base AS b
            WHERE  b.Status = 'ACTIVE' AND b.ItemClass IN ('EARNING', 'DEDUCTION')
              AND  (   (b.AppliesMode = 'ONCE' AND b.StartMonth = @Month)
                    OR (b.AppliesMode = 'MONTHLY' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month))
                    OR (b.AppliesMode = 'INSTALMENT' AND b.StartMonth <= @Month AND b.PaidCount < b.InstalmentCount))
        )
        SELECT  @Month AS SummaryMonth,
                (SELECT ISNULL(SUM(Amount), 0) FROM sal WHERE rn = 1)                 AS MonthlySalary,
                (SELECT COUNT(DISTINCT EmployeeId) FROM sal WHERE rn = 1)             AS SalaryEmployees,
                (SELECT COUNT(1) FROM sal WHERE rn = 1)                               AS SalaryItems,
                (SELECT ISNULL(SUM(Amount), 0) FROM mon WHERE ItemClass = 'EARNING')  AS Earnings,
                (SELECT COUNT(1) FROM mon WHERE ItemClass = 'EARNING')                AS EarningItems,
                (SELECT ISNULL(SUM(Amount), 0) FROM mon WHERE ItemClass = 'DEDUCTION') AS Deductions,
                (SELECT COUNT(1) FROM mon WHERE ItemClass = 'DEDUCTION')              AS DeductionItems,
                (SELECT ISNULL(SUM(CASE WHEN TotalAmount - PaidAmount > 0 THEN TotalAmount - PaidAmount ELSE 0 END), 0)
                   FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoanOutstanding,
                (SELECT COUNT(1) FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoansRunning,
                (SELECT COUNT(1) FROM base WHERE ItemClass = 'LOAN' AND Status = 'PENDING')  AS LoansPending,
                (SELECT COUNT(1) FROM base WHERE Status = 'PENDING')                         AS PendingApprovals;
        RETURN;
    END;

    /* ======================= EMP_SUMMARY ========================= */
    IF @Action = 'EMP_SUMMARY'
    BEGIN
        ;WITH base AS (
            SELECT i.*, c.ItemClass, ISNULL(p.PaidCount, 0) AS PaidCount, ISNULL(p.PaidAmount, 0) AS PaidAmount
            FROM   [Payroll].[EmployeePayItems] AS i
            JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            LEFT JOIN @Paid AS p ON p.EmployeePayItemId = i.EmployeePayItemId
            WHERE  i.Deleted = 0 AND i.PayrollRunId IS NULL AND i.EmployeeId = @EmployeeId
        ), sal AS (
            SELECT b.Amount, ROW_NUMBER() OVER (PARTITION BY b.PayComponentId ORDER BY b.StartMonth DESC, b.EmployeePayItemId DESC) AS rn
            FROM   base AS b
            WHERE  b.ItemClass = 'SALARY' AND b.Status = 'ACTIVE' AND b.StartMonth <= @Month AND (b.EndMonth IS NULL OR b.EndMonth >= @Month)
        )
        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.CompanyId, d.DepartmentName, ds.DesignationName,
                (SELECT ISNULL(SUM(Amount), 0) FROM sal WHERE rn = 1) AS MonthlySalary,
                (SELECT ISNULL(SUM(CASE WHEN TotalAmount - PaidAmount > 0 THEN TotalAmount - PaidAmount ELSE 0 END), 0)
                   FROM base WHERE ItemClass = 'LOAN' AND Status = 'ACTIVE' AND PaidCount < InstalmentCount) AS LoanBalance,
                (SELECT ISNULL(SUM(TotalAmount), 0) FROM base WHERE ItemClass = 'LOAN' AND Status = 'PENDING') AS LoanPending,
                (SELECT ISNULL(SUM(Amount), 0) FROM base
                  WHERE Status = 'ACTIVE' AND ItemClass IN ('DEDUCTION', 'LOAN')
                    AND ((AppliesMode = 'MONTHLY' AND StartMonth <= @Month AND (EndMonth IS NULL OR EndMonth >= @Month))
                      OR (AppliesMode = 'INSTALMENT' AND StartMonth <= @Month AND PaidCount < InstalmentCount))) AS MonthlyDeductions,
                CASE WHEN NULLIF(LTRIM(RTRIM(ep.Iban)), N'') IS NULL THEN 0 ELSE 1 END AS HasIban,
                ep.BankName
        FROM    [Employee].[Employees] AS e
        LEFT JOIN [Core].[Departments]  AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN [Core].[Designations] AS ds ON ds.DesignationId = e.DesignationId
        LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId AND ep.Deleted = 0
        WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0
          AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId);
        RETURN;
    END;

    /* ======================= TYPES / EMPLOYEES =================== */
    IF @Action = 'TYPES'
    BEGIN
        SELECT  c.PayComponentId, c.CompanyId, c.ComponentCode, c.ComponentName, c.ArabicName, c.ItemClass, c.SystemCode, c.IsActive
        FROM    [Payroll].[PayComponents] AS c
        WHERE   c.Deleted = 0 AND c.ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN')
          AND   (@CompanyId  IS NULL OR c.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(c.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ORDER BY CASE c.ItemClass WHEN 'SALARY' THEN 1 WHEN 'EARNING' THEN 2 WHEN 'DEDUCTION' THEN 3 ELSE 4 END, c.DisplayOrder, c.ComponentName;
        RETURN;
    END;

    IF @Action = 'EMPLOYEES'
    BEGIN
        SELECT  e.EmployeeId, e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, e.ArabicName AS EmployeeArabicName,
                e.CompanyId,
                CAST(CASE WHEN e.EmploymentStatus IN (N'Terminated', N'Resigned') THEN 0 ELSE 1 END AS BIT) AS IsActive
        FROM    [Employee].[Employees] AS e
        WHERE   e.Deleted = 0 AND e.IsDeleted = 0
          AND   (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
          AND   (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
        ORDER BY e.FirstName, e.LastName, e.EmployeeNo;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        /* the item, the salary items it replaced and the change waiting to replace it */
        ;WITH up AS (
            SELECT i.EmployeePayItemId, i.ReplacesItemId, 0 AS Depth
            FROM   [Payroll].[EmployeePayItems] AS i
            WHERE  i.EmployeePayItemId = @Id AND (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
            UNION ALL
            SELECT p.EmployeePayItemId, p.ReplacesItemId, up.Depth + 1
            FROM   up JOIN [Payroll].[EmployeePayItems] AS p ON p.EmployeePayItemId = up.ReplacesItemId
            WHERE  up.Depth < 50
        ), chain AS (
            SELECT EmployeePayItemId FROM up
            UNION
            SELECT n.EmployeePayItemId FROM [Payroll].[EmployeePayItems] AS n JOIN up ON n.ReplacesItemId = up.EmployeePayItemId
        )
        , h AS (
            SELECT  h.PayItemHistoryId, h.EmployeePayItemId, h.ActionCode, h.ApprovalLevel, h.OldAmount, h.NewAmount, h.Comment, h.ActionBy, h.ActionDate
            FROM    [Payroll].[EmployeePayItemHistory] AS h
            JOIN    chain ON chain.EmployeePayItemId = h.EmployeePayItemId
            WHERE   h.Deleted = 0
            UNION ALL
            /* items created before the history existed (e.g. salary moved from the employee profile) */
            SELECT  0, i.EmployeePayItemId, 'CREATED', NULL, NULL, i.Amount, i.Comment, i.CreatedBy, i.CreatedDate
            FROM    [Payroll].[EmployeePayItems] AS i
            JOIN    chain ON chain.EmployeePayItemId = i.EmployeePayItemId
            WHERE   NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItemHistory] x WHERE x.EmployeePayItemId = i.EmployeePayItemId
                                AND x.Deleted = 0 AND x.ActionCode IN ('CREATED', 'REVISED'))
        )
        SELECT  h.PayItemHistoryId, h.EmployeePayItemId, h.ActionCode, h.ApprovalLevel, h.OldAmount, h.NewAmount, h.Comment, h.ActionBy, h.ActionDate,
                i.StartMonth, i.EndMonth, i.AppliesMode, i.Status,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    h
        JOIN    [Payroll].[EmployeePayItems] AS i ON i.EmployeePayItemId = h.EmployeePayItemId
        LEFT JOIN [Security].[Users] u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] ue ON ue.EmployeeId = u.EmployeeId
        ORDER BY h.ActionDate DESC, h.PayItemHistoryId DESC
        OPTION (MAXRECURSION 60);
        RETURN;
    END;

    /* ======================= SAVE ================================ */
    IF @Action = 'SAVE'
    BEGIN
        BEGIN TRANSACTION;
        EXEC [Payroll].[usp_PayItem_Save]
             @Id = @Id, @EmployeeId = @EmployeeId, @PayComponentId = @PayComponentId, @Amount = @Amount, @AppliesMode = @AppliesMode,
             @StartMonth = @StartMonth, @EndMonth = @EndMonth, @InstalmentCount = @InstalmentCount, @TotalAmount = @TotalAmount,
             @Comment = @Comment, @CompanyScope = @CompanyId, @CompanyIds = @CompanyIds, @UserId = @UserId,
             @NewId = @NewId OUTPUT, @ResultCode = @ResultCode OUTPUT, @ResultMessage = @ResultMessage OUTPUT;
        IF @ResultCode = 'SUCCESS' COMMIT TRANSACTION; ELSE ROLLBACK TRANSACTION;
        RETURN;
    END;

    /* ======================= item actions ======================== */
    DECLARE @iStatus VARCHAR(10), @iLevel TINYINT, @iSubmittedBy BIGINT, @iSubmittedDate DATETIME2(0), @iReplaces BIGINT, @iStart DATE,
            @iEmp BIGINT, @iAmount DECIMAL(12,3), @iMode VARCHAR(10), @iClass VARCHAR(10), @iUsed BIT = 0;
    SELECT @iStatus = i.Status, @iLevel = i.ApprovalLevel, @iSubmittedBy = i.SubmittedBy, @iSubmittedDate = i.SubmittedDate,
           @iReplaces = i.ReplacesItemId, @iStart = i.StartMonth, @iEmp = i.EmployeeId, @iAmount = i.Amount, @iMode = i.AppliesMode,
           @iClass = c.ItemClass
    FROM   [Payroll].[EmployeePayItems] AS i
    JOIN   [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
    WHERE  i.EmployeePayItemId = @Id AND i.Deleted = 0 AND i.PayrollRunId IS NULL
      AND  (@CompanyId IS NULL OR i.CompanyId = @CompanyId)
      AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(i.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);

    IF @iStatus IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This pay item no longer exists.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
               WHERE l.EmployeePayItemId = @Id AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED'))
        SET @iUsed = 1;
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');

    /* ---------- APPROVE: level 1 (HR), then level 2 (Finance) ---------- */
    IF @Action = 'APPROVE'
    BEGIN
        IF @iStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This item is not waiting for approval.';
            RETURN;
        END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @iLevel
        BEGIN
            SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
            RETURN;
        END;
        DECLARE @aLevel TINYINT = @iLevel + 1;
        IF @AllowSelfApproval = 0 AND (
               @UserId = @iSubmittedBy
            OR (@aLevel = 2 AND EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItemHistory] WHERE EmployeePayItemId = @Id AND Deleted = 0
                                        AND ActionCode = 'APPROVED' AND ApprovalLevel = 1 AND ActionBy = @UserId
                                        AND ActionDate >= ISNULL(@iSubmittedDate, '19000101'))))
        BEGIN
            SELECT @ResultCode = 'SEGREGATION',
                   @ResultMessage = N'You cannot approve an item you sent for approval or already approved at the previous level.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'APPROVED', @aLevel, @iAmount, @Comment, @UserId);

            IF @aLevel >= 2
            BEGIN
                UPDATE [Payroll].[EmployeePayItems]
                   SET Status = 'ACTIVE', ApprovalLevel = 2, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE EmployeePayItemId = @Id AND Status = 'PENDING' AND ApprovalLevel = @iLevel;
                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
                    RETURN;
                END;

                /* a salary change: the replaced item ends the month before */
                IF @iReplaces IS NOT NULL
                BEGIN
                    UPDATE [Payroll].[EmployeePayItems]
                       SET EndMonth = DATEADD(MONTH, -1, @iStart), ModifiedBy = @UserId, ModifiedDate = @Now
                    WHERE  EmployeePayItemId = @iReplaces AND Deleted = 0 AND Status = 'ACTIVE'
                      AND  StartMonth <= DATEADD(MONTH, -1, @iStart) AND (EndMonth IS NULL OR EndMonth >= @iStart);
                    IF @@ROWCOUNT > 0
                        INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                        SELECT EmployeePayItemId, EmployeeId, 'ENDED', Amount, N'Replaced by the approved salary change', @UserId
                        FROM   [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @iReplaces;
                END;
                SET @ResultMessage = N'Approved. The item is now active.';
            END
            ELSE
            BEGIN
                UPDATE [Payroll].[EmployeePayItems] SET ApprovalLevel = @aLevel, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  EmployeePayItemId = @Id AND Status = 'PENDING' AND ApprovalLevel = @iLevel;
                IF @@ROWCOUNT = 0
                BEGIN
                    ROLLBACK TRANSACTION;
                    SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
                    RETURN;
                END;
                SET @ResultMessage = N'Approved. Waiting for the Finance Manager.';
            END;
        COMMIT TRANSACTION;
        SET @NewId = @aLevel;
        RETURN;
    END;

    /* ---------- REJECT: the pending item is removed ---------- */
    IF @Action = 'REJECT'
    BEGIN
        IF @iStatus <> 'PENDING'
        BEGIN
            SELECT @ResultCode = 'NOT_PENDING', @ResultMessage = N'This item is not waiting for approval.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter the reason for rejecting it.';
            RETURN;
        END;
        IF @ExpectedLevel IS NOT NULL AND @ExpectedLevel <> @iLevel
        BEGIN
            SELECT @ResultCode = 'STALE', @ResultMessage = N'This item was approved by someone else meanwhile. The list has been refreshed.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, ApprovalLevel, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'REJECTED', @iLevel + 1, @iAmount, @Comment, @UserId);
            UPDATE [Payroll].[EmployeePayItems] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EmployeePayItemId = @Id;
        COMMIT TRANSACTION;
        SET @ResultMessage = CASE WHEN @iReplaces IS NOT NULL THEN N'Rejected. The current amount stays.' ELSE N'Rejected. The item was removed.' END;
        RETURN;
    END;

    /* ---------- END: stop paying it ---------- */
    IF @Action = 'END'
    BEGIN
        IF @iStatus <> 'ACTIVE'
        BEGIN
            SELECT @ResultCode = 'NOT_ACTIVE', @ResultMessage = N'Only an active item can be ended. Delete or reject an item that waits for approval.';
            RETURN;
        END;
        IF @EndMonth IS NOT NULL SET @EndMonth = DATEFROMPARTS(YEAR(@EndMonth), MONTH(@EndMonth), 1);

        IF @iMode = 'MONTHLY' AND @EndMonth IS NOT NULL
        BEGIN
            IF @EndMonth < (SELECT MAX(r.RunMonth) FROM [Payroll].[PayrollRunLines] l JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = l.PayrollRunId
                            WHERE l.EmployeePayItemId = @Id AND l.Deleted = 0 AND r.Deleted = 0 AND r.Stage NOT IN ('DRAFT', 'CANCELLED'))
            BEGIN
                SELECT @ResultCode = 'END_BEFORE_PAID', @ResultMessage = N'The last month cannot be before a month already paid.';
                RETURN;
            END;
            IF @EndMonth < @iStart
            BEGIN
                SELECT @ResultCode = 'END_BEFORE_START', @ResultMessage = N'The last month cannot be before the first month.';
                RETURN;
            END;
            BEGIN TRANSACTION;
                UPDATE [Payroll].[EmployeePayItems] SET EndMonth = @EndMonth, ModifiedBy = @UserId, ModifiedDate = @Now WHERE EmployeePayItemId = @Id;
                INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                VALUES (@Id, @iEmp, 'ENDED', @iAmount, @Comment, @UserId);
            COMMIT TRANSACTION;
            SET @ResultMessage = N'Last month saved. The item is not paid after it.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE [Payroll].[EmployeePayItems]
               SET Status = 'ENDED',
                   EndMonth = CASE WHEN AppliesMode = 'MONTHLY'
                                   THEN CASE WHEN DATEADD(MONTH, -1, @ThisMonth) < StartMonth THEN StartMonth ELSE DATEADD(MONTH, -1, @ThisMonth) END
                                   ELSE EndMonth END,
                   ModifiedBy = @UserId, ModifiedDate = @Now
            WHERE  EmployeePayItemId = @Id;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'ENDED', @iAmount, @Comment, @UserId);
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Item ended. No further payroll pays it.';
        RETURN;
    END;

    /* ---------- DELETE: only when no payroll has paid it ---------- */
    IF @Action = 'DELETE'
    BEGIN
        IF @iUsed = 1
        BEGIN
            SELECT @ResultCode = 'ALREADY_PAID', @ResultMessage = N'This item has already been paid by a payroll and cannot be deleted. End it instead.';
            RETURN;
        END;
        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
            VALUES (@Id, @iEmp, 'DELETED', @iAmount, @Comment, @UserId);
            UPDATE [Payroll].[EmployeePayItems] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now WHERE EmployeePayItemId = @Id;

            /* an approved salary change: the amount it replaced applies again */
            IF @iStatus = 'ACTIVE' AND @iReplaces IS NOT NULL
            BEGIN
                UPDATE [Payroll].[EmployeePayItems]
                   SET EndMonth = NULL, ModifiedBy = @UserId, ModifiedDate = @Now
                WHERE  EmployeePayItemId = @iReplaces AND Deleted = 0 AND Status = 'ACTIVE' AND EndMonth = DATEADD(MONTH, -1, @iStart);
                IF @@ROWCOUNT > 0
                    INSERT INTO [Payroll].[EmployeePayItemHistory] (EmployeePayItemId, EmployeeId, ActionCode, NewAmount, Comment, ActionBy)
                    SELECT EmployeePayItemId, EmployeeId, 'CHANGED', Amount, N'The salary change that replaced it was deleted - this amount applies again', @UserId
                    FROM   [Payroll].[EmployeePayItems] WHERE EmployeePayItemId = @iReplaces;
            END;
        COMMIT TRANSACTION;
        SET @ResultMessage = N'Pay item deleted.';
        RETURN;
    END;
END;
GO

/* =====================================================================
   usp_PayItem_Import  -  all rows or none
   @Json: [{"row":2,"employeeNo":"E1001","itemType":"BONUS","amount":"150",
            "applies":"One time","fromMonth":"2026-11","untilMonth":"",
            "instalments":"","total":"","comment":"..."}]
   ===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayItem_Import]
    @Json           NVARCHAR(MAX),
    @CompanyId      INT             = NULL,
    @CompanyIds     NVARCHAR(2000)  = NULL,
    @UserId         BIGINT          = NULL,
    @TotalCount     INT             = NULL OUTPUT,
    @ResultCode     VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @TotalCount = 0;
    SET @CompanyIds = NULLIF(LTRIM(RTRIM(@CompanyIds)), N'');

    IF @Json IS NULL OR ISJSON(@Json) = 0
    BEGIN
        SELECT @ResultCode = 'INVALID_FILE', @ResultMessage = N'The file could not be read.';
        SELECT CAST(NULL AS INT) AS RowNo, CAST(NULL AS NVARCHAR(400)) AS Message WHERE 1 = 0;
        RETURN;
    END;

    CREATE TABLE #R (RowNo INT, EmployeeNo NVARCHAR(50), ItemType NVARCHAR(300), Amount NVARCHAR(50), Applies NVARCHAR(50),
                     FromMonth NVARCHAR(30), UntilMonth NVARCHAR(30), Instalments NVARCHAR(20), Total NVARCHAR(50), Comment NVARCHAR(500));
    INSERT INTO #R
    SELECT [row], LTRIM(RTRIM(employeeNo)), LTRIM(RTRIM(itemType)), LTRIM(RTRIM(amount)), UPPER(LTRIM(RTRIM(applies))),
           LTRIM(RTRIM(fromMonth)), LTRIM(RTRIM(untilMonth)), LTRIM(RTRIM(instalments)), LTRIM(RTRIM(total)), LTRIM(RTRIM(comment))
    FROM   OPENJSON(@Json) WITH ([row] INT, employeeNo NVARCHAR(50), itemType NVARCHAR(300), amount NVARCHAR(50), applies NVARCHAR(50),
                                 fromMonth NVARCHAR(30), untilMonth NVARCHAR(30), instalments NVARCHAR(20), total NVARCHAR(50), comment NVARCHAR(500));

    DECLARE @E TABLE (RowNo INT, Message NVARCHAR(400));   -- a table variable survives the ROLLBACK

    IF NOT EXISTS (SELECT 1 FROM #R)
    BEGIN
        SELECT @ResultCode = 'EMPTY_FILE', @ResultMessage = N'The file has no rows to import.';
        SELECT RowNo, Message FROM @E;
        RETURN;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @RowNo INT, @No NVARCHAR(50), @Type NVARCHAR(300), @Amt NVARCHAR(50), @App NVARCHAR(50), @From NVARCHAR(30), @Until NVARCHAR(30),
                @Inst NVARCHAR(20), @Tot NVARCHAR(50), @Com NVARCHAR(500);
        DECLARE @Emp BIGINT, @EmpCount INT, @EmpCompany INT, @Comp INT, @Class VARCHAR(10), @Mode VARCHAR(10), @FromD DATE, @UntilD DATE,
                @AmountD DECIMAL(12,3), @TotalD DECIMAL(12,3), @Count SMALLINT, @Rc VARCHAR(40), @Rm NVARCHAR(400), @Nid BIGINT;

        DECLARE rows_cur CURSOR LOCAL FAST_FORWARD FOR
            SELECT RowNo, EmployeeNo, ItemType, Amount, Applies, FromMonth, UntilMonth, Instalments, Total, Comment FROM #R ORDER BY RowNo;
        OPEN rows_cur;
        FETCH NEXT FROM rows_cur INTO @RowNo, @No, @Type, @Amt, @App, @From, @Until, @Inst, @Tot, @Com;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SELECT @Emp = NULL, @EmpCount = 0, @EmpCompany = NULL, @Comp = NULL, @Class = NULL, @Mode = NULL, @FromD = NULL, @UntilD = NULL;

            SELECT @Emp = MIN(e.EmployeeId), @EmpCount = COUNT(1), @EmpCompany = MIN(e.CompanyId)
            FROM   [Employee].[Employees] AS e
            WHERE  e.EmployeeNo = @No AND e.Deleted = 0 AND e.IsDeleted = 0
              AND  (@CompanyId  IS NULL OR e.CompanyId = @CompanyId)
              AND  (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(e.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0);

            IF ISNULL(@No, N'') = N'' OR @EmpCount = 0
                INSERT INTO @E VALUES (@RowNo, N'Employee number not found.');
            ELSE IF @EmpCount > 1
                INSERT INTO @E VALUES (@RowNo, N'This employee number is in more than one company - choose one company at the top first.');
            ELSE
            BEGIN
                SELECT TOP 1 @Comp = c.PayComponentId, @Class = c.ItemClass
                FROM   [Payroll].[PayComponents] AS c
                WHERE  c.CompanyId = @EmpCompany AND c.Deleted = 0 AND c.IsActive = 1 AND c.ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN')
                  AND  (c.ComponentCode = @Type OR c.ComponentName = @Type OR c.ArabicName = @Type)
                ORDER BY CASE WHEN c.ComponentCode = @Type THEN 0 ELSE 1 END;

                SET @Mode = CASE WHEN @App IN (N'ONCE', N'ONE TIME', N'ONE-TIME') THEN 'ONCE'
                                 WHEN @App IN (N'MONTHLY', N'EVERY MONTH') THEN 'MONTHLY'
                                 WHEN @App IN (N'INSTALMENT', N'INSTALMENTS', N'IN INSTALMENTS', N'INSTALLMENT', N'INSTALLMENTS') THEN 'INSTALMENT'
                                 WHEN ISNULL(@App, N'') = N'' THEN CASE @Class WHEN 'SALARY' THEN 'MONTHLY' WHEN 'LOAN' THEN 'INSTALMENT' ELSE 'ONCE' END
                            END;
                SET @FromD  = COALESCE(TRY_CONVERT(DATE, @From + N'-01', 23), TRY_CONVERT(DATE, @From, 23), TRY_CONVERT(DATE, @From, 103));
                SET @UntilD = CASE WHEN ISNULL(@Until, N'') = N'' THEN NULL
                                   ELSE COALESCE(TRY_CONVERT(DATE, @Until + N'-01', 23), TRY_CONVERT(DATE, @Until, 23), TRY_CONVERT(DATE, @Until, 103)) END;
                SET @AmountD = TRY_CAST(REPLACE(@Amt, N',', N'') AS DECIMAL(12,3));
                SET @TotalD  = TRY_CAST(REPLACE(@Tot, N',', N'') AS DECIMAL(12,3));
                SET @Count   = TRY_CAST(@Inst AS SMALLINT);

                IF @Comp IS NULL
                    INSERT INTO @E VALUES (@RowNo, N'Item type not found - use a code or name from Payroll Settings > Pay Item Types.');
                ELSE IF @Mode IS NULL
                    INSERT INTO @E VALUES (@RowNo, N'Applies must be One time, Every month or Instalments.');
                ELSE IF @FromD IS NULL
                    INSERT INTO @E VALUES (@RowNo, N'From month must be like 2026-11.');
                ELSE IF ISNULL(@Until, N'') <> N'' AND @UntilD IS NULL
                    INSERT INTO @E VALUES (@RowNo, N'Until month must be like 2026-12.');
                ELSE IF @Class <> 'LOAN' AND @AmountD IS NULL
                    INSERT INTO @E VALUES (@RowNo, N'Enter an amount greater than zero.');
                ELSE
                BEGIN
                    SELECT @Rc = NULL, @Rm = NULL, @Nid = NULL;
                    EXEC [Payroll].[usp_PayItem_Save]
                         @Id = NULL, @EmployeeId = @Emp, @PayComponentId = @Comp, @Amount = @AmountD, @AppliesMode = @Mode,
                         @StartMonth = @FromD, @EndMonth = @UntilD, @InstalmentCount = @Count, @TotalAmount = @TotalD, @Comment = @Com,
                         @CompanyScope = @CompanyId, @CompanyIds = @CompanyIds, @UserId = @UserId,
                         @NewId = @Nid OUTPUT, @ResultCode = @Rc OUTPUT, @ResultMessage = @Rm OUTPUT;
                    IF @Rc <> 'SUCCESS' INSERT INTO @E VALUES (@RowNo, @Rm);
                    ELSE SET @TotalCount += 1;
                END;
            END;
            FETCH NEXT FROM rows_cur INTO @RowNo, @No, @Type, @Amt, @App, @From, @Until, @Inst, @Tot, @Com;
        END;
        CLOSE rows_cur;
        DEALLOCATE rows_cur;

        IF EXISTS (SELECT 1 FROM @E)
        BEGIN
            ROLLBACK TRANSACTION;
            SELECT @ResultCode = 'IMPORT_ERRORS', @TotalCount = 0,
                   @ResultMessage = N'Nothing was imported - correct the rows listed and import the file again.';
        END
        ELSE
        BEGIN
            COMMIT TRANSACTION;
            SET @ResultMessage = CONCAT(N'Imported ', @TotalCount, N' pay items.');
        END;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT @ResultCode = 'IMPORT_FAILED', @ResultMessage = N'The import failed - nothing was imported.', @TotalCount = 0;
        INSERT INTO @E VALUES (NULL, ERROR_MESSAGE());
    END CATCH;

    SELECT RowNo, Message FROM @E ORDER BY RowNo;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/38 applied: usp_PayItem_Save, usp_PayItem_Manage, usp_PayItem_Import.';
GO
