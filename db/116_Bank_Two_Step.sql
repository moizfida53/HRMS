/* =====================================================================
   116_Bank_Two_Step.sql  -  Bank File: Ministry Payroll, then Company Payroll
   ---------------------------------------------------------------------
   Run after db/50, db/82 and db/95. Safe to re-run. It replaces
   Payroll.usp_BankFile_Manage and Payroll.usp_BankPayment_Manage (db/50)
   and Employee.usp_EmployeeCompleteness (db/95): run this script again
   whenever one of those is run.

   A closed payroll is paid to the bank in one of two ways (chosen on
   Bank Processing > Bank File; once a file is made the payroll keeps it):

     Single file     one file of every employee's net pay (as before).

     Two steps       1. Ministry Payroll - each employee's Work Permit
                        Salary (Kuwait Compliance).
                     2. Company Payroll  - only after step 1: the net pay
                        less what step 1 transferred. When step 1 paid the
                        net pay or more, nothing is transferred (no negative
                        amounts). Employees with no IBAN are paid their net
                        pay by cash / cheque with this step.

   Each employee has one payment per step (Payroll.BankPayments.Stage =
   FULL / MINISTRY / COMPANY), each with its own status on the Payment
   Register (paid, failed, re-issue). A re-issue file takes the failed
   payments of any step.

   Audit: Payroll.BankFileAudit keeps every file generated, generated again
   (with the reason and the files it replaced), sent to the bank and paid -
   shown as "Process history" on the Bank File page.

   The Work Permit Salary is now mandatory for every employee (Kuwaiti
   nationals too): the profile asks for it and the Employees list flags it.
   Step 1 refuses to run while an employee in it has none.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[BankPayments]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[usp_BankFile_Manage]', N'P') IS NULL
   OR COL_LENGTH(N'Kuwait.EmployeeCompliance', N'WorkPermitSalary') IS NULL OR OBJECT_ID(N'[Employee].[usp_EmployeeCompleteness]', N'P') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/50, db/82 and db/95 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the file kinds and the payment steps ------------------------------ */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_BankFiles_Kind' AND definition NOT LIKE N'%MINISTRY%')
    ALTER TABLE [Payroll].[BankFiles] DROP CONSTRAINT CK_BankFiles_Kind;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_BankFiles_Kind')
    ALTER TABLE [Payroll].[BankFiles] WITH CHECK
        ADD CONSTRAINT CK_BankFiles_Kind CHECK (FileKind IN ('FULL', 'RETRY', 'MINISTRY', 'COMPANY'));
GO

IF COL_LENGTH(N'Payroll.BankPayments', N'Stage') IS NULL
    ALTER TABLE [Payroll].[BankPayments] ADD Stage VARCHAR(10) NOT NULL
        CONSTRAINT DF_BankPayments_Stage DEFAULT ('FULL')
        CONSTRAINT CK_BankPayments_Stage CHECK (Stage IN ('FULL', 'MINISTRY', 'COMPANY'));
GO

/* one payment per employee per step (it was one per employee) */
IF EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_BankPayments_Employee' AND object_id = OBJECT_ID(N'[Payroll].[BankPayments]'))
    DROP INDEX UX_BankPayments_Employee ON [Payroll].[BankPayments];
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_BankPayments_EmployeeStage' AND object_id = OBJECT_ID(N'[Payroll].[BankPayments]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankPayments_EmployeeStage
        ON [Payroll].[BankPayments](PayrollRunId, EmployeeId, Stage) WHERE Deleted = 0;
GO

/* ---- 2. the audit of the bank file process -------------------------------- */
IF OBJECT_ID(N'[Payroll].[BankFileAudit]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[BankFileAudit](
        BankFileAuditId  BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BankFileAudit PRIMARY KEY,
        PayrollRunId     BIGINT         NOT NULL,
        BankFileId       BIGINT         NULL,
        ActionCode       VARCHAR(12)    NOT NULL,           -- GENERATED / REGENERATED / SENT / PAID
        FileKind         VARCHAR(10)    NOT NULL,           -- FULL / RETRY / MINISTRY / COMPANY
        FileNo           NVARCHAR(40)   NULL,
        BankId           INT            NULL,
        LineCount        INT            NULL,
        TotalAmount      DECIMAL(14,3)  NULL,
        Reason           NVARCHAR(500)  NULL,               -- why it was generated again
        Reference        NVARCHAR(100)  NULL,               -- the bank's reference when sent
        ReplacedFileNos  NVARCHAR(400)  NULL,               -- the files a new one replaced
        ActionBy         BIGINT         NULL,
        ActionDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_BankFileAudit_ActionDate DEFAULT (SYSUTCDATETIME()),
        Deleted          BIT            NOT NULL CONSTRAINT DF_Payroll_BankFileAudit_Deleted DEFAULT (0),
        DeletedBy        BIGINT         NULL,
        DeletedDate      DATETIME2(7)   NULL,

        CONSTRAINT FK_BankFileAudit_Run  FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_BankFileAudit_File FOREIGN KEY (BankFileId)   REFERENCES [Payroll].[BankFiles](BankFileId),
        CONSTRAINT CK_BankFileAudit_Action CHECK (ActionCode IN ('GENERATED', 'REGENERATED', 'SENT', 'PAID'))
    );
    CREATE INDEX IX_BankFileAudit_Run ON [Payroll].[BankFileAudit](PayrollRunId, ActionDate DESC) WHERE Deleted = 0;

    /* the files made before this script: their generation (and sending) as history */
    INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, BankId, LineCount, TotalAmount, Reason, ActionBy, ActionDate)
    SELECT PayrollRunId, BankFileId, CASE WHEN Reason IS NULL THEN 'GENERATED' ELSE 'REGENERATED' END, FileKind, FileNo, BankId,
           LineCount, TotalAmount, Reason, CreatedBy, CreatedDate
    FROM   [Payroll].[BankFiles] WHERE Deleted = 0;
    INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, BankId, LineCount, TotalAmount, Reference, ActionBy, ActionDate)
    SELECT PayrollRunId, BankFileId, 'SENT', FileKind, FileNo, BankId, LineCount, TotalAmount, SentReference, SentBy, SentDate
    FROM   [Payroll].[BankFiles] WHERE Deleted = 0 AND SentDate IS NOT NULL;
END;
GO

/* ---- 3. Payroll.usp_BankFile_Manage (db/50) + MINISTRY / COMPANY, STAGES, AUDIT */
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

    IF @Action NOT IN ('RUNS', 'REVIEW', 'LINES', 'CREATE', 'LIST', 'GET', 'DOWNLOADED', 'MARK_SENT', 'STAGES', 'AUDIT')
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
                (SELECT SUM(f.TotalAmount) FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = @RunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED' AND f.FileKind = 'COMPANY') AS CompanyFileAmount
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
    IF @Kind = 'MINISTRY'
       AND EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'COMPANY')
    BEGIN
        SELECT @ResultCode = 'STEP2_DONE', @ResultMessage = N'The Company Payroll is already generated from this Ministry Payroll - the Ministry Payroll cannot be generated again.';
        RETURN;
    END;
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
            IF EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS p JOIN @Replaced AS x ON x.BankFileId = p.BankFileId
                       WHERE p.Deleted = 0 AND p.Status IN ('PAID', 'FAILED'))
            BEGIN
                SELECT @ResultCode = 'IN_USE', @ResultMessage = N'Payments of the current file are already recorded as paid or failed - it cannot be replaced. Re-issue the failed payments instead.';
                RETURN;
            END;
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

    BEGIN TRAN;
        UPDATE bf SET Status = 'SUPERSEDED', ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM [Payroll].[BankFiles] AS bf JOIN @Replaced AS x ON x.BankFileId = bf.BankFileId;

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
               FailureReason = NULL, AttemptCount = p.AttemptCount + 1, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
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
        SELECT @RunId, bf.BankFileId, CASE WHEN EXISTS (SELECT 1 FROM @Replaced) THEN 'REGENERATED' ELSE 'GENERATED' END,
               bf.FileKind, bf.FileNo, bf.BankId, bf.LineCount, bf.TotalAmount, bf.Reason,
               (SELECT STRING_AGG(o.FileNo, N', ') FROM [Payroll].[BankFiles] o JOIN @Replaced r ON r.BankFileId = o.BankFileId),
               @UserId
        FROM   [Payroll].[BankFiles] AS bf WHERE bf.BankFileId = @NewId;
    COMMIT;

    SET @ResultMessage = CASE @Kind WHEN 'MINISTRY' THEN N'Ministry Payroll file generated.'
                                    WHEN 'COMPANY' THEN N'Company Payroll file generated.'
                                    ELSE N'Bank file generated.' END;
END;
GO


/* ---- 4. Payroll.usp_BankPayment_Manage (db/50) + Stage, the audit of a file paid */
CREATE OR ALTER PROCEDURE [Payroll].[usp_BankPayment_Manage]
    @Action                VARCHAR(20),
    @CompanyId             INT             = NULL,
    @CompanyIds            NVARCHAR(2000)  = NULL,
    @RunId                 BIGINT          = NULL,
    @Year                  INT             = NULL,
    @RunMonth              DATE            = NULL,
    @Status                VARCHAR(8)      = NULL,
    @Method                VARCHAR(6)      = NULL,
    @BankId                INT             = NULL,
    @FileId                BIGINT          = NULL,
    @Search                NVARCHAR(200)   = NULL,
    @PageNumber            INT             = 1,
    @PageSize              INT             = 25,

    @Ids                   NVARCHAR(MAX)   = NULL,     -- CSV of BankPaymentId
    @Reference             NVARCHAR(100)   = NULL,
    @Reason                NVARCHAR(300)   = NULL,
    @PaidDate              DATE            = NULL,

    @UserId                BIGINT          = NULL,
    @TotalCount            INT             = NULL OUTPUT,
    @NewId                 BIGINT          = NULL OUTPUT,
    @ResultCode            VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage         NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'SUMMARY', 'SET_STATUS', 'REISSUE', 'FILE_PAID')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    IF @Action IN ('LIST', 'SUMMARY')
    BEGIN
        DECLARE @Rows TABLE (BankPaymentId BIGINT PRIMARY KEY, Status VARCHAR(8), Method VARCHAR(6), Amount DECIMAL(12,3), SortKey NVARCHAR(400));
        INSERT INTO @Rows (BankPaymentId, Status, Method, Amount, SortKey)
        SELECT  p.BankPaymentId, p.Status, p.Method, p.Amount, CONCAT(CONVERT(CHAR(10), r.RunMonth, 120), r.RunCode, re.EmployeeNo)
        FROM    [Payroll].[BankPayments] AS p
        JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = p.PayrollRunId
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = p.RunEmployeeId
        LEFT JOIN [Payroll].[BankFiles] AS bf ON bf.BankFileId = p.BankFileId
        WHERE   p.Deleted = 0
          AND   [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
          AND  (@Year IS NULL OR YEAR(r.RunMonth) = @Year)
          AND  (@RunMonth IS NULL OR r.RunMonth = @RunMonth)
          AND  (@RunId IS NULL OR p.PayrollRunId = @RunId)
          AND  (@Method IS NULL OR p.Method = @Method)
          AND  (@BankId IS NULL OR p.BankId = @BankId)
          AND  (@FileId IS NULL OR p.BankFileId = @FileId)
          AND  (@Action = 'SUMMARY' OR @Status IS NULL OR p.Status = @Status)
          AND  (@Pattern IS NULL OR re.EmployeeName LIKE @Pattern ESCAPE '\' OR re.EmployeeNo LIKE @Pattern ESCAPE '\'
                OR p.Reference LIKE @Pattern ESCAPE '\' OR bf.FileNo LIKE @Pattern ESCAPE '\');

        IF @Action = 'SUMMARY'
        BEGIN
            SELECT  COUNT(1) AS TotalCount, ISNULL(SUM(Amount), 0) AS TotalAmount,
                    ISNULL(SUM(CASE WHEN Status = 'PAID' THEN 1 ELSE 0 END), 0) AS PaidCount,
                    ISNULL(SUM(CASE WHEN Status = 'PAID' THEN Amount END), 0) AS PaidAmount,
                    ISNULL(SUM(CASE WHEN Status = 'IN_FILE' THEN 1 ELSE 0 END), 0) AS InFileCount,
                    ISNULL(SUM(CASE WHEN Status = 'IN_FILE' THEN Amount END), 0) AS InFileAmount,
                    ISNULL(SUM(CASE WHEN Status = 'FAILED' THEN 1 ELSE 0 END), 0) AS FailedCount,
                    ISNULL(SUM(CASE WHEN Status = 'FAILED' THEN Amount END), 0) AS FailedAmount,
                    ISNULL(SUM(CASE WHEN Status = 'PENDING' THEN 1 ELSE 0 END), 0) AS PendingCount,
                    ISNULL(SUM(CASE WHEN Status = 'PENDING' THEN Amount END), 0) AS PendingAmount
            FROM    @Rows;
            RETURN;
        END;

        SELECT @TotalCount = COUNT(1) FROM @Rows;

        SELECT  p.BankPaymentId, p.PayrollRunId, p.EmployeeId, p.Amount, p.Method, p.Status, p.Stage, p.Iban, p.Reference, p.FailureReason,
                p.PaidDate, p.AttemptCount, p.BankFileId, bf.FileNo, b.BankName, r.RunCode, r.RunMonth, r.CompanyId,
                re.EmployeeNo, re.EmployeeName, re.DepartmentName
        FROM    @Rows AS x
        JOIN    [Payroll].[BankPayments] AS p ON p.BankPaymentId = x.BankPaymentId
        JOIN    [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = p.PayrollRunId
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = p.RunEmployeeId
        LEFT JOIN [Payroll].[BankFiles] AS bf ON bf.BankFileId = p.BankFileId
        LEFT JOIN [Payroll].[Banks] AS b ON b.BankId = p.BankId
        ORDER BY CASE p.Status WHEN 'FAILED' THEN 0 WHEN 'PENDING' THEN 1 WHEN 'IN_FILE' THEN 2 ELSE 3 END, x.SortKey DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ---- changes: the payments picked, in scope ---------------------- */
    DECLARE @Picked TABLE (BankPaymentId BIGINT PRIMARY KEY, Status VARCHAR(8), Method VARCHAR(6));
    IF @Action = 'FILE_PAID'
        INSERT INTO @Picked (BankPaymentId, Status, Method)
        SELECT p.BankPaymentId, p.Status, p.Method
        FROM   [Payroll].[BankPayments] AS p
        JOIN   [Payroll].[BankFiles] AS bf ON bf.BankFileId = p.BankFileId
        WHERE  p.BankFileId = @FileId AND p.Deleted = 0 AND p.Status = 'IN_FILE' AND bf.Status <> 'SUPERSEDED'
          AND  [Payroll].[ufn_InCompanyScope](bf.CompanyId, @CompanyId, @CompanyIds) = 1;
    ELSE
        INSERT INTO @Picked (BankPaymentId, Status, Method)
        SELECT p.BankPaymentId, p.Status, p.Method
        FROM   [Payroll].[BankPayments] AS p
        JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = p.PayrollRunId
        JOIN  (SELECT DISTINCT TRY_CAST(value AS BIGINT) AS Id FROM STRING_SPLIT(ISNULL(@Ids, N''), ',')) AS k ON k.Id = p.BankPaymentId
        WHERE  p.Deleted = 0 AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1;

    IF NOT EXISTS (SELECT 1 FROM @Picked)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'There are no payments to update. Refresh and try again.';
        RETURN;
    END;

    IF @Action IN ('SET_STATUS', 'FILE_PAID')
    BEGIN
        SET @Status = CASE WHEN @Action = 'FILE_PAID' THEN 'PAID' ELSE UPPER(@Status) END;
        IF @Status NOT IN ('PAID', 'FAILED')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose paid or failed.';
            RETURN;
        END;
        IF @Status = 'FAILED' AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter why the payment failed.';
            RETURN;
        END;
        /* PAID: from IN_FILE, or a cash payment waiting; FAILED: only from IN_FILE */
        IF EXISTS (SELECT 1 FROM @Picked WHERE (@Status = 'PAID' AND NOT (Status = 'IN_FILE' OR (Status = 'PENDING' AND Method = 'CASH')))
                                            OR (@Status = 'FAILED' AND Status <> 'IN_FILE'))
        BEGIN
            SELECT @ResultCode = 'INVALID_STATE', @ResultMessage = CASE WHEN @Status = 'PAID'
                THEN N'Only payments sent in a bank file, or cash payments waiting, can be marked as paid.'
                ELSE N'Only payments sent in a bank file can be marked as failed.' END;
            RETURN;
        END;

        UPDATE p
           SET Status = @Status,
               Reference = CASE WHEN @Status = 'PAID' THEN COALESCE(NULLIF(LTRIM(RTRIM(@Reference)), N''), p.Reference) ELSE p.Reference END,
               FailureReason = CASE WHEN @Status = 'FAILED' THEN LTRIM(RTRIM(@Reason)) ELSE NULL END,
               PaidDate = CASE WHEN @Status = 'PAID' THEN COALESCE(@PaidDate, bf.ValueDate, CAST(SYSUTCDATETIME() AS DATE)) ELSE NULL END,
               ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM   [Payroll].[BankPayments] AS p
        JOIN   @Picked AS k ON k.BankPaymentId = p.BankPaymentId
        LEFT JOIN [Payroll].[BankFiles] AS bf ON bf.BankFileId = p.BankFileId;

        SET @TotalCount = @@ROWCOUNT;

        /* db/116: a whole file paid is part of the bank file process audit */
        IF @Action = 'FILE_PAID'
            INSERT INTO [Payroll].[BankFileAudit] (PayrollRunId, BankFileId, ActionCode, FileKind, FileNo, BankId, LineCount, TotalAmount, Reference, ActionBy)
            SELECT PayrollRunId, BankFileId, 'PAID', FileKind, FileNo, BankId, @TotalCount,
                   (SELECT SUM(p.Amount) FROM [Payroll].[BankPayments] p JOIN @Picked k ON k.BankPaymentId = p.BankPaymentId),
                   NULL, @UserId
            FROM   [Payroll].[BankFiles] WHERE BankFileId = @FileId;

        SET @ResultMessage = CASE WHEN @Status = 'PAID' THEN N'Payments marked as paid.' ELSE N'Payments marked as failed.' END;
        RETURN;
    END;

    /* REISSUE */
    SET @Method = CASE WHEN UPPER(@Method) = 'CASH' THEN 'CASH' ELSE 'BANK' END;
    IF EXISTS (SELECT 1 FROM @Picked WHERE Status <> 'FAILED')
    BEGIN
        SELECT @ResultCode = 'INVALID_STATE', @ResultMessage = N'Only failed payments can be re-issued.';
        RETURN;
    END;
    IF @Method = 'BANK' AND EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS p JOIN @Picked AS k ON k.BankPaymentId = p.BankPaymentId
                                    LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = p.EmployeeId
                                    WHERE NULLIF(LTRIM(RTRIM(ep.Iban)), N'') IS NULL)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'An employee has no IBAN any more - re-issue as cash / cheque, or add the IBAN first.';
        RETURN;
    END;

    UPDATE p SET Status = 'PENDING', Method = @Method, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
    FROM [Payroll].[BankPayments] AS p JOIN @Picked AS k ON k.BankPaymentId = p.BankPaymentId;

    SET @TotalCount = @@ROWCOUNT;
    SET @ResultMessage = CASE WHEN @Method = 'BANK'
                              THEN N'Payments re-issued - generate a re-issue file for them.'
                              ELSE N'Payments moved to cash / cheque.' END;
END;
GO


/* ---- 5. Employee.usp_EmployeeCompleteness (db/95): Work Permit Salary for every employee */
CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeCompleteness]
    @EmployeeIds    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH ids AS (
        SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) AS EmployeeId
        FROM   STRING_SPLIT(@EmployeeIds, N',')
        WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL
    ),
    emp AS (
        SELECT  e.EmployeeId, e.HireDate, e.NoticePeriodDays, e.AnnualLeaveDays,
                p.BasicSalary, p.BankName, p.Iban,
                k.CivilIdNumber, k.CivilIdExpiryDate, k.PassportNumber, k.PassportCountryId, k.PassportExpiryDate,
                k.ResidencyNumber, k.ResidencyType, k.ResidencyExpiryDate, k.SponsorName,
                k.WorkPermitSalary, k.WorkPermitDesignation, k.WorkPermitDesignationAr,
                CASE WHEN c.CountryCode IN (N'KW', N'KWT') THEN 1 ELSE 0 END AS IsKuwaiti
        FROM    ids
        JOIN    [Employee].[Employees]          AS e ON e.EmployeeId = ids.EmployeeId AND e.Deleted = 0
        LEFT JOIN [Employee].[EmployeePayroll]  AS p ON p.EmployeeId = e.EmployeeId AND p.Deleted = 0
        LEFT JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = e.EmployeeId AND k.Deleted = 0
        LEFT JOIN [Core].[Countries]            AS c ON c.CountryId  = e.NationalityCountryId
    )
    SELECT  emp.EmployeeId,
            COUNT(m.FieldKey) AS MissingCount,
            STRING_AGG(m.FieldKey, N',') WITHIN GROUP (ORDER BY m.SortOrder) AS Missing
    FROM    emp
    OUTER APPLY (VALUES
            ( 1, N'HireDate',                CASE WHEN emp.HireDate IS NULL THEN 1 END),
            ( 2, N'NoticePeriodDays',        CASE WHEN emp.NoticePeriodDays IS NULL THEN 1 END),
            ( 3, N'AnnualLeaveDays',         CASE WHEN emp.AnnualLeaveDays IS NULL THEN 1 END),
            ( 4, N'BasicSalary',             CASE WHEN ISNULL(emp.BasicSalary, 0) <= 0 THEN 1 END),
            ( 5, N'BankName',                CASE WHEN NULLIF(LTRIM(RTRIM(emp.BankName)), N'') IS NULL THEN 1 END),
            ( 6, N'Iban',                    CASE WHEN NULLIF(LTRIM(RTRIM(emp.Iban)), N'') IS NULL THEN 1 END),
            ( 7, N'CivilIdNumber',           CASE WHEN NULLIF(LTRIM(RTRIM(emp.CivilIdNumber)), N'') IS NULL THEN 1 END),
            ( 8, N'CivilIdExpiryDate',       CASE WHEN emp.CivilIdExpiryDate IS NULL THEN 1 END),
            ( 9, N'PassportNumber',          CASE WHEN NULLIF(LTRIM(RTRIM(emp.PassportNumber)), N'') IS NULL THEN 1 END),
            (10, N'PassportCountryId',       CASE WHEN emp.PassportCountryId IS NULL THEN 1 END),
            (11, N'PassportExpiryDate',      CASE WHEN emp.PassportExpiryDate IS NULL THEN 1 END),
            (12, N'ResidencyNumber',         CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.ResidencyNumber)), N'') IS NULL THEN 1 END),
            (13, N'ResidencyType',           CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.ResidencyType)), N'') IS NULL THEN 1 END),
            (14, N'ResidencyExpiryDate',     CASE WHEN emp.IsKuwaiti = 0 AND emp.ResidencyExpiryDate IS NULL THEN 1 END),
            (15, N'SponsorName',             CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.SponsorName)), N'') IS NULL THEN 1 END),
            (16, N'WorkPermitSalary',        CASE WHEN ISNULL(emp.WorkPermitSalary, 0) <= 0 THEN 1 END),   -- db/116: every employee
            (17, N'WorkPermitDesignation',   CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.WorkPermitDesignation)), N'') IS NULL THEN 1 END),
            (18, N'WorkPermitDesignationAr', CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.WorkPermitDesignationAr)), N'') IS NULL THEN 1 END)
        ) AS m (SortOrder, FieldKey, IsMissing)
    WHERE   m.IsMissing = 1
    GROUP BY emp.EmployeeId;
END;
GO


/* ---- 6. labels (English + Arabic) ----------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fin.process', 'fin', N'Bank file process', N'طريقة ملف البنك', NULL),
        ('fin.mode_single', 'fin', N'Single file', N'ملف واحد', NULL),
        ('fin.mode_single_hint', 'fin', N'One file of every employees net pay', N'ملف واحد بصافي راتب كل موظف', NULL),
        ('fin.mode_staged', 'fin', N'Two steps', N'خطوتان', NULL),
        ('fin.mode_staged_hint', 'fin', N'Ministry Payroll, then Company Payroll', N'رواتب الوزارة ثم رواتب الشركة', NULL),
        ('fin.mode_locked_staged', 'fin', N'This payroll is paid in two steps - its files are generated there.', N'تُصرف هذه الرواتب على خطوتين - تُنشأ ملفاتها هناك.', NULL),
        ('fin.mode_locked_single', 'fin', N'This payroll is already paid with a single file.', N'صُرفت هذه الرواتب بالفعل بملف واحد.', NULL),
        ('fin.step1_title', 'fin', N'Step 1 · Ministry Payroll', N'الخطوة 1 · رواتب الوزارة', NULL),
        ('fin.step1_text', 'fin', N'Transfers each employees Work Permit Salary.', N'تحويل راتب إذن العمل لكل موظف.', NULL),
        ('fin.step1_generate', 'fin', N'Generate Ministry Payroll', N'إنشاء رواتب الوزارة', NULL),
        ('fin.step1_regenerate', 'fin', N'Generate Ministry Payroll again', N'إعادة إنشاء رواتب الوزارة', NULL),
        ('fin.step1_locked', 'fin', N'The Company Payroll is generated from it - it cannot be generated again.', N'أُنشئت رواتب الشركة منها - لا يمكن إنشاؤها مرة أخرى.', NULL),
        ('fin.wps_missing_0', 'fin', N'{0} employees have no Work Permit Salary:', N'{0} موظفين بدون راتب إذن عمل:', NULL),
        ('fin.open_employees', 'fin', N'Open Employees', N'فتح الموظفين', NULL),
        ('fin.step2_title', 'fin', N'Step 2 · Company Payroll', N'الخطوة 2 · رواتب الشركة', NULL),
        ('fin.step2_text', 'fin', N'Transfers the net pay less what the Ministry Payroll transferred.', N'تحويل صافي الراتب مخصوماً منه ما حُوّل في رواتب الوزارة.', NULL),
        ('fin.step2_generate', 'fin', N'Generate Company Payroll', N'إنشاء رواتب الشركة', NULL),
        ('fin.step2_regenerate', 'fin', N'Generate Company Payroll again', N'إعادة إنشاء رواتب الشركة', NULL),
        ('fin.step2_locked', 'fin', N'Generate the Ministry Payroll first.', N'أنشئ رواتب الوزارة أولاً.', NULL),
        ('fin.step2_over_0_1', 'fin', N'{0} employees left out - the Ministry Payroll paid more than their net pay (KWD {1} above it).', N'استُبعد {0} موظفين - رواتب الوزارة دفعت أكثر من صافي رواتبهم (بزيادة {1} د.ك).', NULL),
        ('fin.step2_cash_0_1', 'fin', N'{0} employees without IBAN are paid by cash / cheque with this step (KWD {1}).', N'{0} موظفين بدون آيبان يُدفع لهم نقداً / بشيك مع هذه الخطوة ({1} د.ك).', NULL),
        ('fin.process_history', 'fin', N'Process history', N'سجل العمليات', NULL),
        ('fin.no_process_history', 'fin', N'No bank file has been generated for this payroll yet.', N'لم يُنشأ أي ملف بنك لهذه الرواتب بعد.', NULL),
        ('fin.audit_generated', 'fin', N'Generated', N'تم الإنشاء', NULL),
        ('fin.audit_regenerated', 'fin', N'Generated again', N'أُعيد الإنشاء', NULL),
        ('fin.audit_sent', 'fin', N'Sent to the bank', N'أُرسل إلى البنك', NULL),
        ('fin.audit_paid', 'fin', N'Marked as paid', N'سُجّل كمدفوع', NULL),
        ('fin.audit_replaces_0', 'fin', N'Replaces {0}', N'يحل محل {0}', NULL),
        ('fin.reference_0', 'fin', N'Reference: {0}', N'المرجع: {0}', NULL),
        ('fin.kind_full', 'fin', N'Single file', N'ملف واحد', NULL),
        ('fin.kind_retry', 'fin', N'Re-issue', N'إعادة إصدار', NULL),
        ('fin.kind_ministry', 'fin', N'Ministry', N'الوزارة', NULL),
        ('fin.kind_company', 'fin', N'Company', N'الشركة', NULL),
        ('fin.code_ministry', 'fin', N'Ministry Payroll', N'رواتب الوزارة', NULL),
        ('fin.code_company', 'fin', N'Company Payroll', N'رواتب الشركة', NULL),
        ('msg.bf_ministry_done', 'msg', N'Ministry Payroll file generated.', N'تم إنشاء ملف رواتب الوزارة.', NULL),
        ('msg.bf_company_done', 'msg', N'Company Payroll file generated.', N'تم إنشاء ملف رواتب الشركة.', NULL),
        ('msg.bf_mode_staged', 'msg', N'This payroll is paid in two steps (Ministry Payroll, then Company Payroll) - generate its files there.', N'تُصرف هذه الرواتب على خطوتين (رواتب الوزارة ثم رواتب الشركة) - أنشئ ملفاتها هناك.', NULL),
        ('msg.bf_mode_single', 'msg', N'This payroll is already paid with a single bank file - the two-step process cannot be used for it.', N'صُرفت هذه الرواتب بملف بنك واحد - لا يمكن استخدام طريقة الخطوتين لها.', NULL),
        ('msg.bf_step1', 'msg', N'Generate the Ministry Payroll first - the Company Payroll transfers what is left after it.', N'أنشئ رواتب الوزارة أولاً - رواتب الشركة تحوّل المتبقي بعدها.', NULL),
        ('msg.bf_step2_done', 'msg', N'The Company Payroll is already generated from this Ministry Payroll - the Ministry Payroll cannot be generated again.', N'أُنشئت رواتب الشركة من رواتب الوزارة هذه - لا يمكن إنشاء رواتب الوزارة مرة أخرى.', NULL),
        ('msg.bf_nobody_company', 'msg', N'Nobody is left to pay in the Company Payroll - the Ministry Payroll transferred the full net pay.', N'لا يوجد من يُدفع له في رواتب الشركة - حوّلت رواتب الوزارة صافي الراتب كاملاً.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Bank two-step labels inserted: ', @LabelsInserted);
GO
