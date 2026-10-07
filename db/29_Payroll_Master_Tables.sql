/* =====================================================================
   29_Payroll_Master_Tables.sql  -  HRMS Kuwait: Payroll Phase 1 (Master Setup)
   ---------------------------------------------------------------------
   Run AFTER 28_Soft_Delete.sql (it relies on the soft-delete database
   trigger TR_HRMS_SoftDelete_OnCreateTable being in place, but every
   table below also declares its own Deleted / DeletedBy / DeletedDate
   columns so it works either way).

   Creates the configuration tables of the Payroll Master Setup screen.
   Everything here is DATA-DRIVEN: components, calendars, structures,
   statutory rates and banks are rows, not code - add, deactivate or
   (soft-)delete them from the UI.

     Payroll.PayrollCalendars              pay frequency, cut-off / payment rules
     Payroll.PayrollPeriods                generated periods + status workflow
     Payroll.PayrollPeriodStatusHistory    audit of every status change
     Payroll.PayComponents                 earnings AND deductions (one table,
                                           ComponentType = EARNING / DEDUCTION)
     Payroll.SalaryStructures              grade templates tied to Designation /
                                           Job Position / Grade
     Payroll.SalaryStructureComponents     the components inside a structure
     Payroll.PifssContributionRates        effective-dated social security rates
     Payroll.IndemnityRuleSets             effective-dated end-of-service rules
     Payroll.IndemnityServiceSlabs           - entitlement per year of service
     Payroll.IndemnityEntitlementFactors     - % paid per separation type
     Payroll.OvertimeRates                 effective-dated OT multipliers
     Payroll.Banks                         bank master with WPS / SWIFT / IBAN codes
     Payroll.CompanyBankAccounts           the company's own debit accounts

   Conventions (same as the rest of the database)
     * Never physically deleted: Deleted BIT + DeletedBy + DeletedDate.
     * Unique keys are filtered indexes  WHERE Deleted = 0  so a deleted
       code can be re-used.
     * IsActive = "deactivate" (still visible, not offered for new use).
     * Money = DECIMAL(12,3) (KWD has 3 decimals). Rates = DECIMAL(7,4) %.
     * Idempotent: every object is guarded, safe to re-run.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* ---------------------------------------------------------------------
   0. Schema + pre-flight
   ---------------------------------------------------------------------
   The base schema (script 01) may already contain a [Payroll] schema.
   If it also contains a table with one of the names below but a
   different shape, stop here BEFORE changing anything rather than
   failing half-way through script 30.
--------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Payroll')
    EXEC (N'CREATE SCHEMA [Payroll] AUTHORIZATION [dbo];');
GO

DECLARE @Conflicts NVARCHAR(MAX);

/* Every column these scripts rely on (for PayrollPeriods: only the
   base-schema columns - section 2 adds the calendar columns itself). A pre-existing table of the same
   name that is missing ANY of them is reported, and nothing is changed. */
DECLARE @Expected TABLE (TableName SYSNAME, ColumnName SYSNAME);
INSERT INTO @Expected (TableName, ColumnName) VALUES
    (N'PayrollPeriods', N'PayrollPeriodId'),
    (N'PayrollPeriods', N'CompanyId'),
    (N'PayrollPeriods', N'PayrollYear'),
    (N'PayrollPeriods', N'PayrollMonth'),
    (N'PayrollPeriods', N'StartDate'),
    (N'PayrollPeriods', N'EndDate'),
    (N'PayrollPeriods', N'PaymentDate'),
    (N'PayrollPeriods', N'Status'),
    (N'PayrollCalendars', N'PayrollCalendarId'),
    (N'PayrollCalendars', N'CompanyId'),
    (N'PayrollCalendars', N'CalendarCode'),
    (N'PayrollCalendars', N'CalendarName'),
    (N'PayrollCalendars', N'ArabicName'),
    (N'PayrollCalendars', N'PayFrequency'),
    (N'PayrollCalendars', N'FirstPeriodStartDate'),
    (N'PayrollCalendars', N'CutOffDay'),
    (N'PayrollCalendars', N'PaymentDay'),
    (N'PayrollCalendars', N'PaymentMonthOffset'),
    (N'PayrollCalendars', N'CutOffOffsetDays'),
    (N'PayrollCalendars', N'PaymentOffsetDays'),
    (N'PayrollCalendars', N'WorkingDaysBasis'),
    (N'PayrollCalendars', N'FixedDaysPerMonth'),
    (N'PayrollCalendars', N'CurrencyId'),
    (N'PayrollCalendars', N'Description'),
    (N'PayrollCalendars', N'IsDefault'),
    (N'PayrollCalendars', N'IsActive'),
    (N'PayrollCalendars', N'CreatedBy'),
    (N'PayrollCalendars', N'CreatedDate'),
    (N'PayrollCalendars', N'ModifiedBy'),
    (N'PayrollCalendars', N'ModifiedDate'),
    (N'PayrollCalendars', N'Deleted'),
    (N'PayrollCalendars', N'DeletedBy'),
    (N'PayrollCalendars', N'DeletedDate'),
    (N'PayrollPeriodStatusHistory', N'PeriodStatusHistoryId'),
    (N'PayrollPeriodStatusHistory', N'PayrollPeriodId'),
    (N'PayrollPeriodStatusHistory', N'FromStatus'),
    (N'PayrollPeriodStatusHistory', N'ToStatus'),
    (N'PayrollPeriodStatusHistory', N'Remarks'),
    (N'PayrollPeriodStatusHistory', N'ChangedBy'),
    (N'PayrollPeriodStatusHistory', N'ChangedDate'),
    (N'PayrollPeriodStatusHistory', N'Deleted'),
    (N'PayrollPeriodStatusHistory', N'DeletedBy'),
    (N'PayrollPeriodStatusHistory', N'DeletedDate'),
    (N'PayComponents', N'PayComponentId'),
    (N'PayComponents', N'CompanyId'),
    (N'PayComponents', N'ComponentCode'),
    (N'PayComponents', N'ComponentName'),
    (N'PayComponents', N'ArabicName'),
    (N'PayComponents', N'PayslipLabel'),
    (N'PayComponents', N'ComponentType'),
    (N'PayComponents', N'ValueType'),
    (N'PayComponents', N'CalculationMethod'),
    (N'PayComponents', N'CalculationBase'),
    (N'PayComponents', N'DefaultAmount'),
    (N'PayComponents', N'DefaultPercentage'),
    (N'PayComponents', N'Formula'),
    (N'PayComponents', N'MinAmount'),
    (N'PayComponents', N'MaxAmount'),
    (N'PayComponents', N'IsTaxable'),
    (N'PayComponents', N'IsPifssApplicable'),
    (N'PayComponents', N'IsIndemnityApplicable'),
    (N'PayComponents', N'IsOvertimeApplicable'),
    (N'PayComponents', N'IsLeaveSalaryApplicable'),
    (N'PayComponents', N'IsRecurring'),
    (N'PayComponents', N'IsProrated'),
    (N'PayComponents', N'ShowOnPayslip'),
    (N'PayComponents', N'GLAccountCode'),
    (N'PayComponents', N'GLAccountName'),
    (N'PayComponents', N'CostCenterId'),
    (N'PayComponents', N'DisplayOrder'),
    (N'PayComponents', N'SystemCode'),
    (N'PayComponents', N'IsSystem'),
    (N'PayComponents', N'Description'),
    (N'PayComponents', N'IsActive'),
    (N'PayComponents', N'CreatedBy'),
    (N'PayComponents', N'CreatedDate'),
    (N'PayComponents', N'ModifiedBy'),
    (N'PayComponents', N'ModifiedDate'),
    (N'PayComponents', N'Deleted'),
    (N'PayComponents', N'DeletedBy'),
    (N'PayComponents', N'DeletedDate'),
    (N'SalaryStructures', N'SalaryStructureId'),
    (N'SalaryStructures', N'CompanyId'),
    (N'SalaryStructures', N'StructureCode'),
    (N'SalaryStructures', N'StructureName'),
    (N'SalaryStructures', N'ArabicName'),
    (N'SalaryStructures', N'DesignationId'),
    (N'SalaryStructures', N'PositionId'),
    (N'SalaryStructures', N'GradeId'),
    (N'SalaryStructures', N'PayrollCalendarId'),
    (N'SalaryStructures', N'EffectiveFrom'),
    (N'SalaryStructures', N'EffectiveTo'),
    (N'SalaryStructures', N'Description'),
    (N'SalaryStructures', N'IsActive'),
    (N'SalaryStructures', N'CreatedBy'),
    (N'SalaryStructures', N'CreatedDate'),
    (N'SalaryStructures', N'ModifiedBy'),
    (N'SalaryStructures', N'ModifiedDate'),
    (N'SalaryStructures', N'Deleted'),
    (N'SalaryStructures', N'DeletedBy'),
    (N'SalaryStructures', N'DeletedDate'),
    (N'SalaryStructureComponents', N'SalaryStructureComponentId'),
    (N'SalaryStructureComponents', N'SalaryStructureId'),
    (N'SalaryStructureComponents', N'PayComponentId'),
    (N'SalaryStructureComponents', N'CalculationMethod'),
    (N'SalaryStructureComponents', N'CalculationBase'),
    (N'SalaryStructureComponents', N'Amount'),
    (N'SalaryStructureComponents', N'Percentage'),
    (N'SalaryStructureComponents', N'MinAmount'),
    (N'SalaryStructureComponents', N'MaxAmount'),
    (N'SalaryStructureComponents', N'IsMandatory'),
    (N'SalaryStructureComponents', N'AllowOverride'),
    (N'SalaryStructureComponents', N'DisplayOrder'),
    (N'SalaryStructureComponents', N'CreatedBy'),
    (N'SalaryStructureComponents', N'CreatedDate'),
    (N'SalaryStructureComponents', N'ModifiedBy'),
    (N'SalaryStructureComponents', N'ModifiedDate'),
    (N'SalaryStructureComponents', N'Deleted'),
    (N'SalaryStructureComponents', N'DeletedBy'),
    (N'SalaryStructureComponents', N'DeletedDate'),
    (N'PifssContributionRates', N'PifssRateId'),
    (N'PifssContributionRates', N'ContributionCode'),
    (N'PifssContributionRates', N'ContributionName'),
    (N'PifssContributionRates', N'ApplicableTo'),
    (N'PifssContributionRates', N'CalculationBasis'),
    (N'PifssContributionRates', N'EmployeeRate'),
    (N'PifssContributionRates', N'EmployerRate'),
    (N'PifssContributionRates', N'GovernmentRate'),
    (N'PifssContributionRates', N'SalaryFloor'),
    (N'PifssContributionRates', N'SalaryCeiling'),
    (N'PifssContributionRates', N'EffectiveFrom'),
    (N'PifssContributionRates', N'EffectiveTo'),
    (N'PifssContributionRates', N'IsVerified'),
    (N'PifssContributionRates', N'Notes'),
    (N'PifssContributionRates', N'IsActive'),
    (N'PifssContributionRates', N'CreatedBy'),
    (N'PifssContributionRates', N'CreatedDate'),
    (N'PifssContributionRates', N'ModifiedBy'),
    (N'PifssContributionRates', N'ModifiedDate'),
    (N'PifssContributionRates', N'Deleted'),
    (N'PifssContributionRates', N'DeletedBy'),
    (N'PifssContributionRates', N'DeletedDate'),
    (N'IndemnityRuleSets', N'IndemnityRuleSetId'),
    (N'IndemnityRuleSets', N'RuleSetCode'),
    (N'IndemnityRuleSets', N'RuleSetName'),
    (N'IndemnityRuleSets', N'DailyWageDivisor'),
    (N'IndemnityRuleSets', N'MaxIndemnityMonths'),
    (N'IndemnityRuleSets', N'MinServiceMonths'),
    (N'IndemnityRuleSets', N'EffectiveFrom'),
    (N'IndemnityRuleSets', N'EffectiveTo'),
    (N'IndemnityRuleSets', N'IsVerified'),
    (N'IndemnityRuleSets', N'Notes'),
    (N'IndemnityRuleSets', N'IsActive'),
    (N'IndemnityRuleSets', N'CreatedBy'),
    (N'IndemnityRuleSets', N'CreatedDate'),
    (N'IndemnityRuleSets', N'ModifiedBy'),
    (N'IndemnityRuleSets', N'ModifiedDate'),
    (N'IndemnityRuleSets', N'Deleted'),
    (N'IndemnityRuleSets', N'DeletedBy'),
    (N'IndemnityRuleSets', N'DeletedDate'),
    (N'IndemnityServiceSlabs', N'IndemnityServiceSlabId'),
    (N'IndemnityServiceSlabs', N'IndemnityRuleSetId'),
    (N'IndemnityServiceSlabs', N'FromYears'),
    (N'IndemnityServiceSlabs', N'ToYears'),
    (N'IndemnityServiceSlabs', N'EntitlementUnit'),
    (N'IndemnityServiceSlabs', N'EntitlementValue'),
    (N'IndemnityServiceSlabs', N'DisplayOrder'),
    (N'IndemnityServiceSlabs', N'CreatedBy'),
    (N'IndemnityServiceSlabs', N'CreatedDate'),
    (N'IndemnityServiceSlabs', N'Deleted'),
    (N'IndemnityServiceSlabs', N'DeletedBy'),
    (N'IndemnityServiceSlabs', N'DeletedDate'),
    (N'IndemnityEntitlementFactors', N'IndemnityEntitlementFactorId'),
    (N'IndemnityEntitlementFactors', N'IndemnityRuleSetId'),
    (N'IndemnityEntitlementFactors', N'SeparationType'),
    (N'IndemnityEntitlementFactors', N'FromYears'),
    (N'IndemnityEntitlementFactors', N'ToYears'),
    (N'IndemnityEntitlementFactors', N'EntitlementPercent'),
    (N'IndemnityEntitlementFactors', N'CreatedBy'),
    (N'IndemnityEntitlementFactors', N'CreatedDate'),
    (N'IndemnityEntitlementFactors', N'Deleted'),
    (N'IndemnityEntitlementFactors', N'DeletedBy'),
    (N'IndemnityEntitlementFactors', N'DeletedDate'),
    (N'OvertimeRates', N'OvertimeRateId'),
    (N'OvertimeRates', N'CompanyId'),
    (N'OvertimeRates', N'OvertimeCode'),
    (N'OvertimeRates', N'OvertimeName'),
    (N'OvertimeRates', N'Multiplier'),
    (N'OvertimeRates', N'HourlyRateDivisorDays'),
    (N'OvertimeRates', N'HoursPerDay'),
    (N'OvertimeRates', N'MaxHoursPerDay'),
    (N'OvertimeRates', N'MaxHoursPerYear'),
    (N'OvertimeRates', N'EffectiveFrom'),
    (N'OvertimeRates', N'EffectiveTo'),
    (N'OvertimeRates', N'IsVerified'),
    (N'OvertimeRates', N'Notes'),
    (N'OvertimeRates', N'IsActive'),
    (N'OvertimeRates', N'CreatedBy'),
    (N'OvertimeRates', N'CreatedDate'),
    (N'OvertimeRates', N'ModifiedBy'),
    (N'OvertimeRates', N'ModifiedDate'),
    (N'OvertimeRates', N'Deleted'),
    (N'OvertimeRates', N'DeletedBy'),
    (N'OvertimeRates', N'DeletedDate'),
    (N'Banks', N'BankId'),
    (N'Banks', N'BankCode'),
    (N'Banks', N'BankName'),
    (N'Banks', N'ArabicName'),
    (N'Banks', N'ShortName'),
    (N'Banks', N'SwiftCode'),
    (N'Banks', N'IbanBankCode'),
    (N'Banks', N'WpsBankCode'),
    (N'Banks', N'CountryId'),
    (N'Banks', N'IsActive'),
    (N'Banks', N'CreatedBy'),
    (N'Banks', N'CreatedDate'),
    (N'Banks', N'ModifiedBy'),
    (N'Banks', N'ModifiedDate'),
    (N'Banks', N'Deleted'),
    (N'Banks', N'DeletedBy'),
    (N'Banks', N'DeletedDate'),
    (N'CompanyBankAccounts', N'CompanyBankAccountId'),
    (N'CompanyBankAccounts', N'CompanyId'),
    (N'CompanyBankAccounts', N'BankId'),
    (N'CompanyBankAccounts', N'AccountCode'),
    (N'CompanyBankAccounts', N'AccountTitle'),
    (N'CompanyBankAccounts', N'AccountNumber'),
    (N'CompanyBankAccounts', N'Iban'),
    (N'CompanyBankAccounts', N'CurrencyId'),
    (N'CompanyBankAccounts', N'BranchName'),
    (N'CompanyBankAccounts', N'WpsEmployerCode'),
    (N'CompanyBankAccounts', N'PamFileNo'),
    (N'CompanyBankAccounts', N'IsDefault'),
    (N'CompanyBankAccounts', N'IsActive'),
    (N'CompanyBankAccounts', N'CreatedBy'),
    (N'CompanyBankAccounts', N'CreatedDate'),
    (N'CompanyBankAccounts', N'ModifiedBy'),
    (N'CompanyBankAccounts', N'ModifiedDate'),
    (N'CompanyBankAccounts', N'Deleted'),
    (N'CompanyBankAccounts', N'DeletedBy'),
    (N'CompanyBankAccounts', N'DeletedDate');

SELECT @Conflicts = STRING_AGG(CAST(x.Detail AS NVARCHAR(MAX)), N'; ')
FROM (
    SELECT e.TableName + N' (missing: ' + STRING_AGG(CAST(e.ColumnName AS NVARCHAR(MAX)), N', ') + N')' AS Detail
    FROM @Expected AS e
    WHERE OBJECT_ID(N'[Payroll].' + QUOTENAME(e.TableName), N'U') IS NOT NULL
      AND COL_LENGTH(N'[Payroll].' + QUOTENAME(e.TableName), e.ColumnName) IS NULL
    GROUP BY e.TableName
) AS x;

IF @Conflicts IS NOT NULL
BEGIN
    RAISERROR (N'STOPPED - these Payroll tables already exist with a different structure: %s. Nothing was changed.', 16, 1, @Conflicts);
    SET NOEXEC ON;   -- skip every remaining batch in this script
END;
GO

/* =====================================================================
   1. Payroll.PayrollCalendars
   ---------------------------------------------------------------------
   One calendar = one pay group (e.g. "Monthly Staff", "Weekly Labour").
   MONTHLY      uses CutOffDay / PaymentDay (+ PaymentMonthOffset).
   WEEKLY /     uses CutOffOffsetDays / PaymentOffsetDays, counted from
   BIWEEKLY     the period END date (negative = before the end).
   WorkingDaysBasis drives proration and daily-rate maths later:
     CALENDAR = actual days in the period, FIXED = FixedDaysPerMonth
     (26 or 30), WORKING = working days per the calendar/shift.
===================================================================== */
IF OBJECT_ID(N'[Payroll].[PayrollCalendars]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollCalendars](
        PayrollCalendarId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollCalendars PRIMARY KEY,
        CompanyId             INT            NOT NULL,
        CalendarCode          NVARCHAR(30)   NOT NULL,
        CalendarName          NVARCHAR(150)  NOT NULL,
        ArabicName            NVARCHAR(150)  NULL,
        PayFrequency          VARCHAR(10)    NOT NULL,
        FirstPeriodStartDate  DATE           NOT NULL,
        CutOffDay             TINYINT        NULL,
        PaymentDay            TINYINT        NULL,
        PaymentMonthOffset    TINYINT        NOT NULL CONSTRAINT DF_PayrollCalendars_PaymentMonthOffset DEFAULT (0),
        CutOffOffsetDays      SMALLINT       NULL,
        PaymentOffsetDays     SMALLINT       NULL,
        WorkingDaysBasis      VARCHAR(10)    NOT NULL CONSTRAINT DF_PayrollCalendars_WorkingDaysBasis DEFAULT ('FIXED'),
        FixedDaysPerMonth     TINYINT        NULL     CONSTRAINT DF_PayrollCalendars_FixedDaysPerMonth DEFAULT (26),
        CurrencyId            INT            NULL,
        Description           NVARCHAR(500)  NULL,
        IsDefault             BIT            NOT NULL CONSTRAINT DF_PayrollCalendars_IsDefault DEFAULT (0),
        IsActive              BIT            NOT NULL CONSTRAINT DF_PayrollCalendars_IsActive  DEFAULT (1),
        CreatedBy             BIGINT         NULL,
        CreatedDate           DATETIME2(0)   NOT NULL CONSTRAINT DF_PayrollCalendars_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy            BIGINT         NULL,
        ModifiedDate          DATETIME2(0)   NULL,
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollCalendars_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_PayrollCalendars_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_PayrollCalendars_Currency FOREIGN KEY (CurrencyId) REFERENCES [Core].[Currencies](CurrencyId),
        CONSTRAINT CK_PayrollCalendars_Frequency CHECK (PayFrequency IN ('MONTHLY', 'BIWEEKLY', 'WEEKLY')),
        CONSTRAINT CK_PayrollCalendars_DaysBasis CHECK (WorkingDaysBasis IN ('CALENDAR', 'FIXED', 'WORKING')),
        CONSTRAINT CK_PayrollCalendars_FixedDays CHECK (WorkingDaysBasis <> 'FIXED' OR (FixedDaysPerMonth IS NOT NULL AND FixedDaysPerMonth BETWEEN 1 AND 31)),
        CONSTRAINT CK_PayrollCalendars_CutOffDay  CHECK (CutOffDay  IS NULL OR CutOffDay  BETWEEN 1 AND 31),
        CONSTRAINT CK_PayrollCalendars_PaymentDay CHECK (PaymentDay IS NULL OR PaymentDay BETWEEN 1 AND 31),
        CONSTRAINT CK_PayrollCalendars_MonthOffset CHECK (PaymentMonthOffset IN (0, 1)),
        CONSTRAINT CK_PayrollCalendars_MonthlyRules CHECK (
               (PayFrequency =  'MONTHLY' AND CutOffDay IS NOT NULL AND PaymentDay IS NOT NULL)
            OR (PayFrequency <> 'MONTHLY' AND CutOffOffsetDays IS NOT NULL AND PaymentOffsetDays IS NOT NULL))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayrollCalendars_Code' AND object_id = OBJECT_ID(N'[Payroll].[PayrollCalendars]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollCalendars_Code
        ON [Payroll].[PayrollCalendars](CompanyId, CalendarCode) WHERE Deleted = 0;
GO
/* At most one default calendar per company. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayrollCalendars_Default' AND object_id = OBJECT_ID(N'[Payroll].[PayrollCalendars]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollCalendars_Default
        ON [Payroll].[PayrollCalendars](CompanyId) WHERE IsDefault = 1 AND Deleted = 0;
GO

/* =====================================================================
   2. Payroll.PayrollPeriods  (+ status history)
   ---------------------------------------------------------------------
   Status workflow:  OPEN -> PROCESSING -> APPROVED -> POSTED -> CLOSED
   (PROCESSING -> OPEN and APPROVED -> PROCESSING are allowed as
   "re-open" steps; POSTED and CLOSED are final.)

   The base schema (script 01) already ships a Payroll.PayrollPeriods
   (PayrollPeriodId, CompanyId, PayrollYear, PayrollMonth, StartDate,
   EndDate, PaymentDate, Status) that Payroll.PayrollRuns and
   Loans.LoanInstallments reference. It is UPGRADED IN PLACE - its
   columns, rows and foreign keys are kept - by adding the calendar
   columns below. On a database without it, the table is created with
   the same combined shape.
     CompanyId      = the calendar's company (kept in step by the procs)
     PayrollYear    = the year the period belongs to
     PayrollMonth   = month of the period's END date (which month's
                      payroll this is - also meaningful for weekly)
     PeriodNumber   = 1..12 monthly, 1..53 weekly, 1..27 bi-weekly
===================================================================== */
IF OBJECT_ID(N'[Payroll].[PayrollPeriods]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollPeriods](
        PayrollPeriodId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollPeriods PRIMARY KEY,
        CompanyId           INT            NOT NULL,
        PayrollYear         INT            NOT NULL,
        PayrollMonth        INT            NOT NULL,
        StartDate           DATE           NOT NULL,
        EndDate             DATE           NOT NULL,
        PaymentDate         DATE           NULL,
        Status              NVARCHAR(30)   NOT NULL CONSTRAINT DF_PayrollPeriods_Status DEFAULT (N'OPEN'),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PayrollPeriods_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,
        CONSTRAINT FK_PayrollPeriods_Company FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId)
    );
END
GO

/* ---- 2a. add the calendar columns (each guarded - safe to re-run) ---- */
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'PayrollCalendarId') IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD PayrollCalendarId INT           NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'PeriodNumber')      IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD PeriodNumber      TINYINT       NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'PeriodCode')        IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD PeriodCode        NVARCHAR(30)  NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'PeriodName')        IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD PeriodName        NVARCHAR(100) NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'CutOffDate')        IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD CutOffDate        DATE          NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'StatusChangedBy')   IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD StatusChangedBy   BIGINT        NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'StatusChangedDate') IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD StatusChangedDate DATETIME2(0)  NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'Remarks')           IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD Remarks           NVARCHAR(500) NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'CreatedBy')         IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD CreatedBy         BIGINT        NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'CreatedDate')       IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD CreatedDate       DATETIME2(0)  NOT NULL
                                                                         CONSTRAINT DF_PayrollPeriods_CreatedDate DEFAULT (SYSUTCDATETIME());
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'ModifiedBy')        IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD ModifiedBy        BIGINT        NULL;
IF COL_LENGTH(N'Payroll.PayrollPeriods', N'ModifiedDate')      IS NULL ALTER TABLE [Payroll].[PayrollPeriods] ADD ModifiedDate      DATETIME2(0)  NULL;
GO

/* ---- 2b. while the table is still empty, make the calendar columns
           mandatory (a table that already holds base-schema periods
           keeps them nullable so those rows stay valid) -------------- */
IF NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollPeriods])
BEGIN
    IF COLUMNPROPERTY(OBJECT_ID(N'Payroll.PayrollPeriods'), N'PayrollCalendarId', 'AllowsNull') = 1
        ALTER TABLE [Payroll].[PayrollPeriods] ALTER COLUMN PayrollCalendarId INT NOT NULL;
    IF COLUMNPROPERTY(OBJECT_ID(N'Payroll.PayrollPeriods'), N'PeriodNumber', 'AllowsNull') = 1
        ALTER TABLE [Payroll].[PayrollPeriods] ALTER COLUMN PeriodNumber TINYINT NOT NULL;
    IF COLUMNPROPERTY(OBJECT_ID(N'Payroll.PayrollPeriods'), N'PeriodCode', 'AllowsNull') = 1
        ALTER TABLE [Payroll].[PayrollPeriods] ALTER COLUMN PeriodCode NVARCHAR(30) NOT NULL;
    IF COLUMNPROPERTY(OBJECT_ID(N'Payroll.PayrollPeriods'), N'PeriodName', 'AllowsNull') = 1
        ALTER TABLE [Payroll].[PayrollPeriods] ALTER COLUMN PeriodName NVARCHAR(100) NOT NULL;
    IF COLUMNPROPERTY(OBJECT_ID(N'Payroll.PayrollPeriods'), N'CutOffDate', 'AllowsNull') = 1
        ALTER TABLE [Payroll].[PayrollPeriods] ALTER COLUMN CutOffDate DATE NOT NULL;
END
ELSE
    PRINT N'NOTE: Payroll.PayrollPeriods already holds rows - the new calendar columns were left nullable. Assign those periods to a calendar before processing them.';
GO

/* ---- 2c. remove base-schema rules that conflict with calendars ------
   * A unique key that does not include PayrollCalendarId (e.g.
     CompanyId + PayrollYear + PayrollMonth) would forbid weekly periods
     and a second calendar per company - it is replaced by the
     calendar-scoped unique indexes in 2e.
   * A CHECK / DEFAULT on Status with other values would reject the
     OPEN / PROCESSING / APPROVED / POSTED / CLOSED workflow - replaced
     in 2d. Each change is PRINTed. ------------------------------------- */
DECLARE @sql NVARCHAR(MAX), @name SYSNAME, @isConstraint BIT;
DECLARE @oid INT = OBJECT_ID(N'Payroll.PayrollPeriods');

DECLARE ix CURSOR LOCAL STATIC READ_ONLY FOR
    SELECT i.name, i.is_unique_constraint
    FROM   sys.indexes AS i
    WHERE  i.object_id = @oid AND i.is_unique = 1 AND i.is_primary_key = 0
      AND  i.name NOT IN (N'UX_PayrollPeriods_Number', N'UX_PayrollPeriods_StartDate')
      AND  NOT EXISTS (SELECT 1 FROM sys.index_columns ic JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
                       WHERE ic.object_id = i.object_id AND ic.index_id = i.index_id AND c.name = N'PayrollCalendarId');
OPEN ix;
FETCH NEXT FROM ix INTO @name, @isConstraint;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = CASE WHEN @isConstraint = 1
                    THEN N'ALTER TABLE [Payroll].[PayrollPeriods] DROP CONSTRAINT ' + QUOTENAME(@name) + N';'
                    ELSE N'DROP INDEX ' + QUOTENAME(@name) + N' ON [Payroll].[PayrollPeriods];' END;
    EXEC (@sql);
    PRINT N'Replaced base-schema unique key ' + @name + N' on Payroll.PayrollPeriods (it did not allow more than one calendar).';
    FETCH NEXT FROM ix INTO @name, @isConstraint;
END;
CLOSE ix; DEALLOCATE ix;

DECLARE ck CURSOR LOCAL STATIC READ_ONLY FOR
    SELECT cc.name FROM sys.check_constraints AS cc
    JOIN   sys.columns AS c ON c.object_id = cc.parent_object_id AND c.column_id = cc.parent_column_id
    WHERE  cc.parent_object_id = @oid AND c.name = N'Status' AND cc.name <> N'CK_PayrollPeriods_Status'
    UNION
    SELECT cc.name FROM sys.check_constraints AS cc       -- table-level checks that mention Status
    WHERE  cc.parent_object_id = @oid AND cc.parent_column_id = 0 AND cc.definition LIKE N'%[[]Status]%'
      AND  cc.name <> N'CK_PayrollPeriods_Status';
OPEN ck;
FETCH NEXT FROM ck INTO @name;
WHILE @@FETCH_STATUS = 0
BEGIN
    SET @sql = N'ALTER TABLE [Payroll].[PayrollPeriods] DROP CONSTRAINT ' + QUOTENAME(@name) + N';';
    EXEC (@sql);
    PRINT N'Replaced base-schema status check ' + @name + N' on Payroll.PayrollPeriods.';
    FETCH NEXT FROM ck INTO @name;
END;
CLOSE ck; DEALLOCATE ck;

SET @name = NULL;
SELECT @name = dc.name
FROM   sys.default_constraints AS dc
JOIN   sys.columns AS c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
WHERE  dc.parent_object_id = @oid AND c.name = N'Status'
  AND  dc.definition COLLATE Latin1_General_BIN NOT LIKE N'%''OPEN''%';     -- case-sensitive: 'Open' is replaced too
IF @name IS NOT NULL
BEGIN
    SET @sql = N'ALTER TABLE [Payroll].[PayrollPeriods] DROP CONSTRAINT ' + QUOTENAME(@name) + N';';
    EXEC (@sql);
    PRINT N'Replaced base-schema status default ' + @name + N' on Payroll.PayrollPeriods.';
END;
GO

/* ---- 2d. constraints -------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.default_constraints dc JOIN sys.columns c ON c.object_id = dc.parent_object_id AND c.column_id = dc.parent_column_id
               WHERE dc.parent_object_id = OBJECT_ID(N'Payroll.PayrollPeriods') AND c.name = N'Status')
    ALTER TABLE [Payroll].[PayrollPeriods] ADD CONSTRAINT DF_PayrollPeriods_Status DEFAULT (N'OPEN') FOR Status;
IF OBJECT_ID(N'[Payroll].[FK_PayrollPeriods_Calendar]', N'F') IS NULL
    ALTER TABLE [Payroll].[PayrollPeriods] ADD CONSTRAINT FK_PayrollPeriods_Calendar
        FOREIGN KEY (PayrollCalendarId) REFERENCES [Payroll].[PayrollCalendars](PayrollCalendarId);
IF OBJECT_ID(N'[Payroll].[CK_PayrollPeriods_Status]', N'C') IS NULL
    ALTER TABLE [Payroll].[PayrollPeriods] WITH NOCHECK ADD CONSTRAINT CK_PayrollPeriods_Status
        CHECK (Status IN (N'OPEN', N'PROCESSING', N'APPROVED', N'POSTED', N'CLOSED'));
IF OBJECT_ID(N'[Payroll].[CK_PayrollPeriods_Dates]', N'C') IS NULL
    ALTER TABLE [Payroll].[PayrollPeriods] WITH NOCHECK ADD CONSTRAINT CK_PayrollPeriods_Dates CHECK (EndDate >= StartDate);
IF OBJECT_ID(N'[Payroll].[CK_PayrollPeriods_Number]', N'C') IS NULL
    ALTER TABLE [Payroll].[PayrollPeriods] WITH NOCHECK ADD CONSTRAINT CK_PayrollPeriods_Number CHECK (PeriodNumber IS NULL OR PeriodNumber BETWEEN 1 AND 53);
GO

/* ---- 2e. calendar-scoped unique keys ------------------------------- */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayrollPeriods_Number' AND object_id = OBJECT_ID(N'[Payroll].[PayrollPeriods]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollPeriods_Number
        ON [Payroll].[PayrollPeriods](PayrollCalendarId, PayrollYear, PeriodNumber) WHERE Deleted = 0 AND PayrollCalendarId IS NOT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayrollPeriods_StartDate' AND object_id = OBJECT_ID(N'[Payroll].[PayrollPeriods]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayrollPeriods_StartDate
        ON [Payroll].[PayrollPeriods](PayrollCalendarId, StartDate) WHERE Deleted = 0 AND PayrollCalendarId IS NOT NULL;
GO

IF OBJECT_ID(N'[Payroll].[PayrollPeriodStatusHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayrollPeriodStatusHistory](
        PeriodStatusHistoryId BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayrollPeriodStatusHistory PRIMARY KEY,
        PayrollPeriodId       INT           NOT NULL,
        FromStatus            VARCHAR(12)   NULL,
        ToStatus              VARCHAR(12)   NOT NULL,
        Remarks               NVARCHAR(500) NULL,
        ChangedBy             BIGINT        NULL,
        ChangedDate           DATETIME2(0)  NOT NULL CONSTRAINT DF_PayrollPeriodStatusHistory_ChangedDate DEFAULT (SYSUTCDATETIME()),
        Deleted               BIT           NOT NULL CONSTRAINT DF_Payroll_PayrollPeriodStatusHistory_Deleted DEFAULT (0),
        DeletedBy             BIGINT        NULL,
        DeletedDate           DATETIME2(7)  NULL,
        CONSTRAINT FK_PayrollPeriodStatusHistory_Period FOREIGN KEY (PayrollPeriodId) REFERENCES [Payroll].[PayrollPeriods](PayrollPeriodId)
    );
    CREATE INDEX IX_PayrollPeriodStatusHistory_Period
        ON [Payroll].[PayrollPeriodStatusHistory](PayrollPeriodId, ChangedDate DESC);
END
GO

/* =====================================================================
   3. Payroll.PayComponents  -  earnings and deductions, fully dynamic
   ---------------------------------------------------------------------
   ComponentType      EARNING / DEDUCTION
   ValueType          FIXED (same every period, comes from the salary
                      package) / VARIABLE (entered or calculated per period)
   CalculationMethod  AMOUNT      fixed amount (DefaultAmount)
                      PERCENTAGE  DefaultPercentage % of CalculationBase
                      DAYS        (CalculationBase / days basis) x days
                      HOURS       hourly rate of CalculationBase x hours
                                  (x overtime multiplier for OT)
                      FORMULA     expression in Formula (evaluated by the
                                  payroll engine in Phase 2)
                      SYSTEM      computed by the engine (PIFSS, loans)
   CalculationBase    BASIC / FIXED_GROSS / OVERTIME_BASE / INDEMNITY_BASE
                      (the *_BASE values = sum of components whose
                       matching flag below is ticked)
   SystemCode         marks the few components the engine must recognise
                      (BASIC, OVERTIME, LOAN, SALARY_ADVANCE, ABSENCE,
                       UNPAID_LEAVE, PIFSS_EE). NULL for everything you add.
   IsSystem           seeded row: code / type / SystemCode are locked;
                      it can still be renamed, re-flagged, deactivated.
===================================================================== */
IF OBJECT_ID(N'[Payroll].[PayComponents]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PayComponents](
        PayComponentId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PayComponents PRIMARY KEY,
        CompanyId                INT            NOT NULL,
        ComponentCode            NVARCHAR(30)   NOT NULL,
        ComponentName            NVARCHAR(150)  NOT NULL,
        ArabicName               NVARCHAR(150)  NULL,
        PayslipLabel             NVARCHAR(100)  NULL,
        ComponentType            VARCHAR(10)    NOT NULL,
        ValueType                VARCHAR(10)    NOT NULL CONSTRAINT DF_PayComponents_ValueType DEFAULT ('FIXED'),
        CalculationMethod        VARCHAR(12)    NOT NULL CONSTRAINT DF_PayComponents_CalcMethod DEFAULT ('AMOUNT'),
        CalculationBase          VARCHAR(15)    NULL,
        DefaultAmount            DECIMAL(12,3)  NULL,
        DefaultPercentage        DECIMAL(7,4)   NULL,
        Formula                  NVARCHAR(1000) NULL,
        MinAmount                DECIMAL(12,3)  NULL,
        MaxAmount                DECIMAL(12,3)  NULL,

        /* ---- component properties ---- */
        IsTaxable                BIT NOT NULL CONSTRAINT DF_PayComponents_IsTaxable          DEFAULT (0),
        IsPifssApplicable        BIT NOT NULL CONSTRAINT DF_PayComponents_IsPifss            DEFAULT (0),
        IsIndemnityApplicable    BIT NOT NULL CONSTRAINT DF_PayComponents_IsIndemnity        DEFAULT (0),
        IsOvertimeApplicable     BIT NOT NULL CONSTRAINT DF_PayComponents_IsOvertime         DEFAULT (0),
        IsLeaveSalaryApplicable  BIT NOT NULL CONSTRAINT DF_PayComponents_IsLeaveSalary      DEFAULT (0),
        IsRecurring              BIT NOT NULL CONSTRAINT DF_PayComponents_IsRecurring        DEFAULT (1),
        IsProrated               BIT NOT NULL CONSTRAINT DF_PayComponents_IsProrated         DEFAULT (1),
        ShowOnPayslip            BIT NOT NULL CONSTRAINT DF_PayComponents_ShowOnPayslip      DEFAULT (1),

        GLAccountCode            NVARCHAR(50)   NULL,
        GLAccountName            NVARCHAR(150)  NULL,
        CostCenterId             INT            NULL,
        DisplayOrder             SMALLINT       NOT NULL CONSTRAINT DF_PayComponents_DisplayOrder DEFAULT (100),
        SystemCode               VARCHAR(30)    NULL,
        IsSystem                 BIT            NOT NULL CONSTRAINT DF_PayComponents_IsSystem DEFAULT (0),
        Description              NVARCHAR(500)  NULL,
        IsActive                 BIT            NOT NULL CONSTRAINT DF_PayComponents_IsActive DEFAULT (1),
        CreatedBy                BIGINT         NULL,
        CreatedDate              DATETIME2(0)   NOT NULL CONSTRAINT DF_PayComponents_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy               BIGINT         NULL,
        ModifiedDate             DATETIME2(0)   NULL,
        Deleted                  BIT            NOT NULL CONSTRAINT DF_Payroll_PayComponents_Deleted DEFAULT (0),
        DeletedBy                BIGINT         NULL,
        DeletedDate              DATETIME2(7)   NULL,

        CONSTRAINT FK_PayComponents_Company    FOREIGN KEY (CompanyId)    REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_PayComponents_CostCenter FOREIGN KEY (CostCenterId) REFERENCES [Core].[CostCenters](CostCenterId),
        CONSTRAINT CK_PayComponents_Type       CHECK (ComponentType IN ('EARNING', 'DEDUCTION')),
        CONSTRAINT CK_PayComponents_ValueType  CHECK (ValueType IN ('FIXED', 'VARIABLE')),
        CONSTRAINT CK_PayComponents_CalcMethod CHECK (CalculationMethod IN ('AMOUNT', 'PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA', 'SYSTEM')),
        CONSTRAINT CK_PayComponents_CalcBase   CHECK (CalculationBase IS NULL OR CalculationBase IN ('BASIC', 'FIXED_GROSS', 'OVERTIME_BASE', 'INDEMNITY_BASE')),
        CONSTRAINT CK_PayComponents_NeedsBase  CHECK (CalculationMethod NOT IN ('PERCENTAGE', 'DAYS', 'HOURS') OR CalculationBase IS NOT NULL),
        CONSTRAINT CK_PayComponents_NeedsPct   CHECK (CalculationMethod <> 'PERCENTAGE' OR DefaultPercentage IS NOT NULL),
        CONSTRAINT CK_PayComponents_NeedsFormula CHECK (CalculationMethod <> 'FORMULA' OR NULLIF(LTRIM(RTRIM(Formula)), N'') IS NOT NULL),
        CONSTRAINT CK_PayComponents_Amounts    CHECK ((DefaultAmount IS NULL OR DefaultAmount >= 0)
                                                  AND (MinAmount IS NULL OR MinAmount >= 0)
                                                  AND (MaxAmount IS NULL OR MaxAmount >= 0)
                                                  AND (MinAmount IS NULL OR MaxAmount IS NULL OR MaxAmount >= MinAmount)),
        CONSTRAINT CK_PayComponents_Percentage CHECK (DefaultPercentage IS NULL OR DefaultPercentage BETWEEN 0 AND 1000),
        /* The "included in ... base" flags only make sense for earnings. */
        CONSTRAINT CK_PayComponents_EarningFlags CHECK (ComponentType = 'EARNING'
                                                  OR (IsPifssApplicable = 0 AND IsIndemnityApplicable = 0
                                                      AND IsOvertimeApplicable = 0 AND IsLeaveSalaryApplicable = 0))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayComponents_Code' AND object_id = OBJECT_ID(N'[Payroll].[PayComponents]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayComponents_Code
        ON [Payroll].[PayComponents](CompanyId, ComponentCode) WHERE Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_PayComponents_SystemCode' AND object_id = OBJECT_ID(N'[Payroll].[PayComponents]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_PayComponents_SystemCode
        ON [Payroll].[PayComponents](CompanyId, SystemCode) WHERE SystemCode IS NOT NULL AND Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_PayComponents_Company' AND object_id = OBJECT_ID(N'[Payroll].[PayComponents]'))
    CREATE INDEX IX_PayComponents_Company
        ON [Payroll].[PayComponents](CompanyId, ComponentType, IsActive) INCLUDE (ComponentName, DisplayOrder) WHERE Deleted = 0;
GO

/* =====================================================================
   4. Payroll.SalaryStructures + SalaryStructureComponents
   ---------------------------------------------------------------------
   A structure (grade template) is matched to a new hire by
   Designation / Job Position / Grade (any of them may be blank = "any").
   Most specific match wins - see Payroll.usp_SalaryStructure_Manage RESOLVE.
   Lines may override the component's method / amount / percentage;
   NULL on a line = use the component's default.
===================================================================== */
IF OBJECT_ID(N'[Payroll].[SalaryStructures]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[SalaryStructures](
        SalaryStructureId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalaryStructures PRIMARY KEY,
        CompanyId           INT            NOT NULL,
        StructureCode       NVARCHAR(30)   NOT NULL,
        StructureName       NVARCHAR(150)  NOT NULL,
        ArabicName          NVARCHAR(150)  NULL,
        DesignationId       INT            NULL,
        PositionId          INT            NULL,
        GradeId             INT            NULL,
        PayrollCalendarId   INT            NULL,
        EffectiveFrom       DATE           NOT NULL,
        EffectiveTo         DATE           NULL,
        Description         NVARCHAR(500)  NULL,
        IsActive            BIT            NOT NULL CONSTRAINT DF_SalaryStructures_IsActive DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_SalaryStructures_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_SalaryStructures_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_SalaryStructures_Company     FOREIGN KEY (CompanyId)         REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_SalaryStructures_Designation FOREIGN KEY (DesignationId)     REFERENCES [Core].[Designations](DesignationId),
        CONSTRAINT FK_SalaryStructures_Position    FOREIGN KEY (PositionId)        REFERENCES [Core].[Positions](PositionId),
        CONSTRAINT FK_SalaryStructures_Grade       FOREIGN KEY (GradeId)           REFERENCES [Core].[Grades](GradeId),
        CONSTRAINT FK_SalaryStructures_Calendar    FOREIGN KEY (PayrollCalendarId) REFERENCES [Payroll].[PayrollCalendars](PayrollCalendarId),
        CONSTRAINT CK_SalaryStructures_Dates       CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_SalaryStructures_Code' AND object_id = OBJECT_ID(N'[Payroll].[SalaryStructures]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_SalaryStructures_Code
        ON [Payroll].[SalaryStructures](CompanyId, StructureCode) WHERE Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_SalaryStructures_Match' AND object_id = OBJECT_ID(N'[Payroll].[SalaryStructures]'))
    CREATE INDEX IX_SalaryStructures_Match
        ON [Payroll].[SalaryStructures](CompanyId, DesignationId, PositionId, GradeId, EffectiveFrom) WHERE Deleted = 0;
GO

IF OBJECT_ID(N'[Payroll].[SalaryStructureComponents]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[SalaryStructureComponents](
        SalaryStructureComponentId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_SalaryStructureComponents PRIMARY KEY,
        SalaryStructureId   INT            NOT NULL,
        PayComponentId      INT            NOT NULL,
        CalculationMethod   VARCHAR(12)    NULL,      -- NULL = component default
        CalculationBase     VARCHAR(15)    NULL,      -- NULL = component default
        Amount              DECIMAL(12,3)  NULL,
        Percentage          DECIMAL(7,4)   NULL,
        MinAmount           DECIMAL(12,3)  NULL,
        MaxAmount           DECIMAL(12,3)  NULL,
        IsMandatory         BIT            NOT NULL CONSTRAINT DF_SalaryStructureComponents_IsMandatory DEFAULT (1),
        AllowOverride       BIT            NOT NULL CONSTRAINT DF_SalaryStructureComponents_AllowOverride DEFAULT (1),
        DisplayOrder        SMALLINT       NOT NULL CONSTRAINT DF_SalaryStructureComponents_DisplayOrder DEFAULT (100),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_SalaryStructureComponents_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_SalaryStructureComponents_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_SalaryStructureComponents_Structure FOREIGN KEY (SalaryStructureId) REFERENCES [Payroll].[SalaryStructures](SalaryStructureId),
        CONSTRAINT FK_SalaryStructureComponents_Component FOREIGN KEY (PayComponentId)    REFERENCES [Payroll].[PayComponents](PayComponentId),
        CONSTRAINT CK_SalaryStructureComponents_Method    CHECK (CalculationMethod IS NULL OR CalculationMethod IN ('AMOUNT', 'PERCENTAGE', 'DAYS', 'HOURS', 'FORMULA', 'SYSTEM')),
        CONSTRAINT CK_SalaryStructureComponents_Base      CHECK (CalculationBase IS NULL OR CalculationBase IN ('BASIC', 'FIXED_GROSS', 'OVERTIME_BASE', 'INDEMNITY_BASE')),
        CONSTRAINT CK_SalaryStructureComponents_Amounts   CHECK ((Amount IS NULL OR Amount >= 0)
                                                           AND (MinAmount IS NULL OR MinAmount >= 0)
                                                           AND (MaxAmount IS NULL OR MaxAmount >= 0)
                                                           AND (MinAmount IS NULL OR MaxAmount IS NULL OR MaxAmount >= MinAmount)),
        CONSTRAINT CK_SalaryStructureComponents_Pct       CHECK (Percentage IS NULL OR Percentage BETWEEN 0 AND 1000)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_SalaryStructureComponents_Line' AND object_id = OBJECT_ID(N'[Payroll].[SalaryStructureComponents]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_SalaryStructureComponents_Line
        ON [Payroll].[SalaryStructureComponents](SalaryStructureId, PayComponentId) WHERE Deleted = 0;
GO

/* =====================================================================
   5. Kuwait statutory settings - all effective-dated, none hard-coded
   ---------------------------------------------------------------------
   IsVerified = 0 on a row means "seeded default, not yet confirmed by
   the client's finance team". The Phase 2 payroll engine should refuse
   to run with unverified statutory rows in force.
===================================================================== */

/* ---- 5a. PIFSS (social security) contribution rates ----------------
   ApplicableTo     KUWAITI / GCC / EXPAT / ALL  (matched against the
                    employee's nationality by the engine)
   CalculationBasis CAPPED = rate x MIN(MAX(salary, floor), ceiling)
                    BAND   = rate x the part of salary between floor
                             and ceiling (for tiered contributions)
   Rates are percentages (11.5 = 11.5 %).
--------------------------------------------------------------------- */
IF OBJECT_ID(N'[Payroll].[PifssContributionRates]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[PifssContributionRates](
        PifssRateId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PifssContributionRates PRIMARY KEY,
        ContributionCode    NVARCHAR(30)   NOT NULL,
        ContributionName    NVARCHAR(150)  NOT NULL,
        ApplicableTo        VARCHAR(10)    NOT NULL CONSTRAINT DF_PifssContributionRates_ApplicableTo DEFAULT ('KUWAITI'),
        CalculationBasis    VARCHAR(10)    NOT NULL CONSTRAINT DF_PifssContributionRates_Basis DEFAULT ('CAPPED'),
        EmployeeRate        DECIMAL(7,4)   NOT NULL CONSTRAINT DF_PifssContributionRates_EmployeeRate DEFAULT (0),
        EmployerRate        DECIMAL(7,4)   NOT NULL CONSTRAINT DF_PifssContributionRates_EmployerRate DEFAULT (0),
        GovernmentRate      DECIMAL(7,4)   NULL,
        SalaryFloor         DECIMAL(12,3)  NULL,
        SalaryCeiling       DECIMAL(12,3)  NULL,
        EffectiveFrom       DATE           NOT NULL,
        EffectiveTo         DATE           NULL,
        IsVerified          BIT            NOT NULL CONSTRAINT DF_PifssContributionRates_IsVerified DEFAULT (0),
        Notes               NVARCHAR(500)  NULL,
        IsActive            BIT            NOT NULL CONSTRAINT DF_PifssContributionRates_IsActive DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_PifssContributionRates_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_PifssContributionRates_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT CK_PifssContributionRates_ApplicableTo CHECK (ApplicableTo IN ('KUWAITI', 'GCC', 'EXPAT', 'ALL')),
        CONSTRAINT CK_PifssContributionRates_Basis        CHECK (CalculationBasis IN ('CAPPED', 'BAND')),
        CONSTRAINT CK_PifssContributionRates_Rates        CHECK (EmployeeRate BETWEEN 0 AND 100 AND EmployerRate BETWEEN 0 AND 100
                                                             AND (GovernmentRate IS NULL OR GovernmentRate BETWEEN 0 AND 100)),
        CONSTRAINT CK_PifssContributionRates_Range        CHECK ((SalaryFloor IS NULL OR SalaryFloor >= 0)
                                                             AND (SalaryCeiling IS NULL OR SalaryCeiling >= 0)
                                                             AND (SalaryFloor IS NULL OR SalaryCeiling IS NULL OR SalaryCeiling >= SalaryFloor)),
        CONSTRAINT CK_PifssContributionRates_Dates        CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
    CREATE INDEX IX_PifssContributionRates_Lookup
        ON [Payroll].[PifssContributionRates](ContributionCode, ApplicableTo, EffectiveFrom) WHERE Deleted = 0;
END
GO

/* ---- 5b. End-of-service indemnity rules -----------------------------
   Rule set (header)  : daily-wage divisor and the overall cap.
   Service slabs      : entitlement per year of service, by band
                        (EntitlementUnit DAYS = n days' wage per year,
                         MONTHS = n months' wage per year).
   Entitlement factors: % of the computed indemnity actually paid, by
                        separation type and length of service
                        (e.g. resignation with 3-5 years = 50 %).
--------------------------------------------------------------------- */
IF OBJECT_ID(N'[Payroll].[IndemnityRuleSets]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[IndemnityRuleSets](
        IndemnityRuleSetId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndemnityRuleSets PRIMARY KEY,
        RuleSetCode         NVARCHAR(30)   NOT NULL,
        RuleSetName         NVARCHAR(150)  NOT NULL,
        DailyWageDivisor    DECIMAL(5,2)   NOT NULL CONSTRAINT DF_IndemnityRuleSets_Divisor DEFAULT (26),
        MaxIndemnityMonths  DECIMAL(6,2)   NULL,
        MinServiceMonths    DECIMAL(6,2)   NULL,
        EffectiveFrom       DATE           NOT NULL,
        EffectiveTo         DATE           NULL,
        IsVerified          BIT            NOT NULL CONSTRAINT DF_IndemnityRuleSets_IsVerified DEFAULT (0),
        Notes               NVARCHAR(1000) NULL,
        IsActive            BIT            NOT NULL CONSTRAINT DF_IndemnityRuleSets_IsActive DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_IndemnityRuleSets_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_IndemnityRuleSets_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT CK_IndemnityRuleSets_Divisor CHECK (DailyWageDivisor > 0 AND DailyWageDivisor <= 31),
        CONSTRAINT CK_IndemnityRuleSets_Cap     CHECK (MaxIndemnityMonths IS NULL OR MaxIndemnityMonths > 0),
        CONSTRAINT CK_IndemnityRuleSets_Dates   CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_IndemnityRuleSets_Code' AND object_id = OBJECT_ID(N'[Payroll].[IndemnityRuleSets]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_IndemnityRuleSets_Code
        ON [Payroll].[IndemnityRuleSets](RuleSetCode) WHERE Deleted = 0;
GO

IF OBJECT_ID(N'[Payroll].[IndemnityServiceSlabs]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[IndemnityServiceSlabs](
        IndemnityServiceSlabId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndemnityServiceSlabs PRIMARY KEY,
        IndemnityRuleSetId  INT            NOT NULL,
        FromYears           DECIMAL(5,2)   NOT NULL,
        ToYears             DECIMAL(5,2)   NULL,          -- NULL = and above
        EntitlementUnit     VARCHAR(6)     NOT NULL,
        EntitlementValue    DECIMAL(7,3)   NOT NULL,
        DisplayOrder        SMALLINT       NOT NULL CONSTRAINT DF_IndemnityServiceSlabs_DisplayOrder DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_IndemnityServiceSlabs_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_IndemnityServiceSlabs_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_IndemnityServiceSlabs_RuleSet FOREIGN KEY (IndemnityRuleSetId) REFERENCES [Payroll].[IndemnityRuleSets](IndemnityRuleSetId),
        CONSTRAINT CK_IndemnityServiceSlabs_Unit    CHECK (EntitlementUnit IN ('DAYS', 'MONTHS')),
        CONSTRAINT CK_IndemnityServiceSlabs_Range   CHECK (FromYears >= 0 AND (ToYears IS NULL OR ToYears > FromYears)),
        CONSTRAINT CK_IndemnityServiceSlabs_Value   CHECK (EntitlementValue >= 0)
    );
    CREATE INDEX IX_IndemnityServiceSlabs_RuleSet
        ON [Payroll].[IndemnityServiceSlabs](IndemnityRuleSetId, FromYears) WHERE Deleted = 0;
END
GO

IF OBJECT_ID(N'[Payroll].[IndemnityEntitlementFactors]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[IndemnityEntitlementFactors](
        IndemnityEntitlementFactorId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_IndemnityEntitlementFactors PRIMARY KEY,
        IndemnityRuleSetId  INT            NOT NULL,
        SeparationType      VARCHAR(20)    NOT NULL,
        FromYears           DECIMAL(5,2)   NOT NULL,
        ToYears             DECIMAL(5,2)   NULL,          -- NULL = and above
        EntitlementPercent  DECIMAL(7,4)   NOT NULL,
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_IndemnityEntitlementFactors_CreatedDate DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_IndemnityEntitlementFactors_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_IndemnityEntitlementFactors_RuleSet FOREIGN KEY (IndemnityRuleSetId) REFERENCES [Payroll].[IndemnityRuleSets](IndemnityRuleSetId),
        CONSTRAINT CK_IndemnityEntitlementFactors_Type    CHECK (SeparationType IN ('RESIGNATION', 'TERMINATION', 'CONTRACT_END', 'RETIREMENT', 'DEATH', 'DISABILITY', 'OTHER')),
        CONSTRAINT CK_IndemnityEntitlementFactors_Range   CHECK (FromYears >= 0 AND (ToYears IS NULL OR ToYears > FromYears)),
        CONSTRAINT CK_IndemnityEntitlementFactors_Pct     CHECK (EntitlementPercent BETWEEN 0 AND 100)
    );
    CREATE INDEX IX_IndemnityEntitlementFactors_RuleSet
        ON [Payroll].[IndemnityEntitlementFactors](IndemnityRuleSetId, SeparationType, FromYears) WHERE Deleted = 0;
END
GO

/* ---- 5c. Overtime multipliers --------------------------------------
   CompanyId NULL = statutory default for every company.
   CompanyId set  = that company's own (more generous) policy, which
                    takes precedence over the default for that company.
   Hourly rate = OVERTIME_BASE / HourlyRateDivisorDays / HoursPerDay.
--------------------------------------------------------------------- */
IF OBJECT_ID(N'[Payroll].[OvertimeRates]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[OvertimeRates](
        OvertimeRateId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OvertimeRates PRIMARY KEY,
        CompanyId             INT            NULL,
        OvertimeCode          VARCHAR(20)    NOT NULL,
        OvertimeName          NVARCHAR(150)  NOT NULL,
        Multiplier            DECIMAL(5,3)   NOT NULL,
        HourlyRateDivisorDays DECIMAL(5,2)   NOT NULL CONSTRAINT DF_OvertimeRates_Divisor DEFAULT (26),
        HoursPerDay           DECIMAL(4,2)   NOT NULL CONSTRAINT DF_OvertimeRates_HoursPerDay DEFAULT (8),
        MaxHoursPerDay        DECIMAL(4,2)   NULL,
        MaxHoursPerYear       INT            NULL,
        EffectiveFrom         DATE           NOT NULL,
        EffectiveTo           DATE           NULL,
        IsVerified            BIT            NOT NULL CONSTRAINT DF_OvertimeRates_IsVerified DEFAULT (0),
        Notes                 NVARCHAR(500)  NULL,
        IsActive              BIT            NOT NULL CONSTRAINT DF_OvertimeRates_IsActive DEFAULT (1),
        CreatedBy             BIGINT         NULL,
        CreatedDate           DATETIME2(0)   NOT NULL CONSTRAINT DF_OvertimeRates_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy            BIGINT         NULL,
        ModifiedDate          DATETIME2(0)   NULL,
        Deleted               BIT            NOT NULL CONSTRAINT DF_Payroll_OvertimeRates_Deleted DEFAULT (0),
        DeletedBy             BIGINT         NULL,
        DeletedDate           DATETIME2(7)   NULL,

        CONSTRAINT FK_OvertimeRates_Company  FOREIGN KEY (CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_OvertimeRates_Code     CHECK (OvertimeCode IN ('NORMAL_DAY', 'REST_DAY', 'PUBLIC_HOLIDAY', 'NIGHT', 'OTHER')),
        CONSTRAINT CK_OvertimeRates_Mult     CHECK (Multiplier > 0 AND Multiplier <= 10),
        CONSTRAINT CK_OvertimeRates_Divisor  CHECK (HourlyRateDivisorDays > 0 AND HourlyRateDivisorDays <= 31),
        CONSTRAINT CK_OvertimeRates_Hours    CHECK (HoursPerDay > 0 AND HoursPerDay <= 24 AND (MaxHoursPerDay IS NULL OR MaxHoursPerDay BETWEEN 0 AND 24)),
        CONSTRAINT CK_OvertimeRates_Dates    CHECK (EffectiveTo IS NULL OR EffectiveTo >= EffectiveFrom)
    );
    CREATE INDEX IX_OvertimeRates_Lookup
        ON [Payroll].[OvertimeRates](OvertimeCode, CompanyId, EffectiveFrom) WHERE Deleted = 0;
END
GO

/* =====================================================================
   6. Banks + the company's own debit accounts
   ---------------------------------------------------------------------
   Payroll.Banks is shared by all companies (a bank is a bank).
   WpsBankCode    : code the bank / PAM expects in the WPS salary file.
   IbanBankCode   : the 4-letter bank identifier inside a Kuwait IBAN
                    (KWkk BBBB ...), used to auto-detect an employee's
                    bank from the IBAN in Phase 2.
   CompanyBankAccounts.WpsEmployerCode / PamFileNo identify the company
   on the WPS salary file it submits.
===================================================================== */
IF OBJECT_ID(N'[Payroll].[Banks]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[Banks](
        BankId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Banks PRIMARY KEY,
        BankCode        NVARCHAR(20)   NOT NULL,
        BankName        NVARCHAR(150)  NOT NULL,
        ArabicName      NVARCHAR(150)  NULL,
        ShortName       NVARCHAR(30)   NULL,
        SwiftCode       NVARCHAR(11)   NULL,
        IbanBankCode    NVARCHAR(10)   NULL,
        WpsBankCode     NVARCHAR(20)   NULL,
        CountryId       INT            NULL,
        IsActive        BIT            NOT NULL CONSTRAINT DF_Banks_IsActive DEFAULT (1),
        CreatedBy       BIGINT         NULL,
        CreatedDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_Banks_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy      BIGINT         NULL,
        ModifiedDate    DATETIME2(0)   NULL,
        Deleted         BIT            NOT NULL CONSTRAINT DF_Payroll_Banks_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(7)   NULL,

        CONSTRAINT FK_Banks_Country FOREIGN KEY (CountryId) REFERENCES [Core].[Countries](CountryId),
        CONSTRAINT CK_Banks_Swift   CHECK (SwiftCode IS NULL OR LEN(SwiftCode) IN (8, 11))
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_Banks_Code' AND object_id = OBJECT_ID(N'[Payroll].[Banks]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_Banks_Code ON [Payroll].[Banks](BankCode) WHERE Deleted = 0;
GO

IF OBJECT_ID(N'[Payroll].[CompanyBankAccounts]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[CompanyBankAccounts](
        CompanyBankAccountId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CompanyBankAccounts PRIMARY KEY,
        CompanyId           INT            NOT NULL,
        BankId              INT            NOT NULL,
        AccountCode         NVARCHAR(30)   NOT NULL,
        AccountTitle        NVARCHAR(150)  NOT NULL,
        AccountNumber       NVARCHAR(34)   NULL,
        Iban                NVARCHAR(34)   NULL,
        CurrencyId          INT            NULL,
        BranchName          NVARCHAR(150)  NULL,
        WpsEmployerCode     NVARCHAR(50)   NULL,
        PamFileNo           NVARCHAR(50)   NULL,
        IsDefault           BIT            NOT NULL CONSTRAINT DF_CompanyBankAccounts_IsDefault DEFAULT (0),
        IsActive            BIT            NOT NULL CONSTRAINT DF_CompanyBankAccounts_IsActive DEFAULT (1),
        CreatedBy           BIGINT         NULL,
        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_CompanyBankAccounts_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_CompanyBankAccounts_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_CompanyBankAccounts_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_CompanyBankAccounts_Bank     FOREIGN KEY (BankId)     REFERENCES [Payroll].[Banks](BankId),
        CONSTRAINT FK_CompanyBankAccounts_Currency FOREIGN KEY (CurrencyId) REFERENCES [Core].[Currencies](CurrencyId),
        CONSTRAINT CK_CompanyBankAccounts_Number   CHECK (AccountNumber IS NOT NULL OR Iban IS NOT NULL)
    );
END
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CompanyBankAccounts_Code' AND object_id = OBJECT_ID(N'[Payroll].[CompanyBankAccounts]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_CompanyBankAccounts_Code
        ON [Payroll].[CompanyBankAccounts](CompanyId, AccountCode) WHERE Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CompanyBankAccounts_Iban' AND object_id = OBJECT_ID(N'[Payroll].[CompanyBankAccounts]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_CompanyBankAccounts_Iban
        ON [Payroll].[CompanyBankAccounts](Iban) WHERE Iban IS NOT NULL AND Deleted = 0;
GO
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'UX_CompanyBankAccounts_Default' AND object_id = OBJECT_ID(N'[Payroll].[CompanyBankAccounts]'))
    CREATE UNIQUE NONCLUSTERED INDEX UX_CompanyBankAccounts_Default
        ON [Payroll].[CompanyBankAccounts](CompanyId) WHERE IsDefault = 1 AND Deleted = 0;
GO

/* =====================================================================
   7. Make sure every new table is under the soft-delete rule
      (INSTEAD OF DELETE guard trigger). Normally the database trigger
      from script 28 already did this on CREATE TABLE; this is a no-op
      re-check in case it was disabled when these tables were created.
===================================================================== */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll';
GO

SET NOEXEC OFF;
GO
PRINT N'29_Payroll_Master_Tables.sql applied.';
GO
