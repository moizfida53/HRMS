/* ================================================================
   HRMS Kuwait - Module 4: Employee.usp_Employee_Manage
   ----------------------------------------------------------------
   One multi-action procedure for the Employee master (Personal Info
   and Employment tabs of the Employee Profile screen - both are the
   same underlying row, so both come back from a single GET). Kuwait
   Compliance is a separate 1:1 table with its own procedure
   (Kuwait.usp_EmployeeCompliance_Manage, in db/10) rather than more
   columns bolted on here, for the same reason it is a separate table.

   Follows the identical pattern as the eight Organization Setup
   procedures: LIST, GET, INSERT, UPDATE, DELETE, TOGGLE, static SQL
   throughout, CASE-expression sorting against an allowlist.

   NOTE ON @CompanyId: this is the one bug class that broke six of the
   eight Organization procedures the first time around (Msg 134,
   variable already declared). @CompanyId is declared exactly ONCE
   below, in the shared filter preamble - it is also one of the
   editable columns (every employee belongs to a company), but that
   does not get a second declaration; the INSERT/UPDATE statements
   simply reference the one @CompanyId that already exists. Verified
   by the same duplicate-parameter scan used to catch the original bug
   before this file shipped.
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
    @FirstName                  NVARCHAR(100)   = NULL,
    @MiddleName                 NVARCHAR(100)   = NULL,
    @LastName                   NVARCHAR(100)   = NULL,
    @ArabicName                 NVARCHAR(300)   = NULL,
    @Gender                     CHAR(1)         = NULL,
    @DateOfBirth                DATE            = NULL,
    @MaritalStatus              NVARCHAR(20)    = NULL,
    @NationalityCountryId       INT             = NULL,
    @MobileNumber                NVARCHAR(20)   = NULL,
    @PersonalEmail               NVARCHAR(150)  = NULL,
    @WorkEmail                   NVARCHAR(150)  = NULL,
    @Address                     NVARCHAR(500)  = NULL,
    @PhotoPath                   NVARCHAR(300)  = NULL,
    @EmergencyContactName        NVARCHAR(150)  = NULL,
    @EmergencyContactPhone       NVARCHAR(20)   = NULL,
    @EmergencyContactRelation    NVARCHAR(50)   = NULL,

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
                e.FirstName,
                e.MiddleName,
                e.LastName,
                e.ArabicName,
                e.Gender,
                e.DateOfBirth,
                e.MaritalStatus,
                e.NationalityCountryId,
                nc.CountryName                                         AS NationalityName,
                e.MobileNumber,
                e.PersonalEmail,
                e.WorkEmail,
                e.Address,
                e.PhotoPath,
                e.EmergencyContactName,
                e.EmergencyContactPhone,
                e.EmergencyContactRelation,
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
        WHERE       e.EmployeeId = @Id;

        RETURN;
    END;

    /* ======================= INSERT ================================ */
    IF @Action = 'INSERT'
    BEGIN
        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
            RETURN;
        END;

        INSERT INTO [Employee].[Employees]
            (EmployeeCode, FirstName, MiddleName, LastName, ArabicName, Gender, DateOfBirth,
             MaritalStatus, NationalityCountryId, MobileNumber, PersonalEmail, WorkEmail,
             Address, PhotoPath, EmergencyContactName, EmergencyContactPhone, EmergencyContactRelation,
             CompanyId, BranchId, DepartmentId, SectionId, PositionId, DesignationId, GradeId,
             CostCenterId, WorkLocationId, ReportingManagerId, HireDate, ProbationEndDate,
             TerminationDate, EmploymentType, EmploymentStatus, IsDeleted, CreatedBy)
        VALUES
            (@EmployeeCode, @FirstName, @MiddleName, @LastName, @ArabicName, @Gender, @DateOfBirth,
             @MaritalStatus, @NationalityCountryId, @MobileNumber, @PersonalEmail, @WorkEmail,
             @Address, @PhotoPath, @EmergencyContactName, @EmergencyContactPhone, @EmergencyContactRelation,
             @CompanyId, @BranchId, @DepartmentId, @SectionId, @PositionId, @DesignationId, @GradeId,
             @CostCenterId, @WorkLocationId, @ReportingManagerId, @HireDate, @ProbationEndDate,
             @TerminationDate, @EmploymentType, ISNULL(@EmploymentStatus, N'Active'), 0, @UserId);

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

        IF @EmployeeCode IS NOT NULL AND EXISTS (
            SELECT 1 FROM [Employee].[Employees]
            WHERE CompanyId = @CompanyId AND EmployeeCode = @EmployeeCode AND EmployeeId <> @Id)
        BEGIN
            SELECT @ResultCode    = 'DUPLICATE_CODE',
                   @ResultMessage = N'That employee code is already in use. Enter a different code.';
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
               FirstName                = @FirstName,
               MiddleName               = @MiddleName,
               LastName                 = @LastName,
               ArabicName               = @ArabicName,
               Gender                   = @Gender,
               DateOfBirth              = @DateOfBirth,
               MaritalStatus            = @MaritalStatus,
               NationalityCountryId     = @NationalityCountryId,
               MobileNumber             = @MobileNumber,
               PersonalEmail            = @PersonalEmail,
               WorkEmail                = @WorkEmail,
               Address                  = @Address,
               PhotoPath                = @PhotoPath,
               EmergencyContactName     = @EmergencyContactName,
               EmergencyContactPhone    = @EmergencyContactPhone,
               EmergencyContactRelation = @EmergencyContactRelation,
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

        DELETE FROM [Kuwait].[EmployeeCompliance] WHERE EmployeeId = @Id;
        DELETE FROM [Employee].[Employees] WHERE EmployeeId = @Id;

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

PRINT 'Employee stored procedure created: Employee.usp_Employee_Manage.';
GO
