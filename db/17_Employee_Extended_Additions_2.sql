/* ================================================================
   HRMS Kuwait - Module 4 follow-up 3: Father's Details, Passport,
   Civil ID (Personal Info tab)
   ----------------------------------------------------------------
   PURELY ADDITIVE, and idempotent: every ALTER is guarded by
   COL_LENGTH, same pattern as db/08 and db/13.

   Adds to [Employee].[Employees]:
     - Father's Details: FatherName, FatherOccupation,
       FatherMobileNumber, FatherIsDeceased (bit), and
       CurrentResidenceCountryId (FK to Core.Countries, same pattern
       as the existing NationalityCountryId column - "where the
       employee currently lives" is a different fact from
       "nationality" or "Kuwait mailing address" and deliberately not
       folded into either).
     - Passport: PassportNumber, PassportFullName, PassportSurname,
       PassportPlaceOfIssue, PassportExpiryDate, plus two file-path
       columns (PassportFirstPagePath, PassportLastPagePath) that
       store the relative site path of an uploaded scan - the actual
       file lives on disk under wwwroot/uploads/employees/documents,
       written by EmployeesController.SaveUploadedDocumentAsync; only
       the path string is ever sent to this database.
     - Civil ID: CivilIdNumber, CivilIdName, CivilIdExpiryDate, plus
       two file-path columns (CivilIdFrontPath, CivilIdBackPath),
       same file-upload pattern as Passport above.

   None of these three sections have an existing counterpart on the
   Kuwait Compliance tab, so - unlike BloodGroup/PaciNumber in db/13 -
   there is no naming collision to call out here.

   Run AFTER 13/14/15/16 (needs Employee.Employees to already have its
   earlier Module 4 columns) and BEFORE 18 (which extends
   Employee.usp_Employee_Manage to bind these new columns).
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   1. Employee.Employees - Father's Details
================================================================ */
IF COL_LENGTH('Employee.Employees', 'FatherName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FatherName NVARCHAR(150) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'FatherOccupation') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FatherOccupation NVARCHAR(100) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'FatherMobileNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FatherMobileNumber NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'FatherIsDeceased') IS NULL
    ALTER TABLE [Employee].[Employees] ADD FatherIsDeceased BIT NOT NULL
        CONSTRAINT DF_Employees_FatherIsDeceased DEFAULT (0);
GO

IF COL_LENGTH('Employee.Employees', 'CurrentResidenceCountryId') IS NULL
BEGIN
    ALTER TABLE [Employee].[Employees] ADD CurrentResidenceCountryId INT NULL;
    ALTER TABLE [Employee].[Employees] ADD CONSTRAINT FK_Employees_CurrentResidenceCountry
        FOREIGN KEY(CurrentResidenceCountryId) REFERENCES [Core].[Countries](CountryId);
END
GO

/* ================================================================
   2. Employee.Employees - Passport
================================================================ */
IF COL_LENGTH('Employee.Employees', 'PassportNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportNumber NVARCHAR(30) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportFullName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportFullName NVARCHAR(200) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportSurname') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportSurname NVARCHAR(100) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportPlaceOfIssue') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportPlaceOfIssue NVARCHAR(100) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportExpiryDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportExpiryDate DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportFirstPagePath') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportFirstPagePath NVARCHAR(300) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'PassportLastPagePath') IS NULL
    ALTER TABLE [Employee].[Employees] ADD PassportLastPagePath NVARCHAR(300) NULL;
GO

/* ================================================================
   3. Employee.Employees - Civil ID
================================================================ */
IF COL_LENGTH('Employee.Employees', 'CivilIdNumber') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CivilIdNumber NVARCHAR(30) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CivilIdName') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CivilIdName NVARCHAR(200) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CivilIdExpiryDate') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CivilIdExpiryDate DATE NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CivilIdFrontPath') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CivilIdFrontPath NVARCHAR(300) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CivilIdBackPath') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CivilIdBackPath NVARCHAR(300) NULL;
GO

PRINT 'Employee.Employees extended: Father''s Details, Passport, Civil ID (with document upload path columns).';
GO
