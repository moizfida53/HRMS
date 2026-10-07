/* ================================================================
   HRMS Kuwait - Employee import support: fields the master-data
   spreadsheet carries that the schema did not have yet
   ----------------------------------------------------------------
   PURELY ADDITIVE and idempotent (COL_LENGTH / OBJECT_ID guards),
   same pattern as db/08, db/13 and db/17.

   Adds:
     [Employee].[Employees]
        CompanyPhone     NVARCHAR(20)   - company-issued phone number
        CompanyAssets    NVARCHAR(300)  - assets issued (laptop, mobile...)

     [Kuwait].[EmployeeCompliance]
        SponsorStatus    NVARCHAR(50)   - Company Sponsor / Family / Self ...
        ResidencyStatus  NVARCHAR(30)   - Valid / Under Process / Expired ...

     [Employee].[EmployeePayroll]  (NEW, 1:1 with Employee.Employees)
        BasicSalary, Allowances (DECIMAL(12,3) - KWD has 3 decimals),
        BankName, Iban.
        Kept out of Employee.Employees on purpose: salary/bank data is
        sensitive and will get its own permissions once the Payroll
        module is built. Read and written through
        Employee.usp_Employee_Manage (GET / INSERT / UPDATE), so the
        Profile page saves it with the rest of the Employment tab.

   Re-creates (CREATE OR ALTER - full body, nothing removed):
     Employee.usp_Employee_Manage          = db/18 + the fields above
     Kuwait.usp_EmployeeCompliance_Manage  = db/10 + SponsorStatus,
                                             ResidencyStatus

   Run AFTER 18. Then run 21_Employee_Import_Data.sql.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   1. Employee.Employees - company phone & assets
================================================================ */
IF COL_LENGTH('Employee.Employees', 'CompanyPhone') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CompanyPhone NVARCHAR(20) NULL;
GO

IF COL_LENGTH('Employee.Employees', 'CompanyAssets') IS NULL
    ALTER TABLE [Employee].[Employees] ADD CompanyAssets NVARCHAR(300) NULL;
GO

/* ================================================================
   2. Kuwait.EmployeeCompliance - sponsor & residency status
================================================================ */
IF COL_LENGTH('Kuwait.EmployeeCompliance', 'SponsorStatus') IS NULL
    ALTER TABLE [Kuwait].[EmployeeCompliance] ADD SponsorStatus NVARCHAR(50) NULL;
GO

IF COL_LENGTH('Kuwait.EmployeeCompliance', 'ResidencyStatus') IS NULL
    ALTER TABLE [Kuwait].[EmployeeCompliance] ADD ResidencyStatus NVARCHAR(30) NULL;
GO

/* ================================================================
   3. Employee.EmployeePayroll - basic salary, allowances, bank
================================================================ */
IF OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
BEGIN
    CREATE TABLE [Employee].[EmployeePayroll](
        EmployeeId     BIGINT         NOT NULL
            CONSTRAINT PK_EmployeePayroll PRIMARY KEY,
        BasicSalary    DECIMAL(12,3)  NULL,
        Allowances     DECIMAL(12,3)  NULL,
        BankName       NVARCHAR(100)  NULL,
        Iban           NVARCHAR(34)   NULL,
        CreatedBy      BIGINT         NULL,
        CreatedDate    DATETIME2(0)   NOT NULL CONSTRAINT DF_EmployeePayroll_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy     BIGINT         NULL,
        ModifiedDate   DATETIME2(0)   NULL,

        CONSTRAINT FK_EmployeePayroll_Employee FOREIGN KEY(EmployeeId)
            REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT CK_EmployeePayroll_BasicSalary CHECK (BasicSalary IS NULL OR BasicSalary >= 0),
        CONSTRAINT CK_EmployeePayroll_Allowances  CHECK (Allowances  IS NULL OR Allowances  >= 0)
    );
END
GO

/* ================================================================
   4. Employee.usp_Employee_Manage (db/18 + db/20 fields)
================================================================ */
CREATE OR ALTER PROCEDURE [Employee].[usp_Employee_Manage]
    /* ---- action ------------------------------------------------ */
    @Action                     VARCHAR(10),
    @Id                         BIGINT          = NULL,

    /* ---- LIST filters and paging -------------------------------- */
    @Search                     NVARCHAR(200)   = NULL,
    @IsActiveFilter             BIT             = NULL,   -- maps to IsDeleted = 0 (active) / 1 (deleted)
    @CompanyId                  INT             = NULL,   -- LIST scope filter AND editable column - declared once
    @ParentId                   INT             = NULL,   -- LIST filter: DepartmentId
    @PageNumber                 INT             = 1,
    @PageSize                   INT             = 25,
    @SortColumn                 VARCHAR(50)     = NULL,
    @SortDirection              VARCHAR(4)      = 'ASC',

    /* ---- editable columns: personal info ------------------------ */
    @EmployeeCode               NVARCHAR(20)    = NULL,
    @EmployeeNo                 NVARCHAR(20)    = NULL,
    @FirstName                  NVARCHAR(100)   = NULL,
    @MiddleName                 NVARCHAR(100)   = NULL,
    @LastName                   NVARCHAR(100)   = NULL,
    @ArabicName                 NVARCHAR(300)   = NULL,
    @Gender                     CHAR(1)         = NULL,
    @DateOfBirth                DATE            = NULL,
    @MaritalStatus              NVARCHAR(20)    = NULL,
    @NationalityCountryId       INT             = NULL,
    @Religion                   NVARCHAR(50)    = NULL,
    @BloodGroup                 NVARCHAR(5)     = NULL,
    @MobileNumber                NVARCHAR(20)   = NULL,
    @Extension                   NVARCHAR(10)   = NULL,
    @PersonalEmail               NVARCHAR(150)  = NULL,
    @WorkEmail                   NVARCHAR(150)  = NULL,
    @Address                     NVARCHAR(500)  = NULL,
    @Neighborhood                 NVARCHAR(100) = NULL,
    @Block                        NVARCHAR(20)  = NULL,
    @StreetName                   NVARCHAR(150) = NULL,
    @BuildingNumber                NVARCHAR(30) = NULL,
    @FloorNumber                   NVARCHAR(20) = NULL,
    @FlatNumber                    NVARCHAR(20) = NULL,
    @PaciNumber                    NVARCHAR(20) = NULL,
    @Landmark                      NVARCHAR(200)= NULL,
    @PhotoPath                   NVARCHAR(300)  = NULL,
    @EmergencyContactName        NVARCHAR(150)  = NULL,
    @EmergencyContactPhone       NVARCHAR(20)   = NULL,
    @EmergencyContactRelation    NVARCHAR(50)   = NULL,

    /* ---- editable columns: father's details ---------------------- */
    @FatherName                  NVARCHAR(150)  = NULL,
    @FatherOccupation            NVARCHAR(100)  = NULL,
    @FatherMobileNumber          NVARCHAR(20)   = NULL,
    @FatherIsDeceased            BIT            = NULL,
    @CurrentResidenceCountryId   INT            = NULL,

    /* ---- editable columns: passport -------------------------------- */
    @PassportNumber              NVARCHAR(30)   = NULL,
    @PassportFullName            NVARCHAR(200)  = NULL,
    @PassportSurname             NVARCHAR(100)  = NULL,
    @PassportPlaceOfIssue        NVARCHAR(100)  = NULL,
    @PassportExpiryDate          DATE           = NULL,
    @PassportFirstPagePath       NVARCHAR(300)  = NULL,
    @PassportLastPagePath        NVARCHAR(300)  = NULL,

    /* ---- editable columns: civil id -------------------------------- */
    @CivilIdNumber               NVARCHAR(30)   = NULL,
    @CivilIdName                 NVARCHAR(200)  = NULL,
    @CivilIdExpiryDate           DATE           = NULL,
    @CivilIdFrontPath            NVARCHAR(300)  = NULL,
    @CivilIdBackPath             NVARCHAR(300)  = NULL,

    /* ---- editable columns: employment -----------------------------
       CompanyId is NOT repeated here - it is already declared above. */
    @BranchId                    INT            = NULL,
    @DepartmentId                INT            = NULL,
    @SectionId                   INT            = NULL,
    @PositionId                  INT            = NULL,   -- Job Position
    @DesignationId               INT            = NULL,
    @GradeId                     INT            = NULL,
    @CostCenterId                INT            = NULL,
    @WorkLocationId               INT           = NULL,
    @ReportingManagerId          BIGINT         = NULL,
    @HireDate                    DATE           = NULL,
    @ProbationEndDate            DATE           = NULL,
    @TerminationDate             DATE           = NULL,
    @EmploymentType               NVARCHAR(20)  = NULL,
    @EmploymentStatus             NVARCHAR(20)  = NULL,
    @NoticePeriodDays              INT          = NULL,

    /* ---- db/20: company contact & assets -------------------------- */
    @CompanyPhone                NVARCHAR(20)   = NULL,
    @CompanyAssets               NVARCHAR(300)  = NULL,

    /* ---- db/20: payroll & bank (stored in Employee.EmployeePayroll) - */
    @BasicSalary                 DECIMAL(12,3)  = NULL,
    @Allowances                  DECIMAL(12,3)  = NULL,
    @BankName                    NVARCHAR(100)  = NULL,
    @Iban                        NVARCHAR(34)   = NULL,

    /* ---- audit --------------------------------------------------- */
    @UserId                      BIGINT         = NULL,

    /* ---- outputs --------------------------------------------------*/
    @TotalCount                  INT            = NULL OUTPUT,
    @NewId                       BIGINT         = NULL OUTPUT,
    @ResultCode                  VARCHAR(40)    = NULL OUTPUT,
    @ResultMessage               NVARCHAR(400)  = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@Id, 0),
           @TotalCount    = 0;

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE', 'TOGGLE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    SET @SortDirection = CASE WHEN UPPER(ISNULL(@SortDirection, 'ASC')) = 'DESC' THEN 'DESC' ELSE 'ASC' END;
    SET @PageNumber    = CASE WHEN ISNULL(@PageNumber, 1) < 1 THEN 1 ELSE @PageNumber END;
    SET @PageSize      = CASE WHEN ISNULL(@PageSize, 25) NOT BETWEEN 1 AND 200 THEN 25 ELSE @PageSize END;

    DECLARE @Pattern NVARCHAR(410) =
        CASE
            WHEN NULLIF(LTRIM(RTRIM(@Search)), N'') IS NULL THEN NULL
            ELSE N'%' + REPLACE(REPLACE(REPLACE(LTRIM(RTRIM(@Search)), N'\', N'\\'), N'%', N'\%'), N'_', N'\_') + N'%'
        END;

    /* ======================= LIST ================================= */
    IF @Action = 'LIST'
    BEGIN
        SELECT @TotalCount = COUNT(1)
        FROM        [Employee].[Employees] AS e
        WHERE       1 = 1
                AND (@IsActiveFilter IS NULL OR e.IsDeleted = CASE WHEN @IsActiveFilter = 1 THEN 0 ELSE 1 END)
                AND (@CompanyId      IS NULL OR e.CompanyId = @CompanyId)
                AND (@ParentId       IS NULL OR e.DepartmentId = @ParentId)
                AND (@Pattern IS NULL OR (
                        e.EmployeeCode LIKE @Pattern ESCAPE '\'
                     OR e.FirstName    LIKE @Pattern ESCAPE '\'
                     OR e.LastName     LIKE @Pattern ESCAPE '\'
                     OR e.ArabicName   LIKE @Pattern ESCAPE '\'
                     OR e.MobileNumber LIKE @Pattern ESCAPE '\'
                     OR e.WorkEmail    LIKE @Pattern ESCAPE '\'));

        SELECT  e.EmployeeId,
                e.EmployeeCode,
                e.FirstName,
                e.LastName,
                CONCAT(e.FirstName, N' ', ISNULL(e.LastName, N'')) AS FullName,
                e.MobileNumber,
                e.WorkEmail,
                e.HireDate,
                e.EmploymentStatus,
                CASE WHEN e.IsDeleted = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsActive,
                e.CompanyId,
                c.CompanyName,
                e.DepartmentId,
                d.DepartmentName,
                e.PositionId,
                p.PositionName,
                e.DesignationId,
                dg.DesignationName
        FROM        [Employee].[Employees] AS e
        INNER JOIN  [Core].[Companies]     AS c  ON c.CompanyId    = e.CompanyId
        LEFT JOIN   [Core].[Departments]   AS d  ON d.DepartmentId = e.DepartmentId
        LEFT JOIN   [Core].[Positions]     AS p  ON p.PositionId   = e.PositionId
        LEFT JOIN   [Core].[Designations]  AS dg ON dg.DesignationId = e.DesignationId
        WHERE       1 = 1
                AND (@IsActiveFilter IS NULL OR e.IsDeleted = CASE WHEN @IsActiveFilter = 1 THEN 0 ELSE 1 END)
                AND (@CompanyId      IS NULL OR e.CompanyId = @CompanyId)
                AND (@ParentId       IS NULL OR e.DepartmentId = @ParentId)
                AND (@Pattern IS NULL OR (
                        e.EmployeeCode LIKE @Pattern ESCAPE '\'
                     OR e.FirstName    LIKE @Pattern ESCAPE '\'
                     OR e.LastName     LIKE @Pattern ESCAPE '\'
                     OR e.ArabicName   LIKE @Pattern ESCAPE '\'
                     OR e.MobileNumber LIKE @Pattern ESCAPE '\'
                     OR e.WorkEmail    LIKE @Pattern ESCAPE '\'))
        ORDER BY
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EmployeeCode' THEN e.EmployeeCode END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EmployeeCode' THEN e.EmployeeCode END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'FullName' THEN e.FirstName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'FullName' THEN e.FirstName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'DepartmentName' THEN d.DepartmentName END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'HireDate' THEN e.HireDate END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'HireDate' THEN e.HireDate END DESC,
                CASE WHEN @SortDirection = 'ASC'  AND @SortColumn = 'EmploymentStatus' THEN e.EmploymentStatus END ASC,
                CASE WHEN @SortDirection = 'DESC' AND @SortColumn = 'EmploymentStatus' THEN e.EmploymentStatus END DESC,
                e.FirstName ASC
        OFFSET (@PageNumber - 1) * @PageSize ROWS
        FETCH NEXT @PageSize ROWS ONLY;

        RETURN;
    END;

    /* ======================= GET =================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  e.EmployeeId,
                e.EmployeeCode,
                e.EmployeeNo,
                e.FirstName,
                e.MiddleName,
                e.LastName,
                e.ArabicName,
                e.Gender,
                e.DateOfBirth,
                e.MaritalStatus,
                e.NationalityCountryId,
                nc.CountryName                                         AS NationalityName,
                e.Religion,
                e.BloodGroup,
                e.MobileNumber,
                e.Extension,
                e.PersonalEmail,
                e.WorkEmail,
                e.Address,
                e.Neighborhood,
                e.Block,
                e.StreetName,
                e.BuildingNumber,
                e.FloorNumber,
                e.FlatNumber,
                e.PaciNumber,
                e.Landmark,
                e.PhotoPath,
                e.EmergencyContactName,
                e.EmergencyContactPhone,
                e.EmergencyContactRelation,
                e.FatherName,
                e.FatherOccupation,
                e.FatherMobileNumber,
                e.FatherIsDeceased,
                e.CurrentResidenceCountryId,
                crc.CountryName                                        AS CurrentResidenceCountryName,
                e.PassportNumber,
                e.PassportFullName,
                e.PassportSurname,
                e.PassportPlaceOfIssue,
                e.PassportExpiryDate,
                e.PassportFirstPagePath,
                e.PassportLastPagePath,
                e.CivilIdNumber,
                e.CivilIdName,
                e.CivilIdExpiryDate,
                e.CivilIdFrontPath,
                e.CivilIdBackPath,
                e.CompanyId,
                c.CompanyName,
                e.BranchId,
                br.BranchName,
                e.DepartmentId,
                d.DepartmentName,
                e.SectionId,
                s.SectionName,
                e.PositionId,
                p.PositionName,
                e.DesignationId,
                dg.DesignationName,
                e.GradeId,
                g.GradeName,
                e.CostCenterId,
                cc.CostCenterName,
                e.WorkLocationId,
                loc.LocationName,
                e.ReportingManagerId,
                CONCAT(mgr.FirstName, N' ', ISNULL(mgr.LastName, N'')) AS ReportingManagerName,
                e.HireDate,
                e.ProbationEndDate,
                e.TerminationDate,
                e.EmploymentType,
                e.EmploymentStatus,
                e.NoticePeriodDays,
                e.CompanyPhone,
                e.CompanyAssets,
                pay.BasicSalary,
                pay.Allowances,
                pay.BankName,
                pay.Iban,
                CASE WHEN e.IsDeleted = 0 THEN CAST(1 AS BIT) ELSE CAST(0 AS BIT) END AS IsActive
        FROM        [Employee].[Employees] AS e
        INNER JOIN  [Core].[Companies]     AS c   ON c.CompanyId       = e.CompanyId
        LEFT JOIN   [Core].[Branches]      AS br  ON br.BranchId       = e.BranchId
        LEFT JOIN   [Core].[Departments]   AS d   ON d.DepartmentId    = e.DepartmentId
        LEFT JOIN   [Core].[Sections]      AS s   ON s.SectionId       = e.SectionId
        LEFT JOIN   [Core].[Positions]     AS p   ON p.PositionId      = e.PositionId
        LEFT JOIN   [Core].[Designations]  AS dg  ON dg.DesignationId  = e.DesignationId
        LEFT JOIN   [Core].[Grades]        AS g   ON g.GradeId         = e.GradeId
        LEFT JOIN   [Core].[CostCenters]   AS cc  ON cc.CostCenterId   = e.CostCenterId
        LEFT JOIN   [Core].[Locations]     AS loc ON loc.LocationId    = e.WorkLocationId
        LEFT JOIN   [Employee].[Employees] AS mgr ON mgr.EmployeeId    = e.ReportingManagerId
        LEFT JOIN   [Core].[Countries]     AS nc  ON nc.CountryId      = e.NationalityCountryId
        LEFT JOIN   [Core].[Countries]     AS crc ON crc.CountryId      = e.CurrentResidenceCountryId
        LEFT JOIN   [Employee].[EmployeePayroll] AS pay ON pay.EmployeeId = e.EmployeeId
        WHERE       e.EmployeeId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ================================ */
    IF @Action = 'INSERT'
    BEGIN
        IF NULLIF(LTRIM(RTRIM(@EmployeeNo)), N'') IS NULL
        BEGIN
            SELECT @ResultCode    = 'EMPLOYEE_NO_REQUIRED',
                   @ResultMessage = N'Employee No is required.';
            RETURN;
        END;

        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
            RETURN;
        END;

        IF EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeNo = @EmployeeNo)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_EMPLOYEE_NO',
                   @ResultMessage = N'That employee No is already in use. Enter a different one.';
            RETURN;
        END;

        INSERT INTO [Employee].[Employees]
            (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, ArabicName, Gender, DateOfBirth,
             MaritalStatus, NationalityCountryId, Religion, BloodGroup, MobileNumber, Extension,
             PersonalEmail, WorkEmail, Address, Neighborhood, Block, StreetName, BuildingNumber,
             FloorNumber, FlatNumber, PaciNumber, Landmark, PhotoPath, EmergencyContactName,
             EmergencyContactPhone, EmergencyContactRelation,
             FatherName, FatherOccupation, FatherMobileNumber, FatherIsDeceased, CurrentResidenceCountryId,
             PassportNumber, PassportFullName, PassportSurname, PassportPlaceOfIssue, PassportExpiryDate,
             PassportFirstPagePath, PassportLastPagePath,
             CivilIdNumber, CivilIdName, CivilIdExpiryDate, CivilIdFrontPath, CivilIdBackPath,
             CompanyId, BranchId, DepartmentId, SectionId, PositionId, DesignationId, GradeId,
             CostCenterId, WorkLocationId, ReportingManagerId, HireDate, ProbationEndDate,
             TerminationDate, EmploymentType, EmploymentStatus, NoticePeriodDays,
             CompanyPhone, CompanyAssets, IsDeleted, CreatedBy)
        VALUES
            (@EmployeeCode, @EmployeeNo, @FirstName, @MiddleName, @LastName, @ArabicName, @Gender, @DateOfBirth,
             @MaritalStatus, @NationalityCountryId, @Religion, @BloodGroup, @MobileNumber, @Extension,
             @PersonalEmail, @WorkEmail, @Address, @Neighborhood, @Block, @StreetName, @BuildingNumber,
             @FloorNumber, @FlatNumber, @PaciNumber, @Landmark, @PhotoPath, @EmergencyContactName,
             @EmergencyContactPhone, @EmergencyContactRelation,
             @FatherName, @FatherOccupation, @FatherMobileNumber, ISNULL(@FatherIsDeceased, 0), @CurrentResidenceCountryId,
             @PassportNumber, @PassportFullName, @PassportSurname, @PassportPlaceOfIssue, @PassportExpiryDate,
             @PassportFirstPagePath, @PassportLastPagePath,
             @CivilIdNumber, @CivilIdName, @CivilIdExpiryDate, @CivilIdFrontPath, @CivilIdBackPath,
             @CompanyId, @BranchId, @DepartmentId, @SectionId, @PositionId, @DesignationId, @GradeId,
             @CostCenterId, @WorkLocationId, @ReportingManagerId, @HireDate, @ProbationEndDate,
             @TerminationDate, @EmploymentType, ISNULL(@EmploymentStatus, N'Active'), @NoticePeriodDays,
             @CompanyPhone, @CompanyAssets, 0, @UserId);

        SET @NewId = SCOPE_IDENTITY();

        /* db/20: payroll & bank - only create the 1:1 row when something was entered */
        IF COALESCE(CAST(@BasicSalary AS NVARCHAR(40)), CAST(@Allowances AS NVARCHAR(40)), @BankName, @Iban) IS NOT NULL
            INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
            VALUES (@NewId, @BasicSalary, @Allowances, @BankName, @Iban, @UserId);
        SET @ResultMessage = N'Employee created successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ================================= */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        IF NULLIF(LTRIM(RTRIM(@EmployeeNo)), N'') IS NULL
        BEGIN
            SELECT @ResultCode    = 'EMPLOYEE_NO_REQUIRED',
                   @ResultMessage = N'Employee No is required.';
            RETURN;
        END;

        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode AND EmployeeId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
            RETURN;
        END;

        IF EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeNo = @EmployeeNo AND EmployeeId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_EMPLOYEE_NO',
                   @ResultMessage = N'That employee No is already in use. Enter a different one.';
            RETURN;
        END;

        -- An employee cannot be set as their own reporting manager.
        IF @ReportingManagerId = @Id
        BEGIN
            SELECT @ResultCode    = 'INVALID_MANAGER',
                   @ResultMessage = N'An employee cannot report to themselves.';
            RETURN;
        END;

        UPDATE [Employee].[Employees]
           SET EmployeeCode             = @EmployeeCode,
               EmployeeNo               = @EmployeeNo,
               FirstName                = @FirstName,
               MiddleName               = @MiddleName,
               LastName                 = @LastName,
               ArabicName               = @ArabicName,
               Gender                   = @Gender,
               DateOfBirth              = @DateOfBirth,
               MaritalStatus            = @MaritalStatus,
               NationalityCountryId     = @NationalityCountryId,
               Religion                 = @Religion,
               BloodGroup               = @BloodGroup,
               MobileNumber             = @MobileNumber,
               Extension                = @Extension,
               PersonalEmail            = @PersonalEmail,
               WorkEmail                = @WorkEmail,
               Address                  = @Address,
               Neighborhood             = @Neighborhood,
               Block                    = @Block,
               StreetName               = @StreetName,
               BuildingNumber           = @BuildingNumber,
               FloorNumber              = @FloorNumber,
               FlatNumber               = @FlatNumber,
               PaciNumber               = @PaciNumber,
               Landmark                 = @Landmark,
               PhotoPath                = @PhotoPath,
               EmergencyContactName     = @EmergencyContactName,
               EmergencyContactPhone    = @EmergencyContactPhone,
               EmergencyContactRelation = @EmergencyContactRelation,
               FatherName               = @FatherName,
               FatherOccupation         = @FatherOccupation,
               FatherMobileNumber       = @FatherMobileNumber,
               FatherIsDeceased         = ISNULL(@FatherIsDeceased, 0),
               CurrentResidenceCountryId = @CurrentResidenceCountryId,
               PassportNumber           = @PassportNumber,
               PassportFullName         = @PassportFullName,
               PassportSurname          = @PassportSurname,
               PassportPlaceOfIssue     = @PassportPlaceOfIssue,
               PassportExpiryDate       = @PassportExpiryDate,
               PassportFirstPagePath    = @PassportFirstPagePath,
               PassportLastPagePath     = @PassportLastPagePath,
               CivilIdNumber            = @CivilIdNumber,
               CivilIdName              = @CivilIdName,
               CivilIdExpiryDate        = @CivilIdExpiryDate,
               CivilIdFrontPath         = @CivilIdFrontPath,
               CivilIdBackPath          = @CivilIdBackPath,
               CompanyId                = @CompanyId,
               BranchId                 = @BranchId,
               DepartmentId             = @DepartmentId,
               SectionId                = @SectionId,
               PositionId               = @PositionId,
               DesignationId            = @DesignationId,
               GradeId                  = @GradeId,
               CostCenterId             = @CostCenterId,
               WorkLocationId           = @WorkLocationId,
               ReportingManagerId       = @ReportingManagerId,
               HireDate                 = @HireDate,
               ProbationEndDate         = @ProbationEndDate,
               TerminationDate          = @TerminationDate,
               EmploymentType           = @EmploymentType,
               EmploymentStatus         = ISNULL(@EmploymentStatus, N'Active'),
               NoticePeriodDays         = @NoticePeriodDays,
               CompanyPhone             = @CompanyPhone,
               CompanyAssets            = @CompanyAssets,
               ModifiedBy               = @UserId,
               ModifiedDate             = SYSUTCDATETIME()
         WHERE EmployeeId = @Id;

        /* db/20: payroll & bank upsert (1:1) */
        IF EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] WHERE EmployeeId = @Id)
        BEGIN
            UPDATE [Employee].[EmployeePayroll]
               SET BasicSalary  = @BasicSalary,
                   Allowances   = @Allowances,
                   BankName     = @BankName,
                   Iban         = @Iban,
                   ModifiedBy   = @UserId,
                   ModifiedDate = SYSUTCDATETIME()
             WHERE EmployeeId = @Id;
        END
        ELSE IF COALESCE(CAST(@BasicSalary AS NVARCHAR(40)), CAST(@Allowances AS NVARCHAR(40)), @BankName, @Iban) IS NOT NULL
        BEGIN
            INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
            VALUES (@Id, @BasicSalary, @Allowances, @BankName, @Iban, @UserId);
        END;

        SET @NewId = @Id;
        SET @ResultMessage = N'Employee updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ================================= */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists.';
            RETURN;
        END;

        IF EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE ReportingManagerId = @Id)
        OR EXISTS (SELECT 1 FROM [Core].[Departments] WHERE ManagerEmployeeId = @Id)
        OR EXISTS (SELECT 1 FROM [Security].[Users] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'IN_USE',
                   @ResultMessage = N'This employee is referenced elsewhere (as a manager or a system login) and cannot be deleted. Deactivate instead.';
            RETURN;
        END;

        DELETE FROM [Employee].[Dependents]        WHERE EmployeeId = @Id;
        DELETE FROM [Kuwait].[EmployeeCompliance]  WHERE EmployeeId = @Id;
        DELETE FROM [Employee].[EmployeePayroll]   WHERE EmployeeId = @Id;
        DELETE FROM [Employee].[Employees]         WHERE EmployeeId = @Id;

        SET @ResultMessage = N'Employee deleted successfully.';
        RETURN;
    END;

    /* ======================= TOGGLE ================================== */
    -- Employee uses IsDeleted, not IsActive, so TOGGLE flips that instead -
    -- semantics identical to every other master's TOGGLE from the caller's
    -- point of view (activate / deactivate one record).
    IF @Action = 'TOGGLE'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @Id)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists.';
            RETURN;
        END;

        UPDATE [Employee].[Employees]
           SET IsDeleted    = CASE WHEN IsDeleted = 1 THEN 0 ELSE 1 END,
               ModifiedBy   = @UserId,
               ModifiedDate = SYSUTCDATETIME()
         WHERE EmployeeId = @Id;

        SELECT @ResultMessage = CASE WHEN IsDeleted = 0
                                     THEN N'Employee activated.'
                                     ELSE N'Employee deactivated.' END
        FROM [Employee].[Employees]
        WHERE EmployeeId = @Id;

        RETURN;
    END;
END;
GO


/* ================================================================
   5. Kuwait.usp_EmployeeCompliance_Manage (db/10 + SponsorStatus, ResidencyStatus)
================================================================ */
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
                 PaciNumber, PaciAddress, DrivingLicenseNumber, DrivingLicenseExpiryDate,
                 BloodType, HealthCertificateExpiry, CreatedBy)
            VALUES
                (@EmployeeId, @CivilIdNumber, @CivilIdExpiryDate, @PassportNumber, @PassportCountryId,
                 @PassportExpiryDate, @ResidencyNumber, @ResidencyType, @ResidencyExpiryDate,
                 @SponsorName, @SponsorFileNumber, @SponsorStatus, @ResidencyStatus, @MolFileNumber, @WorkPermitNumber, @WorkPermitExpiryDate,
                 @PaciNumber, @PaciAddress, @DrivingLicenseNumber, @DrivingLicenseExpiryDate,
                 @BloodType, @HealthCertificateExpiry, @UserId);
        END;

        SET @ResultMessage = N'Kuwait compliance details saved.';
        RETURN;
    END;
END;
GO

PRINT 'db/20 applied: CompanyPhone, CompanyAssets, SponsorStatus, ResidencyStatus, Employee.EmployeePayroll; procedures re-created.';
GO
