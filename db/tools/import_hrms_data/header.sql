/* =====================================================================
   92_Import_HRMS_Data.sql  -  HRMS: load the companies and employees
   ---------------------------------------------------------------------
   Generated from HRMS_Data.xlsx. Run AFTER db/91 (the reset) on a fresh
   deployment - or on its own: it is RE-RUNNABLE (companies are matched
   on their code, documents on company + type, vehicles on the plate,
   employees on company + civil ID), so running it twice never creates
   duplicates; a second run updates the rows from the sheet again.

   WHAT IS LOADED, FROM WHICH TAB
     Company tabs (6)        Core.Companies - English name in CompanyName,
                             the Arabic licence name in LegalName; country
                             Kuwait, currency KWD; a default Monthly payroll
                             calendar; the default pay components and leave
                             types (the app's own seed procedures)
       licence rows          Documents.OrganizationDocuments (Workforce >
                             Organizations): number, issuing authority,
                             issue / expiry date, notes. Missing document
                             types and three issuing authorities are added.
       vehicle rows          Assets.Assets (Workforce > Assets): Cars, Motor
                             Bikes, Trucks & Pickups (new type); plate =
                             licence number, expiry = registration expiry,
                             the holder named in the sheet goes to Notes
     "Employee Data (3)"     Employee.Employees - code, names (English split
     + "بيانات العمالة"       into first / middle / last; Arabic name),
       (joined on civil ID)  gender, date of birth, nationality, company
                             (= the licence company, see below), designation
                             (= the work-permit job), Active / Full-Time
                             Kuwait.EmployeeCompliance - civil ID + expiry,
                             residency expiry, passport + expiry, sponsor
                             (the licence company), work permit salary and
                             job title (English + Arabic)
                             Employee.EmployeePayroll - basic salary

   DECISIONS MADE FOR YOU (change them in the data lists below if wrong)
     - Company of an employee = the licence ("الترخيص") company: that is
       the legal employer / sponsor that pays the salary. 8 employees
       licensed to RAND but working at Falafel Hamada get a work location
       "Falafel Hamada" in RAND.
     - Employees with no Emp Code in the sheet get a new code per company:
       RAND 2101.., Falafel Hamada 1101.., 4 MG 4001.., IGM 3001..,
       Buruj 5001.., Zafir 6001.. (listed at the end of the run).
     - Designation (blank in the sheet) = the job title of the work
       permit, translated to English (Arabic kept).
     - "Basic Salary" of Employee Data = the contract salary (payroll);
       "الراتب" of بيانات العمالة = the work permit salary.
     - "Expiry Date Civil ID" = civil ID expiry AND residency expiry.
     - Not in the sheet, left blank: hire date, marital status, mobile,
       department, allowances, bank, work permit number / expiry;
       nationality for 19 employees.
     - The passport status (✓ / X) and the notes column have no field in
       the app - they are listed at the end of the run to act on.

   HOW TO RUN
     1. Take a backup. Run db/86-90 first if not done yet (the work permit
        fields are from db/82).
     2. Run this whole file at once (one batch). Any error and nothing is
        saved.
   ===================================================================== */
SET NOCOUNT ON;
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @UserId BIGINT = NULL;   -- optional: Security.Users.UserId stamped as CreatedBy

IF COL_LENGTH('Kuwait.EmployeeCompliance', 'WorkPermitSalary') IS NULL
   OR OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
   OR OBJECT_ID(N'[Documents].[IssuingAuthorities]', N'U') IS NULL
   OR OBJECT_ID(N'[Assets].[AssetTypes]', N'U') IS NULL
BEGIN
    RAISERROR (N'STOPPED - run the numbered scripts up to db/90 first (this script needs db/20, db/75, db/82 and db/84).', 16, 1);
    RETURN;
END;

