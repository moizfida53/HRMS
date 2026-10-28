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
     - Not in the sheet, left blank to fill in later on the employee
       profile: hire date, marital status, mobile, department, allowances,
       bank, work permit number / expiry; nationality for 19 employees.
     - The passport status (✓ / X) is not imported. The notes column has
       no field in the app - it is listed at the end of the run.

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


/* ---- the companies ------------------------------------------------- */
DECLARE @Company TABLE (Code NVARCHAR(30) PRIMARY KEY, NameEn NVARCHAR(200), LegalAr NVARCHAR(300), CompanyId INT NULL);
INSERT INTO @Company (Code, NameEn, LegalAr) VALUES
    (N'RAND', N'RAND General Trading & Contracting Co.', N'شركة راند للتجارة العامة والمقاولات'),
    (N'FH', N'Falafel Hamada', N'فلافل حماده للمأكولات الخفيفة'),
    (N'4MG', N'4 MG Digital Printing', N'فور أم ديجيتال لأعمال الطباعة'),
    (N'IGM', N'IGM Computer - Security Devices & Systems', N'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها'),
    (N'BURUJ', N'Buruj Commission Agent', N'بروج وكيل بالعمولة والتجار بالعمولة'),
    (N'ZAFIR', N'Zafir Watches & Jewellery', N'زفير للبيع بالتجزئة للساعات بأنواعها والمجوهرات والمصوغات');

/* ---- company documents (licences): one row per licence ---------------- */
DECLARE @TypeDef TABLE (TypeKey VARCHAR(10) PRIMARY KEY, TypeName NVARCHAR(150), ArabicName NVARCHAR(150), Category VARCHAR(20), AuthorityShort NVARCHAR(20) NULL);
INSERT INTO @TypeDef VALUES
    (N'COMM', N'Commercial License', N'الرخصة التجارية', N'LICENSE', N'MOCI'),
    (N'IMPORT', N'Import License', N'رخصة استيراد', N'LICENSE', N'MOCI'),
    (N'PAMSIG', N'PAM Signature Authorization', N'اعتماد توقيع الشؤون', N'AUTHORIZATION', N'PAM'),
    (N'ADV', N'Advertising License', N'ترخيص الإعلان', N'LICENSE', N'KM'),
    (N'IND', N'Industrial License', N'الترخيص الصناعي', N'LICENSE', N'PAI'),
    (N'FIRE', N'Fire Force License', N'ترخيص الإطفاء', N'LICENSE', N'KFF'),
    (N'PRESS', N'Printing Press License', N'ترخيص مطبعة', N'LICENSE', N'MOInf'),
    (N'INS', N'Workers Insurance Policy', N'وثيقة التأمين', N'INSURANCE', NULL),
    (N'INJ', N'Work Injury Statistics', N'إحصائية إصابات العمل', N'REGISTRATION', N'PAM'),
    (N'NFUND', N'National Fund Registration Certificate', N'شهادة قيد بالسجل الوطني', N'REGISTRATION', N'NFSMED'),
    (N'TRSIG', N'Traffic Signature Authorization', N'اعتماد توقيع المرور', N'AUTHORIZATION', N'GTD'),
    (N'TENDC', N'Public Tenders Registration Certificate', N'شهادة المناقصات', N'REGISTRATION', N'CAPT'),
    (N'TENDS', N'Public Tenders Signature Authorization', N'اعتماد توقيع لجنة المناقصات العامة', N'AUTHORIZATION', N'CAPT'),
    (N'ENVC', N'Environment Certificate', N'شهادة البيئة', N'LICENSE', N'EPA'),
    (N'ENVU', N'Environment Data Update', N'تحديث بيانات البيئة', N'REGISTRATION', N'EPA'),
    (N'MEDW', N'Medical Waste Transport License', N'ترخيص بمزاولة نقل النفايات الطبية', N'LICENSE', N'MOH'),
    (N'MEDV1', N'Medical Waste Vehicle License 21-11532', N'ترخيص مركبة لنقل النفايات الطبية 21-11532', N'LICENSE', N'MOH'),
    (N'MEDV2', N'Medical Waste Vehicle License 5-82116', N'ترخيص مركبة لنقل النفايات الطبية 5-82116', N'LICENSE', N'MOH'),
    (N'MEDD1', N'Medical Waste Driver License - Ashraf', N'ترخيص قيادة مركبة نفايات طبية - أشرف', N'LICENSE', N'MOH'),
    (N'MEDD2', N'Medical Waste Driver License - Abu Ali', N'ترخيص قيادة مركبة نفايات طبية - أبو علي', N'LICENSE', N'MOH'),
    (N'HLTH_H', N'Health License - Hawally', N'الترخيص الصحي - حولي', N'LICENSE', N'PAFN'),
    (N'HLTH_Q', N'Health License - Qasr Al-Diyafa', N'الترخيص الصحي - قصر الضيافة', N'LICENSE', N'KM'),
    (N'TM', N'Trademark Certificate', N'شهادة العلامة التجارية', N'REGISTRATION', N'MOCI'),
    (N'COMM_S', N'Commercial License - Salmiya', N'الرخصة التجارية - السالمية', N'LICENSE', N'MOCI'),
    (N'COMM_Q', N'Commercial License - Qasr Al-Diyafa', N'الرخصة التجارية - قصر الضيافة', N'LICENSE', N'MOCI');
DECLARE @Doc TABLE (Seq INT IDENTITY(1, 1), CompanyCode NVARCHAR(30), TypeKey VARCHAR(10), DocNumber NVARCHAR(100), Authority NVARCHAR(150), IssueDate DATE, ExpiryDate DATE, Notes NVARCHAR(500));
INSERT INTO @Doc (CompanyCode, TypeKey, DocNumber, Authority, IssueDate, ExpiryDate, Notes) VALUES
    (N'RAND', N'COMM', N'6620/2006', N'وزارة التجارة', N'2026-06-08', N'2026-09-07', NULL),
    (N'RAND', N'NFUND', N'117609', N'الصندوق الوطني', N'2025-11-06', N'2026-11-05', NULL),
    (N'RAND', N'PAMSIG', N'100028815', N'الهيئة العامة للقوى العاملة', N'2025-11-19', N'2026-11-14', NULL),
    (N'RAND', N'TRSIG', N'275908', N'إدارة المرور', N'2025-04-24', N'2026-06-18', NULL),
    (N'RAND', N'TENDC', N'13420', N'الجهاز المركزي للمناقصات العامة', N'2025-05-31', N'2026-05-30', NULL),
    (N'RAND', N'TENDS', N'13420', N'الجهاز المركزي للمناقصات العامة', N'2017-04-01', N'2027-03-31', NULL),
    (N'RAND', N'ENVC', N'6620/2006', N'الهيئة العامة للبيئة', N'2025-08-31', N'2027-08-31', NULL),
    (N'RAND', N'ENVU', N'6620/2006', N'الهيئة العامة للبيئة', N'2026-07-01', N'2026-12-31', NULL),
    (N'RAND', N'MEDW', N'117609', N'وزارة الصحة', N'2024-07-06', N'2029-07-07', NULL),
    (N'RAND', N'MEDV1', N'11532/21', N'وزارة الصحة', N'2026-03-17', N'2027-03-16', NULL),
    (N'RAND', N'MEDV2', N'82116/5', N'وزارة الصحة', NULL, NULL, N'يتعذر التجديد لتجاوز صنع المركبة 10 سنوات'),
    (N'RAND', N'MEDD1', N'14', N'وزارة الصحة', N'2025-03-25', N'2027-04-29', NULL),
    (N'RAND', N'MEDD2', N'14', N'وزارة الصحة', N'2025-03-25', N'2027-04-29', NULL),
    (N'RAND', N'INS', N'WC/27/2025/01/115/3063', N'شركة زمزم للتأمين التكافلي', N'2025-10-01', N'2026-09-30', NULL),
    (N'RAND', N'INJ', N'100028815', N'الهيئة العامة للقوى العاملة', N'2026-10-01', N'2026-12-31', NULL),
    (N'FH', N'COMM', N'2020/2023', N'وزارة التجارة', N'2026-07-22', N'2030-07-21', N'حولي'),
    (N'FH', N'FIRE', N'226912839', N'قوة الإطفاء', N'2026-07-21', N'2028-07-21', N'حولي'),
    (N'FH', N'HLTH_H', N'812/2025', N'الهيئة العامة للغذاء والتغذية', N'2026-08-30', N'2027-08-29', NULL),
    (N'FH', N'ADV', N'22683/2026', N'بلدية الكويت', N'2026-08-26', N'2030-07-20', N'حولي'),
    (N'FH', N'TM', N'156515', N'وزارة التجارة', N'2016-11-08', N'2026-11-08', N'حولي'),
    (N'FH', N'PAMSIG', N'100199869', N'الهيئة العامة للقوى العاملة', N'2026-08-18', N'2027-08-13', NULL),
    (N'FH', N'TRSIG', N'398530', N'إدارة المرور', N'2026-09-15', N'2027-09-14', NULL),
    (N'FH', N'COMM_S', N'19646/2024', N'وزارة التجارة', N'2024-07-03', N'2028-07-02', NULL),
    (N'FH', N'INJ', N'100199869', N'الهيئة العامة للقوى العاملة', N'2026-10-01', N'2026-12-31', NULL),
    (N'FH', N'INS', N'WC/01/27/13144/16/2025', N'الشركة العربية الإسلامية للتأمين التكافلي', N'2025-12-17', N'2026-12-16', NULL),
    (N'FH', N'COMM_Q', N'3495/2018', N'وزارة التجارة', N'2018-10-08', N'2030-09-07', NULL),
    (N'FH', N'HLTH_Q', N'957/2025', N'بلدية الكويت', N'2025-09-14', N'2026-09-13', NULL),
    (N'4MG', N'IND', N'27034', N'الهيئة العامة للصناعة', N'2011-05-11', N'2028-11-12', NULL),
    (N'4MG', N'FIRE', N'224903935', N'قوة الإطفاء العامة', N'2026-06-10', N'2028-06-10', N'شركة النفيسي'),
    (N'4MG', N'ADV', N'20243/2025', N'بلدية الكويت', N'2026-09-27', N'2027-09-07', NULL),
    (N'4MG', N'PRESS', N'MOIP/2023/516/000577', N'وزارة الإعلام', N'2023-10-30', N'2026-10-29', NULL),
    (N'4MG', N'INS', N'WC/27/2025/01/115/3063', N'شركة زمزم للتأمين التكافلي', N'2025-10-01', N'2026-09-30', NULL),
    (N'4MG', N'INJ', N'100028815', N'الهيئة العامة للقوى العاملة', N'2026-10-01', N'2026-12-31', NULL),
    (N'IGM', N'COMM', N'20693/2020', N'وزارة التجارة', N'2025-03-10', N'2029-03-09', NULL),
    (N'IGM', N'IMPORT', N'202107750', N'وزارة التجارة', N'2026-06-10', N'2027-06-09', NULL),
    (N'IGM', N'PAMSIG', N'100236995', N'الهيئة العامة للقوى العاملة', N'2026-06-10', N'2027-06-05', NULL),
    (N'BURUJ', N'COMM', N'13246/2025', N'وزارة التجارة', N'2025-08-17', N'2029-08-16', NULL),
    (N'BURUJ', N'PAMSIG', N'100245967', N'الهيئة العامة للقوى العاملة', N'2026-09-23', N'2027-09-18', NULL),
    (N'BURUJ', N'ADV', N'28774/2026', N'بلدية الكويت', N'2026-02-23', N'2027-02-23', NULL),
    (N'ZAFIR', N'COMM', N'25004/2024', N'وزارة التجارة', N'2024-09-16', N'2028-09-15', NULL),
    (N'ZAFIR', N'ADV', N'27100/2026', N'بلدية الكويت', N'2026-01-27', N'2028-09-14', NULL),
    (N'ZAFIR', N'PAMSIG', N'100228817', N'الهيئة العامة للقوى العاملة', N'2025-12-01', N'2026-11-26', NULL);

/* ---- vehicles -> Assets ----------------------------------------------- */
DECLARE @Vehicle TABLE (Seq INT IDENTITY(1, 1), CompanyCode NVARCHAR(30), TypeName NVARCHAR(100), Brand NVARCHAR(100), Model NVARCHAR(100), Color NVARCHAR(50), Plate NVARCHAR(100), ExpiryDate DATE, Notes NVARCHAR(500));
INSERT INTO @Vehicle (CompanyCode, TypeName, Brand, Model, Color, Plate, ExpiryDate, Notes) VALUES
    (N'RAND', N'Cars', N'Toyota', N'Jeep - 2012', NULL, N'7/59908', N'2027-03-06', N'جيب تويوتا موديل 2012 - المدير العام - registered 2026-03-07'),
    (N'RAND', N'Trucks & Pickups', N'Mitsubishi', N'Pickup - 2013', N'White', N'8/78001', N'2026-11-29', N'نصف شاحنة ميتسوبيشي أبيض موديل 2013 - المشرف عزيز - registered 2025-11-30'),
    (N'RAND', N'Cars', N'Hyundai', N'Jeep - 2015', NULL, N'6/8735', N'2026-10-09', N'جيب هونداي موديل 2015 - سامي - registered 2025-10-10'),
    (N'RAND', N'Trucks & Pickups', N'Mitsubishi', N'Pickup - 2010', N'White', N'5/82116', N'2026-11-29', N'نصف شاحنة ميتسوبيشي أبيض موديل 2010 - أبو علي حقي - registered 2024-10-24'),
    (N'RAND', N'Trucks & Pickups', N'Ashok Leyland', N'Pickup - 2021', NULL, N'21/11532', N'2027-02-16', N'نصف شاحنة أدوك ليلاند 2021 - المشرف عزيز - registered 2026-02-17'),
    (N'FH', N'Motor Bikes', NULL, N'Motorcycle - 2020', NULL, N'7/3857', N'2025-03-06', N'دراجة نارية موديل 2020 - بها أحكام - حولي - registered 2024-03-07'),
    (N'FH', N'Motor Bikes', NULL, N'Motorcycle - 2022', NULL, N'7/5801', N'2027-05-28', N'دراجة نارية موديل 2022 - بركات - registered 2026-05-29'),
    (N'FH', N'Motor Bikes', NULL, N'Motorcycle - 2021', NULL, N'5/8564', N'2027-09-14', N'دراجة نارية موديل 2021 - registered 2026-09-15'),
    (N'FH', N'Cars', N'Kia', N'Saloon - 2017', N'White', N'15/48625', N'2027-10-14', N'صالون كيا ابيض موديل 2017 - أبو علي حنفي - registered 2026-10-15'),
    (N'FH', N'Trucks & Pickups', NULL, N'Saloon truck - 2024', N'White', N'22/49753', N'2027-04-02', N'صالون شاحنة ابيض موديل 2024 - عمران - registered 2026-04-03');

/* ---- nationalities ---------------------------------------------------- */
DECLARE @CountryMap TABLE (Nationality NVARCHAR(50) PRIMARY KEY, CountryCode NVARCHAR(10), CountryName NVARCHAR(100), CountryId INT NULL);
INSERT INTO @CountryMap (Nationality, CountryCode, CountryName) VALUES
    (N'Egyptian', N'EG', N'Egypt'),
    (N'Jordanian', N'JO', N'Jordan'),
    (N'Sudanese', N'SD', N'Sudan'),
    (N'Indian', N'IN', N'India'),
    (N'Bangladeshi', N'BD', N'Bangladesh'),
    (N'Syrian', N'SY', N'Syria'),
    (N'Filipino', N'PH', N'Philippines'),
    (N'Pakistani', N'PK', N'Pakistan'),
    (N'Lebanese', N'LB', N'Lebanon'),
    (N'Yemeni', N'YE', N'Yemen'),
    (N'Iraqi', N'IQ', N'Iraq');

/* ---- designations (the job title of the work permit, in English and Arabic) */
DECLARE @Job TABLE (JobCode NVARCHAR(20) PRIMARY KEY, NameEn NVARCHAR(150), NameAr NVARCHAR(150));
INSERT INTO @Job VALUES
    (N'DSG-ACC', N'Accountant', N'محاسب'),
    (N'DSG-ADMSUP', N'Administrative Supervisor', N'مراقب إداري'),
    (N'DSG-ASTCOOK', N'Assistant Cook', N'مساعد طاهي / طباخ'),
    (N'DSG-CASHIER', N'Cashier', N'صراف نقود / كاشير في المنشآت التجارية'),
    (N'DSG-CLEAR', N'Transactions Clearance Clerk', N'مخلص معاملات'),
    (N'DSG-CLERK', N'Administrative Clerk', N'كاتب إداري / عام'),
    (N'DSG-DRVBIKE', N'Driver - Motorcycle', N'سائق / دراجة نارية'),
    (N'DSG-DRVCAR', N'Driver - Private Car', N'سائق / سيارة خصوصي'),
    (N'DSG-DRVTRUCK', N'Driver - Truck', N'سائق / شاحنة'),
    (N'DSG-ELECGEN', N'Electrician - General Wiring', N'كهربائي تمديدات كهربائية / عام'),
    (N'DSG-ELECPNL', N'Control Panel Electrician', N'كهربائي لوحات مراقبة وتحكم'),
    (N'DSG-FFPREP', N'Fast Food Preparer', N'معد وجبات سريعة'),
    (N'DSG-FINADM', N'Finance & Administration Officer', N'مسؤول مالي وإداري'),
    (N'DSG-ITTECH', N'IT Systems Technician', N'فني نظم معلوماتية'),
    (N'DSG-JEWEL', N'Jewellery Salesperson', N'بائع مجوهرات'),
    (N'DSG-LEGAL', N'Legal Officer', N'مسؤول قانوني'),
    (N'DSG-LOAD', N'Loading Worker - Trucks', N'عامل تحميل / شاحنات'),
    (N'DSG-MSGR', N'Messenger', N'مراسل'),
    (N'DSG-PACK', N'Product Packing Worker', N'عامل تعبئة منتجات'),
    (N'DSG-ROLLOP', N'Paper Roll Machine Operator', N'مشغل / آلة تجهيز رولات الورق'),
    (N'DSG-SALESREP', N'Sales Representative (Field)', N'مندوب مبيعات (متجول)'),
    (N'DSG-STORE', N'Storekeeper', N'أمين مخزن'),
    (N'DSG-WHWORK', N'Warehouse Worker', N'عامل مخازن');

/* ---- the employees (sheet "Employee Data (3)" + "بيانات العمالة", matched on the civil ID) */
DECLARE @Import TABLE (
    Sl INT PRIMARY KEY, CompanyCode NVARCHAR(30) NOT NULL, WorkplaceCode NVARCHAR(30) NULL,
    EmployeeCode NVARCHAR(20) NOT NULL, CodeGenerated BIT NOT NULL,
    FirstName NVARCHAR(100) NOT NULL, MiddleName NVARCHAR(100) NULL, LastName NVARCHAR(100) NULL, ArabicName NVARCHAR(300) NULL,
    Gender CHAR(1) NULL, DateOfBirth DATE NULL, Nationality NVARCHAR(50) NULL,
    CivilIdNumber NVARCHAR(20) NOT NULL, CivilIdExpiry DATE NULL, PassportNumber NVARCHAR(30) NULL, PassportExpiry DATE NULL,
    BasicSalary DECIMAL(12, 3) NULL, PermitSalary DECIMAL(12, 3) NULL,
    JobCode NVARCHAR(20) NULL, SponsorName NVARCHAR(200) NULL, SheetNotes NVARCHAR(300) NULL);
INSERT INTO @Import VALUES
    (1, N'FH', NULL, N'1101', 1, N'Nasser', N'Haitham Saeed', N'Al-Wabar', N'ناصر هيثم سعيد الوبر', N'M', N'1960-10-09', NULL, N'260100902715', N'2027-01-11', N'11896891', N'2029-07-05', 350.000, 350.000, N'DSG-CLEAR', N'فلافل حماده للمأكولات الخفيفة', N'external (خارجية)'),
    (2, N'RAND', NULL, N'2001', 0, N'Ashraf', N'Aziz', N'Ghazi', N'اشرف عزيز غازي', N'M', N'1969-01-09', N'Jordanian', N'269010903694', N'2027-06-03', N'AP0494913', N'2036-07-12', 270.000, 250.000, N'DSG-DRVTRUCK', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (3, N'RAND', NULL, N'2002', 0, N'Abu Ali', N'Hafni Ahmed', N'Awadallah', N'أبو علي حفني أحمد عوض الله', N'M', N'1973-01-13', N'Egyptian', N'271011303247', N'2026-11-22', N'A28165362', N'2028-04-21', 280.000, 75.000, N'DSG-DRVTRUCK', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (4, N'RAND', NULL, N'2005', 0, N'Kawthar', N'Abdullah', N'Hussein', N'كوثر عبد الله حسين محمد أحمد', N'F', N'1992-08-20', N'Sudanese', N'282090800906', N'2026-11-30', NULL, NULL, 200.000, 200.000, N'DSG-ADMSUP', N'شركة راند للتجارة العامة والمقاولات', N'national labour (عمالة وطنية)'),
    (5, N'RAND', NULL, N'2006', 0, N'Sajal', N'Kumar Jahosh', N'Shisu', N'سجال كومار جهوش شيسو', N'M', N'1995-01-10', N'Indian', N'288011705482', N'2027-06-03', N'EK0674223', N'2027-07-03', 100.000, 75.000, N'DSG-PACK', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (6, N'RAND', NULL, N'2011', 0, N'Elias', N'Manik', N'Miah', N'الياس مانيك مياه', N'M', N'1990-03-03', N'Bangladeshi', N'290030106402', N'2027-06-03', N'EK0690670', N'2027-07-05', 85.000, 75.000, N'DSG-PACK', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (7, N'RAND', NULL, N'2017', 0, N'Ali', N'Mustafa', N'Bakri', N'علي مصطفى بكرى', N'M', N'1987-11-12', N'Jordanian', N'269041004464', N'2027-06-03', N'RL4297240', N'2028-05-31', 120.000, 250.000, N'DSG-ELECPNL', N'شركة راند للتجارة العامة والمقاولات', N'passport renewal'),
    (8, N'RAND', NULL, N'2025', 0, N'Ashraf', N'Shawqi Mohammed', N'Ahmed', N'أشرف شوقي محمد أحمد', N'M', N'1984-04-04', N'Jordanian', N'284040409545', NULL, NULL, NULL, 150.000, NULL, N'DSG-LEGAL', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (9, N'RAND', NULL, N'2031', 0, N'Bimal', N'Das Arjun', N'Das', N'بيمال داس ارجون داس', N'M', N'1987-10-21', N'Indian', N'287010213668', N'2026-11-09', N'W1238030', N'2032-06-29', 80.000, 100.000, N'DSG-LOAD', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (10, N'RAND', NULL, N'2046', 0, N'Reshma', N'Sasi Sasi', N'Govindan', N'ريشما ساسي ساسي جوفيندان', N'F', N'1995-02-23', N'Indian', N'295022304639', N'2026-11-14', N'C4836648', N'2034-11-18', 300.000, NULL, N'DSG-ACC', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (11, N'RAND', NULL, N'2047', 0, N'Akram', N'Radwan Abdelhafiz', N'Ghazal', N'أكرم رضوان عبدالحفيظ غزال', N'M', N'1965-08-22', N'Syrian', N'265082200631', NULL, NULL, NULL, 350.000, NULL, N'DSG-FINADM', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (12, N'RAND', N'FH', N'1003', 0, N'Ramadan', N'El-Sayed Morsi', N'Gad El-Rabb', N'رمضان السيد مرسي جاد الرب', N'M', N'1989-06-12', N'Egyptian', N'289061207662', N'2027-06-28', N'A31476473', N'2029-09-11', 270.000, 150.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (13, N'FH', NULL, N'1102', 1, N'Nassar', N'Ahmed Mohammed Yusuf', N'Jani', N'نصار أحمد محمد يوسف جاني', N'M', N'2005-06-03', NULL, N'305060301849', N'2026-12-15', N'AM360485', N'2036-03-02', 75.000, 75.000, N'DSG-ASTCOOK', N'فلافل حماده للمأكولات الخفيفة', N'medical examination'),
    (14, N'FH', NULL, N'1005', 0, N'Abdul Ghaffar', N'Sayed Abdul Majeed', N'El-Ghayaty', N'عبدالغفار سعيد عبدالحميد الفرماوي', N'M', N'1981-02-10', N'Egyptian', N'281021016961', N'2026-12-14', N'A33583628', N'2030-04-04', 250.000, 150.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', NULL),
    (15, N'FH', NULL, N'1006', 0, N'Muhammad', N'Ramadan Abdul Qawi', N'Ahmed', N'محمد رمضان عبدالقوي أحمد', N'M', N'1987-07-28', N'Egyptian', N'287072807162', N'2026-12-14', N'A31244216', N'2029-08-15', 220.000, 150.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', NULL),
    (16, N'FH', NULL, N'1019', 0, N'Arsat', N'Jonathan', N'Philemon', N'ارساث جونايدين فاليل', N'M', N'1992-11-22', N'Filipino', N'292112206107', N'2027-05-03', N'N10202901', N'2033-01-12', 110.000, 120.000, N'DSG-DRVBIKE', N'فلافل حماده للمأكولات الخفيفة', NULL),
    (17, N'FH', NULL, N'1027', 0, N'Nasrullah', N'Rashid Masood', N'Al-Ghul', N'نصرالله رشيد محمود الغول', N'M', N'1999-11-25', N'Jordanian', N'299112503007', N'2027-05-03', N'5027009', N'2028-09-23', 270.000, 150.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', NULL),
    (18, N'FH', NULL, N'1030', 0, N'Yazan', N'Imad Salim', N'Al-Rawaosheh', N'يزن عماد سالم الرواشده', N'M', N'1993-08-04', N'Jordanian', N'293080403492', N'2026-12-14', N'Q858775', N'2027-04-05', 220.000, 250.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', N'travelling'),
    (19, N'FH', NULL, N'1031', 0, N'Ahmed', N'Khaled Abdul Rahman', N'Barakat', N'أحمد خالد عبدالرحمن بركات', N'M', N'1992-08-31', N'Egyptian', N'292083105728', N'2026-11-19', N'50705168', N'2029-10-12', 220.000, 220.000, N'DSG-CASHIER', N'فلافل حماده للمأكولات الخفيفة', N'two-month extension'),
    (20, N'FH', NULL, N'1032', 0, N'Muhammad', N'Abdul Sattar Ayoub', N'Abdul Rahman', N'محمد عبدالستار ايوب عبدالرحمن', N'M', N'1994-09-17', N'Pakistani', N'294091705124', NULL, NULL, NULL, 220.000, NULL, N'DSG-STORE', N'فلافل حماده للمأكولات الخفيفة', N'external labour (عمالة خارجية)'),
    (21, N'RAND', NULL, N'2101', 1, N'Samiul', N'Haque ASM Tariqul', N'Haque', N'سميع الحق ايه اس ام طارق الحق', N'M', N'1993-07-04', NULL, N'293070400626', N'2026-12-25', N'A15847058', N'2034-05-25', 1500.000, 1500.000, N'DSG-CLERK', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (22, N'FH', NULL, N'1037', 0, N'Ammar', N'Abdul Ghani', N'Salloum', N'عمار عبدالغني سلوم', N'M', N'1983-02-15', N'Syrian', N'283021514601', N'2027-08-25', N'N02358782', N'2031-05-12', 220.000, 120.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', N'waiting for the civil ID card'),
    (23, N'FH', NULL, N'1038', 0, N'Hussein', N'Ahmed Faraj', N'Allaw', N'حسين أحمد فرج علاو', N'M', N'1997-11-10', N'Lebanese', N'297111005787', N'2027-08-29', N'N01008509', N'2030-03-03', 190.000, 120.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', N'waiting for the civil ID card'),
    (24, N'FH', NULL, N'1039', 0, N'Abdullah', N'Ali', N'Hariq', N'عبدالله علي حريق', N'M', N'1999-01-01', N'Yemeni', N'299010177271', N'2027-08-29', N'N03524802', N'2031-08-19', 180.000, 120.000, N'DSG-FFPREP', N'فلافل حماده للمأكولات الخفيفة', N'waiting for the civil ID card'),
    (25, N'RAND', NULL, N'2102', 1, N'Khalil', N'Al-Sadiq Al-Bashir', N'Abdullah', N'خليل الصادق البشير عبدالله', N'M', N'1982-01-28', NULL, N'282012810295', N'2026-12-14', N'P11924019', N'2034-04-29', 200.000, 200.000, N'DSG-DRVCAR', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (26, N'RAND', N'FH', N'2008', 0, N'Muhammad', N'Shaujan Hasen', N'Miah', N'محمد شوجان حسين ميا', N'M', N'1986-08-16', N'Bangladeshi', N'286081607088', N'2027-06-03', N'EK0785150', N'2027-08-09', 130.000, 75.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (27, N'RAND', N'FH', N'2012', 0, N'Sahajan', N'Wamaindol', N'Haq', N'ساهاجان وبعيدول حق', N'M', N'1980-07-11', N'Bangladeshi', N'280071106143', N'2026-11-09', N'EK0783793', N'2027-08-09', 130.000, 75.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (28, N'RAND', N'FH', N'2027', 0, N'Mostafa', N'Salimo', N'Kampino', N'مصطفى ساليسو كاميسو', N'M', N'1986-09-22', N'Indian', N'286092209675', N'2026-11-09', N'B01341652', N'2027-11-06', 120.000, 100.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (29, N'RAND', NULL, N'2103', 1, N'Fida', N'Hussain', N'Dudihai', N'فدا حسين دوديهاي', N'M', N'1977-09-01', N'Indian', N'277090100719', N'2027-03-23', N'U0611894', N'2030-04-27', 450.000, 450.000, N'DSG-SALESREP', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (30, N'RAND', N'FH', N'2030', 0, N'Muhammad', N'Jahangir', N'Hossain M.D.', N'محمد جهانجير حسين ام دي', N'M', N'1987-04-03', N'Bangladeshi', N'287040306363', N'2027-06-03', N'B00480773', N'2032-07-13', 130.000, 75.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (31, N'RAND', NULL, N'2104', 1, N'Suresh', N'Mamkuzhyil', N'Thomas', N'سوريش مامكوزهيل توماس', N'M', N'1964-05-30', NULL, N'264053002439', N'2027-07-12', N'Z5642564', N'2031-12-25', 1000.000, 1000.000, N'DSG-ITTECH', N'شركة راند للتجارة العامة والمقاولات', N'external labour (عمالة خارجية)'),
    (32, N'RAND', N'FH', N'2032', 0, N'Jamaluddin', N'Amedy', N'Watilotte', N'جمال ودين أمدي وظيولله', N'M', N'1981-08-22', N'Indian', N'281082206582', N'2027-06-03', N'A04063420', N'2027-05-16', 130.000, 75.000, N'DSG-FFPREP', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (33, N'FH', NULL, N'2033', 0, N'Faisal', N'Zaghloul Khalil', N'Ahmed', N'فيصل زغلول خليل أحمد', N'M', N'1978-01-04', N'Egyptian', N'278010402413', N'2027-06-03', N'A29797691', N'2029-01-30', 220.000, 200.000, N'DSG-ASTCOOK', N'فلافل حماده للمأكولات الخفيفة', NULL),
    (34, N'RAND', N'FH', N'2044', 0, N'Ahmed', N'Abdul Rasul Al-Dawwi', N'Muhammad', N'أحمد عبدالرسول الضوى محمد', N'M', N'1993-04-29', N'Egyptian', N'293042903939', N'2027-07-26', N'A37169751', N'2031-03-13', 220.000, 150.000, N'DSG-CASHIER', N'شركة راند للتجارة العامة والمقاولات', N'عدم الموظف / passport with the employee'),
    (35, N'RAND', N'FH', N'2045', 0, N'Omran', N'Salman Abdul Majeed', N'Salman', N'عمران سالمان عبدالمجيد سلمان', N'M', N'1990-07-12', N'Iraqi', N'290071203559', N'2027-08-27', N'A33485476', N'2030-04-12', 250.000, 90.000, N'DSG-DRVTRUCK', N'شركة راند للتجارة العامة والمقاولات', NULL),
    (36, N'4MG', NULL, N'4001', 1, N'Ibrahim', N'Bhai Mufaddal Bhai', N'Vahora', N'إبراهيم بهاي مفضل بهاي فاهورا', N'M', N'2000-01-30', NULL, N'300130201883', N'2026-11-09', N'56141272', N'2028-08-16', 600.000, 600.000, N'DSG-SALESREP', N'فور أم ديجيتال لأعمال الطباعة', N'passport with the employee'),
    (37, N'4MG', NULL, N'4002', 1, N'Omar', N'Anbasha Sheikh Amir Basha', N'Sheikh', N'عمر انباشا شيخ امير باشا شيخ', N'M', N'1996-06-16', NULL, N'296061202357', N'2027-06-06', N'X2871589', N'2034-02-26', 150.000, 150.000, N'DSG-ROLLOP', N'فور أم ديجيتال لأعمال الطباعة', NULL),
    (38, N'4MG', NULL, N'4003', 1, N'Mohammad', N'Ribon Hussain MD', N'Abul Kalam', N'محمد ريبون حسين ام دي ابوالكلام', N'M', N'1990-01-01', NULL, N'290010158408', N'2027-08-12', N'EK0998366', N'2027-10-15', 100.000, 100.000, N'DSG-ROLLOP', N'فور أم ديجيتال لأعمال الطباعة', N'passport with the employee'),
    (39, N'4MG', NULL, N'4004', 1, N'Shabbir', N'Mulla Ahmed', N'Ali', N'شبير مولا أحمد علي', N'M', N'1971-06-16', NULL, N'271061601832', N'2027-08-05', N'V5156799', N'2032-02-13', 100.000, 100.000, N'DSG-ROLLOP', N'فور أم ديجيتال لأعمال الطباعة', NULL),
    (40, N'4MG', NULL, N'4005', 1, N'Fatima', N'Aizar', N'Vohra', N'فاطمة اييزار فوهرا', N'F', N'1973-06-28', NULL, N'273062805385', N'2027-03-30', N'S2572819', N'2028-05-10', 75.000, 75.000, N'DSG-MSGR', N'فور أم ديجيتال لأعمال الطباعة', NULL),
    (41, N'4MG', NULL, N'4006', 1, N'Shahrukh', N'Khan Sarfaraz', N'Khan', N'شاهروخ خان سارفارازخان', N'M', N'1991-09-03', NULL, N'291090303963', N'2027-05-09', N'B6041894', N'2033-12-20', 75.000, 75.000, N'DSG-ROLLOP', N'فور أم ديجيتال لأعمال الطباعة', NULL),
    (42, N'BURUJ', NULL, N'5001', 1, N'Yusuf', N'Abdulwahid', N'Bait Sayyah', N'يوسف عبدالواحد بيت سياح', N'M', N'1982-05-05', NULL, N'282050501047', N'2027-02-07', N'T97674210', N'2029-05-12', 250.000, 250.000, N'DSG-SALESREP', N'بروج وكيل بالعمولة والتجار بالعمولة', N'absent (تغيب)'),
    (43, N'BURUJ', NULL, N'5002', 1, N'Hussam', N'Ali', N'Tamizkar', N'حسام علي تميزكار', N'M', N'1985-07-17', NULL, N'285071701746', N'2027-03-31', N'B97468027', N'2028-05-17', 800.000, 800.000, N'DSG-CLERK', N'بروج وكيل بالعمولة والتجار بالعمولة', N'passport with the employee'),
    (44, N'BURUJ', NULL, N'5003', 1, N'Abdul Zahra', N'Hassan', N'Haidari', N'عبد الزهرا حسن حيدري', N'M', N'1956-01-02', NULL, N'256010204575', N'2027-03-31', N'F97807320', N'2030-02-09', 350.000, 350.000, N'DSG-CLEAR', N'بروج وكيل بالعمولة والتجار بالعمولة', NULL),
    (45, N'ZAFIR', NULL, N'6001', 1, N'Haider', N'Ali', N'Tamizkar', N'حيدر علي تميزكار', N'M', N'1983-04-11', NULL, N'283041101214', N'2027-05-09', N'B97467559', N'2028-04-29', 1250.000, 1250.000, N'DSG-JEWEL', N'زفير للبيع بالتجزئة للساعات بأنواعها والمجوهرات والمصوغات', NULL),
    (46, N'ZAFIR', NULL, N'6002', 1, N'Hussain', N'Ali', N'Tamizkar', N'حسين علي تميزكار', N'M', N'1980-08-16', NULL, N'280081601447', N'2027-05-09', N'B97467907', N'2028-05-13', 800.000, 800.000, N'DSG-JEWEL', N'زفير للبيع بالتجزئة للساعات بأنواعها والمجوهرات والمصوغات', NULL),
    (47, N'IGM', NULL, N'3001', 1, N'Saji', N'Thomas', N'Joseph', N'ساجي توماس جوزيف', N'M', N'1971-01-13', NULL, N'271011301188', N'2027-07-25', N'Z3829126', N'2027-10-23', 1700.000, 1700.000, N'DSG-ELECPNL', N'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها', NULL),
    (48, N'IGM', NULL, N'3002', 1, N'Mohammad', N'Chand Mohammad', N'Ismail', N'محمد شاند محمد إسماعيل', N'M', N'1993-01-01', NULL, N'293010162814', N'2026-11-11', N'Y4502510', N'2034-09-28', 100.000, 100.000, N'DSG-ELECGEN', N'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها', N'three-month limit (تحديد 3 أشهر)'),
    (49, N'IGM', NULL, N'3003', 1, N'Adel', N'Mohammad Taha', N'Hamada', N'عادل محمد طه حماده', N'M', N'1977-11-28', NULL, N'277112806756', N'2026-12-12', N'U0742182', N'2031-06-17', 150.000, 150.000, N'DSG-WHWORK', N'أي جي أم كمبيوتر للأجهزة والأنظمة الأمنية وتركيبها وصيانتها', N'medical examination');

/* =====================================================================
   Loading
   ===================================================================== */
DECLARE @Now DATETIME2(0) = SYSUTCDATETIME();
DECLARE @KuwaitId INT = (SELECT TOP (1) CountryId FROM [Core].[Countries]
                         WHERE CountryCode IN (N'KW', N'KWT') OR CountryName LIKE N'Kuwait%'
                         ORDER BY CASE WHEN CountryCode IN (N'KW', N'KWT') THEN 0 ELSE 1 END);
DECLARE @KwdId INT = (SELECT TOP (1) CurrencyId FROM [Core].[Currencies] WHERE CurrencyCode = N'KWD');

/* nationalities: reuse by ISO code or name, add the missing ones (outside the
   transaction - if Core.Countries has other required columns the employee's
   nationality is just left blank) */
BEGIN TRY
    INSERT INTO [Core].[Countries] (CountryCode, CountryName, IsActive)
    SELECT m.CountryCode, m.CountryName, 1
    FROM   @CountryMap AS m
    WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Countries] AS c
                       WHERE c.CountryCode = m.CountryCode OR c.CountryName = m.CountryName OR c.CountryName LIKE m.CountryName + N'%');
END TRY
BEGIN CATCH
    PRINT N'NOTE: could not add missing countries (' + ERROR_MESSAGE() + N') - nationality left blank for those employees.';
END CATCH;
UPDATE m
   SET CountryId = (SELECT TOP (1) c.CountryId FROM [Core].[Countries] AS c
                    WHERE c.CountryCode = m.CountryCode OR c.CountryName = m.CountryName OR c.CountryName LIKE m.CountryName + N'%'
                    ORDER BY CASE WHEN c.CountryCode = m.CountryCode THEN 0 WHEN c.CountryName = m.CountryName THEN 1 ELSE 2 END)
FROM @CountryMap AS m;

SET XACT_ABORT ON;
BEGIN TRY
BEGIN TRANSACTION;

/* ---------------------------------------------------------------------
   1. Companies (+ a default monthly payroll calendar, pay components,
      leave types - the app's own seed procedures)
   --------------------------------------------------------------------- */
INSERT INTO [Core].[Companies] (CompanyCode, CompanyName, LegalName, CountryId, DefaultCurrencyId, IsActive)
SELECT c.Code, c.NameEn, c.LegalAr, @KuwaitId, @KwdId, 1
FROM   @Company AS c
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Companies] AS x WHERE x.CompanyCode = c.Code AND x.Deleted = 0);
DECLARE @CompaniesAdded INT = @@ROWCOUNT;

UPDATE x SET CompanyName = c.NameEn, LegalName = c.LegalAr
FROM   [Core].[Companies] AS x
JOIN   @Company AS c ON c.Code = x.CompanyCode
WHERE  x.Deleted = 0;

UPDATE c SET CompanyId = x.CompanyId
FROM   @Company AS c
JOIN   [Core].[Companies] AS x ON x.CompanyCode = c.Code AND x.Deleted = 0;

INSERT INTO [Payroll].[PayrollCalendars]
    (CompanyId, CalendarCode, CalendarName, ArabicName, PayFrequency, FirstPeriodStartDate, CutOffDay, PaymentDay,
     PaymentMonthOffset, WorkingDaysBasis, FixedDaysPerMonth, CurrencyId, Description, IsDefault, IsActive, CreatedBy)
SELECT c.CompanyId, N'MONTHLY', N'Monthly Payroll', N'الرواتب الشهرية', 'MONTHLY',
       DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1), 31, 31, 0, 'FIXED', 26, @KwdId,
       N'Added by the data import (db/92) - check the cut-off and payment day.', 1, 1, @UserId
FROM   @Company AS c
WHERE  NOT EXISTS (SELECT 1 FROM [Payroll].[PayrollCalendars] AS k WHERE k.CompanyId = c.CompanyId AND k.Deleted = 0);

DECLARE @cid INT;
DECLARE cc CURSOR LOCAL FAST_FORWARD FOR SELECT CompanyId FROM @Company;
OPEN cc; FETCH NEXT FROM cc INTO @cid;
WHILE @@FETCH_STATUS = 0
BEGIN
    IF OBJECT_ID(N'[Payroll].[usp_PayComponent_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Payroll].[usp_PayComponent_SeedDefaults] @CompanyId = @cid, @UserId = @UserId;
    IF OBJECT_ID(N'[Leave].[usp_LeaveType_SeedDefaults]', N'P') IS NOT NULL
        EXEC [Leave].[usp_LeaveType_SeedDefaults] @CompanyId = @cid, @UserId = @UserId;
    FETCH NEXT FROM cc INTO @cid;
END;
CLOSE cc; DEALLOCATE cc;

/* ---------------------------------------------------------------------
   2. Issuing authorities and company document types
   --------------------------------------------------------------------- */
INSERT INTO [Documents].[IssuingAuthorities] (AuthorityName, ArabicName, ShortName, IsGovernment, SortOrder)
SELECT a.AuthorityName, a.ArabicName, a.ShortName, 1, 30 + a.n
FROM  (VALUES (N'National Fund for SME Development', N'الصندوق الوطني لرعاية وتنمية المشروعات الصغيرة والمتوسطة', N'NFSMED', 1),
              (N'General Traffic Department (Ministry of Interior)', N'الإدارة العامة للمرور - وزارة الداخلية', N'GTD', 2),
              (N'Central Agency for Public Tenders', N'الجهاز المركزي للمناقصات العامة', N'CAPT', 3)) AS a (AuthorityName, ArabicName, ShortName, n)
WHERE NOT EXISTS (SELECT 1 FROM [Documents].[IssuingAuthorities] AS x
                  WHERE x.Deleted = 0 AND (x.ShortName = a.ShortName OR x.AuthorityName = a.AuthorityName));

DECLARE @PrivateAuthority INT = (SELECT TOP (1) IssuingAuthorityId FROM [Documents].[IssuingAuthorities]
                                 WHERE IsGovernment = 0 AND Deleted = 0 ORDER BY IssuingAuthorityId);

INSERT INTO [Documents].[OrganizationDocumentTypes]
    (TypeName, ArabicName, Category, IsMandatory, HasNumber, HasIssueDate, HasExpiryDate, AlertRules, SortOrder, IsActive, CreatedBy)
SELECT t.TypeName, t.ArabicName, t.Category, 0, 1, 1, 1, 'M2,M1,W2,D0',
       (SELECT ISNULL(MAX(SortOrder), 0) FROM [Documents].[OrganizationDocumentTypes] WHERE Deleted = 0)
           + ROW_NUMBER() OVER (ORDER BY t.TypeName), 1, @UserId
FROM   @TypeDef AS t
WHERE  NOT EXISTS (SELECT 1 FROM [Documents].[OrganizationDocumentTypes] AS x WHERE x.TypeName = t.TypeName AND x.Deleted = 0);

UPDATE x
   SET IssuingAuthorityId = COALESCE(a.IssuingAuthorityId, @PrivateAuthority)
FROM   [Documents].[OrganizationDocumentTypes] AS x
JOIN   @TypeDef AS t ON t.TypeName = x.TypeName
LEFT JOIN [Documents].[IssuingAuthorities] AS a ON a.ShortName = t.AuthorityShort AND a.Deleted = 0
WHERE  x.Deleted = 0 AND x.IssuingAuthorityId IS NULL;

/* ---------------------------------------------------------------------
   3. Company documents (licences): the current one of each type
   --------------------------------------------------------------------- */
DECLARE @DocRows TABLE (Seq INT PRIMARY KEY, CompanyId INT, TypeId INT, CurrentId BIGINT NULL);
INSERT INTO @DocRows (Seq, CompanyId, TypeId, CurrentId)
SELECT d.Seq, c.CompanyId, x.OrgDocumentTypeId,
       (SELECT TOP (1) o.OrgDocumentId FROM [Documents].[OrganizationDocuments] AS o
        WHERE o.CompanyId = c.CompanyId AND o.OrgDocumentTypeId = x.OrgDocumentTypeId AND o.State = 'C' AND o.Deleted = 0)
FROM   @Doc AS d
JOIN   @Company AS c ON c.Code = d.CompanyCode
JOIN   @TypeDef AS t ON t.TypeKey = d.TypeKey
JOIN   [Documents].[OrganizationDocumentTypes] AS x ON x.TypeName = t.TypeName AND x.Deleted = 0;

UPDATE o
   SET DocumentNumber = d.DocNumber, IssuingAuthority = d.Authority, IssueDate = d.IssueDate, ExpiryDate = d.ExpiryDate,
       Notes = d.Notes, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Documents].[OrganizationDocuments] AS o
JOIN   @DocRows AS r ON r.CurrentId = o.OrgDocumentId
JOIN   @Doc AS d ON d.Seq = r.Seq;

INSERT INTO [Documents].[OrganizationDocuments]
    (CompanyId, OrgDocumentTypeId, State, DocumentNumber, IssuingAuthority, IssueDate, ExpiryDate, Notes, CreatedBy)
SELECT r.CompanyId, r.TypeId, 'C', d.DocNumber, d.Authority, d.IssueDate, d.ExpiryDate, d.Notes, @UserId
FROM   @DocRows AS r
JOIN   @Doc AS d ON d.Seq = r.Seq
WHERE  r.CurrentId IS NULL;

/* ---------------------------------------------------------------------
   4. Vehicles -> Assets (matched on company + plate)
   --------------------------------------------------------------------- */
IF NOT EXISTS (SELECT 1 FROM [Assets].[AssetTypes] WHERE TypeName = N'Trucks & Pickups' AND Deleted = 0)
    INSERT INTO [Assets].[AssetTypes] (TypeName, ArabicName, Icon, HasExpiryDate, ExpiryLabel, ExpiryLabelAr, AlertRules, SortOrder, IsActive, CreatedBy)
    VALUES (N'Trucks & Pickups', N'شاحنات ونصف نقل', 'CAR', 1, N'Registration (Daftar) expiry', N'انتهاء الدفتر (الترخيص)', 'M1,W2,W1,D0',
            (SELECT ISNULL(MAX(SortOrder), 0) + 1 FROM [Assets].[AssetTypes] WHERE Deleted = 0), 1, @UserId);

UPDATE a
   SET AssetTypeId = t.AssetTypeId, Brand = v.Brand, Model = v.Model, Color = v.Color, ExpiryDate = v.ExpiryDate,
       Notes = v.Notes, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Assets].[Assets] AS a
JOIN   @Company AS c ON c.CompanyId = a.CompanyId
JOIN   @Vehicle AS v ON v.CompanyCode = c.Code AND v.Plate = a.SerialNumber
JOIN   [Assets].[AssetTypes] AS t ON t.TypeName = v.TypeName AND t.Deleted = 0
WHERE  a.Deleted = 0;

INSERT INTO [Assets].[Assets] (CompanyId, AssetTypeId, AssetCode, Brand, Model, Color, SerialNumber, ExpiryDate, Notes, IsActive, CreatedBy)
SELECT c.CompanyId, t.AssetTypeId, N'VEH-' + REPLACE(v.Plate, N'/', N'-'), v.Brand, v.Model, v.Color, v.Plate, v.ExpiryDate, v.Notes, 1, @UserId
FROM   @Vehicle AS v
JOIN   @Company AS c ON c.Code = v.CompanyCode
JOIN   [Assets].[AssetTypes] AS t ON t.TypeName = v.TypeName AND t.Deleted = 0
WHERE  NOT EXISTS (SELECT 1 FROM [Assets].[Assets] AS a WHERE a.CompanyId = c.CompanyId AND a.SerialNumber = v.Plate AND a.Deleted = 0);

/* ---------------------------------------------------------------------
   5. Designations (per company) and the "works at" locations
   --------------------------------------------------------------------- */
INSERT INTO [Core].[Designations] (CompanyId, DesignationCode, DesignationName, ArabicName, GradeId, Description, IsActive, CreatedBy)
SELECT DISTINCT c.CompanyId, j.JobCode, j.NameEn, j.NameAr, NULL, N'Work permit job title (data import db/92).', 1, @UserId
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
JOIN   @Job AS j ON j.JobCode = i.JobCode
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Designations] AS d
                   WHERE d.CompanyId = c.CompanyId AND (d.DesignationCode = j.JobCode OR d.DesignationName = j.NameEn));

INSERT INTO [Core].[Locations] (CompanyId, BranchId, LocationCode, LocationName, LocationType, IsActive, CreatedBy)
SELECT DISTINCT c.CompanyId, NULL, N'LOC-' + w.Code, w.NameEn, N'Workplace', 1, @UserId
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
JOIN   @Company AS w ON w.Code = i.WorkplaceCode
WHERE  NOT EXISTS (SELECT 1 FROM [Core].[Locations] AS l WHERE l.CompanyId = c.CompanyId AND l.LocationCode = N'LOC-' + w.Code);

/* ---------------------------------------------------------------------
   6. Employees (matched on company + civil ID, else company + code)
   --------------------------------------------------------------------- */
DECLARE @Rows TABLE (Sl INT PRIMARY KEY, EmployeeId BIGINT NULL, CompanyId INT, CountryId INT, DesignationId INT, LocationId INT);
INSERT INTO @Rows (Sl, CompanyId, CountryId, DesignationId, LocationId, EmployeeId)
SELECT i.Sl, c.CompanyId, m.CountryId,
       (SELECT TOP (1) d.DesignationId FROM [Core].[Designations] AS d
        WHERE d.CompanyId = c.CompanyId AND d.DesignationCode = i.JobCode),
       (SELECT TOP (1) l.LocationId FROM [Core].[Locations] AS l
        WHERE l.CompanyId = c.CompanyId AND l.LocationCode = N'LOC-' + i.WorkplaceCode),
       COALESCE((SELECT TOP (1) e.EmployeeId FROM [Employee].[Employees] AS e
                 JOIN [Kuwait].[EmployeeCompliance] AS k ON k.EmployeeId = e.EmployeeId
                 WHERE e.CompanyId = c.CompanyId AND k.CivilIdNumber = i.CivilIdNumber),
                (SELECT TOP (1) e.EmployeeId FROM [Employee].[Employees] AS e
                 WHERE e.CompanyId = c.CompanyId AND e.EmployeeCode = i.EmployeeCode))
FROM   @Import AS i
JOIN   @Company AS c ON c.Code = i.CompanyCode
LEFT JOIN @CountryMap AS m ON m.Nationality = i.Nationality;

UPDATE e
   SET EmployeeCode = i.EmployeeCode, EmployeeNo = i.EmployeeCode,
       FirstName = i.FirstName, MiddleName = i.MiddleName, LastName = i.LastName, ArabicName = i.ArabicName,
       Gender = i.Gender, DateOfBirth = i.DateOfBirth, NationalityCountryId = r.CountryId,
       DesignationId = r.DesignationId, WorkLocationId = r.LocationId,
       ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Employee].[Employees] AS e
JOIN   @Rows AS r ON r.EmployeeId = e.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl;
DECLARE @EmployeesUpdated INT = @@ROWCOUNT;

INSERT INTO [Employee].[Employees]
    (EmployeeCode, EmployeeNo, FirstName, MiddleName, LastName, ArabicName, Gender, DateOfBirth, NationalityCountryId,
     CompanyId, DesignationId, WorkLocationId, EmploymentType, EmploymentStatus, FatherIsDeceased, IsDeleted, CreatedBy)
SELECT i.EmployeeCode, i.EmployeeCode, i.FirstName, i.MiddleName, i.LastName, i.ArabicName, i.Gender, i.DateOfBirth, r.CountryId,
       r.CompanyId, r.DesignationId, r.LocationId, N'Full-Time', N'Active', 0, 0, @UserId
FROM   @Import AS i
JOIN   @Rows AS r ON r.Sl = i.Sl
WHERE  r.EmployeeId IS NULL;
DECLARE @EmployeesAdded INT = @@ROWCOUNT;

UPDATE r SET EmployeeId = e.EmployeeId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
JOIN   [Employee].[Employees] AS e ON e.CompanyId = r.CompanyId AND e.EmployeeCode = i.EmployeeCode
WHERE  r.EmployeeId IS NULL;

/* Kuwait compliance (1:1) - only the columns the sheet carries */
UPDATE k
   SET CivilIdNumber = i.CivilIdNumber, CivilIdExpiryDate = i.CivilIdExpiry, ResidencyExpiryDate = i.CivilIdExpiry,
       PassportNumber = i.PassportNumber, PassportCountryId = r.CountryId, PassportExpiryDate = i.PassportExpiry,
       SponsorName = i.SponsorName, WorkPermitSalary = i.PermitSalary,
       WorkPermitDesignation = j.NameEn, WorkPermitDesignationAr = j.NameAr,
       ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Kuwait].[EmployeeCompliance] AS k
JOIN   @Rows AS r ON r.EmployeeId = k.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl
LEFT JOIN @Job AS j ON j.JobCode = i.JobCode;

INSERT INTO [Kuwait].[EmployeeCompliance]
    (EmployeeId, CivilIdNumber, CivilIdExpiryDate, ResidencyExpiryDate, PassportNumber, PassportCountryId, PassportExpiryDate,
     SponsorName, WorkPermitSalary, WorkPermitDesignation, WorkPermitDesignationAr, CreatedBy)
SELECT r.EmployeeId, i.CivilIdNumber, i.CivilIdExpiry, i.CivilIdExpiry, i.PassportNumber, r.CountryId, i.PassportExpiry,
       i.SponsorName, i.PermitSalary, j.NameEn, j.NameAr, @UserId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
LEFT JOIN @Job AS j ON j.JobCode = i.JobCode
WHERE  NOT EXISTS (SELECT 1 FROM [Kuwait].[EmployeeCompliance] AS k WHERE k.EmployeeId = r.EmployeeId);

/* payroll (1:1) - the contract basic salary; allowances and bank are not in the sheet */
UPDATE p SET BasicSalary = i.BasicSalary, ModifiedBy = @UserId, ModifiedDate = @Now
FROM   [Employee].[EmployeePayroll] AS p
JOIN   @Rows AS r ON r.EmployeeId = p.EmployeeId
JOIN   @Import AS i ON i.Sl = r.Sl;

INSERT INTO [Employee].[EmployeePayroll] (EmployeeId, BasicSalary, CreatedBy)
SELECT r.EmployeeId, i.BasicSalary, @UserId
FROM   @Rows AS r
JOIN   @Import AS i ON i.Sl = r.Sl
WHERE  NOT EXISTS (SELECT 1 FROM [Employee].[EmployeePayroll] AS p WHERE p.EmployeeId = r.EmployeeId);

COMMIT TRANSACTION;

/* =====================================================================
   What was loaded
   ===================================================================== */
PRINT CONCAT(N'Import finished: ', @CompaniesAdded, N' companies added, ', @EmployeesAdded, N' employees added, ',
             @EmployeesUpdated, N' updated.');

SELECT  c.Code AS Company, x.CompanyName, x.LegalName,
        (SELECT COUNT(1) FROM [Employee].[Employees] AS e WHERE e.CompanyId = c.CompanyId AND e.IsDeleted = 0) AS Employees,
        (SELECT COUNT(1) FROM [Documents].[OrganizationDocuments] AS o WHERE o.CompanyId = c.CompanyId AND o.Deleted = 0 AND o.State = 'C') AS Documents,
        (SELECT COUNT(1) FROM [Assets].[Assets] AS a WHERE a.CompanyId = c.CompanyId AND a.Deleted = 0) AS Vehicles
FROM    @Company AS c
JOIN    [Core].[Companies] AS x ON x.CompanyId = c.CompanyId
ORDER BY c.Code;

SELECT  i.CompanyCode AS Company, i.EmployeeCode AS [New code (not in the sheet)], i.FirstName + N' ' + ISNULL(i.LastName, N'') AS Employee
FROM    @Import AS i WHERE i.CodeGenerated = 1 ORDER BY i.CompanyCode, i.EmployeeCode;

SELECT  i.CompanyCode AS Company, i.EmployeeCode AS Code, i.FirstName + N' ' + ISNULL(i.LastName, N'') AS Employee,
        i.SheetNotes AS [Sheet notes]
FROM    @Import AS i
WHERE   i.SheetNotes IS NOT NULL
ORDER BY i.CompanyCode, i.EmployeeCode;

END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    DECLARE @Err NVARCHAR(2000) = CONCAT(N'Import rolled back - nothing was saved. ', ERROR_MESSAGE(), N' (line ', ERROR_LINE(), N')');
    RAISERROR (@Err, 16, 1);
END CATCH;
GO
