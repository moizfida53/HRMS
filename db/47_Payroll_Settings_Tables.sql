/* =====================================================================
   47_Payroll_Settings_Tables.sql  -  HRMS Payroll Settings: rule tables
   ---------------------------------------------------------------------
   Run after 29-30 (payroll masters) and 34 (payroll runs). Idempotent
   (every object is guarded) - safe to re-run. Then run 48 (procedures)
   and 46 (labels).

   The five Payroll Settings screens that had no tables yet:

     Deduction Rules     Payroll.DeductionPolicies + DeductionPriorities
                         the maximum total deductions (% of gross) per
                         company (or the default for all), what happens
                         when it is exceeded, and the order deductions
                         are recovered in (top = taken first).
     Proration Rules     Payroll.ProrationRules
                         per payroll calendar: which events are prorated
                         (joiners, leavers, mid-period revisions, unpaid
                         leave) and whether weekly rest days count. The
                         day basis itself stays on the calendar
                         (PayrollCalendars.WorkingDaysBasis / FixedDaysPerMonth)
                         and is edited from this screen too.
     Approval Workflow   Payroll.ApprovalProcesses
                         per process (payroll run, salary revision, loan,
                         salary advance, payroll adjustment, final
                         settlement): the level 1 and level 2 approver
                         roles, delegates when away, the amount above
                         which level 2 is needed, self-approval.
     Bank Formats        Payroll.BankFileFormats + BankFileFormatFields
                         the salary (WPS) file layout per bank - one
                         default for banks without their own.
     GL Mapping          Payroll.GLMappings
                         the debit / credit GL accounts of a pay item type,
                         for a cost center or any; a pay item type's own
                         GL code stays the default.

   These are configuration: the payroll engine (db/35) keeps its current
   behaviour until it is extended to read them - see the README.

   Standing rule: nothing is ever physically deleted - every table carries
   Deleted / DeletedBy / DeletedDate (db/28 adds the delete guard trigger).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[PayComponents]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[Banks]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 29 and 30 (payroll masters) before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Deduction Rules
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[DeductionPolicies]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[DeductionPolicies](
        DeductionPolicyId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DeductionPolicies PRIMARY KEY,
        CompanyId            INT            NULL,           -- NULL = the default for every company
        PayrollCalendarId    INT            NULL,           -- NULL = every calendar of the company
        MaxDeductionPercent  DECIMAL(5,2)   NOT NULL CONSTRAINT DF_DeductionPolicies_Max DEFAULT (50),
        WhenExceeded         VARCHAR(10)    NOT NULL CONSTRAINT DF_DeductionPolicies_When DEFAULT ('DEFER'),
        Notes                NVARCHAR(500)  NULL,
        IsActive             BIT            NOT NULL CONSTRAINT DF_DeductionPolicies_IsActive DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_DeductionPolicies_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_DeductionPolicies_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_DeductionPolicies_Company  FOREIGN KEY (CompanyId)         REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_DeductionPolicies_Calendar FOREIGN KEY (PayrollCalendarId) REFERENCES [Payroll].[PayrollCalendars](PayrollCalendarId),
        CONSTRAINT CK_DeductionPolicies_Max      CHECK (MaxDeductionPercent > 0 AND MaxDeductionPercent <= 100),
        CONSTRAINT CK_DeductionPolicies_When     CHECK (WhenExceeded IN ('DEFER', 'WARN'))
    );
    /* one policy per company and calendar (and one default) */
    CREATE UNIQUE NONCLUSTERED INDEX UX_DeductionPolicies_Scope
        ON [Payroll].[DeductionPolicies](CompanyId, PayrollCalendarId) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[DeductionPriorities]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[DeductionPriorities](
        DeductionPriorityId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DeductionPriorities PRIMARY KEY,
        DeductionPolicyId    INT            NOT NULL,
        PriorityNo           SMALLINT       NOT NULL,       -- 1 = recovered first
        DeductionGroup       VARCHAR(15)    NOT NULL,
        Behaviour            VARCHAR(10)    NOT NULL,       -- ALWAYS (statutory, never deferred) / TAKEN / DEFER
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_DeductionPriorities_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_DeductionPriorities_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_DeductionPriorities_Policy FOREIGN KEY (DeductionPolicyId) REFERENCES [Payroll].[DeductionPolicies](DeductionPolicyId),
        CONSTRAINT CK_DeductionPriorities_Group  CHECK (DeductionGroup IN ('STATUTORY', 'ABSENCE', 'STANDING', 'ADVANCE', 'LOAN', 'ONE_TIME')),
        CONSTRAINT CK_DeductionPriorities_Beh    CHECK (Behaviour IN ('ALWAYS', 'TAKEN', 'DEFER'))
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_DeductionPriorities_Group
        ON [Payroll].[DeductionPriorities](DeductionPolicyId, DeductionGroup) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   2. Proration Rules (one row per payroll calendar)
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[ProrationRules]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[ProrationRules](
        ProrationRuleId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ProrationRules PRIMARY KEY,
        PayrollCalendarId    INT            NOT NULL,
        ProrateJoiners       BIT            NOT NULL CONSTRAINT DF_ProrationRules_Joiners   DEFAULT (1),
        ProrateLeavers       BIT            NOT NULL CONSTRAINT DF_ProrationRules_Leavers   DEFAULT (1),
        ProrateRevisions     BIT            NOT NULL CONSTRAINT DF_ProrationRules_Revisions DEFAULT (1),
        ProrateUnpaidLeave   BIT            NOT NULL CONSTRAINT DF_ProrationRules_Unpaid    DEFAULT (1),
        ExcludeRestDays      BIT            NOT NULL CONSTRAINT DF_ProrationRules_Rest      DEFAULT (1),   -- weekly rest days not counted as worked (WORKING basis)
        Notes                NVARCHAR(500)  NULL,
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_ProrationRules_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_ProrationRules_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_ProrationRules_Calendar FOREIGN KEY (PayrollCalendarId) REFERENCES [Payroll].[PayrollCalendars](PayrollCalendarId)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_ProrationRules_Calendar
        ON [Payroll].[ProrationRules](PayrollCalendarId) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   3. Approval Workflow
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[ApprovalProcesses]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[ApprovalProcesses](
        ApprovalProcessId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ApprovalProcesses PRIMARY KEY,
        ProcessCode          VARCHAR(20)    NOT NULL,
        CompanyId            INT            NULL,           -- NULL = the default for every company
        Level1RoleId         INT            NULL,
        Level1DelegateUserId BIGINT         NULL,
        Level2RoleId         INT            NULL,           -- NULL = one level only
        Level2DelegateUserId BIGINT         NULL,
        Level2AboveAmount    DECIMAL(12,3)  NULL,           -- NULL = level 2 always; else only above this amount (KWD)
        AllowSelfApproval    BIT            NOT NULL CONSTRAINT DF_ApprovalProcesses_Self DEFAULT (0),
        Notes                NVARCHAR(500)  NULL,
        IsActive             BIT            NOT NULL CONSTRAINT DF_ApprovalProcesses_IsActive DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_ApprovalProcesses_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_ApprovalProcesses_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_ApprovalProcesses_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_ApprovalProcesses_Code    CHECK (ProcessCode IN ('PAYROLL_RUN', 'SALARY_REVISION', 'LOAN', 'SALARY_ADVANCE', 'PAYROLL_ADJUSTMENT', 'FINAL_SETTLEMENT')),
        CONSTRAINT CK_ApprovalProcesses_Amount  CHECK (Level2AboveAmount IS NULL OR Level2AboveAmount >= 0)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_ApprovalProcesses_Scope
        ON [Payroll].[ApprovalProcesses](ProcessCode, CompanyId) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   4. Bank Formats
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[BankFileFormats]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[BankFileFormats](
        BankFileFormatId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BankFileFormats PRIMARY KEY,
        FormatCode           NVARCHAR(30)   NOT NULL,
        FormatName           NVARCHAR(150)  NOT NULL,
        BankId               INT            NULL,           -- NULL = for banks without their own format
        FileType             VARCHAR(10)    NOT NULL CONSTRAINT DF_BankFileFormats_Type DEFAULT ('CSV'),
        Delimiter            NVARCHAR(3)    NULL,           -- CSV / TXT only
        HasHeader            BIT            NOT NULL CONSTRAINT DF_BankFileFormats_Header  DEFAULT (1),
        HasTrailer           BIT            NOT NULL CONSTRAINT DF_BankFileFormats_Trailer DEFAULT (0),
        FileNamePattern      NVARCHAR(100)  NULL,           -- e.g. SAL_{EMPLOYER}_{PERIOD}.csv
        IsDefault            BIT            NOT NULL CONSTRAINT DF_BankFileFormats_Default DEFAULT (0),
        Notes                NVARCHAR(500)  NULL,
        IsActive             BIT            NOT NULL CONSTRAINT DF_BankFileFormats_IsActive DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_BankFileFormats_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_BankFileFormats_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_BankFileFormats_Bank FOREIGN KEY (BankId) REFERENCES [Payroll].[Banks](BankId),
        CONSTRAINT CK_BankFileFormats_Type CHECK (FileType IN ('CSV', 'TXT', 'FIXED'))
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankFileFormats_Code
        ON [Payroll].[BankFileFormats](FormatCode) WHERE Deleted = 0;
    /* one default format, and one active format per bank */
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankFileFormats_Default
        ON [Payroll].[BankFileFormats](IsDefault) WHERE IsDefault = 1 AND Deleted = 0;
    CREATE UNIQUE NONCLUSTERED INDEX UX_BankFileFormats_Bank
        ON [Payroll].[BankFileFormats](BankId) WHERE BankId IS NOT NULL AND IsActive = 1 AND Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[BankFileFormatFields]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[BankFileFormatFields](
        BankFileFormatFieldId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_BankFileFormatFields PRIMARY KEY,
        BankFileFormatId     INT            NOT NULL,
        FieldNo              SMALLINT       NOT NULL,
        FieldName            NVARCHAR(50)   NOT NULL,       -- the header text
        SourceCode           VARCHAR(20)    NOT NULL,
        ConstantValue        NVARCHAR(100)  NULL,           -- SourceCode = CONSTANT
        Width                SMALLINT       NULL,           -- FIXED files (and a maximum length otherwise)
        PadChar              NCHAR(1)       NULL,
        AlignRight           BIT            NOT NULL CONSTRAINT DF_BankFileFormatFields_Right DEFAULT (0),
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_BankFileFormatFields_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_BankFileFormatFields_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_BankFileFormatFields_Format FOREIGN KEY (BankFileFormatId) REFERENCES [Payroll].[BankFileFormats](BankFileFormatId),
        CONSTRAINT CK_BankFileFormatFields_Source CHECK (SourceCode IN ('EMPLOYER_CODE', 'PAM_FILE_NO', 'EMPLOYEE_CODE', 'CIVIL_ID', 'EMPLOYEE_NAME',
                                                                          'BANK_WPS_CODE', 'BANK_SWIFT', 'IBAN', 'ACCOUNT_NO', 'NET_AMOUNT',
                                                                          'BASIC_AMOUNT', 'ALLOWANCES', 'DEDUCTIONS', 'PERIOD_YYYYMM', 'PAY_DATE',
                                                                          'DEBIT_IBAN', 'CONSTANT')),
        CONSTRAINT CK_BankFileFormatFields_Width  CHECK (Width IS NULL OR Width BETWEEN 1 AND 500)
    );
    CREATE INDEX IX_BankFileFormatFields_Format
        ON [Payroll].[BankFileFormatFields](BankFileFormatId, FieldNo) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   5. GL Mapping
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[GLMappings]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[GLMappings](
        GLMappingId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_GLMappings PRIMARY KEY,
        PayComponentId       INT            NOT NULL,
        CostCenterId         INT            NULL,           -- NULL = any cost center
        DebitAccountCode     NVARCHAR(50)   NOT NULL,
        DebitAccountName     NVARCHAR(150)  NULL,
        CreditAccountCode    NVARCHAR(50)   NOT NULL,
        CreditAccountName    NVARCHAR(150)  NULL,
        Notes                NVARCHAR(500)  NULL,
        IsActive             BIT            NOT NULL CONSTRAINT DF_GLMappings_IsActive DEFAULT (1),
        CreatedBy            BIGINT         NULL,
        CreatedDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_GLMappings_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy           BIGINT         NULL,
        ModifiedDate         DATETIME2(0)   NULL,
        Deleted              BIT            NOT NULL CONSTRAINT DF_Payroll_GLMappings_Deleted DEFAULT (0),
        DeletedBy            BIGINT         NULL,
        DeletedDate          DATETIME2(7)   NULL,

        CONSTRAINT FK_GLMappings_Component  FOREIGN KEY (PayComponentId) REFERENCES [Payroll].[PayComponents](PayComponentId),
        CONSTRAINT FK_GLMappings_CostCenter FOREIGN KEY (CostCenterId)   REFERENCES [Core].[CostCenters](CostCenterId)
    );
    /* the most specific row wins - so one row per component and cost center */
    CREATE UNIQUE NONCLUSTERED INDEX UX_GLMappings_Scope
        ON [Payroll].[GLMappings](PayComponentId, CostCenterId) WHERE Deleted = 0;
END;
GO

/* The delete guard of db/28 for the new tables. */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'DeductionPolicies';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'DeductionPriorities';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'ProrationRules';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'ApprovalProcesses';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'BankFileFormats';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'BankFileFormatFields';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'GLMappings';
END;
GO

/* ------------------------------------------------------------------
   6. Starting data (only when empty) - the defaults of the approved designs
   ------------------------------------------------------------------ */
IF NOT EXISTS (SELECT 1 FROM [Payroll].[DeductionPolicies] WHERE CompanyId IS NULL AND PayrollCalendarId IS NULL AND Deleted = 0)
BEGIN
    DECLARE @PolicyId INT;
    INSERT INTO [Payroll].[DeductionPolicies] (CompanyId, PayrollCalendarId, MaxDeductionPercent, WhenExceeded, Notes)
    VALUES (NULL, NULL, 50, 'DEFER', N'Default for every company - starting value, to be confirmed.');
    SET @PolicyId = SCOPE_IDENTITY();
    INSERT INTO [Payroll].[DeductionPriorities] (DeductionPolicyId, PriorityNo, DeductionGroup, Behaviour)
    VALUES (@PolicyId, 1, 'STATUTORY', 'ALWAYS'), (@PolicyId, 2, 'ABSENCE', 'ALWAYS'), (@PolicyId, 3, 'STANDING', 'TAKEN'),
           (@PolicyId, 4, 'ADVANCE', 'DEFER'), (@PolicyId, 5, 'LOAN', 'DEFER'), (@PolicyId, 6, 'ONE_TIME', 'DEFER');
END;
GO

/* the default approval route of every process: HR manager, then finance (no self-approval) -
   the roles are filled in from the screen (they are the client's own roles) */
;WITH p(Code, AboveAmount) AS (
    SELECT * FROM (VALUES ('PAYROLL_RUN', NULL), ('SALARY_REVISION', NULL), ('LOAN', NULL),
                          ('SALARY_ADVANCE', CAST(300 AS DECIMAL(12,3))), ('PAYROLL_ADJUSTMENT', CAST(100 AS DECIMAL(12,3))),
                          ('FINAL_SETTLEMENT', NULL)) AS x(a, b)
)
INSERT INTO [Payroll].[ApprovalProcesses] (ProcessCode, CompanyId, Level2AboveAmount, AllowSelfApproval)
SELECT p.Code, NULL, p.AboveAmount, 0
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[ApprovalProcesses] a WHERE a.ProcessCode = p.Code AND a.CompanyId IS NULL AND a.Deleted = 0);
GO

IF NOT EXISTS (SELECT 1 FROM [Payroll].[BankFileFormats] WHERE Deleted = 0)
BEGIN
    DECLARE @FormatId INT;
    INSERT INTO [Payroll].[BankFileFormats] (FormatCode, FormatName, BankId, FileType, Delimiter, HasHeader, HasTrailer, FileNamePattern, IsDefault, Notes)
    VALUES (N'WPS_CSV', N'Default WPS CSV', NULL, 'CSV', N',', 1, 0, N'SAL_{EMPLOYER}_{PERIOD}.csv', 1,
            N'Used for every bank without its own format until the banks confirm their layouts.');
    SET @FormatId = SCOPE_IDENTITY();
    INSERT INTO [Payroll].[BankFileFormatFields] (BankFileFormatId, FieldNo, FieldName, SourceCode, Width)
    VALUES (@FormatId, 1, N'EmployerCode', 'EMPLOYER_CODE', NULL), (@FormatId, 2, N'EmployeeCode', 'EMPLOYEE_CODE', NULL),
           (@FormatId, 3, N'CivilID', 'CIVIL_ID', 12), (@FormatId, 4, N'Name', 'EMPLOYEE_NAME', 70),
           (@FormatId, 5, N'BankCode', 'BANK_WPS_CODE', NULL), (@FormatId, 6, N'IBAN', 'IBAN', 30),
           (@FormatId, 7, N'Amount', 'NET_AMOUNT', NULL), (@FormatId, 8, N'Period', 'PERIOD_YYYYMM', 6);
END;
GO

SET NOEXEC OFF;
GO
PRINT N'db/47 applied: deduction, proration, approval, bank file format and GL mapping tables. Run db/48 next.';
GO
