/* =====================================================================
   95_Employee_Mandatory_Details.sql  -  HRMS: details every employee must have
   ---------------------------------------------------------------------
   Run after 94. Safe to re-run.

   A new employee may be created without these details; once created, the
   profile cannot be saved until they are filled in, and the Employees list
   shows an amber flag (with the missing fields) against each employee
   that still lacks one:
     Employment       Hire Date, Notice Period, Annual Leave, Basic Salary,
                      Bank Name, IBAN
     Kuwait Compliance Civil ID Number + Expiry, Passport Number, Issuing
                      Country + Expiry
     non-Kuwaiti only Residency Number, Residence Type, Residency Expiry,
                      Sponsor Name, Work Permit Salary, Designation (English
                      and Arabic)
   A Kuwaiti national (nationality code KW / KWT) needs no residency,
   sponsor or work permit.

   1. Employee.usp_EmployeeCompleteness - the missing fields per employee
   2. Labels (English + Arabic)
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

IF COL_LENGTH('Kuwait.EmployeeCompliance', 'WorkPermitSalary') IS NULL
   OR COL_LENGTH('Employee.Employees', 'AnnualLeaveDays') IS NULL
   OR OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
    RAISERROR (N'Run db/20 and db/82 first (this script needs the payroll and work permit fields).', 16, 1);
GO

/* ---------------------------------------------------------------------
   1. The missing fields of the employees given (CSV of ids). Returns one
      row per employee: EmployeeId, MissingCount, Missing (field keys, CSV,
      in the order of the profile).
   --------------------------------------------------------------------- */
CREATE OR ALTER PROCEDURE [Employee].[usp_EmployeeCompleteness]
    @EmployeeIds    NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH ids AS (
        SELECT DISTINCT TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) AS EmployeeId
        FROM   STRING_SPLIT(@EmployeeIds, N',')
        WHERE  TRY_CAST(LTRIM(RTRIM(value)) AS BIGINT) IS NOT NULL
    ),
    emp AS (
        SELECT  e.EmployeeId, e.HireDate, e.NoticePeriodDays, e.AnnualLeaveDays,
                p.BasicSalary, p.BankName, p.Iban,
                k.CivilIdNumber, k.CivilIdExpiryDate, k.PassportNumber, k.PassportCountryId, k.PassportExpiryDate,
                k.ResidencyNumber, k.ResidencyType, k.ResidencyExpiryDate, k.SponsorName,
                k.WorkPermitSalary, k.WorkPermitDesignation, k.WorkPermitDesignationAr,
                CASE WHEN c.CountryCode IN (N'KW', N'KWT') THEN 1 ELSE 0 END AS IsKuwaiti
        FROM    ids
        JOIN    [Employee].[Employees]          AS e ON e.EmployeeId = ids.EmployeeId AND e.Deleted = 0
        LEFT JOIN [Employee].[EmployeePayroll]  AS p ON p.EmployeeId = e.EmployeeId AND p.Deleted = 0
        LEFT JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = e.EmployeeId AND k.Deleted = 0
        LEFT JOIN [Core].[Countries]            AS c ON c.CountryId  = e.NationalityCountryId
    )
    SELECT  emp.EmployeeId,
            COUNT(m.FieldKey) AS MissingCount,
            STRING_AGG(m.FieldKey, N',') WITHIN GROUP (ORDER BY m.SortOrder) AS Missing
    FROM    emp
    OUTER APPLY (VALUES
            ( 1, N'HireDate',                CASE WHEN emp.HireDate IS NULL THEN 1 END),
            ( 2, N'NoticePeriodDays',        CASE WHEN emp.NoticePeriodDays IS NULL THEN 1 END),
            ( 3, N'AnnualLeaveDays',         CASE WHEN emp.AnnualLeaveDays IS NULL THEN 1 END),
            ( 4, N'BasicSalary',             CASE WHEN ISNULL(emp.BasicSalary, 0) <= 0 THEN 1 END),
            ( 5, N'BankName',                CASE WHEN NULLIF(LTRIM(RTRIM(emp.BankName)), N'') IS NULL THEN 1 END),
            ( 6, N'Iban',                    CASE WHEN NULLIF(LTRIM(RTRIM(emp.Iban)), N'') IS NULL THEN 1 END),
            ( 7, N'CivilIdNumber',           CASE WHEN NULLIF(LTRIM(RTRIM(emp.CivilIdNumber)), N'') IS NULL THEN 1 END),
            ( 8, N'CivilIdExpiryDate',       CASE WHEN emp.CivilIdExpiryDate IS NULL THEN 1 END),
            ( 9, N'PassportNumber',          CASE WHEN NULLIF(LTRIM(RTRIM(emp.PassportNumber)), N'') IS NULL THEN 1 END),
            (10, N'PassportCountryId',       CASE WHEN emp.PassportCountryId IS NULL THEN 1 END),
            (11, N'PassportExpiryDate',      CASE WHEN emp.PassportExpiryDate IS NULL THEN 1 END),
            (12, N'ResidencyNumber',         CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.ResidencyNumber)), N'') IS NULL THEN 1 END),
            (13, N'ResidencyType',           CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.ResidencyType)), N'') IS NULL THEN 1 END),
            (14, N'ResidencyExpiryDate',     CASE WHEN emp.IsKuwaiti = 0 AND emp.ResidencyExpiryDate IS NULL THEN 1 END),
            (15, N'SponsorName',             CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.SponsorName)), N'') IS NULL THEN 1 END),
            (16, N'WorkPermitSalary',        CASE WHEN emp.IsKuwaiti = 0 AND ISNULL(emp.WorkPermitSalary, 0) <= 0 THEN 1 END),
            (17, N'WorkPermitDesignation',   CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.WorkPermitDesignation)), N'') IS NULL THEN 1 END),
            (18, N'WorkPermitDesignationAr', CASE WHEN emp.IsKuwaiti = 0 AND NULLIF(LTRIM(RTRIM(emp.WorkPermitDesignationAr)), N'') IS NULL THEN 1 END)
        ) AS m (SortOrder, FieldKey, IsMissing)
    WHERE   m.IsMissing = 1
    GROUP BY emp.EmployeeId;
END;
GO

/* ---------------------------------------------------------------------
   2. Labels
   --------------------------------------------------------------------- */
INSERT INTO [Core].[UiLabels] (LabelKey, Module, EnglishText, ArabicText, SourceText)
SELECT s.LabelKey, s.Module, s.EnglishText, s.ArabicText, s.SourceText
FROM  (VALUES
        ('emp.missing_one', 'emp', N'1 required detail is missing', N'تفصيل إلزامي واحد ناقص', NULL),
        ('emp.missing_many', 'emp', N'{0} required details are missing', N'{0} تفاصيل إلزامية ناقصة', NULL),
        ('emp.missing_hint', 'emp', N'Fill them in to save changes to this employee.', N'أكملها لتتمكن من حفظ التغييرات على هذا الموظف.', NULL),
        ('emp.mf_hire_date', 'emp', N'Hire Date', N'تاريخ التعيين', NULL),
        ('emp.mf_notice_period', 'emp', N'Notice Period', N'فترة الإشعار', NULL),
        ('emp.mf_annual_leave', 'emp', N'Annual Leave', N'الإجازة السنوية', NULL),
        ('emp.mf_basic_salary', 'emp', N'Basic Salary', N'الراتب الأساسي', NULL),
        ('emp.mf_bank_name', 'emp', N'Bank Name', N'اسم البنك', NULL),
        ('emp.mf_iban', 'emp', N'IBAN', N'رقم الآيبان', NULL),
        ('emp.mf_civil_id', 'emp', N'Civil ID Number', N'رقم البطاقة المدنية', NULL),
        ('emp.mf_civil_id_expiry', 'emp', N'Civil ID Expiry', N'انتهاء البطاقة المدنية', NULL),
        ('emp.mf_passport_no', 'emp', N'Passport Number', N'رقم الجواز', NULL),
        ('emp.mf_passport_country', 'emp', N'Passport Issuing Country', N'بلد إصدار الجواز', NULL),
        ('emp.mf_passport_expiry', 'emp', N'Passport Expiry', N'انتهاء الجواز', NULL),
        ('emp.mf_residency_no', 'emp', N'Residency Number', N'رقم الإقامة', NULL),
        ('emp.mf_residency_type', 'emp', N'Residence Type', N'نوع الإقامة', NULL),
        ('emp.mf_residency_expiry', 'emp', N'Residency Expiry', N'انتهاء الإقامة', NULL),
        ('emp.mf_sponsor', 'emp', N'Sponsor Name', N'اسم الكفيل', NULL),
        ('emp.mf_wp_salary', 'emp', N'Work Permit Salary', N'راتب إذن العمل', NULL),
        ('emp.mf_wp_designation', 'emp', N'Designation (English)', N'المسمى الوظيفي (إنجليزي)', NULL),
        ('emp.mf_wp_designation_ar', 'emp', N'Designation (Arabic)', N'المسمى الوظيفي (عربي)', NULL)
      ) AS s (LabelKey, Module, EnglishText, ArabicText, SourceText)
WHERE NOT EXISTS (SELECT 1 FROM [Core].[UiLabels] AS l WHERE l.LabelKey = s.LabelKey COLLATE DATABASE_DEFAULT AND l.Deleted = 0);

DECLARE @LabelsInserted INT = @@ROWCOUNT;
PRINT CONCAT(N'Mandatory details labels inserted: ', @LabelsInserted);
GO
