/* =====================================================================
   32_Payroll_Seed_Data.sql  -  HRMS Kuwait: Payroll Phase 1 starting data
   ---------------------------------------------------------------------
   Run AFTER 31_Lookup_Payroll.sql. Safe to re-run: every insert skips
   rows that already exist, and nothing you edited is overwritten.

     1. Permissions  PAYROLL_SETUP_VIEW / CREATE / EDIT / DELETE and
                     PAYROLL_PERIOD_APPROVE (period status changes),
                     granted to the SYSADMIN role.
     2. Pay components - the minimum earning / deduction set, for EVERY
                     existing company (a company added later gets them via
                     usp_PayComponent_Manage @Action = 'SEED', or the
                     "Load standard components" button).
     3. Banks        - the Kuwaiti local banks (WPS codes left blank -
                     fill them in from your bank's WPS file specification).
     4. Statutory defaults - PIFSS rates, end-of-service rules, overtime
                     multipliers. ALL are seeded with IsVerified = 0.

   >>> IMPORTANT - statutory values <<<
   The PIFSS, indemnity and overtime values below are reasonable
   published starting points, NOT legal advice. PIFSS rates and ceilings
   change by decree. Have the client's finance / legal team confirm every
   row, then tick "Verified" on the screen. The Phase 2 payroll engine
   will refuse to run while an unverified statutory row is in force.
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

/* =====================================================================
   1. Permissions
===================================================================== */
INSERT INTO [Security].[Permissions](PermissionCode, Module, Action)
SELECT v.PermissionCode, v.Module, v.Action
FROM (VALUES
    ('PAYROLL_SETUP_VIEW',     'PayrollSetup', 'View'),
    ('PAYROLL_SETUP_CREATE',   'PayrollSetup', 'Create'),
    ('PAYROLL_SETUP_EDIT',     'PayrollSetup', 'Edit'),
    ('PAYROLL_SETUP_DELETE',   'PayrollSetup', 'Delete'),
    ('PAYROLL_PERIOD_APPROVE', 'PayrollSetup', 'Approve')
) v(PermissionCode, Module, Action)
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = v.PermissionCode);
GO

DECLARE @SysAdminRoleId INT =
    (SELECT TOP 1 RoleId FROM [Security].[Roles] WHERE RoleCode = N'SYSADMIN' AND CompanyId IS NULL);

IF @SysAdminRoleId IS NOT NULL
    INSERT INTO [Security].[RolePermissions](RoleId, PermissionId)
    SELECT @SysAdminRoleId, p.PermissionId
    FROM   [Security].[Permissions] AS p
    WHERE  p.PermissionCode LIKE 'PAYROLL[_]%'
      AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp
                       WHERE rp.RoleId = @SysAdminRoleId AND rp.PermissionId = p.PermissionId);
GO

/* =====================================================================
   2. Minimum pay components for every existing company
===================================================================== */
DECLARE @cid INT, @n INT, @total INT = 0;
DECLARE comp_cur CURSOR LOCAL FAST_FORWARD FOR
    SELECT CompanyId FROM [Core].[Companies] WHERE Deleted = 0 ORDER BY CompanyId;
OPEN comp_cur;
FETCH NEXT FROM comp_cur INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @cid, @UserId = NULL, @Inserted = @n OUTPUT;
    SET @total += ISNULL(@n, 0);
    FETCH NEXT FROM comp_cur INTO @cid;
END;
CLOSE comp_cur; DEALLOCATE comp_cur;
PRINT CONCAT(N'Pay components seeded: ', @total, N' row(s).');
GO

/* =====================================================================
   3. Kuwaiti local banks
   SWIFT codes are the banks' published head-office BICs; IbanBankCode is
   the 4 letters that appear in positions 5-8 of a Kuwait IBAN.
   WpsBankCode is intentionally NULL - take it from each bank's WPS
   salary-file specification.
===================================================================== */
DECLARE @KW INT = (SELECT TOP 1 CountryId FROM [Core].[Countries] WHERE CountryCode = 'KW');

INSERT INTO [Payroll].[Banks] (BankCode, BankName, ArabicName, ShortName, SwiftCode, IbanBankCode, WpsBankCode, CountryId, IsActive)
SELECT v.BankCode, v.BankName, v.ArabicName, v.ShortName, v.SwiftCode, LEFT(v.SwiftCode, 4), NULL, @KW, 1
FROM (VALUES
    (N'NBK',     N'National Bank of Kuwait',       N'بنك الكويت الوطني',       N'NBK',     N'NBOKKWKW'),
    (N'GBK',     N'Gulf Bank',                     N'بنك الخليج',              N'Gulf Bank', N'GULBKWKW'),
    (N'CBK',     N'Commercial Bank of Kuwait',     N'البنك التجاري الكويتي',   N'CBK',     N'COMBKWKW'),
    (N'ABK',     N'Al Ahli Bank of Kuwait',        N'البنك الأهلي الكويتي',    N'ABK',     N'ABKKKWKW'),
    (N'BURGAN',  N'Burgan Bank',                   N'بنك برقان',               N'Burgan',  N'BRGNKWKW'),
    (N'KFH',     N'Kuwait Finance House',          N'بيت التمويل الكويتي',     N'KFH',     N'KFHOKWKW'),
    (N'BOUBYAN', N'Boubyan Bank',                  N'بنك بوبيان',              N'Boubyan', N'BBYNKWKW'),
    (N'WARBA',   N'Warba Bank',                    N'بنك وربة',                N'Warba',   N'WRBAKWKW'),
    (N'KIB',     N'Kuwait International Bank',     N'بنك الكويت الدولي',       N'KIB',     N'KWIBKWKW')
) v(BankCode, BankName, ArabicName, ShortName, SwiftCode)
WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[Banks] b WHERE b.Deleted = 0 AND b.BankCode = v.BankCode);

PRINT CONCAT(N'Banks seeded: ', @@ROWCOUNT, N' row(s).');
GO

/* =====================================================================
   4a. PIFSS contribution rates (Kuwaiti nationals)
   Source used for the seed: PwC Worldwide Tax Summaries - Kuwait,
   Individual, Other taxes (employee 8 % up to KWD 2,750 plus 2.5 % up to
   KWD 1,500 since 1 Jan 2015; employer 11.5 % up to KWD 2,750).
   Expatriates have no PIFSS contribution; GCC nationals contribute under
   their home country's scheme - add rows for them if you employ any.
===================================================================== */
INSERT INTO [Payroll].[PifssContributionRates]
    (ContributionCode, ContributionName, ApplicableTo, CalculationBasis, EmployeeRate, EmployerRate, GovernmentRate,
     SalaryFloor, SalaryCeiling, EffectiveFrom, EffectiveTo, IsVerified, Notes, IsActive)
SELECT v.Code, v.Name, 'KUWAITI', 'CAPPED', v.EE, v.ER, NULL, NULL, v.Ceiling, '2015-01-01', NULL, 0,
       N'Seeded starting value - confirm the current rate and ceiling with PIFSS before go-live, then mark Verified.', 1
FROM (VALUES
    (N'PIFSS_MAIN', N'Social security - main contribution',       CAST(8.0000 AS DECIMAL(7,4)), CAST(11.5000 AS DECIMAL(7,4)), CAST(2750.000 AS DECIMAL(12,3))),
    (N'PIFSS_ADDL', N'Social security - additional contribution', CAST(2.5000 AS DECIMAL(7,4)), CAST( 0.0000 AS DECIMAL(7,4)), CAST(1500.000 AS DECIMAL(12,3)))
) v(Code, Name, EE, ER, Ceiling)
WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[PifssContributionRates] r
                  WHERE r.Deleted = 0 AND r.ContributionCode = v.Code AND r.ApplicableTo = 'KUWAITI');
GO

/* =====================================================================
   4b. End-of-service indemnity - Kuwait Private Sector Labour Law
       No. 6 of 2010, monthly-paid workers
     Art. 51: 15 days' remuneration for each of the first 5 years,
              one month's remuneration for each year after that,
              capped at 1.5 years' (18 months') remuneration.
     Art. 53: on resignation - nothing below 3 years, half for 3-5 years,
              two-thirds for 5-10 years, full from 10 years.
     Daily wage = monthly remuneration / 26.
   Special cases (e.g. a female worker resigning within a year of
   marriage) are not modelled - handle them as a manual override.
===================================================================== */
IF NOT EXISTS (SELECT 1 FROM [Payroll].[IndemnityRuleSets] WHERE Deleted = 0 AND RuleSetCode = N'KW-LL-6-2010')
BEGIN
    DECLARE @rs INT;

    INSERT INTO [Payroll].[IndemnityRuleSets]
        (RuleSetCode, RuleSetName, DailyWageDivisor, MaxIndemnityMonths, MinServiceMonths, EffectiveFrom, EffectiveTo, IsVerified, Notes, IsActive)
    VALUES
        (N'KW-LL-6-2010', N'Kuwait Labour Law 6/2010 - monthly-paid workers', 26, 18, NULL, '2010-02-21', NULL, 0,
         N'Seeded from Law 6/2010 Arts. 51 and 53. Confirm with the client''s legal team (and any later amendments) before go-live, then mark Verified.', 1);

    SET @rs = SCOPE_IDENTITY();

    INSERT INTO [Payroll].[IndemnityServiceSlabs] (IndemnityRuleSetId, FromYears, ToYears, EntitlementUnit, EntitlementValue, DisplayOrder)
    VALUES (@rs, 0, 5,    'DAYS',   15, 1),
           (@rs, 5, NULL, 'MONTHS',  1, 2);

    INSERT INTO [Payroll].[IndemnityEntitlementFactors] (IndemnityRuleSetId, SeparationType, FromYears, ToYears, EntitlementPercent)
    VALUES (@rs, 'RESIGNATION',  0,  3,      0),
           (@rs, 'RESIGNATION',  3,  5,     50),
           (@rs, 'RESIGNATION',  5, 10,     66.6667),
           (@rs, 'RESIGNATION', 10, NULL,  100),
           (@rs, 'TERMINATION',  0, NULL,  100),
           (@rs, 'CONTRACT_END', 0, NULL,  100),
           (@rs, 'RETIREMENT',   0, NULL,  100),
           (@rs, 'DEATH',        0, NULL,  100),
           (@rs, 'DISABILITY',   0, NULL,  100);

    PRINT N'Indemnity rule set KW-LL-6-2010 seeded.';
END;
GO

/* =====================================================================
   4c. Overtime multipliers - statutory defaults (CompanyId NULL)
     Law 6/2010 Arts. 66-68: +25 % on a normal day, +50 % on the weekly
     rest day, +100 % on a public holiday; overtime limited to 2 hours a
     day and 180 hours a year. Hourly rate = OT base / 26 / 8.
   Add a row with a CompanyId for a company whose own policy pays more.
===================================================================== */
INSERT INTO [Payroll].[OvertimeRates]
    (CompanyId, OvertimeCode, OvertimeName, Multiplier, HourlyRateDivisorDays, HoursPerDay, MaxHoursPerDay, MaxHoursPerYear,
     EffectiveFrom, EffectiveTo, IsVerified, Notes, IsActive)
SELECT NULL, v.Code, v.Name, v.Mult, 26, 8, 2, 180, '2010-02-21', NULL, 0,
       N'Seeded statutory default - confirm before go-live, then mark Verified.', 1
FROM (VALUES
    ('NORMAL_DAY',     N'Overtime - normal working day', CAST(1.250 AS DECIMAL(5,3))),
    ('REST_DAY',       N'Overtime - weekly rest day',    CAST(1.500 AS DECIMAL(5,3))),
    ('PUBLIC_HOLIDAY', N'Overtime - public holiday',     CAST(2.000 AS DECIMAL(5,3)))
) v(Code, Name, Mult)
WHERE NOT EXISTS (SELECT 1 FROM [Payroll].[OvertimeRates] r
                  WHERE r.Deleted = 0 AND r.CompanyId IS NULL AND r.OvertimeCode = v.Code);
GO

PRINT N'32_Payroll_Seed_Data.sql applied.';
GO
