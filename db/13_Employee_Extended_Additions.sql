/* ================================================================
   HRMS Kuwait - Module 4 follow-up: extended Employee fields + Dependents
   ----------------------------------------------------------------
   PURELY ADDITIVE, and idempotent: every ALTER is guarded by
   COL_LENGTH and every CREATE TABLE by OBJECT_ID, same pattern as
   db/08_Employee_Kuwait_Additions.sql.

   Adds to [Employee].[Employees]:
     - Religion, BloodGroup: general personal-info fields (distinct
       from [Kuwait].[EmployeeCompliance].BloodType, which stays
       exactly as it was - that one is the Kuwait driving-license/
       medical-certificate field on the Compliance tab; BloodGroup
       here is the general HR record on the Personal Info tab. Two
       fields with overlapping meaning, kept deliberately separate
       rather than merged, because they come from two different
       tabs/forms with two different update cadences).
     - Extension: office phone extension, Contact section.
     - NoticePeriodDays: Employment Terms section.
     - Neighborhood, Block, StreetName, BuildingNumber, FloorNumber,
       FlatNumber, PaciNumber, Landmark: the Kuwait PACI civil-address
       breakdown, replacing the single free-text Address field in the
       Personal Info UI (Address itself is NOT dropped - see the note
       above ALTER TABLE below).
     - Neighborhood and Block are plain NVARCHAR, not FKs to a lookup
       table: Kuwait has hundreds of named neighborhoods/blocks and
       there is no existing master for them (unlike Governorate, which
       already has one in Core.Governorates). Add a proper master and
       switch these to dropdowns later if picklists turn out to matter
       more than free entry.

   Also creates [Employee].[Dependents] - a real one-to-many child list
   (spouse, children, etc.), NOT a 1:1 record like EmployeeCompliance.
   Kept in the [Employee] schema, not [Kuwait], because dependents are
   a general HR concept, not Kuwait government paperwork.

   Run AFTER 08 (needs Employee.Employees to already exist with its
   Module 4 columns) and BEFORE 14 (which extends
   Employee.usp_Employee_Manage to bind these new columns).
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   1. Employee.Employees - additional personal-info fields
================================================================ */
IF COL_LENGTH('Employee.Employees', 'Religion') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Religion NVARCHAR(50) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'BloodGroup') IS NULL
    ALTER TABLE [Employee].[Employees] ADD BloodGroup NVARCHAR(5) NULL
        CONSTRAINT CK_Employees_BloodGroup CHECK (BloodGroup IS NULL OR
            BloodGroup IN ('A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'));
GO

IF COL_LENGTH('Employee.Employees', 'Extension') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Extension NVARCHAR(10) NULL;
GO

/* ----------------------------------------------------------------
   PACI address breakdown. The existing free-text Address column is
   NOT dropped - "purely additive" applies here too, and dropping it
   would silently discard anything already typed into it. It is simply
   no longer bound by the Personal Info form once 14 is applied and the
   application is redeployed; existing values stay in the database and
   can be read directly if ever needed (e.g. via a one-off migration
   into these new fields for pre-existing rows). New rows will only
   ever populate the structured fields below.
---------------------------------------------------------------- */
IF COL_LENGTH('Employee.Employees', 'Neighborhood') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Neighborhood NVARCHAR(100) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'Block') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Block NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'StreetName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD StreetName NVARCHAR(150) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'BuildingNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD BuildingNumber NVARCHAR(30) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'FloorNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FloorNumber NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'FlatNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FlatNumber NVARCHAR(20) NULL;
GO

/* Distinct column from [Kuwait].[EmployeeCompliance].PaciNumber - that
   one is the employee's official PACI file number, entered on the
   Kuwait Compliance tab. This one is part of the everyday mailing
   address on the Personal Info tab. They will usually match in
   practice but are edited from two different forms, so they are kept
   as two columns rather than one shared between two tabs. */
IF COL_LENGTH('Employee.Employees', 'PaciNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PaciNumber NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'Landmark') IS NULL
    ALTER TABLE [Employee].[Employees] ADD Landmark NVARCHAR(200) NULL;
GO

/* ================================================================
   2. Employee.Employees - Employment Terms addition
================================================================ */
IF COL_LENGTH('Employee.Employees', 'NoticePeriodDays') IS NULL
    ALTER TABLE [Employee].[Employees] ADD NoticePeriodDays INT NULL
        CONSTRAINT CK_Employees_NoticePeriodDays CHECK (NoticePeriodDays IS NULL OR NoticePeriodDays >= 0);
GO

/* ================================================================
   3. Employee.Dependents
   ----------------------------------------------------------------
   One-to-many: a spouse, children, or other dependents an employee
   registers (typically for health-insurance coverage). Deliberately
   NOT built on the shared Manage-procedure envelope used by the eight
   Organization Setup masters and Employee itself - there is no
   company-wide list of dependents to page/sort/search, only ever "the
   dependents of employee X", so it gets a small bespoke procedure
   (LIST/GET/INSERT/UPDATE/DELETE scoped by @EmployeeId) and a bespoke
   repository, the same reasoning already used for
   Kuwait.EmployeeCompliance's 1:1 GET/UPSERT pair - just extended to a
   1:many list instead of a single record.
================================================================ */
IF OBJECT_ID(N'[Employee].[Dependents]', N'U') IS NULL
BEGIN
    CREATE TABLE [Employee].[Dependents](
        DependentId        BIGINT          IDENTITY(1,1) NOT NULL
            CONSTRAINT PK_Dependents PRIMARY KEY,
        EmployeeId         BIGINT          NOT NULL,

        FullName           NVARCHAR(150)   NOT NULL,
        Relationship       NVARCHAR(30)    NOT NULL,
        DateOfBirth        DATE            NULL,
        Gender             CHAR(1)         NULL,
        HasHealthInsurance BIT             NOT NULL
            CONSTRAINT DF_Dependents_HasHealthInsurance DEFAULT (0),

        CreatedBy          BIGINT          NULL,
        CreatedDate        DATETIME2(0)    NOT NULL CONSTRAINT DF_Dependents_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy         BIGINT          NULL,
        ModifiedDate       DATETIME2(0)    NULL,

        CONSTRAINT FK_Dependents_Employee FOREIGN KEY(EmployeeId)
            REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_Dependents_Relationship CHECK (Relationship IN
            ('Spouse', 'Son', 'Daughter', 'Father', 'Mother', 'Other')),
        CONSTRAINT CK_Dependents_Gender CHECK (Gender IS NULL OR Gender IN ('M', 'F'))
    );

    CREATE INDEX IX_Dependents_Employee ON [Employee].[Dependents](EmployeeId, CreatedDate);
END
GO

PRINT 'Employee.Employees extended (Religion, BloodGroup, Extension, PACI address breakdown, NoticePeriodDays); Employee.Dependents created.';
GO
