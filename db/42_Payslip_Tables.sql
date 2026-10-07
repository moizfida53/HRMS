/* =====================================================================
   42_Payslip_Tables.sql  -  HRMS Payroll: Payslips
   ---------------------------------------------------------------------
   Run after 34 / 35 (payroll runs). Idempotent (every object is guarded)
   - safe to re-run. Then run 43 (procedures) and 44 (labels).

   What a payslip is
     The payslip of an employee for a CLOSED payroll. Its figures are not
     copied: they are the payroll's own lines (Payroll.PayrollRunLines) and
     employee snapshot (Payroll.PayrollRunEmployees), so a payslip always
     shows exactly what the payroll paid. This table records that the
     payslip was generated (number, language, by whom, the net it showed)
     and its email delivery.
       PayslipNo   <RunCode>-<EmployeeNo>, e.g. DTC-2026-09-01-E1001
       Template    BILINGUAL (English + Arabic, default) / ENGLISH / ARABIC
       NetPay      the net when it was generated - when a payroll is
                   reopened, recalculated and closed again, a payslip whose
                   net no longer matches is shown as "outdated" until it is
                   generated again
       Email       NOT_SENT -> QUEUED -> SENDING -> SENT or FAILED.
                   The email carries no salary figures: it tells the
                   employee the payslip is ready and links to My Payslips.

   Tables
     Payroll.Payslips   one row per employee and payroll

   Also
     Permissions PAYROLL_SLIP_VIEW / _GENERATE / _EMAIL granted to SYSADMIN.
     An employee always sees their own payslips (My Payslips) - no
     permission needed, only a user linked to the employee
     (Security.Users.EmployeeId).

   Standing rule: nothing is ever physically deleted - every table carries
   Deleted / DeletedBy / DeletedDate (db/28 adds the delete guard trigger).
   ===================================================================== */
SET NOCOUNT ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF OBJECT_ID(N'[Payroll].[PayrollRuns]', N'U') IS NULL OR OBJECT_ID(N'[Payroll].[PayrollRunEmployees]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run scripts 34 and 35 (payroll runs) before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

/* ------------------------------------------------------------------
   1. Payroll.Payslips
   ------------------------------------------------------------------ */
IF OBJECT_ID(N'[Payroll].[Payslips]', N'U') IS NULL
BEGIN
    CREATE TABLE [Payroll].[Payslips](
        PayslipId           BIGINT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Payslips PRIMARY KEY,
        PayrollRunId        BIGINT         NOT NULL,
        RunEmployeeId       BIGINT         NOT NULL,
        EmployeeId          BIGINT         NOT NULL,
        CompanyId           INT            NOT NULL,
        PayslipNo           NVARCHAR(70)   NOT NULL,
        Template            VARCHAR(10)    NOT NULL CONSTRAINT DF_Payslips_Template DEFAULT ('BILINGUAL'),
        NetPay              DECIMAL(12,3)  NOT NULL CONSTRAINT DF_Payslips_NetPay DEFAULT (0),
        GenerationCount     SMALLINT       NOT NULL CONSTRAINT DF_Payslips_GenerationCount DEFAULT (1),
        GeneratedBy         BIGINT         NULL,
        GeneratedDate       DATETIME2(0)   NOT NULL CONSTRAINT DF_Payslips_GeneratedDate DEFAULT (SYSUTCDATETIME()),

        /* email delivery */
        EmailTo             NVARCHAR(150)  NULL,
        EmailStatus         VARCHAR(10)    NOT NULL CONSTRAINT DF_Payslips_EmailStatus DEFAULT ('NOT_SENT'),
        EmailQueuedBy       BIGINT         NULL,
        EmailQueuedDate     DATETIME2(0)   NULL,
        EmailClaimedDate    DATETIME2(0)   NULL,
        EmailSentDate       DATETIME2(0)   NULL,
        EmailAttempts       TINYINT        NOT NULL CONSTRAINT DF_Payslips_EmailAttempts DEFAULT (0),
        EmailError          NVARCHAR(400)  NULL,

        /* opened by the employee in My Payslips */
        FirstViewedDate     DATETIME2(0)   NULL,
        ViewCount           INT            NOT NULL CONSTRAINT DF_Payslips_ViewCount DEFAULT (0),

        CreatedDate         DATETIME2(0)   NOT NULL CONSTRAINT DF_Payslips_CreatedDate DEFAULT (SYSUTCDATETIME()),
        ModifiedBy          BIGINT         NULL,
        ModifiedDate        DATETIME2(0)   NULL,
        Deleted             BIT            NOT NULL CONSTRAINT DF_Payroll_Payslips_Deleted DEFAULT (0),
        DeletedBy           BIGINT         NULL,
        DeletedDate         DATETIME2(7)   NULL,

        CONSTRAINT FK_Payslips_Run         FOREIGN KEY (PayrollRunId)  REFERENCES [Payroll].[PayrollRuns](PayrollRunId),
        CONSTRAINT FK_Payslips_RunEmployee FOREIGN KEY (RunEmployeeId) REFERENCES [Payroll].[PayrollRunEmployees](RunEmployeeId),
        CONSTRAINT FK_Payslips_Employee    FOREIGN KEY (EmployeeId)    REFERENCES [Employee].[Employees](EmployeeId),
        CONSTRAINT FK_Payslips_Company     FOREIGN KEY (CompanyId)     REFERENCES [Core].[Companies](CompanyId),
        CONSTRAINT CK_Payslips_Template    CHECK (Template IN ('BILINGUAL', 'ENGLISH', 'ARABIC')),
        CONSTRAINT CK_Payslips_EmailStatus CHECK (EmailStatus IN ('NOT_SENT', 'QUEUED', 'SENDING', 'SENT', 'FAILED'))
    );

    /* one payslip per employee and payroll */
    CREATE UNIQUE NONCLUSTERED INDEX UX_Payslips_RunEmployee
        ON [Payroll].[Payslips](PayrollRunId, EmployeeId) WHERE Deleted = 0;
    /* My Payslips */
    CREATE INDEX IX_Payslips_Employee
        ON [Payroll].[Payslips](EmployeeId, PayrollRunId) INCLUDE (NetPay, EmailStatus) WHERE Deleted = 0;
    /* the email sender's queue */
    CREATE INDEX IX_Payslips_EmailQueue
        ON [Payroll].[Payslips](EmailStatus, EmailQueuedDate) WHERE Deleted = 0 AND EmailStatus IN ('QUEUED', 'SENDING');
END;
GO

/* The delete guard of db/28 (INSTEAD OF DELETE -> Deleted = 1) for the new
   table - the database trigger normally does this on CREATE TABLE already. */
IF OBJECT_ID(N'[Core].[usp_SoftDelete_Apply]', N'P') IS NOT NULL
    EXEC [Core].[usp_SoftDelete_Apply] @SchemaName = N'Payroll', @TableName = N'Payslips';
GO

/* ------------------------------------------------------------------
   2. Permissions (granted to SYSADMIN, like db/32 and db/34)
      PAYROLL_SLIP_VIEW       see every employee's payslips
      PAYROLL_SLIP_GENERATE   generate payslips of a closed payroll
      PAYROLL_SLIP_EMAIL      email payslips, resend
   ------------------------------------------------------------------ */
;WITH p(PermissionCode, Module, [Action]) AS (
    SELECT * FROM (VALUES
        ('PAYROLL_SLIP_VIEW',     'Payslip', 'View'),
        ('PAYROLL_SLIP_GENERATE', 'Payslip', 'Generate'),
        ('PAYROLL_SLIP_EMAIL',    'Payslip', 'Email')) AS x(a, b, c)
)
INSERT INTO [Security].[Permissions] (PermissionCode, Module, [Action])
SELECT p.PermissionCode, p.Module, p.[Action]
FROM   p
WHERE  NOT EXISTS (SELECT 1 FROM [Security].[Permissions] AS e WHERE e.PermissionCode = p.PermissionCode AND e.Deleted = 0);
GO

INSERT INTO [Security].[RolePermissions] (RoleId, PermissionId)
SELECT r.RoleId, p.PermissionId
FROM   [Security].[Roles] AS r
JOIN   [Security].[Permissions] AS p ON p.PermissionCode LIKE 'PAYROLL[_]SLIP[_]%'
WHERE  r.RoleCode = N'SYSADMIN'
  AND  p.Deleted = 0 AND r.Deleted = 0
  AND  NOT EXISTS (SELECT 1 FROM [Security].[RolePermissions] AS rp WHERE rp.RoleId = r.RoleId AND rp.PermissionId = p.PermissionId);
GO

SET NOEXEC OFF;
GO
PRINT N'db/42 applied: Payroll.Payslips, PAYROLL_SLIP_* permissions. Run db/43 and db/44 next.';
GO
