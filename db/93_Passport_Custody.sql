/* =====================================================================
   93_Passport_Custody.sql  -  HRMS: Passport In / Out
   ---------------------------------------------------------------------
   Run after 92. Safe to re-run (IF NOT EXISTS / CREATE OR ALTER).

   Where an employee's passport is - with the COMPANY or with the
   EMPLOYEE - and every hand-over, kept as a log (Workforce > Employees >
   Actions > Passport In / Out).

     Employee.PassportMovements   one row per hand-over: who holds the
                                  passport from that day (C = company,
                                  E = employee), the date, the passport
                                  number at the time, remarks, who entered it
     Employee.usp_PassportCustody_Manage
                                  STATUS  the holder now (= the last row)
                                  LOG     every hand-over, newest first
                                  SAVE    record a hand-over
     Rights  EMPLOYEE_PASSPORT_VIEW  see the holder and the log
             EMPLOYEE_PASSPORT_EDIT  record a hand-over
             (first run: given to the roles with the Kuwait Compliance
              rights - view -> view, edit -> edit - and System Administrator)

   Nothing is physically deleted (db/28, db/77).
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'[Employee].[PassportMovements]', N'U') IS NULL
BEGIN
    CREATE TABLE [Employee].[PassportMovements](
        MovementId      BIGINT IDENTITY(1, 1) NOT NULL CONSTRAINT PK_PassportMovements PRIMARY KEY,
        EmployeeId      BIGINT         NOT NULL,
        CompanyId       INT            NOT NULL,
        HeldBy          CHAR(1)        NOT NULL,          -- C = company, E = employee (from MovementDate on)
        MovementDate    DATE           NOT NULL,
        PassportNumber  NVARCHAR(30)   NULL,
        Remarks         NVARCHAR(300)  NULL,
        CreatedBy       BIGINT         NULL,
        CreatedDate     DATETIME2(0)   NOT NULL CONSTRAINT DF_PassportMovements_Created DEFAULT (SYSUTCDATETIME()),
        ModifiedBy      BIGINT         NULL,
        ModifiedDate    DATETIME2(0)   NULL,
        Deleted         BIT            NOT NULL CONSTRAINT DF_PassportMovements_Deleted DEFAULT (0),
        DeletedBy       BIGINT         NULL,
        DeletedDate     DATETIME2(0)   NULL,
        CONSTRAINT FK_PassportMovements_Employee FOREIGN KEY (EmployeeId) REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_PassportMovements_Company  FOREIGN KEY (CompanyId)  REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_PassportMovements_HeldBy   CHECK (HeldBy IN ('C', 'E'))
    );
    EXEC (N'CREATE NONCLUSTERED INDEX IX_PassportMovements_Employee ON [Employee].[PassportMovements] (EmployeeId, MovementDate DESC, MovementId DESC) INCLUDE (HeldBy) WHERE Deleted = 0;');
    PRINT N'Created [Employee].[PassportMovements].';
END
GO

/* ------------------------------------------------------------------
   Employee.usp_PassportCustody_Manage
   ------------------------------------------------------------------ */
CREATE OR ALTER PROCEDURE [Employee].[usp_PassportCustody_Manage]
    @Action         VARCHAR(10),
    @EmployeeId     BIGINT          = NULL,
    @HeldBy         CHAR(1)         = NULL,
    @MovementDate   DATE            = NULL,
    @Remarks        NVARCHAR(300)   = NULL,
    @CompanyId      INT             = NULL,     -- the user's own company (company users)
    @CompanyIds     NVARCHAR(2000)  = NULL,     -- the top-bar company filter (CSV)
    @UserId         BIGINT          = NULL,

    @TotalCount     INT             = NULL OUTPUT,
    @NewId          BIGINT          = NULL OUTPUT,
    @ResultCode     VARCHAR(40)     = NULL OUTPUT,
    @ResultMessage  NVARCHAR(400)   = NULL OUTPUT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SELECT @ResultCode = 'SUCCESS', @ResultMessage = N'', @NewId = 0, @TotalCount = 0;
    DECLARE @Csv NVARCHAR(2002) = N',' + REPLACE(@CompanyIds, N' ', N'') + N',';
    DECLARE @Today DATE = CAST(SYSDATETIME() AS DATE);
    SET @Remarks = NULLIF(LTRIM(RTRIM(@Remarks)), N'');

    /* the employee, inside the user's companies */
    DECLARE @eCo INT, @eCode NVARCHAR(30), @eName NVARCHAR(300), @eNameAr NVARCHAR(300), @passport NVARCHAR(30), @passportExpiry DATE;
    SELECT  @eCo = e.CompanyId, @eCode = ISNULL(e.EmployeeCode, e.EmployeeNo),
            @eName = LTRIM(RTRIM(CONCAT(e.FirstName, N' ', e.LastName))), @eNameAr = e.ArabicName,
            @passport = NULLIF(LTRIM(RTRIM(k.PassportNumber)), N''), @passportExpiry = k.PassportExpiryDate
    FROM    [Employee].[Employees] AS e
    LEFT JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = e.EmployeeId
    WHERE   e.EmployeeId = @EmployeeId AND e.Deleted = 0 AND e.IsDeleted = 0
      AND   (@CompanyId IS NULL OR e.CompanyId = @CompanyId)
      AND   (@CompanyIds IS NULL OR CHARINDEX(N',' + CAST(e.CompanyId AS NVARCHAR(12)) + N',', @Csv) > 0);

    IF @eCo IS NULL
    BEGIN SELECT @ResultCode = 'NOT_FOUND', @ResultMessage = N'That employee was not found.'; RETURN; END;

    /* the holder now = the last hand-over */
    DECLARE @curHeldBy CHAR(1), @curDate DATE;
    SELECT TOP (1) @curHeldBy = m.HeldBy, @curDate = m.MovementDate
    FROM   [Employee].[PassportMovements] AS m
    WHERE  m.EmployeeId = @EmployeeId AND m.Deleted = 0
    ORDER BY m.MovementDate DESC, m.MovementId DESC;

    IF @Action = 'STATUS'
    BEGIN
        SELECT  @EmployeeId AS EmployeeId, @eCode AS EmployeeCode, @eName AS EmployeeName, @eNameAr AS EmployeeArabicName,
                @passport AS PassportNumber, @passportExpiry AS PassportExpiryDate,
                @curHeldBy AS HeldBy, @curDate AS HeldSince,
                (SELECT COUNT(1) FROM [Employee].[PassportMovements] WHERE EmployeeId = @EmployeeId AND Deleted = 0) AS Movements;
        RETURN;
    END;

    IF @Action = 'LOG'
    BEGIN
        SELECT  m.MovementId, m.MovementDate, m.HeldBy, m.PassportNumber, m.Remarks,
                u.Username AS CreatedByName, m.CreatedDate
        FROM    [Employee].[PassportMovements] AS m
        LEFT JOIN [Security].[Users] AS u ON u.UserId = m.CreatedBy
        WHERE   m.EmployeeId = @EmployeeId AND m.Deleted = 0
        ORDER BY m.MovementDate DESC, m.MovementId DESC;
        SET @TotalCount = @@ROWCOUNT;
        RETURN;
    END;

    IF @Action = 'SAVE'
    BEGIN
        IF @HeldBy IS NULL OR @HeldBy NOT IN ('C', 'E')
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Choose who has the passport.'; RETURN; END;
        IF @passport IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the passport number on the Kuwait Compliance tab first.'; RETURN; END;
        IF @MovementDate IS NULL
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Enter the date.'; RETURN; END;
        IF @MovementDate > @Today
        BEGIN SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'The date cannot be in the future.'; RETURN; END;
        IF @curHeldBy = @HeldBy
        BEGIN
            SELECT @ResultCode = 'VALIDATION',
                   @ResultMessage = CASE WHEN @HeldBy = 'C' THEN N'The passport is already with the company.'
                                         ELSE N'The passport is already with the employee.' END;
            RETURN;
        END;
        IF @curDate IS NOT NULL AND @MovementDate < @curDate
        BEGIN
            SELECT @ResultCode = 'VALIDATION',
                   @ResultMessage = CONCAT(N'The date cannot be before the last hand-over (', FORMAT(@curDate, 'dd/MM/yyyy', 'en-US'), N').');
            RETURN;
        END;

        INSERT INTO [Employee].[PassportMovements] (EmployeeId, CompanyId, HeldBy, MovementDate, PassportNumber, Remarks, CreatedBy)
        VALUES (@EmployeeId, @eCo, @HeldBy, @MovementDate, @passport, @Remarks, @UserId);
        SELECT @NewId = SCOPE_IDENTITY(),
               @ResultMessage = CASE WHEN @HeldBy = 'C' THEN N'Passport received by the company.'
                                     ELSE N'Passport handed to the employee.' END;
        RETURN;
    END;

    SELECT @ResultCode = 'VALIDATION', @ResultMessage = N'Unknown action.';
END;
GO

/* ------------------------------------------------------------------
   Rights (first run): view with the Kuwait Compliance view / edit
   rights, edit with Kuwait Compliance edit; System Administrator
   ------------------------------------------------------------------ */
IF OBJECT_ID('tempdb..#Codes') IS NOT NULL DROP TABLE #Codes;
CREATE TABLE #Codes (PermissionCode VARCHAR(60) COLLATE DATABASE_DEFAULT PRIMARY KEY, Module VARCHAR(30) COLLATE DATABASE_DEFAULT,
                     Action VARCHAR(30) COLLATE DATABASE_DEFAULT, GrantWith1 VARCHAR(60) COLLATE DATABASE_DEFAULT,
                     GrantWith2 VARCHAR(60) COLLATE DATABASE_DEFAULT NULL, IsNew BIT NOT NULL DEFAULT (0));
INSERT INTO #Codes (PermissionCode, Module, Action, GrantWith1, GrantWith2) VALUES
    ('EMPLOYEE_PASSPORT_VIEW', 'Employee', 'PassportView', 'EMPLOYEE_COMPLIANCE_VIEW', 'EMPLOYEE_COMPLIANCE_EDIT'),
    ('EMPLOYEE_PASSPORT_EDIT', 'Employee', 'PassportEdit', 'EMPLOYEE_COMPLIANCE_EDIT', NULL);

UPDATE c SET IsNew = 1 FROM #Codes c
WHERE NOT EXISTS (SELECT 1 FROM [Security].[Permissions] p WHERE p.PermissionCode = c.PermissionCode AND p.Deleted = 0);

INSERT INTO [Security].[Permissions] (PermissionCode, Module, Action)
SELECT c.PermissionCode, c.Module, c.Action FROM #Codes c WHERE c.IsNew = 1;

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT DISTINCT r.RoleId, p.PermissionId
FROM   #Codes c
JOIN   [Security].[Permissions] p ON p.PermissionCode = c.PermissionCode AND p.Deleted = 0
JOIN   [Security].[Roles] r ON r.Deleted = 0
WHERE  c.IsNew = 1
  AND (r.RoleCode = N'SYSADMIN'
       OR EXISTS (SELECT 1 FROM [Security].[RolePermissions] rp JOIN [Security].[Permissions] g ON g.PermissionId = rp.PermissionId
                  WHERE rp.RoleId = r.RoleId AND rp.Deleted = 0 AND g.Deleted = 0 AND g.PermissionCode IN (c.GrantWith1, c.GrantWith2)))
  AND NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] x WHERE x.RoleId = r.RoleId AND x.PermissionId = p.PermissionId AND x.Deleted = 0);

DECLARE @CodesCreated INT = (SELECT COUNT(1) FROM #Codes WHERE IsNew = 1);
PRINT CONCAT(N'Passport In / Out rights created: ', @CodesCreated, N' (users see them after signing in again).');
DROP TABLE #Codes;
GO
