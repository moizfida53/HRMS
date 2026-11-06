/* =====================================================================
   115_Collections.sql  -  Payroll Components > Collection (Work Permit Collection)
   ---------------------------------------------------------------------
   Run after db/30, db/82, db/107 and db/111. Safe to re-run. It replaces
   Payroll.usp_PayrollRun_Calculate (db/107) and
   Payroll.usp_PayComponent_Manage (db/30): run this script again whenever
   one of those is run.

   1. A third kind of pay item type: COLLECTION, next to Earning and
      Deduction (Payroll Settings > Pay Item Types). Its class is
      COLLECTION, so it is not offered on the Earnings / Deductions pages.
      Every company gets the standard "Work Permit Collection" type
      (code WP_COLLECTION, calculated by the payroll).

   2. Generating a payroll (regular payrolls): when an employee's Gross
      Monthly - Basic Salary + Allowances of the employment contract
      (Employee.EmployeePayroll) - is below the Work Permit Salary of the
      Kuwait compliance (Kuwait.EmployeeCompliance), the difference is added
      to their pay as "Work Permit Collection", so the bank transfer reaches
      the work permit salary, and is recorded as a receivable the company
      collects back from the employee (Payroll.Collections). The payroll line
      has its own class COLLECTION (not an earning): the payroll lines, the
      comparison and the payslip show it as Collection, on the payslip in its
      own table. It is part of the net pay; the employee and payroll totals
      keep counting it with the additions to the salary (EarningsTotal /
      TotalEarnings) so Salary + Earnings - Deductions = Net in every report.

   3. Payroll Components > Collection: pick the company and the payroll
      month; the summary shows Total, Pending and Collected amounts; the
      list shows the pending ones first; "Mark as received" records the
      date, a receipt reference and a comment. Every change is kept in
      Payroll.CollectionHistory (created, recalculated, received, set back
      to pending, removed).

   Rights (first run): PAYROLL_COLL_VIEW to every role that sees Deductions
   (PAYROLL_DED_VIEW), PAYROLL_COLL_EDIT (mark as received / set back) to
   every role that edits them (PAYROLL_DED_EDIT); System Administrator gets
   both. Change them on Security > Roles.

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Payroll].[usp_PayrollRun_Calculate]', N'P') IS NULL OR OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
   OR COL_LENGTH(N'Kuwait.EmployeeCompliance', N'WorkPermitSalary') IS NULL OR OBJECT_ID(N'[Security].[RolePermissions]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/30, db/82, db/107 and db/111 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---- 1. the type COLLECTION ---------------------------------------------- */
/* pay item types: Earning, Deduction or Collection */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayComponents_Type' AND definition NOT LIKE N'%COLLECTION%')
    ALTER TABLE [Payroll].[PayComponents] DROP CONSTRAINT CK_PayComponents_Type;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayComponents_Type')
    ALTER TABLE [Payroll].[PayComponents] WITH CHECK
        ADD CONSTRAINT CK_PayComponents_Type CHECK (ComponentType IN ('EARNING', 'DEDUCTION', 'COLLECTION'));
GO

/* the class of a pay item type (db/34): a Collection is its own class, so the Earnings and
   Deductions pages never offer it. The computed column is re-created with that rule. */
IF NOT EXISTS (SELECT 1 FROM sys.computed_columns
               WHERE object_id = OBJECT_ID(N'[Payroll].[PayComponents]') AND name = N'ItemClass' AND definition LIKE N'%COLLECTION%')
BEGIN
    /* statistics on the column would block dropping it */
    DECLARE @sql NVARCHAR(MAX) = N'';
    SELECT @sql += N'DROP STATISTICS [Payroll].[PayComponents].' + QUOTENAME(s.name) + N';'
    FROM   sys.stats AS s
    JOIN   sys.stats_columns AS sc ON sc.object_id = s.object_id AND sc.stats_id = s.stats_id
    JOIN   sys.columns AS c ON c.object_id = sc.object_id AND c.column_id = sc.column_id
    WHERE  s.object_id = OBJECT_ID(N'[Payroll].[PayComponents]') AND c.name = N'ItemClass'
      AND  NOT EXISTS (SELECT 1 FROM sys.indexes i WHERE i.object_id = s.object_id AND i.index_id = s.stats_id);
    IF @sql <> N'' EXEC sys.sp_executesql @sql;

    IF COL_LENGTH(N'Payroll.PayComponents', N'ItemClass') IS NOT NULL
        ALTER TABLE [Payroll].[PayComponents] DROP COLUMN ItemClass;
    ALTER TABLE [Payroll].[PayComponents] ADD ItemClass AS (
        CAST(CASE
                WHEN SystemCode = 'PIFSS_EE'                                   THEN 'STATUTORY'
                WHEN SystemCode IN ('LOAN', 'SALARY_ADVANCE')                  THEN 'LOAN'
                WHEN ComponentType = 'COLLECTION'                              THEN 'COLLECTION'
                WHEN ComponentType = 'EARNING' AND IsRecurring = 1
                     AND ValueType = 'FIXED'                                   THEN 'SALARY'
                WHEN ComponentType = 'EARNING'                                 THEN 'EARNING'
                ELSE 'DEDUCTION'
             END AS VARCHAR(10)));
END;
GO

/* payroll lines: the class and the source COLLECTION - a line of its own kind, not an earning */
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayrollRunLines_Class' AND definition NOT LIKE N'%COLLECTION%')
    ALTER TABLE [Payroll].[PayrollRunLines] DROP CONSTRAINT CK_PayrollRunLines_Class;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayrollRunLines_Class')
    ALTER TABLE [Payroll].[PayrollRunLines] WITH CHECK
        ADD CONSTRAINT CK_PayrollRunLines_Class CHECK (ItemClass IN ('SALARY', 'EARNING', 'DEDUCTION', 'LOAN', 'STATUTORY', 'COLLECTION'));
IF EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayrollRunLines_Source' AND definition NOT LIKE N'%COLLECTION%')
    ALTER TABLE [Payroll].[PayrollRunLines] DROP CONSTRAINT CK_PayrollRunLines_Source;
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_PayrollRunLines_Source')
    ALTER TABLE [Payroll].[PayrollRunLines] WITH CHECK
        ADD CONSTRAINT CK_PayrollRunLines_Source CHECK (Source IN ('SALARY', 'PROFILE', 'PAY_ITEM', 'LOAN', 'STATUTORY', 'RUN', 'COLLECTION'));
GO

/* lines written by the first version of this script (class EARNING) become Collection lines;
   the totals do not change (a Collection is counted with the additions) */
UPDATE [Payroll].[PayrollRunLines] SET ItemClass = 'COLLECTION'
WHERE  Source = 'COLLECTION' AND ItemClass = 'EARNING';
PRINT CONCAT(N'Payroll lines set to class Collection: ', @@ROWCOUNT);
GO

/* ---- 2. the receivables and their audit ---------------------------------- */
IF OBJECT_ID(N'[Payroll].[Collections]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[Collections](
        CollectionId      BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Collections PRIMARY KEY,
        CompanyId         INT            NOT NULL,
        PayrollRunId      BIGINT         NOT NULL,
        RunEmployeeId     BIGINT         NOT NULL,
        EmployeeId        BIGINT         NOT NULL,
        RunMonth          DATE           NOT NULL,              -- the payroll month
        PayComponentId    INT            NOT NULL,              -- the Work Permit Collection item type
        GrossMonthly      DECIMAL(12,3)  NOT NULL,              -- Basic Salary + Allowances when calculated
        WorkPermitSalary  DECIMAL(12,3)  NOT NULL,
        Amount            DECIMAL(12,3)  NOT NULL,              -- paid on top, to collect back
        Status            VARCHAR(10)    NOT NULL CONSTRAINT DF_Collections_Status DEFAULT ('PENDING'),
        CollectedDate     DATE           NULL,                  -- the day it was received
        Reference         NVARCHAR(100)  NULL,                  -- receipt / voucher number
        Comment           NVARCHAR(500)  NULL,
        CollectedBy       BIGINT         NULL,
        CollectedOn       DATETIME2(0)   NULL,                  -- when it was marked
        CreatedBy         BIGINT         NULL,
        CreatedDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_Collections_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy        BIGINT         NULL,
        ModifiedDate      DATETIME2(0)   NULL,
        Deleted           BIT            NOT NULL CONSTRAINT DF_Payroll_Collections_Deleted DEFAULT (0),
        DeletedBy         BIGINT         NULL,
        DeletedDate       DATETIME2(7)   NULL,

        CONSTRAINT FK_Collections_Company     FOREIGN KEY (CompanyId)      REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_Collections_Run         FOREIGN KEY (PayrollRunId)   REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_Collections_RunEmployee FOREIGN KEY (RunEmployeeId)  REFERENCES [Payroll].[PayrollRunEmployees](RunEmployeeId),
        CONSTRAINT FK_Collections_Employee    FOREIGN KEY (EmployeeId)     REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_Collections_Component   FOREIGN KEY (PayComponentId) REFERENCES [Payroll].[PayComponents](PayComponentId),
        CONSTRAINT CK_Collections_Status      CHECK (Status IN ('PENDING', 'COLLECTED')),
        CONSTRAINT CK_Collections_Amount      CHECK (Amount > 0),
        CONSTRAINT CK_Collections_Collected   CHECK (Status = 'PENDING' OR CollectedDate IS NOT NULL)
    );
    CREATE UNIQUE INDEX UX_Collections_RunEmployee ON [Payroll].[Collections](PayrollRunId, EmployeeId) WHERE Deleted = 0;
    CREATE INDEX IX_Collections_CompanyMonth ON [Payroll].[Collections](CompanyId, RunMonth, Status) INCLUDE (Amount) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Payroll].[CollectionHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[CollectionHistory](
        CollectionHistoryId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CollectionHistory PRIMARY KEY,
        CollectionId        BIGINT         NOT NULL,
        ActionCode          VARCHAR(12)    NOT NULL,            -- CREATED / UPDATED / COLLECTED / REOPENED / REMOVED
        OldAmount           DECIMAL(12,3)  NULL,
        NewAmount           DECIMAL(12,3)  NULL,
        CollectedDate       DATE           NULL,
        Reference           NVARCHAR(100)  NULL,
        Comment             NVARCHAR(500)  NULL,
        ActionBy            BIGINT         NULL,
        ActionDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_CollectionHistory_ActionDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_CollectionHistory_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_CollectionHistory_Collection FOREIGN KEY (CollectionId) REFERENCES [Payroll].[Collections](CollectionId),
        CONSTRAINT CK_CollectionHistory_Action     CHECK (ActionCode IN ('CREATED', 'UPDATED', 'COLLECTED', 'REOPENED', 'REMOVED'))
    );
    CREATE INDEX IX_CollectionHistory_Collection ON [Payroll].[CollectionHistory](CollectionId, ActionDate DESC) WHERE Deleted = 0;
END;
GO

/* ---- 3. the standard "Work Permit Collection" item type of a company ----- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayComponent_SeedCollection]
    @CompanyId  INT,
    @UserId     BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    IF @CompanyId IS NULL
       OR EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0)
        RETURN;

    /* the code is taken already (a type made by hand): that one becomes the standard type */
    UPDATE TOP (1) [Payroll].[PayComponents]
       SET SystemCode = 'WP_COLLECTION', ComponentType = 'COLLECTION', CalculationMethod = 'SYSTEM', CalculationBase = NULL,
           DefaultPercentage = NULL, Formula = NULL, IsPifssApplicable = 0, IsIndemnityApplicable = 0, IsOvertimeApplicable = 0,
           IsLeaveSalaryApplicable = 0, IsRecurring = 0, IsProrated = 0, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
     WHERE CompanyId = @CompanyId AND ComponentCode = N'WP_COLLECTION' AND Deleted = 0 AND SystemCode IS NULL;
    IF @@ROWCOUNT > 0 RETURN;

    INSERT INTO [Payroll].[PayComponents]
        (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod,
         IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable,
         IsRecurring, IsProrated, ShowOnPayslip, DisplayOrder, SystemCode, IsSystem, Description, IsActive, CreatedBy)
    VALUES
        (@CompanyId, N'WP_COLLECTION', N'Work Permit Collection', N'تحصيل فرق راتب إذن العمل', NULL, 'COLLECTION', 'VARIABLE', 'SYSTEM',
         0, 0, 0, 0, 0,
         0, 0, 1, 900, 'WP_COLLECTION', 1,
         N'Added by the payroll when the gross monthly salary (Basic + Allowances) is below the work permit salary; collected back from the employee (Payroll Components > Collection).',
         1, @UserId);
END;
GO

DECLARE @Co INT, @Seeded INT = 0;
DECLARE co CURSOR LOCAL FAST_FORWARD FOR
    SELECT c.CompanyId FROM [Core].[Companies] AS c
    WHERE  c.Deleted = 0
      AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] p WHERE p.CompanyId = c.CompanyId AND p.SystemCode = 'WP_COLLECTION' AND p.Deleted = 0);
OPEN co;
FETCH NEXT FROM co INTO @Co;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Payroll].[usp_PayComponent_SeedCollection] @CompanyId = @Co;
    SET @Seeded += 1;
    FETCH NEXT FROM co INTO @Co;
END;
CLOSE co; DEALLOCATE co;
PRINT CONCAT(N'Work Permit Collection item type added to companies: ', @Seeded);
GO

/* ---- 4. the payroll engine (db/107) + 5d. Work Permit Collection --------- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayrollRun_Calculate]
    @RunId        BIGINT,
    @EmployeeIds  NVARCHAR(MAX) = NULL,   -- CSV; NULL = whole run (also re-syncs who is in it)
    @UserId       BIGINT        = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CompanyId INT, @Start DATE, @End DATE, @RunMonth DATE, @RunType VARCHAR(10), @Stage VARCHAR(20),
            @Freq VARCHAR(10), @Dept INT, @Loc INT, @EmpType NVARCHAR(20), @Nat VARCHAR(12), @CalendarId INT, @PeriodId INT;

    SELECT  @CompanyId = r.CompanyId, @Start = p.StartDate, @End = p.EndDate, @RunMonth = r.RunMonth,
            @RunType = r.RunType, @Stage = r.Stage, @Freq = pc.PayFrequency, @CalendarId = r.PayrollCalendarId, @PeriodId = r.PayrollPeriodId,
            @Dept = r.ScopeDepartmentId, @Loc = r.ScopeWorkLocationId, @EmpType = r.ScopeEmploymentType, @Nat = r.ScopeNationality
    FROM    [Payroll].[PayrollRuns]      AS r
    JOIN    [Payroll].[PayrollPeriods]   AS p  ON p.PayrollPeriodId    = r.PayrollPeriodId
    JOIN    [Payroll].[PayrollCalendars] AS pc ON pc.PayrollCalendarId = r.PayrollCalendarId
    WHERE   r.PayrollRunId = @RunId AND r.Deleted = 0;

    /* in Validation only one employee's exclude / include recalculates */
    IF @CompanyId IS NULL OR NOT (@Stage IN ('DRAFT', 'REGISTERED') OR (@Stage = 'VALIDATION' AND @EmployeeIds IS NOT NULL))
        RETURN;

    /* the profile salary is paid through the company's Basic Salary / Other Allowances
       pay components: a company set up after the payroll seed (db/32) gets the defaults now */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND Deleted = 0 AND ComponentCode = N'BASIC')
       AND OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @CompanyId, @UserId = @UserId;

    /* db/107: the salary + allowances of the employment contract become the employee's salary
       pay items (Basic Salary / Other Allowances) when they have none yet - new joiners included */
    IF OBJECT_ID(N'[Payroll].[usp_SalaryItems_FromContract]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_SalaryItems_FromContract] @CompanyId = @CompanyId, @UserId = @UserId;

    /* db/115: the company's Work Permit Collection item type (type COLLECTION) */
    IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayComponents] WHERE CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0)
        EXEC [Payroll].[usp_PayComponent_SeedCollection] @CompanyId = @CompanyId, @UserId = @UserId;

    DECLARE @PeriodDays INT = DATEDIFF(DAY, @Start, @End) + 1;
    DECLARE @BasisDays  INT = CASE WHEN @Freq = 'MONTHLY' THEN @PeriodDays ELSE DAY(EOMONTH(@RunMonth)) END;
    DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();

    BEGIN TRANSACTION;

    /* ---- 1. who is in the run (whole-run calculation only) ----------- */
    IF @EmployeeIds IS NULL
    BEGIN
        /* a payroll pays the employees of ITS calendar (db/60); an employee with no
           calendar yet is paid by the company's default calendar */
        /* db/80: a company with no active default calendar uses its first active
           monthly calendar as the default (Kuwait pays monthly) */
        DECLARE @DefaultCal BIT = CASE
            WHEN EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                         WHERE PayrollCalendarId = @CalendarId AND IsDefault = 1) THEN 1
            WHEN NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars]
                             WHERE CompanyId = @CompanyId AND IsDefault = 1 AND IsActive = 1 AND Deleted = 0)
                 AND @CalendarId = (SELECT TOP (1) PayrollCalendarId FROM [Payroll].[PayrollCalendars]
                                    WHERE CompanyId = @CompanyId AND PayFrequency = 'MONTHLY' AND IsActive = 1 AND Deleted = 0
                                    ORDER BY PayrollCalendarId) THEN 1
            ELSE 0 END;
        DECLARE @Eligible TABLE (EmployeeId BIGINT PRIMARY KEY);
        INSERT INTO @Eligible (EmployeeId)
        SELECT e.EmployeeId
        FROM   [Employee].[Employees] AS e
        LEFT JOIN [Core].[Countries]  AS n ON n.CountryId = e.NationalityCountryId
        WHERE  e.CompanyId = @CompanyId AND e.Deleted = 0 AND e.IsDeleted = 0
          /* db/80: the default calendar also pays an employee whose calendar was
             deactivated or removed, or is another company's - nobody is left out */
          AND  (e.PayrollCalendarId = @CalendarId
                OR (@DefaultCal = 1 AND (e.PayrollCalendarId IS NULL
                     OR NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] AS ec
                                    WHERE ec.PayrollCalendarId = e.PayrollCalendarId AND ec.CompanyId = e.CompanyId
                                      AND ec.Deleted = 0 AND ec.IsActive = 1))))
          AND  (e.HireDate IS NULL OR e.HireDate <= @End)
          AND  (e.TerminationDate IS NULL OR e.TerminationDate >= @Start)
          AND  NOT (e.EmploymentStatus IN (N'Terminated', N'Resigned') AND e.TerminationDate IS NULL)
          AND  (@Dept    IS NULL OR e.DepartmentId   = @Dept)
          AND  (@Loc     IS NULL OR e.WorkLocationId = @Loc)
          AND  (@EmpType IS NULL OR e.EmploymentType = @EmpType)
          AND  (@Nat     IS NULL OR (@Nat = 'KUWAITI' AND n.CountryCode IN ('KW', 'KWT'))
                                 OR (@Nat = 'NON_KUWAITI' AND ISNULL(n.CountryCode, '') NOT IN ('KW', 'KWT')));

        /* an employee's final settlement (draft to paid) pays the salary from its
           "Salary unpaid from" day - no payroll pays those days again (db/39-40) */
        IF OBJECT_ID(N'[Payroll].[FinalSettlements]', N'U') IS NOT NULL
            DELETE x
            FROM   @Eligible AS x
            WHERE  EXISTS (SELECT 1 FROM [Payroll].[FinalSettlements] AS fs
                           WHERE fs.EmployeeId = x.EmployeeId AND fs.Deleted = 0 AND fs.SettlementType <> 'ENCASHMENT'
                             AND fs.Status <> 'CANCELLED' AND fs.SalaryFrom <= @End);

        /* db/80: one regular payroll per employee per month - an employee already in
           another created regular payroll of the same month (any calendar; drafts
           do not count - Create recalculates, so the second one leaves them out)
           is not paid again here. The periods of one
           weekly / bi-weekly calendar inside a month are each paid. */
        IF @RunType = 'REGULAR'
            DELETE x
            FROM   @Eligible AS x
            WHERE  EXISTS (SELECT 1
                           FROM   [Payroll].[PayrollRunEmployees] AS oe
                           JOIN   [Payroll].[PayrollRuns]         AS o ON o.PayrollRunId = oe.PayrollRunId
                           WHERE  oe.EmployeeId = x.EmployeeId AND oe.Deleted = 0 AND o.Deleted = 0
                             AND  o.PayrollRunId <> @RunId AND o.RunType = 'REGULAR'
                             AND  o.Stage IN ('REGISTERED', 'VALIDATION', 'AWAITING_APPROVAL', 'CLOSED')
                             AND  o.RunMonth = @RunMonth
                             AND  NOT (o.PayrollCalendarId = @CalendarId AND o.PayrollPeriodId <> @PeriodId));

        /* leave: no longer in scope */
        UPDATE l SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Payroll].[PayrollRunLines] AS l
        JOIN   [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = l.RunEmployeeId
        WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND l.Deleted = 0
          AND  NOT EXISTS (SELECT 1 FROM @Eligible x WHERE x.EmployeeId = re.EmployeeId);

        UPDATE re SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
        FROM   [Payroll].[PayrollRunEmployees] AS re
        WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0
          AND  NOT EXISTS (SELECT 1 FROM @Eligible x WHERE x.EmployeeId = re.EmployeeId);

        /* join: newly in scope (an off-cycle payroll only takes new people while it is a draft) */
        INSERT INTO [Payroll].[PayrollRunEmployees] (PayrollRunId, EmployeeId)
        SELECT @RunId, x.EmployeeId
        FROM   @Eligible AS x
        WHERE  (@RunType = 'REGULAR' OR @Stage = 'DRAFT')
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] re
                           WHERE re.PayrollRunId = @RunId AND re.EmployeeId = x.EmployeeId AND re.Deleted = 0);

        /* db/107: on leave for the WHOLE period, the leave salary already paid in cash and not
           back yet -> excluded (nothing to pay; the leave-salary recovery of the month is not
           taken either). HR can include them and add pay items. Once HR includes or excludes
           someone by hand (AutoExcluded stays 1 / ExcludedBy is set), the payroll leaves them be;
           an auto-exclusion that no longer applies (early return, leave changed) is undone. */
        IF @RunType = 'REGULAR' AND COL_LENGTH(N'Leave.LeaveRequests', N'SettlementMode') IS NOT NULL
        BEGIN
            UPDATE re
               SET IsExcluded = 0, AutoExcluded = 0, ExcludeReason = NULL, ExcludedDate = NULL
            FROM   [Payroll].[PayrollRunEmployees] AS re
            WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 1 AND re.AutoExcluded = 1 AND re.ExcludedBy IS NULL
              AND  NOT EXISTS (SELECT 1 FROM [Leave].[LeaveRequests] AS r
                               WHERE r.EmployeeId = re.EmployeeId AND r.Deleted = 0 AND r.Status = 'APPROVED' AND r.SettlementMode = 'CASH'
                                 AND r.StartDate <= @Start AND ISNULL(r.ActualEndDate, r.EndDate) >= @End);

            UPDATE re
               SET IsExcluded = 1, AutoExcluded = 1, ExcludedBy = NULL, ExcludedDate = @Now,
                   ExcludeReason = LEFT(CONCAT(N'On leave all period (', lv.RequestNo, N', ', FORMAT(lv.StartDate, 'dd MMM yyyy', 'en-US'),
                                               N' - ', FORMAT(lv.LastDay, 'dd MMM yyyy', 'en-US'),
                                               N'); leave salary already paid in cash. Include to pay anything else.'), 500)
            FROM   [Payroll].[PayrollRunEmployees] AS re
            CROSS APPLY (SELECT TOP (1) r.RequestNo, r.StartDate, ISNULL(r.ActualEndDate, r.EndDate) AS LastDay
                         FROM   [Leave].[LeaveRequests] AS r
                         WHERE  r.EmployeeId = re.EmployeeId AND r.Deleted = 0 AND r.Status = 'APPROVED' AND r.SettlementMode = 'CASH'
                           AND  r.StartDate <= @Start AND ISNULL(r.ActualEndDate, r.EndDate) >= @End
                         ORDER BY r.StartDate DESC) AS lv
            WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0 AND re.AutoExcluded = 0;
        END;
    END;

    /* ---- 2. target employees ----------------------------------------- */
    DECLARE @T TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, IsExcluded BIT NOT NULL, CatchUp BIT NOT NULL DEFAULT (0));
    INSERT INTO @T (RunEmployeeId, EmployeeId, IsExcluded)
    SELECT re.RunEmployeeId, re.EmployeeId, re.IsExcluded
    FROM   [Payroll].[PayrollRunEmployees] AS re
    WHERE  re.PayrollRunId = @RunId AND re.Deleted = 0
      AND  (@EmployeeIds IS NULL OR re.EmployeeId IN (SELECT TRY_CAST(value AS BIGINT) FROM STRING_SPLIT(@EmployeeIds, ',')));

    /* catch-up (off-cycle): excluded from the closed regular payroll of this period
       and not paid by another off-cycle payroll of the period */
    IF @RunType = 'OFFCYCLE'
        UPDATE t SET CatchUp = 1
        FROM   @T AS t
        WHERE  t.IsExcluded = 0
          AND  EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] AS x
                       JOIN   [Payroll].[PayrollRuns] AS g ON g.PayrollRunId = x.PayrollRunId
                       WHERE  g.PayrollPeriodId = @PeriodId AND g.RunType = 'REGULAR' AND g.Stage = 'CLOSED' AND g.Deleted = 0
                         AND  x.EmployeeId = t.EmployeeId AND x.Deleted = 0 AND x.IsExcluded = 1)
          AND  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollRunEmployees] AS y
                           JOIN   [Payroll].[PayrollRuns] AS o ON o.PayrollRunId = y.PayrollRunId
                           WHERE  o.PayrollPeriodId = @PeriodId AND o.RunType = 'OFFCYCLE' AND o.PayrollRunId <> @RunId
                             AND  o.Deleted = 0 AND o.Stage <> 'CANCELLED'
                             AND  y.EmployeeId = t.EmployeeId AND y.Deleted = 0 AND y.IsExcluded = 0 AND y.SalaryTotal > 0);

    /* ---- 3. snapshot of the employee -------------------------------- */
    UPDATE re
       SET EmployeeNo       = ISNULL(e.EmployeeCode, e.EmployeeNo),
           EmployeeName     = LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))),
           ArabicName       = e.ArabicName,
           DepartmentId     = e.DepartmentId,
           DepartmentName   = d.DepartmentName,
           CostCenterId     = COALESCE(e.CostCenterId, d.CostCenterId),
           IsKuwaiti        = CASE WHEN n.CountryCode IN ('KW', 'KWT') THEN 1 ELSE 0 END,
           EmploymentStatus = e.EmploymentStatus,
           HireDate         = e.HireDate,
           TerminationDate  = e.TerminationDate,
           PeriodDays       = @BasisDays,
           PaidDays         = CASE WHEN x.PaidTo < x.PaidFrom THEN 0 ELSE DATEDIFF(DAY, x.PaidFrom, x.PaidTo) + 1 END,
           HasBankAccount   = CASE WHEN NULLIF(LTRIM(RTRIM(ep.Iban)), N'') IS NULL THEN 0 ELSE 1 END
    FROM   [Payroll].[PayrollRunEmployees] AS re
    JOIN   @T AS t ON t.RunEmployeeId = re.RunEmployeeId
    JOIN   [Employee].[Employees] AS e ON e.EmployeeId = re.EmployeeId
    LEFT JOIN [Core].[Departments] AS d ON d.DepartmentId = e.DepartmentId
    LEFT JOIN [Core].[Countries]   AS n ON n.CountryId = e.NationalityCountryId
    LEFT JOIN [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = e.EmployeeId AND ep.Deleted = 0
    CROSS APPLY (SELECT CASE WHEN e.HireDate > @Start THEN e.HireDate ELSE @Start END AS PaidFrom,
                        CASE WHEN e.TerminationDate < @End THEN e.TerminationDate ELSE @End END AS PaidTo) AS x;

    /* weekly / bi-weekly: paid days are the days of THIS period, the basis the month */
    /* (PaidDays above is already limited to the period, so nothing else to do) */

    /* ---- 4. clear the old lines of the target employees -------------- */
    UPDATE l SET Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
    FROM   [Payroll].[PayrollRunLines] AS l
    JOIN   @T AS t ON t.RunEmployeeId = l.RunEmployeeId
    WHERE  l.Deleted = 0;

    /* lines of other live payrolls - an item is paid by one payroll a month */
    DECLARE @Used TABLE (EmployeePayItemId BIGINT PRIMARY KEY, PaidCount INT NOT NULL, PaidAmount DECIMAL(14,3) NOT NULL, ThisMonth BIT NOT NULL);
    INSERT INTO @Used (EmployeePayItemId, PaidCount, PaidAmount, ThisMonth)
    SELECT l.EmployeePayItemId, COUNT(1), SUM(ABS(l.Amount)), MAX(CASE WHEN r.RunMonth = @RunMonth THEN 1 ELSE 0 END)
    FROM   [Payroll].[PayrollRunLines] AS l
    JOIN   [Payroll].[PayrollRuns]     AS r ON r.PayrollRunId = l.PayrollRunId
    JOIN   @T AS t ON t.EmployeeId = l.EmployeeId
    WHERE  l.Deleted = 0 AND r.Deleted = 0 AND l.EmployeePayItemId IS NOT NULL
      AND  r.PayrollRunId <> @RunId AND r.Stage NOT IN ('DRAFT', 'CANCELLED')
    GROUP BY l.EmployeePayItemId;

    /* ---- 5a. salary items (regular runs, off-cycle catch-up) --------- */
    IF @RunType = 'REGULAR' OR EXISTS (SELECT 1 FROM @T WHERE CatchUp = 1)
    BEGIN
        ;WITH s AS (
            SELECT  i.*, c.ComponentName, c.ArabicName AS CompArabic, c.IsProrated, c.DisplayOrder,
                    ROW_NUMBER() OVER (PARTITION BY i.EmployeeId, i.PayComponentId ORDER BY i.StartMonth DESC, i.EmployeePayItemId DESC) AS rn
            FROM    [Payroll].[EmployeePayItems] AS i
            JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
            JOIN    @T AS t ON t.EmployeeId = i.EmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
            WHERE   i.Deleted = 0 AND i.Status = 'ACTIVE' AND i.PayrollRunId IS NULL
              AND   c.ItemClass = 'SALARY' AND i.AppliesMode = 'MONTHLY'
              AND   i.StartMonth <= @RunMonth AND (i.EndMonth IS NULL OR i.EndMonth >= @RunMonth)
        )
        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, EmployeePayItemId, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, re.RunEmployeeId, s.EmployeeId, s.PayComponentId, 'SALARY', s.ComponentName, s.CompArabic,
                CASE WHEN s.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN CONCAT(N'Prorated ', re.PaidDays, N' of ', re.PeriodDays, N' days')
                     ELSE ISNULL(NULLIF(LTRIM(RTRIM(s.Comment)), N''), N'Monthly salary item') END,
                'SALARY', s.EmployeePayItemId, s.Amount,
                CASE WHEN s.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN ROUND(s.Amount * re.PaidDays / NULLIF(re.PeriodDays, 0), 3) ELSE s.Amount END,
                s.DisplayOrder
        FROM    s
        JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = @RunId AND re.EmployeeId = s.EmployeeId AND re.Deleted = 0
        WHERE   s.rn = 1;

        /* no salary items at all yet -> basic + allowances from the employee profile */
        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, re.RunEmployeeId, re.EmployeeId, c.PayComponentId, 'SALARY', c.ComponentName, c.ArabicName,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN CONCAT(N'Prorated ', re.PaidDays, N' of ', re.PeriodDays, N' days')
                     ELSE N'From the employee profile' END,
                'PROFILE', v.Amount,
                CASE WHEN c.IsProrated = 1 AND re.PaidDays < re.PeriodDays
                     THEN ROUND(v.Amount * re.PaidDays / NULLIF(re.PeriodDays, 0), 3) ELSE v.Amount END,
                c.DisplayOrder
        FROM    [Payroll].[PayrollRunEmployees] AS re
        JOIN    @T AS t ON t.RunEmployeeId = re.RunEmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
        JOIN    [Employee].[EmployeePayroll] AS ep ON ep.EmployeeId = re.EmployeeId AND ep.Deleted = 0
        CROSS APPLY (VALUES ('BASIC', ep.BasicSalary), ('OTHER_ALW', ep.Allowances)) AS v(Code, Amount)
        JOIN    [Payroll].[PayComponents] AS c ON c.CompanyId = @CompanyId AND c.ComponentCode = v.Code AND c.Deleted = 0
        WHERE   v.Amount > 0
          AND   NOT EXISTS (SELECT 1 FROM [Payroll].[EmployeePayItems] i
                            JOIN [Payroll].[PayComponents] ic ON ic.PayComponentId = i.PayComponentId
                            WHERE i.EmployeeId = re.EmployeeId AND i.Deleted = 0 AND ic.ItemClass = 'SALARY' AND i.PayrollRunId IS NULL);
    END;

    /* ---- 5b. earnings, deductions, loans ----------------------------- */
    ;WITH it AS (
        SELECT  i.EmployeePayItemId, i.EmployeeId, i.PayComponentId, i.Amount, i.AppliesMode, i.InstalmentCount, i.TotalAmount,
                i.Comment, i.PayrollRunId, c.ItemClass, c.ComponentName, c.ArabicName AS CompArabic, c.DisplayOrder,
                ISNULL(u.PaidCount, 0) AS PaidCount, ISNULL(u.PaidAmount, 0) AS PaidAmount, ISNULL(u.ThisMonth, 0) AS ThisMonth
        FROM    [Payroll].[EmployeePayItems] AS i
        JOIN    [Payroll].[PayComponents]    AS c ON c.PayComponentId = i.PayComponentId
        JOIN    @T AS t ON t.EmployeeId = i.EmployeeId AND t.IsExcluded = 0
        LEFT JOIN @Used AS u ON u.EmployeePayItemId = i.EmployeePayItemId
        WHERE   i.Deleted = 0 AND i.Status = 'ACTIVE'
          AND   c.ItemClass IN ('EARNING', 'DEDUCTION', 'LOAN')
          AND   (   i.PayrollRunId = @RunId
                 OR ((@RunType = 'REGULAR' OR t.CatchUp = 1) AND i.PayrollRunId IS NULL AND ISNULL(u.ThisMonth, 0) = 0 AND (
                        (i.AppliesMode = 'MONTHLY'    AND i.StartMonth <= @RunMonth AND (i.EndMonth IS NULL OR i.EndMonth >= @RunMonth))
                     OR (i.AppliesMode = 'ONCE'       AND i.StartMonth = @RunMonth)
                     OR (i.AppliesMode = 'INSTALMENT' AND i.StartMonth <= @RunMonth AND ISNULL(u.PaidCount, 0) < i.InstalmentCount))))
    )
    INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                             Comment, Source, EmployeePayItemId, InstalmentNo, FullAmount, Amount, DisplayOrder)
    SELECT  @RunId, re.RunEmployeeId, it.EmployeeId, it.PayComponentId, it.ItemClass, it.ComponentName, it.CompArabic,
            it.Comment,
            CASE WHEN it.PayrollRunId = @RunId THEN 'RUN' WHEN it.ItemClass = 'LOAN' THEN 'LOAN' ELSE 'PAY_ITEM' END,
            it.EmployeePayItemId,
            CASE WHEN it.AppliesMode = 'INSTALMENT' THEN it.PaidCount + 1 END,
            a.Amt,
            CASE WHEN it.ItemClass = 'EARNING' THEN a.Amt ELSE -a.Amt END,
            it.DisplayOrder
    FROM    it
    JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.PayrollRunId = @RunId AND re.EmployeeId = it.EmployeeId AND re.Deleted = 0
    CROSS APPLY (SELECT CASE WHEN it.AppliesMode = 'INSTALMENT' AND it.TotalAmount IS NOT NULL AND it.PaidCount + 1 >= it.InstalmentCount
                             THEN CASE WHEN it.TotalAmount - it.PaidAmount > 0 THEN it.TotalAmount - it.PaidAmount ELSE 0 END
                             ELSE it.Amount END AS Amt) AS a
    WHERE   a.Amt > 0;

    /* ---- 5c. PIFSS employee share (Kuwaiti, regular runs, catch-up) -- */
    IF @RunType = 'REGULAR' OR EXISTS (SELECT 1 FROM @T WHERE CatchUp = 1)
    BEGIN
        DECLARE @PifssId INT, @PifssName NVARCHAR(150), @PifssArabic NVARCHAR(150), @PifssOrder SMALLINT;
        SELECT TOP 1 @PifssId = PayComponentId, @PifssName = ComponentName, @PifssArabic = ArabicName, @PifssOrder = DisplayOrder
        FROM   [Payroll].[PayComponents]
        WHERE  CompanyId = @CompanyId AND SystemCode = 'PIFSS_EE' AND Deleted = 0 AND IsActive = 1;

        IF @PifssId IS NOT NULL
        BEGIN
            ;WITH b AS (
                SELECT  l.RunEmployeeId, l.EmployeeId, SUM(l.Amount) AS Base
                FROM    [Payroll].[PayrollRunLines] AS l
                JOIN    [Payroll].[PayComponents]   AS c ON c.PayComponentId = l.PayComponentId
                JOIN    [Payroll].[PayrollRunEmployees] AS re ON re.RunEmployeeId = l.RunEmployeeId
                JOIN    @T AS t ON t.RunEmployeeId = l.RunEmployeeId AND t.IsExcluded = 0 AND (@RunType = 'REGULAR' OR t.CatchUp = 1)
                WHERE   l.PayrollRunId = @RunId AND l.Deleted = 0 AND l.ItemClass = 'SALARY'
                  AND   c.IsPifssApplicable = 1 AND re.IsKuwaiti = 1
                GROUP BY l.RunEmployeeId, l.EmployeeId
            ), share AS (
                SELECT  b.RunEmployeeId, b.EmployeeId,
                        SUM(ROUND(CASE WHEN r.SalaryCeiling IS NOT NULL AND b.Base > r.SalaryCeiling THEN r.SalaryCeiling ELSE b.Base END
                                  * r.EmployeeRate / 100.0, 3)) AS Amt
                FROM    b
                JOIN    [Payroll].[PifssContributionRates] AS r
                        ON r.Deleted = 0 AND r.IsActive = 1 AND r.ApplicableTo = 'KUWAITI'
                       AND r.EffectiveFrom <= @End AND (r.EffectiveTo IS NULL OR r.EffectiveTo >= @End)
                WHERE   b.Base > 0
                GROUP BY b.RunEmployeeId, b.EmployeeId
            )
            INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                     Comment, Source, FullAmount, Amount, DisplayOrder)
            SELECT  @RunId, s.RunEmployeeId, s.EmployeeId, @PifssId, 'STATUTORY', @PifssName, @PifssArabic,
                    N'Employee share, Kuwaiti', 'STATUTORY', s.Amt, -s.Amt, @PifssOrder
            FROM    share AS s
            WHERE   s.Amt > 0;
        END;
    END;

    /* ---- 5d. db/115: Work Permit Collection ----------------------------
       Gross Monthly (contract Basic Salary + Allowances, Employee.EmployeePayroll)
       below the Work Permit Salary (Kuwait.EmployeeCompliance): the payroll pays
       the difference on top - the bank transfer reaches the work permit salary -
       and the company collects it back from the employee. The line has the
       class COLLECTION (not an earning), of the company's "Work Permit
       Collection" item type; the amount owed is a receivable on Payroll Components >
       Collection (Payroll.Collections), marked there once received.
       Regular payrolls only; an excluded employee gets none. */
    DECLARE @CollId INT, @CollName NVARCHAR(150), @CollArabic NVARCHAR(150), @CollOrder SMALLINT;
    SELECT TOP (1) @CollId = PayComponentId, @CollName = ComponentName, @CollArabic = ArabicName, @CollOrder = DisplayOrder
    FROM   [Payroll].[PayComponents]
    WHERE  CompanyId = @CompanyId AND SystemCode = 'WP_COLLECTION' AND Deleted = 0 AND IsActive = 1;

    DECLARE @Coll TABLE (RunEmployeeId BIGINT PRIMARY KEY, EmployeeId BIGINT NOT NULL, Gross DECIMAL(12,3) NOT NULL,
                         Wps DECIMAL(12,3) NOT NULL, Amt DECIMAL(12,3) NOT NULL);
    IF @RunType = 'REGULAR' AND @CollId IS NOT NULL
    BEGIN
        INSERT INTO @Coll (RunEmployeeId, EmployeeId, Gross, Wps, Amt)
        SELECT  t.RunEmployeeId, t.EmployeeId, g.Gross, k.WorkPermitSalary, k.WorkPermitSalary - g.Gross
        FROM    @T AS t
        JOIN    [Kuwait].[EmployeeCompliance] AS k  ON k.EmployeeId = t.EmployeeId AND k.Deleted = 0
        JOIN    [Employee].[EmployeePayroll]  AS ep ON ep.EmployeeId = t.EmployeeId AND ep.Deleted = 0
        CROSS APPLY (SELECT CAST(ISNULL(ep.BasicSalary, 0) + ISNULL(ep.Allowances, 0) AS DECIMAL(12,3)) AS Gross) AS g
        WHERE   t.IsExcluded = 0
          AND   ISNULL(ep.BasicSalary, 0) > 0            -- no contract salary: nothing to compare with
          AND   k.WorkPermitSalary > g.Gross;

        INSERT INTO [Payroll].[PayrollRunLines] (PayrollRunId, RunEmployeeId, EmployeeId, PayComponentId, ItemClass, ComponentName, ComponentArabicName,
                                                 Comment, Source, FullAmount, Amount, DisplayOrder)
        SELECT  @RunId, c.RunEmployeeId, c.EmployeeId, @CollId, 'COLLECTION', @CollName, @CollArabic,
                LEFT(CONCAT(N'Work permit salary ', FORMAT(c.Wps, 'N3', 'en-US'), N' - gross monthly ', FORMAT(c.Gross, 'N3', 'en-US'),
                            N'; collected back from the employee'), 500),
                'COLLECTION', c.Amt, c.Amt, @CollOrder
        FROM    @Coll AS c;
    END;

    /* the receivables of the employees just calculated: new ones are added (PENDING), a
       pending one follows the new amount or goes when it no longer applies; one already
       COLLECTED is never changed by a recalculation (its history says what was received) */
    DECLARE @CollNew TABLE (CollectionId BIGINT PRIMARY KEY, Amount DECIMAL(12,3) NOT NULL);

    INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
    SELECT  x.CollectionId, 'UPDATED', x.Amount, c.Amt, N'Payroll recalculated', @UserId
    FROM    [Payroll].[Collections] AS x
    JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
    WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING' AND x.Amount <> c.Amt;

    UPDATE  x
       SET  Amount = c.Amt, GrossMonthly = c.Gross, WorkPermitSalary = c.Wps, RunEmployeeId = c.RunEmployeeId,
            ModifiedBy = @UserId, ModifiedDate = @Now
    FROM    [Payroll].[Collections] AS x
    JOIN    @Coll AS c ON c.EmployeeId = x.EmployeeId
    WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
      AND   (x.Amount <> c.Amt OR x.GrossMonthly <> c.Gross OR x.WorkPermitSalary <> c.Wps OR x.RunEmployeeId <> c.RunEmployeeId);

    /* no longer owed: the employees calculated now without a collection, and (whole-run
       calculation) anyone no longer in the payroll */
    INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
    SELECT  x.CollectionId, 'REMOVED', x.Amount, NULL, N'No longer due after the payroll was recalculated', @UserId
    FROM    [Payroll].[Collections] AS x
    WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
      AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId)
      AND   (@EmployeeIds IS NULL OR EXISTS (SELECT 1 FROM @T t WHERE t.EmployeeId = x.EmployeeId));

    UPDATE  x
       SET  Deleted = 1, DeletedBy = @UserId, DeletedDate = @Now
    FROM    [Payroll].[Collections] AS x
    WHERE   x.PayrollRunId = @RunId AND x.Deleted = 0 AND x.Status = 'PENDING'
      AND   NOT EXISTS (SELECT 1 FROM @Coll c WHERE c.EmployeeId = x.EmployeeId)
      AND   (@EmployeeIds IS NULL OR EXISTS (SELECT 1 FROM @T t WHERE t.EmployeeId = x.EmployeeId));

    INSERT INTO [Payroll].[Collections] (CompanyId, PayrollRunId, RunEmployeeId, EmployeeId, RunMonth, PayComponentId,
                                         GrossMonthly, WorkPermitSalary, Amount, Status, CreatedBy)
    OUTPUT  inserted.CollectionId, inserted.Amount INTO @CollNew (CollectionId, Amount)
    SELECT  @CompanyId, @RunId, c.RunEmployeeId, c.EmployeeId, @RunMonth, @CollId, c.Gross, c.Wps, c.Amt, 'PENDING', @UserId
    FROM    @Coll AS c
    WHERE   NOT EXISTS (SELECT 1 FROM [Payroll].[Collections] x
                        WHERE x.PayrollRunId = @RunId AND x.EmployeeId = c.EmployeeId AND x.Deleted = 0);

    INSERT INTO [Payroll].[CollectionHistory] (CollectionId, ActionCode, OldAmount, NewAmount, Comment, ActionBy)
    SELECT  n.CollectionId, 'CREATED', NULL, n.Amount, N'Gross monthly below the work permit salary', @UserId
    FROM    @CollNew AS n;

    /* ---- 6. employee totals ------------------------------------------ */
    UPDATE re
       SET SalaryTotal     = ISNULL(x.Sal, 0),
           EarningsTotal   = ISNULL(x.Ern, 0),
           DeductionsTotal = ISNULL(x.Ded, 0),
           NetPay          = ISNULL(x.Sal, 0) + ISNULL(x.Ern, 0) + ISNULL(x.Ded, 0),
           LineCount       = ISNULL(x.Cnt, 0),
           AddedLineCount  = ISNULL(x.Added, 0),
           HasSalary       = CASE WHEN ISNULL(x.SalCnt, 0) > 0 THEN 1 ELSE 0 END,
           PreviousNet     = prev.NetPay
    FROM   [Payroll].[PayrollRunEmployees] AS re
    JOIN   @T AS t ON t.RunEmployeeId = re.RunEmployeeId
    OUTER APPLY (
        SELECT  SUM(CASE WHEN l.ItemClass = 'SALARY' THEN l.Amount END)                     AS Sal,
                /* db/115: a Collection is paid with the salary - counted with the additions so the
                   totals still add up to the net pay everywhere (reports, bank, journal) */
                SUM(CASE WHEN l.ItemClass IN ('EARNING', 'COLLECTION') THEN l.Amount END)   AS Ern,
                SUM(CASE WHEN l.ItemClass IN ('DEDUCTION', 'LOAN', 'STATUTORY') THEN l.Amount END) AS Ded,
                COUNT(1)                                                                    AS Cnt,
                SUM(CASE WHEN l.Source = 'RUN' THEN 1 ELSE 0 END)                           AS Added,
                SUM(CASE WHEN l.ItemClass = 'SALARY' THEN 1 ELSE 0 END)                     AS SalCnt
        FROM    [Payroll].[PayrollRunLines] AS l
        WHERE   l.RunEmployeeId = re.RunEmployeeId AND l.Deleted = 0
    ) AS x
    OUTER APPLY (
        SELECT TOP 1 pe.NetPay
        FROM   [Payroll].[PayrollRunEmployees] AS pe
        JOIN   [Payroll].[PayrollRuns]         AS pr ON pr.PayrollRunId = pe.PayrollRunId
        WHERE  pe.EmployeeId = re.EmployeeId AND pe.Deleted = 0 AND pe.IsExcluded = 0
          AND  pr.Deleted = 0 AND pr.Stage = 'CLOSED' AND pr.RunType = 'REGULAR'
          AND  pr.CompanyId = @CompanyId AND pr.RunMonth < @RunMonth AND pr.PayrollRunId <> @RunId
        ORDER BY pr.RunMonth DESC, pr.PayrollRunId DESC
    ) AS prev;

    /* ---- 7. run totals ----------------------------------------------- */
    UPDATE r
       SET EmployeeCount   = ISNULL(x.Cnt, 0),
           ExcludedCount   = ISNULL(x.Excl, 0),
           TotalSalary     = ISNULL(x.Sal, 0),
           TotalEarnings   = ISNULL(x.Ern, 0),
           TotalDeductions = ISNULL(x.Ded, 0),
           TotalNet        = ISNULL(x.Net, 0),
           CalculatedBy    = @UserId,
           CalculatedDate  = @Now
    FROM   [Payroll].[PayrollRuns] AS r
    OUTER APPLY (
        SELECT  SUM(CASE WHEN re.IsExcluded = 0 AND (@RunType = 'REGULAR' OR re.LineCount > 0) THEN 1 ELSE 0 END) AS Cnt,
                SUM(CASE WHEN re.IsExcluded = 1 THEN 1 ELSE 0 END) AS Excl,
                SUM(re.SalaryTotal) AS Sal, SUM(re.EarningsTotal) AS Ern, SUM(re.DeductionsTotal) AS Ded, SUM(re.NetPay) AS Net
        FROM    [Payroll].[PayrollRunEmployees] AS re
        WHERE   re.PayrollRunId = r.PayrollRunId AND re.Deleted = 0
    ) AS x
    WHERE  r.PayrollRunId = @RunId;

    COMMIT TRANSACTION;
END;
GO


/* ---- 5. Payroll.usp_PayComponent_Manage (db/30) + type COLLECTION ---------- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_PayComponent_Manage]
    @Action                   VARCHAR(10),
    @Id                       BIGINT          = NULL,

    @Search                   NVARCHAR(200)   = NULL,
    @IsActiveFilter           BIT             = NULL,
    @CompanyId                INT             = NULL,   -- LIST filter AND editable column
    @CompanyIds               NVARCHAR(2000)  = NULL,
    @ParentId                 INT             = NULL,
    @PageNumber               INT             = 1,
    @PageSize                 INT             = 25,
    @SortColumn               VARCHAR(50)     = NULL,
    @SortDirection            VARCHAR(4)      = 'ASC',
    @ComponentTypeFilter      VARCHAR(10)     = NULL,   -- EARNING / DEDUCTION / COLLECTION / NULL = all

    /* ---- editable columns -------------------------------------- */
    @ComponentCode            NVARCHAR(30)    = NULL,
    @ComponentName            NVARCHAR(150)   = NULL,
    @ArabicName               NVARCHAR(150)   = NULL,
    @PayslipLabel             NVARCHAR(100)   = NULL,
    @ComponentType            VARCHAR(10)     = NULL,
    @ValueType                VARCHAR(10)     = NULL,
    @CalculationMethod        VARCHAR(12)     = NULL,
    @CalculationBase          VARCHAR(15)     = NULL,
    @DefaultAmount            DECIMAL(12,3)   = NULL,
    @DefaultPercentage        DECIMAL(7,4)    = NULL,
    @Formula                  NVARCHAR(1000)  = NULL,
    @MinAmount                DECIMAL(12,3)   = NULL,
    @MaxAmount                DECIMAL(12,3)   = NULL,
    @IsTaxable                BIT             = NULL,
    @IsPifssApplicable        BIT             = NULL,
    @IsIndemnityApplicable    BIT             = NULL,
    @IsOvertimeApplicable     BIT             = NULL,
    @IsLeaveSalaryApplicable  BIT             = NULL,
    @IsRecurring              BIT             = NULL,
    @IsProrated               BIT             = NULL,
    @ShowOnPayslip            BIT             = NULL,
    @GLAccountCode            NVARCHAR(50)    = NULL,
    @GLAccountName            NVARCHAR(150)   = NULL,
    @CostCenterId             INT             = NULL,
    @DisplayOrder             SMALLINT        = NULL,
    @Description              NVARCHAR(500)   = NULL,
    @IsActive                 BIT             = NULL,

    @UserId                   BIGINT          = NULL,

    @TotalCount               INT             = NULL OUTPUT,
    @NewId                    BIGINT          = NULL OUTPUT,
    @ResultCode               VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage            NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = ISNULL(@Id, 0), @TotalCount = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE', 'SEED')
    BEGIN
        SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;
    SET @ComponentTypeFilter = NULLIF(UPPER(LTRIM(RTRIM(@ComponentTypeFilter))), '');

    DECLARE @Pattern NVARCHAR(410) =
        CASE WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
             ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%' END;

    /* ======================= LIST ================================ */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM   [Payroll].[PayComponents] AS pc
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ComponentTypeFilter IS NULL OR pc.ComponentType = @ComponentTypeFilter)
          AND (@Pattern IS NULL OR pc.ComponentCode LIKE @Pattern ESCAPE '\' OR pc.ComponentName LIKE @Pattern ESCAPE '\'
               OR pc.ArabicName LIKE @Pattern ESCAPE '\' OR pc.GLAccountCode LIKE @Pattern ESCAPE '\');

        SELECT  pc.PayComponentId, pc.CompanyId, pc.ComponentCode, pc.ComponentName, pc.ArabicName, pc.PayslipLabel,
                pc.ComponentType, pc.ValueType, pc.CalculationMethod, pc.CalculationBase,
                pc.DefaultAmount, pc.DefaultPercentage, pc.Formula, pc.MinAmount, pc.MaxAmount,
                pc.IsTaxable, pc.IsPifssApplicable, pc.IsIndemnityApplicable, pc.IsOvertimeApplicable,
                pc.IsLeaveSalaryApplicable, pc.IsRecurring, pc.IsProrated, pc.ShowOnPayslip,
                pc.GLAccountCode, pc.GLAccountName, pc.CostCenterId, pc.DisplayOrder, pc.SystemCode, pc.IsSystem,
                pc.Description, pc.IsActive,
                c.CompanyName, cc.CostCenterName,
                (SELECT COUNT(1) FROM [Payroll].[SalaryStructureComponents] l
                  WHERE l.Deleted = 0 AND l.PayComponentId = pc.PayComponentId) AS StructureCount
        FROM        [Payroll].[PayComponents] AS pc
        INNER JOIN  [Core].[Companies]        AS c  ON c.CompanyId     = pc.CompanyId
        LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = pc.CostCenterId
        WHERE  pc.Deleted = 0
          AND (@IsActiveFilter IS NULL OR pc.IsActive = @IsActiveFilter)
          AND (@CompanyId IS NULL OR pc.CompanyId = @CompanyId)
          AND (@CompanyIds IS NULL OR CHARINDEX(',' + CAST(pc.CompanyId AS VARCHAR(12)) + ',', ',' + REPLACE(@CompanyIds, ' ', '') + ',') > 0)
          AND (@ComponentTypeFilter IS NULL OR pc.ComponentType = @ComponentTypeFilter)
          AND (@Pattern IS NULL OR pc.ComponentCode LIKE @Pattern ESCAPE '\' OR pc.ComponentName LIKE @Pattern ESCAPE '\'
               OR pc.ArabicName LIKE @Pattern ESCAPE '\' OR pc.GLAccountCode LIKE @Pattern ESCAPE '\')
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentCode'     THEN pc.ComponentCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentCode'     THEN pc.ComponentCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentName'     THEN pc.ComponentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentName'     THEN pc.ComponentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'ComponentType'     THEN pc.ComponentType END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'ComponentType'     THEN pc.ComponentType END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'CalculationMethod' THEN pc.CalculationMethod END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'CalculationMethod' THEN pc.CalculationMethod END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'IsActive'          THEN pc.IsActive END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'IsActive'          THEN pc.IsActive END DESC,
                CASE WHEN @SortDirection = 'DESC' AND ISNULL(@SortColumn, 'DisplayOrder') = 'DisplayOrder' THEN pc.DisplayOrder END DESC,
                pc.DisplayOrder ASC, pc.ComponentName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS FETCH NEXT @PageSize ROWS ONLY;
        RETURN;
    END;

    /* ======================= GET ================================= */
    IF @Action = 'GET'
    BEGIN
        SELECT  pc.PayComponentId, pc.CompanyId, pc.ComponentCode, pc.ComponentName, pc.ArabicName, pc.PayslipLabel,
                pc.ComponentType, pc.ValueType, pc.CalculationMethod, pc.CalculationBase,
                pc.DefaultAmount, pc.DefaultPercentage, pc.Formula, pc.MinAmount, pc.MaxAmount,
                pc.IsTaxable, pc.IsPifssApplicable, pc.IsIndemnityApplicable, pc.IsOvertimeApplicable,
                pc.IsLeaveSalaryApplicable, pc.IsRecurring, pc.IsProrated, pc.ShowOnPayslip,
                pc.GLAccountCode, pc.GLAccountName, pc.CostCenterId, pc.DisplayOrder, pc.SystemCode, pc.IsSystem,
                pc.Description, pc.IsActive,
                c.CompanyName, cc.CostCenterName,
                (SELECT COUNT(1) FROM [Payroll].[SalaryStructureComponents] l
                  WHERE l.Deleted = 0 AND l.PayComponentId = pc.PayComponentId) AS StructureCount
        FROM        [Payroll].[PayComponents] AS pc
        INNER JOIN  [Core].[Companies]        AS c  ON c.CompanyId     = pc.CompanyId
        LEFT JOIN   [Core].[CostCenters]      AS cc ON cc.CostCenterId = pc.CostCenterId
        WHERE pc.PayComponentId = @Id AND pc.Deleted = 0;
        RETURN;
    END;

    /* ======================= SEED ================================ */
    IF @Action = 'SEED'
    BEGIN
        IF @CompanyId IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Select a company first.';
            RETURN;
        END;
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @CompanyId, @UserId = @UserId, @Inserted = @TotalCount OUTPUT;
        SET @ResultMessage = CASE WHEN @TotalCount = 0 THEN N'This company already has all the standard components.'
                                  ELSE CONCAT(@TotalCount, N' standard component(s) added.') END;
        RETURN;
    END;

    /* ======================= shared validation =================== */
    DECLARE @CurSystemCode VARCHAR(30), @CurType VARCHAR(10), @CurCode NVARCHAR(30), @CurCompanyId INT, @CurMethod VARCHAR(12), @Exists BIT = 0;

    IF @Action IN ('UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @Exists = 1, @CurSystemCode = SystemCode, @CurType = ComponentType, @CurCode = ComponentCode,
               @CurCompanyId = CompanyId, @CurMethod = CalculationMethod
        FROM [Payroll].[PayComponents] WHERE PayComponentId = @Id AND Deleted = 0;

        IF @Exists = 0
        BEGIN
            SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That record no longer exists. Refresh and try again.';
            RETURN;
        END;
    END;

    IF @Action IN ('INSERT', 'UPDATE')
    BEGIN
        /* System components keep their identity: code, type, company and (for SYSTEM-calculated ones) method. */
        IF @CurSystemCode IS NOT NULL
            SELECT @ComponentCode = @CurCode, @ComponentType = @CurType, @CompanyId = @CurCompanyId,
                   @CalculationMethod = CASE WHEN @CurMethod = 'SYSTEM' THEN 'SYSTEM' ELSE @CalculationMethod END;

        SELECT @ComponentType     = UPPER(LTRIM(RTRIM(@ComponentType))),
               @ValueType         = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@ValueType)), ''), 'FIXED')),
               @CalculationMethod = UPPER(ISNULL(NULLIF(LTRIM(RTRIM(@CalculationMethod)), ''), 'AMOUNT')),
               @CalculationBase   = NULLIF(UPPER(LTRIM(RTRIM(@CalculationBase))), '');

        IF @CompanyId IS NULL OR NULLIF(LTRIM(RTRIM(@ComponentCode)), N'') IS NULL OR NULLIF(LTRIM(RTRIM(@ComponentName)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Company, code and name are required.';
            RETURN;
        END;
        IF @ComponentType NOT IN ('EARNING', 'DEDUCTION', 'COLLECTION')     -- db/115: + COLLECTION
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose whether this is an Earning, a Deduction or a Collection.';
            RETURN;
        END;
        IF @ValueType NOT IN ('FIXED', 'VARIABLE')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose Fixed or Variable.';
            RETURN;
        END;
        IF @CalculationMethod NOT IN ('AMOUNT', 'PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA', 'SYSTEM')
           OR (@CalculationMethod = 'SYSTEM' AND @CurSystemCode IS NULL)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose a calculation method: Amount, Percentage, Days, Hours or Formula.';
            RETURN;
        END;
        IF @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS')
           AND ISNULL(@CalculationBase, '') NOT IN ('BASIC', 'FIXED_GROSS', 'OVERTIME_BASE', 'INDEMNITY_BASE')
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Percentage, Days and Hours methods need a calculation base (Basic, Fixed gross, Overtime base or Indemnity base).';
            RETURN;
        END;
        IF @CalculationMethod = 'PERCENTAGE' AND @DefaultPercentage IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the default percentage.';
            RETURN;
        END;
        IF @CalculationMethod = 'FORMULA' AND NULLIF(LTRIM(RTRIM(@Formula)), N'') IS NULL
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the formula.';
            RETURN;
        END;
        IF @ComponentType <> 'EARNING'
           AND (ISNULL(@IsPifssApplicable, 0) = 1 OR ISNULL(@IsIndemnityApplicable, 0) = 1
                OR ISNULL(@IsOvertimeApplicable, 0) = 1 OR ISNULL(@IsLeaveSalaryApplicable, 0) = 1)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Social security, end-of-service, overtime and leave-salary flags apply to earnings only.';
            RETURN;
        END;
        IF @MinAmount IS NOT NULL AND @MaxAmount IS NOT NULL AND @MaxAmount < @MinAmount
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Maximum amount cannot be less than the minimum amount.';
            RETURN;
        END;
        IF @CostCenterId IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM [Core].[CostCenters] WHERE CostCenterId = @CostCenterId AND CompanyId = @CompanyId AND Deleted = 0)
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The selected cost center does not belong to this company.';
            RETURN;
        END;
        IF @CurSystemCode = 'BASIC' AND ISNULL(@IsActive, 1) = 0
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT', @ResultMessage = N'Basic Salary is required by the payroll engine and cannot be deactivated.';
            RETURN;
        END;
        IF EXISTS (SELECT 1 FROM [Payroll].[PayComponents]
                   WHERE Deleted = 0 AND CompanyId = @CompanyId AND ComponentCode = @ComponentCode
                     AND (@Action = 'INSERT' OR PayComponentId <> @Id))
        BEGIN
            SELECT @ResultCode = 'DUPLICATE_CODE', @ResultMessage = N'That code is already in use. Enter a different code.';
            RETURN;
        END;
    END;

    /* ======================= INSERT ============================== */
    IF @Action = 'INSERT'
    BEGIN
        INSERT INTO [Payroll].[PayComponents]
            (CompanyId, ComponentCode, ComponentName, ArabicName, PayslipLabel, ComponentType, ValueType, CalculationMethod, CalculationBase,
             DefaultAmount, DefaultPercentage, Formula, MinAmount, MaxAmount,
             IsTaxable, IsPifssApplicable, IsIndemnityApplicable, IsOvertimeApplicable, IsLeaveSalaryApplicable,
             IsRecurring, IsProrated, ShowOnPayslip, GLAccountCode, GLAccountName, CostCenterId, DisplayOrder,
             SystemCode, IsSystem, Description, IsActive, CreatedBy)
        VALUES
            (@CompanyId, @ComponentCode, @ComponentName, @ArabicName, @PayslipLabel, @ComponentType, @ValueType, @CalculationMethod,
             CASE WHEN @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA') THEN @CalculationBase END,
             @DefaultAmount, CASE WHEN @CalculationMethod = 'PERCENTAGE' THEN @DefaultPercentage END,
             CASE WHEN @CalculationMethod = 'FORMULA' THEN @Formula END, @MinAmount, @MaxAmount,
             ISNULL(@IsTaxable, 0), ISNULL(@IsPifssApplicable, 0), ISNULL(@IsIndemnityApplicable, 0), ISNULL(@IsOvertimeApplicable, 0),
             ISNULL(@IsLeaveSalaryApplicable, 0), ISNULL(@IsRecurring, 1), ISNULL(@IsProrated, 1), ISNULL(@ShowOnPayslip, 1),
             @GLAccountCode, @GLAccountName, @CostCenterId, ISNULL(@DisplayOrder, 100),
             NULL, 0, @Description, ISNULL(@IsActive, 1), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = CASE WHEN @ComponentType = 'EARNING' THEN N'Earning component created successfully.'
                                  ELSE N'Deduction component created successfully.' END;
        RETURN;
    END;

    /* ======================= UPDATE ============================== */
    IF @Action = 'UPDATE'
    BEGIN
        /* Changing the type of a component already used in a structure would flip the sign of those lines. */
        IF @ComponentType <> @CurType
           AND EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] WHERE Deleted = 0 AND PayComponentId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This component is used in a salary structure, so it cannot be switched between Earning and Deduction.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET CompanyId               = @CompanyId,
               ComponentCode           = @ComponentCode,
               ComponentName           = @ComponentName,
               ArabicName              = @ArabicName,
               PayslipLabel            = @PayslipLabel,
               ComponentType           = @ComponentType,
               ValueType               = @ValueType,
               CalculationMethod       = @CalculationMethod,
               CalculationBase         = CASE WHEN @CalculationMethod IN ('PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA') THEN @CalculationBase END,
               DefaultAmount           = @DefaultAmount,
               DefaultPercentage       = CASE WHEN @CalculationMethod = 'PERCENTAGE' THEN @DefaultPercentage END,
               Formula                 = CASE WHEN @CalculationMethod = 'FORMULA' THEN @Formula END,
               MinAmount               = @MinAmount,
               MaxAmount               = @MaxAmount,
               IsTaxable               = ISNULL(@IsTaxable, 0),
               IsPifssApplicable       = ISNULL(@IsPifssApplicable, 0),
               IsIndemnityApplicable   = ISNULL(@IsIndemnityApplicable, 0),
               IsOvertimeApplicable    = ISNULL(@IsOvertimeApplicable, 0),
               IsLeaveSalaryApplicable = ISNULL(@IsLeaveSalaryApplicable, 0),
               IsRecurring             = ISNULL(@IsRecurring, 1),
               IsProrated              = ISNULL(@IsProrated, 1),
               ShowOnPayslip           = ISNULL(@ShowOnPayslip, 1),
               GLAccountCode           = @GLAccountCode,
               GLAccountName           = @GLAccountName,
               CostCenterId            = @CostCenterId,
               DisplayOrder            = ISNULL(@DisplayOrder, DisplayOrder),
               Description             = @Description,
               IsActive                = ISNULL(@IsActive, IsActive),
               ModifiedBy              = @UserId,
               ModifiedDate            = SYSUTCDATETIME()
         WHERE PayComponentId = @Id;

        SET @NewId = @Id;
        SET @ResultMessage = N'Component updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ============================== */
    IF @Action = 'DELETE'
    BEGIN
        IF @CurSystemCode IS NOT NULL
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT',
                   @ResultMessage = CASE WHEN @CurSystemCode = 'BASIC' THEN N'Basic Salary is required by the payroll engine and cannot be deleted.'
                                         ELSE N'This is a standard component the payroll engine relies on. Deactivate it instead of deleting it.' END;
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Payroll].[SalaryStructureComponents] WHERE Deleted = 0 AND PayComponentId = @Id)
        BEGIN
            SELECT @ResultCode = 'IN_USE', @ResultMessage = N'This component is used in a salary structure and cannot be deleted. Remove it from the structure or deactivate it instead.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET Deleted = 1, DeletedBy = @UserId, DeletedDate = SYSUTCDATETIME()
         WHERE PayComponentId = @Id AND Deleted = 0;

        SET @ResultMessage = N'Component deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ============================== */
    IF @Action = 'TOGGLE'
    BEGIN
        IF @CurSystemCode = 'BASIC'
        BEGIN
            SELECT @ResultCode = 'SYSTEM_COMPONENT', @ResultMessage = N'Basic Salary is required by the payroll engine and cannot be deactivated.';
            RETURN;
        END;

        UPDATE [Payroll].[PayComponents]
           SET IsActive = CASE WHEN IsActive = 1 THEN 0 ELSE 1 END, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE PayComponentId = @Id;

        SELECT @ResultMessage = CASE WHEN IsActive = 1 THEN N'Component activated.' ELSE N'Component deactivated.' END
        FROM [Payroll].[PayComponents] WHERE PayComponentId = @Id;
        RETURN;
    END;
END;
GO


/* ---- 6. Payroll.usp_Collection_Manage - the Collection page -------------- */
CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_Manage]
    @Action         VARCHAR(20),
    @CompanyId      INT             = NULL,     -- the company picked on the page (required)
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

    IF @Action NOT IN ('MONTHS', 'LIST', 'SUMMARY', 'COLLECT', 'REOPEN', 'HISTORY')
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
    WHERE   c.Deleted = 0 AND r.Deleted = 0 AND r.Stage <> 'CANCELLED'
      AND   (@AnyCompany = 1 OR c.CompanyId IN (SELECT CompanyId FROM @Allowed))
      AND   (@Action IN ('COLLECT', 'REOPEN', 'HISTORY') OR (c.CompanyId = @CompanyId AND (@Month IS NULL OR c.RunMonth = @Month)));

    /* ======================= MONTHS ============================== */
    /* the payroll months of the company (regular payrolls), newest first, with how much is due */
    IF @Action = 'MONTHS'
    BEGIN
        IF @AnyCompany = 0 AND NOT EXISTS (SELECT 1 FROM @Allowed WHERE CompanyId = @CompanyId) RETURN;
        SELECT  m.RunMonth,
                ISNULL(SUM(CASE WHEN c.Status = 'PENDING' THEN c.Amount END), 0) AS PendingAmount,
                COUNT(c.CollectionId) AS CollectionCount
        FROM   (SELECT DISTINCT r.RunMonth FROM [Payroll].[PayrollRuns] AS r
                WHERE r.CompanyId = @CompanyId AND r.Deleted = 0 AND r.Stage <> 'CANCELLED' AND r.RunType = 'REGULAR') AS m
        LEFT JOIN [Payroll].[Collections] AS c ON c.RunMonth = m.RunMonth AND c.CompanyId = @CompanyId
                                               AND c.CollectionId IN (SELECT CollectionId FROM @Live)
        GROUP BY m.RunMonth
        ORDER BY m.RunMonth DESC;
        RETURN;
    END;

    /* ======================= SUMMARY ============================= */
    IF @Action = 'SUMMARY'
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
                c.GrossMonthly, c.WorkPermitSalary, c.Amount, c.Status,
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
        IF EXISTS (SELECT 1 FROM @Pick p JOIN [Payroll].[Collections] c ON c.CollectionId = p.CollectionId
                   JOIN [Payroll].[PayrollRuns] r ON r.PayrollRunId = c.PayrollRunId WHERE r.Stage = 'DRAFT')
        BEGIN
            SELECT @ResultCode = 'DRAFT', @ResultMessage = N'The payroll is still a draft - create it before marking its collections as received.';
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

/* ---- 7. the rights of the Collection page (first run: from Deductions) ---- */
IF OBJECT_ID('tempdb..#CollCodes') IS NOT NULL DROP TABLE #CollCodes;
CREATE TABLE #CollCodes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                         Action VARCHAR(30) COLLATE DATABASE_DEFAULT, FromCode VARCHAR(60) COLLATE DATABASE_DEFAULT, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #CollCodes (PermissionCode, Module, Action, FromCode)
VALUES ('PAYROLL_COLL_VIEW', 'PayrollComponentCOLL', 'VIEW', 'PAYROLL_DED_VIEW'),
       ('PAYROLL_COLL_EDIT', 'PayrollComponentCOLL', 'EDIT', 'PAYROLL_DED_EDIT');

UPDATE c SET IsNew = 1 FROM #CollCodes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #CollCodes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT r.RoleId, p.PermissionId
FROM   #CollCodes c
JOIN   [Security].[Permissions] p ON p.PermissionCode = c.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] r ON r.Deleted = 0
WHERE  c.IsNew = 1
  AND (r.RoleCode = N'SYSADMIN'
       OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                  WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = c.FromCode))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @CollGranted INT = @@ROWCOUNT;
DECLARE @CollCreated INT = (SELECT COUNT(1) FROM #CollCodes WHERE IsNew = 1);   -- PRINT takes no subquery
PRINT CONCAT(N'Collection rights created: ', @CollCreated, N', granted: ', @CollGranted);
DROP TABLE #CollCodes;
GO

/* ---- 8. labels (English + Arabic) ----------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        /* Pay Item Types */
        ('st.collection', 'st', N'Collection', N'تحصيل', NULL),
        ('st.collection_hint', 'st', N'Paid with the salary, collected back', N'يُصرف مع الراتب ويُسترد من الموظف', NULL),
        ('st.collections', 'st', N'Collections', N'التحصيلات', NULL),
        ('st.class_collection', 'st', N'Collection', N'تحصيل', NULL),
        /* Security > Roles */
        ('sec.pg_pc_collection', 'sec', N'Collection', N'التحصيل', NULL),
        ('sec.pg_pc_collection_hint', 'sec', N'Read = see the collections; Write = mark as received and set back to pending', N'القراءة = عرض التحصيلات؛ الكتابة = تسجيل الاستلام وإعادتها إلى قيد التحصيل', NULL),
        /* the page */
        ('col.title', 'col', N'Collection', N'التحصيل', NULL),
        ('col.subtitle', 'col', N'Work permit salary differences paid with the payroll and collected back from employees', N'فروق راتب إذن العمل المصروفة مع الرواتب والمستردة من الموظفين', NULL),
        ('col.intro_title', 'col', N'Work Permit Collection.', N'تحصيل فرق راتب إذن العمل.', NULL),
        ('col.intro_text', 'col', N'When an employee''s gross monthly salary (Basic + Allowances) is below the work permit salary, the payroll pays the difference so the bank transfer reaches the work permit salary. The company collects it back from the employee - mark it here once received.', N'عندما يكون إجمالي الراتب الشهري للموظف (الأساسي + البدلات) أقل من راتب إذن العمل، تصرف الرواتب الفرق ليصل التحويل البنكي إلى راتب إذن العمل. تسترد الشركة هذا الفرق من الموظف - سجّل استلامه هنا.', NULL),
        ('col.pick_label', 'col', N'Company and payroll month', N'الشركة وشهر الرواتب', NULL),
        ('col.payroll_month', 'col', N'Payroll month', N'شهر الرواتب', NULL),
        ('col.loading_months', 'col', N'Loading months…', N'جارٍ تحميل الأشهر…', NULL),
        ('col.all_pending_first', 'col', N'All (pending first)', N'الكل (قيد التحصيل أولاً)', NULL),
        ('col.status_pending', 'col', N'Pending', N'قيد التحصيل', NULL),
        ('col.status_collected', 'col', N'Collected', N'تم التحصيل', NULL),
        ('col.search', 'col', N'Search', N'بحث', NULL),
        ('col.search_placeholder', 'col', N'Employee, number or reference', N'الموظف أو الرقم أو المرجع', NULL),
        ('col.kpi_total', 'col', N'Total collection', N'إجمالي التحصيل', NULL),
        ('col.kpi_n_employees', 'col', N'KWD · {0} employees', N'د.ك · {0} موظفين', NULL),
        ('col.kpi_pending', 'col', N'Pending collection', N'قيد التحصيل', NULL),
        ('col.kpi_n_to_collect', 'col', N'KWD · {0} still to collect', N'د.ك · {0} بانتظار التحصيل', NULL),
        ('col.kpi_collected', 'col', N'Collected', N'تم تحصيله', NULL),
        ('col.kpi_n_received', 'col', N'KWD · {0} received', N'د.ك · {0} تم استلامها', NULL),
        ('col.progress', 'col', N'{0}% of the month received', N'تم استلام {0}% من الشهر', NULL),
        ('col.1_collection', 'col', N'1 collection', N'تحصيل واحد', NULL),
        ('col.0_collections', 'col', N'{0} collections', N'{0} تحصيلات', NULL),
        ('col.none_this_month', 'col', N'Nothing to collect this month', N'لا يوجد ما يُحصّل هذا الشهر', NULL),
        ('col.none_this_month_text', 'col', N'Every employee''s gross monthly salary reaches their work permit salary, or the payroll has not been generated yet.', N'إجمالي الراتب الشهري لكل موظف يصل إلى راتب إذن العمل، أو لم يتم إنشاء الرواتب بعد.', NULL),
        ('col.none_match', 'col', N'No collections match the filters', N'لا توجد تحصيلات تطابق عوامل التصفية', NULL),
        ('col.none_match_text', 'col', N'Clear the search or choose another status.', N'امسح البحث أو اختر حالة أخرى.', NULL),
        ('col.no_payroll_yet', 'col', N'No payroll for this company yet', N'لا توجد رواتب لهذه الشركة بعد', NULL),
        ('col.no_payroll_yet_text', 'col', N'Collections are added when a payroll is generated.', N'تُضاف التحصيلات عند إنشاء الرواتب.', NULL),
        ('col.gross_monthly', 'col', N'Gross monthly (KWD)', N'إجمالي الراتب الشهري (د.ك)', NULL),
        ('col.work_permit_salary', 'col', N'Work permit salary (KWD)', N'راتب إذن العمل (د.ك)', NULL),
        ('col.amount', 'col', N'To collect (KWD)', N'المبلغ المطلوب تحصيله (د.ك)', NULL),
        ('col.received', 'col', N'Received', N'الاستلام', NULL),
        ('col.draft_payroll', 'col', N'Draft payroll', N'رواتب مسودة', NULL),
        ('col.by_0', 'col', N'by {0}', N'بواسطة {0}', NULL),
        ('col.ref_0', 'col', N'Ref. {0}', N'مرجع {0}', NULL),
        ('col.mark_received', 'col', N'Mark as received', N'تسجيل الاستلام', NULL),
        ('col.mark_selected', 'col', N'Mark selected as received', N'تسجيل استلام المحدد', NULL),
        ('col.1_selected', 'col', N'1 selected', N'تم تحديد 1', NULL),
        ('col.0_selected', 'col', N'{0} selected', N'تم تحديد {0}', NULL),
        ('col.select_all_pending', 'col', N'Select all pending', N'تحديد كل ما هو قيد التحصيل', NULL),
        ('col.select_0', 'col', N'Select {0}', N'تحديد {0}', NULL),
        ('col.date_received', 'col', N'Date received', N'تاريخ الاستلام', NULL),
        ('col.reference', 'col', N'Receipt reference', N'مرجع الإيصال', NULL),
        ('col.reference_hint', 'col', N'Receipt or voucher number', N'رقم الإيصال أو السند', NULL),
        ('col.comment_hint', 'col', N'How it was received, e.g. cash', N'طريقة الاستلام، مثل نقداً', NULL),
        ('col.set_back', 'col', N'Set back to pending', N'إعادة إلى قيد التحصيل', NULL),
        ('col.why_set_back', 'col', N'Why is it set back to pending?', N'لماذا تتم إعادته إلى قيد التحصيل؟', NULL),
        ('col.received_on', 'col', N'Received on', N'تاريخ الاستلام', NULL),
        ('col.no_history', 'col', N'No history recorded yet.', N'لا يوجد سجل بعد.', NULL),
        ('col.h_created', 'col', N'Added by the payroll', N'أُضيف من الرواتب', NULL),
        ('col.h_updated', 'col', N'Amount changed (payroll recalculated)', N'تغيّر المبلغ (أُعيد احتساب الرواتب)', NULL),
        ('col.h_collected', 'col', N'Marked as received', N'تم تسجيل الاستلام', NULL),
        ('col.h_reopened', 'col', N'Set back to pending', N'أُعيد إلى قيد التحصيل', NULL),
        ('col.h_removed', 'col', N'Removed (no longer due)', N'أُزيل (لم يعد مستحقاً)', NULL),
        ('col.h_changed', 'col', N'Changed', N'تم التغيير', NULL),
        /* page script */
        ('js.col_loading_months', 'js', N'Loading months…', N'جارٍ تحميل الأشهر…', NULL),
        ('js.col_no_months', 'js', N'No payroll yet', N'لا توجد رواتب بعد', NULL),
        ('js.col_month_pending', 'js', N'{0} · {1} pending', N'{0} · {1} قيد التحصيل', NULL),
        ('js.col_enter_date', 'js', N'Enter the date it was received.', N'أدخل تاريخ الاستلام.', NULL),
        ('js.col_enter_reason', 'js', N'Enter why it is set back to pending.', N'أدخل سبب الإعادة إلى قيد التحصيل.', NULL),
        ('js.col_collect_one', 'js', N'{0} · KWD {1}', N'{0} · {1} د.ك', NULL),
        ('js.col_collect_many', 'js', N'{0} collections · KWD {1}', N'{0} تحصيلات · {1} د.ك', NULL),
        /* messages of the procedure (translated on the way out) */
        ('msg.col_marked_received', 'msg', N'Marked as received.', N'تم تسجيل الاستلام.', NULL),
        ('msg.col_set_back', 'msg', N'Set back to pending.', N'تمت الإعادة إلى قيد التحصيل.', NULL),
        ('msg.col_draft', 'msg', N'The payroll is still a draft - create it before marking its collections as received.', N'الرواتب ما زالت مسودة - أنشئها قبل تسجيل استلام تحصيلاتها.', NULL),
        ('msg.col_future', 'msg', N'The date received cannot be in the future.', N'لا يمكن أن يكون تاريخ الاستلام في المستقبل.', NULL),
        ('msg.col_select', 'msg', N'Select the collections that were received.', N'حدد التحصيلات التي تم استلامها.', NULL),
        ('msg.col_reason', 'msg', N'Enter why it is set back to pending.', N'أدخل سبب الإعادة إلى قيد التحصيل.', NULL),
        ('msg.col_already', 'msg', N'A selected collection was already marked as received. The list has been refreshed.', N'تم تسجيل استلام أحد التحصيلات المحددة مسبقاً. تم تحديث القائمة.', NULL),
        ('msg.col_gone', 'msg', N'A selected collection no longer exists. The list has been refreshed.', N'أحد التحصيلات المحددة لم يعد موجوداً. تم تحديث القائمة.', NULL),
        ('pr.collection', 'pr', N'Collection', N'تحصيل', NULL),
        ('pr.src_collection', 'pr', N'Work permit collection', N'تحصيل فرق راتب إذن العمل', NULL),
        ('ps.doc_collection', 'ps', N'Collection', N'التحصيل', NULL),
        ('ps.doc_total_collection', 'ps', N'Total collection', N'إجمالي التحصيل', NULL),
        ('ps.doc_collection_note', 'ps', N'Paid with the salary; collected back from the employee', N'يُصرف مع الراتب ويُسترد من الموظف', NULL),
        ('msg.pc_type_three', 'msg', N'Choose whether this is an Earning, a Deduction or a Collection.', N'اختر ما إذا كان استحقاقاً أو استقطاعاً أو تحصيلاً.', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Collection labels inserted: ', @LabelsInserted);
GO
