/* =====================================================================
   82_Employee_Profile_Additions.sql  -  HRMS: work permit details, annual
   leave per employee, and per-tab rights on the Employee Profile
   ---------------------------------------------------------------------
   Run after 81. Safe to re-run. Re-run it after db/20 or db/69 if those
   are ever run again (it replaces the procedure / function below).

     1. Kuwait.EmployeeCompliance  + WorkPermitSalary, WorkPermitDesignation,
        WorkPermitDesignationAr (Kuwait Compliance > Ministry of Labour &
        Work Permit) and Kuwait.usp_EmployeeCompliance_Manage reading /
        saving them (db/20 + these three).
     2. Employee.Employees.AnnualLeaveDays (Employment > Employment Terms):
        the employee's own annual leave days per year (an individual
        agreement). Blank = the Annual Leave type's days per year (Leave >
        Settings). Employee.usp_EmployeeLeaveTerms_Manage GET / SET.
     3. Leave.tvf_Balances (db/69): annual leave is earned at the employee's
        own days per year when set.
     4. Rights per profile tab (Security > Create Roles > Employees):
          EMPLOYEE_PERSONAL_VIEW     Personal Info: see    (edit = EMPLOYEE_EDIT)
          EMPLOYEE_EMPLOYMENT_VIEW   Employment: see
          EMPLOYEE_EMPLOYMENT_EDIT   Employment: edit
          EMPLOYEE_LEAVE_VIEW        Leave tab: see
        Kuwait Compliance, Dependents and Documents keep their rights. A tab
        a role has no right to is hidden. So that nobody loses a tab today,
        the first run gives the new rights to the roles that already had
        the matching ones (view -> see, edit -> edit).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

/* ---- 1. work permit details ------------------------------------------- */
IF COL_LENGTH('Kuwait.EmployeeCompliance', 'WorkPermitSalary') IS NULL
    ALTER TABLE [Kuwait].[EmployeeCompliance] ADD [WorkPermitSalary] DECIMAL(12, 3) NULL;
IF COL_LENGTH('Kuwait.EmployeeCompliance', 'WorkPermitDesignation') IS NULL
    ALTER TABLE [Kuwait].[EmployeeCompliance] ADD [WorkPermitDesignation] NVARCHAR(150) NULL;
IF COL_LENGTH('Kuwait.EmployeeCompliance', 'WorkPermitDesignationAr') IS NULL
    ALTER TABLE [Kuwait].[EmployeeCompliance] ADD [WorkPermitDesignationAr] NVARCHAR(150) NULL;
GO

CREATE OR ALTER PROCEDURE [Kuwait].[usp_EmployeeCompliance_Manage]
    @Action                     VARCHAR(10),
    @EmployeeId                 BIGINT          = NULL,

    @CivilIdNumber               NVARCHAR(20)   = NULL,
    @CivilIdExpiryDate           DATE           = NULL,

    @PassportNumber              NVARCHAR(30)   = NULL,
    @PassportCountryId           INT            = NULL,
    @PassportExpiryDate          DATE           = NULL,

    @ResidencyNumber             NVARCHAR(30)   = NULL,
    @ResidencyType                NVARCHAR(50)  = NULL,
    @ResidencyExpiryDate          DATE          = NULL,

    @SponsorName                  NVARCHAR(200) = NULL,
    @SponsorFileNumber            NVARCHAR(50)  = NULL,
    @SponsorStatus                NVARCHAR(50)  = NULL,   -- db/20
    @ResidencyStatus              NVARCHAR(30)  = NULL,   -- db/20

    @MolFileNumber                NVARCHAR(50)  = NULL,
    @WorkPermitNumber             NVARCHAR(50)  = NULL,
    @WorkPermitExpiryDate         DATE          = NULL,
    @WorkPermitSalary             DECIMAL(12,3) = NULL,   -- db/82
    @WorkPermitDesignation        NVARCHAR(150) = NULL,   -- db/82
    @WorkPermitDesignationAr      NVARCHAR(150) = NULL,   -- db/82

    @PaciNumber                   NVARCHAR(20)  = NULL,
    @PaciAddress                  NVARCHAR(300) = NULL,

    @DrivingLicenseNumber         NVARCHAR(30)  = NULL,
    @DrivingLicenseExpiryDate     DATE          = NULL,
    @BloodType                    NVARCHAR(5)   = NULL,
    @HealthCertificateExpiry      DATE          = NULL,

    @UserId                       BIGINT        = NULL,

    @ResultCode                   VARCHAR(40)   = NULL OUTPUT,
    @ResultMessage                NVARCHAR(400) = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'';

    IF @Action NOT IN ('GET', 'UPSERT')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    IF @EmployeeId IS NULL
    BEGIN
        SELECT @ResultCode    = 'INVALID_REQUEST',
               @ResultMessage = N'An employee must be specified.';
        RETURN;
    END;

    /* ======================= GET =================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  ec.EmployeeId,
                ec.CivilIdNumber,
                ec.CivilIdExpiryDate,
                ec.PassportNumber,
                ec.PassportCountryId,
                pc.CountryName                AS PassportCountryName,
                ec.PassportExpiryDate,
                ec.ResidencyNumber,
                ec.ResidencyType,
                ec.ResidencyExpiryDate,
                ec.SponsorName,
                ec.SponsorFileNumber,
                ec.SponsorStatus,
                ec.ResidencyStatus,
                ec.MolFileNumber,
                ec.WorkPermitNumber,
                ec.WorkPermitExpiryDate,
                ec.WorkPermitSalary,
                ec.WorkPermitDesignation,
                ec.WorkPermitDesignationAr,
                ec.PaciNumber,
                ec.PaciAddress,
                ec.DrivingLicenseNumber,
                ec.DrivingLicenseExpiryDate,
                ec.BloodType,
                ec.HealthCertificateExpiry
        FROM        [Kuwait].[EmployeeCompliance] AS ec
        LEFT JOIN   [Core].[Countries]            AS pc ON pc.CountryId = ec.PassportCountryId
        WHERE       ec.EmployeeId = @EmployeeId;

        RETURN;
    END;

    /* ======================= UPSERT ================================= */
    IF @Action = 'UPSERT'
    BEGIN
        IF @WorkPermitSalary < 0
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The work permit salary cannot be negative.';
            RETURN;
        END;

        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] WHERE EmployeeId = @EmployeeId)
        BEGIN
            UPDATE [Kuwait].[EmployeeCompliance]
               SET CivilIdNumber            = @CivilIdNumber,
                   CivilIdExpiryDate        = @CivilIdExpiryDate,
                   PassportNumber           = @PassportNumber,
                   PassportCountryId        = @PassportCountryId,
                   PassportExpiryDate       = @PassportExpiryDate,
                   ResidencyNumber          = @ResidencyNumber,
                   ResidencyType            = @ResidencyType,
                   ResidencyExpiryDate      = @ResidencyExpiryDate,
                   SponsorName              = @SponsorName,
                   SponsorFileNumber        = @SponsorFileNumber,
                   SponsorStatus            = @SponsorStatus,
                   ResidencyStatus          = @ResidencyStatus,
                   MolFileNumber            = @MolFileNumber,
                   WorkPermitNumber         = @WorkPermitNumber,
                   WorkPermitExpiryDate     = @WorkPermitExpiryDate,
                   WorkPermitSalary         = @WorkPermitSalary,
                   WorkPermitDesignation    = @WorkPermitDesignation,
                   WorkPermitDesignationAr  = @WorkPermitDesignationAr,
                   PaciNumber               = @PaciNumber,
                   PaciAddress              = @PaciAddress,
                   DrivingLicenseNumber     = @DrivingLicenseNumber,
                   DrivingLicenseExpiryDate = @DrivingLicenseExpiryDate,
                   BloodType                = @BloodType,
                   HealthCertificateExpiry  = @HealthCertificateExpiry,
                   ModifiedBy               = @UserId,
                   ModifiedDate             = SYSUTCDATETIME()
             WHERE EmployeeId = @EmployeeId;
        END
        ELSE
        BEGIN
            INSERT INTO [Kuwait].[EmployeeCompliance]
                (EmployeeId, CivilIdNumber, CivilIdExpiryDate, PassportNumber, PassportCountryId,
                 PassportExpiryDate, ResidencyNumber, ResidencyType, ResidencyExpiryDate,
                 SponsorName, SponsorFileNumber, SponsorStatus, ResidencyStatus, MolFileNumber, WorkPermitNumber, WorkPermitExpiryDate,
                 WorkPermitSalary, WorkPermitDesignation, WorkPermitDesignationAr,
                 PaciNumber, PaciAddress, DrivingLicenseNumber, DrivingLicenseExpiryDate,
                 BloodType, HealthCertificateExpiry, CreatedBy)
            VALUES
                (@EmployeeId, @CivilIdNumber, @CivilIdExpiryDate, @PassportNumber, @PassportCountryId,
                 @PassportExpiryDate, @ResidencyNumber, @ResidencyType, @ResidencyExpiryDate,
                 @SponsorName, @SponsorFileNumber, @SponsorStatus, @ResidencyStatus, @MolFileNumber, @WorkPermitNumber, @WorkPermitExpiryDate,
                 @WorkPermitSalary, @WorkPermitDesignation, @WorkPermitDesignationAr,
                 @PaciNumber, @PaciAddress, @DrivingLicenseNumber, @DrivingLicenseExpiryDate,
                 @BloodType, @HealthCertificateExpiry, @UserId);
        END;

        SET @ResultMessage = N'Kuwait compliance details saved.';
        RETURN;
    END;
END;
GO

/* ---- 2. annual leave per employee ------------------------------------- */
IF COL_LENGTH('Employee.Employees', 'AnnualLeaveDays') IS NULL
    ALTER TABLE [Employee].[Employees] ADD [AnnualLeaveDays] DECIMAL(6, 2) NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_Employees_AnnualLeaveDays')
    ALTER TABLE [Employee].[Employees] WITH CHECK
        ADD CONSTRAINT [CK_Employees_AnnualLeaveDays] CHECK ([AnnualLeaveDays] IS NULL OR [AnnualLeaveDays] BETWEEN 0 AND 366);
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeLeaveTerms_Manage]
    @Action             VARCHAR(10),
    @Id                 BIGINT          = NULL,      -- EmployeeId
    @AnnualLeaveDays    DECIMAL(6, 2)   = NULL,      -- SET: NULL = the Annual Leave type's days
    @UserId             BIGINT          = NULL,
    @TotalCount         INT             = NULL OUTPUT,
    @NewId              BIGINT          = NULL OUTPUT,
    @ResultCode         VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage      NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @TotalCount = 0, @NewId = ISNULL(@Id, 0);

    IF @Action = 'GET'
    BEGIN
        /* the employee's own days, and the days of the company's Annual Leave type */
        SELECT  e.EmployeeId, e.AnnualLeaveDays,
                (SELECT TOP (1) t.DaysPerYear FROM [Leave].[LeaveTypes] AS t
                 WHERE t.CompanyId = e.CompanyId AND t.Category = 'ANNUAL' AND t.IsActive = 1 AND t.Deleted = 0
                 ORDER BY t.SortOrder, t.LeaveTypeId) AS DefaultAnnualLeaveDays
        FROM    [Employee].[Employees] AS e
        WHERE   e.EmployeeId = @Id AND e.Deleted = 0;
        RETURN;
    END;

    IF @Action = 'SET'
    BEGIN
        IF @AnnualLeaveDays IS NOT NULL AND @AnnualLeaveDays NOT BETWEEN 0 AND 366
        BEGIN
            SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Annual leave must be between 0 and 366 days a year.';
            RETURN;
        END;
        UPDATE [Employee].[Employees]
           SET AnnualLeaveDays = @AnnualLeaveDays, ModifiedBy = @UserId, ModifiedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @Id AND Deleted = 0
           AND ISNULL(AnnualLeaveDays, -1) <> ISNULL(@AnnualLeaveDays, -1);
        RETURN;
    END;

    SELECT @ResultCode = 'INVALID_ACTION', @ResultMessage = N'Unsupported action.';
END;
GO

/* ---- 3. leave balances: the employee's own annual leave --------------- */
IF OBJECT_ID(N'[Leave].[LeaveTypes]', N'U') IS NOT NULL
    EXEC (N'
CREATE OR ALTER FUNCTION [Leave].[tvf_Balances]
(
    @AsOf        DATE,
    @EmployeeId  BIGINT        -- NULL = every employee
)
RETURNS TABLE
AS
RETURN
WITH et AS (
    SELECT  e.EmployeeId, e.CompanyId, e.HireDate,
            t.LeaveTypeId, t.BalanceMode,
            /* db/82: the employee''s own annual leave (Employment Terms) replaces the
               type''s days per year for annual leave; blank = the type''s */
            CASE WHEN t.Category = ''ANNUAL'' AND e.AnnualLeaveDays IS NOT NULL THEN e.AnnualLeaveDays
                 ELSE t.DaysPerYear END AS DaysPerYear,
            t.AccrualMethod,
            op.OpeningDate, ISNULL(op.OpeningDays, 0) AS OpeningDays,
            CASE t.BalanceMode
                 WHEN ''ACCRUE'' THEN COALESCE(op.OpeningDate, e.HireDate, DATEFROMPARTS(YEAR(@AsOf), 1, 1))
                 WHEN ''YEARLY'' THEN DATEFROMPARTS(YEAR(@AsOf), 1, 1)
                 ELSE CAST(''19000101'' AS DATE) END AS WinStart,
            CASE WHEN t.BalanceMode = ''YEARLY'' THEN DATEFROMPARTS(YEAR(@AsOf), 12, 31)
                 ELSE CAST(''99991231'' AS DATE) END AS WinEnd
    FROM    [Employee].[Employees] AS e
    JOIN    [Leave].[LeaveTypes] AS t
            ON t.CompanyId = e.CompanyId AND t.Deleted = 0 AND t.IsActive = 1
           AND (t.Gender IS NULL OR t.Gender = e.Gender)
    OUTER APPLY (SELECT TOP (1) l.EntryDate AS OpeningDate, l.Days AS OpeningDays
                 FROM   [Leave].[LeaveLedger] AS l
                 WHERE  l.EmployeeId = e.EmployeeId AND l.LeaveTypeId = t.LeaveTypeId AND l.EntryType = ''OPENING''
                   AND  l.Deleted = 0 AND l.EntryDate <= @AsOf
                 ORDER BY l.EntryDate DESC, l.EntryId DESC) AS op
    WHERE   e.Deleted = 0 AND (@EmployeeId IS NULL OR e.EmployeeId = @EmployeeId)
),
calc AS (
    SELECT  et.*,
            CAST(CASE et.BalanceMode
                 WHEN ''ACCRUE'' THEN
                      CASE WHEN et.WinStart > @AsOf THEN 0
                           WHEN et.AccrualMethod = ''UPFRONT''
                                THEN ISNULL(et.DaysPerYear, 0) * ((YEAR(@AsOf) - YEAR(et.WinStart)) + (13 - MONTH(et.WinStart)) / 12.0)
                           ELSE ISNULL(et.DaysPerYear, 0) / 12.0
                                * (DATEDIFF(MONTH, et.WinStart, @AsOf) - CASE WHEN DAY(@AsOf) < DAY(et.WinStart) THEN 1 ELSE 0 END)
                      END
                 WHEN ''UNLIMITED'' THEN 0
                 ELSE ISNULL(et.DaysPerYear, 0) END AS DECIMAL(9, 2)) AS Earned,
            ISNULL((SELECT SUM(a.Days) FROM [Leave].[LeaveLedger] AS a
                    WHERE a.EmployeeId = et.EmployeeId AND a.LeaveTypeId = et.LeaveTypeId AND a.EntryType = ''ADJUST''
                      AND a.Deleted = 0 AND a.EntryDate BETWEEN et.WinStart AND et.WinEnd AND a.EntryDate <= @AsOf), 0) AS Adjusted,
            ISNULL((SELECT SUM(r.Days) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = ''APPROVED'' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Taken,
            ISNULL((SELECT SUM(r.Days) FROM [Leave].[LeaveRequests] AS r
                    WHERE r.EmployeeId = et.EmployeeId AND r.LeaveTypeId = et.LeaveTypeId AND r.Deleted = 0
                      AND r.Status = ''PENDING'' AND r.StartDate BETWEEN et.WinStart AND et.WinEnd), 0) AS Pending
    FROM    et
)
SELECT  EmployeeId, CompanyId, LeaveTypeId, BalanceMode, WinStart, WinEnd, OpeningDate,
        CAST(OpeningDays AS DECIMAL(9, 2)) AS OpeningDays, Earned, CAST(Adjusted AS DECIMAL(9, 2)) AS Adjusted,
        CAST(CASE WHEN BalanceMode = ''UNLIMITED'' THEN NULL ELSE OpeningDays + Earned + Adjusted END AS DECIMAL(9, 2)) AS Entitled,
        CAST(Taken AS DECIMAL(9, 2)) AS Taken,
        CAST(Pending AS DECIMAL(9, 2)) AS Pending,
        CAST(CASE WHEN BalanceMode = ''UNLIMITED'' THEN NULL ELSE OpeningDays + Earned + Adjusted - Taken END AS DECIMAL(9, 2)) AS Available
FROM    calc;
');
ELSE
    PRINT N'Leave module not installed (db/68-69) - balances skipped.';
GO

/* ---- 4. rights per profile tab ---------------------------------------- */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, GrantWith VARCHAR(60) COLLATE DATABASE_DEFAULT,
                     AlsoNeeds VARCHAR(60) COLLATE DATABASE_DEFAULT NULL, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action, GrantWith, AlsoNeeds) VALUES
    ('EMPLOYEE_PERSONAL_VIEW',   'Employee', 'PersonalView',   'EMPLOYEE_VIEW', NULL),
    ('EMPLOYEE_EMPLOYMENT_VIEW', 'Employee', 'EmploymentView', 'EMPLOYEE_VIEW', NULL),
    ('EMPLOYEE_EMPLOYMENT_EDIT', 'Employee', 'EmploymentEdit', 'EMPLOYEE_EDIT', NULL),
    ('EMPLOYEE_LEAVE_VIEW',      'Employee', 'LeaveView',      'EMPLOYEE_VIEW', 'LEAVE_VIEW');

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

/* first run only: System Administrator, and every role that had the matching right */
INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT r.RoleId, p.PermissionId
FROM   #Codes c
JOIN   [Security].[Permissions] p ON p.PermissionCode = c.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] r ON r.Deleted = 0
WHERE  c.IsNew = 1
  AND (r.RoleCode = N'SYSADMIN'
       OR (EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                   WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = c.GrantWith)
           AND (c.AlsoNeeds IS NULL
                OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                           WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode = c.AlsoNeeds))))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @CodesCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Employee profile tab rights created: ', @CodesCreated, N' (users see them after signing in again).');
DROP TABLE #Codes;
GO
