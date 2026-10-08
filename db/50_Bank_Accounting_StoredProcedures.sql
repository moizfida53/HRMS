/* =====================================================================
   50_Bank_Accounting_StoredProcedures.sql  -  HRMS Payroll: Bank
                                               Processing and Accounting
   ---------------------------------------------------------------------
   Run AFTER 49_Bank_Accounting_Tables.sql. Idempotent (CREATE OR ALTER).

   Envelope as the payroll processing procedures (@Action VARCHAR(20),
   @CompanyId / @CompanyIds = the user's company scope; OUT @TotalCount,
   @NewId, @ResultCode, @ResultMessage).

     Payroll.ufn_RunPayees(@RunId)        who a closed payroll pays and how
                                          (IBAN -> BANK, none -> CASH), with
                                          the bank matched from the IBAN
     Payroll.ufn_PayrollJournal(@RunId)   the journal of a payroll, grouped
                                          by account and cost center

     usp_BankFile_Manage      RUNS / REVIEW / LINES / CREATE / LIST / GET /
                              DOWNLOADED / MARK_SENT
     usp_BankPayment_Manage   LIST / SUMMARY / SET_STATUS / REISSUE / FILE_PAID
     usp_Journal_Manage       RUNS / PREVIEW / CREATE / LIST / GET / LINES /
                              EXPORTED / POSTED / REVERSE / DEFAULTS /
                              SET_DEFAULTS
     usp_CostAllocation_Manage LIST / GET / LINES / SAVE / DELETE
     usp_PayrollFinance_NavCounts   the sidebar figures

   The bank file text is built by the application from the bank format
   (Payroll Settings > Bank Formats) and stored as generated.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[BankFiles]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[ufn_InCompanyScope]', N'FN') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 48 and 49 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* =====================================================================
   Payroll.ufn_RunPayees - the employees a payroll pays (not excluded,
   net above zero), their IBAN and bank. The bank is the one whose IBAN
   bank code is inside the IBAN (KWkk BBBB ...), else the one named on
   the employee's payroll details.
===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_RunPayees] (@RunId BIGINT)
RETURNS TABLE
AS
RETURN
    SELECT  re.RunEmployeeId, re.EmployeeId, re.EmployeeNo, re.EmployeeName, re.DepartmentName,
            ci.CivilIdNumber AS CivilId,
            ib.Iban,
            CASE WHEN ib.Iban IS NULL THEN 'CASH' ELSE 'BANK' END AS Method,
            bk.BankId, ISNULL(bk.BankName, NULLIF(LTRIM(RTRIM(ep.BankName)), N'')) AS BankName,
            bk.WpsBankCode, bk.SwiftCode,
            re.NetPay, re.SalaryTotal, re.EarningsTotal, ABS(re.DeductionsTotal) AS DeductionsTotal
    FROM    [Payroll].[PayrollRunEmployees] AS re
    LEFT JOIN [Employee].[EmployeePayroll]  AS ep ON ep.EmployeeId = re.EmployeeId
    LEFT JOIN [Kuwait].[EmployeeCompliance] AS ci ON ci.EmployeeId = re.EmployeeId
    CROSS APPLY (SELECT NULLIF(UPPER(REPLACE(REPLACE(LTRIM(RTRIM(ep.Iban)), N' ', N''), N'-', N'')), N'') AS Iban) AS ib
    OUTER APPLY (SELECT TOP (1) b.BankId, b.BankName, b.WpsBankCode, b.SwiftCode
                 FROM   [Payroll].[Banks] AS b
                 WHERE  b.Deleted = 0
                   AND (   (b.IbanBankCode IS NOT NULL AND ib.Iban IS NOT NULL AND SUBSTRING(ib.Iban, 5, LEN(b.IbanBankCode)) = b.IbanBankCode)
                        OR (NULLIF(LTRIM(RTRIM(ep.BankName)), N'') IS NOT NULL
                            AND LTRIM(RTRIM(ep.BankName)) IN (b.BankName, b.ShortName, b.BankCode)))
                 ORDER BY CASE WHEN b.IbanBankCode IS NOT NULL AND ib.Iban IS NOT NULL
                                    AND SUBSTRING(ib.Iban, 5, LEN(b.IbanBankCode)) = b.IbanBankCode THEN 0 ELSE 1 END,
                          b.BankId) AS bk
    WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0 AND re.NetPay > 0;
GO

/* =====================================================================
   Payroll.ufn_PayrollJournal - the double entry of every payroll line:
     earning   Dr  mapping debit  (else the item's GL code)   cost center
               Cr  mapping credit (else salaries payable)
     deduction Dr  mapping debit  (else salaries payable)
               Cr  mapping credit (else the item's GL code)
   The mapping is Payroll.GLMappings for the line's cost center, else
   for any cost center. An earning's cost is split by the employee's
   cost allocation in force at the month end (else the payroll's cost
   center of the employee). A side with no account at all posts to
   UNMAPPED-<item code> and is flagged. Grouped by account, cost center
   and side - debits always equal credits.
===================================================================== */
CREATE OR ALTER FUNCTION [Payroll].[ufn_PayrollJournal] (@RunId BIGINT)
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
        SELECT l.RunLineId, l.EmployeeId, l.PayComponentId, l.Amount, ABS(l.Amount) AS Amt, re.CostCenterId AS EmpCc
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
        SELECT ln.RunLineId, ln.PayComponentId, ln.Amount,
               CASE WHEN ln.Amount > 0 AND a.EmployeeId IS NOT NULL THEN a.CostCenterId ELSE ln.EmpCc END AS CostCenterId,
               CASE WHEN ln.Amount > 0 AND a.EmployeeId IS NOT NULL
                    THEN ROUND(ln.Amt * a.CumShare / 100.0, 3) - ROUND(ln.Amt * (a.CumShare - a.SharePercent) / 100.0, 3)
                    ELSE ln.Amt END AS Amt
        FROM   ln
        LEFT JOIN alloc AS a ON a.EmployeeId = ln.EmployeeId AND ln.Amount > 0
    ), entry AS (
        SELECT e.Side, e.Code, e.Name, e.CostCenterId, e.Unmapped, p.Amt, c.ComponentName
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
    SELECT  ROW_NUMBER() OVER (ORDER BY g.Side DESC, g.Code, cc.CostCenterName) AS LineNumber,
            g.Code AS AccountCode, g.Name AS AccountName, g.CostCenterId, cc.CostCenterName,
            CAST(CASE WHEN g.Side = 'D' THEN g.Amt ELSE 0 END AS DECIMAL(14,3)) AS Debit,
            CAST(CASE WHEN g.Side = 'C' THEN g.Amt ELSE 0 END AS DECIMAL(14,3)) AS Credit,
            g.Unmapped AS IsUnmapped, g.Items AS Description
    FROM (
        SELECT Side, Code, MAX(Name) AS Name, CostCenterId, SUM(Amt) AS Amt, CAST(MAX(Unmapped) AS BIT) AS Unmapped,
               LEFT(STRING_AGG(CAST(NULLIF(ComponentName, N'') AS NVARCHAR(MAX)), N', ') WITHIN GROUP (ORDER BY ComponentName), 300) AS Items
        FROM (SELECT DISTINCT Side, Code, Name, CostCenterId, Unmapped, ComponentName, CAST(0 AS DECIMAL(14,3)) AS Amt FROM entry
              UNION ALL
              SELECT Side, Code, Name, CostCenterId, Unmapped, N'', Amt FROM entry) AS u
        GROUP BY Side, Code, CostCenterId
    ) AS g
    LEFT JOIN [Core].[CostCenters] AS cc ON cc.CostCenterId = g.CostCenterId;
GO

/* =====================================================================
   Payroll.usp_BankFile_Manage
     RUNS        closed payrolls (year / month) and their bank file state
     REVIEW      what a file would hold, per bank (@Kind FULL / RETRY);
                 CASH rows are the employees with no IBAN (never in a file)
     LINES       the employees of a file, with every value a bank format
                 can use (@Kind, @BankId)
     CREATE      store a generated file and record its payments
     LIST        the files (Payment History)
     GET         one file with its text; DOWNLOADED counts a download
     MARK_SENT   the file was uploaded to the bank (@Reference optional)
===================================================================== */
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

    @Kind                  VARCHAR(10)     = NULL,     -- FULL / RETRY
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

    IF @Action NOT IN ('RUNS', 'REVIEW', 'LINES', 'CREATE', 'LIST', 'GET', 'DOWNLOADED', 'MARK_SENT')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @Kind = CASE WHEN UPPER(ISNULL(@Kind, 'FULL')) = 'RETRY' THEN 'RETRY' ELSE 'FULL' END;
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

    /* the employees of a FULL file, or the re-issued payments of a RETRY file */
    DECLARE @Candidates TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT, BankId INT, Iban NVARCHAR(34), Amount DECIMAL(12,3));
    INSERT INTO @Candidates (RunEmployeeId, EmployeeId, BankId, Iban, Amount)
    SELECT  p.RunEmployeeId, p.EmployeeId, p.BankId, p.Iban, p.NetPay
    FROM    [Payroll].[ufn_RunPayees](@RunId) AS p
    LEFT JOIN [Payroll].[BankPayments] AS bp ON bp.PayrollRunId = @RunId AND bp.EmployeeId = p.EmployeeId AND bp.Deleted = 0
    WHERE   p.Method = 'BANK'
      AND  (@BankId IS NULL OR p.BankId = @BankId)
      AND  (   (@Kind = 'FULL'  AND (bp.BankPaymentId IS NULL OR bp.Method = 'BANK'))
            OR (@Kind = 'RETRY' AND bp.Method = 'BANK' AND bp.Status = 'PENDING'));

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
        WHERE   p.Method = 'CASH' AND @Kind = 'FULL' AND @BankId IS NULL
        HAVING  COUNT(1) > 0
        ORDER BY 1, 4 DESC;
        RETURN;
    END;

    IF @Action = 'LINES'
    BEGIN
        SELECT  p.RunEmployeeId, p.EmployeeId, p.EmployeeNo, p.EmployeeName, p.CivilId, p.Iban, p.BankId, p.BankName,
                p.WpsBankCode, p.SwiftCode, p.NetPay, p.SalaryTotal, p.EarningsTotal, p.DeductionsTotal
        FROM    @Candidates AS c
        JOIN    [Payroll].[ufn_RunPayees](@RunId) AS p ON p.RunEmployeeId = c.RunEmployeeId
        ORDER BY p.BankName, p.EmployeeNo;
        RETURN;
    END;

    /* ======================= CREATE ============================== */
    DECLARE @Picked TABLE (RunEmployeeId BIGINT PRIMARY KEY);
    INSERT INTO @Picked (RunEmployeeId)
    SELECT DISTINCT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(ISNULL(@RunEmployeeIds, N''), ',') WHERE TRY_CAST(value AS BIGINT) IS NOT NULL;

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

    /* a FULL file replaces the live FULL file(s) of the same scope (all banks / that bank) */
    DECLARE @Replaced TABLE (BankFileId BIGINT PRIMARY KEY);
    IF @Kind = 'FULL'
    BEGIN
        IF EXISTS (SELECT 1 FROM [Payroll].[BankFiles]
                   WHERE PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'FULL'
                     AND ((BankId IS NULL AND @BankId IS NOT NULL) OR (BankId IS NOT NULL AND @BankId IS NULL)))
        BEGIN
            SELECT @ResultCode = 'SCOPE', @ResultMessage = N'This payroll already has a file for a different bank choice. Generate it again with the same bank choice.';
            RETURN;
        END;

        INSERT INTO @Replaced (BankFileId)
        SELECT BankFileId FROM [Payroll].[BankFiles]
        WHERE  PayrollRunId = @RunId AND Deleted = 0 AND Status <> 'SUPERSEDED' AND FileKind = 'FULL'
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
    DECLARE @FileNo NVARCHAR(40) = CONCAT(N'WPS-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
    WHILE EXISTS (SELECT 1 FROM [Payroll].[BankFiles] WHERE CompanyId = @rCompany AND FileNo = @FileNo AND Deleted = 0)
    BEGIN
        SET @Seq += 1;
        SET @FileNo = CONCAT(N'WPS-', YEAR(@rMonth), N'-', RIGHT(CONCAT(N'0', MONTH(@rMonth)), 2), N'-', RIGHT(CONCAT(N'0', @Seq), 2));
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

        /* the payments of the file */
        UPDATE p
           SET Amount = c.Amount, Method = 'BANK', BankId = c.BankId, Iban = c.Iban, BankFileId = @NewId, Status = 'IN_FILE',
               FailureReason = NULL, AttemptCount = p.AttemptCount + 1, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
        FROM   [Payroll].[BankPayments] AS p
        JOIN   @Candidates AS c ON c.EmployeeId = p.EmployeeId
        JOIN   @Picked AS k ON k.RunEmployeeId = c.RunEmployeeId
        WHERE  p.PayrollRunId = @RunId AND p.Deleted = 0;

        INSERT INTO [Payroll].[BankPayments] (PayrollRunId, RunEmployeeId, EmployeeId, Amount, Method, BankId, Iban, BankFileId, Status, AttemptCount, CreatedBy)
        SELECT @RunId, c.RunEmployeeId, c.EmployeeId, c.Amount, 'BANK', c.BankId, c.Iban, @NewId, 'IN_FILE', 1, @UserId
        FROM   @Candidates AS c JOIN @Picked AS k ON k.RunEmployeeId = c.RunEmployeeId
        WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS p WHERE p.PayrollRunId = @RunId AND p.EmployeeId = c.EmployeeId AND p.Deleted = 0);

        /* the employees with no IBAN go on the register as cash / cheque payments */
        INSERT INTO [Payroll].[BankPayments] (PayrollRunId, RunEmployeeId, EmployeeId, Amount, Method, Status, CreatedBy)
        SELECT @RunId, p.RunEmployeeId, p.EmployeeId, p.NetPay, 'CASH', 'PENDING', @UserId
        FROM   [Payroll].[ufn_RunPayees](@RunId) AS p
        WHERE  p.Method = 'CASH'
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[BankPayments] AS x WHERE x.PayrollRunId = @RunId AND x.EmployeeId = p.EmployeeId AND x.Deleted = 0);
    COMMIT;

    SET @ResultMessage = N'Bank file generated.';
END;
GO

/* =====================================================================
   Payroll.usp_BankPayment_Manage - the payment register
     LIST / SUMMARY   (year / month / payroll / status / method / bank / search)
     SET_STATUS       @Ids, @Status PAID (@Reference, @PaidDate) or FAILED (@Reason)
     REISSUE          a failed payment waits again: BANK (next re-issue
                      file) or CASH (pay by cash / cheque) - @Method
     FILE_PAID        every payment still in file @FileId is paid
===================================================================== */
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

        SELECT  p.BankPaymentId, p.PayrollRunId, p.EmployeeId, p.Amount, p.Method, p.Status, p.Iban, p.Reference, p.FailureReason,
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

/* =====================================================================
   Payroll.usp_Journal_Manage
     RUNS          closed payrolls (year / month) with their journal
     PREVIEW       the journal a payroll would get (ufn_PayrollJournal)
     CREATE        store it (JV-<yyyy>-<mm>-<nn>)
     LIST / GET / LINES
     EXPORTED      counted on every export; READY -> EXPORTED
     POSTED        entered in the books - @Reference required
     REVERSE       @Reason required; the payroll can be journaled again
     DEFAULTS / SET_DEFAULTS   the company's salaries payable account
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
                j.JournalId, j.JournalNo, j.Status AS JournalStatus
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
                j.UnmappedCount, j.ExportCount, j.ExportedDate, j.PostedReference, j.PostedDate, j.ReversedDate, j.ReverseReason, j.CreatedDate,
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
                   j.UnmappedCount, j.ExportCount, j.PostedReference, j.ReverseReason, r.RunCode, r.RunMonth, co.CompanyName
            FROM   [Payroll].[JournalBatches] AS j
            JOIN   [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = j.PayrollRunId
            JOIN   [Core].[Companies] AS co ON co.CompanyId = j.CompanyId
            WHERE  j.JournalId = @Id;
            RETURN;
        END;
        IF @Action = 'LINES'
        BEGIN
            SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description
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
        SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description
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
                          Debit DECIMAL(14,3), Credit DECIMAL(14,3), IsUnmapped BIT, Description NVARCHAR(300));
    INSERT INTO @Lines SELECT LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description
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
        INSERT INTO [Payroll].[JournalBatches] (CompanyId, PayrollRunId, JournalNo, JournalDate, TotalDebit, TotalCredit, LineCount, UnmappedCount, CreatedBy)
        SELECT @rCompany, @RunId, @No, @rPayDate, SUM(Debit), SUM(Credit), COUNT(1), SUM(CASE WHEN IsUnmapped = 1 THEN 1 ELSE 0 END), @UserId
        FROM   @Lines;
        SET @NewId = SCOPE_IDENTITY();

        INSERT INTO [Payroll].[JournalLines] (JournalId, LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description)
        SELECT @NewId, LineNumber, AccountCode, AccountName, CostCenterId, CostCenterName, Debit, Credit, IsUnmapped, Description FROM @Lines;
    COMMIT;

    SET @ResultMessage = N'Journal created.';
END;
GO

/* =====================================================================
   Payroll.usp_CostAllocation_Manage - an employee's cost split
     LIST    the splits (in force in @RunMonth when given), search
     GET     one split; LINES its cost centers
     SAVE    @Id (0 = new), @EmployeeId, @EffectiveFrom, @EffectiveTo,
             @LinesJson [{"CostCenterId":3,"SharePercent":60}, ...] -
             shares add up to 100; a new split ends the employee's open
             split the day before it starts
     DELETE
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_CostAllocation_Manage]
    @Action                VARCHAR(20),
    @CompanyId             INT             = NULL,
    @CompanyIds            NVARCHAR(2000)  = NULL,
    @Id                    BIGINT          = NULL,
    @RunMonth              DATE            = NULL,
    @Year                  INT             = NULL,
    @Search                NVARCHAR(200)   = NULL,
    @CostCenterId          INT             = NULL,
    @PageNumber            INT             = 1,
    @PageSize              INT             = 25,

    @EmployeeId            BIGINT          = NULL,
    @EffectiveFrom         DATE            = NULL,
    @EffectiveTo           DATE            = NULL,
    @Notes                 NVARCHAR(500)   = NULL,
    @LinesJson             NVARCHAR(MAX)   = NULL,

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

    IF @Action NOT IN ('LIST', 'GET', 'LINES', 'SAVE', 'DELETE')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @PageNumber = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize   = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;
    DECLARE @From DATE = COALESCE(@RunMonth, CASE WHEN @Year IS NOT NULL THEN DATEFROMPARTS(@Year, 1, 1) END);
    DECLARE @To   DATE = COALESCE(EOMONTH(@RunMonth), CASE WHEN @Year IS NOT NULL THEN DATEFROMPARTS(@Year, 12, 31) END);

    IF @Action = 'LIST'
    BEGIN
        DECLARE @Ids TABLE (CostAllocationId INT PRIMARY KEY);
        INSERT INTO @Ids (CostAllocationId)
        SELECT a.CostAllocationId
        FROM   [Payroll].[CostAllocations] AS a
        JOIN   [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        WHERE  a.Deleted = 0
          AND  [Payroll].[ufn_InCompanyScope](a.CompanyId, @CompanyId, @CompanyIds) = 1
          AND (@From IS NULL OR (a.EffectiveFrom <= @To AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= @From)))
          AND (@CostCenterId IS NULL OR EXISTS (SELECT 1 FROM [Payroll].[CostAllocationLines] l
                                               WHERE l.CostAllocationId = a.CostAllocationId AND l.Deleted = 0 AND l.CostCenterId = @CostCenterId))
          AND (@Pattern IS NULL OR e.EmployeeNo LIKE @Pattern ESCAPE '\'
               OR CONCAT(e.FirstName, N' ', e.LastName) LIKE @Pattern ESCAPE '\');

        SELECT @TotalCount = COUNT(1) FROM @Ids;

        SELECT  a.CostAllocationId, a.CompanyId, a.EmployeeId, a.EffectiveFrom, a.EffectiveTo, a.Notes,
                e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName, co.CompanyName,
                (SELECT STRING_AGG(CONCAT(cc.CostCenterName, N' ', FORMAT(l.SharePercent, '0.##'), N'%'), N' · ')
                        WITHIN GROUP (ORDER BY l.SharePercent DESC)
                 FROM [Payroll].[CostAllocationLines] AS l JOIN [Core].[CostCenters] AS cc ON cc.CostCenterId = l.CostCenterId
                 WHERE l.CostAllocationId = a.CostAllocationId AND l.Deleted = 0) AS Split,
                CAST(CASE WHEN a.EffectiveFrom <= CAST(SYSUTCDATETIME() AS DATE)
                               AND (a.EffectiveTo IS NULL OR a.EffectiveTo >= CAST(SYSUTCDATETIME() AS DATE)) THEN 1 ELSE 0 END AS BIT) AS IsCurrent
        FROM    @Ids AS x
        JOIN    [Payroll].[CostAllocations] AS a ON a.CostAllocationId = x.CostAllocationId
        JOIN    [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        JOIN    [Core].[Companies] AS co ON co.CompanyId = a.CompanyId
        ORDER BY e.EmployeeNo, a.EffectiveFrom DESC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    IF @Action IN ('GET', 'LINES', 'DELETE')
       AND NOT EXISTS (SELECT 1 FROM [Payroll].[CostAllocations] WHERE CostAllocationId = @Id AND Deleted = 0
                         AND [Payroll].[ufn_InCompanyScope](CompanyId, @CompanyId, @CompanyIds) = 1)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That cost split no longer exists. Refresh and try again.';
        RETURN;
    END;

    IF @Action = 'GET'
    BEGIN
        SELECT a.CostAllocationId, a.CompanyId, a.EmployeeId, a.EffectiveFrom, a.EffectiveTo, a.Notes,
               e.EmployeeNo, LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))) AS EmployeeName
        FROM   [Payroll].[CostAllocations] AS a JOIN [Employee].[Employees] AS e ON e.EmployeeId = a.EmployeeId
        WHERE  a.CostAllocationId = @Id;
        RETURN;
    END;
    IF @Action = 'LINES'
    BEGIN
        SELECT l.CostCenterId, l.SharePercent, cc.CostCenterName
        FROM   [Payroll].[CostAllocationLines] AS l JOIN [Core].[CostCenters] AS cc ON cc.CostCenterId = l.CostCenterId
        WHERE  l.CostAllocationId = @Id AND l.Deleted = 0
        ORDER BY l.SharePercent DESC, l.CostAllocationLineId;
        RETURN;
    END;
    IF @Action = 'DELETE'
    BEGIN
        BEGIN TRAN;
            UPDATE [Payroll].[CostAllocationLines] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE CostAllocationId = @Id AND Deleted = 0;
            UPDATE [Payroll].[CostAllocations]     SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME() WHERE CostAllocationId = @Id;
        COMMIT;
        SET @ResultMessage = N'Cost split deleted.';
        RETURN;
    END;

    /* SAVE */
    DECLARE @eCompany INT = (SELECT CompanyId FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId);
    IF @eCompany IS NULL OR [Payroll].[ufn_InCompanyScope](@eCompany, @CompanyId, @CompanyIds) = 0
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select the employee.';
        RETURN;
    END;
    IF ISNULL(@Id, 0) > 0 AND NOT EXISTS (SELECT 1 FROM [Payroll].[CostAllocations] WHERE CostAllocationId = @Id AND Deleted = 0 AND EmployeeId = @EmployeeId)
    BEGIN
        SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That cost split no longer exists. Refresh and try again.';
        RETURN;
    END;
    IF @EffectiveFrom IS NULL OR (@EffectiveTo IS NOT NULL AND @EffectiveTo < @EffectiveFrom)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the date the split applies from (and an end date after it).';
        RETURN;
    END;

    DECLARE @Lines TABLE (CostCenterId INT, SharePercent DECIMAL(9,4));
    IF @LinesJson IS NOT NULL AND ISJSON(@LinesJson) = 1
        INSERT INTO @Lines (CostCenterId, SharePercent)
        SELECT j.CostCenterId, j.SharePercent FROM OPENJSON(@LinesJson) WITH (CostCenterId INT '$.CostCenterId', SharePercent DECIMAL(9,4) '$.SharePercent') AS j;

    IF (SELECT COUNT(1) FROM @Lines) < 1
       OR EXISTS (SELECT 1 FROM @Lines WHERE CostCenterId IS NULL OR SharePercent IS NULL OR SharePercent <= 0 OR SharePercent > 100)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Every line needs a cost center and a share above 0.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM @Lines GROUP BY CostCenterId HAVING COUNT(1) > 1)
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Each cost center can be listed once only.';
        RETURN;
    END;
    IF (SELECT SUM(SharePercent) FROM @Lines) <> 100
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The shares must add up to 100%.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM @Lines AS l WHERE NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] cc WHERE cc.CostCenterId = l.CostCenterId AND cc.CompanyId = @eCompany AND cc.Deleted = 0))
    BEGIN
        SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'A cost center does not belong to the employee''s company.';
        RETURN;
    END;
    IF EXISTS (SELECT 1 FROM [Payroll].[CostAllocations]
               WHERE EmployeeId = @EmployeeId AND Deleted = 0 AND CostAllocationId <> ISNULL(@Id, 0)
                 AND EffectiveFrom >= @EffectiveFrom AND EffectiveFrom <= ISNULL(@EffectiveTo, '9999-12-31'))
    BEGIN
        SELECT @ResultCode = 'OVERLAP', @ResultMessage = N'The employee has another split starting within these dates. Change its dates first.';
        RETURN;
    END;

    BEGIN TRAN;
        /* the open split before this one ends the day before */
        UPDATE [Payroll].[CostAllocations]
           SET EffectiveTo = DATEADD(DAY, -1, @EffectiveFrom), ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @EmployeeId AND Deleted = 0 AND CostAllocationId <> ISNULL(@Id, 0)
           AND EffectiveFrom < @EffectiveFrom AND (EffectiveTo IS NULL OR EffectiveTo >= @EffectiveFrom);

        IF ISNULL(@Id, 0) > 0
        BEGIN
            UPDATE [Payroll].[CostAllocations]
               SET EffectiveFrom = @EffectiveFrom, EffectiveTo = @EffectiveTo, Notes = NULLIF(LTRIM(RTRIM(@Notes)), N''),
                   ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
             WHERE CostAllocationId = @Id;
            UPDATE [Payroll].[CostAllocationLines] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
             WHERE CostAllocationId = @Id AND Deleted = 0;
            SET @NewId = @Id;
        END
        ELSE
        BEGIN
            INSERT INTO [Payroll].[CostAllocations] (CompanyId, EmployeeId, EffectiveFrom, EffectiveTo, Notes, CreatedBy)
            VALUES (@eCompany, @EmployeeId, @EffectiveFrom, @EffectiveTo, NULLIF(LTRIM(RTRIM(@Notes)), N''), @UserId);
            SET @NewId = SCOPE_IDENTITY();
        END;

        INSERT INTO [Payroll].[CostAllocationLines] (CostAllocationId, CostCenterId, SharePercent)
        SELECT @NewId, CostCenterId, SharePercent FROM @Lines;
    COMMIT;

    SET @ResultMessage = N'Cost split saved.';
END;
GO

/* =====================================================================
   Payroll.usp_PayrollFinance_NavCounts - the sidebar figures of Bank
   Processing and Accounting (closed payrolls of the last 12 months):
     BankFilesToMake    closed payrolls paying by bank with no bank file
     PaymentsOpen       payments failed, waiting or awaiting confirmation
     JournalsToMake     closed payrolls with no journal
     JournalsToPost     journals ready or exported, not posted
===================================================================== */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollFinance_NavCounts]
    @CompanyId   INT            = NULL,
    @CompanyIds  NVARCHAR(2000) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Since DATE = DATEADD(MONTH, -12, DATEFROMPARTS(YEAR(SYSUTCDATETIME()), MONTH(SYSUTCDATETIME()), 1));

    SELECT
        (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] AS r
         WHERE r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth >= @Since AND r.TotalNet > 0
           AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
           AND NOT EXISTS (SELECT 1 FROM [Payroll].[BankFiles] f WHERE f.PayrollRunId = r.PayrollRunId AND f.Deleted = 0 AND f.Status <> 'SUPERSEDED')) AS BankFilesToMake,
        (SELECT COUNT(1) FROM [Payroll].[BankPayments] AS p JOIN [Payroll].[PayrollRuns] AS r ON r.PayrollRunId = p.PayrollRunId
         WHERE p.Deleted = 0 AND p.Status IN ('PENDING', 'FAILED', 'IN_FILE')
           AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1) AS PaymentsOpen,
        (SELECT COUNT(1) FROM [Payroll].[PayrollRuns] AS r
         WHERE r.Deleted = 0 AND r.Stage = 'CLOSED' AND r.RunMonth >= @Since
           AND [Payroll].[ufn_InCompanyScope](r.CompanyId, @CompanyId, @CompanyIds) = 1
           AND NOT EXISTS (SELECT 1 FROM [Payroll].[JournalBatches] j WHERE j.PayrollRunId = r.PayrollRunId AND j.Deleted = 0 AND j.Status <> 'REVERSED')) AS JournalsToMake,
        (SELECT COUNT(1) FROM [Payroll].[JournalBatches] AS j
         WHERE j.Deleted = 0 AND j.Status IN ('READY', 'EXPORTED')
           AND [Payroll].[ufn_InCompanyScope](j.CompanyId, @CompanyId, @CompanyIds) = 1) AS JournalsToPost;
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/50 applied: bank file, payment, journal and cost allocation procedures. Run db/51 next.';
GO
