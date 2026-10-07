/* ================================================================
   HRMS Kuwait - Module 4: Workforce (Employees & Kuwait Compliance)
   ----------------------------------------------------------------
   PURELY ADDITIVE, and idempotent: every ALTER is guarded by
   COL_LENGTH so re-running this script is always safe, and every
   CREATE TABLE is guarded by OBJECT_ID for the same reason - the same
   pattern used in db/06_Security_Auth_Additions.sql.

   [Employee].[Employees] already exists in your base schema (it is
   referenced by Organization Setup's employee-count columns and by
   Department.ManagerEmployeeId). This script only adds the columns
   the Employee Profile screen needs that are not already there:
   personal-info fields, and the employment fields the Organization
   Setup module did not need (DesignationId, GradeId, WorkLocationId,
   ReportingManagerId, dates, employment type/status).

   It also creates one new table:
     [Kuwait].[EmployeeCompliance] - Civil ID, passport, residency
     (iqama), work permit and PACI address. One row per employee
     (1:1), kept in its own schema/table rather than bolted onto
     Employee.Employees, because it is a distinct area that changes on
     its own cadence (renewals, sponsor transfers) and the "Kuwait"
     schema was already reserved for exactly this in the original
     design.

   Run AFTER 01-07.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   1. Employee.Employees - personal-info columns
================================================================ */
IF COL_LENGTH('Employee.Employees', 'EmployeeCode') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmployeeCode NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'MiddleName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD MiddleName NVARCHAR(100) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'ArabicName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD ArabicName NVARCHAR(300) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'Gender') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Gender CHAR(1) NULL
        CONSTRAINT CK_Employees_Gender CHECK (Gender IS NULL OR Gender IN ('M', 'F'));
GO

IF COL_LENGTH('Employee.Employees', 'DateOfBirth') IS NULL
    ALTER TABLE [Employee].[Employees] ADD DateOfBirth DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'MaritalStatus') IS NULL
    ALTER TABLE [Employee].[Employees] ADD MaritalStatus NVARCHAR(20) NULL
        CONSTRAINT CK_Employees_MaritalStatus CHECK (MaritalStatus IS NULL OR
            MaritalStatus IN ('Single', 'Married', 'Divorced', 'Widowed'));
GO

IF COL_LENGTH('Employee.Employees', 'NationalityCountryId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD NationalityCountryId INT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_NationalityCountry
        FOREIGN KEY(NationalityCountryId) REFERENCES [Core].[Countries](CountryId);
END
GO

IF COL_LENGTH('Employee.Employees', 'MobileNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD MobileNumber NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PersonalEmail') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PersonalEmail NVARCHAR(150) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'WorkEmail') IS NULL
    ALTER TABLE [Employee].[Employees] ADD WorkEmail NVARCHAR(150) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'Address') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Address NVARCHAR(500) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PhotoPath') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PhotoPath NVARCHAR(300) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'EmergencyContactName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmergencyContactName NVARCHAR(150) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'EmergencyContactPhone') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmergencyContactPhone NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'EmergencyContactRelation') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmergencyContactRelation NVARCHAR(50) NULL;
GO

/* ================================================================
   2. Employee.Employees - employment columns
   ----------------------------------------------------------------
   CompanyId, BranchId, DepartmentId, SectionId, PositionId,
   CostCenterId and IsDeleted already exist (Organization Setup's
   employee-count subqueries depend on them). Designation and Grade
   were not yet wired to an employee row - added here.
================================================================ */
IF COL_LENGTH('Employee.Employees', 'DesignationId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD DesignationId INT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_Designation
        FOREIGN KEY(DesignationId) REFERENCES [Core].[Designations](DesignationId);
END
GO

IF COL_LENGTH('Employee.Employees', 'GradeId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD GradeId INT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_Grade
        FOREIGN KEY(GradeId) REFERENCES [Core].[Grades](GradeId);
END
GO

IF COL_LENGTH('Employee.Employees', 'WorkLocationId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD WorkLocationId INT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_WorkLocation
        FOREIGN KEY(WorkLocationId) REFERENCES [Core].[Locations](LocationId);
END
GO

IF COL_LENGTH('Employee.Employees', 'ReportingManagerId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD ReportingManagerId BIGINT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_ReportingManager
        FOREIGN KEY(ReportingManagerId) REFERENCES [Employee].[Employees](EmployeeId);
END
GO

IF COL_LENGTH('Employee.Employees', 'HireDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD HireDate DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'ProbationEndDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD ProbationEndDate DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'TerminationDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD TerminationDate DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'EmploymentType') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmploymentType NVARCHAR(20) NULL
        CONSTRAINT CK_Employees_EmploymentType CHECK (EmploymentType IS NULL OR
            EmploymentType IN ('Full-Time', 'Part-Time', 'Temporary', 'Contract'));
GO

/* A separate business-lifecycle status, deliberately independent of the
   generic IsDeleted soft-delete flag every other master uses for its
   TOGGLE action. IsDeleted means "this row was created in error" - an
   employee who resigns or is terminated is NEVER hard-deleted, since
   payroll, EOS and Kuwait Ministry of Labour records must be kept. */
IF COL_LENGTH('Employee.Employees', 'EmploymentStatus') IS NULL
    ALTER TABLE [Employee].[Employees] ADD EmploymentStatus NVARCHAR(20) NOT NULL
        CONSTRAINT DF_Employees_EmploymentStatus DEFAULT ('Active')
        CONSTRAINT CK_Employees_EmploymentStatus CHECK (EmploymentStatus IN
            ('Active', 'Probation', 'OnLeave', 'Suspended', 'Terminated', 'Resigned'));
GO

IF COL_LENGTH('Employee.Employees', 'CreatedBy') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CreatedBy BIGINT NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CreatedDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CreatedDate DATETIME2(0) NOT NULL
        CONSTRAINT DF_Employees_CreatedDate DEFAULT (SYSUTCDATETIME());
GO

IF COL_LENGTH('Employee.Employees', 'ModifiedBy') IS NULL
    ALTER TABLE [Employee].[Employees] ADD ModifiedBy BIGINT NULL;
GO

IF COL_LENGTH('Employee.Employees', 'ModifiedDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD ModifiedDate DATETIME2(0) NULL;
GO

/* EmployeeCode is unique per company once populated. A filtered index
   (rather than a table constraint) so historical rows with no code yet
   assigned do not collide with each other on NULL. */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UQ_Employees_Code' AND object_id = OBJECT_ID('Employee.Employees'))
    CREATE UNIQUE INDEX UQ_Employees_Code
        ON [Employee].[Employees](CompanyId, EmployeeCode)
        WHERE EmployeeCode IS NOT NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Employees_Company' AND object_id = OBJECT_ID('Employee.Employees'))
    CREATE INDEX IX_Employees_Company
        ON [Employee].[Employees](CompanyId, IsDeleted) INCLUDE(FirstName, LastName, EmploymentStatus);
GO

/* ================================================================
   3. Kuwait.EmployeeCompliance
   ----------------------------------------------------------------
   One row per employee (1:1 via EmployeeId as both PK and FK).
   Everything here is Kuwait government / labour-law paperwork:
   Civil ID, passport, residency (iqama), work permit, sponsor, PACI
   address. Expiry dates are the whole point of this table - a later
   module (Notifications) will alert HR before any of them lapse.
================================================================ */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'Kuwait')
    EXEC('CREATE SCHEMA [Kuwait]');
GO

IF OBJECT_ID(N'[Kuwait].[EmployeeCompliance]', N'U') IS NULL
BEGIN
    CREATE TABLE [Kuwait].[EmployeeCompliance](
        EmployeeId                BIGINT          NOT NULL
            CONSTRAINT PK_EmployeeCompliance PRIMARY KEY,

        /* Civil ID - the primary Kuwait identity document */
        CivilIdNumber             NVARCHAR(20)    NULL,
        CivilIdExpiryDate         DATE            NULL,

        /* Passport */
        PassportNumber            NVARCHAR(30)    NULL,
        PassportCountryId         INT             NULL,
        PassportExpiryDate        DATE            NULL,

        /* Residency (iqama) */
        ResidencyNumber           NVARCHAR(30)    NULL,
        ResidencyType             NVARCHAR(50)    NULL,
        ResidencyExpiryDate       DATE            NULL,

        /* Sponsorship - who the residency is filed under */
        SponsorName               NVARCHAR(200)   NULL,
        SponsorFileNumber         NVARCHAR(50)    NULL,

        /* Ministry of Labour / work permit */
        MolFileNumber             NVARCHAR(50)    NULL,
        WorkPermitNumber          NVARCHAR(50)    NULL,
        WorkPermitExpiryDate      DATE            NULL,

        /* PACI civil address system */
        PaciNumber                NVARCHAR(20)    NULL,
        PaciAddress               NVARCHAR(300)   NULL,

        /* Driving and medical - common Kuwait HR requirements,
           optional since not every role needs them */
        DrivingLicenseNumber      NVARCHAR(30)    NULL,
        DrivingLicenseExpiryDate  DATE            NULL,
        BloodType                 NVARCHAR(5)     NULL,
        HealthCertificateExpiry   DATE            NULL,

        CreatedBy                 BIGINT          NULL,
        CreatedDate                DATETIME2(0)   NOT NULL CONSTRAINT DF_EmployeeCompliance_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy                 BIGINT         NULL,
        ModifiedDate                DATETIME2(0)  NULL,

        CONSTRAINT FK_EmployeeCompliance_Employee FOREIGN KEY(EmployeeId)
            REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_EmployeeCompliance_PassportCountry FOREIGN KEY(PassportCountryId)
            REFERENCES [Core].[Countries](CountryId),
        CONSTRAINT CK_EmployeeCompliance_BloodType CHECK (BloodType IS NULL OR
            BloodType IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'))
    );

    CREATE INDEX IX_EmployeeCompliance_CivilIdExpiry   ON [Kuwait].[EmployeeCompliance](CivilIdExpiryDate);
    CREATE INDEX IX_EmployeeCompliance_ResidencyExpiry ON [Kuwait].[EmployeeCompliance](ResidencyExpiryDate);
    CREATE INDEX IX_EmployeeCompliance_PermitExpiry    ON [Kuwait].[EmployeeCompliance](WorkPermitExpiryDate);
    CREATE INDEX IX_EmployeeCompliance_PassportExpiry  ON [Kuwait].[EmployeeCompliance](PassportExpiryDate);
END
GO

PRINT 'Workforce additive schema applied: Employee.Employees columns extended, Kuwait.EmployeeCompliance created.';
GO
