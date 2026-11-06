/* =====================================================================
   121_Payroll_Funding.sql  -  Work permit transfer, balance transfer, collection
   ---------------------------------------------------------------------
   Run after db/116, db/119 and db/120. Safe to re-run. It replaces
   Payroll.usp_Collection_FromPayroll and Payroll.usp_Collection_Manage
   (db/119) and Payroll.usp_Collection_RunPreview (db/120): run this script
   again whenever one of those is run.

   How a payroll's net pay reaches the employees (employees paid by bank):

     Step 1  Work Permit Transfer   the Work Permit Salary, to every employee
     then, per employee, comparing the NET PAY (salary, allowances and other
     earnings less every deduction) with the Work Permit Salary:
       Net = Work Permit Salary   nothing more
       Net < Work Permit Salary   step 1 paid too much: the difference is
                                  collected back - a Work Permit Collection
       Net > Work Permit Salary   Step 2 Balance Transfer: the difference
     Employees with no IBAN are paid their net pay by cash / cheque.

   So:  Work Permit Transfer + Balance Transfer - To Collect = Net payable by bank.

   Payroll.ufn_RunFunding(@RunId) works this out per employee; the
   collections recorded when a payroll is approved, the Create Payroll
   funding summary (Payroll.usp_Payroll_Funding) and the Company Payroll of
   the Bank File (db/116) all follow it. The Collection page shows the net
   pay of each collection (Payroll.Collections.NetPayable).

   First run: the pending collections of approved payrolls are worked out
   again with this rule (collected ones are never changed; history kept).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[ufn_RunPayees]', N'IF') IS NULL OR OBJECT_ID(N'[Payroll].[Collections]', N'U') IS NULL
   OR OBJECT_ID(N'[Payroll].[usp_Collection_FromPayroll]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/50, db/116 and db/119 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the net pay of a collection --------------------------------------- */
IF COL_LENGTH(N'Payroll.Collections', N'NetPayable') IS NULL
    ALTER TABLE [Payroll].[Collections] ADD NetPayable DECIMAL(12,3) NULL;
GO

/* ---- 2. Payroll.ufn_RunFunding - what each employee of a payroll is transferred */
CREATE OR ALTER FUNCTION [Payroll].[ufn_RunFunding] (@RunId BIGINT)
RETURNS TABLE
AS
RETURN
    SELECT  p.RunEmployeeId, p.EmployeeId, p.EmployeeNo, p.EmployeeName, p.DepartmentName, p.Method, p.BankName,
            p.NetPay,
            NULLIF(k.WorkPermitSalary, 0) AS Wps,
            /* step 1: the work permit salary (employees paid by bank) */
            CAST(CASE WHEN p.Method = 'BANK' THEN ISNULL(k.WorkPermitSalary, 0) ELSE 0 END AS DECIMAL(12,3)) AS WorkPermitTransfer,
            /* step 2: the net pay above the work permit salary */
            CAST(CASE WHEN p.Method = 'BANK' AND p.NetPay > ISNULL(k.WorkPermitSalary, 0)
                      THEN p.NetPay - ISNULL(k.WorkPermitSalary, 0) ELSE 0 END AS DECIMAL(12,3)) AS BalanceTransfer,
            /* step 1 paid more than the net pay: collected back */
            CAST(CASE WHEN p.Method = 'BANK' AND ISNULL(k.WorkPermitSalary, 0) > p.NetPay
                      THEN k.WorkPermitSalary - p.NetPay ELSE 0 END AS DECIMAL(12,3)) AS ToCollect,
            CAST(CASE WHEN p.Method = 'CASH' THEN p.NetPay ELSE 0 END AS DECIMAL(12,3)) AS CashPayment,
            CAST(CASE WHEN p.Method = 'CASH'                       THEN 'CASH'
                      WHEN ISNULL(k.WorkPermitSalary, 0) <= 0      THEN 'NO_WPS'
                      WHEN p.NetPay = k.WorkPermitSalary           THEN 'EQUAL'
                      WHEN p.NetPay < k.WorkPermitSalary           THEN 'COLLECT'
                      ELSE 'BALANCE' END AS VARCHAR(8)) AS FundingCase
    FROM    [Payroll].[ufn_RunPayees](@RunId) AS p
    LEFT JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = p.EmployeeId AND k.Deleted = 0;
GO

/* ---- 3. Payroll.usp_Payroll_Funding - the funding summary of a payroll (any stage) */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Payroll_Funding]
    @RunId  BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  f.RunEmployeeId, f.EmployeeId, f.EmployeeNo, f.EmployeeName, f.DepartmentName, f.Method, f.BankName,
            f.NetPay, f.Wps, f.WorkPermitTransfer, f.BalanceTransfer, f.ToCollect, f.CashPayment, f.FundingCase
    FROM    [Payroll].[ufn_RunFunding](@RunId) AS f
    ORDER BY CASE f.FundingCase WHEN 'NO_WPS' THEN 0 WHEN 'COLLECT' THEN 1 WHEN 'BALANCE' THEN 2 WHEN 'EQUAL' THEN 3 ELSE 4 END,
             f.EmployeeNo;
END;
GO

/* ---- 4. Payroll.usp_Collection_RunPreview (db/120): from the funding rule ---- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_RunPreview]
    @RunId  BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT  ISNULL(SUM(f.WorkPermitTransfer), 0)                         AS WorkPermitPayable,
            ISNULL(SUM(CASE WHEN f.WorkPermitTransfer > 0 THEN 1 ELSE 0 END), 0) AS WorkPermitCount,
            ISNULL(SUM(f.ToCollect), 0)                                  AS CollectionAmount,
            ISNULL(SUM(CASE WHEN f.ToCollect > 0 THEN 1 ELSE 0 END), 0)  AS CollectionCount
    FROM    [Payroll].[ufn_RunFunding](@RunId) AS f;
END;
GO

/* ---- 5. Payroll.usp_Collection_FromPayroll (db/119): net pay below the work permit salary */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_FromPayroll]
    @RunId   BIGINT,
    @UserId  BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    /* an approved (closed) regular payroll only */
    DECLARE @CompanyId INT, @RunMonth DATE;
    SELECT  @CompanyId = r.CompanyId, @RunMonth = r.RunMonth
    FROM    [Payroll].[PayrollRuns] AS r
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR';
    IF @CompanyId IS NULL RETURN;

    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0)
        EXEC [Payroll].[usp_PayComponent_SeedCollection] @CompanyId = @CompanyId, @UserId = @UserId;
    DECLARE @CollId INT = (SELECT TOP (1) PayComponentId FROM [Payroll].[PayComponents]
                           WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0 AND IsActive = 1);
    IF @CollId IS NULL RETURN;      -- the type is deactivated: no collections

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    /* db/121: the employees paid by bank whose net pay is below the Work Permit Salary - the
       Ministry Payroll transferred more than they are owed; the difference is collected back */
    DECLARE @Coll TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, Gross DECIMAL(12,3) NOT NULL,
                         Net DECIMAL(12,3) NOT NULL, Wps DECIMAL(12,3) NOT NULL, Amt DECIMAL(12,3) NOT NULL);
    INSERT INTO @Coll (RunEmployeeId, EmployeeId, Gross, Net, Wps, Amt)
    SELECT  f.RunEmployeeId, f.EmployeeId,
            CAST(ISNULL(ep.BasicSalary, 0) + ISNULL(ep.Allowances, 0) AS DECIMAL(12,3)), f.NetPay, f.Wps, f.ToCollect
    FROM    [Payroll].[ufn_RunFunding](@RunId) AS f
    LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = f.EmployeeId AND ep.Deleted = 0
    WHERE   f.FundingCase = 'COLLECT' AND f.ToCollect > 0;

    DECLARE @CollNew TABLE (CollectionId BIGINT PRIMARY KEY, Amount DECIMAL(12,3) NOT NULL);

    BEGIN TRANSACTION;
        /* a pending one follows the figures; one already collected is never changed */
        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  x.CollectionId, 'UPDATED', x.Amount, c.Amt, N'Payroll approved', @UserId
        FROM    [Payroll].[Collections] AS x
        JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING' AND x.Amount <> c.Amt;

        UPDATE  x
           SET  Amount = c.Amt, GrossMonthly = c.Gross, NetPayable = c.Net, WorkPermitSalary = c.Wps, RunEmployeeId = c.RunEmployeeId,
                ModifiedBy = @UserId, ModifiedDate = @Now
        FROM    [Payroll].[Collections] AS x
        JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   (x.Amount <> c.Amt OR x.GrossMonthly <> c.Gross OR ISNULL(x.NetPayable, -1) <> c.Net OR x.WorkPermitSalary <> c.Wps OR x.RunEmployeeId <> c.RunEmployeeId);

        /* no longer due (e.g. approved again after a change) */
        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  x.CollectionId, 'REMOVED', x.Amount, NULL, N'No longer due when the payroll was approved', @UserId
        FROM    [Payroll].[Collections] AS x
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId);
        UPDATE  x SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM    [Payroll].[Collections] AS x
        WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
          AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId);

        INSERT INTO [Payroll].[Collections] (CompanyId, PayrollRunId, RunEmployeeId, EmployeeId, RunMonth, PayComponentId,
                                             GrossMonthly, NetPayable, WorkPermitSalary, Amount, Status, CreatedBy)
        OUTPUT  inserted.CollectionId, inserted.Amount INTO @CollNew (CollectionId, Amount)
        SELECT  @CompanyId, @RunId, c.RunEmployeeId, c.EmployeeId, @RunMonth, @CollId, c.Gross, c.Net, c.Wps, c.Amt, 'PENDING', @UserId
        FROM    @Coll AS c
        WHERE   NOT EXISTS (SELECT 1 FROM [Payroll].[Collections] x
                            WHERE x.PayrollRunId = @RunId AND x.EmployeeId = c.EmployeeId AND x.Deleted = 0);

        INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
        SELECT  n.CollectionId, 'CREATED', NULL, n.Amount, N'Payroll approved - net pay below the work permit salary', @UserId
        FROM    @CollNew AS n;
    COMMIT TRANSACTION;
END;
GO

/* ---- 6. Payroll.usp_Collection_Manage (db/119): + the net pay of each collection */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_Manage]
    @Action         VARCHAR(20),
    @CompanyId      INT             = NULL,     -- the company picked on the page (DASHBOARD: NULL = every company in scope)
    @CompanyIds     NVARCHAR(2000)  = NULL,     -- the companies the user may open (CSV; NULL = any)
    @Month          DATE            = NULL,     -- the payroll month (any day of it)
    @Status         VARCHAR(10)     = NULL,     -- LIST: PENDING / COLLECTED / NULL = both (pending first)
    @Search         NVARCHAR(200)   = NULL,
    @Id             BIGINT          = NULL,
    @Ids            NVARCHAR(MAX)   = NULL,     -- COLLECT: CSV of collection ids
    @CollectedDate  DATE            = NULL,
    @Reference      NVARCHAR(100)   = NULL,
    @Comment        NVARCHAR(500)   = NULL,
    @UserId         BIGINT          = NULL,
    @TotalCount     INT             = NULL OUTPUT,
    @NewId          BIGINT          = NULL OUTPUT,
    @ResultCode     VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = NULL, @TotalCount = 0, @NewId = NULL;

    IF @Action NOT IN ('MONTHS', 'LIST', 'SUMMARY', 'DASHBOARD', 'COLLECT', 'REOPEN', 'HISTORY')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @Month   = CASE WHEN @Month IS NULL THEN NULL ELSE DATEFROMPARTS(YEAR(@Month), MONTH(@Month), 1) END;
    SET @Status  = NULLIF(UPPER(LTRIM(RTRIM(@Status))), '');
    SET @Comment = NULLIF(LTRIM(RTRIM(@Comment)), N'');
    SET @Reference = NULLIF(LTRIM(RTRIM(@Reference)), N'');
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    DECLARE @Allowed TABLE (CompanyId INT PRIMARY KEY);
    IF NULLIF(LTRIM(RTRIM(@CompanyIds)), N'') IS NOT NULL
        INSERT INTO @Allowed (CompanyId)
        SELECT DISTINCT TRY_CAST(value AS INT) FROM STRING_SPLIT(@CompanyIds, ',') WHERE TRY_CAST(value AS INT) IS NOT NULL;
    DECLARE @AnyCompany BIT = CASE WHEN EXISTS (SELECT 1 FROM @Allowed) THEN 0 ELSE 1 END;

    /* the collections of live payrolls (not cancelled, not deleted) the user may see */
    DECLARE @Live TABLE (CollectionId BIGINT PRIMARY KEY);
    INSERT INTO @Live (CollectionId)
    SELECT  c.CollectionId
    FROM    [Payroll].[Collections] AS c
    JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
    WHERE   c.Deleted = 0 AND r.Deleted = 0 AND r.Stage = 'CLOSED'      -- db/119: approved payrolls only
      AND   (@AnyCompany = 1 OR c.CompanyId IN (SELECT CompanyId FROM @Allowed))
      AND   (@Action IN ('COLLECT', 'REOPEN', 'HISTORY')
             OR ((c.CompanyId = @CompanyId OR (@Action = 'DASHBOARD' AND @CompanyId IS NULL)) AND (@Month IS NULL OR c.RunMonth = @Month)));

    /* ======================= MONTHS ============================== */
    /* the payroll months of the company (regular payrolls), newest first, with how much is due */
    IF @Action = 'MONTHS'
    BEGIN
        IF @AnyCompany = 0 AND NOT EXISTS (SELECT 1 FROM @Allowed WHERE CompanyId = @CompanyId) RETURN;
        SELECT  m.RunMonth,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN c.Amount END), 0) AS PendingAmount,
                COUNT(c.CollectionId) AS CollectionCount
        FROM   (SELECT DISTINCT r.RunMonth FROM [Payroll].[PayrollRuns] AS r
                WHERE r.CompanyId = @CompanyId AND r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunType = 'REGULAR') AS m
        LEFT JOIN [Payroll].[Collections] AS c ON c.RunMonth = m.RunMonth AND c.CompanyId = @CompanyId
                                               AND c.CollectionId IN (SELECT CollectionId FROM @Live)
        GROUP BY m.RunMonth
        ORDER BY m.RunMonth DESC;
        RETURN;
    END;

    /* ======================= SUMMARY / DASHBOARD ================= */
    /* DASHBOARD: the Payroll Dashboard's month - every company in scope, or the one given */
    IF @Action IN ('SUMMARY', 'DASHBOARD')
    BEGIN
        SELECT  ISNULL(SUM(c.Amount), 0)                                              AS TotalAmount,
                COUNT(c.CollectionId)                                                 AS TotalCount,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN c.Amount END), 0)      AS PendingAmount,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN 1 ELSE 0 END), 0)      AS PendingCount,
                ISNULL(SUM(CASE WHEN c.Status = 'COLLECTED' THEN c.Amount END), 0)    AS CollectedAmount,
                ISNULL(SUM(CASE WHEN c.Status = 'COLLECTED' THEN 1 ELSE 0 END), 0)    AS CollectedCount
        FROM    [Payroll].[Collections] AS c
        WHERE   c.CollectionId IN (SELECT CollectionId FROM @Live);
        RETURN;
    END;

    /* ======================= LIST ================================ */
    /* not collected first, then by employee */
    IF @Action = 'LIST'
    BEGIN
        SELECT  c.CollectionId, c.CompanyId, c.PayrollRunId, r.RunCode, r.Stage AS RunStage, c.RunMonth,
                c.EmployeeId, re.EmployeeNo, re.EmployeeName, re.ArabicName AS EmployeeArabicName, re.DepartmentName,
                c.GrossMonthly, c.NetPayable, c.WorkPermitSalary, c.Amount, c.Status,
                c.CollectedDate, c.Reference, c.Comment, c.CollectedOn,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS CollectedByName
        FROM    [Payroll].[Collections] AS c
        JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = c.PayrollRunId
        LEFT JOIN [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = c.RunEmployeeId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = c.CollectedBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   c.CollectionId IN (SELECT CollectionId FROM @Live)
          AND   (@Status IS NULL OR c.Status = @Status)
          AND   (@Pattern IS NULL OR re.EmployeeName LIKE @Pattern ESCAPE '\' OR re.ArabicName LIKE @Pattern ESCAPE '\'
                 OR re.EmployeeNo LIKE @Pattern ESCAPE '\' OR c.Reference LIKE @Pattern ESCAPE '\')
        ORDER BY CASE WHEN c.Status = 'PENDING' THEN 0 ELSE 1 END, re.EmployeeName, c.CollectionId;
        SET @TotalCount = @@ROWCOUNT;
        RETURN;
    END;

    /* ======================= HISTORY ============================= */
    IF @Action = 'HISTORY'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Live WHERE CollectionId = @Id) RETURN;
        SELECT  h.CollectionHistoryId, h.ActionCode, h.OldAmount, h.NewAmount, h.CollectedDate, h.Reference, h.Comment, h.ActionDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Payroll].[CollectionHistory] AS h
        LEFT JOIN [Security].[Users] AS u ON u.UserId = h.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   h.CollectionId = @Id AND h.Deleted = 0
        ORDER BY h.ActionDate DESC, h.CollectionHistoryId DESC;
        RETURN;
    END;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);

    /* ======================= COLLECT ============================= */
    /* mark one or more pending collections as received (with the date and an optional
       receipt reference); only once the payroll is created - a draft can still change */
    IF @Action = 'COLLECT'
    BEGIN
        DECLARE @Pick TABLE (CollectionId BIGINT PRIMARY KEY);
        INSERT INTO @Pick (CollectionId)
        SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@Ids, CAST(@Id AS NVARCHAR(30))), ',')
        WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

        IF NOT EXISTS (SELECT 1 FROM @Pick)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the collections that were received.';
            RETURN;
        END;
        SET @CollectedDate = ISNULL(@CollectedDate, @Today);
        IF @CollectedDate > @Today
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The date received cannot be in the future.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Pick p WHERE NOT EXISTS (SELECT 1 FROM @Live l WHERE l.CollectionId = p.CollectionId))
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'A selected collection no longer exists. The list has been refreshed.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM @Pick p JOIN [Payroll].[Collections] c ON c.CollectionId = p.CollectionId WHERE c.Status <> 'PENDING')
        BEGIN
            SELECT @ResultCode = 'ALREADY', @ResultMessage = N'A selected collection was already marked as received. The list has been refreshed.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            UPDATE c
               SET Status = 'COLLECTED', CollectedDate = @CollectedDate, Reference = @Reference, Comment = @Comment,
                   CollectedBy = @UserId, CollectedOn = @Now, ModifiedBy = @UserId, ModifiedDate = @Now
            FROM   [Payroll].[Collections] AS c
            JOIN   @Pick AS p ON p.CollectionId = c.CollectionId;
            SET @TotalCount = @@ROWCOUNT;

            INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, CollectedDate, Reference, Comment, ActionBy)
            SELECT c.CollectionId, 'COLLECTED', NULL, c.Amount, @CollectedDate, @Reference, @Comment, @UserId
            FROM   [Payroll].[Collections] AS c
            JOIN   @Pick AS p ON p.CollectionId = c.CollectionId;
        COMMIT TRANSACTION;

        SET @ResultMessage = CASE WHEN @TotalCount = 1 THEN N'Marked as received.' ELSE CONCAT(@TotalCount, N' collections marked as received.') END;
        RETURN;
    END;

    /* ======================= REOPEN ============================== */
    /* undo a "received" marked by mistake - back to pending, with the reason */
    IF @Action = 'REOPEN'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM @Live WHERE CollectionId = @Id)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'This collection no longer exists.';
            RETURN;
        END;
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[Collections] WHERE CollectionId = @Id AND Status = 'COLLECTED')
        BEGIN
            SELECT @ResultCode = 'NOT_COLLECTED', @ResultMessage = N'This collection is not marked as received.';
            RETURN;
        END;
        IF @Comment IS NULL
        BEGIN
            SELECT @ResultCode = 'COMMENT_REQUIRED', @ResultMessage = N'Enter why it is set back to pending.';
            RETURN;
        END;

        BEGIN TRANSACTION;
            INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, CollectedDate, Reference, Comment, ActionBy)
            SELECT CollectionId, 'REOPENED', Amount, NULL, CollectedDate, Reference, @Comment, @UserId
            FROM   [Payroll].[Collections] WHERE CollectionId = @Id;

            UPDATE [Payroll].[Collections]
               SET Status = 'PENDING', CollectedDate = NULL, Reference = NULL, Comment = NULL, CollectedBy = NULL, CollectedOn = NULL,
                   ModifiedBy = @UserId, ModifiedDate = @Now
             WHERE CollectionId = @Id;
        COMMIT TRANSACTION;
        SELECT @NewId = @Id, @ResultMessage = N'Set back to pending.';
        RETURN;
    END;
END;
GO

/* ---- 7. first run: the pending collections of approved payrolls, again ------ */
DECLARE @Run BIGINT, @Done INT = 0;
DECLARE runs CURSOR LOCAL FAST_FORWARD FOR
    SELECT PayrollRunId FROM [Payroll].[PayrollRuns] WHERE Deleted = 0 AND Stage = 'CLOSED' AND RunType = 'REGULAR';
OPEN runs;
FETCH NEXT FROM runs INTO @Run;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Payroll].[usp_Collection_FromPayroll] @RunId = @Run;
    SET @Done += 1;
    FETCH NEXT FROM runs INTO @Run;
END;
CLOSE runs; DEALLOCATE runs;
PRINT CONCAT(N'Approved payrolls whose collections were worked out again: ', @Done);
GO

/* ---- 8. labels ------------------------------------------------------------ */
UPDATE l SET EnglishText = v.EnglishText, ArabicText = v.ArabicText
FROM   [Core].[UiLabels] AS l
JOIN  (VALUES
        ('col.intro_text', N'When an employee''s net pay is below the work permit salary, the Ministry Payroll (step 1 of the bank file) transfers more than they are owed: approving the payroll records the difference here, to collect back. Company records only - not on the payslip. Mark it here once collected.', N'عندما يكون صافي راتب الموظف أقل من راتب إذن العمل، تحوّل رواتب الوزارة (الخطوة 1 من ملف البنك) أكثر من المستحق: يُسجَّل الفرق هنا عند اعتماد الرواتب لاسترداده. لسجلات الشركة فقط - لا يظهر في قسيمة الراتب. سجّل تحصيله هنا.'),
        ('col.none_this_month_text', N'Every employee''s net pay reaches their work permit salary, or the payroll is not approved yet.', N'صافي راتب كل موظف يصل إلى راتب إذن العمل، أو لم تُعتمد الرواتب بعد.'),
        ('pr.total_collection_note_0', N'KWD · {0} employees · net pay below the work permit salary', N'د.ك · {0} موظفين · صافي الراتب أقل من راتب إذن العمل')
      ) AS v (LabelKey, EnglishText, ArabicText) ON v.LabelKey = l.LabelKey COLLATE DATABASE_DEFAULT
WHERE  l.Deleted = 0;

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('col.net_payable', 'col', N'Net payable (KWD)', N'صافي المستحق (د.ك)', NULL),
        ('fund.title', 'fund', N'Payroll funding', N'تمويل الرواتب', NULL),
        ('fund.subtitle', 'fund', N'How the net pay reaches the employees: the work permit salary first, then the balance; what step 1 pays too much is collected back.', N'كيف يصل صافي الراتب إلى الموظفين: راتب إذن العمل أولاً ثم الرصيد؛ وما تدفعه الخطوة 1 زيادةً يُسترد.', NULL),
        ('fund.net_payable', 'fund', N'Net payable', N'صافي المستحق', NULL),
        ('fund.net_payable_note_0', 'fund', N'KWD · company payroll · {0} employees', N'د.ك · رواتب الشركة · {0} موظفين', NULL),
        ('fund.wp_transfer', 'fund', N'Step 1 · Work permit transfer', N'الخطوة 1 · تحويل راتب إذن العمل', NULL),
        ('fund.wp_transfer_note_0', 'fund', N'KWD · Ministry Payroll · {0} employees', N'د.ك · رواتب الوزارة · {0} موظفين', NULL),
        ('fund.balance', 'fund', N'Step 2 · Balance transfer', N'الخطوة 2 · تحويل الرصيد', NULL),
        ('fund.balance_note_0', 'fund', N'KWD · Company Payroll · {0} employees', N'د.ك · رواتب الشركة · {0} موظفين', NULL),
        ('fund.collect', 'fund', N'To collect', N'المطلوب تحصيله', NULL),
        ('fund.collect_note_0', 'fund', N'KWD · from {0} employees', N'د.ك · من {0} موظفين', NULL),
        ('fund.reconcile', 'fund', N'Work permit transfer + Balance transfer − To collect = Net payable by bank', N'تحويل إذن العمل + تحويل الرصيد − المطلوب تحصيله = صافي المستحق بالبنك', NULL),
        ('fund.cash_0_1', 'fund', N'+ Cash / cheque {0} ({1} employees with no IBAN) = Net payable {2}', N'+ نقداً / شيك {0} ({1} موظفين بدون آيبان) = صافي المستحق {2}', NULL),
        ('fund.balanced', 'fund', N'Balanced', N'متوازن', NULL),
        ('fund.not_balanced', 'fund', N'Not balanced', N'غير متوازن', NULL),
        ('fund.by_case', 'fund', N'By case', N'حسب الحالة', NULL),
        ('fund.case', 'fund', N'Case', N'الحالة', NULL),
        ('fund.case_equal', 'fund', N'Net = work permit salary', N'الصافي = راتب إذن العمل', NULL),
        ('fund.case_equal_hint', 'fund', N'Step 1 pays it all', N'الخطوة 1 تدفعه كاملاً', NULL),
        ('fund.case_collect', 'fund', N'Net below work permit salary', N'الصافي أقل من راتب إذن العمل', NULL),
        ('fund.case_collect_hint', 'fund', N'Step 1 pays too much - collected back', N'الخطوة 1 تدفع زيادة - تُسترد', NULL),
        ('fund.case_balance', 'fund', N'Net above work permit salary', N'الصافي أعلى من راتب إذن العمل', NULL),
        ('fund.case_balance_hint', 'fund', N'Step 2 transfers the balance', N'الخطوة 2 تحوّل الرصيد', NULL),
        ('fund.case_cash', 'fund', N'No IBAN - cash / cheque', N'بدون آيبان - نقداً / شيك', NULL),
        ('fund.case_cash_hint', 'fund', N'Net pay by cash / cheque', N'صافي الراتب نقداً / بشيك', NULL),
        ('fund.case_no_wps', 'fund', N'No work permit salary', N'بدون راتب إذن عمل', NULL),
        ('fund.case_no_wps_hint', 'fund', N'Enter it on the profile - step 1 cannot run', N'أدخله في الملف - لا يمكن تنفيذ الخطوة 1', NULL),
        ('fund.employees', 'fund', N'Employees', N'الموظفون', NULL),
        ('fund.col_net', 'fund', N'Net pay', N'صافي الراتب', NULL),
        ('fund.col_wps', 'fund', N'Work permit salary', N'راتب إذن العمل', NULL),
        ('fund.col_step1', 'fund', N'Step 1', N'الخطوة 1', NULL),
        ('fund.col_step2', 'fund', N'Step 2', N'الخطوة 2', NULL),
        ('fund.col_collect', 'fund', N'To collect', N'للتحصيل', NULL),
        ('fund.col_cash', 'fund', N'Cash', N'نقداً', NULL),
        ('fund.total', 'fund', N'Total', N'الإجمالي', NULL),
        ('fund.show_employees_0', 'fund', N'Show the {0} employees', N'عرض الموظفين ({0})', NULL),
        ('fund.no_wps_warning_0', 'fund', N'{0} employees paid by bank have no work permit salary - the Ministry Payroll cannot be generated until it is entered.', N'{0} موظفين يُدفع لهم بالبنك بدون راتب إذن عمل - لا يمكن إنشاء رواتب الوزارة حتى يُدخل.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Payroll funding labels inserted: ', @@ROWCOUNT);
GO
