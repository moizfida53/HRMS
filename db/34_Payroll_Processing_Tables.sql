/* =====================================================================
   34_Payroll_Processing_Tables.sql  -  HRMS Payroll Phase 2: payroll runs
   ---------------------------------------------------------------------
   Run after 33. Idempotent (every object is guarded) - safe to re-run.

   What a payroll run is
     A run ("payroll") is created for ONE company, calendar and period and
     gets a generated name  <CompanyCode>-<YYYY>-<MM>-<NN>  where NN is the
     running number of payrolls for that company and month (from 01, shared
     by every calendar; a cancelled run keeps its number).
     Stages:  DRAFT (wizard only, never listed)  ->  REGISTERED  ->
              VALIDATION  ->  AWAITING_APPROVAL (level 1 HR, level 2
              Finance)  ->  CLOSED,  or CANCELLED at any point before CLOSED.

   Tables
     Payroll.EmployeePayItems     every amount an employee is paid or has
                                  deducted, one line per item (Salary,
                                  Earning, Deduction, Loan) with a comment.
                                  Replaces separate salary / variable-input /
                                  loan screens (feedback round 3). Items added
                                  inside a payroll carry its PayrollRunId.
     Payroll.PayrollRuns          the run header, scope, stage and totals
     Payroll.PayrollRunEmployees  one row per employee in the run (snapshot)
     Payroll.PayrollRunLines      the calculated lines of each employee
     Payroll.PayrollRunIssues     validation errors / warnings + acknowledgement
     Payroll.PayrollRunHistory    every stage change and approval

   Also
     Payroll.PayComponents.ItemClass  computed: SALARY / EARNING / DEDUCTION /
                                      LOAN / STATUTORY (how a pay item type is
                                      grouped on screen and in the engine)
     Existing Employee.EmployeePayroll basic salary and allowances are copied
     to salary items once (comment "Moved from the employee profile").
     Permissions PAYROLL_RUN_* granted to SYSADMIN.

   Standing rule: nothing is ever physically deleted - every table carries
   Deleted / DeletedBy / DeletedDate (db/28 adds the delete guard trigger).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[PayComponents]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[PayrollPeriods]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 29 to 32 (Payroll Phase 1) before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Pay item class on the pay item types (computed, never stale)
   ------------------------------------------------------------------ */
IF COL_LENGTH(N'Payroll.PayComponents', N'ItemClass') IS NULL
    ALTER TABLE [Payroll].[PayComponents] ADD ItemClass AS (
        CAST(CASE
                WHEN SystemCode = 'PIFSS_EE'                                   THEN 'STATUTORY'
                WHEN SystemCode IN ('LOAN', 'SALARY_ADVANCE')                  THEN 'LOAN'
                WHEN ComponentType = 'EARNING' AND IsRecurring = 1
                     AND ValueType = 'FIXED'                                   THEN 'SALARY'
                WHEN ComponentType = 'EARNING'                                 THEN 'EARNING'
                ELSE 'DEDUCTION'
             END AS VARCHAR(10)));
GO

/* ------------------------------------------------------------------
   2. Payroll.EmployeePayItems
      Amount is always positive; the class decides the sign.
        MONTHLY     every month from StartMonth (to EndMonth when set)
        ONCE        only in StartMonth (or only in PayrollRunId when set)
        INSTALMENT  Amount per month from StartMonth, InstalmentCount times
                    (TotalAmount = the loan / recovery total)
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[EmployeePayItems]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[EmployeePayItems](
        EmployeePayItemId   BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeePayItems PRIMARY KEY,
        CompanyId           INT            NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        PayComponentId      INT            NOT NULL,
        Amount              DECIMAL(12,3)  NOT NULL,
        AppliesMode         VARCHAR(10)    NOT NULL CONSTRAINT DF_EmployeePayItems_AppliesMode DEFAULT ('ONCE'),
        StartMonth          DATE           NOT NULL,
        EndMonth            DATE           NULL,
        InstalmentCount     SMALLINT       NULL,
        TotalAmount         DECIMAL(12,3)  NULL,
        Comment             NVARCHAR(500)  NULL,
        Status              VARCHAR(10)    NOT NULL CONSTRAINT DF_EmployeePayItems_Status DEFAULT ('ACTIVE'),
        PayrollRunId        BIGINT         NULL,
        SourceRef           NVARCHAR(50)   NULL,
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_EmployeePayItems_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_EmployeePayItems_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_EmployeePayItems_Company   FOREIGN KEY (CompanyId)      REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_EmployeePayItems_Employee  FOREIGN KEY (EmployeeId)     REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_EmployeePayItems_Component FOREIGN KEY (PayComponentId) REFERENCES [Payroll].[PayComponents](PayComponentId),
        CONSTRAINT CK_EmployeePayItems_Amount    CHECK (Amount >= 0),
        CONSTRAINT CK_EmployeePayItems_Mode      CHECK (AppliesMode IN ('MONTHLY', 'ONCE', 'INSTALMENT')),
        CONSTRAINT CK_EmployeePayItems_Status    CHECK (Status IN ('ACTIVE', 'PENDING', 'ENDED')),
        CONSTRAINT CK_EmployeePayItems_Start     CHECK (DAY(StartMonth) = 1),
        CONSTRAINT CK_EmployeePayItems_End       CHECK (EndMonth IS NULL OR (DAY(EndMonth) = 1 AND EndMonth >= StartMonth)),
        CONSTRAINT CK_EmployeePayItems_Instal    CHECK (AppliesMode <> 'INSTALMENT' OR (InstalmentCount IS NOT NULL AND InstalmentCount BETWEEN 1 AND 600))
    );
    CREATE INDEX IX_EmployeePayItems_Employee ON [Payroll].[EmployeePayItems](EmployeeId, Status, StartMonth)
        INCLUDE (PayComponentId, Amount, AppliesMode, EndMonth, PayrollRunId) WHERE Deleted = 0;
    CREATE INDEX IX_EmployeePayItems_Run ON [Payroll].[EmployeePayItems](PayrollRunId) WHERE Deleted = 0 AND PayrollRunId IS NOT NULL;
END;
GO

/* ------------------------------------------------------------------
   3. Payroll.PayrollRuns
      The client's base schema already has an (empty) Payroll.PayrollRuns
      with a different structure (PayrollRunId, PayrollPeriodId, RunNo ...).
      It is RENAMED to Payroll.PayrollRuns_Legacy - with its constraints and
      triggers - so nothing is dropped and its foreign keys keep working.
      If it holds rows the script stops and changes nothing.
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[PayrollRuns]', N'U') IS NOT NULL AND COL_LENGTH(N'Payroll.PayrollRuns', N'RunCode') IS NULL
BEGIN
    DECLARE @LegacyRows BIGINT = 0;
    EXEC sys.sp_executesql N'SELECT @n = COUNT_BIG(*) FROM [Payroll].[PayrollRuns];', N'@n BIGINT OUTPUT', @n = @LegacyRows OUTPUT;

    IF @LegacyRows > 0
    BEGIN
        RAISERROR (N'STOPPED - the base-schema table Payroll.PayrollRuns already holds %I64d row(s). Move or archive them, then re-run this script. Nothing was changed.', 16, 1, @LegacyRows);
        SET NOEXEC ON;
    END
    ELSE
    BEGIN
        DECLARE @oid INT = OBJECT_ID(N'[Payroll].[PayrollRuns]'), @obj SYSNAME, @newName SYSNAME, @full NVARCHAR(400);

        /* constraints and triggers of the old table get a _Legacy suffix (their names are schema-wide) */
        DECLARE legacy CURSOR LOCAL FAST_FORWARD FOR
            SELECT o.name FROM sys.objects AS o
            WHERE  o.parent_object_id = @oid AND o.type IN ('PK', 'UQ', 'F', 'C', 'D', 'TR');
        OPEN legacy;
        FETCH NEXT FROM legacy INTO @obj;
        WHILE @@FETCH_STATUS = 0
        BEGIN
            SET @newName = LEFT(@obj, 120) + N'_Legacy';
            SET @full = N'[Payroll].' + QUOTENAME(@obj);
            EXEC sys.sp_rename @objname = @full, @newname = @newName, @objtype = 'OBJECT';
            FETCH NEXT FROM legacy INTO @obj;
        END;
        CLOSE legacy; DEALLOCATE legacy;

        DECLARE @tableName SYSNAME = N'PayrollRuns_Legacy', @i INT = 2;
        WHILE OBJECT_ID(N'[Payroll].' + QUOTENAME(@tableName), N'U') IS NOT NULL
        BEGIN
            SET @tableName = CONCAT(N'PayrollRuns_Legacy', @i);
            SET @i += 1;
        END;
        EXEC sys.sp_rename @objname = N'[Payroll].[PayrollRuns]', @newname = @tableName, @objtype = 'OBJECT';
        PRINT N'NOTE: the empty base-schema table Payroll.PayrollRuns was renamed to Payroll.' + @tableName + N' (not dropped).';
    END;
END;
GO

IF OBJECT_ID(N'[Payroll].[PayrollRuns]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollRuns](
        PayrollRunId          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollRuns PRIMARY KEY,
        CompanyId             INT            NOT NULL,
        PayrollCalendarId     INT            NOT NULL,
        PayrollPeriodId       INT            NOT NULL,
        RunMonth              DATE           NOT NULL,              -- first day of the period's payroll month
        RunSeq                SMALLINT       NULL,                  -- set when the draft is created as a payroll
        RunCode               NVARCHAR(40)   NULL,
        RunType               VARCHAR(10)    NOT NULL CONSTRAINT DF_PayrollRuns_RunType DEFAULT ('REGULAR'),
        Description           NVARCHAR(500)  NULL,
        Stage                 VARCHAR(20)    NOT NULL CONSTRAINT DF_PayrollRuns_Stage DEFAULT ('DRAFT'),
        ApprovalLevel         TINYINT        NOT NULL CONSTRAINT DF_PayrollRuns_ApprovalLevel DEFAULT (0),

        /* scope - who is included (NULL = everyone) */
        ScopeDepartmentId     INT            NULL,
        ScopeWorkLocationId   INT            NULL,
        ScopeEmploymentType   NVARCHAR(20)   NULL,
        ScopeNationality      VARCHAR(12)    NULL,

        /* totals (refreshed on every calculation) */
        EmployeeCount         INT            NOT NULL CONSTRAINT DF_PayrollRuns_EmployeeCount DEFAULT (0),
        ExcludedCount         INT            NOT NULL CONSTRAINT DF_PayrollRuns_ExcludedCount DEFAULT (0),
        TotalSalary           DECIMAL(14,3)  NOT NULL CONSTRAINT DF_PayrollRuns_TotalSalary DEFAULT (0),
        TotalEarnings         DECIMAL(14,3)  NOT NULL CONSTRAINT DF_PayrollRuns_TotalEarnings DEFAULT (0),
        TotalDeductions       DECIMAL(14,3)  NOT NULL CONSTRAINT DF_PayrollRuns_TotalDeductions DEFAULT (0),
        TotalNet              DECIMAL(14,3)  NOT NULL CONSTRAINT DF_PayrollRuns_TotalNet DEFAULT (0),
        ErrorCount            INT            NOT NULL CONSTRAINT DF_PayrollRuns_ErrorCount DEFAULT (0),
        WarningCount          INT            NOT NULL CONSTRAINT DF_PayrollRuns_WarningCount DEFAULT (0),

        CalculatedBy          BIGINT         NULL,
        CalculatedDate        DATETIME2(0)   NULL,
        ValidatedDate         DATETIME2(0)   NULL,
        SubmittedBy           BIGINT         NULL,
        SubmittedDate         DATETIME2(0)   NULL,
        ClosedBy              BIGINT         NULL,
        ClosedDate            DATETIME2(0)   NULL,
        CancelledBy           BIGINT         NULL,
        CancelledDate         DATETIME2(0)   NULL,
        CancelReason          NVARCHAR(500)  NULL,
        CreatedBy             BIGINT         NULL,
        CreatedDate           DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollRuns_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy            BIGINT         NULL,
        ModifiedDate          DATETIME2(0)   NULL,
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollRuns_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollRuns_Company  FOREIGN KEY (CompanyId)         REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_PayrollRuns_Calendar FOREIGN KEY (PayrollCalendarId) REFERENCES [Payroll].[PayrollCalendars](PayrollCalendarId),
        CONSTRAINT FK_PayrollRuns_Period   FOREIGN KEY (PayrollPeriodId)   REFERENCES [Payroll].[PayrollPeriods](PayrollPeriodId),
        CONSTRAINT CK_PayrollRuns_Type     CHECK (RunType IN ('REGULAR', 'OFFCYCLE')),
        CONSTRAINT CK_PayrollRuns_Stage    CHECK (Stage IN ('DRAFT', 'REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED', 'CANCELLED')),
        CONSTRAINT CK_PayrollRuns_Month    CHECK (DAY(RunMonth) = 1),
        CONSTRAINT CK_PayrollRuns_Level    CHECK (ApprovalLevel BETWEEN 0 AND 2),
        CONSTRAINT CK_PayrollRuns_Nat      CHECK (ScopeNationality IS NULL OR ScopeNationality IN ('KUWAITI', 'NON_KUWAITI')),
        CONSTRAINT CK_PayrollRuns_Code     CHECK (Stage = 'DRAFT' OR (RunSeq IS NOT NULL AND RunCode IS NOT NULL))
    );

    /* the run name is unique per company; the number per company and month */
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollRuns_Code
        ON [Payroll].[PayrollRuns](CompanyId, RunCode) WHERE RunCode IS NOT NULL AND Deleted = 0;
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollRuns_Seq
        ON [Payroll].[PayrollRuns](CompanyId, RunMonth, RunSeq) WHERE RunSeq IS NOT NULL AND Deleted = 0;
    /* one live regular payroll per calendar and period (cancel it to run another) */
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollRuns_OneRegular
        ON [Payroll].[PayrollRuns](PayrollCalendarId, PayrollPeriodId)
        WHERE RunType = 'REGULAR' AND Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED') AND Deleted = 0;
    CREATE INDEX IX_PayrollRuns_List
        ON [Payroll].[PayrollRuns](CompanyId, RunMonth, Stage) INCLUDE (RunCode, RunType, TotalNet, EmployeeCount) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   4. Payroll.PayrollRunEmployees - snapshot of each employee in a run
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[PayrollRunEmployees]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollRunEmployees](
        RunEmployeeId       BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollRunEmployees PRIMARY KEY,
        PayrollRunId        BIGINT         NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        EmployeeNo          NVARCHAR(20)   NULL,
        EmployeeName        NVARCHAR(300)  NULL,
        ArabicName          NVARCHAR(300)  NULL,
        DepartmentId        INT            NULL,
        DepartmentName      NVARCHAR(150)  NULL,
        CostCenterId        INT            NULL,
        IsKuwaiti           BIT            NOT NULL CONSTRAINT DF_PayrollRunEmployees_IsKuwaiti DEFAULT (0),
        EmploymentStatus    NVARCHAR(20)   NULL,
        HireDate            DATE           NULL,
        TerminationDate     DATE           NULL,
        PeriodDays          SMALLINT       NOT NULL CONSTRAINT DF_PayrollRunEmployees_PeriodDays DEFAULT (0),
        PaidDays            SMALLINT       NOT NULL CONSTRAINT DF_PayrollRunEmployees_PaidDays DEFAULT (0),
        HasBankAccount      BIT            NOT NULL CONSTRAINT DF_PayrollRunEmployees_HasBank DEFAULT (0),
        IsExcluded          BIT            NOT NULL CONSTRAINT DF_PayrollRunEmployees_IsExcluded DEFAULT (0),
        ExcludeReason       NVARCHAR(500)  NULL,
        ExcludedBy          BIGINT         NULL,
        ExcludedDate        DATETIME2(0)   NULL,
        SalaryTotal         DECIMAL(12,3)  NOT NULL CONSTRAINT DF_PayrollRunEmployees_Salary DEFAULT (0),
        EarningsTotal       DECIMAL(12,3)  NOT NULL CONSTRAINT DF_PayrollRunEmployees_Earnings DEFAULT (0),
        DeductionsTotal     DECIMAL(12,3)  NOT NULL CONSTRAINT DF_PayrollRunEmployees_Deductions DEFAULT (0),
        NetPay              DECIMAL(12,3)  NOT NULL CONSTRAINT DF_PayrollRunEmployees_NetPay DEFAULT (0),
        PreviousNet         DECIMAL(12,3)  NULL,
        LineCount           SMALLINT       NOT NULL CONSTRAINT DF_PayrollRunEmployees_LineCount DEFAULT (0),
        AddedLineCount      SMALLINT       NOT NULL CONSTRAINT DF_PayrollRunEmployees_AddedLines DEFAULT (0),
        HasSalary           BIT            NOT NULL CONSTRAINT DF_PayrollRunEmployees_HasSalary DEFAULT (0),
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollRunEmployees_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollRunEmployees_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollRunEmployees_Run      FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_PayrollRunEmployees_Employee FOREIGN KEY (EmployeeId)   REFERENCES [Employee].[Employees](EmployeeId)
    );
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollRunEmployees_Employee
        ON [Payroll].[PayrollRunEmployees](PayrollRunId, EmployeeId) WHERE Deleted = 0;
    CREATE INDEX IX_PayrollRunEmployees_Employee
        ON [Payroll].[PayrollRunEmployees](EmployeeId) INCLUDE (PayrollRunId, NetPay, IsExcluded) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   5. Payroll.PayrollRunLines - Amount is signed (deductions negative)
      Source: SALARY (salary item) / PROFILE (Employee.EmployeePayroll,
      no salary items yet) / PAY_ITEM / LOAN / STATUTORY / RUN (added in
      this payroll)
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[PayrollRunLines]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollRunLines](
        RunLineId           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollRunLines PRIMARY KEY,
        PayrollRunId        BIGINT         NOT NULL,
        RunEmployeeId       BIGINT         NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        PayComponentId      INT            NOT NULL,
        ItemClass           VARCHAR(10)    NOT NULL,
        ComponentName       NVARCHAR(150)  NOT NULL,
        ComponentArabicName NVARCHAR(150)  NULL,
        Comment             NVARCHAR(500)  NULL,
        Source              VARCHAR(10)    NOT NULL,
        EmployeePayItemId   BIGINT         NULL,
        InstalmentNo        SMALLINT       NULL,
        FullAmount          DECIMAL(12,3)  NOT NULL,
        Amount              DECIMAL(12,3)  NOT NULL,
        DisplayOrder        SMALLINT       NOT NULL CONSTRAINT DF_PayrollRunLines_DisplayOrder DEFAULT (100),
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollRunLines_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollRunLines_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollRunLines_Run         FOREIGN KEY (PayrollRunId)      REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_PayrollRunLines_RunEmployee FOREIGN KEY (RunEmployeeId)     REFERENCES [Payroll].[PayrollRunEmployees](RunEmployeeId),
        CONSTRAINT FK_PayrollRunLines_Component   FOREIGN KEY (PayComponentId)    REFERENCES [Payroll].[PayComponents](PayComponentId),
        CONSTRAINT FK_PayrollRunLines_PayItem     FOREIGN KEY (EmployeePayItemId) REFERENCES [Payroll].[EmployeePayItems](EmployeePayItemId),
        CONSTRAINT CK_PayrollRunLines_Class       CHECK (ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN', 'STATUTORY')),
        CONSTRAINT CK_PayrollRunLines_Source      CHECK (Source IN ('SALARY', 'PROFILE', 'PAY_ITEM', 'LOAN', 'STATUTORY', 'RUN'))
    );
    CREATE INDEX IX_PayrollRunLines_Employee
        ON [Payroll].[PayrollRunLines](PayrollRunId, RunEmployeeId) INCLUDE (ItemClass, Amount, Source) WHERE Deleted = 0;
    CREATE INDEX IX_PayrollRunLines_PayItem
        ON [Payroll].[PayrollRunLines](EmployeePayItemId) INCLUDE (PayrollRunId, InstalmentNo) WHERE Deleted = 0 AND EmployeePayItemId IS NOT NULL;
END;
GO

/* ------------------------------------------------------------------
   6. Payroll.PayrollRunIssues - validation results
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[PayrollRunIssues]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollRunIssues](
        RunIssueId          BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollRunIssues PRIMARY KEY,
        PayrollRunId        BIGINT         NOT NULL,
        EmployeeId          BIGINT         NULL,
        RuleCode            VARCHAR(10)    NOT NULL,
        Severity            VARCHAR(10)    NOT NULL,
        Message             NVARCHAR(400)  NOT NULL,
        IsAcknowledged      BIT            NOT NULL CONSTRAINT DF_PayrollRunIssues_Ack DEFAULT (0),
        AcknowledgedBy      BIGINT         NULL,
        AcknowledgedDate    DATETIME2(0)   NULL,
        AcknowledgeReason   NVARCHAR(500)  NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollRunIssues_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollRunIssues_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollRunIssues_Run FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT CK_PayrollRunIssues_Severity CHECK (Severity IN ('ERROR', 'WARNING'))
    );
    CREATE INDEX IX_PayrollRunIssues_Run ON [Payroll].[PayrollRunIssues](PayrollRunId, Severity) WHERE Deleted = 0;
END;
GO

/* ------------------------------------------------------------------
   7. Payroll.PayrollRunHistory - stage changes, approvals, comments
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[PayrollRunHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollRunHistory](
        RunHistoryId        BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollRunHistory PRIMARY KEY,
        PayrollRunId        BIGINT         NOT NULL,
        ActionCode          VARCHAR(20)    NOT NULL,
        FromStage           VARCHAR(20)    NULL,
        ToStage             VARCHAR(20)    NULL,
        ApprovalLevel       TINYINT        NULL,
        Comment             NVARCHAR(500)  NULL,
        ActionBy            BIGINT         NULL,
        ActionDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollRunHistory_ActionDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollRunHistory_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollRunHistory_Run FOREIGN KEY (PayrollRunId) REFERENCES [Payroll].[PayrollRuns](PayrollRunId)
    );
    CREATE INDEX IX_PayrollRunHistory_Run ON [Payroll].[PayrollRunHistory](PayrollRunId, ActionDate) WHERE Deleted = 0;
END;
GO

/* The delete guard of db/28 (INSTEAD OF DELETE -> Deleted = 1) for the new
   tables - the database trigger normally does this on CREATE TABLE already. */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
BEGIN
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'EmployeePayItems';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'PayrollRuns';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'PayrollRunEmployees';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'PayrollRunLines';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'PayrollRunIssues';
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'PayrollRunHistory';
END;
GO

/* ------------------------------------------------------------------
   8. Salary items from the employee profile (once)
      Employee.EmployeePayroll.BasicSalary -> Basic Salary item,
      .Allowances -> Other Allowances item, every month from the hire
      month. Only for employees that have no salary items yet.
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NOT NULL
BEGIN
    ;WITH src AS (
        SELECT e.EmployeeId, e.CompanyId, ep.BasicSalary, ep.Allowances,
               DATEFROMPARTS(YEAR(ISNULL(e.HireDate, '2000-01-01')), MONTH(ISNULL(e.HireDate, '2000-01-01')), 1) AS StartMonth
        FROM   [Employee].[EmployeePayroll] AS ep
        JOIN   [Employee].[Employees]       AS e ON e.EmployeeId = ep.EmployeeId
        WHERE  e.Deleted = 0
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] i
                           JOIN [Payroll].[PayComponents] c ON c.PayComponentId = i.PayComponentId
                           WHERE i.EmployeeId = e.EmployeeId AND i.Deleted = 0 AND c.ItemClass = 'SALARY')
    )
    INSERT INTO [Payroll].[EmployeePayItems] (CompanyId, EmployeeId, PayComponentId, Amount, AppliesMode, StartMonth, Comment, Status, SourceRef)
    SELECT s.CompanyId, s.EmployeeId, c.PayComponentId, v.Amount, 'MONTHLY', s.StartMonth,
           N'Moved from the employee profile', 'ACTIVE', N'Employee.EmployeePayroll'
    FROM   src AS s
    CROSS APPLY (VALUES ('BASIC', s.BasicSalary), ('OTHER_ALW', s.Allowances)) AS v(Code, Amount)
    JOIN   [Payroll].[PayComponents] AS c
           ON c.CompanyId = s.CompanyId AND c.ComponentCode = v.Code AND c.Deleted = 0
    WHERE  v.Amount > 0;

    PRINT CONCAT(N'Salary items created from Employee.EmployeePayroll: ', @@ROWCOUNT);
END;
GO

/* ------------------------------------------------------------------
   9. Permissions (granted to SYSADMIN, like db/32)
      PAYROLL_RUN_VIEW      see payrolls
      PAYROLL_RUN_PROCESS   create, calculate, register, validate, submit
      PAYROLL_RUN_APPROVE_HR       approval level 1 (HR Manager)
      PAYROLL_RUN_APPROVE_FINANCE  approval level 2 (Finance Manager)
      PAYROLL_RUN_CANCEL    cancel / reject a payroll
      PAYROLL_RUN_REOPEN    reopen a closed payroll
   ------------------------------------------------------------------ */
;WITH p(PermissionCode, Module, [Action]) AS (
    SELECT * FROM (VALUES
        ('PAYROLL_RUN_VIEW',            'PayrollRun', 'View'),
        ('PAYROLL_RUN_PROCESS',         'PayrollRun', 'Process'),
        ('PAYROLL_RUN_APPROVE_HR',      'PayrollRun', 'ApproveHR'),
        ('PAYROLL_RUN_APPROVE_FINANCE', 'PayrollRun', 'ApproveFinance'),
        ('PAYROLL_RUN_CANCEL',          'PayrollRun', 'Cancel'),
        ('PAYROLL_RUN_REOPEN',          'PayrollRun', 'Reopen')) AS x(a, b, c)
)
INSERT INTO [Security].[Permissions] (PermissionCode, Module, [Action])
SELECT p.PermissionCode, p.Module, p.[Action]
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[Permissions] AS e WHERE e.PermissionCode = p.PermissionCode AND e.Deleted = 0);
GO

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] AS r
JOIN   [Security].[Permissions] AS p ON p.PermissionCode LIKE 'PAYROLL[_]RUN[_]%'
WHERE  r.RoleCode = N'SYSADMIN'
  AND  p.Deleted = 0 AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

SET NOEXEC OFF;
GO
PRINT N'db/34 applied: payroll run tables, pay items, ItemClass, PAYROLL_RUN_* permissions.';
GO
