/* =====================================================================
   105_Journal_Entry_Mode.sql  -  Payroll Journal: GL entry for the Company or for each Employee
   ---------------------------------------------------------------------
   Safe to re-run. Run after db/50 (it replaces Payroll.usp_Journal_Manage).

   When a journal is created from a closed payroll the user now chooses:
     COMPANY   (as before) one entry for the whole payroll - the lines are
               grouped by account and cost center
     EMPLOYEE  an entry for every employee - each employee's own debit and
               credit lines (same GL mapping, cost allocation and salaries
               payable rules), balanced per employee, and every line carries
               the employee and the Payroll Month-Year for reference

   JournalBatches.EntryMode / PayrollMonth and JournalLines.EmployeeId /
   EmployeeNo / EmployeeName / PayrollMonth hold it. Journals made before this
   script are COMPANY journals; their month is filled from the payroll.
   A payroll still has one open journal at a time - reverse it to journal the
   payroll again in the other way.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH('Payroll.JournalBatches', 'EntryMode') IS NULL
    ALTER TABLE [Payroll].[JournalBatches] ADD [EntryMode] VARCHAR(10) NOT NULL CONSTRAINT DF_JournalBatches_EntryMode DEFAULT ('COMPANY');
GO
IF COL_LENGTH('Payroll.JournalBatches', 'PayrollMonth') IS NULL
    ALTER TABLE [Payroll].[JournalBatches] ADD [PayrollMonth] DATE NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_JournalBatches_EntryMode')
    ALTER TABLE [Payroll].[JournalBatches] ADD CONSTRAINT CK_JournalBatches_EntryMode CHECK (EntryMode IN ('COMPANY', 'EMPLOYEE'));
GO
IF COL_LENGTH('Payroll.JournalLines', 'EmployeeId') IS NULL
    ALTER TABLE [Payroll].[JournalLines] ADD [EmployeeId] BIGINT NULL;
GO
IF COL_LENGTH('Payroll.JournalLines', 'EmployeeNo') IS NULL
    ALTER TABLE [Payroll].[JournalLines] ADD [EmployeeNo] NVARCHAR(20) NULL;
GO
IF COL_LENGTH('Payroll.JournalLines', 'EmployeeName') IS NULL
    ALTER TABLE [Payroll].[JournalLines] ADD [EmployeeName] NVARCHAR(300) NULL;
GO
IF COL_LENGTH('Payroll.JournalLines', 'PayrollMonth') IS NULL
    ALTER TABLE [Payroll].[JournalLines] ADD [PayrollMonth] DATE NULL;
GO

/* journals made before: the payroll's month */
UPDATE j SET PayrollMonth = r.RunMonth
FROM   [Payroll].[JournalBatches] AS j JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
WHERE  j.PayrollMonth IS NULL;
UPDATE l SET PayrollMonth = j.PayrollMonth
FROM   [Payroll].[JournalLines] AS l JOIN [Payroll].[JournalBatches] AS j ON j.JournalId = l.JournalId
WHERE  l.PayrollMonth IS NULL;
GO

/* =====================================================================
   Payroll.ufn_PayrollJournalByEmployee - ufn_PayrollJournal (db/50) with
   the employee kept on every line: grouped by employee, account, cost
   center and side, so each employee's entry balances on its own.
===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_PayrollJournalByEmployee] (@RunId BIGINT)
RETURNS TABLE
AS
RETURN
    WITH run AS (
        SELECT r.PayrollRunId, r.CompanyId, r.RunMonth, EOMONTH(r.RunMonth) AS MonthEnd,
               ISNULL(ad.NetPayAccountCode, N'210100') AS PayCode,
               ISNULL(ad.NetPayAccountName, N'Salaries payable') AS PayName
        FROM   [Payroll].[PayrollRuns] AS r
        LEFT JOIN [Payroll].[AccountingDefaults] AS ad ON ad.CompanyId = r.CompanyId AND ad.Deleted = 0
        WHERE  r.PayrollRunId = @RunId
    ), ln AS (
        SELECT l.RunLineId, l.EmployeeId, re.EmployeeNo, re.EmployeeName, l.PayComponentId, l.Amount, ABS(l.Amount) AS Amt, re.CostCenterId AS EmpCc
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = l.RunEmployeeId AND re.Deleted = 0 AND re.IsExcluded = 0
        WHERE  l.PayrollRunId = @RunId AND l.Deleted = 0 AND l.Amount <> 0
    ), alloc AS (
        SELECT a.EmployeeId, al.CostCenterId, al.SharePercent,
               SUM(al.SharePercent) OVER (PARTITION BY a.EmployeeId ORDER BY al.CostAllocationLineId ROWS UNBOUNDED PRECEDING) AS CumShare
        FROM   [Payroll].[CostAllocations] AS a
        JOIN   run ON run.CompanyId = a.CompanyId
        JOIN   [Payroll].[CostAllocationLines] AS al ON al.CostAllocationId = a.CostAllocationId AND al.Deleted = 0
        WHERE  a.Deleted = 0 AND a.EffectiveFrom <= run.MonthEnd AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= run.MonthEnd)
    ), part AS (
        /* earnings are split by the allocation (the rounding goes to the shares in turn, so they add up exactly) */
        SELECT ln.RunLineId, ln.EmployeeId, ln.EmployeeNo, ln.EmployeeName, ln.PayComponentId, ln.Amount,
               CASE WHEN ln.Amount > 0 AND a.EmployeeId IS NOT NULL THEN a.CostCenterId ELSE ln.EmpCc END AS CostCenterId,
               CASE WHEN ln.Amount > 0 AND a.EmployeeId IS NOT NULL
                    THEN ROUND(ln.Amt * a.CumShare / 100.0, 3) - ROUND(ln.Amt * (a.CumShare - a.SharePercent) / 100.0, 3)
                    ELSE ln.Amt END AS Amt
        FROM   ln
        LEFT JOIN alloc AS a ON a.EmployeeId = ln.EmployeeId AND ln.Amount > 0
    ), entry AS (
        SELECT e.Side, e.Code, e.Name, e.CostCenterId, e.Unmapped, p.Amt, c.ComponentName, p.EmployeeId, p.EmployeeNo, p.EmployeeName
        FROM   part AS p
        CROSS JOIN run
        JOIN   [Payroll].[PayComponents] AS c ON c.PayComponentId = p.PayComponentId
        OUTER APPLY (SELECT TOP (1) m.DebitAccountCode, m.DebitAccountName, m.CreditAccountCode, m.CreditAccountName
                     FROM   [Payroll].[GLMappings] AS m
                     WHERE  m.PayComponentId = p.PayComponentId AND m.IsActive = 1 AND m.Deleted = 0
                       AND (m.CostCenterId = p.CostCenterId OR m.CostCenterId IS NULL)
                     ORDER BY CASE WHEN m.CostCenterId IS NULL THEN 1 ELSE 0 END) AS m
        CROSS APPLY (VALUES
            /* debit side */
            ('D',
             CASE WHEN p.Amount > 0 THEN COALESCE(m.DebitAccountCode, NULLIF(c.GLAccountCode, N''), N'UNMAPPED-' + c.ComponentCode)
                  ELSE COALESCE(m.DebitAccountCode, run.PayCode) END,
             CASE WHEN p.Amount > 0 THEN COALESCE(m.DebitAccountName, CASE WHEN m.DebitAccountCode IS NULL THEN c.GLAccountName END, c.ComponentName)
                  ELSE COALESCE(m.DebitAccountName, CASE WHEN m.DebitAccountCode IS NULL THEN run.PayName END) END,
             CASE WHEN p.Amount > 0 THEN p.CostCenterId END,
             CASE WHEN p.Amount > 0 AND m.DebitAccountCode IS NULL AND NULLIF(c.GLAccountCode, N'') IS NULL THEN 1 ELSE 0 END),
            /* credit side */
            ('C',
             CASE WHEN p.Amount > 0 THEN COALESCE(m.CreditAccountCode, run.PayCode)
                  ELSE COALESCE(m.CreditAccountCode, NULLIF(c.GLAccountCode, N''), N'UNMAPPED-' + c.ComponentCode) END,
             CASE WHEN p.Amount > 0 THEN COALESCE(m.CreditAccountName, CASE WHEN m.CreditAccountCode IS NULL THEN run.PayName END)
                  ELSE COALESCE(m.CreditAccountName, CASE WHEN m.CreditAccountCode IS NULL THEN c.GLAccountName END, c.ComponentName) END,
             NULL,
             CASE WHEN p.Amount < 0 AND m.CreditAccountCode IS NULL AND NULLIF(c.GLAccountCode, N'') IS NULL THEN 1 ELSE 0 END)
        ) AS e(Side, Code, Name, CostCenterId, Unmapped)
        WHERE  p.Amt <> 0
    )
    SELECT  ROW_NUMBER() OVER (ORDER BY g.EmployeeNo, g.EmployeeId, g.Side DESC, g.Code, cc.CostCenterName) AS LineNumber,
            g.Code AS AccountCode, g.Name AS AccountName, g.CostCenterId, cc.CostCenterName,
            CAST(CASE WHEN g.Side = 'D' THEN g.Amt ELSE 0 END AS DECIMAL(14,3)) AS Debit,
            CAST(CASE WHEN g.Side = 'C' THEN g.Amt ELSE 0 END AS DECIMAL(14,3)) AS Credit,
            g.Unmapped AS IsUnmapped,
            LEFT(CONCAT(FORMAT(run.RunMonth, 'MMM-yyyy', 'en-US'), N' · ', g.EmployeeNo, N' ', g.EmployeeName,
                        CASE WHEN g.Items IS NULL THEN N'' ELSE CONCAT(N' · ', g.Items) END), 300) AS Description,
            g.EmployeeId, g.EmployeeNo, g.EmployeeName, run.RunMonth AS PayrollMonth
    FROM (
        SELECT Side, Code, MAX(Name) AS Name, CostCenterId, EmployeeId, MAX(EmployeeNo) AS EmployeeNo, MAX(EmployeeName) AS EmployeeName,
               SUM(Amt) AS Amt, CAST(MAX(Unmapped) AS BIT) AS Unmapped,
               LEFT(STRING_AGG(CAST(NULLIF(ComponentName, N'') AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY ComponentName), 200) AS Items
        FROM (SELECT DISTINCT Side, Code, Name, CostCenterId, Unmapped, ComponentName, EmployeeId, EmployeeNo, EmployeeName, CAST(0 AS DECIMAL(14,3)) AS Amt FROM entry
              UNION ALL
              SELECT Side, Code, Name, CostCenterId, Unmapped, N'', EmployeeId, EmployeeNo, EmployeeName, Amt FROM entry) AS u
        GROUP BY Side, Code, CostCenterId, EmployeeId
    ) AS g
    CROSS JOIN run
    LEFT JOIN [Core].[CostCenters] AS cc ON cc.CostCenterId = g.CostCenterId;
GO


/* =====================================================================
   Payroll.usp_Journal_Manage - db/50 plus @Mode (COMPANY / EMPLOYEE) on
   PREVIEW and CREATE, and EntryMode / PayrollMonth / the employee on GET,
   LIST and LINES.
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Journal_Manage]
    @Action                VARCHAR(20),
    @CompanyId             INT             = NULL,
    @CompanyIds            NVARCHAR(2000)  = NULL,
    @Id                    BIGINT          = NULL,
    @RunId                 BIGINT          = NULL,
    @Year                  INT             = NULL,
    @RunMonth              DATE            = NULL,
    @Status                VARCHAR(10)     = NULL,
    @Search                NVARCHAR(200)   = NULL,
    @PageNumber            INT             = 1,
    @PageSize              INT             = 25,

    @Reference             NVARCHAR(100)   = NULL,
    @Reason                NVARCHAR(500)   = NULL,
    @Mode                  VARCHAR(10)     = NULL,     -- PREVIEW / CREATE: COMPANY (one entry for the payroll) or EMPLOYEE (an entry per employee)
    @ForCompanyId          INT             = NULL,     -- DEFAULTS / SET_DEFAULTS
    @AccountCode           NVARCHAR(50)    = NULL,
    @AccountName           NVARCHAR(150)   = NULL,

    @UserId                BIGINT          = NULL,
    @TotalCount            INT             = NULL OUTPUT,
    @NewId                 BIGINT          = NULL OUTPUT,
    @ResultCode            VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage         NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    SET @Mode = CASE WHEN UPPER(LTRIM(RTRIM(@Mode))) = 'EMPLOYEE' THEN 'EMPLOYEE' ELSE 'COMPANY' END;

    IF @Action NOT IN ('RUNS', 'PREVIEW', 'CREATE', 'LIST', 'GET', 'LINES', 'EXPORTED', 'POSTED', 'REVERSE', 'DEFAULTS', 'SET_DEFAULTS')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= DEFAULTS ============================ */
    IF @Action IN ('DEFAULTS', 'SET_DEFAULTS')
    BEGIN
        IF @ForCompanyId IS NULL OR [Payroll].[ufn_InCompanyScope](@ForCompanyId, @CompanyId, @CompanyIds) = 0
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select a company.';
            RETURN;
        END;
        IF @Action = 'DEFAULTS'
        BEGIN
            SELECT @ForCompanyId AS CompanyId, ISNULL(ad.NetPayAccountCode, N'210100') AS NetPayAccountCode,
                   ISNULL(ad.NetPayAccountName, N'Salaries payable') AS NetPayAccountName,
                   CAST(CASE WHEN ad.CompanyId IS NULL THEN 0 ELSE 1 END AS BIT) AS IsSaved
            FROM (SELECT 1 AS x) AS one
            LEFT JOIN [Payroll].[AccountingDefaults] AS ad ON ad.CompanyId = @ForCompanyId AND ad.Deleted = 0;
            RETURN;
        END;
        IF NULLIF(LTRIM(RTRIM(@AccountCode)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the salaries payable account.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[AccountingDefaults] WHERE CompanyId = @ForCompanyId)
            UPDATE [Payroll].[AccountingDefaults]
               SET NetPayAccountCode = LTRIM(RTRIM(@AccountCode)), NetPayAccountName = NULLIF(LTRIM(RTRIM(@AccountName)), N''),
                   Deleted = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE CompanyId = @ForCompanyId;
        ELSE
            INSERT INTO [Payroll].[AccountingDefaults] (CompanyId, NetPayAccountCode, NetPayAccountName, ModifiedBy)
            VALUES (@ForCompanyId, LTRIM(RTRIM(@AccountCode)), NULLIF(LTRIM(RTRIM(@AccountName)), N''), @UserId);
        SET @ResultMessage = N'Default accounts saved.';
        RETURN;
    END;

    /* ======================= RUNS ================================ */
    IF @Action = 'RUNS'
    BEGIN
        SELECT  r.PayrollRunId, r.RunCode, r.RunType, r.RunMonth, r.CompanyId, co.CompanyName, pc.CalendarName,
                pp.StartDate, pp.EndDate, pp.PaymentDate, r.ClosedDate, r.EmployeeCount, r.TotalNet,
                r.TotalSalary + r.TotalEarnings AS TotalGross, ABS(r.TotalDeductions) AS TotalDeductions,
                j.JournalId, j.JournalNo, j.Status AS JournalStatus, j.EntryMode AS JournalEntryMode
        FROM    [Payroll].[PayrollRuns]      AS r
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]   AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        LEFT JOIN [Payroll].[JournalBatches] AS j ON j.PayrollRunId = r.PayrollRunId AND j.Deleted = 0 AND j.Status <> 'REVERSED'
        WHERE   r.Deleted = 0 AND r.Stage = 'CLOSED'
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND  (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
        ORDER BY r.RunMonth DESC, r.RunCode;
        RETURN;
    END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[JournalBatches] AS j
        JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
        WHERE  j.Deleted = 0
          AND  [Payroll].[ufn_InCompanyScope](j.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
          AND (@Status IS NULL OR j.Status = @Status OR (@Status = 'OPEN' AND j.Status IN ('READY', 'EXPORTED')))
          AND (@Pattern IS NULL OR j.JournalNo LIKE @Pattern ESCAPE '\' OR r.RunCode LIKE @Pattern ESCAPE '\' OR j.PostedReference LIKE @Pattern ESCAPE '\');

        SELECT  j.JournalId, j.CompanyId, j.PayrollRunId, j.JournalNo, j.JournalDate, j.Status, j.TotalDebit, j.TotalCredit, j.LineCount,
                j.UnmappedCount, j.ExportCount, j.EntryMode, j.PayrollMonth, j.ExportedDate, j.PostedReference, j.PostedDate, j.ReversedDate, j.ReverseReason, j.CreatedDate,
                r.RunCode, r.RunMonth, co.CompanyName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(xe.FirstName, N' ', xe.LastName))), N''), xu.Username) AS ExportedByName,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(pe.FirstName, N' ', pe.LastName))), N''), pu.Username) AS PostedByName
        FROM    [Payroll].[JournalBatches] AS j
        JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
        JOIN    [Core].[Companies] AS co ON co.CompanyId = j.CompanyId
        LEFT JOIN [Security].[Users] AS xu ON xu.UserId = j.ExportedBy
        LEFT JOIN [Employee].[Employees] AS xe ON xe.EmployeeId = xu.EmployeeId
        LEFT JOIN [Security].[Users] AS pu ON pu.UserId = j.PostedBy
        LEFT JOIN [Employee].[Employees] AS pe ON pe.EmployeeId = pu.EmployeeId
        WHERE   j.Deleted = 0
          AND   [Payroll].[ufn_InCompanyScope](j.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND  (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
          AND  (@Status IS NULL OR j.Status = @Status OR (@Status = 'OPEN' AND j.Status IN ('READY', 'EXPORTED')))
          AND  (@Pattern IS NULL OR j.JournalNo LIKE @Pattern ESCAPE '\' OR r.RunCode LIKE @Pattern ESCAPE '\' OR j.PostedReference LIKE @Pattern ESCAPE '\')
        ORDER BY CASE j.Status WHEN 'READY' THEN 0 WHEN 'EXPORTED' THEN 1 WHEN 'POSTED' THEN 2 ELSE 3 END, r.RunMonth DESC, j.JournalNo DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= one journal ========================= */
    IF @Action IN ('GET', 'LINES', 'EXPORTED', 'POSTED', 'REVERSE')
    BEGIN
        DECLARE @jStatus VARCHAR(10);
        SELECT @jStatus = Status FROM [Payroll].[JournalBatches]
        WHERE  JournalId = @Id AND Deleted = 0 AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1;
        IF @jStatus IS NULL
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That journal no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF @Action = 'GET'
        BEGIN
            SELECT j.JournalId, j.CompanyId, j.PayrollRunId, j.JournalNo, j.JournalDate, j.Status, j.TotalDebit, j.TotalCredit, j.LineCount,
                   j.UnmappedCount, j.ExportCount, j.EntryMode, j.PayrollMonth, j.PostedReference, j.ReverseReason, r.RunCode, r.RunMonth, co.CompanyName
            FROM   [Payroll].[JournalBatches] AS j
            JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
            JOIN   [Core].[Companies] AS co ON co.CompanyId = j.CompanyId
            WHERE  j.JournalId = @Id;
            RETURN;
        END;
        IF @Action = 'LINES'
        BEGIN
            SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                   EmployeeId, EmployeeNo, EmployeeName, PayrollMonth
            FROM   [Payroll].[JournalLines] WHERE JournalId = @Id AND Deleted = 0 ORDER BY LineNumber;
            RETURN;
        END;
        IF @Action = 'EXPORTED'
        BEGIN
            UPDATE [Payroll].[JournalBatches]
               SET ExportCount = ExportCount + 1, ExportedBy = @UserId, ExportedDate = SYSUTCDATETIME(),
                   Status = CASE WHEN Status = 'READY' THEN 'EXPORTED' ELSE Status END
             WHERE JournalId = @Id;
            RETURN;
        END;
        IF @Action = 'POSTED'
        BEGIN
            IF @jStatus NOT IN ('READY', 'EXPORTED')
            BEGIN
                SELECT @ResultCode = 'INVALID_STATE', @ResultMessage = N'Only a journal that is not yet posted or reversed can be marked as posted.';
                RETURN;
            END;
            IF NULLIF(LTRIM(RTRIM(@Reference)), N'') IS NULL
            BEGIN
                SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reference of the entry in the books.';
                RETURN;
            END;
            UPDATE [Payroll].[JournalBatches]
               SET Status = 'POSTED', PostedReference = LTRIM(RTRIM(@Reference)), PostedBy = @UserId, PostedDate = SYSUTCDATETIME()
             WHERE JournalId = @Id;
            SET @ResultMessage = N'Journal marked as posted.';
            RETURN;
        END;
        /* REVERSE */
        IF @jStatus = 'REVERSED'
        BEGIN
            SELECT @ResultCode = 'INVALID_STATE', @ResultMessage = N'This journal is already reversed.';
            RETURN;
        END;
        IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the reason for reversing the journal.';
            RETURN;
        END;
        UPDATE [Payroll].[JournalBatches]
           SET Status = 'REVERSED', ReverseReason = LTRIM(RTRIM(@Reason)), ReversedBy = @UserId, ReversedDate = SYSUTCDATETIME()
         WHERE JournalId = @Id;
        SET @ResultMessage = N'Journal reversed - the payroll can be journaled again.';
        RETURN;
    END;

    /* ======================= PREVIEW / CREATE ==================== */
    DECLARE @rCompany INT, @rMonth DATE, @rPayDate DATE;
    SELECT  @rCompany = r.CompanyId, @rMonth = r.RunMonth, @rPayDate = ISNULL(pp.PaymentDate, EOMONTH(r.RunMonth))
    FROM    [Payroll].[PayrollRuns] AS r
    JOIN    [Payroll].[PayrollPeriods] AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0 AND r.Stage = 'CLOSED'
      AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;

    IF @rCompany IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select a closed payroll - a journal is made only for a closed payroll.';
        RETURN;
    END;

    IF @Action = 'PREVIEW'
    BEGIN
        IF @Mode = 'EMPLOYEE'
            SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                   EmployeeId, EmployeeNo, EmployeeName, PayrollMonth
            FROM   [Payroll].[ufn_PayrollJournalByEmployee](@RunId)
            ORDER BY LineNumber;
        ELSE
            SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                   CAST(NULL AS BIGINT) AS EmployeeId, CAST(NULL AS NVARCHAR(20)) AS EmployeeNo, CAST(NULL AS NVARCHAR(300)) AS EmployeeName,
                   @rMonth AS PayrollMonth
            FROM   [Payroll].[ufn_PayrollJournal](@RunId)
            ORDER BY LineNumber;
        RETURN;
    END;

    /* CREATE */
    IF EXISTS (SELECT 1 FROM [Payroll].[JournalBatches] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'REVERSED')
    BEGIN
        SELECT @ResultCode = 'DUPLICATE', @ResultMessage = N'This payroll already has a journal. Reverse it first to make a new one.';
        RETURN;
    END;

    DECLARE @Lines TABLE (LineNumber INT, AccountCode NVARCHAR(50), AccountName NVARCHAR(150), CostCenterId INT, CostCenterName NVARCHAR(150),
                          Debit DECIMAL(14,3), Credit DECIMAL(14,3), IsUnmapped BIT, Description NVARCHAR(300),
                          EmployeeId BIGINT, EmployeeNo NVARCHAR(20), EmployeeName NVARCHAR(300), PayrollMonth DATE);
    IF @Mode = 'EMPLOYEE'
        INSERT INTO @Lines SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                                  EmployeeId, EmployeeNo, EmployeeName, PayrollMonth
                           FROM [Payroll].[ufn_PayrollJournalByEmployee](@RunId);
    ELSE
        INSERT INTO @Lines SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                                  NULL, NULL, NULL, @rMonth
                           FROM [Payroll].[ufn_PayrollJournal](@RunId);

    IF NOT EXISTS (SELECT 1 FROM @Lines)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The payroll has no amounts to journal.';
        RETURN;
    END;
    IF (SELECT SUM(Debit) - SUM(Credit) FROM @Lines) <> 0
    BEGIN
        SELECT @ResultCode = 'UNBALANCED', @ResultMessage = N'The journal does not balance. Check the GL mapping and try again.';
        RETURN;
    END;

    DECLARE @Seq INT = (SELECT COUNT(1) FROM [Payroll].[JournalBatches] AS j JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
                        WHERE j.CompanyId = @rCompany AND r.RunMonth = @rMonth) + 1;
    DECLARE @No NVARCHAR(40) = CONCAT(N'JV-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
    WHILE EXISTS (SELECT 1 FROM [Payroll].[JournalBatches] WHERE CompanyId = @rCompany AND JournalNo = @No AND Deleted = 0)
    BEGIN
        SET @Seq += 1;
        SET @No = CONCAT(N'JV-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
    END;

    BEGIN TRAN;
        INSERT INTO [Payroll].[JournalBatches] (CompanyId, PayrollRunId, JournalNo, JournalDate, TotalDebit, TotalCredit, LineCount, UnmappedCount, EntryMode, PayrollMonth, CreatedBy)
        SELECT @rCompany, @RunId, @No, @rPayDate, SUM(Debit), SUM(Credit), COUNT(1), SUM(CASE WHEN IsUnmapped = 1 THEN 1 ELSE 0 END), @Mode, @rMonth, @UserId
        FROM   @Lines;
        SET @NewId = SCOPE_IDENTITY();

        INSERT INTO [Payroll].[JournalLines] (JournalId, LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
                                              EmployeeId, EmployeeNo, EmployeeName, PayrollMonth)
        SELECT @NewId, LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description,
               EmployeeId, EmployeeNo, EmployeeName, PayrollMonth FROM @Lines;
    COMMIT;

    SET @ResultMessage = CASE WHEN @Mode = 'EMPLOYEE' THEN N'Journal created - an entry for each employee.' ELSE N'Journal created.' END;
END;
GO

/* ------------------------------------------------------------------
   Labels (English + Arabic)
   ------------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fin.entry_for', 'fin', N'GL entry for', N'قيد الأستاذ العام لـ', NULL),
        ('fin.entry_company', 'fin', N'Company', N'الشركة', NULL),
        ('fin.entry_employee', 'fin', N'Employee', N'الموظف', NULL),
        ('fin.entry_company_hint', 'fin', N'One entry for the whole payroll.', N'قيد واحد لكامل الرواتب.', NULL),
        ('fin.entry_employee_hint', 'fin', N'A separate entry for each employee, flagged with the payroll month.', N'قيد منفصل لكل موظف، مع إشارة إلى شهر الرواتب.', NULL),
        ('fin.col_employee', 'fin', N'Employee', N'الموظف', NULL),
        ('fin.col_payroll_month', 'fin', N'Payroll month', N'شهر الرواتب', NULL),
        ('fin.entry_n_employees', 'fin', N'{0} employees', N'{0} موظف', NULL),
        ('fin.create_journal_employee_text', 'fin', N'Creates the journal with a separate entry for each employee, flagged with the payroll month. Reverse it to journal the payroll again.', N'ينشئ القيد مع قيد منفصل لكل موظف، مع إشارة إلى شهر الرواتب. اعكسه لإعادة ترحيل الرواتب.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Journal entry mode labels inserted: ', @LabelsInserted);
GO
