/* ================================================================
   HRMS Kuwait - Industry-standard Organization Setup seed data
   ----------------------------------------------------------------
   Seeds one company's Branches, Cost Centers, Departments, Sections,
   Designations, Job Positions and Locations with a realistic,
   generic corporate structure - the kind of directory a mid-size
   Kuwait company (services, trading, contracting or light industry)
   actually runs, covering both office staff and the blue-collar
   Designations (Driver, Storekeeper, Security Guard, Cleaner, ...)
   that Kuwait Civil ID / work-permit paperwork commonly uses.

   Everything here is starting-point data, not a fixed requirement -
   edit the VALUES lists freely before running, or after, through the
   Organization Setup screens themselves (this script only seeds
   rows that do not already exist, so re-editing through the UI is
   always safe and will not be reverted by re-running this script).

   PURELY ADDITIVE and IDEMPOTENT, same convention as every other
   script in this folder: every INSERT is guarded by
   `WHERE NOT EXISTS (...)` against the same unique constraint the
   application itself enforces, so running this script twice (or
   against a company that already has some of this data) only adds
   what is missing.

   HOW TO USE
   ----------
   1. Run this AFTER 01-11 and after you have created at least one
      row in Core.Companies (through the Organization Setup screen,
      or your own INSERT) - this script seeds a company's org
      structure, it does not create the company itself.
   2. If you have more than one company, set @CompanyCode below to
      the CompanyCode of the one you want to seed. If you have
      exactly one company, you can leave it NULL and the script will
      find it automatically.
   3. Run the whole script in one go (it is one batch after the
      initial SET/GO - every INSERT below shares the @CompanyId
      variable, so do not split it with extra GO statements).

   Column lists below match [Core].[usp_*_Manage]'s own INSERT
   statements in db/03_Organization_StoredProcedures.sql exactly -
   this script writes to the same tables through plain INSERTs
   (seed data, not a user action), not through the stored procedures.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
GO

/* ================================================================
   0. Pick the company to seed
================================================================ */
DECLARE @CompanyCode NVARCHAR(30) = NULL;  -- <-- set this if you have more than one company
DECLARE @CompanyId   INT;

IF @CompanyCode IS NOT NULL
    SELECT @CompanyId = CompanyId FROM [Core].[Companies] WHERE CompanyCode = @CompanyCode;
ELSE IF (SELECT COUNT(1) FROM [Core].[Companies]) = 1
    SELECT @CompanyId = CompanyId FROM [Core].[Companies];

IF @CompanyId IS NULL
BEGIN
    RAISERROR(N'Could not determine which company to seed. Create a company first (Organization Setup > Companies), or set @CompanyCode near the top of this script to an existing Core.Companies.CompanyCode value, then re-run.', 16, 1);
    RETURN;
END;

/* ================================================================
   1. Branches - Head Office plus one branch in each of Kuwait's
      main commercial governorates (matching the Core.Governorates
      seeded by db/02_Organization_Additions.sql).
================================================================ */
INSERT INTO [Core].[Branches]
    (CompanyId, BranchCode, BranchName, Address, Area, Governorate, Telephone, Email, IsActive)
SELECT @CompanyId, v.Code, v.Name, v.Address, v.Area, v.Governorate, v.Telephone, v.Email, 1
FROM (VALUES
    ('HQ',     N'Head Office',       N'Ahmed Al Jaber Street, Sharq',        N'Sharq',      N'Al Asimah (Capital)', N'+965 2222 1000', N'info@company.com.kw'),
    ('BR-HAW', N'Hawalli Branch',    N'Tunis Street, Hawalli',               N'Hawalli',    N'Hawalli',             N'+965 2265 2000', N'hawalli@company.com.kw'),
    ('BR-FAR', N'Farwaniya Branch',  N'Damascus Street, Farwaniya',          N'Farwaniya',  N'Farwaniya',           N'+965 2472 3000', N'farwaniya@company.com.kw'),
    ('BR-AHM', N'Ahmadi Branch',     N'Main Street, Ahmadi',                 N'Ahmadi',     N'Ahmadi',              N'+965 2398 4000', N'ahmadi@company.com.kw'),
    ('BR-JAH', N'Jahra Branch',      N'King Abdulaziz Street, Jahra',        N'Jahra',      N'Jahra',               N'+965 2455 5000', N'jahra@company.com.kw')
) v(Code, Name, Address, Area, Governorate, Telephone, Email)
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Branches] b WHERE b.CompanyId = @CompanyId AND b.BranchCode = v.Code);

/* ================================================================
   2. Cost Centers - one root "Corporate" center, with one child
      center per department created below (matched by code, so the
      Departments insert in step 4 can attach to them directly).
================================================================ */
INSERT INTO [Core].[CostCenters]
    (CompanyId, ParentCostCenterId, CostCenterCode, CostCenterName, IsActive)
SELECT @CompanyId, NULL, N'CC-CORP', N'Corporate / Head Office', 1
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[CostCenters] cc WHERE cc.CompanyId = @CompanyId AND cc.CostCenterCode = N'CC-CORP');

INSERT INTO [Core].[CostCenters]
    (CompanyId, ParentCostCenterId, CostCenterCode, CostCenterName, IsActive)
SELECT @CompanyId, root.CostCenterId, v.Code, v.Name, 1
FROM (VALUES
    ('CC-EXEC',  N'Executive Office'),
    ('CC-HR',    N'Human Resources'),
    ('CC-FIN',   N'Finance & Accounts'),
    ('CC-IT',    N'Information Technology'),
    ('CC-OPS',   N'Operations'),
    ('CC-SALES', N'Sales & Marketing'),
    ('CC-PROC',  N'Procurement & Supply Chain'),
    ('CC-LEGAL', N'Legal & Compliance'),
    ('CC-ADMIN', N'Administration & General Services'),
    ('CC-QA',    N'Quality Assurance'),
    ('CC-CS',    N'Customer Service'),
    ('CC-WH',    N'Warehouse & Logistics')
) v(Code, Name)
CROSS JOIN (
    SELECT CostCenterId FROM [Core].[CostCenters]
    WHERE CompanyId = @CompanyId AND CostCenterCode = N'CC-CORP'
) AS root
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[CostCenters] cc WHERE cc.CompanyId = @CompanyId AND cc.CostCenterCode = v.Code);

/* ================================================================
   3. Departments - a standard 12-department corporate structure,
      each attached to its matching Cost Center from step 2.
      ParentDepartmentId and ManagerEmployeeId are left NULL - set
      those through the Organization Setup screen once you know who
      reports to whom (ManagerEmployeeId cannot be seeded here since
      it depends on employees that do not exist yet on a fresh DB).
================================================================ */
INSERT INTO [Core].[Departments]
    (CompanyId, ParentDepartmentId, DepartmentCode, DepartmentName, CostCenterId, ManagerEmployeeId, IsActive)
SELECT @CompanyId, NULL, v.Code, v.Name, cc.CostCenterId, NULL, 1
FROM (VALUES
    ('EXEC',  N'Executive Office',                  N'CC-EXEC'),
    ('HR',    N'Human Resources',                   N'CC-HR'),
    ('FIN',   N'Finance & Accounts',                 N'CC-FIN'),
    ('IT',    N'Information Technology',             N'CC-IT'),
    ('OPS',   N'Operations',                          N'CC-OPS'),
    ('SALES', N'Sales & Marketing',                   N'CC-SALES'),
    ('PROC',  N'Procurement & Supply Chain',          N'CC-PROC'),
    ('LEGAL', N'Legal & Compliance',                  N'CC-LEGAL'),
    ('ADMIN', N'Administration & General Services',   N'CC-ADMIN'),
    ('QA',    N'Quality Assurance',                    N'CC-QA'),
    ('CS',    N'Customer Service',                     N'CC-CS'),
    ('WH',    N'Warehouse & Logistics',                N'CC-WH')
) v(Code, Name, CCCode)
LEFT JOIN [Core].[CostCenters] cc ON cc.CompanyId = @CompanyId AND cc.CostCenterCode = v.CCCode
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Departments] d WHERE d.CompanyId = @CompanyId AND d.DepartmentCode = v.Code);

/* ================================================================
   4. Sections - sub-units under the departments most companies
      actually split further. Not every department gets sections
      (Executive Office, Legal, QA and Customer Service commonly
      stay flat) - add more later through the UI as the org grows.
================================================================ */
INSERT INTO [Core].[Sections]
    (DepartmentId, SectionCode, SectionName, IsActive)
SELECT d.DepartmentId, v.Code, v.Name, 1
FROM (VALUES
    ('HR',    'HR-REC',    N'Recruitment'),
    ('HR',    'HR-PAY',    N'Payroll & Benefits'),
    ('HR',    'HR-ER',     N'Employee Relations & Training'),
    ('FIN',   'FIN-AP',    N'Accounts Payable'),
    ('FIN',   'FIN-AR',    N'Accounts Receivable'),
    ('FIN',   'FIN-TR',    N'Treasury & Budgeting'),
    ('IT',    'IT-INFRA',  N'Infrastructure & Network'),
    ('IT',    'IT-APP',    N'Applications & Systems'),
    ('IT',    'IT-HD',     N'Help Desk & Support'),
    ('OPS',   'OPS-PROD',  N'Production'),
    ('OPS',   'OPS-MAINT', N'Maintenance'),
    ('SALES', 'SALES-DOM', N'Domestic Sales'),
    ('SALES', 'SALES-MKT', N'Marketing & Branding'),
    ('PROC',  'PROC-PUR',  N'Purchasing'),
    ('PROC',  'PROC-VEN',  N'Vendor Management'),
    ('ADMIN', 'ADMIN-FAC', N'Facilities Management'),
    ('ADMIN', 'ADMIN-TRN', N'Transport & Fleet'),
    ('WH',    'WH-INV',    N'Inventory Control'),
    ('WH',    'WH-DIST',   N'Distribution')
) v(DeptCode, Code, Name)
JOIN [Core].[Departments] d ON d.CompanyId = @CompanyId AND d.DepartmentCode = v.DeptCode
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Sections] s WHERE s.DepartmentId = d.DepartmentId AND s.SectionCode = v.Code);

/* ================================================================
   5. Designations - the job title as printed on the Civil ID, work
      permit and contract. Deliberately covers both office and
      blue-collar roles, since Kuwait Civil ID / MOL paperwork tracks
      the same way for every employee regardless of role. GradeId is
      left NULL - Core.Grades has no seed data assumption here; map
      designations to grades yourself once your grade structure is
      final (Organization Setup > Designations lets you set it).
================================================================ */
INSERT INTO [Core].[Designations]
    (CompanyId, DesignationCode, DesignationName, ArabicName, GradeId, Description, IsActive, CreatedBy)
SELECT @CompanyId, v.Code, v.Name, v.ArabicName, NULL, v.Description, 1, NULL
FROM (VALUES
    ('DSG-CEO',   N'Chief Executive Officer',       N'الرئيس التنفيذي',              N'Overall leadership and strategic direction of the company.'),
    ('DSG-GM',    N'General Manager',               N'المدير العام',                 N'Day-to-day management across all departments.'),
    ('DSG-HRMGR', N'HR Manager',                    N'مدير الموارد البشرية',          N'Leads recruitment, payroll, employee relations and compliance.'),
    ('DSG-HROFF', N'HR Officer',                    N'موظف الموارد البشرية',          N'Handles day-to-day HR administration and employee records.'),
    ('DSG-RECR',  N'Recruitment Specialist',        N'أخصائي توظيف',                 N'Sources and screens candidates for open positions.'),
    ('DSG-PAYOFF',N'Payroll Officer',                N'موظف الرواتب',                 N'Processes monthly payroll and statutory deductions.'),
    ('DSG-FINMGR',N'Finance Manager',                N'المدير المالي',                N'Oversees accounting, treasury and financial reporting.'),
    ('DSG-SRACC', N'Senior Accountant',              N'محاسب أول',                    N'Reviews ledgers and prepares financial statements.'),
    ('DSG-ACC',   N'Accountant',                     N'محاسب',                        N'Handles day-to-day bookkeeping and reconciliations.'),
    ('DSG-ITMGR', N'IT Manager',                     N'مدير تقنية المعلومات',          N'Owns IT infrastructure, applications and support.'),
    ('DSG-NETADM',N'Network Administrator',          N'مسؤول الشبكات',                N'Maintains network, servers and security.'),
    ('DSG-DEV',   N'Software Developer',             N'مطور برمجيات',                 N'Builds and maintains internal applications.'),
    ('DSG-HDTECH',N'Help Desk Technician',           N'فني الدعم الفني',              N'First-line IT support for staff.'),
    ('DSG-OPSMGR',N'Operations Manager',             N'مدير العمليات',                N'Runs day-to-day production/operations activity.'),
    ('DSG-PRODSUP',N'Production Supervisor',         N'مشرف الإنتاج',                 N'Supervises the production floor and shift teams.'),
    ('DSG-MAINT', N'Maintenance Technician',         N'فني الصيانة',                  N'Maintains and repairs equipment and facilities.'),
    ('DSG-SLSMGR',N'Sales Manager',                  N'مدير المبيعات',                N'Leads the sales team and key accounts.'),
    ('DSG-SLSEXEC',N'Sales Executive',               N'موظف مبيعات',                  N'Manages customer accounts and closes sales.'),
    ('DSG-MKTEXEC',N'Marketing Executive',           N'موظف تسويق',                   N'Runs marketing campaigns and branding activity.'),
    ('DSG-PROCOFF',N'Procurement Officer',           N'موظف مشتريات',                 N'Sources suppliers and processes purchase orders.'),
    ('DSG-WHSUP', N'Warehouse Supervisor',           N'مشرف المستودع',                N'Oversees warehouse staff, receiving and dispatch.'),
    ('DSG-STORE', N'Storekeeper',                    N'أمين مخزن',                    N'Maintains stock records and inventory accuracy.'),
    ('DSG-HDRV',  N'Heavy Driver',                   N'سائق مركبات ثقيلة',            N'Holds a heavy-vehicle licence; operates trucks/heavy equipment.'),
    ('DSG-LDRV',  N'Light Driver',                   N'سائق مركبات خفيفة',            N'Holds a light-vehicle licence; deliveries and staff transport.'),
    ('DSG-OFFAST',N'Office Assistant',               N'مساعد إداري',                  N'General office and administrative support.'),
    ('DSG-RECEP', N'Receptionist',                   N'موظف استقبال',                 N'Front-desk, visitor and call handling.'),
    ('DSG-SEC',   N'Security Guard',                 N'حارس أمن',                     N'Site security and access control.'),
    ('DSG-CLEAN', N'Cleaner',                        N'عامل نظافة',                   N'Cleaning and general upkeep of premises.'),
    ('DSG-LEGAL', N'Legal Advisor',                  N'مستشار قانوني',                N'Contracts, compliance and legal matters.'),
    ('DSG-QAINSP',N'Quality Control Inspector',      N'مفتش ضبط الجودة',              N'Inspects output against quality standards.'),
    ('DSG-CSREP', N'Customer Service Representative',N'ممثل خدمة العملاء',            N'Handles customer inquiries and complaints.'),
    ('DSG-ADMAST',N'Administrative Assistant',       N'مساعد إداري أول',              N'Supports department managers with scheduling and records.')
) v(Code, Name, ArabicName, Description)
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Designations] dg WHERE dg.CompanyId = @CompanyId AND dg.DesignationCode = v.Code);

/* ================================================================
   6. Job Positions - seats in the org chart (Core.Positions).
      Narrower than the Designation list above on purpose: a
      Position is "one HR Manager seat", filled by whoever currently
      holds that Designation - most companies plan headcount at this
      coarser level. GradeId left NULL for the same reason as above.
================================================================ */
INSERT INTO [Core].[Positions]
    (CompanyId, PositionCode, PositionName, JobDescription, GradeId, IsActive)
SELECT @CompanyId, v.Code, v.Name, v.Description, NULL, 1
FROM (VALUES
    ('POS-CEO',    N'Chief Executive Officer', N'Sets company strategy and reports to the board.'),
    ('POS-GM',     N'General Manager',         N'Runs day-to-day operations across all departments.'),
    ('POS-HRMGR',  N'HR Manager',              N'Leads the Human Resources department.'),
    ('POS-HROFF',  N'HR Officer',              N'Supports HR administration and employee records.'),
    ('POS-FINMGR', N'Finance Manager',         N'Leads the Finance & Accounts department.'),
    ('POS-ACC',    N'Accountant',              N'General accounting and reconciliations.'),
    ('POS-ITMGR',  N'IT Manager',              N'Leads the Information Technology department.'),
    ('POS-ITSUP',  N'IT Support Engineer',     N'First and second-line technical support.'),
    ('POS-OPSMGR', N'Operations Manager',      N'Leads day-to-day Operations.'),
    ('POS-PRODSUP',N'Production Supervisor',   N'Supervises a production shift or line.'),
    ('POS-SLSMGR', N'Sales Manager',           N'Leads the Sales & Marketing department.'),
    ('POS-SLSEXEC',N'Sales Executive',         N'Manages a portfolio of customer accounts.'),
    ('POS-MKTEXEC',N'Marketing Executive',     N'Plans and runs marketing activity.'),
    ('POS-PROCOFF',N'Procurement Officer',     N'Sources suppliers and issues purchase orders.'),
    ('POS-WHSUP',  N'Warehouse Supervisor',    N'Oversees warehouse operations.'),
    ('POS-STORE',  N'Storekeeper',             N'Maintains stock accuracy.'),
    ('POS-DRV',    N'Driver',                  N'Vehicle operation and deliveries.'),
    ('POS-OFFAST', N'Office Assistant',        N'General administrative support.'),
    ('POS-RECEP',  N'Receptionist',            N'Front-desk and switchboard.'),
    ('POS-SEC',    N'Security Guard',          N'Site security.')
) v(Code, Name, Description)
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Positions] p WHERE p.CompanyId = @CompanyId AND p.PositionCode = v.Code);

/* ================================================================
   7. Locations - physical work sites, tied to the branch they sit
      at. Latitude/Longitude left NULL here (fill them in later from
      the Organization Setup screen once you have exact coordinates
      for attendance-device placement).
================================================================ */
INSERT INTO [Core].[Locations]
    (CompanyId, BranchId, LocationCode, LocationName, LocationType, Governorate, Area, Block, Street, Building, Latitude, Longitude, IsActive, CreatedBy)
SELECT @CompanyId, b.BranchId, v.Code, v.Name, v.Type, v.Governorate, v.Area, v.Block, v.Street, v.Building, NULL, NULL, 1, NULL
FROM (VALUES
    ('HQ',     'LOC-HQMAIN', N'Head Office Building',   N'Office',    N'Al Asimah (Capital)', N'Sharq',     N'1', N'Ahmed Al Jaber Street', N'Tower 1'),
    ('HQ',     'LOC-HQWH',   N'Head Office Warehouse',   N'Warehouse', N'Al Asimah (Capital)', N'Shuwaikh',  N'2', N'Industrial Road',        N'Warehouse 4'),
    ('BR-HAW', 'LOC-HAWOFF', N'Hawalli Office',          N'Office',    N'Hawalli',             N'Hawalli',   N'3', N'Tunis Street',           NULL),
    ('BR-FAR', 'LOC-FAROFF', N'Farwaniya Office',        N'Office',    N'Farwaniya',           N'Farwaniya', N'2', N'Damascus Street',        NULL),
    ('BR-AHM', 'LOC-AHMSITE',N'Ahmadi Site Camp',        N'Site',      N'Ahmadi',              N'Ahmadi',    N'1', N'Main Street',            NULL),
    ('BR-AHM', 'LOC-AHMWH',  N'Ahmadi Warehouse',        N'Warehouse', N'Ahmadi',              N'Fahaheel',  N'5', N'Coastal Road',           N'Warehouse 2'),
    ('BR-JAH', 'LOC-JAHOFF', N'Jahra Office',            N'Office',    N'Jahra',               N'Jahra',     N'1', N'King Abdulaziz Street',  NULL)
) v(BranchCode, Code, Name, Type, Governorate, Area, Block, Street, Building)
JOIN [Core].[Branches] b ON b.CompanyId = @CompanyId AND b.BranchCode = v.BranchCode
WHERE NOT EXISTS (
    SELECT 1 FROM [Core].[Locations] l WHERE l.CompanyId = @CompanyId AND l.LocationCode = v.Code);

/* ================================================================
   Summary
================================================================ */
DECLARE @Summary TABLE (TableName NVARCHAR(50), RecordCount INT);
INSERT INTO @Summary VALUES
    (N'Branches',     (SELECT COUNT(1) FROM [Core].[Branches]     WHERE CompanyId = @CompanyId)),
    (N'CostCenters',  (SELECT COUNT(1) FROM [Core].[CostCenters]  WHERE CompanyId = @CompanyId)),
    (N'Departments',  (SELECT COUNT(1) FROM [Core].[Departments]  WHERE CompanyId = @CompanyId)),
    (N'Sections',     (SELECT COUNT(1) FROM [Core].[Sections] s JOIN [Core].[Departments] d ON d.DepartmentId = s.DepartmentId WHERE d.CompanyId = @CompanyId)),
    (N'Designations', (SELECT COUNT(1) FROM [Core].[Designations] WHERE CompanyId = @CompanyId)),
    (N'JobPositions', (SELECT COUNT(1) FROM [Core].[Positions]    WHERE CompanyId = @CompanyId)),
    (N'Locations',    (SELECT COUNT(1) FROM [Core].[Locations]    WHERE CompanyId = @CompanyId));

SELECT TableName, RecordCount FROM @Summary ORDER BY TableName;

PRINT N'Organization seed data applied for CompanyId ' + CAST(@CompanyId AS NVARCHAR(10)) + N'. Re-run any time - already-seeded rows are skipped.';
GO
