/* =====================================================================
   49_Bank_Accounting_Tables.sql  -  HRMS Payroll: Bank Processing and
                                    Accounting
   ---------------------------------------------------------------------
   Run after 34 (payroll runs), 42 (payslips) and 47 (payroll settings).
   Idempotent - safe to re-run. Then run 50 (procedures), 51 (reports)
   and 52 (labels).

   Bank Processing
     Payroll.BankFiles          one salary (WPS) file of a closed payroll -
                                its text is kept as generated, so a file
                                downloads the same every time. FULL = every
                                employee paid by bank, RETRY = the payments
                                that failed and were re-issued. Generating
                                the FULL file again (with a reason) replaces
                                the previous one (SUPERSEDED).
     Payroll.BankPayments       the payment register: one row per employee
                                of a closed payroll - BANK (in a file) or
                                CASH (no IBAN: cash or cheque) - and its
                                status PENDING / IN_FILE / PAID / FAILED.

   Accounting
     Payroll.JournalBatches     the payroll journal of a closed payroll
     Payroll.JournalLines       (debit / credit per GL account and cost
                                center), READY -> EXPORTED -> POSTED; a
                                REVERSED journal frees the payroll for a
                                new one.
     Payroll.AccountingDefaults per company: the salaries payable account
                                used for a pay item type with no GL mapping.
     Payroll.CostAllocations    an employee's cost split across cost
     Payroll.CostAllocationLines centers from a date (shares add up to 100).

   Permissions (to SYSADMIN): PAYROLL_BANK_VIEW / PAYROLL_BANK_PROCESS,
   PAYROLL_GL_VIEW / PAYROLL_GL_POST, PAYROLL_REPORT_VIEW.

   Standing rule: nothing is ever physically deleted (Deleted flag, db/28).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[PayrollRunEmployees]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[BankFileFormats]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 34 (payroll runs) and 47 (payroll settings) before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Bank files
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[BankFiles]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[BankFiles](
        BankFileId           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BankFiles PRIMARY KEY,
        CompanyId            INT            NOT NULL,
        PayrollRunId         BIGINT         NOT NULL,
        FileNo               NVARCHAR(40)   NOT NULL,       -- WPS-<yyyy>-<mm>-<nn> per company
        FileKind             VARCHAR(10)    NOT NULL CONSTRAINT DF_BankFiles_Kind DEFAULT ('FULL'),
        BankFileFormatId     INT            NOT NULL,
        CompanyBankAccountId INT            NOT NULL,
        BankId               INT            NULL,           -- NULL = every bank
        ValueDate            DATE           NOT NULL,
        FileName             NVARCHAR(150)  NOT NULL,
        Content              NVARCHAR(MAX)  NOT NULL,
        LineCount            INT            NOT NULL,
        TotalAmount          DECIMAL(14,3)  NOT NULL,
        Status               VARCHAR(12)    NOT NULL CONSTRAINT DF_BankFiles_Status DEFAULT ('GENERATED'),
        Reason               NVARCHAR(500)  NULL,           -- why it was generated again
        DownloadCount        INT            NOT NULL CONSTRAINT DF_BankFiles_Downloads DEFAULT (0),
        SentBy               BIGINT         NULL,
        SentDate             DATETIME2(0)   NULL,
        SentReference        NVARCHAR(100)  NULL,
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_BankFiles_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_BankFiles_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_BankFiles_Company FOREIGN KEY (CompanyId)            REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_BankFiles_Run     FOREIGN KEY (PayrollRunId)         REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_BankFiles_Format  FOREIGN KEY (BankFileFormatId)     REFERENCES [Payroll].[BankFileFormats](BankFileFormatId),
        CONSTRAINT FK_BankFiles_Account FOREIGN KEY (CompanyBankAccountId) REFERENCES [Payroll].[CompanyBankAccounts](CompanyBankAccountId),
        CONSTRAINT FK_BankFiles_Bank    FOREIGN KEY (BankId)               REFERENCES [Payroll].[Banks](BankId),
        CONSTRAINT CK_BankFiles_Kind    CHECK (FileKind IN ('FULL', 'RETRY')),
        CONSTRAINT CK_BankFiles_Status  CHECK (Status IN ('GENERATED', 'SENT', 'SUPERSEDED'))
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankFiles_No ON [Payroll].[BankFiles](CompanyId, FileNo) WHERE Deleted = 0;
    CREATE INDEX IX_BankFiles_Run ON [Payroll].[BankFiles](PayrollRunId, Status) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[BankPayments]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[BankPayments](
        BankPaymentId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BankPayments PRIMARY KEY,
        PayrollRunId         BIGINT         NOT NULL,
        RunEmployeeId        BIGINT         NOT NULL,
        EmployeeId           BIGINT         NOT NULL,
        Amount               DECIMAL(12,3)  NOT NULL,
        Method               VARCHAR(6)     NOT NULL,       -- BANK / CASH
        BankId               INT            NULL,
        Iban                 NVARCHAR(34)   NULL,
        BankFileId           BIGINT         NULL,           -- the latest file it was in
        Status               VARCHAR(8)     NOT NULL,       -- PENDING / IN_FILE / PAID / FAILED
        Reference            NVARCHAR(100)  NULL,           -- bank reference, cheque or voucher number
        FailureReason        NVARCHAR(300)  NULL,
        PaidDate             DATE           NULL,
        AttemptCount         SMALLINT       NOT NULL CONSTRAINT DF_BankPayments_Attempts DEFAULT (0),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_BankPayments_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_BankPayments_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_BankPayments_Run         FOREIGN KEY (PayrollRunId)  REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_BankPayments_RunEmployee FOREIGN KEY (RunEmployeeId) REFERENCES [Payroll].[PayrollRunEmployees](RunEmployeeId),
        CONSTRAINT FK_BankPayments_File        FOREIGN KEY (BankFileId)    REFERENCES [Payroll].[BankFiles](BankFileId),
        CONSTRAINT FK_BankPayments_Bank        FOREIGN KEY (BankId)        REFERENCES [Payroll].[Banks](BankId),
        CONSTRAINT CK_BankPayments_Method      CHECK (Method IN ('BANK', 'CASH')),
        CONSTRAINT CK_BankPayments_Status      CHECK (Status IN ('PENDING', 'IN_FILE', 'PAID', 'FAILED')),
        CONSTRAINT CK_BankPayments_Amount      CHECK (Amount >= 0)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankPayments_Employee ON [Payroll].[BankPayments](PayrollRunId, EmployeeId) WHERE Deleted = 0;
    CREATE INDEX IX_BankPayments_File ON [Payroll].[BankPayments](BankFileId, Status) WHERE Deleted = 0;
    CREATE INDEX IX_BankPayments_Status ON [Payroll].[BankPayments](Status) INCLUDE (PayrollRunId, Amount) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   2. Accounting
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[AccountingDefaults]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[AccountingDefaults](
        CompanyId            INT            NOT NULL CONSTRAINT PK_AccountingDefaults PRIMARY KEY,
        NetPayAccountCode    NVARCHAR(50)   NOT NULL,
        NetPayAccountName    NVARCHAR(150)  NULL,
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_AccountingDefaults_Date DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_AccountingDefaults_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_AccountingDefaults_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId)
    );
END;
GO

IF OBJECT_ID(N'[Payroll].[JournalBatches]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[JournalBatches](
        JournalId            BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_JournalBatches PRIMARY KEY,
        CompanyId            INT            NOT NULL,
        PayrollRunId         BIGINT         NOT NULL,
        JournalNo            NVARCHAR(40)   NOT NULL,       -- JV-<yyyy>-<mm>-<nn> per company
        JournalDate          DATE           NOT NULL,
        Status               VARCHAR(10)    NOT NULL CONSTRAINT DF_JournalBatches_Status DEFAULT ('READY'),
        TotalDebit           DECIMAL(14,3)  NOT NULL,
        TotalCredit          DECIMAL(14,3)  NOT NULL,
        LineCount            INT            NOT NULL,
        UnmappedCount        INT            NOT NULL CONSTRAINT DF_JournalBatches_Unmapped DEFAULT (0),
        ExportCount          INT            NOT NULL CONSTRAINT DF_JournalBatches_Exports DEFAULT (0),
        ExportedBy           BIGINT         NULL,
        ExportedDate         DATETIME2(0)   NULL,
        PostedReference      NVARCHAR(100)  NULL,
        PostedBy             BIGINT         NULL,
        PostedDate           DATETIME2(0)   NULL,
        ReversedBy           BIGINT         NULL,
        ReversedDate         DATETIME2(0)   NULL,
        ReverseReason        NVARCHAR(500)  NULL,
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_JournalBatches_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_JournalBatches_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_JournalBatches_Company FOREIGN KEY (CompanyId)    REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_JournalBatches_Run     FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT CK_JournalBatches_Status  CHECK (Status IN ('READY', 'EXPORTED', 'POSTED', 'REVERSED'))
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_JournalBatches_No ON [Payroll].[JournalBatches](CompanyId, JournalNo) WHERE Deleted = 0;
    /* one live journal per payroll (reverse it to make another) */
    CREATE UNIQUE NONCLUSTERED INDEX UX_JournalBatches_Run ON [Payroll].[JournalBatches](PayrollRunId) WHERE Status <> 'REVERSED' AND Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[JournalLines]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[JournalLines](
        JournalLineId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_JournalLines PRIMARY KEY,
        JournalId            BIGINT         NOT NULL,
        LineNumber           INT            NOT NULL,
        AccountCode          NVARCHAR(50)   NOT NULL,
        AccountName          NVARCHAR(150)  NULL,
        CostCenterId         INT            NULL,
        CostCenterName       NVARCHAR(150)  NULL,
        Debit                DECIMAL(14,3)  NOT NULL CONSTRAINT DF_JournalLines_Debit DEFAULT (0),
        Credit               DECIMAL(14,3)  NOT NULL CONSTRAINT DF_JournalLines_Credit DEFAULT (0),
        Description          NVARCHAR(300)  NULL,
        IsUnmapped           BIT            NOT NULL CONSTRAINT DF_JournalLines_Unmapped DEFAULT (0),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_JournalLines_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_JournalLines_Journal FOREIGN KEY (JournalId) REFERENCES [Payroll].[JournalBatches](JournalId)
    );
    CREATE INDEX IX_JournalLines_Journal ON [Payroll].[JournalLines](JournalId, LineNumber) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[CostAllocations]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[CostAllocations](
        CostAllocationId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CostAllocations PRIMARY KEY,
        CompanyId            INT            NOT NULL,
        EmployeeId           BIGINT         NOT NULL,
        EffectiveFrom        DATE           NOT NULL,
        EffectiveTo          DATE           NULL,
        Notes                NVARCHAR(500)  NULL,
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_CostAllocations_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_CostAllocations_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_CostAllocations_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_CostAllocations_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_CostAllocations_Dates    CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
    CREATE INDEX IX_CostAllocations_Employee ON [Payroll].[CostAllocations](EmployeeId, EffectiveFrom) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[CostAllocationLines]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[CostAllocationLines](
        CostAllocationLineId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CostAllocationLines PRIMARY KEY,
        CostAllocationId     INT            NOT NULL,
        CostCenterId         INT            NOT NULL,
        SharePercent         DECIMAL(5,2)   NOT NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_CostAllocationLines_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,
        CONSTRAINT FK_CostAllocationLines_Allocation FOREIGN KEY (CostAllocationId) REFERENCES [Payroll].[CostAllocations](CostAllocationId),
        CONSTRAINT FK_CostAllocationLines_CostCenter FOREIGN KEY (CostCenterId)     REFERENCES [Core].[CostCenters](CostCenterId),
        CONSTRAINT CK_CostAllocationLines_Share      CHECK (SharePercent > 0 AND SharePercent <= 100)
    );
    CREATE INDEX IX_CostAllocationLines_Allocation ON [Payroll].[CostAllocationLines](CostAllocationId) WHERE Deleted = 0;
END;
GO

/* The delete guard of db/28 for the new tables. */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'BankFiles';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'BankPayments';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'AccountingDefaults';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'JournalBatches';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'JournalLines';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'CostAllocations';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'CostAllocationLines';
END;
GO

/* ------------------------------------------------------------------
   3. Permissions
      PAYROLL_BANK_VIEW      see bank files and the payment register
      PAYROLL_BANK_PROCESS   generate files, record payments
      PAYROLL_GL_VIEW        see journals and cost allocations
      PAYROLL_GL_POST        create / export / post / reverse journals,
                             edit cost allocations and default accounts
      PAYROLL_REPORT_VIEW    the payroll reports
   ------------------------------------------------------------------ */
;WITH p(PermissionCode, Module, [Action]) AS (
    SELECT * FROM (VALUES
        ('PAYROLL_BANK_VIEW',    'PayrollBank',    'View'),
        ('PAYROLL_BANK_PROCESS', 'PayrollBank',    'Process'),
        ('PAYROLL_GL_VIEW',      'PayrollGL',      'View'),
        ('PAYROLL_GL_POST',      'PayrollGL',      'Post'),
        ('PAYROLL_REPORT_VIEW',  'PayrollReport',  'View')) AS x(a, b, c)
)
INSERT INTO [Security].[Permissions] (PermissionCode, Module, [Action])
SELECT p.PermissionCode, p.Module, p.[Action]
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[Permissions] AS e WHERE e.PermissionCode = p.PermissionCode AND e.Deleted = 0);
GO

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] AS r
JOIN   [Security].[Permissions] AS p
       ON p.PermissionCode IN ('PAYROLL_BANK_VIEW', 'PAYROLL_BANK_PROCESS', 'PAYROLL_GL_VIEW', 'PAYROLL_GL_POST', 'PAYROLL_REPORT_VIEW')
WHERE  r.RoleCode = N'SYSADMIN'
  AND  p.Deleted = 0 AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

SET NOEXEC OFF;
GO
PRINT N'db/49 applied: bank files and payments, journals, cost allocations, PAYROLL_BANK_* / PAYROLL_GL_* / PAYROLL_REPORT_VIEW. Run db/50 next.';
GO
