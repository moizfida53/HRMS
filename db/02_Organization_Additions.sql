/* ================================================================
   HRMS Kuwait - Organization Setup: additive schema
   ----------------------------------------------------------------
   Run AFTER your existing 01 schema script.

   This script is PURELY ADDITIVE. It creates two tables that the
   Organization Setup screen needs and that the base schema does not
   yet contain. It does not alter, drop or re-create anything you
   already built.

     Core.Designations  - the job title as printed on the Civil ID,
                          work permit and contract ("Accountant",
                          "Heavy Driver"). Distinct from Core.Positions,
                          which is a seat in the org chart.

     Core.Locations     - a physical work site (office floor, warehouse,
                          site camp, clinic). Needed later by the
                          attendance module to place biometric devices.

   Naming, defaults and constraint style follow the conventions in
   your base script exactly.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   Core.Designations
================================================================ */
IF OBJECT_ID(N'[Core].[Designations]', N'U') IS NULL
BEGIN
    CREATE TABLE [Core].[Designations](
        DesignationId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Designations PRIMARY KEY,
        CompanyId       INT NOT NULL,
        DesignationCode NVARCHAR(50) NOT NULL,
        DesignationName NVARCHAR(150) NOT NULL,
        ArabicName      NVARCHAR(150) NULL,
        GradeId         INT NULL,
        Description     NVARCHAR(500) NULL,
        IsActive        BIT NOT NULL CONSTRAINT DF_Designations_IsActive DEFAULT(1),
        CreatedBy       BIGINT NULL,
        CreatedDate     DATETIME2(0) NOT NULL CONSTRAINT DF_Designations_CreatedDate DEFAULT(SYSUTCDATETIME()),
        ModifiedBy      BIGINT NULL,
        ModifiedDate    DATETIME2(0) NULL,
        CONSTRAINT UQ_Designations_Code UNIQUE(CompanyId, DesignationCode),
        CONSTRAINT FK_Designations_Company FOREIGN KEY(CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_Designations_Grade   FOREIGN KEY(GradeId)   REFERENCES [Core].[Grades](GradeId)
    );

    CREATE INDEX IX_Designations_Company
        ON [Core].[Designations](CompanyId, IsActive) INCLUDE(DesignationName);
END
GO

/* ================================================================
   Core.Locations
================================================================ */
IF OBJECT_ID(N'[Core].[Locations]', N'U') IS NULL
BEGIN
    CREATE TABLE [Core].[Locations](
        LocationId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Locations PRIMARY KEY,
        CompanyId    INT NOT NULL,
        BranchId     INT NULL,
        LocationCode NVARCHAR(50) NOT NULL,
        LocationName NVARCHAR(150) NOT NULL,
        LocationType NVARCHAR(50) NULL,
        Governorate  NVARCHAR(100) NULL,
        Area         NVARCHAR(100) NULL,
        Block        NVARCHAR(30) NULL,
        Street       NVARCHAR(150) NULL,
        Building     NVARCHAR(50) NULL,
        Latitude     DECIMAL(10,7) NULL,
        Longitude    DECIMAL(10,7) NULL,
        IsActive     BIT NOT NULL CONSTRAINT DF_Locations_IsActive DEFAULT(1),
        CreatedBy    BIGINT NULL,
        CreatedDate  DATETIME2(0) NOT NULL CONSTRAINT DF_Locations_CreatedDate DEFAULT(SYSUTCDATETIME()),
        ModifiedBy   BIGINT NULL,
        ModifiedDate DATETIME2(0) NULL,
        CONSTRAINT UQ_Locations_Code UNIQUE(CompanyId, LocationCode),
        CONSTRAINT FK_Locations_Company FOREIGN KEY(CompanyId) REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT FK_Locations_Branch  FOREIGN KEY(BranchId)  REFERENCES [Core].[Branches](BranchId),
        CONSTRAINT CK_Locations_Latitude  CHECK(Latitude  IS NULL OR Latitude  BETWEEN -90  AND 90),
        CONSTRAINT CK_Locations_Longitude CHECK(Longitude IS NULL OR Longitude BETWEEN -180 AND 180)
    );

    CREATE INDEX IX_Locations_Company
        ON [Core].[Locations](CompanyId, IsActive) INCLUDE(LocationName);
END
GO

/* ================================================================
   Kuwait governorates - reference data for the Branch and Location
   address fields. Stored as a small keyed table so the same dropdown
   can be served by Core.usp_Lookup_Get.
================================================================ */
IF OBJECT_ID(N'[Core].[Governorates]', N'U') IS NULL
BEGIN
    CREATE TABLE [Core].[Governorates](
        GovernorateId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Governorates PRIMARY KEY,
        CountryId       INT NULL,
        Code            NVARCHAR(20) NOT NULL,
        Name            NVARCHAR(100) NOT NULL,
        ArabicName      NVARCHAR(100) NULL,
        IsActive        BIT NOT NULL CONSTRAINT DF_Governorates_IsActive DEFAULT(1),
        CONSTRAINT UQ_Governorates_Code UNIQUE(Code),
        CONSTRAINT FK_Governorates_Country FOREIGN KEY(CountryId) REFERENCES [Core].[Countries](CountryId)
    );
END
GO

INSERT INTO [Core].[Governorates](CountryId, Code, Name, ArabicName)
SELECT (SELECT TOP 1 CountryId FROM [Core].[Countries] WHERE CountryCode = 'KW'),
       v.Code, v.Name, v.ArabicName
FROM (VALUES
    ('KW-AS', N'Al Asimah (Capital)', N'العاصمة'),
    ('KW-HA', N'Hawalli',             N'حولي'),
    ('KW-FA', N'Farwaniya',           N'الفروانية'),
    ('KW-AH', N'Ahmadi',              N'الأحمدي'),
    ('KW-JA', N'Jahra',               N'الجهراء'),
    ('KW-MU', N'Mubarak Al-Kabeer',   N'مبارك الكبير')
) v(Code, Name, ArabicName)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[Governorates] g WHERE g.Code = v.Code);
GO

PRINT 'Organization Setup additive schema applied: Core.Designations, Core.Locations, Core.Governorates.';
GO
