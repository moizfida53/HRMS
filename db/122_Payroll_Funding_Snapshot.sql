/* =====================================================================
   122_Payroll_Funding_Snapshot.sql  -  the payroll funding, kept at approval
   ---------------------------------------------------------------------
   Run after db/121. Safe to re-run. It replaces Payroll.usp_Payroll_Funding
   (db/121): run this script again whenever db/121 is run.

   The payroll funding (step 1 work permit transfer, step 2 balance
   transfer, to collect, cash - db/121) is shown to the approver and kept for
   reference: the "Payroll funding" button on the payroll's pages (Register,
   Validation, Approval, and a closed payroll opened from Payroll History).

   When a payroll is approved (closed) its funding is saved as it was then
   (Payroll.RunFundingSnapshot) - a closed payroll always shows those
   figures, even if a work permit salary changes later. Before approval the
   figures are worked out live.

   First run: the closed payrolls get a snapshot of their funding as it
   works out now.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[ufn_RunFunding]', N'IF') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/121 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the funding of a payroll as approved ------------------------------ */
IF OBJECT_ID(N'[Payroll].[RunFundingSnapshot]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[RunFundingSnapshot](
        RunFundingSnapshotId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RunFundingSnapshot PRIMARY KEY,
        PayrollRunId         BIGINT         NOT NULL,
        RunEmployeeId        BIGINT         NOT NULL,
        EmployeeId           BIGINT         NOT NULL,
        EmployeeNo           NVARCHAR(20)   NULL,
        EmployeeName         NVARCHAR(300)  NULL,
        DepartmentName       NVARCHAR(200)  NULL,
        Method               VARCHAR(6)     NOT NULL,
        BankName             NVARCHAR(200)  NULL,
        NetPay               DECIMAL(12,3)  NOT NULL,
        Wps                  DECIMAL(12,3)  NULL,
        WorkPermitTransfer   DECIMAL(12,3)  NOT NULL,
        BalanceTransfer      DECIMAL(12,3)  NOT NULL,
        ToCollect            DECIMAL(12,3)  NOT NULL,
        CashPayment          DECIMAL(12,3)  NOT NULL,
        FundingCase          VARCHAR(8)     NOT NULL,
        SnapshotBy           BIGINT         NULL,
        SnapshotDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_RunFundingSnapshot_Date DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_RunFundingSnapshot_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_RunFundingSnapshot_Run FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId)
    );
    CREATE INDEX IX_RunFundingSnapshot_Run ON [Payroll].[RunFundingSnapshot](PayrollRunId) WHERE Deleted = 0;
END;
GO

/* ---- 2. Payroll.usp_Payroll_FundingSnapshot - saved when the payroll is approved */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Payroll_FundingSnapshot]
    @RunId   BIGINT,
    @UserId  BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage = 'CLOSED') RETURN;

    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
    BEGIN TRANSACTION;
        /* approved again (after a reopen): the new figures replace the old ones */
        UPDATE [Payroll].[RunFundingSnapshot] SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        WHERE  PayrollRunId = @RunId AND Deleted = 0;

        INSERT INTO [Payroll].[RunFundingSnapshot]
            (PayrollRunId, RunEmployeeId, EmployeeId, EmployeeNo, EmployeeName, DepartmentName, Method, BankName, NetPay, Wps,
             WorkPermitTransfer, BalanceTransfer, ToCollect, CashPayment, FundingCase, SnapshotBy, SnapshotDate)
        SELECT  @RunId, f.RunEmployeeId, f.EmployeeId, f.EmployeeNo, f.EmployeeName, f.DepartmentName, f.Method, f.BankName, f.NetPay, f.Wps,
                f.WorkPermitTransfer, f.BalanceTransfer, f.ToCollect, f.CashPayment, f.FundingCase, @UserId, @Now
        FROM    [Payroll].[ufn_RunFunding](@RunId) AS f;
    COMMIT TRANSACTION;
END;
GO

/* ---- 3. Payroll.usp_Payroll_Funding (db/121): a closed payroll shows its snapshot */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Payroll_Funding]
    @RunId  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM [Payroll].[PayrollRuns] WHERE PayrollRunId = @RunId AND Deleted = 0 AND Stage = 'CLOSED')
       AND EXISTS (SELECT 1 FROM [Payroll].[RunFundingSnapshot] WHERE PayrollRunId = @RunId AND Deleted = 0)
    BEGIN
        SELECT  s.RunEmployeeId, s.EmployeeId, s.EmployeeNo, s.EmployeeName, s.DepartmentName, s.Method, s.BankName,
                s.NetPay, s.Wps, s.WorkPermitTransfer, s.BalanceTransfer, s.ToCollect, s.CashPayment, s.FundingCase,
                CAST(1 AS BIT) AS IsSnapshot, s.SnapshotDate,
                COALESCE(NULLIF(LTRIM(RTRIM(CONCAT(ue.FirstName, N' ', ue.LastName))), N''), u.Username) AS SnapshotByName
        FROM    [Payroll].[RunFundingSnapshot] AS s
        LEFT JOIN [Security].[Users] AS u ON u.UserId = s.SnapshotBy
        LEFT JOIN [Employee].[Employees] AS ue ON ue.EmployeeId = u.EmployeeId
        WHERE   s.PayrollRunId = @RunId AND s.Deleted = 0
        ORDER BY CASE s.FundingCase WHEN 'NO_WPS' THEN 0 WHEN 'COLLECT' THEN 1 WHEN 'BALANCE' THEN 2 WHEN 'EQUAL' THEN 3 ELSE 4 END,
                 s.EmployeeNo;
        RETURN;
    END;

    SELECT  f.RunEmployeeId, f.EmployeeId, f.EmployeeNo, f.EmployeeName, f.DepartmentName, f.Method, f.BankName,
            f.NetPay, f.Wps, f.WorkPermitTransfer, f.BalanceTransfer, f.ToCollect, f.CashPayment, f.FundingCase,
            CAST(0 AS BIT) AS IsSnapshot, CAST(NULL AS DATETIME2(0)) AS SnapshotDate, CAST(NULL AS NVARCHAR(300)) AS SnapshotByName
    FROM    [Payroll].[ufn_RunFunding](@RunId) AS f
    ORDER BY CASE f.FundingCase WHEN 'NO_WPS' THEN 0 WHEN 'COLLECT' THEN 1 WHEN 'BALANCE' THEN 2 WHEN 'EQUAL' THEN 3 ELSE 4 END,
             f.EmployeeNo;
END;
GO

/* ---- 4. first run: the closed payrolls get their snapshot ------------------ */
DECLARE @Run BIGINT, @Done INT = 0;
DECLARE runs CURSOR LOCAL FAST_FORWARD FOR
    SELECT r.PayrollRunId FROM [Payroll].[PayrollRuns] AS r
    WHERE  r.Deleted = 0 AND r.Stage = 'CLOSED'
      AND  NOT EXISTS (SELECT 1 FROM [Payroll].[RunFundingSnapshot] s WHERE s.PayrollRunId = r.PayrollRunId AND s.Deleted = 0);
OPEN runs;
FETCH NEXT FROM runs INTO @Run;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Payroll].[usp_Payroll_FundingSnapshot] @RunId = @Run;
    SET @Done += 1;
    FETCH NEXT FROM runs INTO @Run;
END;
CLOSE runs; DEALLOCATE runs;
PRINT CONCAT(N'Closed payrolls given a funding snapshot: ', @Done);
GO

/* ---- 5. labels ------------------------------------------------------------ */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('fund.button', 'fund', N'Payroll funding', N'تمويل الرواتب', NULL),
        ('fund.button_hint', 'fund', N'Work permit transfer, balance transfer and what is collected back', N'تحويل إذن العمل وتحويل الرصيد وما يُسترد', NULL),
        ('fund.popup_title_0', 'fund', N'Payroll funding · {0}', N'تمويل الرواتب · {0}', NULL),
        ('fund.as_approved_0_1', 'fund', N'As approved on {0} by {1} - these figures are kept for reference.', N'كما اعتُمدت في {0} بواسطة {1} - تُحفظ هذه الأرقام للرجوع إليها.', NULL),
        ('fund.as_approved_0', 'fund', N'As approved on {0} - these figures are kept for reference.', N'كما اعتُمدت في {0} - تُحفظ هذه الأرقام للرجوع إليها.', NULL),
        ('fund.live', 'fund', N'Worked out now from the payroll and the work permit salaries - kept as they are when the payroll is approved.', N'محسوبة الآن من الرواتب ورواتب إذن العمل - تُحفظ كما هي عند اعتماد الرواتب.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Funding labels inserted: ', @@ROWCOUNT);
GO
