/* ================================================================
   HRMS Kuwait - Employee.usp_EmployeeDependent_Manage
   ----------------------------------------------------------------
   Dependents tab of the Employee Profile screen: a spouse, children
   or other dependents registered against one employee (typically for
   health-insurance coverage). A real one-to-many child list, unlike
   Kuwait.EmployeeCompliance's 1:1 GET/UPSERT pair, so this gets
   LIST/GET/INSERT/UPDATE/DELETE - but scoped entirely by @EmployeeId,
   with no company-wide paging/search/sort, since a dependents list is
   always short and always viewed in the context of one employee.

   Static SQL throughout, same discipline as every other procedure in
   this project. GET/UPDATE/DELETE all re-check that the requested
   @DependentId actually belongs to the given @EmployeeId before acting
   on it, so a forged id from one employee's page can never read or
   modify another employee's dependent row.

   Run AFTER 13 (needs Employee.Dependents to already exist).
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeDependent_Manage]
    @Action              VARCHAR(10),
    @DependentId         BIGINT          = NULL,
    @EmployeeId          BIGINT          = NULL,

    /* ---- editable columns ---------------------------------------- */
    @FullName            NVARCHAR(150)   = NULL,
    @Relationship        NVARCHAR(30)    = NULL,
    @DateOfBirth         DATE            = NULL,
    @Gender              CHAR(1)         = NULL,
    @HasHealthInsurance  BIT             = NULL,

    /* ---- audit ----------------------------------------------------*/
    @UserId              BIGINT          = NULL,

    /* ---- outputs ----------------------------------------------------*/
    @NewId               BIGINT          = NULL OUTPUT,
    @ResultCode          VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage       NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    SELECT @ResultCode    = 'SUCCESS',
           @ResultMessage = N'',
           @NewId         = ISNULL(@DependentId, 0);

    IF @Action NOT IN ('LIST', 'GET', 'INSERT', 'UPDATE', 'DELETE')
    BEGIN
        SELECT @ResultCode    = 'INVALID_ACTION',
               @ResultMessage = N'Unsupported action.';
        RETURN;
    END;

    /* ======================= LIST ================================= */
    -- Every dependent for one employee, oldest-added first (no paging -
    -- this list is never long enough to need it).
    IF @Action = 'LIST'
    BEGIN
        SELECT  DependentId,
                EmployeeId,
                FullName,
                Relationship,
                DateOfBirth,
                Gender,
                HasHealthInsurance
        FROM    [Employee].[Dependents]
        WHERE   EmployeeId = @EmployeeId
        ORDER BY CreatedDate ASC;

        RETURN;
    END;

    /* ======================= GET =================================== */
    IF @Action = 'GET'
    BEGIN
        SELECT  DependentId,
                EmployeeId,
                FullName,
                Relationship,
                DateOfBirth,
                Gender,
                HasHealthInsurance
        FROM    [Employee].[Dependents]
        WHERE   DependentId = @DependentId
            AND EmployeeId  = @EmployeeId;

        RETURN;
    END;

    /* ======================= INSERT ================================ */
    IF @Action = 'INSERT'
    BEGIN
        IF NOT EXISTS (SELECT 1 FROM [Employee].[Employees] WHERE EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That employee no longer exists. Refresh and try again.';
            RETURN;
        END;

        INSERT INTO [Employee].[Dependents]
            (EmployeeId, FullName, Relationship, DateOfBirth, Gender, HasHealthInsurance, CreatedBy)
        VALUES
            (@EmployeeId, @FullName, @Relationship, @DateOfBirth, @Gender, ISNULL(@HasHealthInsurance, 0), @UserId);

        SET @NewId = SCOPE_IDENTITY();
        SET @ResultMessage = N'Dependent added successfully.';
        RETURN;
    END;

    /* ======================= UPDATE ================================= */
    IF @Action = 'UPDATE'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM [Employee].[Dependents]
            WHERE DependentId = @DependentId AND EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That dependent no longer exists. Refresh and try again.';
            RETURN;
        END;

        UPDATE [Employee].[Dependents]
           SET FullName            = @FullName,
               Relationship        = @Relationship,
               DateOfBirth         = @DateOfBirth,
               Gender              = @Gender,
               HasHealthInsurance  = ISNULL(@HasHealthInsurance, 0),
               ModifiedBy          = @UserId,
               ModifiedDate        = SYSUTCDATETIME()
         WHERE DependentId = @DependentId
           AND EmployeeId  = @EmployeeId;

        SET @NewId = @DependentId;
        SET @ResultMessage = N'Dependent updated successfully.';
        RETURN;
    END;

    /* ======================= DELETE ================================= */
    IF @Action = 'DELETE'
    BEGIN
        IF NOT EXISTS (
            SELECT 1 FROM [Employee].[Dependents]
            WHERE DependentId = @DependentId AND EmployeeId = @EmployeeId)
        BEGIN
            SELECT @ResultCode    = 'NOT_FOUND',
                   @ResultMessage = N'That dependent no longer exists.';
            RETURN;
        END;

        DELETE FROM [Employee].[Dependents]
         WHERE DependentId = @DependentId
           AND EmployeeId  = @EmployeeId;

        SET @ResultMessage = N'Dependent removed successfully.';
        RETURN;
    END;
END;
GO

PRINT 'Employee stored procedure created: Employee.usp_EmployeeDependent_Manage.';
GO
