/* ================================================================
   HRMS Kuwait - Employee master data import (10 employees)
   ----------------------------------------------------------------
   Loads the "Employee Master" spreadsheet (Basic/Personal,
   Employment & Work, Passport & Visa, Contact & Emergency,
   Payroll & Bank) into the existing schema so the Employees grid
   and the Employee Profile tabs show real-looking data.

   RE-RUNNABLE: employees are matched on (CompanyId, EmployeeCode).
   An existing employee is UPDATED with the sheet values, a missing
   one is INSERTED - running it twice never creates duplicates.
   Missing master data (countries, departments, designations,
   locations) is created on the fly; anything that already exists
   is reused.

   WHERE EACH SPREADSHEET COLUMN GOES
   ----------------------------------------------------------------
   Emp Code                -> Employees.EmployeeCode AND EmployeeNo
   Full Name               -> FirstName / MiddleName / LastName
                              (split by hand in the VALUES list -
                              compound names like "Abu Bakr" and
                              "Awad Allah" kept together)
   Gender                  -> Employees.Gender ('M' / 'F')
   Date of Birth           -> Employees.DateOfBirth
   Nationality             -> Employees.NationalityCountryId
                              (+ Compliance.PassportCountryId)
   Civil ID / National ID  -> Compliance.CivilIdNumber
   Marital Status          -> Employees.MaritalStatus
   Joining Date            -> Employees.HireDate
   Designation / Title     -> Employees.DesignationId (Core.Designations)
   Department              -> Employees.DepartmentId  (Core.Departments)
                              + CostCenterId from the department
   Work Location           -> Employees.WorkLocationId (Core.Locations)
                              + BranchId from the location
   Employment Status       -> Full-time  = Full-Time / Active
                              Probation  = Full-Time / Probation
                              Contract   = Contract  / Active
   Sponsor Status          -> Compliance.SponsorStatus      (db/20)
   Company Email           -> Employees.WorkEmail
   Company Phone           -> Employees.CompanyPhone        (db/20)
   Company Assets          -> Employees.CompanyAssets       (db/20)
   Passport Number/Expiry  -> Compliance.PassportNumber / PassportExpiryDate
   Civil ID Expiry         -> Compliance.CivilIdExpiryDate
   Work Permit Expiry      -> Compliance.WorkPermitExpiryDate
   Residency Status        -> Compliance.ResidencyStatus    (db/20)
   Personal Mobile         -> Employees.MobileNumber
   Personal Email          -> Employees.PersonalEmail
   Local Address           -> Employees.Address (full text) plus
                              Neighborhood / Block / StreetName
   Emergency Contact Name  -> "Wife (Fatima)" ->
                              EmergencyContactName = Fatima,
                              EmergencyContactRelation = Wife
   Emergency Contact Phone -> Employees.EmergencyContactPhone
   Basic Salary / Allow.   -> EmployeePayroll.BasicSalary / Allowances (db/20)
   Bank Name / IBAN        -> EmployeePayroll.BankName / Iban            (db/20)

   Passport and Civil ID go to Kuwait.EmployeeCompliance only - the
   Kuwait Compliance tab is the single place they are edited (the
   matching Employees.PassportNumber / CivilIdNumber columns from
   db/17 are deliberately left alone).

   HOW TO USE
   ----------
   1. Run 19 and 20 first (20 adds the columns this script fills).
   2. If you have more than one company, set @CompanyCode below.
   3. Run the whole file in one go - it is a single batch.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

DECLARE @CompanyCode NVARCHAR(30) = NULL;   -- <-- set if you have more than one company
DECLARE @UserId      BIGINT       = NULL;   -- optional: Security.Users.UserId to stamp CreatedBy
DECLARE @CompanyId   INT;

IF @CompanyCode IS NOT NULL
    SELECT @CompanyId = CompanyId FROM [Core].[Companies] WHERE CompanyCode = @CompanyCode;
ELSE IF (SELECT COUNT(1) FROM [Core].[Companies]) = 1
    SELECT @CompanyId = CompanyId FROM [Core].[Companies];

IF @CompanyId IS NULL
BEGIN
    RAISERROR(N'Could not determine which company to import into. Set @CompanyCode near the top of this script to an existing Core.Companies.CompanyCode, then re-run.', 16, 1);
    RETURN;
END;

IF COL_LENGTH('Employee.Employees', 'CompanyPhone') IS NULL
   OR OBJECT_ID(N'[Employee].[EmployeePayroll]', N'U') IS NULL
BEGIN
    RAISERROR(N'Run db/20_Employee_Import_Additions.sql first - it adds CompanyPhone, CompanyAssets, SponsorStatus, ResidencyStatus and Employee.EmployeePayroll.', 16, 1);
    RETURN;
END;

/* ================================================================
   0. The spreadsheet rows
================================================================ */
DECLARE @Import TABLE (
    EmployeeCode      NVARCHAR(20)  NOT NULL PRIMARY KEY,
    FirstName         NVARCHAR(100) NOT NULL,
    MiddleName        NVARCHAR(100) NULL,
    LastName          NVARCHAR(100) NULL,
    Gender            CHAR(1)       NULL,
    DateOfBirth       DATE          NULL,
    Nationality       NVARCHAR(50)  NULL,
    CivilIdNumber     NVARCHAR(20)  NULL,
    MaritalStatus     NVARCHAR(20)  NULL,
    HireDate          DATE          NULL,
    Designation       NVARCHAR(150) NULL,
    Department        NVARCHAR(150) NULL,
    WorkLocation      NVARCHAR(150) NULL,
    EmploymentType    NVARCHAR(20)  NULL,
    EmploymentStatus  NVARCHAR(20)  NOT NULL,
    SponsorStatus     NVARCHAR(50)  NULL,
    WorkEmail         NVARCHAR(150) NULL,
    CompanyPhone      NVARCHAR(20)  NULL,
    CompanyAssets     NVARCHAR(300) NULL,
    PassportNumber    NVARCHAR(30)  NULL,
    PassportExpiry    DATE          NULL,
    CivilIdExpiry     DATE          NULL,
    WorkPermitExpiry  DATE          NULL,
    ResidencyStatus   NVARCHAR(30)  NULL,
    MobileNumber      NVARCHAR(20)  NULL,
    PersonalEmail     NVARCHAR(150) NULL,
    Address           NVARCHAR(500) NULL,
    Neighborhood      NVARCHAR(100) NULL,
    Block             NVARCHAR(20)  NULL,
    StreetName        NVARCHAR(150) NULL,
    EmergencyName     NVARCHAR(150) NULL,
    EmergencyRelation NVARCHAR(50)  NULL,
    EmergencyPhone    NVARCHAR(20)  NULL,
    BasicSalary       DECIMAL(12,3) NULL,
    Allowances        DECIMAL(12,3) NULL,
    BankName          NVARCHAR(100) NULL,
    Iban              NVARCHAR(34)  NULL
);

INSERT INTO @Import VALUES
    (N'2001', N'Abu Bakr', N'Mohammed', N'Awad Allah', N'M', N'1988-05-15', N'Egyptian', N'288051512345', N'Married', N'2026-09-01', N'Senior Engineer', N'Engineering', N'Shuwaikh Site', N'Full-Time', N'Active', N'Company Sponsor', N'abubakr@rand.com', N'+965 90001111', N'Laptop, Mobile', N'N1234567', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50001111', N'abubakr@gmail.com', N'Salmiya, Block 10, St 4', N'Salmiya', N'10', N'Street 4', N'Fatima', N'Wife', N'+965 99990001', 270.000, 50.000, N'NBK', N'KW12NBBK00000000001111'),
    (N'2002', N'Kawtar', N'Shams El-Din Mohammed', N'Ahmed', N'F', N'1992-08-20', N'Sudanese', N'292082012346', N'Single', N'2026-09-01', N'Accountant', N'Finance', N'Head Office', N'Full-Time', N'Active', N'Company Sponsor', N'kawtar@rand.com', N'+965 90002222', N'Laptop', N'P7654321', N'2029-08-15', N'2027-08-19', N'2027-08-19', N'Valid', N'+965 50002222', N'kawtar@gmail.com', N'Hawally, Block 2, St 12', N'Hawally', N'2', N'Street 12', N'Ahmed', N'Brother', N'+965 99990002', 280.000, 40.000, N'Gulf Bank', N'KW12GULF00000000002222'),
    (N'2003', N'Sujal', N'Kumar Jibesh', N'Sahoo', N'M', N'1995-01-10', N'Indian', N'295011012347', N'Single', N'2026-09-01', N'Technician', N'Operations', N'Ahmadi Site', N'Full-Time', N'Active', N'Company Sponsor', N'sujal@rand.com', N'+965 90003333', N'Tool Kit', N'Z9876543', N'2027-01-05', N'2027-01-09', N'2027-01-09', N'Valid', N'+965 50003333', N'sujal@gmail.com', N'Fahaheel, Block 7, St 2', N'Fahaheel', N'7', N'Street 2', N'Jibesh', N'Father', N'+91 9876543210', 200.000, 30.000, N'KFH', N'KW12KFH00000000003333'),
    (N'2004', N'Elias', N'Banik', N'Miah', N'M', N'1990-03-03', N'Bangladeshi', N'290030312348', N'Married', N'2026-09-01', N'Supervisor', N'Operations', N'Shuwaikh Site', N'Full-Time', N'Active', N'Company Sponsor', N'elias@rand.com', N'+965 90004444', N'Mobile', N'A3456789', N'2028-02-12', N'2027-03-02', N'2027-03-02', N'Valid', N'+965 50004444', N'elias@gmail.com', N'Jawaher, Block 1, St 5', N'Jawaher', N'1', N'Street 5', N'Sultana', N'Wife', N'+880 1712345678', 100.000, 20.000, N'Burgan Bank', N'KW12BURG00000000004444'),
    (N'2011', N'Ali', N'Mustafa', N'Bakri', N'M', N'1987-11-12', N'Jordanian', N'287111212349', N'Married', N'2026-09-01', N'HR Officer', N'Human Resources', N'Head Office', N'Full-Time', N'Active', N'Company Sponsor', N'ali@rand.com', N'+965 90005555', N'Laptop, Phone', N'B9012345', N'2028-11-30', N'2027-11-11', N'2027-11-11', N'Valid', N'+965 50005555', N'ali@gmail.com', N'Salmiya, Block 5, St 8', N'Salmiya', N'5', N'Street 8', N'Rania', N'Wife', N'+962 791234567', 120.000, 25.000, N'Boubyan Bank', N'KW12BOUB00000000005555'),
    (N'2015', N'Lal', N'Bishwol Mohammed', N'Ahmed', N'M', N'1993-07-25', N'Nepali', N'293072512350', N'Single', N'2026-09-19', N'Driver', N'Logistics', N'Head Office', N'Full-Time', N'Probation', N'Company Sponsor', N'lal@rand.com', N'+965 90006666', N'Company Vehicle', N'C6789012', N'2027-07-18', N'2027-07-24', N'2027-07-24', N'Under Process', N'+965 50006666', N'lal@gmail.com', N'Khaitan, Block 4, St 9', N'Khaitan', N'4', N'Street 9', N'Bishwol', N'Father', N'+977 9801234567', 80.000, 15.000, N'NBK', N'KW12NBBK00000000006666'),
    (N'2025', N'Bimal', N'Das Birjon', N'Das', N'M', N'1991-12-08', N'Indian', N'291120812351', N'Married', N'2026-09-01', N'Storekeeper', N'Logistics', N'Central Warehouse', N'Full-Time', N'Active', N'Company Sponsor', N'bimal@rand.com', N'+965 90007777', N'Tablet', N'D4567890', N'2028-12-01', N'2027-12-07', N'2027-12-07', N'Valid', N'+965 50007777', N'bimal@gmail.com', N'Farwaniya, Block 3, St 11', N'Farwaniya', N'3', N'Street 11', N'Priya', N'Wife', N'+91 9812345678', 150.000, 30.000, N'CBK', N'KW12CBK00000000007777'),
    (N'2031', N'Akram', N'Rasul Abdul Hafiz', N'Ghazal', N'M', N'1985-02-14', N'Syrian', N'285021412352', N'Married', N'2026-09-01', N'Project Manager', N'Projects', N'Ahmadi Site', N'Full-Time', N'Active', N'Company Sponsor', N'akram@rand.com', N'+965 90008888', N'Laptop, Car, Mobile', N'E2345678', N'2029-02-10', N'2027-02-13', N'2027-02-13', N'Valid', N'+965 50008888', N'akram@gmail.com', N'Jabriya, Block 8, St 15', N'Jabriya', N'8', N'Street 15', N'Mona', N'Wife', N'+963 933123456', 350.000, 100.000, N'NBK', N'KW12NBBK00000000008888'),
    (N'2042', N'Reshma', N'Sasi Sasi', N'Govindan', N'F', N'1994-10-19', N'Indian', N'294101912353', N'Married', N'2026-09-12', N'Admin Assistant', N'Administration', N'Head Office', N'Full-Time', N'Probation', N'Company Sponsor', N'reshma@rand.com', N'+965 90009999', N'Desktop PC', N'F8901234', N'2028-10-05', N'2027-10-18', N'2027-10-18', N'Valid', N'+965 50009999', N'reshma@gmail.com', N'Mangaf, Block 4, St 3', N'Mangaf', N'4', N'Street 3', N'Sasi', N'Husband', N'+91 9947000000', 300.000, 50.000, N'ABK', N'KW12ABK00000000009999'),
    (N'2046', N'Extra', N'Employee', N'Entry', N'M', N'1990-01-01', N'Indian', N'290010112354', N'Single', N'2026-09-01', N'Assistant', N'General', N'Head Office', N'Contract', N'Active', N'Company Sponsor', N'extra@rand.com', N'+965 90000000', NULL, N'G1234567', N'2028-01-01', N'2027-01-01', N'2027-01-01', N'Valid', N'+965 50000000', N'extra@gmail.com', N'Abbasiya, Block 2, St 6', N'Abbasiya', N'2', N'Street 6', N'Kumar', N'Friend', N'+965 55550000', 0.000, 0.000, N'NBK', N'KW12NBBK00000000010000');

/* ================================================================
   1. Lookup maps: spreadsheet text -> master record
      (Code = what to look for / create; Name = display name)
================================================================ */
DECLARE @CountryMap TABLE (Nationality NVARCHAR(50) PRIMARY KEY, CountryCode NVARCHAR(10), CountryName NVARCHAR(100));
INSERT INTO @CountryMap VALUES
    (N'Egyptian',    N'EG', N'Egypt'),
    (N'Sudanese',    N'SD', N'Sudan'),
    (N'Indian',      N'IN', N'India'),
    (N'Bangladeshi', N'BD', N'Bangladesh'),
    (N'Jordanian',   N'JO', N'Jordan'),
    (N'Nepali',      N'NP', N'Nepal'),
    (N'Syrian',      N'SY', N'Syria');

-- Sheet department -> existing seed code (db/12) where one clearly fits,
-- otherwise a new department is created with this code/name.
DECLARE @DeptMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DeptCode NVARCHAR(20), DeptName NVARCHAR(150));
INSERT INTO @DeptMap VALUES
    (N'Engineering',     N'ENG',   N'Engineering'),
    (N'Finance',         N'FIN',   N'Finance & Accounts'),
    (N'Operations',      N'OPS',   N'Operations'),
    (N'Human Resources', N'HR',    N'Human Resources'),
    (N'Logistics',       N'WH',    N'Warehouse & Logistics'),
    (N'Projects',        N'PROJ',  N'Projects'),
    (N'Administration',  N'ADMIN', N'Administration & General Services'),
    (N'General',         N'GEN',   N'General');

DECLARE @DesigMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DesigCode NVARCHAR(20), DesigName NVARCHAR(150), ArabicName NVARCHAR(150));
INSERT INTO @DesigMap VALUES
    (N'Senior Engineer', N'DSG-SRENG',  N'Senior Engineer',          N'مهندس أول'),
    (N'Accountant',      N'DSG-ACC',    N'Accountant',               N'محاسب'),
    (N'Technician',      N'DSG-TECH',   N'Technician',               N'فني'),
    (N'Supervisor',      N'DSG-SUP',    N'Supervisor',               N'مشرف'),
    (N'HR Officer',      N'DSG-HROFF',  N'HR Officer',               N'موظف الموارد البشرية'),
    (N'Driver',          N'DSG-DRV',    N'Driver',                   N'سائق'),
    (N'Storekeeper',     N'DSG-STORE',  N'Storekeeper',              N'أمين مخزن'),
    (N'Project Manager', N'DSG-PM',     N'Project Manager',          N'مدير مشروع'),
    (N'Admin Assistant', N'DSG-ADMAST', N'Administrative Assistant', N'مساعد إداري أول'),
    (N'Assistant',       N'DSG-ASST',   N'Assistant',                N'مساعد');

DECLARE @LocMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, LocCode NVARCHAR(20), LocName NVARCHAR(150), LocType NVARCHAR(50), Governorate NVARCHAR(100), Area NVARCHAR(100));
INSERT INTO @LocMap VALUES
    (N'Head Office',       N'LOC-HQMAIN',  N'Head Office Building', N'Office',    N'Al Asimah (Capital)', N'Sharq'),
    (N'Ahmadi Site',       N'LOC-AHMSITE', N'Ahmadi Site Camp',     N'Site',      N'Ahmadi',              N'Ahmadi'),
    (N'Shuwaikh Site',     N'LOC-SHWSITE', N'Shuwaikh Site',        N'Site',      N'Al Asimah (Capital)', N'Shuwaikh'),
    (N'Central Warehouse', N'LOC-CENTWH',  N'Central Warehouse',    N'Warehouse', N'Al Asimah (Capital)', N'Shuwaikh');

/* ================================================================
   2. Countries - reuse by ISO code or name; add any that are missing.
      Outside the main transaction: if Core.Countries has extra
      required columns the INSERT fails softly and that employee's
      nationality is just left blank.
================================================================ */
BEGIN TRY
    INSERT INTO [Core].[Countries] (CountryCode, CountryName, IsActive)
    SELECT m.CountryCode, m.CountryName, 1
    FROM @CountryMap m
    WHERE NOT EXISTS (SELECT 1 FROM [Core].[Countries] c
                      WHERE c.CountryCode = m.CountryCode
                         OR c.CountryName = m.CountryName
                         OR c.CountryName LIKE m.CountryName + N'%');
END TRY
BEGIN CATCH
    PRINT N'NOTE: could not add missing countries (' + ERROR_MESSAGE() + N'). Nationality is left blank for those employees.';
END CATCH;

DECLARE @Countries TABLE (Nationality NVARCHAR(50) PRIMARY KEY, CountryId INT);
INSERT INTO @Countries
SELECT m.Nationality,
       (SELECT TOP 1 c.CountryId FROM [Core].[Countries] c
        WHERE c.CountryCode = m.CountryCode OR c.CountryName = m.CountryName OR c.CountryName LIKE m.CountryName + N'%'
        ORDER BY CASE WHEN c.CountryCode = m.CountryCode THEN 0 WHEN c.CountryName = m.CountryName THEN 1 ELSE 2 END)
FROM @CountryMap m;

SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

/* ================================================================
   3. Departments - by code, then by name; create if missing
================================================================ */
INSERT INTO [Core].[Departments]
    (CompanyId, ParentDepartmentId, DepartmentCode, DepartmentName, CostCenterId, ManagerEmployeeId, IsActive)
SELECT @CompanyId, NULL, m.DeptCode, m.DeptName, NULL, NULL, 1
FROM @DeptMap m
WHERE EXISTS (SELECT 1 FROM @Import i WHERE i.Department = m.SheetName)
  AND NOT EXISTS (SELECT 1 FROM [Core].[Departments] d
                  WHERE d.CompanyId = @CompanyId
                    AND (d.DepartmentCode = m.DeptCode OR d.DepartmentName IN (m.DeptName, m.SheetName)));

DECLARE @Depts TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DepartmentId INT, CostCenterId INT);
INSERT INTO @Depts
SELECT m.SheetName, d.DepartmentId, d.CostCenterId
FROM @DeptMap m
CROSS APPLY (SELECT TOP 1 d.DepartmentId, d.CostCenterId FROM [Core].[Departments] d
             WHERE d.CompanyId = @CompanyId
               AND (d.DepartmentCode = m.DeptCode OR d.DepartmentName IN (m.DeptName, m.SheetName))
             ORDER BY CASE WHEN d.DepartmentCode = m.DeptCode THEN 0 ELSE 1 END) d;

/* ================================================================
   4. Designations - by code, then by name; create if missing
================================================================ */
INSERT INTO [Core].[Designations]
    (CompanyId, DesignationCode, DesignationName, ArabicName, GradeId, Description, IsActive, CreatedBy)
SELECT @CompanyId, m.DesigCode, m.DesigName, m.ArabicName, NULL, N'Added by employee import (db/21).', 1, @UserId
FROM @DesigMap m
WHERE EXISTS (SELECT 1 FROM @Import i WHERE i.Designation = m.SheetName)
  AND NOT EXISTS (SELECT 1 FROM [Core].[Designations] dg
                  WHERE dg.CompanyId = @CompanyId
                    AND (dg.DesignationCode = m.DesigCode OR dg.DesignationName IN (m.DesigName, m.SheetName)));

DECLARE @Desigs TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DesignationId INT);
INSERT INTO @Desigs
SELECT m.SheetName, dg.DesignationId
FROM @DesigMap m
CROSS APPLY (SELECT TOP 1 dg.DesignationId FROM [Core].[Designations] dg
             WHERE dg.CompanyId = @CompanyId
               AND (dg.DesignationCode = m.DesigCode OR dg.DesignationName IN (m.DesigName, m.SheetName))
             ORDER BY CASE WHEN dg.DesignationCode = m.DesigCode THEN 0 ELSE 1 END) dg;

/* ================================================================
   5. Locations - by code, then by name; new ones go under the
      Head Office branch (HQ) when it exists
================================================================ */
DECLARE @HqBranchId INT =
    (SELECT TOP 1 BranchId FROM [Core].[Branches] WHERE CompanyId = @CompanyId ORDER BY CASE WHEN BranchCode = N'HQ' THEN 0 ELSE 1 END, BranchId);

INSERT INTO [Core].[Locations]
    (CompanyId, BranchId, LocationCode, LocationName, LocationType, Governorate, Area, Block, Street, Building, Latitude, Longitude, IsActive, CreatedBy)
SELECT @CompanyId, @HqBranchId, m.LocCode, m.LocName, m.LocType, m.Governorate, m.Area, NULL, NULL, NULL, NULL, NULL, 1, @UserId
FROM @LocMap m
WHERE EXISTS (SELECT 1 FROM @Import i WHERE i.WorkLocation = m.SheetName)
  AND NOT EXISTS (SELECT 1 FROM [Core].[Locations] l
                  WHERE l.CompanyId = @CompanyId
                    AND (l.LocationCode = m.LocCode OR l.LocationName IN (m.LocName, m.SheetName)));

DECLARE @Locs TABLE (SheetName NVARCHAR(150) PRIMARY KEY, LocationId INT, BranchId INT);
INSERT INTO @Locs
SELECT m.SheetName, l.LocationId, l.BranchId
FROM @LocMap m
CROSS APPLY (SELECT TOP 1 l.LocationId, l.BranchId FROM [Core].[Locations] l
             WHERE l.CompanyId = @CompanyId
               AND (l.LocationCode = m.LocCode OR l.LocationName IN (m.LocName, m.SheetName))
             ORDER BY CASE WHEN l.LocationCode = m.LocCode THEN 0 ELSE 1 END) l;

/* ================================================================
   6. Resolve every row to its IDs
================================================================ */
DECLARE @Rows TABLE (
    EmployeeCode NVARCHAR(20) PRIMARY KEY, EmployeeId BIGINT NULL,
    NationalityCountryId INT, DepartmentId INT, CostCenterId INT,
    DesignationId INT, WorkLocationId INT, BranchId INT);

INSERT INTO @Rows (EmployeeCode, EmployeeId, NationalityCountryId, DepartmentId, CostCenterId, DesignationId, WorkLocationId, BranchId)
SELECT i.EmployeeCode,
       (SELECT TOP 1 e.EmployeeId FROM [Employee].[Employees] e WHERE e.CompanyId = @CompanyId AND e.EmployeeCode = i.EmployeeCode),
       c.CountryId, d.DepartmentId, d.CostCenterId, dg.DesignationId, l.LocationId, l.BranchId
FROM @Import i
LEFT JOIN @Countries c ON c.Nationality = i.Nationality
LEFT JOIN @Depts     d ON d.SheetName   = i.Department
LEFT JOIN @Desigs   dg ON dg.SheetName  = i.Designation
LEFT JOIN @Locs      l ON l.SheetName   = i.WorkLocation;

/* ================================================================
   7. Employees - update existing, insert new
================================================================ */
UPDATE e
   SET EmployeeNo               = i.EmployeeCode,
       FirstName                = i.FirstName,
       MiddleName               = i.MiddleName,
       LastName                 = i.LastName,
       Gender                   = i.Gender,
       DateOfBirth              = i.DateOfBirth,
       MaritalStatus            = i.MaritalStatus,
       NationalityCountryId     = r.NationalityCountryId,
       MobileNumber             = i.MobileNumber,
       PersonalEmail            = i.PersonalEmail,
       WorkEmail                = i.WorkEmail,
       Address                  = i.Address,
       Neighborhood             = i.Neighborhood,
       Block                    = i.Block,
       StreetName               = i.StreetName,
       EmergencyContactName     = i.EmergencyName,
       EmergencyContactPhone    = i.EmergencyPhone,
       EmergencyContactRelation = i.EmergencyRelation,
       BranchId                 = r.BranchId,
       DepartmentId             = r.DepartmentId,
       DesignationId            = r.DesignationId,
       CostCenterId             = r.CostCenterId,
       WorkLocationId           = r.WorkLocationId,
       HireDate                 = i.HireDate,
       EmploymentType           = i.EmploymentType,
       EmploymentStatus         = i.EmploymentStatus,
       CompanyPhone             = i.CompanyPhone,
       CompanyAssets            = i.CompanyAssets,
       ModifiedBy               = @UserId,
       ModifiedDate             = SYSUTCDATETIME()
FROM [Employee].[Employees] e
JOIN @Rows   r ON r.EmployeeId   = e.EmployeeId
JOIN @Import i ON i.EmployeeCode = r.EmployeeCode;

DECLARE @Updated INT = @@ROWCOUNT;

INSERT INTO [Employee].[Employees]
    (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, Gender, DateOfBirth, MaritalStatus,
     NationalityCountryId, MobileNumber, PersonalEmail, WorkEmail, Address, Neighborhood, Block, StreetName,
     EmergencyContactName, EmergencyContactPhone, EmergencyContactRelation, FatherIsDeceased,
     CompanyId, BranchId, DepartmentId, DesignationId, CostCenterId, WorkLocationId,
     HireDate, EmploymentType, EmploymentStatus, CompanyPhone, CompanyAssets, IsDeleted, CreatedBy)
SELECT i.EmployeeCode, i.EmployeeCode, i.FirstName, i.MiddleName, i.LastName, i.Gender, i.DateOfBirth, i.MaritalStatus,
       r.NationalityCountryId, i.MobileNumber, i.PersonalEmail, i.WorkEmail, i.Address, i.Neighborhood, i.Block, i.StreetName,
       i.EmergencyName, i.EmergencyPhone, i.EmergencyRelation, 0,
       @CompanyId, r.BranchId, r.DepartmentId, r.DesignationId, r.CostCenterId, r.WorkLocationId,
       i.HireDate, i.EmploymentType, i.EmploymentStatus, i.CompanyPhone, i.CompanyAssets, 0, @UserId
FROM @Import i
JOIN @Rows r ON r.EmployeeCode = i.EmployeeCode
WHERE r.EmployeeId IS NULL;

DECLARE @Inserted INT = @@ROWCOUNT;

UPDATE r
   SET EmployeeId = e.EmployeeId
FROM @Rows r
JOIN [Employee].[Employees] e ON e.CompanyId = @CompanyId AND e.EmployeeCode = r.EmployeeCode
WHERE r.EmployeeId IS NULL;

/* ================================================================
   8. Kuwait compliance (1:1) - only the columns the sheet carries
      are written; anything already entered elsewhere is kept.
================================================================ */
UPDATE ec
   SET CivilIdNumber        = i.CivilIdNumber,
       CivilIdExpiryDate    = i.CivilIdExpiry,
       PassportNumber       = i.PassportNumber,
       PassportCountryId    = r.NationalityCountryId,
       PassportExpiryDate   = i.PassportExpiry,
       WorkPermitExpiryDate = i.WorkPermitExpiry,
       SponsorStatus        = i.SponsorStatus,
       ResidencyStatus      = i.ResidencyStatus,
       ModifiedBy           = @UserId,
       ModifiedDate         = SYSUTCDATETIME()
FROM [Kuwait].[EmployeeCompliance] ec
JOIN @Rows   r ON r.EmployeeId   = ec.EmployeeId
JOIN @Import i ON i.EmployeeCode = r.EmployeeCode;

INSERT INTO [Kuwait].[EmployeeCompliance]
    (EmployeeId, CivilIdNumber, CivilIdExpiryDate, PassportNumber, PassportCountryId, PassportExpiryDate,
     WorkPermitExpiryDate, SponsorStatus, ResidencyStatus, CreatedBy)
SELECT r.EmployeeId, i.CivilIdNumber, i.CivilIdExpiry, i.PassportNumber, r.NationalityCountryId, i.PassportExpiry,
       i.WorkPermitExpiry, i.SponsorStatus, i.ResidencyStatus, @UserId
FROM @Rows r
JOIN @Import i ON i.EmployeeCode = r.EmployeeCode
WHERE NOT EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] ec WHERE ec.EmployeeId = r.EmployeeId);

/* ================================================================
   9. Payroll & bank (1:1)
================================================================ */
UPDATE p
   SET BasicSalary  = i.BasicSalary,
       Allowances   = i.Allowances,
       BankName     = i.BankName,
       Iban         = i.Iban,
       ModifiedBy   = @UserId,
       ModifiedDate = SYSUTCDATETIME()
FROM [Employee].[EmployeePayroll] p
JOIN @Rows   r ON r.EmployeeId   = p.EmployeeId
JOIN @Import i ON i.EmployeeCode = r.EmployeeCode;

INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
SELECT r.EmployeeId, i.BasicSalary, i.Allowances, i.BankName, i.Iban, @UserId
FROM @Rows r
JOIN @Import i ON i.EmployeeCode = r.EmployeeCode
WHERE NOT EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] p WHERE p.EmployeeId = r.EmployeeId);

COMMIT TRANSACTION;

PRINT N'Employee import finished for CompanyId ' + CAST(@CompanyId AS NVARCHAR(10))
    + N': ' + CAST(@Inserted AS NVARCHAR(10)) + N' inserted, ' + CAST(@Updated AS NVARCHAR(10)) + N' updated.';

/* ================================================================
   10. What was loaded - check for blanks in the ID columns
================================================================ */
SELECT  e.EmployeeCode, CONCAT(e.FirstName, N' ', e.LastName) AS FullName,
        nc.CountryName AS Nationality, d.DepartmentName, dg.DesignationName, l.LocationName,
        e.EmploymentType, e.EmploymentStatus,
        ec.CivilIdNumber, ec.CivilIdExpiryDate, ec.PassportNumber, ec.ResidencyStatus,
        p.BasicSalary, p.Allowances, p.BankName
FROM        [Employee].[Employees]         e
JOIN        @Rows                          r  ON r.EmployeeId     = e.EmployeeId
LEFT JOIN   [Core].[Countries]             nc ON nc.CountryId     = e.NationalityCountryId
LEFT JOIN   [Core].[Departments]           d  ON d.DepartmentId   = e.DepartmentId
LEFT JOIN   [Core].[Designations]          dg ON dg.DesignationId = e.DesignationId
LEFT JOIN   [Core].[Locations]             l  ON l.LocationId     = e.WorkLocationId
LEFT JOIN   [Kuwait].[EmployeeCompliance]  ec ON ec.EmployeeId    = e.EmployeeId
LEFT JOIN   [Employee].[EmployeePayroll]   p  ON p.EmployeeId     = e.EmployeeId
ORDER BY    e.EmployeeCode;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(4000) = N'Employee import rolled back - nothing was saved. ' + ERROR_MESSAGE()
        + N' (line ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + N')';
    RAISERROR(@Err, 16, 1);
END CATCH;
GO
