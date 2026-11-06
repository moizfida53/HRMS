/* =====================================================================
   120_Create_Payroll_Summary_WPS.sql  -  Create Payroll summary: work permit figures
   ---------------------------------------------------------------------
   Run after db/115. Safe to re-run. Adds Payroll.usp_Collection_RunPreview:
   for one payroll (any stage, drafts included) the two figures the
   "Ready to create the payroll" summary of Create Payroll shows:

     Work Permit Payable      the Work Permit Salary of the employees in the
                              payroll (what the Ministry Payroll transfers)
     Total Collection Amount  for each employee, the Work Permit Salary less
                              the Gross Monthly (Basic + Allowances) when
                              that is above zero - a preview: the collections
                              are recorded when the payroll is approved (db/119)
   ===================================================================== */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

IF COL_LENGTH(N'Kuwait.EmployeeCompliance', N'WorkPermitSalary') IS NULL OR OBJECT_ID(N'[Payroll].[PayrollRunEmployees]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run db/34 and db/82 before this script.', 16, 1);
    SET NOEXEC ON;
END;
GO

CREATE OR ALTER PROCEDURE [Payroll].[usp_Collection_RunPreview]
    @RunId  BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT  ISNULL(SUM(ISNULL(k.WorkPermitSalary, 0)), 0)                                         AS WorkPermitPayable,
            ISNULL(SUM(CASE WHEN k.WorkPermitSalary > 0 THEN 1 ELSE 0 END), 0)                     AS WorkPermitCount,
            ISNULL(SUM(CASE WHEN ISNULL(ep.BasicSalary, 0) > 0 AND k.WorkPermitSalary > g.Gross
                            THEN k.WorkPermitSalary - g.Gross END), 0)                             AS CollectionAmount,
            ISNULL(SUM(CASE WHEN ISNULL(ep.BasicSalary, 0) > 0 AND k.WorkPermitSalary > g.Gross
                            THEN 1 ELSE 0 END), 0)                                                 AS CollectionCount
    FROM    [Payroll].[PayrollRunEmployees] AS re
    LEFT JOIN [Kuwait].[EmployeeCompliance] AS k  ON k.EmployeeId = re.EmployeeId AND k.Deleted = 0
    LEFT JOIN [Employee].[EmployeePayroll]  AS ep ON ep.EmployeeId = re.EmployeeId AND ep.Deleted = 0
    CROSS APPLY (SELECT CAST(ISNULL(ep.BasicSalary, 0) + ISNULL(ep.Allowances, 0) AS DECIMAL(12,3)) AS Gross) AS g
    WHERE   re.PayrollRunId = @RunId AND re.Deleted = 0 AND re.IsExcluded = 0;
END;
GO

INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('pr.wps_payable', 'pr', N'Work Permit Payable', N'رواتب إذن العمل المستحقة', NULL),
        ('pr.wps_payable_note_0', 'pr', N'KWD · work permit salary of {0} employees', N'د.ك · راتب إذن العمل لـ {0} موظفين', NULL),
        ('pr.total_collection', 'pr', N'Total Collection Amount', N'إجمالي مبلغ التحصيل', NULL),
        ('pr.total_collection_note_0', 'pr', N'KWD · {0} employees · recorded on approval', N'د.ك · {0} موظفين · يُسجَّل عند الاعتماد', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);
PRINT CONCAT(N'Create payroll summary labels inserted: ', @@ROWCOUNT);
GO
