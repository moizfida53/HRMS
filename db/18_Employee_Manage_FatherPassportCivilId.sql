/* ================================================================
   HRMS Kuwait - extends Employee.usp_Employee_Manage (again)
   ----------------------------------------------------------------
   Adds Father's Details, Passport and Civil ID as their own fields on
   the Personal Info tab/step, per the user's follow-up request:

     Father's Section: Father's Name, Father's Occupation, Father's
     Mobile Number, Dead (checkbox -> FatherIsDeceased BIT), Currently
     Residing In (country dropdown -> CurrentResidenceCountryId, same
     FK-to-Core.Countries pattern as the existing NationalityCountryId).

     Passport Section: Passport Number, Full Name in Passport, Surname
     in Passport, Place of Issue, Date of Expiry, plus two uploaded
     scans (First Page / Last Page) - the upload itself is handled by
     EmployeesController.SaveUploadedDocumentAsync, which writes the
     file under wwwroot/uploads/employees/documents and passes only
     the resulting relative path string down to this procedure
     (PassportFirstPagePath / PassportLastPagePath) - no BLOB/FILESTREAM
     column, consistent with the existing (currently unused) PhotoPath
     column's own path-not-bytes convention.

     Civil ID Section: Civil ID Number, Name in Civil ID, Expiry Date,
     plus two uploaded scans (Front / Back), same path-column pattern
     as Passport above (CivilIdFrontPath / CivilIdBackPath).

   As with db/16, CREATE OR ALTER replaces the whole procedure body, so
   this file carries the complete text of db/16_Employee_Manage_EmployeeNo.sql
   plus the 17 new parameters above, wired into GET's SELECT list (with
   a new LEFT JOIN Core.Countries AS crc for CurrentResidenceCountryName)
   and INSERT/UPDATE's column and SET lists. FatherIsDeceased goes
   through ISNULL(@FatherIsDeceased, 0) the same way EmploymentStatus
   already goes through ISNULL(@EmploymentStatus, N'Active') - both are
   NOT NULL columns with a database default that a NULL parameter
   should fall back to, not overwrite with NULL.

   Every existing action, filter and column from db/16 is reproduced
   unchanged so nothing already working regresses.

   Run AFTER 17 (needs the new Employee.Employees columns to exist).
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

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
             TerminationDate, EmploymentType, EmploymentStatus, NoticePeriodDays, IsDeleted, CreatedBy)
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
             @TerminationDate, @EmploymentType, ISNULL(@EmploymentStatus, N'Active'), @NoticePeriodDays, 0, @UserId);

        SET @NewId = SCOPE_IDENTITY();
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
               ModifiedBy               = @UserId,
               ModifiedDate             = SYSUTCDATETIME()
         WHERE EmployeeId = @Id;

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

PRINT 'Employee.usp_Employee_Manage extended: Father''s Details, Passport, Civil ID (with document upload path columns) are now bound (GET/INSERT/UPDATE).';
GO
