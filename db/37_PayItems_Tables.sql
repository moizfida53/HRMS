/* =====================================================================
   37_PayItems_Tables.sql  -  HRMS Payroll: Pay Items (Phase 2b)
   ---------------------------------------------------------------------
   Run after 34 / 35. Idempotent.

   Payroll.EmployeePayItems  (db/34) gets the approval fields:
        ApprovalLevel   0 = waiting for level 1, 1 = HR approved, 2 = fully approved
        SubmittedBy/At  who sent the item for approval (cannot approve it)
        ReplacesItemId  a salary change replaces this earlier salary item
   Payroll.EmployeePayItemHistory  every create / change / approval / end /
        delete of a pay item (who, when, old and new amount, comment)

   Permissions   PAYROLL_ITEM_VIEW / CREATE / EDIT / DELETE (to SYSADMIN).
                 Approving a salary or loan item uses the payroll approval
                 permissions PAYROLL_RUN_APPROVE_HR and _FINANCE.

   Standing rule: nothing is physically deleted (Deleted bit).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[EmployeePayItems]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run script 34 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ---------------- 1. approval fields ---------------- */
IF COL_LENGTH(N'Payroll.EmployeePayItems', N'ApprovalLevel') IS NULL
    ALTER TABLE [Payroll].[EmployeePayItems] ADD ApprovalLevel TINYINT NOT NULL
        CONSTRAINT DF_EmployeePayItems_ApprovalLevel DEFAULT (0);
GO
IF COL_LENGTH(N'Payroll.EmployeePayItems', N'SubmittedBy') IS NULL
    ALTER TABLE [Payroll].[EmployeePayItems] ADD SubmittedBy BIGINT NULL, SubmittedDate DATETIME2(0) NULL;
GO
IF COL_LENGTH(N'Payroll.EmployeePayItems', N'ReplacesItemId') IS NULL
    ALTER TABLE [Payroll].[EmployeePayItems] ADD ReplacesItemId BIGINT NULL;
GO
IF NOT EXISTS (SELECT 1 FROM sys.foreign_keys WHERE name = N'FK_EmployeePayItems_Replaces')
    ALTER TABLE [Payroll].[EmployeePayItems] ADD CONSTRAINT FK_EmployeePayItems_Replaces
        FOREIGN KEY (ReplacesItemId) REFERENCES [Payroll].[EmployeePayItems](EmployeePayItemId);
GO
IF NOT EXISTS (SELECT 1 FROM sys.check_constraints WHERE name = N'CK_EmployeePayItems_ApprovalLevel')
    ALTER TABLE [Payroll].[EmployeePayItems] ADD CONSTRAINT CK_EmployeePayItems_ApprovalLevel CHECK (ApprovalLevel IN (0, 1, 2));
GO

/* the items already active before this script (migrated profile salary, run lines) are fully approved */
UPDATE [Payroll].[EmployeePayItems] SET ApprovalLevel = 2 WHERE Status = 'ACTIVE' AND ApprovalLevel = 0;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_EmployeePayItems_Company_Status' AND object_id = OBJECT_ID(N'[Payroll].[EmployeePayItems]'))
    CREATE INDEX IX_EmployeePayItems_Company_Status ON [Payroll].[EmployeePayItems](CompanyId, Status, EmployeeId)
        INCLUDE (PayComponentId, AppliesMode, StartMonth, EndMonth) WHERE Deleted = 0 AND PayrollRunId IS NULL;
GO

/* ---------------- 2. history ---------------- */
IF OBJECT_ID(N'[Payroll].[EmployeePayItemHistory]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[EmployeePayItemHistory](
        PayItemHistoryId    BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_EmployeePayItemHistory PRIMARY KEY,
        EmployeePayItemId   BIGINT         NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        ActionCode          VARCHAR(20)    NOT NULL,   -- CREATED, CHANGED, REVISED, SUBMITTED, APPROVED, REJECTED, ENDED, DELETED
        ApprovalLevel       TINYINT        NULL,
        OldAmount           DECIMAL(12,3)  NULL,
        NewAmount           DECIMAL(12,3)  NULL,
        Comment             NVARCHAR(500)  NULL,
        ActionBy            BIGINT         NULL,
        ActionDate          DATETIME2(0)   NOT NULL CONSTRAINT DF_EmployeePayItemHistory_Date DEFAULT (SYSUTCDATETIME()),
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_EmployeePayItemHistory_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,
        CONSTRAINT FK_EmployeePayItemHistory_Item FOREIGN KEY (EmployeePayItemId) REFERENCES [Payroll].[EmployeePayItems](EmployeePayItemId),
        CONSTRAINT CK_EmployeePayItemHistory_Action CHECK (ActionCode IN ('CREATED','CHANGED','REVISED','SUBMITTED','APPROVED','REJECTED','ENDED','DELETED'))
    );
    CREATE INDEX IX_EmployeePayItemHistory_Item ON [Payroll].[EmployeePayItemHistory](EmployeePayItemId, ActionDate) WHERE Deleted = 0;
END;
GO

IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'EmployeePayItemHistory';
GO

/* ---------------- 3. permissions ---------------- */
;WITH p(PermissionCode, Module, [Action]) AS (
    SELECT * FROM (VALUES
        ('PAYROLL_ITEM_VIEW',   'PayrollItem', 'View'),
        ('PAYROLL_ITEM_CREATE', 'PayrollItem', 'Create'),
        ('PAYROLL_ITEM_EDIT',   'PayrollItem', 'Edit'),
        ('PAYROLL_ITEM_DELETE', 'PayrollItem', 'Delete')) AS x(a, b, c)
)
INSERT INTO [Security].[Permissions] (PermissionCode, Module, [Action])
SELECT p.PermissionCode, p.Module, p.[Action]
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[Permissions] AS e WHERE e.PermissionCode = p.PermissionCode AND e.Deleted = 0);
GO

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] AS r
JOIN   [Security].[Permissions] AS p ON p.PermissionCode LIKE 'PAYROLL[_]ITEM[_]%'
WHERE  r.RoleCode = N'SYSADMIN'
  AND  p.Deleted = 0 AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

SET NOEXEC OFF;
GO
PRINT N'db/37 applied: pay item approval fields, history table, PAYROLL_ITEM_* permissions.';
GO
