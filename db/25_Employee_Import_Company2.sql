/* ================================================================
   HRMS Kuwait - Employee master data import: CompanyId = 2 (20 employees)
   ----------------------------------------------------------------
   Same column mapping and rules as db/21 (which loaded the first
   company), for the second company's spreadsheet. Run AFTER db/20
   (which adds the columns this fills); db/21 does not need to have run.

   RE-RUNNABLE: an employee is matched within CompanyId 2 on
   EmployeeCode, or - for the two rows whose Emp Code is "N/A" - on
   their Civil ID. Matched rows are UPDATED, the rest INSERTED.

   ROWS TO CHECK AFTER LOADING
     * Sl. 19 Omran Salman and Sl. 20 Al-Kull Sattar have no Emp Code
       ("N/A"). They load with EmployeeCode empty and EmployeeNo
       NA-19 / NA-20 (EmployeeNo is required). Set their real codes on
       the Profile page once assigned.
     * Sl. 10 to 20 have 13-digit Civil IDs (e.g. 2880110123410).
       Kuwait Civil IDs are 12 digits and the Kuwait Compliance tab only
       accepts 12 - they are imported exactly as given, but saving that
       tab for these employees will ask for a valid 12-digit number.
     * Emergency contact is "Family Contact" with no relationship, so
       EmergencyContactRelation is left empty.
     * Sl. 20 Al-Kull Sattar has Basic Salary and Allowances of 0.000.

   WHERE EACH SPREADSHEET COLUMN GOES
   ----------------------------------------------------------------
   Emp Code                -> Employees.EmployeeCode AND EmployeeNo
                              ("N/A" -> code empty, EmployeeNo NA-<Sl.No>)
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
   1. Run db/20 first (it adds the columns this script fills).
   2. Run the whole file in one go - it is a single batch.
   3. Check the result grid at the end for blank ID columns.
================================================================ */
SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET NOCOUNT ON;
GO

DECLARE @CompanyId   INT          = 2;      -- <-- target company
DECLARE @UserId      BIGINT       = NULL;   -- optional: Security.Users.UserId to stamp CreatedBy

IF NOT EXISTS (SELECT 1 FROM [Core].[Companies] WHERE CompanyId = @CompanyId)
BEGIN
    RAISERROR(N'Core.Companies has no CompanyId 2. Create the company first (Setup > Companies), or change @CompanyId at the top of this script.', 16, 1);
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
    SlNo              INT           NOT NULL PRIMARY KEY,
    EmployeeCode      NVARCHAR(20)  NULL,
    EmployeeNo        NVARCHAR(20)  NOT NULL,
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
    (1, N'1001', N'1001', N'Muhammad', N'Ramadan Abdul Qawi', N'Ahmed', N'M', N'1991-01-15', N'Egyptian', N'288010112341', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'muhammad1@fallahalhamad.com', N'+965 90000001', N'Uniform, Tools', N'N0000001', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000001', N'muhammad1@gmail.com', N'Salmiya, Block 1, St 1', N'Salmiya', N'1', N'Street 1', N'Family Contact', NULL, N'+965 99900001', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000001'),
    (2, N'1003', N'1003', N'Ramadan', N'El-Sayed Morsi', N'Gad El-Rabb', N'M', N'1992-01-15', N'Egyptian', N'288010212342', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'ramadan2@fallahalhamad.com', N'+965 90000002', N'Uniform, Tools', N'N0000002', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000002', N'ramadan2@gmail.com', N'Salmiya, Block 2, St 2', N'Salmiya', N'2', N'Street 2', N'Family Contact', NULL, N'+965 99900002', 270.000, 20.000, N'NBK', N'KW12NBBK00000000000002'),
    (3, N'1011', N'1011', N'Abdul Ghaffar', N'Sayed Abdul Majeed', N'El-Ghayaty', N'M', N'1993-01-15', N'Egyptian', N'288010312343', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'abdul3@fallahalhamad.com', N'+965 90000003', N'Uniform, Tools', N'N0000003', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000003', N'abdul3@gmail.com', N'Salmiya, Block 3, St 3', N'Salmiya', N'3', N'Street 3', N'Family Contact', NULL, N'+965 99900003', 250.000, 20.000, N'NBK', N'KW12NBBK00000000000003'),
    (4, N'2012', N'2012', N'Arsat', N'Jonathan', N'Philemon', N'M', N'1994-01-15', N'Filipino', N'288010412344', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'arsat4@fallahalhamad.com', N'+965 90000004', N'Uniform, Tools', N'N0000004', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000004', N'arsat4@gmail.com', N'Salmiya, Block 4, St 4', N'Salmiya', N'4', N'Street 4', N'Family Contact', NULL, N'+965 99900004', 110.000, 20.000, N'NBK', N'KW12NBBK00000000000004'),
    (5, N'2008', N'2008', N'Sahajan', N'Wamaindol', N'Haq', N'M', N'1995-01-15', N'Bangladeshi', N'288010512345', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'sahajan5@fallahalhamad.com', N'+965 90000005', N'Uniform, Tools', N'N0000005', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000005', N'sahajan5@gmail.com', N'Salmiya, Block 5, St 5', N'Salmiya', N'5', N'Street 5', N'Family Contact', NULL, N'+965 99900005', 130.000, 20.000, N'NBK', N'KW12NBBK00000000000005'),
    (6, N'2027', N'2027', N'Muhammad', N'Shaujan Hasen', N'Miah', N'M', N'1996-01-15', N'Bangladeshi', N'288010612346', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'muhammad6@fallahalhamad.com', N'+965 90000006', N'Uniform, Tools', N'N0000006', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000006', N'muhammad6@gmail.com', N'Salmiya, Block 6, St 6', N'Salmiya', N'6', N'Street 6', N'Family Contact', NULL, N'+965 99900006', 130.000, 20.000, N'NBK', N'KW12NBBK00000000000006'),
    (7, N'2030', N'2030', N'Mostafa', N'Salimo', N'Kampino', N'M', N'1997-01-15', N'Indian', N'288010712347', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'mostafa7@fallahalhamad.com', N'+965 90000007', N'Uniform, Tools', N'N0000007', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000007', N'mostafa7@gmail.com', N'Salmiya, Block 7, St 7', N'Salmiya', N'7', N'Street 7', N'Family Contact', NULL, N'+965 99900007', 120.000, 20.000, N'NBK', N'KW12NBBK00000000000007'),
    (8, N'2032', N'2032', N'Nasrullah', N'Rashid Masood', N'Al-Ghul', N'M', N'1998-01-15', N'Jordanian', N'288010812348', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'nasrullah8@fallahalhamad.com', N'+965 90000008', N'Uniform, Tools', N'N0000008', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000008', N'nasrullah8@gmail.com', N'Salmiya, Block 8, St 8', N'Salmiya', N'8', N'Street 8', N'Family Contact', NULL, N'+965 99900008', 270.000, 20.000, N'NBK', N'KW12NBBK00000000000008'),
    (9, N'1030', N'1030', N'Muhammad', N'Jahangir', N'Hossain M.D.', N'M', N'1999-01-15', N'Bangladeshi', N'288010912349', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'muhammad9@fallahalhamad.com', N'+965 90000009', N'Uniform, Tools', N'N0000009', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000009', N'muhammad9@gmail.com', N'Salmiya, Block 9, St 9', N'Salmiya', N'9', N'Street 9', N'Family Contact', NULL, N'+965 99900009', 130.000, 20.000, N'NBK', N'KW12NBBK00000000000009'),
    (10, N'1031', N'1031', N'Jamaluddin', N'Amedy', N'Watilotte', N'M', N'1990-01-15', N'Indian', N'2880110123410', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'jamaluddin10@fallahalhamad.com', N'+965 90000010', N'Uniform, Tools', N'N0000010', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000010', N'jamaluddin10@gmail.com', N'Salmiya, Block 10, St 10', N'Salmiya', N'10', N'Street 10', N'Family Contact', NULL, N'+965 99900010', 130.000, 20.000, N'NBK', N'KW12NBBK00000000000010'),
    (11, N'1032', N'1032', N'Yazan', N'Imad Salim', N'Al-Rawaosheh', N'M', N'1991-01-15', N'Jordanian', N'2880111123411', N'Married', N'2025-01-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'yazan11@fallahalhamad.com', N'+965 90000011', N'Uniform, Tools', N'N0000011', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000011', N'yazan11@gmail.com', N'Salmiya, Block 11, St 11', N'Salmiya', N'11', N'Street 11', N'Family Contact', NULL, N'+965 99900011', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000011'),
    (12, N'2033', N'2033', N'Ahmed', N'Khaled Abdul Rahman', N'Barakat', N'M', N'1992-01-15', N'Egyptian', N'2880112123412', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'ahmed12@fallahalhamad.com', N'+965 90000012', N'Uniform, Tools', N'N0000012', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000012', N'ahmed12@gmail.com', N'Salmiya, Block 12, St 12', N'Salmiya', N'12', N'Street 12', N'Family Contact', NULL, N'+965 99900012', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000012'),
    (13, N'1037', N'1037', N'Muhammad', N'Abdul Sattar Ayoub', N'Abdul Rahman', N'M', N'1993-01-15', N'Pakistani', N'2880113123413', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'muhammad13@fallahalhamad.com', N'+965 90000013', N'Uniform, Tools', N'N0000013', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000013', N'muhammad13@gmail.com', N'Salmiya, Block 13, St 13', N'Salmiya', N'13', N'Street 13', N'Family Contact', NULL, N'+965 99900013', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000013'),
    (14, N'1038', N'1038', N'Faisal', N'Zaghloul Khalil', N'Ahmed', N'M', N'1994-01-15', N'Egyptian', N'2880114123414', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'faisal14@fallahalhamad.com', N'+965 90000014', N'Uniform, Tools', N'N0000014', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000014', N'faisal14@gmail.com', N'Salmiya, Block 14, St 14', N'Salmiya', N'14', N'Street 14', N'Family Contact', NULL, N'+965 99900014', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000014'),
    (15, N'1039', N'1039', N'Ammar', N'Abdul Ghani', N'Salloum', N'M', N'1995-01-15', N'Syrian', N'2880115123415', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'ammar15@fallahalhamad.com', N'+965 90000015', N'Uniform, Tools', N'N0000015', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000015', N'ammar15@gmail.com', N'Salmiya, Block 15, St 15', N'Salmiya', N'15', N'Street 15', N'Family Contact', NULL, N'+965 99900015', 190.000, 20.000, N'NBK', N'KW12NBBK00000000000015'),
    (16, N'2044', N'2044', N'Hussein', N'Ahmed Faraj', N'Allaw', N'M', N'1996-01-15', N'Lebanese', N'2880116123416', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'hussein16@fallahalhamad.com', N'+965 90000016', N'Uniform, Tools', N'N0000016', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000016', N'hussein16@gmail.com', N'Salmiya, Block 16, St 16', N'Salmiya', N'16', N'Street 16', N'Family Contact', NULL, N'+965 99900016', 180.000, 20.000, N'NBK', N'KW12NBBK00000000000016'),
    (17, N'2045', N'2045', N'Abdullah', N'Ali', N'Hariq', N'M', N'1997-01-15', N'Yemeni', N'2880117123417', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'abdullah17@fallahalhamad.com', N'+965 90000017', N'Uniform, Tools', N'N0000017', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000017', N'abdullah17@gmail.com', N'Salmiya, Block 17, St 17', N'Salmiya', N'17', N'Street 17', N'Family Contact', NULL, N'+965 99900017', 220.000, 20.000, N'NBK', N'KW12NBBK00000000000017'),
    (18, N'2017', N'2017', N'Ahmed', N'Abdul Rasul Al-Dawwi', N'Muhammad', N'M', N'1998-01-15', N'Egyptian', N'2880118123418', N'Married', N'2026-09-01', N'Engineer', N'Technical', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'ahmed18@fallahalhamad.com', N'+965 90000018', N'Uniform, Tools', N'N0000018', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000018', N'ahmed18@gmail.com', N'Salmiya, Block 18, St 18', N'Salmiya', N'18', N'Street 18', N'Family Contact', NULL, N'+965 99900018', 250.000, 20.000, N'NBK', N'KW12NBBK00000000000018'),
    (19, NULL, N'NA-19', N'Omran', N'Salman Abdul Majeed', N'Salman', N'M', N'1999-01-15', N'Iraqi', N'2880119123419', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'omran19@fallahalhamad.com', N'+965 90000019', N'Uniform, Tools', N'N0000019', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000019', N'omran19@gmail.com', N'Salmiya, Block 19, St 19', N'Salmiya', N'19', N'Street 19', N'Family Contact', NULL, N'+965 99900019', 161.000, 20.000, N'NBK', N'KW12NBBK00000000000019'),
    (20, NULL, N'NA-20', N'Al-Kull', NULL, N'Sattar', N'M', N'1990-01-15', N'Indian', N'2880120123420', N'Married', N'2026-09-01', N'Technician', N'Operations', N'Site Work', N'Full-Time', N'Active', N'Company Sponsor', N'al-kull20@fallahalhamad.com', N'+965 90000020', N'Uniform, Tools', N'N0000020', N'2028-05-10', N'2027-05-14', N'2027-05-14', N'Valid', N'+965 50000020', N'al-kull20@gmail.com', N'Salmiya, Block 20, St 20', N'Salmiya', N'20', N'Street 20', N'Family Contact', NULL, N'+965 99900020', 0.000, 0.000, N'NBK', N'KW12NBBK00000000000020');

/* ================================================================
   1. Lookup maps: spreadsheet text -> master record
      (Code = what to look for / create; Name = display name)
================================================================ */
DECLARE @CountryMap TABLE (Nationality NVARCHAR(50) PRIMARY KEY, CountryCode NVARCHAR(10), CountryName NVARCHAR(100));
INSERT INTO @CountryMap VALUES
    (N'Egyptian',    N'EG', N'Egypt'),
    (N'Filipino',    N'PH', N'Philippines'),
    (N'Bangladeshi', N'BD', N'Bangladesh'),
    (N'Indian',      N'IN', N'India'),
    (N'Jordanian',   N'JO', N'Jordan'),
    (N'Pakistani',   N'PK', N'Pakistan'),
    (N'Syrian',      N'SY', N'Syria'),
    (N'Lebanese',    N'LB', N'Lebanon'),
    (N'Yemeni',      N'YE', N'Yemen'),
    (N'Iraqi',       N'IQ', N'Iraq');

-- Sheet department -> existing seed code (db/12) where one clearly fits,
-- otherwise a new department is created with this code/name.
DECLARE @DeptMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DeptCode NVARCHAR(20), DeptName NVARCHAR(150));
INSERT INTO @DeptMap VALUES
    (N'Technical',  N'TECH', N'Technical'),
    (N'Operations', N'OPS',  N'Operations');

DECLARE @DesigMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, DesigCode NVARCHAR(20), DesigName NVARCHAR(150), ArabicName NVARCHAR(150));
INSERT INTO @DesigMap VALUES
    (N'Engineer',   N'DSG-ENG',  N'Engineer',   N'مهندس'),
    (N'Technician', N'DSG-TECH', N'Technician', N'فني');

DECLARE @LocMap TABLE (SheetName NVARCHAR(150) PRIMARY KEY, LocCode NVARCHAR(20), LocName NVARCHAR(150), LocType NVARCHAR(50), Governorate NVARCHAR(100), Area NVARCHAR(100));
INSERT INTO @LocMap VALUES
    (N'Site Work', N'LOC-SITEWORK', N'Site Work', N'Site', NULL, NULL);

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
    SlNo INT PRIMARY KEY, EmployeeCode NVARCHAR(20) NULL, EmployeeNo NVARCHAR(20), EmployeeId BIGINT NULL,
    NationalityCountryId INT, DepartmentId INT, CostCenterId INT,
    DesignationId INT, WorkLocationId INT, BranchId INT);

INSERT INTO @Rows (SlNo, EmployeeCode, EmployeeNo, EmployeeId, NationalityCountryId, DepartmentId, CostCenterId, DesignationId, WorkLocationId, BranchId)
SELECT i.SlNo, i.EmployeeCode, i.EmployeeNo,
       -- match on Emp Code; rows without one ("N/A") match on Civil ID
       CASE WHEN i.EmployeeCode IS NOT NULL
            THEN (SELECT TOP 1 e.EmployeeId FROM [Employee].[Employees] e
                  WHERE e.CompanyId = @CompanyId AND e.EmployeeCode = i.EmployeeCode)
            ELSE (SELECT TOP 1 e.EmployeeId FROM [Employee].[Employees] e
                  JOIN [Kuwait].[EmployeeCompliance] ec ON ec.EmployeeId = e.EmployeeId
                  WHERE e.CompanyId = @CompanyId AND ec.CivilIdNumber = i.CivilIdNumber)
       END,
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
   SET EmployeeCode             = ISNULL(i.EmployeeCode, e.EmployeeCode),
       EmployeeNo               = CASE WHEN i.EmployeeCode IS NULL THEN e.EmployeeNo ELSE i.EmployeeNo END,
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
JOIN @Import i ON i.SlNo = r.SlNo;

DECLARE @Updated INT = @@ROWCOUNT;

INSERT INTO [Employee].[Employees]
    (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, Gender, DateOfBirth, MaritalStatus,
     NationalityCountryId, MobileNumber, PersonalEmail, WorkEmail, Address, Neighborhood, Block, StreetName,
     EmergencyContactName, EmergencyContactPhone, EmergencyContactRelation, FatherIsDeceased,
     CompanyId, BranchId, DepartmentId, DesignationId, CostCenterId, WorkLocationId,
     HireDate, EmploymentType, EmploymentStatus, CompanyPhone, CompanyAssets, IsDeleted, CreatedBy)
SELECT i.EmployeeCode, i.EmployeeNo, i.FirstName, i.MiddleName, i.LastName, i.Gender, i.DateOfBirth, i.MaritalStatus,
       r.NationalityCountryId, i.MobileNumber, i.PersonalEmail, i.WorkEmail, i.Address, i.Neighborhood, i.Block, i.StreetName,
       i.EmergencyName, i.EmergencyPhone, i.EmergencyRelation, 0,
       @CompanyId, r.BranchId, r.DepartmentId, r.DesignationId, r.CostCenterId, r.WorkLocationId,
       i.HireDate, i.EmploymentType, i.EmploymentStatus, i.CompanyPhone, i.CompanyAssets, 0, @UserId
FROM @Import i
JOIN @Rows r ON r.SlNo = i.SlNo
WHERE r.EmployeeId IS NULL;

DECLARE @Inserted INT = @@ROWCOUNT;

UPDATE r
   SET EmployeeId = e.EmployeeId
FROM @Rows r
JOIN [Employee].[Employees] e ON e.CompanyId = @CompanyId
                              AND (e.EmployeeCode = r.EmployeeCode
                                   OR (r.EmployeeCode IS NULL AND e.EmployeeCode IS NULL AND e.EmployeeNo = r.EmployeeNo))
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
JOIN @Import i ON i.SlNo = r.SlNo;

INSERT INTO [Kuwait].[EmployeeCompliance]
    (EmployeeId, CivilIdNumber, CivilIdExpiryDate, PassportNumber, PassportCountryId, PassportExpiryDate,
     WorkPermitExpiryDate, SponsorStatus, ResidencyStatus, CreatedBy)
SELECT r.EmployeeId, i.CivilIdNumber, i.CivilIdExpiry, i.PassportNumber, r.NationalityCountryId, i.PassportExpiry,
       i.WorkPermitExpiry, i.SponsorStatus, i.ResidencyStatus, @UserId
FROM @Rows r
JOIN @Import i ON i.SlNo = r.SlNo
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
JOIN @Import i ON i.SlNo = r.SlNo;

INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, Allowances, BankName, Iban, CreatedBy)
SELECT r.EmployeeId, i.BasicSalary, i.Allowances, i.BankName, i.Iban, @UserId
FROM @Rows r
JOIN @Import i ON i.SlNo = r.SlNo
WHERE NOT EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] p WHERE p.EmployeeId = r.EmployeeId);

COMMIT TRANSACTION;

PRINT N'Employee import finished for CompanyId ' + CAST(@CompanyId AS NVARCHAR(10))
    + N': ' + CAST(@Inserted AS NVARCHAR(10)) + N' inserted, ' + CAST(@Updated AS NVARCHAR(10)) + N' updated.';

/* ================================================================
   10. What was loaded - check for blanks in the ID columns
================================================================ */
SELECT  e.EmployeeCode, e.EmployeeNo, CONCAT(e.FirstName, N' ', e.LastName) AS FullName,
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
ORDER BY    r.SlNo;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(4000) = N'Employee import rolled back - nothing was saved. ' + ERROR_MESSAGE()
        + N' (line ' + CAST(ERROR_LINE() AS NVARCHAR(10)) + N')';
    RAISERROR(@Err, 16, 1);
END CATCH;
GO
