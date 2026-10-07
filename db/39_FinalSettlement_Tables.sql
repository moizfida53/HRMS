/* =====================================================================
   39_FinalSettlement_Tables.sql  -  HRMS Payroll: Final Settlement
   ---------------------------------------------------------------------
   Run after 34-38. Idempotent (every object is guarded) - safe to re-run.

   What a final settlement is
     The end-of-service payment of ONE employee who leaves (resignation,
     termination, end of contract, retirement, death, disability), or a
     leave encashment WITHOUT exit (type ENCASHMENT). It is numbered
     FS-<YYYY>-<MM>-<NNN> per company and month of the last working day.
       DRAFT  ->  PENDING (level 1 HR, level 2 Finance)  ->  APPROVED  ->  PAID
       CANCELLED from DRAFT or PENDING (a rejected settlement is cancelled;
       a returned one goes back to DRAFT). It keeps its number.

   Tables
     Payroll.FinalSettlements        header: employee, separation, inputs
                                     (salary unpaid from, leave balance),
                                     the bases used and the section totals
     Payroll.FinalSettlementLines    the calculated lines (salary per month
                                     and item, unpaid pay items, leave,
                                     indemnity slabs, loans and other
                                     recoveries) and the lines added by hand
     Payroll.FinalSettlementHistory  every change, submission and approval

   Also
     Pay item type LEAVE_ENC (SystemCode LEAVE_ENCASH) for every company - an
     approved leave encashment without exit becomes a one-time earning of
     this type, paid by the payroll of the month chosen on it.
     Permissions PAYROLL_FS_VIEW / PROCESS / PAY / CANCEL (to SYSADMIN).
     Approving uses the payroll approval permissions
     PAYROLL_RUN_APPROVE_HR and PAYROLL_RUN_APPROVE_FINANCE.

   After this script run 40 (procedures), then re-run 35 (the payroll
   engine leaves out employees whose settlement pays their last salary)
   and 41 (labels).

   Standing rule: nothing is physically deleted (Deleted bit).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH(N'Payroll.EmployeePayItems', N'ApprovalLevel') IS NULL OR OBJECT_ID(N'[Payroll].[IndemnityRuleSets]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 29 to 38 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Payroll.FinalSettlements
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[FinalSettlements](
        FinalSettlementId     BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FinalSettlements PRIMARY KEY,
        CompanyId             INT            NOT NULL,
        EmployeeId            BIGINT         NOT NULL,
        SettlementNo          NVARCHAR(30)   NOT NULL,
        SettlementSeq         SMALLINT       NOT NULL,
        SettlementType        VARCHAR(20)    NOT NULL,
        Status                VARCHAR(10)    NOT NULL CONSTRAINT DF_FinalSettlements_Status DEFAULT ('DRAFT'),
        ApprovalLevel         TINYINT        NOT NULL CONSTRAINT DF_FinalSettlements_ApprovalLevel DEFAULT (0),

        /* ---- inputs ---- */
        LastWorkingDay        DATE           NOT NULL,      -- ENCASHMENT: the date the leave balance is taken on
        NoticeDate            DATE           NULL,
        Reason                NVARCHAR(500)  NULL,
        SalaryFrom            DATE           NULL,          -- first day not paid by a payroll (pending salary SalaryFrom..LastWorkingDay)
        LeaveBalanceDays      DECIMAL(7,2)   NOT NULL CONSTRAINT DF_FinalSettlements_LeaveBalance DEFAULT (0),
        EncashDays            DECIMAL(7,2)   NOT NULL CONSTRAINT DF_FinalSettlements_EncashDays DEFAULT (0),
        PayMonth              DATE           NULL,          -- ENCASHMENT: the payroll month that pays it

        /* ---- snapshot of the employee and the bases used ---- */
        HireDate              DATE           NULL,
        ServiceDays           INT            NOT NULL CONSTRAINT DF_FinalSettlements_ServiceDays DEFAULT (0),
        ServiceYears          DECIMAL(9,4)   NOT NULL CONSTRAINT DF_FinalSettlements_ServiceYears DEFAULT (0),
        IsKuwaiti             BIT            NOT NULL CONSTRAINT DF_FinalSettlements_IsKuwaiti DEFAULT (0),
        MonthlySalary         DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_MonthlySalary DEFAULT (0),
        IndemnityBase         DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_IndemnityBase DEFAULT (0),
        LeaveBase             DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_LeaveBase DEFAULT (0),
        DailyDivisor          DECIMAL(5,2)   NOT NULL CONSTRAINT DF_FinalSettlements_Divisor DEFAULT (26),
        SalaryFromProfile     BIT            NOT NULL CONSTRAINT DF_FinalSettlements_FromProfile DEFAULT (0),
        IndemnityRuleSetId    INT            NULL,
        RuleSetVerified       BIT            NOT NULL CONSTRAINT DF_FinalSettlements_RuleVerified DEFAULT (0),
        IndemnityGross        DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_IndGross DEFAULT (0),
        IndemnityCap          DECIMAL(12,3)  NULL,
        IndemnityPercent      DECIMAL(7,4)   NOT NULL CONSTRAINT DF_FinalSettlements_IndPct DEFAULT (0),
        BelowMinService       BIT            NOT NULL CONSTRAINT DF_FinalSettlements_BelowMin DEFAULT (0),

        /* ---- totals (refreshed on every calculation; recoveries negative) ---- */
        PendingSalaryAmount   DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Pending DEFAULT (0),
        OtherEarningsAmount   DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Earnings DEFAULT (0),
        LeaveAmount           DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Leave DEFAULT (0),
        IndemnityAmount       DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Indemnity DEFAULT (0),
        RecoveryAmount        DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Recovery DEFAULT (0),
        NetPayable            DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlements_Net DEFAULT (0),
        CalculatedDate        DATETIME2(0)   NULL,

        /* ---- workflow ---- */
        AckUnverified         BIT            NOT NULL CONSTRAINT DF_FinalSettlements_Ack DEFAULT (0),
        SubmittedBy           BIGINT         NULL,
        SubmittedDate         DATETIME2(0)   NULL,
        ApprovedBy            BIGINT         NULL,
        ApprovedDate          DATETIME2(0)   NULL,
        PaidDate              DATE           NULL,
        PaymentMethod         VARCHAR(10)    NULL,
        PaymentRef            NVARCHAR(100)  NULL,
        PaidBy                BIGINT         NULL,
        PayItemId             BIGINT         NULL,          -- ENCASHMENT: the earning created on approval
        CancelledBy           BIGINT         NULL,
        CancelledDate         DATETIME2(0)   NULL,
        CancelReason          NVARCHAR(500)  NULL,

        CreatedBy             BIGINT         NULL,
        CreatedDate           DATETIME2(0)   NOT NULL CONSTRAINT DF_FinalSettlements_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy            BIGINT         NULL,
        ModifiedDate          DATETIME2(0)   NULL,
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_FinalSettlements_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_FinalSettlements_Company  FOREIGN KEY (CompanyId)          REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_FinalSettlements_Employee FOREIGN KEY (EmployeeId)         REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_FinalSettlements_RuleSet  FOREIGN KEY (IndemnityRuleSetId) REFERENCES [Payroll].[IndemnityRuleSets](IndemnityRuleSetId),
        CONSTRAINT FK_FinalSettlements_PayItem  FOREIGN KEY (PayItemId)          REFERENCES [Payroll].[EmployeePayItems](EmployeePayItemId),
        CONSTRAINT CK_FinalSettlements_Type     CHECK (SettlementType IN ('RESIGNATION', 'TERMINATION', 'CONTRACT_END', 'RETIREMENT', 'DEATH', 'DISABILITY', 'ENCASHMENT')),
        CONSTRAINT CK_FinalSettlements_Status   CHECK (Status IN ('DRAFT', 'PENDING', 'APPROVED', 'PAID', 'CANCELLED')),
        CONSTRAINT CK_FinalSettlements_Level    CHECK (ApprovalLevel BETWEEN 0 AND 2),
        CONSTRAINT CK_FinalSettlements_Leave    CHECK (LeaveBalanceDays >= 0 AND EncashDays >= 0 AND EncashDays <= LeaveBalanceDays),
        CONSTRAINT CK_FinalSettlements_PayMonth CHECK (PayMonth IS NULL OR DAY(PayMonth) = 1),
        CONSTRAINT CK_FinalSettlements_Method   CHECK (PaymentMethod IS NULL OR PaymentMethod IN ('BANK', 'CHEQUE', 'CASH', 'PAYROLL'))
    );

    CREATE UNIQUE NONCLUSTERED INDEX UX_FinalSettlements_No
        ON [Payroll].[FinalSettlements](CompanyId, SettlementNo) WHERE Deleted = 0;
    /* one live exit settlement per employee (cancel it to start another) */
    CREATE UNIQUE NONCLUSTERED INDEX UX_FinalSettlements_OneExit
        ON [Payroll].[FinalSettlements](EmployeeId)
        WHERE SettlementType <> 'ENCASHMENT' AND Status <> 'CANCELLED' AND Deleted = 0;
    CREATE INDEX IX_FinalSettlements_List
        ON [Payroll].[FinalSettlements](CompanyId, Status, LastWorkingDay)
        INCLUDE (EmployeeId, SettlementNo, SettlementType, NetPayable) WHERE Deleted = 0;
    CREATE INDEX IX_FinalSettlements_Employee
        ON [Payroll].[FinalSettlements](EmployeeId, Status) INCLUDE (SettlementType, SalaryFrom, LastWorkingDay) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   2. Payroll.FinalSettlementLines  (Amount signed: recoveries negative)
        Section   SALARY     salary for the unpaid days, per month and item
                  EARNING    unpaid earnings (pay items) and earnings added by hand
                  LEAVE      leave encashment
                  INDEMNITY  the slabs of the indemnity (IsInfo = 1: shown,
                             not added up - the header carries the payable)
                  RECOVERY   loans, advances, unpaid deductions, PIFSS on the
                             pending salary, and recoveries added by hand
        LineCode  SALARY / PAY_ITEM / LEAVE / IND_SLAB / LOAN / PIFSS / MANUAL
        IsIncluded = 0: an automatic line waived by the user (kept on recalculation)
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[FinalSettlementLines]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[FinalSettlementLines](
        SettlementLineId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FinalSettlementLines PRIMARY KEY,
        FinalSettlementId     BIGINT         NOT NULL,
        Section               VARCHAR(10)    NOT NULL,
        LineCode              VARCHAR(10)    NOT NULL,
        IsManual              BIT            NOT NULL CONSTRAINT DF_FinalSettlementLines_IsManual DEFAULT (0),
        IsInfo                BIT            NOT NULL CONSTRAINT DF_FinalSettlementLines_IsInfo DEFAULT (0),
        IsIncluded            BIT            NOT NULL CONSTRAINT DF_FinalSettlementLines_IsIncluded DEFAULT (1),
        Description           NVARCHAR(300)  NULL,
        ArabicDescription     NVARCHAR(300)  NULL,
        PayComponentId        INT            NULL,
        EmployeePayItemId     BIGINT         NULL,
        SourceRef             NVARCHAR(50)   NULL,
        PeriodFrom            DATE           NULL,
        PeriodTo              DATE           NULL,
        Quantity              DECIMAL(12,4)  NULL,          -- days / years / instalments
        Rate                  DECIMAL(14,6)  NULL,          -- days in month / days per year / %
        Basis                 DECIMAL(12,3)  NULL,          -- monthly amount / base
        FromYears             DECIMAL(5,2)   NULL,
        ToYears               DECIMAL(5,2)   NULL,
        Unit                  VARCHAR(6)     NULL,
        Amount                DECIMAL(12,3)  NOT NULL CONSTRAINT DF_FinalSettlementLines_Amount DEFAULT (0),
        DisplayOrder          SMALLINT       NOT NULL CONSTRAINT DF_FinalSettlementLines_DisplayOrder DEFAULT (100),
        CreatedBy             BIGINT         NULL,
        CreatedDate           DATETIME2(0)   NOT NULL CONSTRAINT DF_FinalSettlementLines_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_FinalSettlementLines_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_FinalSettlementLines_Settlement FOREIGN KEY (FinalSettlementId) REFERENCES [Payroll].[FinalSettlements](FinalSettlementId),
        CONSTRAINT FK_FinalSettlementLines_PayItem    FOREIGN KEY (EmployeePayItemId) REFERENCES [Payroll].[EmployeePayItems](EmployeePayItemId),
        CONSTRAINT CK_FinalSettlementLines_Section    CHECK (Section IN ('SALARY', 'EARNING', 'LEAVE', 'INDEMNITY', 'RECOVERY')),
        CONSTRAINT CK_FinalSettlementLines_Code       CHECK (LineCode IN ('SALARY', 'PAY_ITEM', 'LEAVE', 'IND_SLAB', 'LOAN', 'PIFSS', 'MANUAL')),
        CONSTRAINT CK_FinalSettlementLines_Sign       CHECK ((Section = 'RECOVERY' AND Amount <= 0) OR (Section <> 'RECOVERY' AND Amount >= 0))
    );
    CREATE INDEX IX_FinalSettlementLines_Settlement
        ON [Payroll].[FinalSettlementLines](FinalSettlementId, Section, DisplayOrder) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   3. Payroll.FinalSettlementHistory
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[FinalSettlementHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[FinalSettlementHistory](
        SettlementHistoryId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_FinalSettlementHistory PRIMARY KEY,
        FinalSettlementId     BIGINT         NOT NULL,
        ActionCode            VARCHAR(20)    NOT NULL,
        ApprovalLevel         TINYINT        NULL,
        NetPayable            DECIMAL(12,3)  NULL,
        Comment               NVARCHAR(500)  NULL,
        ActionBy              BIGINT         NULL,
        ActionDate            DATETIME2(0)   NOT NULL CONSTRAINT DF_FinalSettlementHistory_Date DEFAULT (SYSUTCDATETIME()),
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_FinalSettlementHistory_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_FinalSettlementHistory_Settlement FOREIGN KEY (FinalSettlementId) REFERENCES [Payroll].[FinalSettlements](FinalSettlementId),
        CONSTRAINT CK_FinalSettlementHistory_Action CHECK (ActionCode IN ('CREATED', 'CHANGED', 'LINE_ADDED', 'LINE_REMOVED', 'LINE_WAIVED', 'LINE_RESTORED',
                                                                          'SUBMITTED', 'APPROVED', 'RETURNED', 'REJECTED', 'PAID', 'CANCELLED'))
    );
    CREATE INDEX IX_FinalSettlementHistory_Settlement
        ON [Payroll].[FinalSettlementHistory](FinalSettlementId, ActionDate) WHERE Deleted = 0;
END;
GO

/* the delete guard of db/28 (INSTEAD OF DELETE -> Deleted = 1) */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'FinalSettlements';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'FinalSettlementLines';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'FinalSettlementHistory';
END;
GO

/* ------------------------------------------------------------------
   4. Pay item type for leave encashment (every company that has payroll)
      EARNING, variable, not recurring -> ItemClass EARNING (one time)
   ------------------------------------------------------------------ */
INSERT INTO [Payroll].[PayComponents]
    (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod,
     IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable, IsRecurring, IsProrated, ShowOnPayslip,
     DisplayOrder, SystemCode, IsSystem, Description, IsActive)
SELECT c.CompanyId, N'LEAVE_ENC', N'Leave Encashment', N'بدل رصيد الإجازات', N'Leave Encashment', 'EARNING', 'VARIABLE', 'AMOUNT',
       0, 0, 0, 0, 0, 0, 0, 1,
       180, 'LEAVE_ENCASH', 1, N'Paid when a leave encashment (Final Settlement) is approved.', 1
FROM   [Core].[Companies] AS c
WHERE  c.Deleted = 0
  AND  EXISTS (SELECT 1 FROM [Payroll].[PayComponents] AS b WHERE b.CompanyId = c.CompanyId AND b.SystemCode = 'BASIC' AND b.Deleted = 0)
  AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] AS x
                   WHERE x.CompanyId = c.CompanyId AND x.Deleted = 0 AND (x.SystemCode = 'LEAVE_ENCASH' OR x.ComponentCode = N'LEAVE_ENC'));
PRINT CONCAT(N'Leave encashment pay item types added: ', @@ROWCOUNT);
GO

/* ------------------------------------------------------------------
   5. Permissions (granted to SYSADMIN)
      PAYROLL_FS_VIEW     see settlements and statements
      PAYROLL_FS_PROCESS  create, change, calculate and submit settlements
      PAYROLL_FS_PAY      record the payment of an approved settlement
      PAYROLL_FS_CANCEL   cancel a draft or pending settlement
   ------------------------------------------------------------------ */
;WITH p(PermissionCode, Module, [Action]) AS (
    SELECT * FROM (VALUES
        ('PAYROLL_FS_VIEW',    'FinalSettlement', 'View'),
        ('PAYROLL_FS_PROCESS', 'FinalSettlement', 'Process'),
        ('PAYROLL_FS_PAY',     'FinalSettlement', 'Pay'),
        ('PAYROLL_FS_CANCEL',  'FinalSettlement', 'Cancel')) AS x(a, b, c)
)
INSERT INTO [Security].[Permissions] (PermissionCode, Module, [Action])
SELECT p.PermissionCode, p.Module, p.[Action]
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[Permissions] AS e WHERE e.PermissionCode = p.PermissionCode AND e.Deleted = 0);
GO

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] AS r
JOIN   [Security].[Permissions] AS p ON p.PermissionCode LIKE 'PAYROLL[_]FS[_]%'
WHERE  r.RoleCode = N'SYSADMIN'
  AND  p.Deleted = 0 AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

SET NOEXEC OFF;
GO
PRINT N'db/39 applied: final settlement tables, LEAVE_ENC pay item type, PAYROLL_FS_* permissions.';
GO
