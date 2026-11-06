/* =====================================================================
   118_Bank_File_Regenerate_Post_GL.sql  -  generate again freely; Post to GL locks
   ---------------------------------------------------------------------
   Run after db/116 (and db/105). Safe to re-run. It replaces
   Payroll.usp_BankFile_Manage of db/116: run this script again whenever
   db/116 or db/50 is run.

   1. A bank file can be generated again as many times as needed (with the
      reason, kept in the process history): also when its payments are
      already recorded as paid or failed - they go back in the new file - and
      the Ministry Payroll also after the Company Payroll (the Company Payroll
      is then replaced and must be generated again from the new step 1).

   2. Post to GL (Bank File page): the payroll's journal is created when it
      has none, and marked posted with the reference of the entry in the
      books. From then on the payroll's bank files can no longer be generated
      again (a re-issue file of failed payments still can). Reversing the
      journal (Accounting > Payroll Journal) opens them again.
      "Posted to GL" is recorded in the process history (Payroll.BankFileAudit).

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[BankFileAudit]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[JournalBatches]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/105 and db/116 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the audit: "Posted to GL" (no file kind) ------------------------- */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_BankFileAudit_Action' AND definition NOT LIKE N'%GL_POSTED%')
    ALTER TABLE [Payroll].[BankFileAudit] DROP CONSTRAINT CK_BankFileAudit_Action;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_BankFileAudit_Action')
    ALTER TABLE [Payroll].[BankFileAudit] WITH CHECK
        ADD CONSTRAINT CK_BankFileAudit_Action CHECK (ActionCode IN ('GENERATED', 'REGENERATED', 'SENT', 'PAID', 'GL_POSTED'));
GO
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID(N'[Payroll].[BankFileAudit]') AND name = N'FileKind' AND is_nullable = 0)
    ALTER TABLE [Payroll].[BankFileAudit] ALTER COLUMN FileKind VARCHAR(10) NULL;
GO

/* ---- 2. Payroll.usp_BankFile_Manage (db/116) + generate again freely, GL lock, GL_POSTED */
CREATE OR ALTER PROCEDURE [Payroll].[usp_BankFile_Manage]
    @Action                VARCHAR(20),
    @CompanyId             INT             = NULL,
    @CompanyIds            NVARCHAR(2000)  = NULL,
    @Id                    BIGINT          = NULL,
    @RunId                 BIGINT          = NULL,
    @Year                  INT             = NULL,
    @RunMonth              DATE            = NULL,
    @Search                NVARCHAR(200)   = NULL,
    @Status                VARCHAR(12)     = NULL,
    @PageNumber            INT             = 1,
    @PageSize              INT             = 25,

    @Kind                  VARCHAR(10)     = NULL,     -- FULL / RETRY / MINISTRY / COMPANY (db/116: the two-step process)
    @BankId                INT             = NULL,     -- a file for one bank (NULL = every bank)
    @BankFileFormatId      INT             = NULL,
    @CompanyBankAccountId  INT             = NULL,
    @ValueDate             DATE            = NULL,
    @FileName              NVARCHAR(150)   = NULL,
    @Content               NVARCHAR(MAX)   = NULL,
    @RunEmployeeIds        NVARCHAR(MAX)   = NULL,     -- CSV: the employees in the file
    @Reason                NVARCHAR(500)   = NULL,
    @Reference             NVARCHAR(100)   = NULL,

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

    IF @Action NOT IN ('RUNS', 'REVIEW', 'LINES', 'CREATE', 'LIST', 'GET', 'DOWNLOADED', 'MARK_SENT', 'STAGES', 'AUDIT', 'GL_POSTED')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* db/116: FULL = one file of the net pay; MINISTRY then COMPANY = the two-step process
       (step 1 the work permit salary, step 2 the net pay less what step 1 transferred) */
    SET @Kind = CASE UPPER(ISNULL(@Kind, 'FULL')) WHEN 'RETRY' THEN 'RETRY' WHEN 'MINISTRY' THEN 'MINISTRY'
                                                  WHEN 'COMPANY' THEN 'COMPANY' ELSE 'FULL' END;
    /* the payments a file makes: one per employee per stage (FULL, or MINISTRY and COMPANY) */
    DECLARE @Stage VARCHAR(10) = CASE WHEN @Kind IN ('MINISTRY', 'COMPANY') THEN @Kind ELSE 'FULL' END;
    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= RUNS ================================ */
    IF @Action = 'RUNS'
    BEGIN
        SELECT  r.PayrollRunId, r.RunCode, r.RunType, r.RunMonth, r.CompanyId, co.CompanyName, pc.CalendarName,
                pp.StartDate, pp.EndDate, pp.PaymentDate, r.ClosedDate, r.EmployeeCount, r.TotalNet,
                f.FileCount, f.LastFileNo, f.LastFileDate,
                ISNULL(pay.PaidCount, 0) AS PaidCount, ISNULL(pay.FailedCount, 0) AS FailedCount,
                ISNULL(pay.InFileCount, 0) AS InFileCount, ISNULL(pay.RetryCount, 0) AS RetryCount,
                ISNULL(pay.CashPendingCount, 0) AS CashPendingCount
        FROM    [Payroll].[PayrollRuns]      AS r
        JOIN    [Core].[Companies]           AS co ON co.CompanyId = r.CompanyId
        JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
        JOIN    [Payroll].[PayrollPeriods]   AS pp ON pp.PayrollPeriodId = r.PayrollPeriodId
        OUTER APPLY (SELECT COUNT(1) AS FileCount, MAX(bf.FileNo) AS LastFileNo, MAX(bf.CreatedDate) AS LastFileDate
                     FROM [Payroll].[BankFiles] AS bf
                     WHERE bf.PayrollRunId = r.PayrollRunId AND bf.Deleted = 0 AND bf.Status <> 'SUPERSEDED') AS f
        OUTER APPLY (SELECT SUM(CASE WHEN p.Status = 'PAID' THEN 1 ELSE 0 END) AS PaidCount,
                            SUM(CASE WHEN p.Status = 'FAILED' THEN 1 ELSE 0 END) AS FailedCount,
                            SUM(CASE WHEN p.Status = 'IN_FILE' THEN 1 ELSE 0 END) AS InFileCount,
                            SUM(CASE WHEN p.Status = 'PENDING' AND p.Method = 'BANK' THEN 1 ELSE 0 END) AS RetryCount,
                            SUM(CASE WHEN p.Status = 'PENDING' AND p.Method = 'CASH' THEN 1 ELSE 0 END) AS CashPendingCount
                     FROM [Payroll].[BankPayments] AS p WHERE p.PayrollRunId = r.PayrollRunId AND p.Deleted = 0) AS pay
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
        ;WITH f AS (
            SELECT  bf.BankFileId, bf.FileNo, bf.FileKind, bf.FileName, bf.ValueDate, bf.LineCount, bf.TotalAmount, bf.Status, bf.Reason,
                    bf.DownloadCount, bf.SentDate, bf.SentReference, bf.CreatedDate, bf.PayrollRunId, bf.CompanyId,
                    r.RunCode, r.RunMonth, co.CompanyName, fm.FormatName, b.BankName, a.AccountTitle,
                    COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ce.FirstName, N' ', ce.LastName))), N''), cu.Username) AS CreatedByName,
                    (SELECT COUNT(1) FROM [Payroll].[BankPayments] p WHERE p.BankFileId = bf.BankFileId AND p.Deleted = 0 AND p.Status = 'PAID') AS PaidCount,
                    (SELECT COUNT(1) FROM [Payroll].[BankPayments] p WHERE p.BankFileId = bf.BankFileId AND p.Deleted = 0 AND p.Status = 'FAILED') AS FailedCount
            FROM    [Payroll].[BankFiles] AS bf
            JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = bf.PayrollRunId
            JOIN    [Core].[Companies] AS co ON co.CompanyId = bf.CompanyId
            JOIN    [Payroll].[BankFileFormats] AS fm ON fm.BankFileFormatId = bf.BankFileFormatId
            JOIN    [Payroll].[CompanyBankAccounts] AS a ON a.CompanyBankAccountId = bf.CompanyBankAccountId
            LEFT JOIN [Payroll].[Banks] AS b ON b.BankId = bf.BankId
            LEFT JOIN [Security].[Users] AS cu ON cu.UserId = bf.CreatedBy
            LEFT JOIN [Employee].[Employees] AS ce ON ce.EmployeeId = cu.EmployeeId
            WHERE   bf.Deleted = 0
              AND   [Payroll].[ufn_InCompanyScope](bf.CompanyId, @CompanyId, @CompanyIds) = 1
              AND  (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
              AND  (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
              AND  (@RunId IS NULL OR bf.PayrollRunId = @RunId)
              AND  (@Status IS NULL OR bf.Status = @Status)
              AND  (@Pattern IS NULL OR bf.FileNo LIKE @Pattern ESCAPE '\' OR r.RunCode LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\')
        )
        SELECT *, COUNT(1) OVER () AS Total FROM f
        ORDER BY f.CreatedDate DESC, f.BankFileId DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;

        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[BankFiles] AS bf
        JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = bf.PayrollRunId
        LEFT JOIN [Payroll].[Banks] AS b ON b.BankId = bf.BankId
        WHERE  bf.Deleted = 0
          AND  [Payroll].[ufn_InCompanyScope](bf.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
          AND (@RunId IS NULL OR bf.PayrollRunId = @RunId)
          AND (@Status IS NULL OR bf.Status = @Status)
          AND (@Pattern IS NULL OR bf.FileNo LIKE @Pattern ESCAPE '\' OR r.RunCode LIKE @Pattern ESCAPE '\' OR b.BankName LIKE @Pattern ESCAPE '\');
        RETURN;
    END;

    /* ======================= GET / DOWNLOADED / MARK_SENT ======= */
    IF @Action IN ('GET', 'DOWNLOADED', 'MARK_SENT')
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE BankFileId = @Id AND Deleted = 0
                         AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1)
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That bank file no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF @Action = 'GET'
            SELECT bf.BankFileId, bf.FileNo, bf.FileKind, bf.FileName, bf.Content, bf.ValueDate, bf.LineCount, bf.TotalAmount,
                   bf.Status, bf.PayrollRunId, bf.CompanyId, r.RunCode
            FROM   [Payroll].[BankFiles] AS bf JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = bf.PayrollRunId
            WHERE  bf.BankFileId = @Id;
        ELSE IF @Action = 'DOWNLOADED'
            UPDATE [Payroll].[BankFiles] SET DownloadCount = DownloadCount + 1 WHERE BankFileId = @Id;
        ELSE
        BEGIN
            IF EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE BankFileId = @Id AND Status <> 'GENERATED')
            BEGIN
                SELECT @ResultCode = 'INVALID_STATE', @ResultMessage = N'Only a generated file can be marked as sent to the bank.';
                RETURN;
            END;
            UPDATE [Payroll].[BankFiles]
               SET Status = 'SENT', SentBy = @UserId, SentDate = SYSUTCDATETIME(), SentReference = NULLIF(LTRIM(RTRIM(@Reference)), N''),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE BankFileId = @Id;

            /* db/116: the audit of the bank file process */
            INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, BankId, LineCount, TotalAmount, Reference, ActionBy)
            SELECT PayrollRunId, BankFileId, 'SENT', FileKind, FileNo, BankId, LineCount, TotalAmount, SentReference, @UserId
            FROM   [Payroll].[BankFiles] WHERE BankFileId = @Id;
            SET @ResultMessage = N'Bank file marked as sent to the bank.';
        END;
        RETURN;
    END;

    /* ======================= the payroll (REVIEW / LINES / CREATE) */
    DECLARE @rCompany INT, @rMonth DATE, @rCode NVARCHAR(40);
    SELECT  @rCompany = r.CompanyId, @rMonth = r.RunMonth, @rCode = r.RunCode
    FROM    [Payroll].[PayrollRuns] AS r
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0 AND r.Stage = 'CLOSED'
      AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;

    IF @rCompany IS NULL
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'Select a closed payroll - salaries are paid only for a closed payroll.';
        RETURN;
    END;

    /* db/118: the payroll's journal (the latest one not reversed) - once it is POSTED to the GL,
       the bank files can no longer be generated again (a re-issue of failed payments still can) */
    DECLARE @jId BIGINT, @jNo NVARCHAR(40), @jStatus VARCHAR(10), @jRef NVARCHAR(100), @jPosted DATETIME2(0);
    SELECT TOP (1) @jId = j.JournalId, @jNo = j.JournalNo, @jStatus = j.Status, @jRef = j.PostedReference, @jPosted = j.PostedDate
    FROM   [Payroll].[JournalBatches] AS j
    WHERE  j.PayrollRunId = @RunId AND j.Deleted = 0 AND j.Status <> 'REVERSED'
    ORDER BY j.JournalId DESC;

    /* ======================= GL_POSTED =========================== */
    /* db/118: the audit line of "Post to GL" (the journal itself is posted by usp_Journal_Manage) */
    IF @Action = 'GL_POSTED'
    BEGIN
        IF ISNULL(@jStatus, '') <> 'POSTED'
        BEGIN
            SELECT @ResultCode = 'NOT_POSTED', @ResultMessage = N'The journal of this payroll is not posted.';
            RETURN;
        END;
        INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, LineCount, TotalAmount, Reference, ActionBy)
        SELECT @RunId, NULL, 'GL_POSTED', NULL, @jNo, j.LineCount, j.TotalDebit, @jRef, @UserId
        FROM   [Payroll].[JournalBatches] AS j WHERE j.JournalId = @jId;
        SET @ResultMessage = N'Posted to GL - the bank files of this payroll can no longer be generated again.';
        RETURN;
    END;

    /* ======================= AUDIT ============================== */
    /* db/116: what happened to the payroll's bank files - generated (again), sent, paid */
    IF @Action = 'AUDIT'
    BEGIN
        SELECT  a.BankFileAuditId, a.ActionCode, a.FileKind, a.FileNo, a.LineCount, a.TotalAmount, a.Reason, a.Reference, a.ActionDate,
                b.BankName, a.ReplacedFileNos,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username, N'System') AS ActionByName
        FROM    [Payroll].[BankFileAudit] AS a
        LEFT JOIN [Payroll].[Banks] AS b ON b.BankId = a.BankId
        LEFT JOIN [Security].[Users] AS u ON u.UserId = a.ActionBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   a.PayrollRunId = @RunId AND a.Deleted = 0
        ORDER BY a.ActionDate DESC, a.BankFileAuditId DESC;
        RETURN;
    END;

    /* the payees and what each step pays them:
         FULL      the net pay
         MINISTRY  the work permit salary (Kuwait Compliance)
         COMPANY   the net pay less what the Ministry step transferred (its payment, else the
                   work permit salary while step 1 is not generated); nothing when that is
                   zero or less - the Ministry step paid more than the net pay
         RETRY     the re-issued (pending) bank payments, whatever their step */
    DECLARE @Payees TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT, EmployeeNo NVARCHAR(20), EmployeeName NVARCHAR(300),
                           BankId INT, Iban NVARCHAR(34), Method VARCHAR(6), NetPay DECIMAL(12,3), Wps DECIMAL(12,3),
                           MinistryPaid DECIMAL(12,3), StagePayMethod VARCHAR(6), StagePayId BIGINT,
                           RetryAmount DECIMAL(12,3), RetryCount INT);
    INSERT INTO @Payees
    SELECT  p.RunEmployeeId, p.EmployeeId, p.EmployeeNo, p.EmployeeName, p.BankId, p.Iban, p.Method, p.NetPay,
            NULLIF(k.WorkPermitSalary, 0), mp.Amount, sp.Method, sp.BankPaymentId, rp.Amount, ISNULL(rp.Cnt, 0)
    FROM    [Payroll].[ufn_RunPayees](@RunId) AS p
    LEFT JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = p.EmployeeId AND k.Deleted = 0
    OUTER APPLY (SELECT TOP (1) x.Amount FROM [Payroll].[BankPayments] AS x
                 WHERE x.PayrollRunId = @RunId AND x.EmployeeId = p.EmployeeId AND x.Deleted = 0 AND x.Stage = 'MINISTRY') AS mp
    OUTER APPLY (SELECT TOP (1) x.BankPaymentId, x.Method FROM [Payroll].[BankPayments] AS x
                 WHERE x.PayrollRunId = @RunId AND x.EmployeeId = p.EmployeeId AND x.Deleted = 0 AND x.Stage = @Stage) AS sp
    OUTER APPLY (SELECT SUM(x.Amount) AS Amount, COUNT(1) AS Cnt FROM [Payroll].[BankPayments] AS x
                 WHERE x.PayrollRunId = @RunId AND x.EmployeeId = p.EmployeeId AND x.Deleted = 0
                   AND x.Method = 'BANK' AND x.Status = 'PENDING') AS rp;

    /* ======================= STAGES ============================= */
    /* db/116: the payroll's process - which mode it is paid in, and the two steps */
    IF @Action = 'STAGES'
    BEGIN
        SELECT  CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind IN ('MINISTRY', 'COMPANY'))
                       OR EXISTS (SELECT 1 FROM [Payroll].[BankPayments] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage IN ('MINISTRY', 'COMPANY'))
                     THEN 'STAGED'
                     WHEN EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'FULL')
                       OR EXISTS (SELECT 1 FROM [Payroll].[BankPayments] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage = 'FULL' AND Method = 'BANK')
                     THEN 'SINGLE' ELSE 'NONE' END AS Mode,
                /* step 1 */
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' THEN ISNULL(x.MinistryPaid, x.Wps) END), 0)                AS MinistryAmount,
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND ISNULL(x.MinistryPaid, x.Wps) > 0 THEN 1 ELSE 0 END), 0) AS MinistryCount,
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND x.Wps IS NULL AND x.MinistryPaid IS NULL THEN 1 ELSE 0 END), 0) AS MissingWpsCount,
                (SELECT STRING_AGG(CONCAT(m.EmployeeNo, N' ', m.EmployeeName), N', ')
                 FROM (SELECT TOP (5) y.EmployeeNo, y.EmployeeName FROM @Payees y
                       WHERE y.Method = 'BANK' AND y.Wps IS NULL AND y.MinistryPaid IS NULL ORDER BY y.EmployeeNo) AS m)  AS MissingWpsNames,
                /* step 2 */
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) > 0
                                THEN x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) END), 0)               AS CompanyAmount,
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) > 0 THEN 1 ELSE 0 END), 0) AS CompanyCount,
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) < 0 THEN 1 ELSE 0 END), 0) AS OverCount,
                ISNULL(SUM(CASE WHEN x.Method = 'BANK' AND x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) < 0
                                THEN ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0)) - x.NetPay END), 0)               AS OverAmount,
                ISNULL(SUM(CASE WHEN x.Method = 'CASH' THEN 1 ELSE 0 END), 0)                                     AS CashCount,
                ISNULL(SUM(CASE WHEN x.Method = 'CASH' THEN x.NetPay END), 0)                                     AS CashAmount,
                /* the live files of each step */
                (SELECT COUNT(1) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'MINISTRY') AS MinistryFiles,
                (SELECT STRING_AGG(f.FileNo, N', ') FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'MINISTRY') AS MinistryFileNos,
                (SELECT SUM(f.TotalAmount) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'MINISTRY') AS MinistryFileAmount,
                (SELECT COUNT(1) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'COMPANY') AS CompanyFiles,
                (SELECT STRING_AGG(f.FileNo, N', ') FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'COMPANY') AS CompanyFileNos,
                (SELECT SUM(f.TotalAmount) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'COMPANY') AS CompanyFileAmount,
                (SELECT COUNT(1) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'FULL') AS FullFiles,
                /* db/118: the payroll's journal - posted to the GL = the bank files are locked */
                @jId AS JournalId, @jNo AS JournalNo, @jStatus AS JournalStatus, @jRef AS GlReference, @jPosted AS GlPostedDate
        FROM    @Payees AS x;
        RETURN;
    END;

    DECLARE @Candidates TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT, BankId INT, Iban NVARCHAR(34), Amount DECIMAL(12,3));
    INSERT INTO @Candidates (RunEmployeeId, EmployeeId, BankId, Iban, Amount)
    SELECT  x.RunEmployeeId, x.EmployeeId, x.BankId, x.Iban,
            CASE @Kind WHEN 'MINISTRY' THEN ISNULL(x.Wps, 0)
                       WHEN 'COMPANY'  THEN x.NetPay - ISNULL(x.MinistryPaid, ISNULL(x.Wps, 0))
                       WHEN 'RETRY'    THEN x.RetryAmount
                       ELSE x.NetPay END
    FROM    @Payees AS x
    WHERE   x.Method = 'BANK'
      AND  (@BankId IS NULL OR x.BankId = @BankId)
      AND  (   (@Kind <> 'RETRY' AND (x.StagePayId IS NULL OR x.StagePayMethod = 'BANK'))
            OR (@Kind = 'RETRY' AND x.RetryCount > 0));

    /* step 2: a negative or zero transfer is left out (step 1 paid the net pay or more);
       step 1: an employee with no work permit salary has nothing to transfer (CREATE refuses) */
    DELETE FROM @Candidates WHERE @Kind IN ('MINISTRY', 'COMPANY') AND Amount <= 0;

    IF @Action = 'REVIEW'
    BEGIN
        SELECT  'BANK' AS Method, c.BankId, MAX(p.BankName) AS BankName, MAX(p.WpsBankCode) AS WpsBankCode,
                CAST(CASE WHEN EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] f WHERE f.BankId = c.BankId AND f.IsActive = 1 AND f.Deleted = 0)
                          THEN 1 ELSE 0 END AS BIT) AS HasOwnFormat,
                COUNT(1) AS EmployeeCount, SUM(c.Amount) AS Amount
        FROM    @Candidates AS c
        JOIN    [Payroll].[ufn_RunPayees](@RunId) AS p ON p.RunEmployeeId = c.RunEmployeeId
        GROUP BY c.BankId
        UNION ALL
        SELECT  'CASH', NULL, NULL, NULL, CAST(0 AS BIT), COUNT(1), ISNULL(SUM(p.NetPay), 0)
        FROM    [Payroll].[ufn_RunPayees](@RunId) AS p
        WHERE   p.Method = 'CASH' AND @Kind IN ('FULL', 'COMPANY') AND @BankId IS NULL
        HAVING  COUNT(1) > 0
        ORDER BY 1, 4 DESC;
        RETURN;
    END;

    IF @Action = 'LINES'
    BEGIN
        SELECT  p.RunEmployeeId, p.EmployeeId, p.EmployeeNo, p.EmployeeName, p.CivilId, p.Iban, p.BankId, p.BankName,
                p.WpsBankCode, p.SwiftCode,
                c.Amount AS NetPay,      -- db/116: the amount this file transfers (net pay, the step's amount or the re-issue)
                p.SalaryTotal, p.EarningsTotal, p.DeductionsTotal
        FROM    @Candidates AS c
        JOIN    [Payroll].[ufn_RunPayees](@RunId) AS p ON p.RunEmployeeId = c.RunEmployeeId
        ORDER BY p.BankName, p.EmployeeNo;
        RETURN;
    END;

    /* ======================= CREATE ============================== */
    DECLARE @Picked TABLE (RunEmployeeId BIGINT PRIMARY KEY);
    INSERT INTO @Picked (RunEmployeeId)
    SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@RunEmployeeIds, N''), ',') WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

    /* db/118: once the payroll is posted to the GL its bank files are final */
    IF @Kind <> 'RETRY' AND @jStatus = 'POSTED'
    BEGIN
        SELECT @ResultCode = 'GL_POSTED', @ResultMessage = CONCAT(N'This payroll is posted to the GL (', @jNo, N') - its bank file cannot be generated again.');
        RETURN;
    END;

    /* db/116: one way of paying a payroll - one file of the net pay, or the two steps */
    IF @Kind = 'FULL'
       AND EXISTS (SELECT 1 FROM [Payroll].[BankPayments] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage IN ('MINISTRY', 'COMPANY'))
    BEGIN
        SELECT @ResultCode = 'MODE', @ResultMessage = N'This payroll is paid in two steps (Ministry Payroll, then Company Payroll) - generate its files there.';
        RETURN;
    END;
    IF @Kind IN ('MINISTRY', 'COMPANY')
       AND EXISTS (SELECT 1 FROM [Payroll].[BankPayments] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage = 'FULL' AND Method = 'BANK')
    BEGIN
        SELECT @ResultCode = 'MODE', @ResultMessage = N'This payroll is already paid with a single bank file - the two-step process cannot be used for it.';
        RETURN;
    END;
    IF @Kind = 'MINISTRY'
       AND EXISTS (SELECT 1 FROM @Payees WHERE Method = 'BANK' AND (@BankId IS NULL OR BankId = @BankId) AND Wps IS NULL)
    BEGIN
        SELECT @ResultCode = 'WPS_MISSING',
               @ResultMessage = LEFT(CONCAT(N'Enter the Work Permit Salary of every employee first (Employee > Kuwait Compliance): ',
                   (SELECT STRING_AGG(CONCAT(m.EmployeeNo, N' ', m.EmployeeName), N', ')
                    FROM (SELECT TOP (5) EmployeeNo, EmployeeName FROM @Payees
                          WHERE Method = 'BANK' AND (@BankId IS NULL OR BankId = @BankId) AND Wps IS NULL ORDER BY EmployeeNo) AS m),
                   CASE WHEN (SELECT COUNT(1) FROM @Payees WHERE Method = 'BANK' AND (@BankId IS NULL OR BankId = @BankId) AND Wps IS NULL) > 5
                        THEN N' ...' ELSE N'' END, N'.'), 400);
        RETURN;
    END;
    /* db/118: the Ministry Payroll can be generated again after the Company Payroll: the
       Company Payroll is then replaced too (it must be generated again from the new step 1) */
    IF @Kind = 'COMPANY'
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'MINISTRY')
    BEGIN
        SELECT @ResultCode = 'STEP1', @ResultMessage = N'Generate the Ministry Payroll first - the Company Payroll transfers what is left after it.';
        RETURN;
    END;

    IF NOT EXISTS (SELECT 1 FROM @Picked)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'There is nobody to pay in this file.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM @Picked AS k WHERE NOT EXISTS (SELECT 1 FROM @Candidates AS c WHERE c.RunEmployeeId = k.RunEmployeeId))
    BEGIN
        SELECT @ResultCode = 'CHANGED', @ResultMessage = N'The payments changed while the file was being prepared. Refresh and generate it again.';
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] WHERE BankFileFormatId = @BankFileFormatId AND IsActive = 1 AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select an active bank format.';
        RETURN;
    END;
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[CompanyBankAccounts]
                   WHERE CompanyBankAccountId = @CompanyBankAccountId AND CompanyId = @rCompany AND IsActive = 1 AND Deleted = 0)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select an active salary account of the payroll''s company.';
        RETURN;
    END;
    IF @ValueDate IS NULL OR NULLIF(LTRIM(RTRIM(@FileName)), N'') IS NULL OR @Content IS NULL
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The value date, file name and file content are required.';
        RETURN;
    END;

    /* a FULL / MINISTRY / COMPANY file replaces the live file(s) of the same kind and scope (all banks / that bank) */
    DECLARE @Replaced TABLE (BankFileId BIGINT PRIMARY KEY);
    IF @Kind <> 'RETRY'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[BankFiles]
                   WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = @Kind
                     AND ((BankId IS NULL AND @BankId IS NOT NULL) OR (BankId IS NOT NULL AND @BankId IS NULL)))
        BEGIN
            SELECT @ResultCode = 'SCOPE', @ResultMessage = N'This payroll already has a file for a different bank choice. Generate it again with the same bank choice.';
            RETURN;
        END;

        INSERT INTO @Replaced (BankFileId)
        SELECT BankFileId FROM [Payroll].[BankFiles]
        WHERE  PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = @Kind
          AND  ISNULL(BankId, 0) = ISNULL(@BankId, 0);

        IF EXISTS (SELECT 1 FROM @Replaced)
        BEGIN
            IF NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
            BEGIN
                SELECT @ResultCode = 'REASON_REQUIRED', @ResultMessage = N'A file was already generated for this payroll. Enter the reason for generating it again.';
                RETURN;
            END;
            /* db/118: no limit on generating a file again (until the payroll is posted to the GL);
               payments already recorded as paid or failed go back in the new file */
        END;
    END;

    DECLARE @Seq INT = (SELECT COUNT(1) FROM [Payroll].[BankFiles] AS bf
                        JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = bf.PayrollRunId
                        WHERE bf.CompanyId = @rCompany AND r.RunMonth = @rMonth) + 1;
    DECLARE @Prefix NVARCHAR(4) = CASE @Kind WHEN 'MINISTRY' THEN N'MIN' WHEN 'COMPANY' THEN N'CMP' ELSE N'WPS' END;   -- db/116
    DECLARE @FileNo NVARCHAR(40) = CONCAT(@Prefix, N'-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
    WHILE EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE CompanyId = @rCompany AND FileNo = @FileNo AND Deleted = 0)
    BEGIN
        SET @Seq += 1;
        SET @FileNo = CONCAT(@Prefix, N'-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
    END;

    /* db/118: step 1 generated again - the Company Payroll made from the old step 1 goes too */
    DECLARE @StepTwo TABLE (BankFileId BIGINT PRIMARY KEY);
    IF @Kind = 'MINISTRY'
        INSERT INTO @StepTwo (BankFileId)
        SELECT BankFileId FROM [Payroll].[BankFiles]
        WHERE  PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'COMPANY';

    BEGIN TRAN;
        UPDATE bf SET Status = 'SUPERSEDED', ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM [Payroll].[BankFiles] AS bf JOIN @Replaced AS x ON x.BankFileId = bf.BankFileId;

        IF EXISTS (SELECT 1 FROM @StepTwo)
        BEGIN
            UPDATE bf SET Status = 'SUPERSEDED', ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
            FROM [Payroll].[BankFiles] AS bf JOIN @StepTwo AS x ON x.BankFileId = bf.BankFileId;
            /* its bank payments are made again by the next Company Payroll (cash ones stay) */
            UPDATE p SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
            FROM [Payroll].[BankPayments] AS p
            WHERE p.PayrollRunId = @RunId AND p.Deleted = 0 AND p.Stage = 'COMPANY' AND p.Method = 'BANK';
        END;

        /* employees of a replaced file who are not in the new one wait for a file again */
        UPDATE p SET Status = 'PENDING', BankFileId = NULL, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM [Payroll].[BankPayments] AS p JOIN @Replaced AS x ON x.BankFileId = p.BankFileId
        WHERE p.Deleted = 0 AND p.Status = 'IN_FILE'
          AND NOT EXISTS (SELECT 1 FROM @Picked AS k WHERE k.RunEmployeeId = p.RunEmployeeId);

        INSERT INTO [Payroll].[BankFiles]
            (CompanyId, PayrollRunId, FileNo, FileKind, BankFileFormatId, CompanyBankAccountId, BankId, ValueDate, FileName, Content,
             LineCount, TotalAmount, Reason, CreatedBy)
        SELECT @rCompany, @RunId, @FileNo, @Kind, @BankFileFormatId, @CompanyBankAccountId, @BankId, @ValueDate, LTRIM(RTRIM(@FileName)), @Content,
               COUNT(1), SUM(c.Amount), NULLIF(LTRIM(RTRIM(@Reason)), N''), @UserId
        FROM   @Candidates AS c JOIN @Picked AS k ON k.RunEmployeeId = c.RunEmployeeId;
        SET @NewId = SCOPE_IDENTITY();

        /* the payments of the file: FULL / MINISTRY / COMPANY - the employee's payment of that
           step; RETRY - every re-issued (pending) bank payment of the employee, whatever its step */
        UPDATE p
           SET Amount = CASE WHEN @Kind = 'RETRY' THEN p.Amount ELSE c.Amount END,
               Method = 'BANK', BankId = c.BankId, Iban = c.Iban, BankFileId = @NewId, Status = 'IN_FILE',
               FailureReason = NULL, PaidDate = NULL, Reference = NULL,     -- db/118: a file generated again starts again
               AttemptCount = p.AttemptCount + 1, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM   [Payroll].[BankPayments] AS p
        JOIN   @Candidates AS c ON c.EmployeeId = p.EmployeeId
        JOIN   @Picked AS k ON k.RunEmployeeId = c.RunEmployeeId
        WHERE  p.PayrollRunId = @RunId AND p.Deleted = 0
          AND (   (@Kind <> 'RETRY' AND p.Stage = @Stage)
               OR (@Kind = 'RETRY' AND p.Method = 'BANK' AND p.Status = 'PENDING'));

        INSERT INTO [Payroll].[BankPayments] (PayrollRunId, RunEmployeeId, EmployeeId, Amount, Method, BankId, Iban, BankFileId, Status, AttemptCount, Stage, CreatedBy)
        SELECT @RunId, c.RunEmployeeId, c.EmployeeId, c.Amount, 'BANK', c.BankId, c.Iban, @NewId, 'IN_FILE', 1, @Stage, @UserId
        FROM   @Candidates AS c JOIN @Picked AS k ON k.RunEmployeeId = c.RunEmployeeId
        WHERE  @Kind <> 'RETRY'
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS p
                           WHERE p.PayrollRunId = @RunId AND p.EmployeeId = c.EmployeeId AND p.Deleted = 0 AND p.Stage = @Stage);

        /* the employees with no IBAN go on the register as cash / cheque payments of the net pay
           (single file, or step 2 of the two steps) */
        INSERT INTO [Payroll].[BankPayments] (PayrollRunId, RunEmployeeId, EmployeeId, Amount, Method, Status, Stage, CreatedBy)
        SELECT @RunId, p.RunEmployeeId, p.EmployeeId, p.NetPay, 'CASH', 'PENDING', @Stage, @UserId
        FROM   [Payroll].[ufn_RunPayees](@RunId) AS p
        WHERE  p.Method = 'CASH' AND @Kind IN ('FULL', 'COMPANY')
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS x WHERE x.PayrollRunId = @RunId AND x.EmployeeId = p.EmployeeId AND x.Deleted = 0);

        /* db/116: the audit of the bank file process */
        INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, BankId, LineCount, TotalAmount, Reason, ReplacedFileNos, ActionBy)
        SELECT @RunId, bf.BankFileId, CASE WHEN EXISTS (SELECT 1 FROM @Replaced) OR EXISTS (SELECT 1 FROM @StepTwo) THEN 'REGENERATED' ELSE 'GENERATED' END,
               bf.FileKind, bf.FileNo, bf.BankId, bf.LineCount, bf.TotalAmount, bf.Reason,
               (SELECT STRING_AGG(o.FileNo, N', ') FROM [Payroll].[BankFiles] o
                 WHERE o.BankFileId IN (SELECT BankFileId FROM @Replaced UNION SELECT BankFileId FROM @StepTwo)),
               @UserId
        FROM   [Payroll].[BankFiles] AS bf WHERE bf.BankFileId = @NewId;
    COMMIT;

    SET @ResultMessage = CASE @Kind WHEN 'MINISTRY' THEN N'Ministry Payroll file generated.'
                                    WHEN 'COMPANY' THEN N'Company Payroll file generated.'
                                    ELSE N'Bank file generated.' END;
END;
GO


/* ---- 3. labels (English + Arabic) ----------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fin.post_gl', 'fin', N'Post to GL', N'الترحيل إلى دفتر الأستاذ', NULL),
        ('fin.post_gl_title', 'fin', N'Post to GL', N'الترحيل إلى دفتر الأستاذ', NULL),
        ('fin.post_gl_text', 'fin', N'The payroll journal is created (if needed) and marked as posted in the books. After that the bank files of this payroll can no longer be generated again.', N'يُنشأ قيد الرواتب (عند الحاجة) ويُسجّل كمرحَّل في الدفاتر. بعد ذلك لا يمكن إعادة إنشاء ملفات البنك لهذه الرواتب.', NULL),
        ('fin.post_gl_ref', 'fin', N'Reference of the entry in the books', N'مرجع القيد في الدفاتر', NULL),
        ('fin.post_gl_hint', 'fin', N'Once posted to the GL, the bank files can no longer be generated again.', N'بعد الترحيل إلى دفتر الأستاذ لا يمكن إعادة إنشاء ملفات البنك.', NULL),
        ('fin.post_gl_needs_file', 'fin', N'Generate the bank file first (both steps in the two-step process).', N'أنشئ ملف البنك أولاً (الخطوتان في طريقة الخطوتين).', NULL),
        ('fin.gl_posted_0_1_2', 'fin', N'Posted to GL · {0} · reference {1} · {2}. The bank files can no longer be generated again.', N'تم الترحيل إلى دفتر الأستاذ · {0} · المرجع {1} · {2}. لا يمكن إعادة إنشاء ملفات البنك.', NULL),
        ('fin.gl_locked', 'fin', N'Posted to GL - the bank file cannot be generated again. Reverse the journal on Accounting > Payroll Journal to change it.', N'مرحَّل إلى دفتر الأستاذ - لا يمكن إعادة إنشاء ملف البنك. اعكس القيد من المحاسبة > قيد الرواتب لتغييره.', NULL),
        ('fin.audit_gl_posted', 'fin', N'Posted to GL', N'رُحّل إلى دفتر الأستاذ', NULL),
        ('fin.step1_regen_note', 'fin', N'Generating it again also replaces the Company Payroll - generate step 2 again afterwards.', N'إعادة إنشائها تستبدل رواتب الشركة أيضاً - أعد إنشاء الخطوة 2 بعدها.', NULL),
        ('msg.bf_gl_posted_done', 'msg', N'Posted to GL - the bank files of this payroll can no longer be generated again.', N'تم الترحيل إلى دفتر الأستاذ - لا يمكن إعادة إنشاء ملفات البنك لهذه الرواتب.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Bank file / GL labels inserted: ', @LabelsInserted);
GO
